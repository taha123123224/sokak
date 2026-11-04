// SOKAK: Operasyon — match relay (Cloudflare Workers + Durable Objects, free plan)
// One Durable Object per room code. Players connect with a WebSocket; every message is forwarded to
// the other players in the room (or to one player when it has a "to" field). The first player is the
// host (runs the match rules); if the host leaves, the oldest remaining player becomes the host.

import { WEAPONS } from "./weapons.js";

// ---- anti-cheat: every "hit" is checked against the real weapon table before it reaches the victim ----
const MAX_LVL_BONUS = 1.30;      // +7 upgrade = +28% damage, small margin
const STRIKES_TO_KICK = 6;

function hitLimit(w, head) {
  const wd = WEAPONS[w];
  if (!wd) return 0;
  return wd.dmg * (head ? wd.head : 1.0) * MAX_LVL_BONUS * (w === "frag" ? 1.0 : 1.0);
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const m = url.pathname.match(/^\/room\/([A-Za-z0-9_-]{3,24})$/);
    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response(JSON.stringify({ ok: true, service: "sokak-relay", version: 1 }), { headers: { "content-type": "application/json" } });
    }
    if (!m) return new Response("not found", { status: 404 });
    if (req.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    // ---- identity: the player must send a valid Supabase login token; id + name come from the server, not the client
    // local test only (wrangler dev --var DEV_NOAUTH:1): never set this variable on the real worker
    if (env.DEV_NOAUTH === "1") {
      const fwd0 = new URL(req.url);
      fwd0.searchParams.set("k", env.SUPABASE_KEY.slice(-12));
      return env.ROOMS.get(env.ROOMS.idFromName(m[1].toUpperCase())).fetch(new Request(fwd0.toString(), req));
    }
    const auth = req.headers.get("Authorization") || "";
    const tok = auth.startsWith("Bearer ") ? auth.slice(7) : (url.searchParams.get("tok") || "");
    if (!tok || tok.length > 4096) return new Response("Oyunu güncelle ve tekrar giriş yap", { status: 401 });
    const H = { apikey: env.SUPABASE_KEY, Authorization: "Bearer " + tok };
    let uid = "", name = "";
    try {
      const ur = await fetch(env.SUPABASE_URL + "/auth/v1/user", { headers: H });
      if (!ur.ok) return new Response("Oturum geçersiz, tekrar giriş yap", { status: 401 });
      uid = String((await ur.json()).id || "");
      const pr = await fetch(env.SUPABASE_URL + "/rest/v1/profiles?select=username,banned_until&id=eq." + encodeURIComponent(uid), { headers: H });
      const rows = pr.ok ? await pr.json() : [];
      if (!rows.length) return new Response("Profil bulunamadı", { status: 403 });
      const b = rows[0].banned_until;
      if (b && (b === "infinity" || Date.parse(b) > Date.now())) return new Response("Hesabın yasaklandı", { status: 403 });
      name = String(rows[0].username || "Oyuncu").slice(0, 20);
    } catch (e) {
      return new Response("Doğrulama sunucusuna ulaşılamadı", { status: 503 });
    }
    if (!uid) return new Response("Oturum geçersiz", { status: 401 });
    const fwd = new URL(req.url);
    fwd.search = "";
    fwd.searchParams.set("id", uid);
    fwd.searchParams.set("name", name);
    fwd.searchParams.set("k", env.SUPABASE_KEY.slice(-12));   // marks the request as coming through this worker
    const id = env.ROOMS.idFromName(m[1].toUpperCase());
    return env.ROOMS.get(id).fetch(new Request(fwd.toString(), req));
  },
};

const MAX_PLAYERS = 10;

export class Room {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.flood = new Map();   // socket -> {t, n}
    this.chatT = new Map();   // player id -> last chat ms
  }

  members() {
    return this.state.getWebSockets().map((ws) => ws.deserializeAttachment()).filter(Boolean)
      .sort((a, b) => a.joined - b.joined);
  }

  hostId() {
    const m = this.members();
    return m.length ? m[0].id : null;
  }

  send(ws, obj) {
    try { ws.send(typeof obj === "string" ? obj : JSON.stringify(obj)); } catch (e) {}
  }

  broadcast(obj, exceptWs = null) {
    const s = typeof obj === "string" ? obj : JSON.stringify(obj);
    for (const ws of this.state.getWebSockets()) if (ws !== exceptWs) this.send(ws, s);
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.searchParams.get("k") !== String(this.env.SUPABASE_KEY || "").slice(-12)) return new Response("forbidden", { status: 403 });
    const pid = (url.searchParams.get("id") || "").slice(0, 64);
    const name = (url.searchParams.get("name") || "Oyuncu").slice(0, 20);
    if (!pid) return new Response("missing id", { status: 400 });
    // same account reconnecting: drop the old socket
    for (const ws of this.state.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (a && a.id === pid) { try { ws.close(4000, "replaced"); } catch (e) {} }
    }
    if (this.members().length >= MAX_PLAYERS) return new Response("room full", { status: 403 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ id: pid, name, joined: Date.now() });
    const host = this.hostId();
    this.send(server, { t: "welcome", you: pid, host, members: this.members() });
    this.broadcast({ t: "joined", id: pid, name, host }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, msg) {
    const me = ws.deserializeAttachment();
    if (!me) return;
    // ---- flood guard: more than 90 messages in one second = disconnect
    const now = Date.now();
    const f = this.flood.get(ws) || { t: now, n: 0 };
    if (now - f.t > 1000) { f.t = now; f.n = 0; }
    f.n += 1;
    this.flood.set(ws, f);
    if (f.n > 90) { try { ws.close(4004, "flood"); } catch (e) {} return; }
    if (typeof msg !== "string") {
      // binary = voice only: 'V', id length, id, samples. The id inside must be the sender's own id.
      const b = new Uint8Array(msg);
      if (b.length < 3 || b.length > 4096 || b[0] !== 0x56) return;
      const l = b[1];
      if (b.length < 2 + l) return;
      const sid = new TextDecoder().decode(b.subarray(2, 2 + l));
      if (sid !== me.id) return;
      for (const o of this.state.getWebSockets()) if (o !== ws) { try { o.send(msg); } catch (e) {} }
      return;
    }
    if (msg.length > 16384) return;
    let data;
    try { data = JSON.parse(msg); } catch (e) { return; }
    if (!data || typeof data !== "object" || Array.isArray(data)) return;
    if (data.t === "ping") { this.send(ws, { t: "pong", ts: data.ts }); return; }
    data.from = me.id;
    // only the relay may send system messages; only the host may start / configure / end the match
    if (data.t === "sys" || data.t === "welcome" || data.t === "joined" || data.t === "left") return;
    if ((data.t === "start" || data.t === "cfg" || data.t === "end") && me.id !== this.hostId()) return;
    if (data.t === "chat") {
      const last = this.chatT.get(me.id) || 0;
      if (now - last < 600) return;                       // max ~1.6 messages / second
      this.chatT.set(me.id, now);
      data.n = me.name;                                   // real account name, can't be faked
      data.m = String(data.m || "").slice(0, 120);
      if (!data.m.trim()) return;
    }
    if (data.t === "hit") {
      const ok = this.checkHit(ws, me, data);
      if (!ok) return;
    }
    const out = JSON.stringify(data);
    if (data.to) {
      for (const o of this.state.getWebSockets()) {
        const a = o.deserializeAttachment();
        if (a && a.id === data.to) this.send(o, out);
      }
    } else {
      this.broadcast(out, ws);
    }
  }

  checkHit(ws, me, data) {
    const w = String(data.w || "");
    const dmg = Number(data.d);
    const lim = hitLimit(w, !!data.h);
    const now = Date.now();
    const wd = WEAPONS[w];
    let bad = !wd || !isFinite(dmg) || dmg < 0 || dmg > lim + 0.5;
    // rate: at most (rpm/60 * pellets) hits per second (+ slack), tracked per sender
    const st = this.rate || (this.rate = {});
    const r = st[me.id] || (st[me.id] = { t: now, n: 0, strikes: 0 });
    if (now - r.t > 1000) { r.t = now; r.n = 0; }
    r.n += 1;
    if (wd && r.n > Math.ceil((wd.rpm / 60) * wd.pel * 1.6) + 3) bad = true;
    if (!bad) return true;
    r.strikes += 1;
    if (r.strikes >= STRIKES_TO_KICK) {
      this.broadcast({ t: "sys", msg: me.name + " hile şüphesiyle odadan atıldı." }, ws);
      try { ws.close(4003, "hile"); } catch (e) {}
    }
    return false;
  }

  async webSocketClose(ws) { this.leave(ws); }
  async webSocketError(ws) { this.leave(ws); }

  leave(ws) {
    this.flood.delete(ws);
    const me = ws.deserializeAttachment();
    try { ws.close(); } catch (e) {}
    if (!me) return;
    ws.serializeAttachment(null);
    this.broadcast({ t: "left", id: me.id, host: this.hostId() });
  }
}
