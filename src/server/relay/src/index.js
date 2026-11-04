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
    const id = env.ROOMS.idFromName(m[1].toUpperCase());
    return env.ROOMS.get(id).fetch(req);
  },
};

const MAX_PLAYERS = 10;

export class Room {
  constructor(state, env) {
    this.state = state;
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
    if (typeof msg !== "string") {
      // binary state packets: forward unchanged to everyone else (sender id is inside the packet)
      for (const o of this.state.getWebSockets()) if (o !== ws) { try { o.send(msg); } catch (e) {} }
      return;
    }
    let data;
    try { data = JSON.parse(msg); } catch (e) { return; }
    if (data.t === "ping") { this.send(ws, { t: "pong", ts: data.ts }); return; }
    data.from = me.id;
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
    const me = ws.deserializeAttachment();
    try { ws.close(); } catch (e) {}
    if (!me) return;
    ws.serializeAttachment(null);
    this.broadcast({ t: "left", id: me.id, host: this.hostId() });
  }
}
