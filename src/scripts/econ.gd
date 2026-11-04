extends RefCounted
## Economy rules (prices, crates, upgrades, match rewards, missions, loadout validation).
## The SAME rules run on the server (server/supabase/v2_guvenlik.sql, function sokak_act) for online
## accounts: there the client never writes economy fields, it only asks the server to perform an action.
## Offline play (bot mode without an account) uses this file on the local profile.

const SET_COUNT := 5
const CHANCES := [80, 62, 48, 35, 25, 16, 10]          # success % for +1 .. +7
const FAIL_DROP_FROM := 5                                # failing at +5 or higher drops one level
const FEATURED := ["m249", "aug", "vector", "scar"]      # weekly offer: first one not owned, -20%
const PACKS := [["Demir Paketi", "demir", 50, 600], ["Krom Paketi", "krom", 25, 900], ["Titanyum Paketi", "titanyum", 10, 1500], ["Kobalt Paketi", "kobalt", 5, 2500], ["Kasa Anahtarı", "crate", 1, 1000]]
const MATS := ["demir", "krom", "titanyum", "kobalt"]
const STARTER := ["ak47", "mp5", "glock", "knife", "frag"]
const FREE_CHARS := ["takim", "deri", "asker1"]

static func default_profile_base() -> Dictionary:
	var owned := {}
	for w in STARTER:
		owned[w] = {"lvl": 0, "skins": ["std"], "skin": "std"}
	var sets := []
	for i in SET_COUNT:
		sets.append({"ana": "ak47" if i != 1 else "mp5", "tabanca": "glock", "bicak": "knife", "bomba": "frag"})
	return {"level": 1, "xp": 0, "gold": 7500, "mats": {"demir": 150, "krom": 50, "titanyum": 15, "kobalt": 5},
		"owned": owned, "sets": sets, "active_set": 0, "chars": FREE_CHARS.duplicate(), "char": "",
		"stats": {"kills": 0, "deaths": 0, "matches": 0, "wins": 0, "headshots": 0, "shots": 0, "hits": 0},
		"missions": {"kills": 0, "head": 0, "matches": 0, "wins": 0, "claimed": {}},
		"crates": 1, "crates2": {}, "parts": {}, "wparts": {}}

static func xp_for_level(l: int) -> int:
	return int(1200 * pow(l, 1.35))

static func upgrade_cost(lvl: int) -> Dictionary:
	return {
		"gold": 400 * (lvl + 1), "demir": 18 * (lvl + 1), "krom": 10 * lvl if lvl >= 1 else 0,
		"titanyum": 5 * (lvl - 2) if lvl >= 3 else 0, "kobalt": 4 * (lvl - 4) if lvl >= 5 else 0,
		"chance": CHANCES[lvl] if lvl < CHANCES.size() else 0,
	}

static func _err(t: String) -> Dictionary:
	return {"ok": false, "err": t, "res": {}}

static func _ok(res: Dictionary = {}) -> Dictionary:
	return {"ok": true, "err": "", "res": res}

static func _gold(p: Dictionary) -> int:
	return int(p.get("gold", 0))

static func _pay_gold(p: Dictionary, n: int) -> bool:
	if _gold(p) < n or n < 0:
		return false
	p["gold"] = _gold(p) - n
	return true

static func _owned(p: Dictionary, w: String) -> bool:
	return (p.get("owned", {}) as Dictionary).has(w)

static func _add_xp(p: Dictionary, amount: int) -> int:
	var ups := 0
	p["xp"] = int(p.get("xp", 0)) + amount
	while int(p["xp"]) >= xp_for_level(int(p["level"])):
		p["xp"] = int(p["xp"]) - xp_for_level(int(p["level"]))
		p["level"] = int(p["level"]) + 1
		ups += 1
		p["gold"] = _gold(p) + 500
		p["crates"] = int(p.get("crates", 0)) + 1
	return ups

## Perform one action on profile p (mutated in place). cat = catalog dictionary (see catalog()).
static func act(p: Dictionary, cat: Dictionary, a: String, args: Dictionary, now: float) -> Dictionary:
	match a:
		"buy_weapon":
			var id := str(args.get("id", ""))
			var wd: Dictionary = cat["weapons"].get(id, {})
			if wd.is_empty() or wd["throwable"] or int(wd["price"]) <= 0:
				return _err("Bu silah satılmıyor")
			if _owned(p, id):
				return _err("Bu silaha zaten sahipsin")
			var price := int(wd["price"])
			var feat := ""
			for f in cat["featured"]:
				if not _owned(p, f):
					feat = f; break
			if id == feat:
				price = int(price * 0.8)
			if not _pay_gold(p, price):
				return _err("Yetersiz altın!")
			p["owned"][id] = {"lvl": 0, "skins": ["std"], "skin": "std"}
			return _ok({"id": id, "price": price})
		"buy_skin":
			var wid := str(args.get("wid", ""))
			var sk := str(args.get("skin", ""))
			if not _owned(p, wid) or not cat["skins"].has(sk) or sk == "std":
				return _err("Geçersiz stil")
			var have: Array = p["owned"][wid].get("skins", ["std"])
			if have.has(sk):
				return _err("Bu stile zaten sahipsin")
			if not _pay_gold(p, int(cat["skins"][sk]["price"])):
				return _err("Yetersiz altın!")
			have.append(sk)
			p["owned"][wid]["skins"] = have
			p["owned"][wid]["skin"] = sk
			return _ok()
		"buy_part":
			var pid := str(args.get("id", ""))
			if not cat["parts"].has(pid):
				return _err("Geçersiz eklenti")
			if not _pay_gold(p, int(cat["parts"][pid]["price"])):
				return _err("Yetersiz altın!")
			var pp: Dictionary = p.get("parts", {})
			pp[pid] = int(pp.get(pid, 0)) + 1
			p["parts"] = pp
			return _ok()
		"buy_char":
			var c := str(args.get("id", ""))
			if not cat["chars"].has(c):
				return _err("Geçersiz karakter")
			var own: Array = p.get("chars", FREE_CHARS.duplicate())
			if own.has(c) or int(cat["chars"][c]["price"]) == 0:
				return _err("Bu karaktere zaten sahipsin")
			if not _pay_gold(p, int(cat["chars"][c]["price"])):
				return _err("Yetersiz altın!")
			own.append(c)
			p["chars"] = own
			p["char"] = c
			return _ok()
		"buy_crate":
			var t := str(args.get("id", ""))
			if not cat["crates"].has(t):
				return _err("Geçersiz kasa")
			if not _pay_gold(p, int(cat["crates"][t]["price"])):
				return _err("Yetersiz altın!")
			_crate_add(p, t, 1)
			return _ok()
		"buy_pack":
			var i := int(args.get("i", -1))
			if i < 0 or i >= cat["packs"].size():
				return _err("Geçersiz paket")
			var pk: Array = cat["packs"][i]
			if not _pay_gold(p, int(pk[3])):
				return _err("Yetersiz altın!")
			if pk[1] == "crate":
				_crate_add(p, "sokak", int(pk[2]))
			else:
				p["mats"][pk[1]] = int(p["mats"].get(pk[1], 0)) + int(pk[2])
			return _ok()
		"open_crate":
			var t := str(args.get("id", ""))
			if not cat["crates"].has(t):
				return _err("Geçersiz kasa")
			if _crate_count(p, t) > 0:
				_crate_add(p, t, -1)
			elif not _pay_gold(p, int(cat["crates"][t]["price"])):
				return _err("Yetersiz altın!")
			var it := _roll(p, cat, t)
			_grant(p, cat, it)
			return _ok(it)
		"upgrade":
			var wid := str(args.get("wid", ""))
			if not _owned(p, wid) or cat["weapons"].get(wid, {}).get("throwable", false):
				return _err("Geçersiz silah")
			var lvl := int(p["owned"][wid].get("lvl", 0))
			if lvl >= CHANCES.size():
				return _err("Silah en yüksek seviyede")
			var cost := upgrade_cost(lvl)
			if _gold(p) < int(cost["gold"]):
				return _err("Yetersiz altın!")
			for m in MATS:
				if int(p["mats"].get(m, 0)) < int(cost[m]):
					return _err("Yetersiz malzeme!")
			p["gold"] = _gold(p) - int(cost["gold"])
			for m in MATS:
				p["mats"][m] = int(p["mats"].get(m, 0)) - int(cost[m])
			var ok := randi_range(1, 100) <= int(cost["chance"])
			var nl := lvl + 1 if ok else (lvl - 1 if lvl >= FAIL_DROP_FROM else lvl)
			p["owned"][wid]["lvl"] = nl
			return _ok({"success": ok, "lvl": nl, "prev": lvl})
		"claim_mission":
			var mid := str(args.get("id", ""))
			for ms in cat["missions"]:
				if ms["id"] == mid:
					var mm: Dictionary = p["missions"]
					if mm["claimed"].has(mid):
						return _err("Ödül zaten alındı")
					if int(mm.get(ms["key"], 0)) < int(ms["goal"]):
						return _err("Görev henüz tamamlanmadı")
					for k in ms["reward"].keys():
						if k == "gold":
							p["gold"] = _gold(p) + int(ms["reward"][k])
						else:
							p["mats"][k] = int(p["mats"].get(k, 0)) + int(ms["reward"][k])
					mm["claimed"][mid] = true
					return _ok()
			return _err("Görev bulunamadı")
		"match_start":
			p["_t0"] = now
			return _ok()
		"match_end":
			return _match_end(p, args, now)
		"sync":
			_sync(p, cat, args)
			return _ok()
		"reset":
			var keep_name := str(p.get("name", ""))
			var d := default_profile_base()
			p.clear()
			p.merge(d)
			p["name"] = keep_name
			return _ok()
	return _err("Bilinmeyen işlem")

static func _crate_count(p: Dictionary, t: String) -> int:
	if t == "sokak":
		return int(p.get("crates", 0))
	return int(p.get("crates2", {}).get(t, 0))

static func _crate_add(p: Dictionary, t: String, n: int) -> void:
	if t == "sokak":
		p["crates"] = maxi(0, int(p.get("crates", 0)) + n)
	else:
		var d: Dictionary = p.get("crates2", {})
		d[t] = maxi(0, int(d.get(t, 0)) + n)
		p["crates2"] = d

static func _roll(p: Dictionary, cat: Dictionary, t: String) -> Dictionary:
	var cd: Dictionary = cat["crates"][t]
	var r := randf()
	var epic_min: bool = t == "efsane"
	if not epic_min and r < (0.3 if t == "sokak" else 0.18):
		var m: String = ["demir", "demir", "krom", "titanyum", "kobalt"][randi() % 5]
		return {"type": "mat", "id": m, "n": {"demir": 40, "krom": 20, "titanyum": 8, "kobalt": 3}[m]}
	if not epic_min and r < (0.5 if t == "sokak" else 0.3):
		return {"type": "gold", "n": [500, 800, 1200, 2500][randi() % 4]}
	var parts: Array = cd.get("parts", [])
	if parts.size() > 0 and randf() < (0.85 if t == "eklenti" else 0.12):
		return {"type": "part", "id": parts[randi() % parts.size()]}
	var ws: Array = cd.get("weapons", [])
	if ws.size() > 0 and randf() < 0.10:
		return {"type": "weapon", "id": ws[randi() % ws.size()]}
	var chs: Array = cd.get("chars", [])
	if chs.size() > 0 and randf() < 0.06:
		return {"type": "char", "id": chs[randi() % chs.size()]}
	var owned_ids: Array = []
	for id in p["owned"].keys():
		if cat["weapons"].has(id) and not cat["weapons"][id]["throwable"]:
			owned_ids.append(id)
	var wid: String = owned_ids[randi() % owned_ids.size()] if owned_ids.size() > 0 else "ak47"
	var pool: Array = (cd["skins"] as Array).duplicate()
	var tot := 0.0
	var weights: Array = []
	for sk in pool:
		var rr: int = int(cat["skins"].get(sk, {"rarity": 0})["rarity"])
		var wgt: float = [10.0, 5.0, 2.0, 0.5][rr] if not epic_min else [0.0, 0.0, 4.0, 1.2][rr]
		weights.append(wgt); tot += wgt
	var pick := randf() * maxf(tot, 0.001)
	var sk2: String = pool[0] if pool.size() > 0 else "kamuflaj"
	for i in pool.size():
		pick -= weights[i]
		if pick <= 0:
			sk2 = pool[i]; break
	return {"type": "skin", "wid": wid, "id": sk2}

static func _grant(p: Dictionary, cat: Dictionary, it: Dictionary) -> void:
	match it["type"]:
		"part":
			var pp: Dictionary = p.get("parts", {})
			pp[it["id"]] = int(pp.get(it["id"], 0)) + 1
			p["parts"] = pp
		"mat":
			p["mats"][it["id"]] = int(p["mats"].get(it["id"], 0)) + int(it["n"])
		"gold":
			p["gold"] = _gold(p) + int(it["n"])
		"skin":
			var sk: Array = p["owned"][it["wid"]]["skins"] if _owned(p, it["wid"]) else []
			if _owned(p, it["wid"]) and not sk.has(it["id"]):
				sk.append(it["id"])
			else:
				it["dup"] = int(cat["skins"][it["id"]]["price"]) / 2
				p["gold"] = _gold(p) + int(it["dup"])
		"weapon":
			if _owned(p, it["id"]):
				it["dup"] = int(cat["weapons"][it["id"]]["price"]) / 2
				p["gold"] = _gold(p) + int(it["dup"])
			else:
				p["owned"][it["id"]] = {"lvl": 0, "skin": "std", "skins": ["std"]}
		"char":
			var own: Array = p.get("chars", FREE_CHARS.duplicate())
			if own.has(it["id"]):
				it["dup"] = 1500
				p["gold"] = _gold(p) + 1500
			else:
				own.append(it["id"])
				p["chars"] = own

static func _match_end(p: Dictionary, s: Dictionary, now: float) -> Dictionary:
	## rewards are computed here from a capped summary; real elapsed time since match_start bounds everything
	var t0 := float(p.get("_t0", 0.0))
	p.erase("_t0")
	var secs := clampf(now - t0, 0.0, 1800.0) if t0 > 0.0 else 0.0
	var kills := clampi(int(s.get("kills", 0)), 0, mini(50, int(secs / 6.0)))
	var head := clampi(int(s.get("head", 0)), 0, kills)
	var deaths := clampi(int(s.get("deaths", 0)), 0, 200)
	var won := bool(s.get("won", false)) and secs >= 60.0
	var place := clampi(int(s.get("place", 10)), 1, 20)
	var shots := clampi(int(s.get("shots", 0)), 0, int(secs * 15.0))
	var hits := clampi(int(s.get("hits", 0)), 0, shots)
	var full := secs >= 45.0
	var xp: int = (200 + kills * 100 + head * 50 + (600 if won else 0) + maxi(0, 4 - place) * 100) if full else kills * 50
	var gold: int = (150 + kills * 45 + (400 if won else 0)) if full else kills * 20
	var mats := {"demir": (randi_range(6, 14) + kills) if full else 0, "krom": randi_range(2, 6) if full and randf() < 0.75 else 0,
		"titanyum": randi_range(1, 3) if full and randf() < 0.35 + (0.2 if won else 0.0) else 0, "kobalt": 1 if full and randf() < 0.12 + (0.1 if won else 0.0) else 0}
	var ups := _add_xp(p, xp)
	p["gold"] = _gold(p) + gold
	for m in mats.keys():
		p["mats"][m] = int(p["mats"].get(m, 0)) + int(mats[m])
	var st: Dictionary = p["stats"]
	st["kills"] = int(st["kills"]) + kills
	st["headshots"] = int(st["headshots"]) + head
	st["deaths"] = int(st["deaths"]) + deaths
	st["shots"] = int(st.get("shots", 0)) + shots
	st["hits"] = int(st.get("hits", 0)) + hits
	var ms: Dictionary = p["missions"]
	ms["kills"] = int(ms.get("kills", 0)) + kills
	ms["head"] = int(ms.get("head", 0)) + head
	if full:
		st["matches"] = int(st["matches"]) + 1
		ms["matches"] = int(ms.get("matches", 0)) + 1
	if won:
		st["wins"] = int(st["wins"]) + 1
		ms["wins"] = int(ms.get("wins", 0)) + 1
	return _ok({"xp": xp, "gold": gold, "mats": mats, "ups": ups, "won": won})

static func _sync(p: Dictionary, cat: Dictionary, s: Dictionary) -> void:
	## cosmetic / loadout fields proposed by the client; every value is checked against ownership
	if s.get("sets") is Array:
		var sets := []
		for i in mini((s["sets"] as Array).size(), SET_COUNT):
			var src = s["sets"][i]
			var cur: Dictionary = (p["sets"][i] if i < (p["sets"] as Array).size() else {}).duplicate()
			if src is Dictionary:
				for slot in ["ana", "tabanca", "bicak", "bomba"]:
					var w := str(src.get(slot, ""))
					if _owned(p, w) and str(cat["weapons"].get(w, {}).get("cat", "")) == slot:
						cur[slot] = w
			sets.append(cur)
		while sets.size() < SET_COUNT:
			sets.append((p["sets"][0] as Dictionary).duplicate() if (p["sets"] as Array).size() > 0 else {})
		p["sets"] = sets
	if s.has("active_set"):
		p["active_set"] = clampi(int(s["active_set"]), 0, SET_COUNT - 1)
	if s.has("char"):
		var c := str(s["char"])
		if c == "" or (cat["chars"].has(c) and (int(cat["chars"][c]["price"]) == 0 or (p.get("chars", []) as Array).has(c))):
			p["char"] = c
	if s.get("skins") is Dictionary:
		for w in s["skins"].keys():
			if _owned(p, w):
				var sk := str(s["skins"][w])
				if (p["owned"][w].get("skins", ["std"]) as Array).has(sk):
					p["owned"][w]["skin"] = sk
	if s.get("wparts") is Dictionary:
		var wp := {}
		for w in s["wparts"].keys():
			if not _owned(p, w) or not (s["wparts"][w] is Array):
				continue
			var lst := []
			var slots := {}
			for pid in s["wparts"][w]:
				pid = str(pid)
				var pd: Dictionary = cat["parts"].get(pid, {})
				if pd.is_empty() or int(p.get("parts", {}).get(pid, 0)) <= 0 or not (pd["fits"] as Array).has(w) or slots.has(pd["slot"]):
					continue
				slots[pd["slot"]] = true
				lst.append(pid)
			if lst.size() > 0:
				wp[w] = lst
		p["wparts"] = wp
