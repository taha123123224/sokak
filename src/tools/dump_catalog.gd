extends RefCounted
## godot --headless --path . -- --shot=x --dumpcatalog  -> server/supabase/catalog.json
## Base game catalog (no mods) shared by the server economy functions and the client rules.
static func run() -> void:
	var g = load("res://scripts/gs.gd").new()
	var e = load("res://scripts/econ.gd")
	var w := {}
	for id in g.WEAPONS.keys():
		var d: Dictionary = g.WEAPONS[id]
		w[id] = {"price": int(d.get("price", 0)), "cat": str(d["cat"]), "throwable": bool(d.get("throwable", false)), "melee": bool(d.get("melee", false)),
			"dmg": float(d.get("dmg", 0)), "head": float(d.get("head", 1.0)), "pellets": int(d.get("pellets", 1)), "rpm": float(d.get("rpm", 60))}
	var sk := {}
	for id in g.SKINS.keys():
		sk[id] = {"price": int(g.SKINS[id]["price"]), "rarity": int(g.SKINS[id]["rarity"])}
	var parts := {}
	for pid in g.PARTS.keys():
		var fits := []
		for wid in g.WEAPONS.keys():
			if g.part_fits(pid, wid):
				fits.append(wid)
		parts[pid] = {"price": int(g.PARTS[pid]["price"]), "slot": str(g.PARTS[pid]["slot"]), "fits": fits}
	var cr := {}
	for id in g.CRATES.keys():
		var c: Dictionary = g.CRATES[id]
		cr[id] = {"price": int(c["price"]), "skins": c.get("skins", []), "weapons": c.get("weapons", []), "chars": c.get("chars", []), "parts": c.get("parts", [])}
	var ch := {}
	for id in g.CHARACTERS.keys():
		ch[id] = {"price": int(g.CHARACTERS[id]["price"])}
	var out := {"weapons": w, "skins": sk, "parts": parts, "crates": cr, "chars": ch, "missions": g.MISSIONS,
		"packs": e.PACKS, "featured": e.FEATURED, "chances": e.CHANCES, "max_lvl": e.CHANCES.size(), "sets": e.SET_COUNT,
		"default": e.default_profile_base()}
	var f := FileAccess.open("res://server/supabase/catalog.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	print("catalog ok: ", w.size(), " weapons, ", sk.size(), " skins")
	g.free()
