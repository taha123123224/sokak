extends Node
## Global state: game data, player profile, settings, input map.

signal profile_changed
signal settings_changed

const SAVE_PATH := "user://profile.json"
const SETTINGS_PATH := "user://settings.json"

# ---------------------------------------------------------------- weapon data
# dmg: body damage, rpm, mag, reserve, reload(s), spread(rad hip), ads_spread, move: extra spread when moving,
# recoil: vertical kick (rad), hrec: horizontal, auto, range, pellets, zoom (fov multiplier), speed (move multiplier)
var WEAPONS := {
	"ak47":   {"name": "AK-47", "cat": "ana", "cls": "Makinalı", "dmg": 33, "rpm": 600, "mag": 30, "reserve": 120, "reload": 2.4, "spread": 0.028, "ads_spread": 0.004, "move": 0.05, "recoil": 0.021, "hrec": 0.009, "auto": true, "range": 160.0, "speed": 0.96, "price": 0, "snd": "shot_ak", "zoom": 1.25, "head": 2.6},
	"m4a1":   {"name": "M4A1", "cat": "ana", "cls": "Makinalı", "dmg": 29, "rpm": 740, "mag": 30, "reserve": 120, "reload": 2.2, "spread": 0.024, "ads_spread": 0.003, "move": 0.045, "recoil": 0.016, "hrec": 0.007, "auto": true, "range": 160.0, "speed": 0.97, "price": 2600, "snd": "shot_m4", "zoom": 1.35, "head": 2.5},
	"mp5":    {"name": "MP5", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 23, "rpm": 800, "mag": 30, "reserve": 150, "reload": 2.0, "spread": 0.026, "ads_spread": 0.006, "move": 0.02, "recoil": 0.011, "hrec": 0.006, "auto": true, "range": 90.0, "speed": 1.05, "price": 1500, "snd": "shot_smg", "zoom": 1.2, "head": 2.2},
	"p90":    {"name": "P90", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 21, "rpm": 900, "mag": 50, "reserve": 150, "reload": 2.6, "spread": 0.03, "ads_spread": 0.007, "move": 0.02, "recoil": 0.01, "hrec": 0.007, "auto": true, "range": 90.0, "speed": 1.05, "price": 3200, "snd": "shot_p90", "zoom": 1.25, "head": 2.2},
	"spas":   {"name": "SPAS-12", "cat": "ana", "cls": "Pompalı", "dmg": 16, "rpm": 70, "mag": 8, "reserve": 32, "reload": 0.55, "spread": 0.075, "ads_spread": 0.055, "move": 0.02, "recoil": 0.07, "hrec": 0.02, "auto": false, "range": 40.0, "pellets": 9, "speed": 0.98, "price": 2200, "snd": "shot_shotgun", "zoom": 1.15, "head": 1.6, "shell_reload": true},
	"awp":    {"name": "AWP", "cat": "ana", "cls": "Nişancı", "dmg": 120, "rpm": 40, "mag": 5, "reserve": 25, "reload": 3.4, "spread": 0.09, "ads_spread": 0.0003, "move": 0.12, "recoil": 0.08, "hrec": 0.01, "auto": false, "range": 400.0, "scope": true, "zoom": 5.0, "speed": 0.86, "price": 4750, "snd": "shot_sniper", "head": 3.0, "bolt": true},
	"kar98":  {"name": "Kar98", "cat": "ana", "cls": "Nişancı", "dmg": 105, "rpm": 48, "mag": 5, "reserve": 25, "reload": 3.0, "spread": 0.08, "ads_spread": 0.0005, "move": 0.1, "recoil": 0.07, "hrec": 0.01, "auto": false, "range": 400.0, "scope": true, "zoom": 4.0, "speed": 0.92, "price": 3500, "snd": "shot_kar", "head": 3.0, "bolt": true},
	"scar":   {"name": "SCAR-H", "cat": "ana", "cls": "Makinalı", "dmg": 38, "rpm": 560, "mag": 20, "reserve": 100, "reload": 2.5, "spread": 0.026, "ads_spread": 0.003, "move": 0.05, "recoil": 0.024, "hrec": 0.008, "auto": true, "range": 180.0, "speed": 0.95, "price": 5200, "snd": "shot_scar", "zoom": 1.35, "head": 2.6},
	"ump45":  {"name": "UMP-45", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 27, "rpm": 650, "mag": 25, "reserve": 125, "reload": 2.1, "spread": 0.027, "ads_spread": 0.006, "move": 0.02, "recoil": 0.013, "hrec": 0.006, "auto": true, "range": 85.0, "speed": 1.04, "price": 2400, "snd": "shot_ump", "zoom": 1.25, "head": 2.2},
	"aug":    {"name": "AUG A3", "cat": "ana", "cls": "Makinalı", "dmg": 31, "rpm": 700, "mag": 30, "reserve": 120, "reload": 2.6, "spread": 0.024, "ads_spread": 0.0022, "move": 0.045, "recoil": 0.017, "hrec": 0.006, "auto": true, "range": 180.0, "speed": 0.96, "price": 4400, "snd": "shot_m4", "zoom": 1.65, "head": 2.5},
	"vector": {"name": "Vector .45", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 19, "rpm": 1150, "mag": 25, "reserve": 150, "reload": 1.9, "spread": 0.028, "ads_spread": 0.007, "move": 0.018, "recoil": 0.009, "hrec": 0.008, "auto": true, "range": 70.0, "speed": 1.07, "price": 3800, "snd": "shot_ump", "zoom": 1.2, "head": 2.1},
	"m249":   {"name": "M249 SAW", "cat": "ana", "cls": "Ağır Makinalı", "dmg": 30, "rpm": 760, "mag": 100, "reserve": 200, "reload": 5.2, "spread": 0.034, "ads_spread": 0.008, "move": 0.08, "recoil": 0.02, "hrec": 0.011, "auto": true, "range": 170.0, "speed": 0.84, "price": 6200, "snd": "shot_scar", "zoom": 1.25, "head": 2.3},
	"revolver": {"name": "Magnum .357", "cat": "tabanca", "cls": "Tabanca", "dmg": 62, "rpm": 150, "mag": 6, "reserve": 36, "reload": 2.3, "spread": 0.02, "ads_spread": 0.003, "move": 0.04, "recoil": 0.06, "hrec": 0.012, "auto": false, "range": 120.0, "speed": 1.05, "price": 2600, "snd": "shot_revolver", "zoom": 1.25, "head": 2.7},
	"glock":  {"name": "Glock 17", "cat": "tabanca", "cls": "Tabanca", "dmg": 24, "rpm": 420, "mag": 17, "reserve": 68, "reload": 1.6, "spread": 0.02, "ads_spread": 0.006, "move": 0.015, "recoil": 0.02, "hrec": 0.006, "auto": false, "range": 80.0, "speed": 1.08, "price": 0, "snd": "shot_pistol", "zoom": 1.15, "head": 2.5},
	"deagle": {"name": "Deagle .50", "cat": "tabanca", "cls": "Tabanca", "dmg": 54, "rpm": 210, "mag": 7, "reserve": 35, "reload": 1.9, "spread": 0.022, "ads_spread": 0.004, "move": 0.04, "recoil": 0.055, "hrec": 0.012, "auto": false, "range": 120.0, "speed": 1.05, "price": 1800, "snd": "shot_deagle", "zoom": 1.2, "head": 2.6},
	"knife":  {"name": "Savaş Bıçağı", "cat": "bicak", "cls": "Bıçak", "dmg": 55, "rpm": 110, "melee": true, "speed": 1.15, "price": 0, "head": 1.0},
	"karambit": {"name": "Karambit", "cat": "bicak", "cls": "Bıçak", "dmg": 60, "rpm": 130, "melee": true, "speed": 1.17, "price": 2000, "head": 1.0},
	"frag":   {"name": "El Bombası MK3", "cat": "bomba", "cls": "Bomba", "dmg": 130, "count": 2, "throwable": true, "speed": 1.1, "price": 0, "head": 1.0},
}
const CATS := {"ana": "Ana Silah", "tabanca": "Tabanca", "bicak": "Bıçak", "bomba": "Bomba"}
const SLOT_ORDER := ["ana", "tabanca", "bicak", "bomba"]

var SKINS := {
	"std": {"name": "Standart", "price": 0, "rarity": 0},
	"kamuflaj": {"name": "Orman Kamuflaj", "price": 600, "rarity": 0},
	"kar": {"name": "Kış Operasyonu", "price": 800, "rarity": 1},
	"gece": {"name": "Gece Avcısı", "price": 1200, "rarity": 1},
	"neon": {"name": "Zehir Yeşili", "price": 1400, "rarity": 2},
	"kizil": {"name": "Kızıl Ejder", "price": 2200, "rarity": 2},
	"galaksi": {"name": "Galaksi", "price": 3500, "rarity": 3},
	"altin": {"name": "Altın Varak", "price": 5000, "rarity": 3},
	"dijital": {"name": "Şehir Dijital", "price": 700, "rarity": 0},
	"karbon": {"name": "Karbon Fiber", "price": 1500, "rarity": 1},
	"cini": {"name": "Osmanlı Çini", "price": 3000, "rarity": 2},
	"turkuaz": {"name": "Turkuaz Altın", "price": 3200, "rarity": 2},
	"buz": {"name": "Buz Kristali", "price": 4200, "rarity": 3},
	"lav": {"name": "Lav Akıntısı", "price": 4800, "rarity": 3},
}
var CRATES := {
	"sokak": {"name": "Sokak Kasası", "price": 1000, "color": Color("ff8a1f"), "desc": "Her şeyden biraz: malzeme, altın, stiller.",
		"skins": ["kamuflaj", "kar", "dijital", "gece", "neon", "kizil", "galaksi", "altin"], "weapons": [], "chars": []},
	"operasyon": {"name": "Operasyon Kasası", "price": 2000, "color": Color("4fb3ff"), "desc": "Taktik stiller ve yeni silah şansı (AUG, Vector, SCAR-H, UMP-45).",
		"skins": ["dijital", "karbon", "kar", "kamuflaj", "gece", "buz"], "weapons": ["aug", "vector", "scar", "ump45", "m4a1", "p90"], "chars": ["asker2", "asker3"]},
	"eklenti": {"name": "Eklenti Paketi", "price": 1500, "color": Color("7dff6a"), "desc": "Silah eklentileri: susturucu, nişangah, şarjör, tutamak, lazer.",
		"skins": ["karbon", "dijital"], "weapons": [], "chars": [], "parts": ["sus", "kompen", "optik", "sarjor", "tutamak", "lazer"]},
	"osmanli": {"name": "Osmanlı Kasası", "price": 2500, "color": Color("2fb6a8"), "desc": "Çini ve turkuaz desenler, Magnum ve Patron karakteri şansı.",
		"skins": ["cini", "turkuaz", "altin", "kizil", "neon"], "weapons": ["revolver", "deagle", "karambit"], "chars": ["patron", "kapson"]},
	"efsane": {"name": "Efsane Kasası", "price": 5000, "color": Color("ffb02e"), "desc": "En az Epik garantili! Lav, Buz, Galaksi, Altın.",
		"skins": ["lav", "buz", "galaksi", "altin", "cini", "turkuaz"], "weapons": ["awp", "scar", "m249"], "chars": ["kot", "patron", "asker2"], "parts": ["sus", "optik", "sarjor"]},
}
const RARITY_NAMES := ["Sıradan", "Nadir", "Epik", "Efsanevi"]
const RARITY_COLORS := [Color("9aa4ad"), Color("3b8cff"), Color("b04bff"), Color("ffb02e")]
## ballistics & unique abilities per weapon (applied on top of WEAPONS):
## ap = armour penetration (0..1), pen = wall thickness it can shoot through (m), f0/f1/fmin = damage falloff start/end/min factor,
## limb = arm/leg multiplier, abil = special mechanic, ability = shop text
const BALLISTICS := {
	"ak47":   {"ap": 0.5, "pen": 0.3, "f0": 25.0, "f1": 75.0, "fmin": 0.72, "limb": 0.8, "ability": "7.62 mermi: ince duvar ve kapıları deler"},
	"m4a1":   {"ap": 0.4, "pen": 0.2, "f0": 30.0, "f1": 85.0, "fmin": 0.74, "limb": 0.75, "ability": "En düşük sekme, isabetli uzun seri"},
	"scar":   {"ap": 0.75, "pen": 0.45, "f0": 35.0, "f1": 110.0, "fmin": 0.78, "limb": 0.85, "ability": "Ağır mermi: zırhı büyük ölçüde deler"},
	"aug":    {"ap": 0.45, "pen": 0.25, "f0": 40.0, "f1": 110.0, "fmin": 0.78, "limb": 0.75, "ability": "Entegre dürbün: uzak mesafede keskin nişan"},
	"m249":   {"ap": 0.5, "pen": 0.4, "f0": 30.0, "f1": 90.0, "fmin": 0.72, "limb": 0.8, "abil": "suppress", "ability": "100'lük şarjör: bastırma ateşi hedefin nişanını bozar"},
	"mp5":    {"ap": 0.2, "pen": 0.05, "f0": 14.0, "f1": 45.0, "fmin": 0.6, "limb": 0.8, "ability": "Hafif ve hızlı: en hızlı nişan alma"},
	"p90":    {"ap": 0.4, "pen": 0.12, "f0": 16.0, "f1": 50.0, "fmin": 0.62, "limb": 0.8, "ability": "50'lik şarjör, zırh delici 5.7 mm"},
	"ump45":  {"ap": 0.15, "pen": 0.05, "f0": 12.0, "f1": 40.0, "fmin": 0.62, "limb": 0.85, "abil": "slow", "ability": "Yavaşlatan .45 mermi: vurulan hedef yavaşlar"},
	"vector": {"ap": 0.1, "pen": 0.0, "f0": 10.0, "f1": 30.0, "fmin": 0.55, "limb": 0.85, "ability": "Dakikada 1150 atış: yakın mesafenin kralı"},
	"spas":   {"ap": 0.1, "pen": 0.0, "f0": 6.0, "f1": 22.0, "fmin": 0.22, "limb": 0.9, "ability": "Yakın mesafede tek atışta öldürür"},
	"awp":    {"ap": 0.95, "pen": 0.65, "f0": 400.0, "f1": 500.0, "fmin": 1.0, "limb": 0.85, "ability": "Gövdeden tek atış, duvar deler"},
	"kar98":  {"ap": 0.85, "pen": 0.5, "f0": 400.0, "f1": 500.0, "fmin": 1.0, "limb": 0.8, "ability": "Hızlı sürgü, kafadan kesin ölüm"},
	"glock":  {"ap": 0.1, "pen": 0.0, "f0": 12.0, "f1": 35.0, "fmin": 0.65, "limb": 0.8, "ability": "Işık hızında çekiş ve geniş şarjör"},
	"deagle": {"ap": 0.6, "pen": 0.2, "f0": 20.0, "f1": 60.0, "fmin": 0.7, "limb": 0.8, "ability": "Kafadan tek atış"},
	"revolver": {"ap": 0.55, "pen": 0.18, "f0": 22.0, "f1": 65.0, "fmin": 0.72, "limb": 0.85, "ability": "En güçlü tabanca, sert geri tepme"},
}

## weapon attachments (eklenti parçaları): dropped from crates, bought in the market, fitted in the bag
const PARTS := {
	"sus":     {"name": "Susturucu", "desc": "Sessiz atış, namlu alevi yok, haritada görünmezsin. Hasar -%6", "slot": "namlu", "price": 900, "pistol": true},
	"kompen":  {"name": "Kompansatör", "desc": "Dikey sekme -%22", "slot": "namlu", "price": 700, "pistol": true},
	"optik":   {"name": "Holografik Nişangah", "desc": "Nişanlı isabet +%30, yakınlaştırma +0.2", "slot": "optik", "price": 800, "pistol": false},
	"sarjor":  {"name": "Uzatılmış Şarjör", "desc": "Şarjör +%50, doldurma süresi +%12", "slot": "sarjor", "price": 1000, "pistol": true},
	"tutamak": {"name": "Ön Tutamak", "desc": "Sekme -%15, yatay sekme -%30", "slot": "alt", "price": 750, "pistol": false},
	"lazer":   {"name": "Taktik Lazer", "desc": "Belden atış isabeti +%25, hareket isabeti +%30", "slot": "alt", "price": 850, "pistol": true},
}
const PART_SLOTS := ["namlu", "optik", "sarjor", "alt"]

func ball(id: String) -> Dictionary:
	return BALLISTICS.get(id, {"ap": 0.2, "pen": 0.0, "f0": 20.0, "f1": 60.0, "fmin": 0.7, "limb": 0.8})

func wparts(id: String) -> Array:
	return profile.get("wparts", {}).get(id, [])

func part_fits(pid: String, wid: String) -> bool:
	var w: Dictionary = WEAPONS.get(wid, {})
	if w.get("melee", false) or w.get("throwable", false):
		return false
	if pid == "optik" and (w.get("scope", false) or wid in ["m4a1", "scar", "ump45", "vector", "m249", "aug"]):
		return false   # these already have an optic
	if w.get("pellets", 0) > 0 and pid in ["sus", "optik"]:
		return false
	return w["cat"] == "ana" or bool(PARTS[pid]["pistol"])

func fit_part(wid: String, pid: String) -> void:
	## one part per slot; fitting a new one in the slot swaps it out
	if not profile.has("wparts"):
		profile["wparts"] = {}
	var cur: Array = (profile["wparts"].get(wid, []) as Array).duplicate()
	for q in cur.duplicate():
		if PARTS[q]["slot"] == PARTS[pid]["slot"]:
			cur.erase(q)
	if pid not in wparts(wid):
		cur.append(pid)
	profile["wparts"][wid] = cur
	save_profile()

func remove_part(wid: String, pid: String) -> void:
	var cur: Array = (profile.get("wparts", {}).get(wid, []) as Array).duplicate()
	cur.erase(pid)
	if not profile.has("wparts"):
		profile["wparts"] = {}
	profile["wparts"][wid] = cur
	save_profile()

func parts_owned(pid: String) -> int:
	return int(profile.get("parts", {}).get(pid, 0))

## final weapon stats: base + upgrade level + fitted attachments + ballistics
func full_stats(id: String, parts = null) -> Dictionary:
	var w: Dictionary = WEAPONS[id].duplicate()
	var st := stats_for(id)
	w["dmg"] = st["dmg"]; w["recoil"] = st["recoil"]; w["spread"] = st["spread"]; w["mag_max"] = st["mag"]
	w.merge(ball(id), true)
	var ps: Array = wparts(id) if parts == null else parts
	for pid in ps:
		match pid:
			"sus":
				w["dmg"] = int(round(float(w["dmg"]) * 0.94)); w["silenced"] = true
			"kompen":
				w["recoil"] = float(w["recoil"]) * 0.78
			"optik":
				w["ads_spread"] = float(w.get("ads_spread", 0.005)) * 0.7; w["zoom"] = float(w.get("zoom", 1.2)) + 0.2
			"sarjor":
				w["mag_max"] = int(ceil(float(w["mag_max"]) * 1.5)); w["reload"] = float(w["reload"]) * 1.12
			"tutamak":
				w["recoil"] = float(w["recoil"]) * 0.85; w["hrec"] = float(w.get("hrec", 0.006)) * 0.7
			"lazer":
				w["spread"] = float(w["spread"]) * 0.75; w["move"] = float(w.get("move", 0.03)) * 0.7
	return w

const LVL_GLOW_COLS := [Color(0, 0, 0), Color(0.3, 0.75, 1.0), Color(0.3, 0.75, 1.0), Color(0.65, 0.4, 1.0), Color(0.65, 0.4, 1.0), Color(1.0, 0.5, 0.15), Color(1.0, 0.5, 0.15), Color(1.0, 0.82, 0.3)]
var _glow_shader: Shader

func level_glow(gun: Node3D, id: String, strength: float = 1.0) -> void:
	## upgraded weapons carry a coloured energy rim (+1/2 blue, +3/4 purple, +5/6 orange, +7 gold) with a moving sweep
	var lvl := wlvl(id)
	if lvl <= 0 or gun == null:
		return
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float power = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	// thin rim only on silhouette edges (does not cover the skin pattern)
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	// a narrow diagonal glint passes over the weapon about every 3.5 s, then it rests
	float cyc = fract(TIME * 0.28);
	float lane = lp.z * 1.6 + lp.y * 1.2;
	float head = cyc * 3.4 - 1.7;
	float glint = (1.0 - smoothstep(0.0, 0.022, abs(lane - head))) * step(cyc, 0.55);
	float sparkle = pow(max(sin(lp.x * 140.0 + lp.z * 90.0 + TIME * 3.0), 0.0), 40.0) * 0.25;
	ALBEDO = col.rgb * (rim * 0.5 + glint * 0.8 + sparkle * rim) * power;
}"""

	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("col", LVL_GLOW_COLS[clamp(lvl, 0, 7)])
	m.set_shader_parameter("power", (0.5 + lvl * 0.08) * strength)
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m

func _att(pid: String) -> Node3D:
	var path := "res://assets/models/att_%s.glb" % pid
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	MatLib.apply(n, "std")
	return n

func parts_visual(gun: Node3D, id: String, parts = null) -> void:
	## real modelled attachments (tools/attachments.py) mounted on the weapon's markers
	var ps: Array = wparts(id) if parts == null else parts
	if ps.is_empty() or gun == null:
		return
	var mz := gun.find_child("muzzle", true, false) as Node3D
	var sg := gun.find_child("sight", true, false) as Node3D
	var lh := gun.find_child("lhand", true, false) as Node3D
	var mg := gun.find_child("mag", true, false) as Node3D
	var pistol: bool = WEAPONS[id]["cat"] == "tabanca"
	for pid in ps:
		match pid:
			"sus", "kompen":
				if mz:
					var a := _att(pid)
					if a == null: continue
					mz.get_parent().add_child(a)
					a.position = mz.position + Vector3(0, 0, 0.004)
					if pistol:
						a.scale = Vector3(0.8, 0.8, 0.72) if pid == "sus" else Vector3(0.8, 0.8, 0.8)
					var tip := a.find_child("muzzle", true, false) as Node3D
					if tip:
						mz.position = a.position + tip.position * a.scale
			"optik":
				if sg:
					var a := _att("optik")
					if a == null: continue
					sg.get_parent().add_child(a)
					a.position = sg.position + Vector3(0, -0.02, 0.025)
					var win := a.find_child("sight", true, false) as Node3D
					if win:
						sg.position = a.position + win.position   # aiming now looks through the holo window
			"sarjor":
				if mg:
					mg.scale = Vector3(1.04, 1.38, 1.04)
			"tutamak":
				if lh:
					var a := _att("tutamak")
					if a == null: continue
					lh.get_parent().add_child(a)
					a.position = lh.position + Vector3(0, -0.026, 0.01)
			"lazer":
				if lh:
					var a := _att("lazer")
					if a == null: continue
					lh.get_parent().add_child(a)
					a.position = lh.position + Vector3(0.012 if not pistol else 0.0, -0.004 if not pistol else -0.03, -0.05 if not pistol else -0.02)

const MATS := {"demir": "Demir", "krom": "Krom", "titanyum": "Titanyum", "kobalt": "Kobalt"}
const MAX_LVL := 7

var MAPS := {
	"mahalle": {"name": "Eski Mahalle", "desc": "İstanbul ara sokakları, dükkanlar ve çay bahçesi. Yakın-orta mesafe.", "size": "Orta"},
	"safranbolu": {"name": "Safranbolu", "desc": "Osmanlı konakları, Arasta çarşısı ve teraslar. Çok katmanlı çatışma.", "size": "Büyük"},
	"gemi": {"name": "Gemi", "desc": "Gün batımında Marmara'da yük gemisi. Konteyner koridorları.", "size": "Orta"},
	"liman": {"name": "Liman Deposu", "desc": "Sisli sabah, konteyner sahası ve depo. Nişancı dostu.", "size": "Büyük"},
}
var MODES := {
	"ffa": {"name": "Ölüm Maçı", "desc": "Herkes herkese karşı. En çok öldüren kazanır.", "teams": false},
	"tdm": {"name": "Takım Ölüm Maçı", "desc": "KARTAL vs AKREP. Takım skoru hedefe ulaşınca biter.", "teams": true},
	"gungame": {"name": "Silah Oyunu", "desc": "Her öldürmede silahın değişir. Son silah bıçak!", "teams": false},
	"knife": {"name": "Bıçak Arenası", "desc": "Sadece bıçak ve el bombası. Saf refleks.", "teams": false},
	"sniper": {"name": "Nişancı Düellosu", "desc": "Sadece keskin nişancı tüfekleri. Takımlı.", "teams": true},
}
const TEAMS := {"a": "KARTAL", "b": "AKREP"}
const TEAM_COLORS := {"a": Color("3d8bff"), "b": Color("ff4d3d")}
const GUNGAME_ORDER := ["glock", "deagle", "mp5", "p90", "spas", "m4a1", "ak47", "kar98", "awp", "knife"]

var CHARACTERS := {
	"takim": {"name": "Ajan", "desc": "Takım elbiseli şehir ajanı", "team": "a", "price": 0},
	"deri": {"name": "Sokak Reisi", "desc": "Deri ceketli mahalle lideri", "team": "a", "price": 0},
	"patron": {"name": "Patron", "desc": "Klasik takım, keskin bakış", "team": "a", "price": 4500},
	"kot": {"name": "Seyyah", "desc": "Kot ceketli hızlı tetikçi", "team": "a", "price": 3000},
	"kapson": {"name": "Gölge", "desc": "Kapüşonlu sessiz avcı", "team": "a", "price": 3500},
	"asker1": {"name": "Operatör", "desc": "Taktik yelekli özel kuvvet", "team": "b", "price": 0},
	"asker2": {"name": "Komando", "desc": "Ağır zırhlı saha komandosu", "team": "b", "price": 5000},
	"asker3": {"name": "Keşif Eri", "desc": "Hafif teçhizatlı keşif uzmanı", "team": "b", "price": 4000},
}

func team_chars(t: String) -> Array:
	var r := []
	for k in CHARACTERS.keys():
		if CHARACTERS[k]["team"] == t:
			r.append(k)
	return r

func cur_char() -> String:
	var c := str(profile.get("char", "takim"))
	return c if CHARACTERS.has(c) else "takim"

const BOT_NAMES := ["KaraKartal", "Tetikçi_34", "GeceKurdu", "Efsane06", "ŞahinBey", "Reis35", "Yıldırım", "Hayalet", "Kobra", "Pars_01",
	"Tilki", "Atmaca", "SessizAdım", "Kartal07", "DemirYumruk", "Çelik", "Fırtına", "Kurşun_44", "Akıncı", "Kasırga", "Gölge", "Turbo", "Kral_61", "Bora"]

const MISSIONS := [
	{"id": "k25", "text": "25 düşman indir", "key": "kills", "goal": 25, "reward": {"gold": 1500, "krom": 15}},
	{"id": "h10", "text": "10 kafadan vuruş yap", "key": "head", "goal": 10, "reward": {"gold": 1200, "titanyum": 6}},
	{"id": "m3", "text": "3 maç tamamla", "key": "matches", "goal": 3, "reward": {"gold": 1000, "kobalt": 3}},
	{"id": "w1", "text": "1 maç kazan", "key": "wins", "goal": 1, "reward": {"gold": 2000, "krom": 10}},
]

var profile: Dictionary = {}
var settings: Dictionary = {}
var room: Dictionary = {}       # current room config for match
var last_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings_raw()
	load_mods()
	load_profile()
	load_settings()
	setup_input()
	apply_settings()

# ---------------------------------------------------------------- profile
func default_profile() -> Dictionary:
	return {
		"name": "Oyuncu%d" % randi_range(100, 999), "level": 1, "xp": 0, "gold": 7500,
		"mats": {"demir": 150, "krom": 50, "titanyum": 15, "kobalt": 5},
		"owned": {
			"ak47": {"lvl": 0, "skins": ["std"], "skin": "std"},
			"mp5": {"lvl": 0, "skins": ["std"], "skin": "std"},
			"glock": {"lvl": 0, "skins": ["std"], "skin": "std"},
			"knife": {"lvl": 0, "skins": ["std"], "skin": "std"},
			"frag": {"lvl": 0, "skins": ["std"], "skin": "std"},
		},
		"sets": [
			{"ana": "ak47", "tabanca": "glock", "bicak": "knife", "bomba": "frag"},
			{"ana": "mp5", "tabanca": "glock", "bicak": "knife", "bomba": "frag"},
			{"ana": "ak47", "tabanca": "glock", "bicak": "knife", "bomba": "frag"},
		],
		"active_set": 0,
		"stats": {"kills": 0, "deaths": 0, "matches": 0, "wins": 0, "headshots": 0, "shots": 0, "hits": 0},
		"missions": {"kills": 0, "head": 0, "matches": 0, "wins": 0, "claimed": {}},
		"crates": 1,
	}

func load_profile() -> void:
	profile = default_profile()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d.keys():
				profile[k] = d[k]
	sanitize_profile()

func sanitize_profile() -> void:
	## fills missing keys and fixes types (used for local saves and for cloud saves from older versions)
	var base := default_profile()
	for k in base.keys():
		if not profile.has(k):
			profile[k] = base[k]
	# json numbers -> ints where needed
	profile["level"] = int(profile["level"]); profile["xp"] = int(profile["xp"]); profile["gold"] = int(profile["gold"])
	profile["active_set"] = int(profile["active_set"])
	# items from eklentiler that are not loaded right now are parked, not lost
	var dormant: Dictionary = profile.get("dormant", {})
	for w in dormant.keys():
		if WEAPONS.has(w):
			profile["owned"][w] = dormant[w]
			dormant.erase(w)
	for w in profile["owned"].keys():
		if not WEAPONS.has(w):
			dormant[w] = profile["owned"][w]
	for w in dormant.keys():
		profile["owned"].erase(w)
	profile["dormant"] = dormant
	for w in profile["owned"].keys():
		profile["owned"][w]["lvl"] = int(profile["owned"][w]["lvl"])
		var sks: Array = profile["owned"][w].get("skins", ["std"])
		profile["owned"][w]["skins"] = sks.filter(func(x): return SKINS.has(x))
		if not SKINS.has(str(profile["owned"][w].get("skin", "std"))):
			profile["owned"][w]["skin"] = "std"
	var defaults := {"ana": "ak47", "tabanca": "glock", "bicak": "knife", "bomba": "frag"}
	for st in profile["sets"]:
		for c in (st as Dictionary).keys():
			if not owned(str(st[c])):
				st[c] = defaults.get(c, "knife")
	if not CHARACTERS.has(str(profile.get("char", "takim"))):
		profile["char"] = "takim"

func save_profile(local_only: bool = false) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))
	if not local_only and has_node("/root/Online"):
		get_node("/root/Online").queue_save()   # cloud save (debounced)
	profile_changed.emit()

func owned(id: String) -> bool:
	return profile["owned"].has(id)

func wlvl(id: String) -> int:
	return int(profile["owned"][id]["lvl"]) if owned(id) else 0

func wskin(id: String) -> String:
	return str(profile["owned"][id]["skin"]) if owned(id) else "std"

func active_set() -> Dictionary:
	return profile["sets"][profile["active_set"]]

func xp_for_level(l: int) -> int:
	return int(1200 * pow(l, 1.35))

func add_xp(amount: int) -> int:
	var ups := 0
	profile["xp"] = int(profile["xp"]) + amount
	while profile["xp"] >= xp_for_level(profile["level"]):
		profile["xp"] -= xp_for_level(profile["level"])
		profile["level"] += 1
		ups += 1
		profile["gold"] += 500
		profile["crates"] = int(profile.get("crates", 0)) + 1
	return ups

func upgrade_cost(lvl: int) -> Dictionary:
	var chances := [100, 95, 85, 75, 60, 45, 35]
	return {
		"gold": 300 * (lvl + 1), "demir": 15 * (lvl + 1), "krom": 8 * lvl if lvl >= 1 else 0,
		"titanyum": 4 * (lvl - 2) if lvl >= 3 else 0, "kobalt": 3 * (lvl - 4) if lvl >= 5 else 0,
		"chance": chances[lvl] if lvl < chances.size() else 30,
	}

func can_afford(cost: Dictionary) -> bool:
	if profile["gold"] < cost.get("gold", 0):
		return false
	for m in MATS.keys():
		if int(profile["mats"].get(m, 0)) < int(cost.get(m, 0)):
			return false
	return true

func pay(cost: Dictionary) -> void:
	profile["gold"] -= int(cost.get("gold", 0))
	for m in MATS.keys():
		profile["mats"][m] = int(profile["mats"].get(m, 0)) - int(cost.get(m, 0))

func stats_for(id: String, lvl: int = -1) -> Dictionary:
	if lvl < 0:
		lvl = wlvl(id)
	var w: Dictionary = WEAPONS[id]
	var mag := int(w.get("mag", 0))
	if w["cat"] == "ana" and not w.get("scope", false) and mag >= 20:
		mag += lvl
	return {"dmg": int(round(w["dmg"] * (1.0 + 0.04 * lvl))), "recoil": float(w.get("recoil", 0.0)) * (1.0 - 0.03 * lvl), "mag": mag, "spread": float(w.get("spread", 0.0)) * (1.0 - 0.02 * lvl)}

# ---------------------------------------------------------------- settings
func default_settings() -> Dictionary:
	return {
		"sens": 1.0, "ads_sens": 0.8, "scope_sens": 0.6, "invert_y": false, "fov": 80.0,
		"quality": "ultra", "resolution_scale": 1.0, "upscaler": "fsr2", "fullscreen": true, "vsync": false, "fps_cap": 0,
		"msaa": 2, "taa": false, "fxaa": true, "shadows": 3, "ssao": true, "ssil": true, "ssr": true, "sdfgi": false, "glow": true, "volumetric": true,
		"motion_blur": false, "draw_distance": 1.0, "sharpen": 0.3, "brightness": 1.0, "show_fps": true, "announcer": true,
		"vol_master": 0.8, "vol_sfx": 1.0, "vol_music": 0.5, "vol_amb": 0.6,
		"xh_style": 0, "xh_color": "3dff8a", "xh_size": 7.0, "xh_gap": 5.0, "xh_thick": 2.0, "xh_dot": false, "xh_outline": true, "xh_dynamic": true, "xh_alpha": 1.0,
		"hit_marker": true, "kill_feed": true, "blood": true, "minimap": true, "damage_numbers": true,
		"binds": {},
	}

func load_settings() -> void:
	settings = default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d.keys():
				settings[k] = d[k]

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	apply_settings()
	settings_changed.emit()

const QUALITY_PRESETS := {
	"low": {"msaa": 0, "fxaa": true, "taa": false, "shadows": 0, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "glow": false, "volumetric": false, "resolution_scale": 0.75, "draw_distance": 0.6},
	"medium": {"msaa": 0, "fxaa": true, "taa": false, "shadows": 1, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "glow": true, "volumetric": false, "resolution_scale": 0.9, "draw_distance": 0.8},
	"high": {"msaa": 2, "fxaa": true, "taa": false, "shadows": 2, "ssao": true, "ssil": false, "ssr": true, "sdfgi": false, "glow": true, "volumetric": true, "resolution_scale": 1.0, "draw_distance": 1.0},
	"ultra": {"msaa": 4, "fxaa": true, "taa": false, "shadows": 3, "ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "glow": true, "volumetric": true, "resolution_scale": 1.0, "draw_distance": 1.0},
	"uhd": {"msaa": 4, "fxaa": true, "taa": false, "shadows": 4, "ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "glow": true, "volumetric": true, "resolution_scale": 1.0, "draw_distance": 1.3},
}

func apply_preset(name: String) -> void:
	settings["quality"] = name
	for k in QUALITY_PRESETS[name].keys():
		settings[k] = QUALITY_PRESETS[name][k]

func apply_settings() -> void:
	var win := get_window()
	if settings["fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings["fps_cap"])
	var vp := get_viewport()
	var ms := int(settings["msaa"])
	vp.msaa_3d = Viewport.MSAA_DISABLED if ms == 0 else (Viewport.MSAA_2X if ms == 2 else (Viewport.MSAA_4X if ms == 4 else Viewport.MSAA_8X))
	# SMAA keeps edges smooth without the blur of FXAA/TAA -> crisp image
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if settings["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(settings["taa"])
	vp.use_debanding = true
	var rs := float(settings["resolution_scale"])
	vp.scaling_3d_scale = rs
	if rs < 0.99:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if settings["upscaler"] == "fsr2" else Viewport.SCALING_3D_MODE_FSR
	else:
		# FSR 1 at 100% = pure RCAS sharpening pass (sharper textures, no upscaling)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(settings["sharpen"]) > 0.01 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = clamp(1.0 - float(settings["sharpen"]) * 1.6, 0.0, 2.0)
	vp.mesh_lod_threshold = 1.0 if float(settings["draw_distance"]) >= 1.0 else 2.0
	vp.use_occlusion_culling = true
	var sh := int(settings["shadows"])
	var sizes := [1024, 2048, 4096, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(sizes[clamp(sh, 0, 4)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][clamp(sh, 0, 4)])
	# audio buses
	_set_bus("Master", settings["vol_master"])
	_set_bus("SFX", settings["vol_sfx"])
	_set_bus("Music", settings["vol_music"])
	_set_bus("Amb", settings["vol_amb"])
	apply_binds()

func _set_bus(n: String, v: float) -> void:
	var i := AudioServer.get_bus_index(n)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, linear_to_db(max(float(v), 0.0001)))

# ---------------------------------------------------------------- input
const DEFAULT_BINDS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "crouch": [KEY_CTRL, KEY_C], "walk": [KEY_SHIFT], "reload": [KEY_R], "use": [KEY_E],
	"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3], "slot4": [KEY_4], "grenade": [KEY_G], "inspect": [KEY_F],
	"scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE], "chat": [KEY_T], "last_weapon": [KEY_Q], "buy_menu": [KEY_B],
}
const BIND_NAMES := {
	"move_forward": "İleri", "move_back": "Geri", "move_left": "Sol", "move_right": "Sağ", "jump": "Zıpla", "crouch": "Eğil",
	"walk": "Yürü (sessiz)", "reload": "Şarjör Değiştir", "use": "Kullan", "slot1": "Ana Silah", "slot2": "Tabanca", "slot3": "Bıçak",
	"slot4": "Bomba", "grenade": "Hızlı Bomba", "inspect": "Silahı İncele", "scoreboard": "Skor Tablosu", "last_weapon": "Son Silah", "buy_menu": "Silah Menüsü",
}

func setup_input() -> void:
	for a in DEFAULT_BINDS.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	for a in ["fire", "aim"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var mb := InputEventMouseButton.new(); mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_erase_events("fire"); InputMap.action_add_event("fire", mb)
	var mb2 := InputEventMouseButton.new(); mb2.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_erase_events("aim"); InputMap.action_add_event("aim", mb2)

func apply_binds() -> void:
	var b: Dictionary = settings.get("binds", {})
	for a in DEFAULT_BINDS.keys():
		InputMap.action_erase_events(a)
		var keys: Array = b.get(a, DEFAULT_BINDS[a])
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(a, ev)

func bind_label(a: String) -> String:
	var b: Dictionary = settings.get("binds", {})
	var keys: Array = b.get(a, DEFAULT_BINDS[a])
	var parts: Array = []
	for k in keys:
		parts.append(OS.get_keycode_string(int(k)))
	return " / ".join(parts)


# ================================================================ EKLENTİLER (mods)
## A mod is a folder with a mod.json, placed in  <oyun klasörü>/mods/  or  user://mods/ .
## It can add weapons (based on an existing model, or its own .glb), skins (png), characters (.glb),
## maps (.glb + .json) and crates. See mods/README.txt (written by the game) for the format.
var mods: Array = []                 # [{id, name, author, version, desc, dir, enabled, counts}]
var mod_weapon_model := {}           # weapon id -> {"base": id} or {"glb": abs path}
var mod_skin_tex := {}               # skin id -> abs png path (or "" for colour-only)
var mod_skin_col := {}
var mod_char_model := {}             # char id -> abs glb path
var mod_maps := {}                   # map id -> {"glb": path, "json": path}
var _ext_cache := {}

func mod_dirs() -> Array:
	var out: Array = []
	var exe_dir := OS.get_executable_path().get_base_dir()
	for root in [exe_dir.path_join("mods"), ProjectSettings.globalize_path("user://mods")]:
		if DirAccess.dir_exists_absolute(root):
			out.append(root)
	return out

func load_settings_raw() -> void:
	# settings are needed before mods (disabled list) -> lightweight early read
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if d is Dictionary:
			settings = d

func load_mods() -> void:
	mods.clear()
	var disabled: Array = settings.get("mods_disabled", [])
	for root in mod_dirs():
		var da := DirAccess.open(root)
		if da == null:
			continue
		for sub in da.get_directories():
			var dir: String = root.path_join(sub)
			var mf := dir.path_join("mod.json")
			if not FileAccess.file_exists(mf):
				continue
			var j = JSON.parse_string(FileAccess.get_file_as_string(mf))
			if not (j is Dictionary):
				push_warning("Eklenti okunamadı: " + mf)
				continue
			var mid := str(j.get("id", sub))
			var info := {"id": mid, "name": str(j.get("name", sub)), "author": str(j.get("author", "?")), "version": str(j.get("version", "1.0")),
				"desc": str(j.get("desc", "")), "dir": dir, "enabled": not disabled.has(mid), "counts": {}}
			mods.append(info)
			if info["enabled"]:
				_apply_mod(j, dir, info)

func _apply_mod(j: Dictionary, dir: String, info: Dictionary) -> void:
	var c := {"silah": 0, "stil": 0, "karakter": 0, "harita": 0, "kasa": 0}
	for wid in (j.get("weapons", {}) as Dictionary).keys():
		var wd: Dictionary = j["weapons"][wid]
		var base := str(wd.get("base", "ak47"))
		if not WEAPONS.has(base):
			continue
		var w: Dictionary = (WEAPONS[base] as Dictionary).duplicate(true)
		for k in wd.keys():
			if k != "base" and k != "model":
				w[k] = wd[k]
		WEAPONS[wid] = w
		if wd.has("model"):
			mod_weapon_model[wid] = {"glb": dir.path_join(str(wd["model"])), "base": base}
		else:
			mod_weapon_model[wid] = {"base": base}
		c["silah"] += 1
	for sk in (j.get("skins", {}) as Dictionary).keys():
		var sd: Dictionary = j["skins"][sk]
		SKINS[sk] = {"name": str(sd.get("name", sk)), "price": int(sd.get("price", 1000)), "rarity": clamp(int(sd.get("rarity", 1)), 0, 3)}
		mod_skin_tex[sk] = dir.path_join(str(sd["texture"])) if sd.has("texture") else ""
		mod_skin_col[sk] = Color.html(str(sd.get("color", "#ffffff")))
		c["stil"] += 1
	for ch in (j.get("characters", {}) as Dictionary).keys():
		var cd: Dictionary = j["characters"][ch]
		CHARACTERS[ch] = {"name": str(cd.get("name", ch)), "desc": str(cd.get("desc", "Eklenti karakteri")), "team": str(cd.get("team", "a")), "price": int(cd.get("price", 0))}
		if cd.has("model"):
			mod_char_model[ch] = dir.path_join(str(cd["model"]))
		elif cd.has("base"):
			mod_char_model[ch] = "base:" + str(cd["base"])
		c["karakter"] += 1
	for mp in (j.get("maps", {}) as Dictionary).keys():
		var md: Dictionary = j["maps"][mp]
		MAPS[mp] = {"name": str(md.get("name", mp)), "desc": str(md.get("desc", "Eklenti haritası")), "size": str(md.get("size", "Orta"))}
		mod_maps[mp] = {"glb": dir.path_join(str(md.get("glb", mp + ".glb"))), "json": dir.path_join(str(md.get("json", mp + ".json")))}
		c["harita"] += 1
	for cr in (j.get("crates", {}) as Dictionary).keys():
		var cd2: Dictionary = j["crates"][cr]
		CRATES[cr] = {"name": str(cd2.get("name", cr)), "price": int(cd2.get("price", 1500)), "color": Color.html(str(cd2.get("color", "#ff8a1f"))),
			"desc": str(cd2.get("desc", "")), "skins": cd2.get("skins", ["kamuflaj"]), "weapons": cd2.get("weapons", []), "chars": cd2.get("chars", [])}
		c["kasa"] += 1
	info["counts"] = c

func set_mod_enabled(mid: String, on: bool) -> void:
	var dis: Array = settings.get("mods_disabled", [])
	if on:
		dis.erase(mid)
	elif not dis.has(mid):
		dis.append(mid)
	settings["mods_disabled"] = dis
	save_settings()

func _load_ext_glb(path: String) -> PackedScene:
	if _ext_cache.has(path):
		return _ext_cache[path]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var ps: PackedScene = null
	if doc.append_from_file(path, st) == OK:
		var root := doc.generate_scene(st)
		if root:
			ps = PackedScene.new()
			_own(root, root)
			ps.pack(root)
			root.free()
	_ext_cache[path] = ps
	return ps

func _own(n: Node, owner_: Node) -> void:
	for c in n.get_children():
		c.owner = owner_
		_own(c, owner_)

## central asset resolution (base game + eklentiler)
func weapon_scene(id: String) -> PackedScene:
	var mm: Dictionary = mod_weapon_model.get(id, {})
	if mm.has("glb"):
		var ps := _load_ext_glb(mm["glb"])
		if ps:
			return ps
	var base: String = mm.get("base", id)
	return load("res://assets/models/w_%s.glb" % base)

func weapon_base(id: String) -> String:
	return str(mod_weapon_model.get(id, {}).get("base", id))

func char_scene(id: String) -> PackedScene:
	var p: String = mod_char_model.get(id, "")
	if p.begins_with("base:"):
		return load("res://assets/models/rb_%s.glb" % p.substr(5))
	if p != "":
		var ps := _load_ext_glb(p)
		if ps:
			return ps
	var path := "res://assets/models/rb_%s.glb" % id
	return load(path) if ResourceLoader.exists(path) else load("res://assets/models/rb_takim.glb")

func map_paths(id: String) -> Dictionary:
	if mod_maps.has(id):
		return mod_maps[id]
	return {"glb": "res://assets/maps/%s.glb" % id, "json": "res://assets/maps/%s.json" % id}

func map_scene(id: String) -> PackedScene:
	var p: String = map_paths(id)["glb"]
	if p.begins_with("res://"):
		return load(p)
	return _load_ext_glb(p)

func write_example_mod() -> String:
	## creates a ready-to-edit example eklenti in user://mods/ornek_paket
	var dir := ProjectSettings.globalize_path("user://mods/ornek_paket")
	DirAccess.make_dir_recursive_absolute(dir)
	var j := {
		"id": "ornek_paket", "name": "Örnek Eklenti Paketi", "author": "SOKAK", "version": "1.0",
		"desc": "Yeni silah, stil, karakter ve kasa ekleyen örnek eklenti. Düzenleyip kendi eklentini yap!",
		"weapons": {"ak_kizil": {"base": "ak47", "name": "AK-47 Kızıl Kurt", "dmg": 35, "rpm": 620, "price": 4000, "cls": "Makinalı"},
			"mp5_hiz": {"base": "mp5", "name": "MP5 Şimşek", "rpm": 900, "dmg": 21, "price": 3000}},
		"skins": {"pembe": {"name": "Pembe Panter", "price": 900, "rarity": 1, "color": "#ff5fb0"}},
		"characters": {"ajan2": {"base": "patron", "name": "Gizli Ajan", "team": "a", "price": 0, "desc": "Eklentiden gelen karakter"}},
		"crates": {"ornek": {"name": "Eklenti Kasası", "price": 1200, "color": "#ff5fb0", "desc": "Örnek eklenti kasası", "skins": ["pembe", "kamuflaj", "kizil"], "weapons": ["ak_kizil", "mp5_hiz"], "chars": ["ajan2"]}}
	}
	var f := FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(j, "\t"))
	f.close()
	var r := FileAccess.open(ProjectSettings.globalize_path("user://mods").path_join("README.txt"), FileAccess.WRITE)
	r.store_string(MOD_README)
	r.close()
	return dir

const MOD_README := """SOKAK — EKLENTİ (MOD) REHBERİ
=============================
Her eklenti bir klasördür ve içinde mod.json bulunur. Klasörü şuraya koy:
  • Oyun klasörü/mods/<eklenti>/mod.json     (SOKAK.exe'nin yanındaki mods klasörü)
  • %APPDATA%/Godot/app_userdata/SOKAK/mods/<eklenti>/mod.json

mod.json alanları (hepsi isteğe bağlı):
  "weapons":    { "id": { "base": "ak47", "name": "...", "dmg": 33, "rpm": 600, "mag": 30, "price": 3000, "model": "silah.glb" } }
                base = hazır silah (model + animasyonlar), "model" verirsen kendi .glb modelin kullanılır.
  "skins":      { "id": { "name": "...", "price": 900, "rarity": 0-3, "texture": "desen.png", "color": "#ff0000" } }
  "characters": { "id": { "name": "...", "team": "a"|"b", "price": 0, "model": "karakter.glb" | "base": "takim" } }
  "maps":       { "id": { "name": "...", "glb": "harita.glb", "json": "harita.json" } }
                json: {"colliders":[{"c":[x,y,z],"s":[sx,sy,sz],"r":[rx,ry,rz]}], "spawns":[{"p":[x,y,z],"yaw":0,"team":"a"}], "env":{"preset":"day"}, "bounds":[x0,y0,x1,y1]}
  "crates":     { "id": { "name": "...", "price": 1500, "color": "#ffaa00", "skins": [...], "weapons": [...], "chars": [...] } }

Oyunda: Lobi > EKLENTİLER sayfasından eklentileri açıp kapatabilirsin (değişiklik yeniden başlatınca uygulanır).
"""
