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
	"aug":    {"name": "AUG A3", "cat": "ana", "cls": "Makinalı", "dmg": 31, "rpm": 700, "mag": 30, "reserve": 120, "reload": 2.6, "spread": 0.024, "ads_spread": 0.0022, "move": 0.045, "recoil": 0.017, "hrec": 0.006, "auto": true, "range": 180.0, "speed": 0.96, "price": 4400, "snd": "shot_aug", "zoom": 1.65, "head": 2.5},
	"vector": {"name": "Vector .45", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 19, "rpm": 1150, "mag": 25, "reserve": 150, "reload": 1.9, "spread": 0.028, "ads_spread": 0.007, "move": 0.018, "recoil": 0.009, "hrec": 0.008, "auto": true, "range": 70.0, "speed": 1.07, "price": 3800, "snd": "shot_vector", "zoom": 1.2, "head": 2.1},
	"m249":   {"name": "M249 SAW", "cat": "ana", "cls": "Ağır Makinalı", "dmg": 30, "rpm": 760, "mag": 100, "reserve": 200, "reload": 5.2, "spread": 0.034, "ads_spread": 0.008, "move": 0.08, "recoil": 0.02, "hrec": 0.011, "auto": true, "range": 170.0, "speed": 0.84, "price": 6200, "snd": "shot_m249", "zoom": 1.25, "head": 2.3},
	"revolver": {"name": "Magnum .357", "cat": "tabanca", "cls": "Tabanca", "dmg": 62, "rpm": 150, "mag": 6, "reserve": 36, "reload": 2.3, "spread": 0.02, "ads_spread": 0.003, "move": 0.04, "recoil": 0.06, "hrec": 0.012, "auto": false, "range": 120.0, "speed": 1.05, "price": 2600, "snd": "shot_revolver", "zoom": 1.25, "head": 2.7},
	"glock":  {"name": "Glock 17", "cat": "tabanca", "cls": "Tabanca", "dmg": 24, "rpm": 420, "mag": 17, "reserve": 68, "reload": 1.6, "spread": 0.02, "ads_spread": 0.006, "move": 0.015, "recoil": 0.02, "hrec": 0.006, "auto": false, "range": 80.0, "speed": 1.08, "price": 0, "snd": "shot_pistol", "zoom": 1.15, "head": 2.5},
	"deagle": {"name": "Deagle .50", "cat": "tabanca", "cls": "Tabanca", "dmg": 54, "rpm": 210, "mag": 7, "reserve": 35, "reload": 1.9, "spread": 0.022, "ads_spread": 0.004, "move": 0.04, "recoil": 0.055, "hrec": 0.012, "auto": false, "range": 120.0, "speed": 1.05, "price": 1800, "snd": "shot_deagle", "zoom": 1.2, "head": 2.6},
	"r870":   {"name": "870 Pompalı", "cat": "ana", "cls": "Pompalı", "dmg": 19, "rpm": 62, "mag": 6, "reserve": 30, "reload": 0.6, "spread": 0.068, "ads_spread": 0.05, "move": 0.02, "recoil": 0.075, "hrec": 0.02, "auto": false, "range": 45.0, "pellets": 8, "speed": 0.97, "price": 2800, "snd": "shot_r870", "zoom": 1.15, "head": 1.6, "shell_reload": true},
	"fn502":  {"name": "FN 502 Taktik", "cat": "tabanca", "cls": "Tabanca", "dmg": 21, "rpm": 480, "mag": 15, "reserve": 60, "reload": 1.5, "spread": 0.017, "ads_spread": 0.004, "move": 0.012, "recoil": 0.014, "hrec": 0.005, "auto": false, "range": 75.0, "speed": 1.08, "price": 1400, "snd": "shot_fn502", "zoom": 1.2, "head": 2.5, "silenced": true},
	"m1911":  {"name": "M1911 Susturuculu", "cat": "tabanca", "cls": "Tabanca", "dmg": 31, "rpm": 380, "mag": 8, "reserve": 48, "reload": 1.7, "spread": 0.016, "ads_spread": 0.003, "move": 0.012, "recoil": 0.024, "hrec": 0.007, "auto": false, "range": 70.0, "speed": 1.07, "price": 1900, "snd": "shot_m1911", "zoom": 1.2, "head": 2.6, "silenced": true},
	"vityaz": {"name": "PP-19 Vityaz", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 22, "rpm": 820, "mag": 30, "reserve": 150, "reload": 2.1, "spread": 0.025, "ads_spread": 0.006, "move": 0.02, "recoil": 0.011, "hrec": 0.007, "auto": true, "range": 85.0, "speed": 1.05, "price": 2700, "snd": "shot_vityaz", "zoom": 1.2, "head": 2.2},
	"rpk16":  {"name": "RPK-16", "cat": "ana", "cls": "Ağır Makinalı", "dmg": 31, "rpm": 700, "mag": 95, "reserve": 190, "reload": 4.6, "spread": 0.031, "ads_spread": 0.006, "move": 0.07, "recoil": 0.018, "hrec": 0.01, "auto": true, "range": 175.0, "speed": 0.86, "price": 5600, "snd": "shot_rpk", "zoom": 1.45, "head": 2.4},
	"awm":    {"name": "AWM", "cat": "ana", "cls": "Nişancı", "dmg": 135, "rpm": 38, "mag": 5, "reserve": 20, "reload": 3.6, "spread": 0.09, "ads_spread": 0.0002, "move": 0.13, "recoil": 0.09, "hrec": 0.01, "auto": false, "range": 450.0, "scope": true, "zoom": 5.5, "speed": 0.84, "price": 6500, "snd": "shot_awm", "head": 3.2, "bolt": true},
	"uzi":    {"name": "Micro UZI", "cat": "ana", "cls": "Hafif Makinalı", "dmg": 18, "rpm": 1200, "mag": 32, "reserve": 160, "reload": 1.8, "spread": 0.032, "ads_spread": 0.011, "move": 0.012, "recoil": 0.009, "hrec": 0.011, "auto": true, "range": 55.0, "speed": 1.1, "price": 2100, "snd": "shot_uzi", "zoom": 1.15, "head": 2.0},
	"kuzgun": {"name": "BR-7 Kuzgun", "cat": "ana", "cls": "Savaş Tüfeği", "dmg": 36, "rpm": 900, "mag": 36, "reserve": 144, "reload": 2.5, "spread": 0.02, "ads_spread": 0.002, "move": 0.045, "recoil": 0.016, "hrec": 0.006, "auto": false, "burst": 3, "burst_delay": 0.32, "range": 220.0, "speed": 0.95, "price": 5200, "snd": "shot_kuzgun", "zoom": 2.0, "head": 2.5},
	"m4k":    {"name": "M4 Karabina", "cat": "ana", "cls": "Makinalı", "dmg": 30, "rpm": 780, "mag": 30, "reserve": 120, "reload": 2.1, "spread": 0.023, "ads_spread": 0.0028, "move": 0.04, "recoil": 0.015, "hrec": 0.007, "auto": true, "range": 165.0, "speed": 0.98, "price": 3400, "snd": "shot_m4k", "zoom": 1.35, "head": 2.5},
	"usp":    {"name": "USP .45 Taktik", "cat": "tabanca", "cls": "Tabanca", "dmg": 29, "rpm": 400, "mag": 12, "reserve": 60, "reload": 1.6, "spread": 0.017, "ads_spread": 0.0035, "move": 0.013, "recoil": 0.022, "hrec": 0.006, "auto": false, "range": 85.0, "speed": 1.08, "price": 1600, "snd": "shot_usp", "zoom": 1.2, "head": 2.6},
	"kartal": {"name": "Kartal .44 Toplu", "cat": "tabanca", "cls": "Tabanca", "dmg": 68, "rpm": 130, "mag": 6, "reserve": 30, "reload": 2.4, "spread": 0.019, "ads_spread": 0.0028, "move": 0.04, "recoil": 0.065, "hrec": 0.013, "auto": false, "range": 125.0, "speed": 1.05, "price": 3000, "snd": "shot_kartal", "zoom": 1.25, "head": 2.7},
	"akm":    {"name": "AKM", "cat": "ana", "cls": "Makinalı", "dmg": 34, "rpm": 600, "mag": 30, "reserve": 120, "reload": 2.5, "spread": 0.029, "ads_spread": 0.0042, "move": 0.05, "recoil": 0.022, "hrec": 0.009, "auto": true, "range": 160.0, "speed": 0.95, "price": 3000, "snd": "shot_akm", "zoom": 1.25, "head": 2.6},
	"knife":  {"name": "Savaş Bıçağı", "cat": "bicak", "cls": "Bıçak", "dmg": 55, "rpm": 110, "melee": true, "speed": 1.15, "price": 0, "head": 1.0},
	"karambit": {"name": "Karambit", "cat": "bicak", "cls": "Bıçak", "dmg": 60, "rpm": 130, "melee": true, "speed": 1.17, "price": 2000, "head": 1.0},
	"hancer": {"name": "Osmanlı Hançeri", "cat": "bicak", "cls": "Bıçak", "dmg": 58, "rpm": 125, "melee": true, "speed": 1.17, "price": 2600, "head": 1.0},
	"kasap":  {"name": "Kasap Bıçağı", "cat": "bicak", "cls": "Bıçak", "dmg": 50, "rpm": 150, "melee": true, "speed": 1.18, "price": 1200, "head": 1.0},
	"balta":  {"name": "Taktik Balta", "cat": "bicak", "cls": "Bıçak", "dmg": 75, "rpm": 80, "melee": true, "speed": 1.08, "price": 2800, "head": 1.0},
	"frag":   {"name": "El Bombası MK3", "cat": "bomba", "cls": "Bomba", "dmg": 130, "count": 2, "throwable": true, "speed": 1.1, "price": 0, "head": 1.0},
	"pence":  {"name": "Kurt Pençesi", "cat": "bicak", "cls": "Kurt", "dmg": 68, "rpm": 160, "melee": true, "speed": 1.55, "price": 0, "head": 1.0, "hidden": true},
	"smoke":  {"name": "Sis Bombası M18", "cat": "bomba", "cls": "Bomba", "dmg": 0, "count": 1, "throwable": true, "smoke": true, "speed": 1.1, "price": 0, "head": 1.0, "hidden": true, "base": "frag"},
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
	"col": {"name": "Çöl Fırtınası", "price": 700, "rarity": 0},
	"kan": {"name": "Kan Kırmızı Karbon", "price": 1600, "rarity": 1},
	"lale": {"name": "Lale Devri", "price": 1900, "rarity": 1},
	"okyanus": {"name": "Derin Okyanus", "price": 2100, "rarity": 1},
	"siber": {"name": "Siber Neon", "price": 2800, "rarity": 2},
	"nazar": {"name": "Nazar", "price": 2900, "rarity": 2},
	"ejder": {"name": "Ejderha Pulu", "price": 3400, "rarity": 2},
	"kehribar": {"name": "Kehribar", "price": 3600, "rarity": 2},
	"zumrut": {"name": "Zümrüt", "price": 4400, "rarity": 3},
	"mermer": {"name": "Marmara Mermeri", "price": 4600, "rarity": 3},
	"aurora": {"name": "Kuzey Işığı", "price": 5200, "rarity": 3},
	"ayyildiz": {"name": "Ay Yıldız", "price": 5500, "rarity": 3},
	# v3.2 animated legendaries (glowing, moving patterns)
	"ejderha": {"name": "Kara Ejderha", "price": 9000, "rarity": 3, "anim": true},
	"anka": {"name": "Anka Alevi", "price": 8500, "rarity": 3, "anim": true},
	"kuantum": {"name": "Kuantum Devresi", "price": 7500, "rarity": 3, "anim": true},
	"yildirim": {"name": "Yıldırım Fırtınası", "price": 8000, "rarity": 3, "anim": true},
	# v3.4.1 animated legendaries, each with its own motion
	"hologram": {"name": "Hologram", "price": 8800, "rarity": 3, "anim": true},
	"plazma": {"name": "Plazma Fırtınası", "price": 9200, "rarity": 3, "anim": true},
	"nebula": {"name": "Kozmik Nebula", "price": 9500, "rarity": 3, "anim": true},
	"magma": {"name": "Magma Çekirdeği", "price": 9000, "rarity": 3, "anim": true},
}
var CRATES := {
	"sokak": {"name": "Sokak Kasası", "price": 1000, "color": Color("ff8a1f"), "desc": "Her şeyden biraz: malzeme, altın, stiller.",
		"skins": ["kamuflaj", "kar", "dijital", "gece", "neon", "kizil", "galaksi", "altin", "col", "kan", "okyanus", "siber"], "weapons": ["mp5", "ump45", "p90", "fn502", "usp", "deagle", "spas", "kar98", "kasap"], "wchance": 0.2, "chars": []},
	"silah": {"name": "Silah Kasası", "price": 1800, "color": Color("ff4d5e"), "desc": "Her açılışta yüksek silah şansı! Süreli (3/7/30 gün) veya nadiren SÜRESİZ silahlar.",
		"skins": ["kamuflaj", "dijital", "karbon", "kizil"], "weapons": ["m4a1", "scar", "aug", "vector", "ump45", "p90", "vityaz", "rpk16", "m249", "awp", "awm", "kar98", "r870", "spas", "deagle", "revolver", "m1911", "fn502", "uzi", "kuzgun", "m4k", "usp", "kartal", "akm", "balta"], "wchance": 0.62, "chars": []},
	"operasyon": {"name": "Operasyon Kasası", "price": 2000, "color": Color("4fb3ff"), "desc": "Taktik stiller ve %38 silah şansı (AUG, Vector, Vityaz, UZI...). Kasa silahları süreli gelir.",
		"skins": ["dijital", "karbon", "kar", "kamuflaj", "gece", "buz", "col", "kan", "siber", "okyanus"], "weapons": ["aug", "vector", "scar", "ump45", "m4a1", "p90", "r870", "fn502", "vityaz", "m1911", "uzi", "m4k", "usp", "akm", "kasap"], "wchance": 0.38, "chars": ["asker2", "asker3"]},
	"eklenti": {"name": "Eklenti Paketi", "price": 1500, "color": Color("7dff6a"), "desc": "Silah eklentileri: susturucu, nişangah, şarjör, tutamak, lazer.",
		"skins": ["karbon", "dijital"], "weapons": [], "chars": [], "parts": ["sus", "kompen", "optik", "durbun", "sarjor", "tutamak", "lazer", "sus_kisa", "sus_ejder", "sus_plazma", "durbun_holo", "optik_nebula", "kompen_kuantum"]},
	"osmanli": {"name": "Osmanlı Kasası", "price": 2500, "color": Color("2fb6a8"), "desc": "Çini ve turkuaz desenler, Magnum ve Patron karakteri şansı.",
		"skins": ["cini", "turkuaz", "altin", "kizil", "neon", "lale", "nazar", "mermer", "ayyildiz", "kehribar"], "weapons": ["revolver", "kartal", "deagle", "karambit", "hancer", "m1911"], "wchance": 0.32, "chars": ["patron", "kapson"]},
	"ejder": {"name": "Ejder Kasası", "price": 6500, "color": Color("ff3b1f"), "desc": "HAREKETLİ efsanevi kaplamalar: Kara Ejderha, Anka Alevi, Kuantum Devresi, Yıldırım Fırtınası!",
		"skins": ["ejderha", "anka", "kuantum", "yildirim", "lav", "galaksi", "aurora", "buz", "ejder", "kizil"], "weapons": ["awm", "awp", "scar", "rpk16", "m4a1", "ak47"], "wchance": 0.2, "chars": [], "parts": []},
	"kozmik": {"name": "Kozmik Kasa", "price": 7000, "color": Color("b84bff"), "desc": "YENİ hareketli efsaneviler: Hologram, Plazma Fırtınası, Kozmik Nebula, Magma Çekirdeği!",
		"skins": ["hologram", "plazma", "nebula", "magma", "kuantum", "yildirim", "galaksi", "aurora", "siber", "neon"], "weapons": ["awm", "scar", "m4a1", "ak47", "vector", "deagle"], "wchance": 0.2, "chars": [], "parts": ["sus_plazma", "durbun_holo", "optik_nebula", "kompen_kuantum"]},
	"efsane": {"name": "Efsane Kasası", "price": 5000, "color": Color("ffb02e"), "desc": "En az Epik garantili! Lav, Buz, Galaksi, Altın.",
		"skins": ["lav", "buz", "galaksi", "altin", "cini", "turkuaz", "zumrut", "mermer", "aurora", "ayyildiz", "ejder", "kehribar"], "weapons": ["awp", "awm", "scar", "m249", "rpk16", "kuzgun"], "wchance": 0.4, "chars": ["kot", "patron", "asker2"], "parts": ["sus", "optik", "durbun", "sarjor"]},
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
	"r870":   {"ap": 0.1, "pen": 0.0, "f0": 7.0, "f1": 26.0, "fmin": 0.25, "limb": 0.9, "ability": "Sıkı saçma: pompalılar arasında en uzun menzil"},
	"fn502":  {"ap": 0.15, "pen": 0.0, "f0": 14.0, "f1": 40.0, "fmin": 0.65, "limb": 0.8, "ability": "Namlu ucu susturuculu: haritada görünmezsin"},
	"m1911":  {"ap": 0.3, "pen": 0.05, "f0": 14.0, "f1": 40.0, "fmin": 0.65, "limb": 0.8, "ability": ".45 ACP ve susturucu: sessiz ve ağır vuruş"},
	"vityaz": {"ap": 0.2, "pen": 0.05, "f0": 14.0, "f1": 45.0, "fmin": 0.6, "limb": 0.8, "ability": "Rus SMG: düşük geri tepme, hızlı şarjör"},
	"rpk16":  {"ap": 0.5, "pen": 0.35, "f0": 30.0, "f1": 95.0, "fmin": 0.72, "limb": 0.8, "abil": "suppress", "ability": "95'lik tambur + holografik nişangah: bastırma ateşi"},
	"awm":    {"ap": 1.0, "pen": 0.75, "f0": 450.0, "f1": 550.0, "fmin": 1.0, "limb": 0.85, "ability": ".338 Magnum: her yerden tek atış, kalın duvar deler"},
	"uzi":    {"ap": 0.1, "pen": 0.0, "f0": 9.0, "f1": 28.0, "fmin": 0.55, "limb": 0.85, "ability": "Cep makinalısı: en hızlı koşu, dakikada 1200 atış"},
	"kuzgun": {"ap": 0.55, "pen": 0.3, "f0": 40.0, "f1": 120.0, "fmin": 0.75, "limb": 0.8, "ability": "3'lü seri atış + 2x dürbün: orta mesafede 1 seriyle kafadan öldürür"},
	"spas":   {"ap": 0.1, "pen": 0.0, "f0": 6.0, "f1": 22.0, "fmin": 0.22, "limb": 0.9, "ability": "Yakın mesafede tek atışta öldürür"},
	"awp":    {"ap": 0.95, "pen": 0.65, "f0": 400.0, "f1": 500.0, "fmin": 1.0, "limb": 0.85, "ability": "Gövdeden tek atış, duvar deler"},
	"kar98":  {"ap": 0.85, "pen": 0.5, "f0": 400.0, "f1": 500.0, "fmin": 1.0, "limb": 0.8, "ability": "Hızlı sürgü, kafadan kesin ölüm"},
	"glock":  {"ap": 0.1, "pen": 0.0, "f0": 12.0, "f1": 35.0, "fmin": 0.65, "limb": 0.8, "ability": "Işık hızında çekiş ve geniş şarjör"},
	"deagle": {"ap": 0.6, "pen": 0.2, "f0": 20.0, "f1": 60.0, "fmin": 0.7, "limb": 0.8, "ability": "Kafadan tek atış"},
	"m4k":    {"ap": 0.42, "pen": 0.2, "f0": 30.0, "f1": 90.0, "fmin": 0.74, "limb": 0.75, "ability": "Kısa namlu karabina: hızlı nişan, dengeli geri tepme"},
	"usp":    {"ap": 0.3, "pen": 0.05, "f0": 15.0, "f1": 45.0, "fmin": 0.66, "limb": 0.8, "ability": ".45 ACP: 2 kafa atışıyla öldürür, isabetli ilk mermi"},
	"kartal": {"ap": 0.6, "pen": 0.2, "f0": 24.0, "f1": 70.0, "fmin": 0.74, "limb": 0.85, "ability": ".44 Magnum toplu: kafadan tek atış, çok sert geri tepme"},
	"akm":    {"ap": 0.5, "pen": 0.32, "f0": 25.0, "f1": 75.0, "fmin": 0.72, "limb": 0.8, "ability": "Modern AK: ahşap kundak, 7.62 mermi ince duvarları deler"},
	"revolver": {"ap": 0.55, "pen": 0.18, "f0": 22.0, "f1": 65.0, "fmin": 0.72, "limb": 0.85, "ability": "En güçlü tabanca, sert geri tepme"},
}

## weapon attachments (eklenti parçaları): dropped from crates, bought in the market, fitted in the bag
const PARTS := {
	"sus":     {"name": "Susturucu", "desc": "Sessiz atış, namlu alevi yok, haritada görünmezsin. Hasar -%6", "slot": "namlu", "price": 900, "pistol": true},
	"kompen":  {"name": "Kompansatör", "desc": "Dikey sekme -%22", "slot": "namlu", "price": 700, "pistol": true},
	"optik":   {"name": "Holografik Nişangah (EXPS)", "desc": "Nişanlı isabet +%30, yakınlaştırma +0.2", "slot": "optik", "price": 800, "pistol": false},
	"durbun":  {"name": "Taktik Dürbün 3x", "desc": "3 kat yakınlaştırma, nişanlı isabet +%50, nişan alma biraz yavaş", "slot": "optik", "price": 1400, "pistol": false},
	# v3.5.1 special variants: same mount as their base part, animated pattern + their own stats
	"sus_ejder":   {"name": "Magma Susturucu", "desc": "HAREKETLİ magma çatlakları. Sessiz atış, hasar sadece -%3", "slot": "namlu", "price": 2600, "pistol": true, "base": "sus", "fx": "magma", "dmg": 0.97},
	"sus_plazma":  {"name": "Plazma Susturucu", "desc": "HAREKETLİ plazma akışı. Sessiz atış, geri tepme -%8, hasar -%6", "slot": "namlu", "price": 2800, "pistol": true, "base": "sus", "fx": "plazma", "recoil": 0.92},
	"sus_kisa":    {"name": "Kısa Taktik Susturucu", "desc": "Karbon fiber, kısa gövde. Sessiz atış, hasar -%4, nişan alma +%10 hızlı", "slot": "namlu", "price": 1600, "pistol": true, "base": "sus", "fx": "karbon", "dmg": 0.96, "len": 0.62, "ads": 0.9},
	"durbun_holo": {"name": "Hologram Dürbün 3x", "desc": "HAREKETLİ hologram gövde. 3x yakınlaştırma, nişanlı isabet +%55, nişan alma normal hızda", "slot": "optik", "price": 3200, "pistol": false, "base": "durbun", "fx": "hologram", "ads": 0.74},
	"optik_nebula": {"name": "Kozmik Holo Nişangah", "desc": "HAREKETLİ nebula gövde. Nişanlı isabet +%35, yakınlaştırma +0.25", "slot": "optik", "price": 2400, "pistol": false, "base": "optik", "fx": "nebula"},
	"kompen_kuantum": {"name": "Kuantum Kompansatör", "desc": "HAREKETLİ kuantum devreleri. Dikey sekme -%26", "slot": "namlu", "price": 2200, "pistol": true, "base": "kompen", "fx": "kuantum", "recoil": 0.95},
	"sarjor":  {"name": "Uzatılmış Şarjör", "desc": "Şarjör +%50, doldurma süresi +%12", "slot": "sarjor", "price": 1000, "pistol": true},
	"tutamak": {"name": "Ön Tutamak", "desc": "Sekme -%15, yatay sekme -%30", "slot": "alt", "price": 750, "pistol": false},
	"lazer":   {"name": "Taktik Lazer", "desc": "Belden atış isabeti +%25, hareket isabeti +%30", "slot": "alt", "price": 850, "pistol": true},
}
const PART_SLOTS := ["namlu", "optik", "sarjor", "alt"]

func ball(id: String) -> Dictionary:
	return BALLISTICS.get(id, {"ap": 0.2, "pen": 0.0, "f0": 20.0, "f1": 60.0, "fmin": 0.7, "limb": 0.8})

func wparts(id: String) -> Array:
	return profile.get("wparts", {}).get(id, [])

func pbase(pid: String) -> String:
	return str(PARTS.get(pid, {}).get("base", pid))

func has_part_base(wid: String, base: String) -> bool:
	for q in wparts(wid):
		if pbase(str(q)) == base:
			return true
	return false

func part_fits(pid: String, wid: String) -> bool:
	var w: Dictionary = WEAPONS.get(wid, {})
	var bpid := pbase(pid)
	if w.get("melee", false) or w.get("throwable", false):
		return false
	if bpid in ["optik", "durbun"] and (w.get("scope", false) or wid in ["scar", "ump45", "vector", "m249", "aug"]):
		return false   # these already have an optic
	if w.get("pellets", 0) > 0 and bpid in ["sus", "optik", "durbun"]:
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
		var pd: Dictionary = PARTS.get(pid, {})
		match pbase(str(pid)):
			"sus":
				w["dmg"] = int(round(float(w["dmg"]) * float(pd.get("dmg", 0.94)))); w["silenced"] = true
				w["recoil"] = float(w["recoil"]) * float(pd.get("recoil", 1.0))
			"kompen":
				w["recoil"] = float(w["recoil"]) * 0.78 * float(pd.get("recoil", 1.0))
			"optik":
				w["ads_spread"] = float(w.get("ads_spread", 0.005)) * (0.65 if pd.has("fx") else 0.7); w["zoom"] = float(w.get("zoom", 1.2)) + (0.25 if pd.has("fx") else 0.2)
			"durbun":
				w["ads_spread"] = float(w.get("ads_spread", 0.005)) * (0.45 if pd.has("fx") else 0.5); w["zoom"] = 3.0; w["ads_time"] = float(w.get("ads_time", 0.18)) * 1.35
			"sarjor":
				w["mag_max"] = int(ceil(float(w["mag_max"]) * 1.5)); w["reload"] = float(w["reload"]) * 1.12
			"tutamak":
				w["recoil"] = float(w["recoil"]) * 0.85; w["hrec"] = float(w.get("hrec", 0.006)) * 0.7
			"lazer":
				w["spread"] = float(w["spread"]) * 0.75; w["move"] = float(w.get("move", 0.03)) * 0.7
	return w

const LVL_GLOW_COLS := [Color(0, 0, 0), Color(0.3, 0.75, 1.0), Color(0.3, 0.75, 1.0), Color(0.65, 0.4, 1.0), Color(0.65, 0.4, 1.0), Color(1.0, 0.5, 0.15), Color(1.0, 0.5, 0.15), Color(1.0, 0.82, 0.3)]
const LVL_GLOW_COLS2 := [Color(0, 0, 0), Color(0.75, 0.95, 1.0), Color(0.75, 0.95, 1.0), Color(1.0, 0.55, 0.95), Color(1.0, 0.55, 0.95), Color(1.0, 0.85, 0.35), Color(1.0, 0.85, 0.35), Color(1.0, 1.0, 0.85)]
## shown next to a weapon name: "+4" badge colour for an upgrade level
func lvl_color(lvl: int) -> Color:
	return LVL_GLOW_COLS[clamp(lvl, 0, 7)] if lvl > 0 else Color(0.7, 0.75, 0.8)
var _glow_shader: Shader

func _is_optic_mesh(mi: MeshInstance3D) -> bool:
	## glass / reticle surfaces must never get the upgrade overlay (it would cloud the sight picture)
	if mi.mesh == null:
		return false
	for k in mi.mesh.get_surface_count():
		var sm := mi.mesh.surface_get_material(k)
		var n := sm.resource_name if sm else ""
		if "glass" in n or "holo" in n or "ret" in n or "dot" in n or "lens" in n:
			return true
	return false

func level_glow(gun: Node3D, id: String, strength: float = 1.0) -> void:
	## Upgrade tiers: +1/2 cyan, +3/4 violet, +5/6 ember, +7 gold.
	## No surface tint (the skin stays fully visible): thin energy lines run along the weapon's hard edges,
	## a faint silhouette rim, and a narrow light sweep every few seconds. In the menu/inspect (strength >= 1)
	## tier 3+ also gets a soft particle aura.
	var lvl := wlvl(id)
	if gun == null:
		return
	for old in gun.find_children("LvlAura", "GPUParticles3D", true, false):
		old.queue_free()
	if lvl <= 0:
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = null
		return
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, depth_test_default;
uniform vec4 col : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 col2 : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float power = 1.0;
uniform float tier = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
// distance to the nearest hexagon edge (0 on the edge)
float hexd(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}
void fragment() {
	// additive overlay only: the skin underneath is never tinted, glass/reticle meshes are skipped on the CPU side
	float edge = smoothstep(0.35, 0.9, length(fwidth(NORMAL)) * 4.0);
	float flow = 0.6 + 0.4 * sin(lp.z * 34.0 - TIME * (2.4 + tier * 0.45) + lp.y * 18.0);
	float pulse = 0.8 + 0.2 * sin(TIME * (2.0 + tier * 0.3));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0) * (0.07 + tier * 0.012);
	// the energy wave: a bright front that travels muzzle -> stock, leaving a hexagon trail that dissolves
	float period = 3.0 - tier * 0.14;
	float cyc = fract(TIME / period);
	float front = mix(-0.75, 0.42, cyc);
	float d = lp.z - front;                       // < 0 : already passed (towards the muzzle)
	float wave = exp(-d * d * 1600.0);
	float trail = d < 0.0 ? exp(d * 7.0) * (1.0 - cyc * 0.35) : 0.0;
	float hx = 1.0 - smoothstep(0.0, 0.09, hexd(vec2(lp.z, lp.y + lp.x * 0.5) * 95.0));
	float scan = 0.5 + 0.5 * sin(lp.y * 520.0 - TIME * 9.0);
	vec3 c = mix(col.rgb, col2.rgb, clamp(wave + hx * trail * 0.6, 0.0, 1.0));
	// second, fainter counter wave from tier 5
	float d2 = lp.z - mix(0.42, -0.75, fract(TIME / period + 0.5));
	float wave2 = step(4.5, tier) * exp(-d2 * d2 * 2600.0) * 0.55;
	float spark = step(6.5, tier) * pow(max(sin(lp.x * 210.0 + TIME * 4.0) * sin(lp.z * 170.0 - TIME * 3.0), 0.0), 30.0);
	float e = edge * flow * pulse * 0.6 + rim + wave * (0.9 + edge * 1.2) + wave2 * (0.6 + edge)
		+ trail * (hx * 0.75 + scan * 0.08) * (0.55 + tier * 0.06) + spark * 1.6;
	ALBEDO = c * e * power;
}"""

	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("col", LVL_GLOW_COLS[clamp(lvl, 0, 7)])
	m.set_shader_parameter("col2", LVL_GLOW_COLS2[clamp(lvl, 0, 7)])
	m.set_shader_parameter("power", (0.55 + lvl * 0.07) * strength)
	m.set_shader_parameter("tier", float(lvl))
	gun.set_meta("glow_mat", m)
	gun.set_meta("glow_power", (0.55 + lvl * 0.07) * strength)
	var aabb := AABB()
	var first := true
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		if _is_optic_mesh(mm):
			mm.material_overlay = null
			continue
		mm.material_overlay = m
		if mm.mesh:
			var bb: AABB = gun.global_transform.affine_inverse() * mm.global_transform * mm.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
	if strength >= 1.0 and lvl >= 3 and not first:
		var p := GPUParticles3D.new()
		p.name = "LvlAura"
		p.amount = 24 + lvl * 6
		p.lifetime = 1.6
		p.local_coords = true
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = aabb.size * 0.5
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.02
		pm.initial_velocity_max = 0.08
		pm.gravity = Vector3(0, 0.03, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var cr := Curve.new()
		cr.add_point(Vector2(0, 0)); cr.add_point(Vector2(0.25, 1)); cr.add_point(Vector2(1, 0))
		var ct := CurveTexture.new(); ct.curve = cr
		pm.scale_curve = ct
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.012)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.albedo_color = LVL_GLOW_COLS[clamp(lvl, 0, 7)] * 1.6
		var gt := GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0)
		var gr := Gradient.new(); gr.set_color(0, Color.WHITE); gr.set_color(1, Color(1, 1, 1, 0))
		gt.gradient = gr
		qm.albedo_texture = gt
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.vertex_color_use_as_albedo = true
		q.material = qm
		p.draw_pass_1 = q
		p.position = aabb.get_center()
		p.visibility_aabb = AABB(-aabb.size, aabb.size * 2.0)
		gun.add_child(p)

func _att(pid: String, fx: String = "") -> Node3D:
	var path := "res://assets/models/att_%s.glb" % pid
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.set_meta("att", true)
	MatLib.apply(n, "std")
	if fx != "":
		# special variants: the animated / patterned finish goes over the body, never over glass or reticles
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var om = m3.get_active_material(si)
				var nm := str(om.resource_name if om else "")
				if "glass" in nm or "reticle" in nm or "dot" in nm or not (om is BaseMaterial3D):
					continue
				m3.set_surface_override_material(si, MatLib.ext_skin_mat(om as BaseMaterial3D, fx))
	return n

func parts_visual(gun: Node3D, id: String, parts = null) -> void:
	## real modelled attachments (tools/attachments.py) mounted on the weapon's markers
	var ps: Array = wparts(id) if parts == null else parts
	if gun == null:
		return
	# v4.1: re-applicable (online puppets change parts): drop old attachments, restore the markers
	for c in gun.find_children("*", "Node3D", true, false):
		if c.has_meta("att"):
			c.queue_free()
	for nm in ["muzzle", "sight", "mag"]:
		var mk := gun.find_child(nm, true, false) as Node3D
		if mk:
			if mk.has_meta("p0"):
				mk.position = mk.get_meta("p0")
				mk.scale = mk.get_meta("s0", Vector3.ONE)
			else:
				mk.set_meta("p0", mk.position)
				mk.set_meta("s0", mk.scale)
	if ps.is_empty():
		return
	var mz := gun.find_child("muzzle", true, false) as Node3D
	var sg := gun.find_child("sight", true, false) as Node3D
	var lh := gun.find_child("lhand", true, false) as Node3D
	var mg := gun.find_child("mag", true, false) as Node3D
	var pistol: bool = WEAPONS[id]["cat"] == "tabanca"
	for pid0 in ps:
		var pid := pbase(str(pid0))
		var pfx := str(PARTS.get(pid0, {}).get("fx", ""))
		match pid:
			"sus", "kompen":
				if mz:
					var a := _att(pid, pfx)
					if a and PARTS.get(pid0, {}).has("len"):
						a.scale = Vector3(1.08, 1.08, float(PARTS[pid0]["len"]))
					if a == null: continue
					mz.get_parent().add_child(a)
					a.position = mz.position + Vector3(0, 0, 0.004)
					if pistol:
						a.scale = Vector3(0.8, 0.8, 0.72) if pid == "sus" else Vector3(0.8, 0.8, 0.8)
					var tip := a.find_child("muzzle", true, false) as Node3D
					if tip:
						mz.position = a.position + tip.position * a.scale
			"optik", "durbun":
				if sg:
					var a := _att(pid, pfx)
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
	"insaat": {"name": "İnşaat", "desc": "Yarım kalmış 3 katlı beton bina, vinç ve şantiye. Küçük ve hızlı, yakın çatışma.", "size": "Küçük"},
	"canakkale": {"name": "Çanakkale", "desc": "Boğaz kıyısında taş tabya, top mevzileri ve siper hattı. Gün batımında destansı çatışma.", "size": "Büyük"},
	"hurda": {"name": "Hurda Sahası", "desc": "Çukurdaki konteyner sahası: hesco bariyerleri, lastikler, sürekli çatışma.", "size": "Küçük", "amb": "amb_site"},
	"fabrika": {"name": "Paslı Fabrika", "desc": "Terk edilmiş tuğla fabrika kompleksi, avlular, depolar ve bacalar.", "size": "Büyük", "amb": "amb_city"},
	"cekirdek": {"name": "Çekirdek Tesisi", "desc": "Yeraltı araştırma tesisi: dar koridorlar, metal ızgaralı köprüler, kontrol odaları ve çok katlı salonlar.", "size": "Büyük", "amb": "amb_wind"},
}
var MODES := {
	"ffa": {"name": "Ölüm Maçı", "desc": "Herkes herkese karşı. En çok öldüren kazanır.", "teams": false},
	"tdm": {"name": "Takım Ölüm Maçı", "desc": "KARTAL vs AKREP. Takım skoru hedefe ulaşınca biter.", "teams": true},
	"gungame": {"name": "Silah Oyunu", "desc": "Her öldürmede silahın değişir. Son silah bıçak!", "teams": false},
	"knife": {"name": "Bıçak Arenası", "desc": "Sadece bıçak ve el bombası. Saf refleks.", "teams": false},
	"sniper": {"name": "Nişancı Düellosu", "desc": "Sadece keskin nişancı tüfekleri. Takımlı.", "teams": true},
	"kurt": {"name": "Kurt Adam", "desc": "Gece çöktü. Enerjin dolunca 3'e bas ve KURDA DÖNÜŞ: hızlı koşu, çift zıplama taklası, duvara tırmanma, ölümcül pençe!", "teams": true},
	"bayrak": {"name": "Bayrak Savaşı", "desc": "Rakibin bayrağını çal, kendi üssüne getir: 1 sayı. Bayrağın üssündeyken sayı alınır. İlk 3 sayıyı alan kazanır.", "teams": true},
	"sabotaj": {"name": "Sabotaj", "desc": "KARTAL bombayı A ya da B noktasına kurar, AKREP çözer. Turlu, ilk 6 turu alan kazanır.", "teams": true},
}
## CC-BY 4.0 assets: [work, author, licence/link] — shown in Ayarlar > Lisanslar
const CREDITS := [
	["M4 - FPS Weapon Animations Pack v.1 (M4A1 birinci şahıs)", "BarcodeGames", "CC-BY 4.0 · sketchfab.com"],
	["Sniper animated (AWM birinci şahıs)", "DJMaesen", "CC-BY 4.0 · sketchfab.com/bumstrum"],
	["Sniper (AWM)", "DJMaesen", "CC-BY 4.0 · sketchfab.com/bumstrum"],
	["Shotgun (SPAS)", "DJMaesen", "CC-BY 4.0 · sketchfab.com/bumstrum"],
	["Scar-H First Person FPS Animated (SCAR-H)", "Jainesh Pathak", "CC-BY 4.0 · sketchfab.com/spectraut2"],
	["Kar98k with ZF4 (Kar98)", "FF_Morph", "CC-BY 4.0 · sketchfab.com"],
	["MP5 (PBR) High Poly (MP5)", "Stein Games", "CC-BY 4.0 · sketchfab.com/jvitor17"],
	["P90 Modular Game Ready (P90)", "TWORKS", "CC-BY 4.0 · sketchfab.com/trbrick"],
	["Kriss Vector 45 ACP (Vector)", "vadimm", "CC-BY 4.0 · sketchfab.com/kravchukv123"],
	["Desert Eagle (Deagle .50)", "drcrazzie", "CC-BY 4.0 · sketchfab.com/drcrazzie"],
	["Low Poly M249 SAW (M249)", "Sketchfab sanatçısı", "CC-BY 4.0 · sketchfab.com"],
	["Low Poly 3D Magnum Revolver (Magnum .357)", "Sketchfab sanatçısı", "CC-BY 4.0 · sketchfab.com"],
	["Low Poly Uzi", "Duane's Mind", "CC-BY 4.0 · sketchfab.com"],
	["PP-19-01 Vityaz", "suspensy", "CC-BY 4.0 · sketchfab.com"],
	["Pistol 9mm - semi auto (Glock)", "Hitansh 3D", "CC-BY 4.0 · sketchfab.com"],
	["RPK-16", "FamousUnityHubSoldier", "Sketchfab Standard · sketchfab.com"],
	["Müzik: Movement Proposition, Mechanolith, Heroic Age, Darkest Child", "Kevin MacLeod (incompetech.com)", "CC BY 4.0 · creativecommons.org/licenses/by/4.0"],
	["Silah sesleri: The Free Firearm Sound Library", "Still North Media", "CC0 · github.com/buddingmonkey/FreeFirearmsSFXLibrary"],
	["Deagle / AWM atış sesleri (freesound)", "areniporgen, elliotlp, qubodup — GunLib derlemesi", "CC0 · github.com/Deases/GunLib"],
	["Oculus Audio Pack 01 (adım, bıçak, ortam sesleri)", "Oculus VR, LLC", "CC BY 4.0 · developers.meta.com/vr/downloads/package/oculus-audio-pack-1"],
	["SCAR-H, MP5, UMP-45 modelleri: Flat Guns West/East", "fps-asset-kit", "CC0 · github.com/petroulacl/fps-asset-kit"],
	["Impact Sounds (mermi çarpma)", "Kenney", "CC0 · kenney.nl"],
	["knife Animated (tüm bıçaklarda birinci şahıs kollar ve animasyonlar)", "DJMaesen", "CC-BY 4.0 · sketchfab.com/bumstrum"],
	["PARAMS SET (Çekirdek Tesisi haritası)", "kullanıcının sağladığı model", "Sketchfab"],
	["Maps (Hurda Sahası haritası)", "frostychaos144", "CC-BY 4.0 · sketchfab.com/frostychaos144"],
	["Rust (Paslı Fabrika haritası)", "frostychaos144", "CC-BY 4.0 · sketchfab.com/frostychaos144"],
	["Howling (Kurt Adam modeli, rig + animasyon: SOKAK)", "Daniele De Filippis", "CC-BY 4.0 · sketchfab.com/danieledefilippis"],
	["Interface Sounds / UI Audio (menü sesleri)", "Kenney", "CC0 · kenney.nl"],
]
const TEAMS := {"a": "KARTAL", "b": "AKREP"}
const TEAM_COLORS := {"a": Color("3d8bff"), "b": Color("ff4d3d")}
const GUNGAME_ORDER := ["glock", "deagle", "uzi", "mp5", "vityaz", "spas", "m4a1", "ak47", "kuzgun", "kar98", "awm", "knife"]

## v3.8 Ekipman: permanent gear, one per slot. Effects are small and stack across slots (balanced so that a
## fully geared player is better but never untouchable: e.g. -15% body damage costs 4% move speed).
const GEAR_SLOTS := [["yelek", "YELEK"], ["kask", "KASK"], ["eldiven", "ELDİVEN"], ["postal", "POSTAL"], ["canta", "ÇANTA"], ["kart", "TAKTİK KART"]]
const GEAR := {
	"kevlar": {"slot": "yelek", "name": "Kevlar Yelek", "price": 6000, "rar": 1, "fx": {"body_dr": 0.08}, "desc": "Gövdeye gelen hasar %8 azalır. Hız kaybı yok."},
	"celik_yelek": {"slot": "yelek", "name": "Çelik Yelek", "price": 14000, "rar": 3, "fx": {"body_dr": 0.15, "speed": -0.04}, "desc": "Gövdeye gelen hasar %15 azalır, hareket hızı %4 düşer."},
	"celik_kask": {"slot": "kask", "name": "Çelik Kask", "price": 9000, "rar": 2, "fx": {"head_dr": 0.18}, "desc": "Kafaya gelen hasar %18 azalır (keskin nişancı tüfekleri hariç)."},
	"taktik_eld": {"slot": "eldiven", "name": "Taktik Eldiven", "price": 7000, "rar": 1, "fx": {"swap": 0.35, "reload": 0.08}, "desc": "Silah çıkarma %35, şarjör değiştirme %8 daha hızlı."},
	"nisanci_eld": {"slot": "eldiven", "name": "Nişancı Eldiveni", "price": 11000, "rar": 2, "fx": {"recoil": 0.15}, "desc": "Silah tepmesi %15 azalır."},
	"sessiz_postal": {"slot": "postal", "name": "Sessiz Postal", "price": 6500, "rar": 1, "fx": {"step": 0.55}, "desc": "Ayak seslerin %55 daha kısık, adımların zor duyulur."},
	"kosu_postal": {"slot": "postal", "name": "Koşu Postalı", "price": 8500, "rar": 2, "fx": {"speed": 0.05}, "desc": "Hareket hızı %5 artar."},
	"muhimmat": {"slot": "canta", "name": "Mühimmat Çantası", "price": 5000, "rar": 1, "fx": {"reserve": 0.5}, "desc": "Yedek mermin %50 fazla."},
	"bomba_canta": {"slot": "canta", "name": "Bomba Çantası", "price": 8000, "rar": 2, "fx": {"nades": 1}, "desc": "Her doğuşta +1 el bombası."},
	"hizli_dogma": {"slot": "kart", "name": "Hızlı Doğma Kartı", "price": 7500, "rar": 2, "fx": {"respawn": 0.4}, "desc": "Öldükten sonra %40 daha hızlı doğarsın."},
	"adrenalin": {"slot": "kart", "name": "Adrenalin Kartı", "price": 9500, "rar": 3, "fx": {"kill_heal": 15}, "desc": "Her leşte +15 can."},
	"toparlanma": {"slot": "kart", "name": "Toparlanma Kartı", "price": 10000, "rar": 3, "fx": {"regen": 4.0}, "desc": "5 sn hasar almazsan saniyede 4 can yenilenir."},
}

func gear_eq() -> Dictionary:
	var g = profile.get("gear_eq", {})
	return g if g is Dictionary else {}

func gear_owned(id: String) -> bool:
	var o = profile.get("gear", [])
	return o is Array and o.has(id)

## sum of one effect over everything the player has equipped (0 when nothing)
func gear(key: String) -> float:
	var v := 0.0
	for sl in gear_eq().keys():
		var id := str(gear_eq()[sl])
		if GEAR.has(id) and gear_owned(id):
			v += float(GEAR[id]["fx"].get(key, 0.0))
	return v

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
var play_mode := ""             # "bot" or "online" (chosen after login, per session)
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
	var d := Econ.default_profile_base()
	d["name"] = "Oyuncu%d" % randi_range(100, 999)
	d["char"] = "takim"
	return d

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
	profile["crates"] = int(profile.get("crates", 0))
	for grp in ["stats", "mats"]:
		var gd: Dictionary = profile[grp]
		for k in gd.keys():
			gd[k] = int(gd[k])
	for k in profile["missions"].keys():
		if k != "claimed":
			profile["missions"][k] = int(profile["missions"][k])
	for k in profile["parts"].keys() if profile.get("parts") is Dictionary else []:
		profile["parts"][k] = int(profile["parts"][k])
	if profile.get("pass") is Dictionary:
		var pcl: Array = []
		for x in profile["pass"].get("claimed", []):
			pcl.append(int(x))
		profile["pass"]["claimed"] = pcl
		profile["pass"]["xp"] = int(profile["pass"].get("xp", 0))
	for k in profile["crates2"].keys() if profile.get("crates2") is Dictionary else []:
		profile["crates2"][k] = int(profile["crates2"][k])
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
	if not (profile["sets"] is Array):
		profile["sets"] = []
	while (profile["sets"] as Array).size() < Econ.SET_COUNT:
		profile["sets"].append(defaults.duplicate())
	profile["active_set"] = clampi(int(profile["active_set"]), 0, Econ.SET_COUNT - 1)
	for k2 in ["parts", "wparts", "crates2"]:
		if not (profile.get(k2) is Dictionary):
			profile[k2] = {}
	Econ.expire(profile, Time.get_unix_time_from_system())
	if not (profile.get("expired") is Dictionary):
		profile["expired"] = {}
	for st in profile["sets"]:
		for c in (st as Dictionary).keys():
			if not owned(str(st[c])):
				st[c] = defaults.get(c, "knife")
	if not CHARACTERS.has(str(profile.get("char", "takim"))):
		profile["char"] = "takim"

const Econ = preload("res://scripts/econ.gd")
var _cat_cache: Dictionary = {}

func _online() -> bool:
	return has_node("/root/Online") and get_node("/root/Online").is_logged_in()

func catalog() -> Dictionary:
	## economy catalog built from the loaded game data (the server keeps its own copy of the base catalog)
	if not _cat_cache.is_empty():
		return _cat_cache
	var w := {}
	for id in WEAPONS.keys():
		var d: Dictionary = WEAPONS[id]
		if d.get("hidden", false):
			continue
		w[id] = {"price": int(d.get("price", 0)), "cat": str(d["cat"]), "throwable": bool(d.get("throwable", false)), "melee": bool(d.get("melee", false))}
	var sk := {}
	for id in SKINS.keys():
		sk[id] = {"price": int(SKINS[id]["price"]), "rarity": int(SKINS[id]["rarity"])}
	var parts := {}
	for pid in PARTS.keys():
		var fits := []
		for wid in WEAPONS.keys():
			if part_fits(pid, wid):
				fits.append(wid)
		parts[pid] = {"price": int(PARTS[pid]["price"]), "slot": str(PARTS[pid]["slot"]), "fits": fits}
	var cr := {}
	for id in CRATES.keys():
		var c: Dictionary = CRATES[id]
		cr[id] = {"price": int(c["price"]), "skins": c.get("skins", []), "weapons": c.get("weapons", []), "chars": c.get("chars", []), "parts": c.get("parts", []), "wchance": float(c.get("wchance", 0.0))}
	var ch := {}
	for id in CHARACTERS.keys():
		ch[id] = {"price": int(CHARACTERS[id]["price"])}
	var gr := {}
	for id in GEAR.keys():
		gr[id] = {"price": int(GEAR[id]["price"]), "slot": str(GEAR[id]["slot"])}
	_cat_cache = {"weapons": w, "skins": sk, "parts": parts, "crates": cr, "chars": ch, "gear": gr, "missions": MISSIONS, "packs": Econ.PACKS, "featured": Econ.FEATURED}
	return _cat_cache

func act(a: String, args: Dictionary = {}) -> Dictionary:
	## Every economy change goes through here. Online accounts: the server performs it and returns the
	## authoritative profile. Offline: the same rules run locally (scripts/econ.gd).
	if _online():
		var r: Dictionary = await get_node("/root/Online").act(a, args)
		if not r.get("fallback", false):
			if r["ok"] and r.get("profile") is Dictionary:
				var keep_name := str(profile.get("name", ""))
				profile = r["profile"]
				if keep_name != "" and not profile.has("name"):
					profile["name"] = keep_name
				sanitize_profile()
				profile_changed.emit()
			return {"ok": r["ok"], "err": r["err"], "res": r.get("res", {})}
	var res: Dictionary = Econ.act(profile, catalog(), a, args, Time.get_unix_time_from_system())
	if res["ok"]:
		sanitize_profile()
		save_profile(a == "match_start")
	return res

func save_profile(local_only: bool = false) -> void:
	# online accounts live on the server; the local file is the offline profile only
	if not _online():
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

## seconds left on a timed (crate) weapon; 0 = permanent / not owned
func wtime_left(id: String) -> float:
	if not owned(id):
		return 0.0
	var e := float(profile["owned"][id].get("exp", 0))
	return maxf(e - Time.get_unix_time_from_system(), 1.0) if e > 0.0 else 0.0

func wtime_label(id: String) -> String:
	var t := wtime_left(id)
	if t <= 0.0:
		return ""
	if t >= 86400.0:
		return "%d GÜN" % int(ceil(t / 86400.0))
	if t >= 3600.0:
		return "%d SAAT" % int(ceil(t / 3600.0))
	return "%d DK" % int(ceil(t / 60.0))

# ---------------------------------------------------------------- competitive rank
const RANKS := ["Er I", "Er II", "Er III", "Onbaşı I", "Onbaşı II", "Çavuş I", "Çavuş II", "Astsubay I", "Astsubay II",
	"Teğmen", "Üsteğmen", "Yüzbaşı", "Binbaşı", "Yarbay", "Albay", "Tuğgeneral", "Korgeneral", "Mareşal"]
const RANK_COLORS := [Color("c48a5a"), Color("c48a5a"), Color("c48a5a"), Color("c3ccd8"), Color("c3ccd8"), Color("f0be4a"), Color("f0be4a"), Color("f0be4a"), Color("f0be4a"),
	Color("4fd8cc"), Color("4fd8cc"), Color("4fd8cc"), Color("b27cff"), Color("b27cff"), Color("b27cff"), Color("ff5a4a"), Color("ff5a4a"), Color("ffc43a")]

func rank_index(rp: int) -> int:
	var i := 0
	for k in Econ.RANK_RP.size():
		if rp >= int(Econ.RANK_RP[k]):
			i = k
	return i

func rank_info(rp: int) -> Dictionary:
	var i := rank_index(rp)
	var lo: int = Econ.RANK_RP[i]
	var hi: int = Econ.RANK_RP[i + 1] if i + 1 < Econ.RANK_RP.size() else lo
	return {"i": i, "name": RANKS[i], "color": RANK_COLORS[i], "lo": lo, "hi": hi, "rp": rp,
		"prog": 1.0 if hi == lo else clampf(float(rp - lo) / float(hi - lo), 0.0, 1.0),
		"icon": load("res://assets/ui/ranks/r%d.png" % i)}

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
	return Econ.upgrade_cost(lvl)

func _old_upgrade_cost(lvl: int) -> Dictionary:
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
		"quality": "high", "resolution_scale": 1.0, "upscaler": "fsr2", "fullscreen": true, "window_mode": "", "resolution": "auto", "ui_scale": 1.0, "vsync": false, "fps_cap": -1,
		"msaa": 0, "taa": false, "fxaa": true, "shadows": 2, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "glow": true, "volumetric": false,
		"dyn_res": true, "dyn_target": 75,
		"motion_blur": false, "draw_distance": 1.0, "sharpen": 0.3, "brightness": 1.0, "color_pack": "canli", "spray": "gg", "show_fps": true, "perf_overlay": 1, "grass": true, "shadow_dist": 1.0, "announcer": true,
		"vol_master": 0.8, "vol_sfx": 1.0, "vol_music": 0.5, "vol_amb": 0.6, "vol_voice": 1.0, "voice_on": true, "voice_mode": "ptt",
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
	# v2.7: one-time automatic quality pick (older installs defaulted to ULTRA, too heavy for many PCs)
	if not bool(settings.get("perf_v29", false)):
		if int(settings.get("fps_cap", 0)) == 0:
			settings["fps_cap"] = -1
		settings["perf_v29"] = true
	# v2.9.4: re-pick once with the corrected GPU table (RX 6400/6500, GTX 16xx were rated too high)
	if not bool(settings.get("perf_v294", false)):
		settings["perf_v294"] = true
		var t2 := detect_tier()
		var order := ["low", "medium", "high", "ultra", "uhd"]
		if order.find(str(settings.get("quality", "high"))) > order.find(t2):
			apply_preset(t2)
			settings["auto_tier"] = t2
		save_settings.call_deferred()
	if not bool(settings.get("perf_v28", false)):
		var tier := detect_tier()
		apply_preset(tier)
		settings["dyn_res"] = true
		settings["perf_v28"] = true
		settings["auto_tier"] = tier
		save_settings.call_deferred()

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	apply_settings()
	settings_changed.emit()

const QUALITY_PRESETS := {
	"low": {"msaa": 0, "fxaa": true, "taa": false, "shadows": 0, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "glow": false, "volumetric": false, "resolution_scale": 0.75, "draw_distance": 0.6},
	"medium": {"msaa": 0, "fxaa": true, "taa": false, "shadows": 1, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "glow": true, "volumetric": false, "resolution_scale": 1.0, "draw_distance": 0.8},
	"high": {"msaa": 0, "fxaa": true, "taa": false, "shadows": 2, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "glow": true, "volumetric": false, "resolution_scale": 1.0, "draw_distance": 1.0},
	"ultra": {"msaa": 2, "fxaa": true, "taa": false, "shadows": 3, "ssao": true, "ssil": true, "ssr": true, "sdfgi": false, "glow": true, "volumetric": true, "resolution_scale": 1.0, "draw_distance": 1.0},
	"uhd": {"msaa": 4, "fxaa": true, "taa": false, "shadows": 4, "ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "glow": true, "volumetric": true, "resolution_scale": 1.0, "draw_distance": 1.3},
}

## picks a quality preset from the graphics card (runs once per install / after the v2.7 update)
func detect_tier() -> String:
	var n := RenderingServer.get_video_adapter_name().to_lower()
	var t := RenderingServer.get_video_adapter_type()
	if t == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or t == RenderingDevice.DEVICE_TYPE_CPU or n.contains("llvmpipe") or n.contains("basic render") \
			or n.contains("intel") and not n.contains("arc"):
		return "low"
	var re := RegEx.new()
	for pat in [["rtx\\s*(40|50)\\d\\d", "ultra"], ["rtx\\s*30[6-9]0", "ultra"], ["rx\\s*(6[7-9]|7[6-9]|9[0-9])\\d\\d", "ultra"],
			["rx\\s*6[45]\\d\\d", "medium"], ["rtx\\s*30[0-5]0", "high"], ["rtx", "high"], ["gtx\\s*16\\d\\d", "medium"], ["gtx\\s*10[78]0", "high"], ["rx\\s*(5[6-7]|6[0-6]|7[0-5])\\d\\d", "high"], ["arc", "high"],
			["gtx\\s*(10[56]0|9[5-8]0)", "medium"], ["rx\\s*(4[7-8]|5[5-9])0", "medium"], ["rx\\s*5[0-5]00", "medium"], ["vega", "medium"]]:
		re.compile(pat[0])
		if re.search(n):
			return pat[1]
	return "medium" if t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU else "low"

func apply_preset(name: String) -> void:
	settings["quality"] = name
	for k in QUALITY_PRESETS[name].keys():
		settings[k] = QUALITY_PRESETS[name][k]

## screen sizes offered in Ayarlar > Ekran (only the ones that fit the monitor are listed)
const RESOLUTIONS := ["1280x720", "1366x768", "1440x900", "1600x900", "1680x1050", "1920x1080", "1920x1200", "2560x1080", "2560x1440", "3440x1440", "3840x2160"]

func window_mode() -> String:
	var m := str(settings.get("window_mode", ""))
	if m == "":
		m = "fullscreen" if bool(settings.get("fullscreen", true)) else "windowed"
	return m

func res_size() -> Vector2i:
	## the chosen resolution ("auto" = the monitor's native size)
	var scr := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var r := str(settings.get("resolution", "auto"))
	if r == "auto" or not "x" in r:
		return scr
	var p := r.split("x")
	return Vector2i(int(p[0]), int(p[1]))

## window mode + resolution + interface scale; the UI always lays out on a 1920x1080 canvas that is
## stretched (and widened/heightened, never cropped) to the window, so nothing can spill off-screen.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("editor_hint"):
		return
	var win := get_window()
	var m := window_mode()
	settings["fullscreen"] = m != "windowed"
	var scr_i := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr_i)
	var want := res_size()
	if m == "exclusive":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	elif m == "fullscreen":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if str(settings.get("resolution", "auto")) == "auto":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# never bigger than the free desktop area (taskbar excluded), centred
			var sz := Vector2i(mini(want.x, usable.size.x), mini(want.y, usable.size.y - 32))
			DisplayServer.window_set_size(sz)
			DisplayServer.window_set_position(usable.position + (usable.size - sz) / 2)
	# fullscreen at a lower resolution: render the 3D world at that size (FSR upscales), UI stays sharp
	var scr := DisplayServer.screen_get_size(scr_i)
	res_factor = 1.0
	if m != "windowed" and str(settings.get("resolution", "auto")) != "auto" and scr.y > 0:
		res_factor = clampf(float(want.y) / float(scr.y), 0.33, 1.0)
	win.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), 0.75, 1.25)

var res_factor := 1.0

func apply_settings() -> void:
	var win := get_window()
	var md := str(settings.get("mic_device", ""))
	if md != "" and md in AudioServer.get_input_device_list():
		AudioServer.input_device = md
	apply_display()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit()
	var vp := get_viewport()
	var ms := int(settings["msaa"])
	vp.msaa_3d = Viewport.MSAA_DISABLED if ms == 0 else (Viewport.MSAA_2X if ms == 2 else (Viewport.MSAA_4X if ms == 4 else Viewport.MSAA_8X))
	# SMAA keeps edges smooth without the blur of FXAA/TAA -> crisp image
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if settings["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(settings["taa"])
	vp.use_debanding = true
	var rs := float(settings["resolution_scale"]) * res_factor
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
	var sizes := [1024, 2048, 2048, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(sizes[clamp(sh, 0, 4)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][clamp(sh, 0, 4)])
	# post-process quality tiers (AO / indirect light / reflections)
	var qi: int = ["low", "medium", "high", "ultra", "uhd"].find(str(settings.get("quality", "ultra")))
	if qi < 0: qi = 3
	var rq: int = [RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH, RenderingServer.ENV_SSAO_QUALITY_ULTRA][qi]
	RenderingServer.environment_set_ssao_quality(rq, qi < 3, 0.5, 2 if qi < 3 else 3, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(rq, qi < 4, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_roughness_quality([RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH][qi])
	RenderingServer.environment_glow_set_use_bicubic_upscale(qi >= 2)
	# removes sparkling specular aliasing on metal (gun barrels, rails, roofs)
	RenderingServer.screen_space_roughness_limiter_set_active(qi >= 2, 0.25, 0.18)
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if qi < 3 else 96, 64 if qi < 3 else 96)
	RenderingServer.environment_set_volumetric_fog_filter_active(qi >= 2)
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
	"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3], "slot4": [KEY_4], "grenade": [KEY_X], "drop": [KEY_G], "spray": [KEY_T], "radio": [KEY_F1], "radio_enemy": [KEY_F2], "radio_help": [KEY_F3], "radio_ok": [KEY_F4], "inspect": [KEY_F], "voice": [KEY_V], "team_chat": [KEY_Y],
	"scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE], "chat": [KEY_ENTER], "last_weapon": [KEY_Q], "buy_menu": [KEY_B], "ping": [KEY_Z],
}
const BIND_NAMES := {
	"move_forward": "İleri", "move_back": "Geri", "move_left": "Sol", "move_right": "Sağ", "jump": "Zıpla", "crouch": "Eğil",
	"walk": "Yürü (sessiz)", "reload": "Şarjör Değiştir", "use": "Kullan", "slot1": "Ana Silah", "slot2": "Tabanca", "slot3": "Bıçak",
	"slot4": "Bomba", "grenade": "Hızlı Bomba", "inspect": "Silahı İncele", "voice": "Sesli Konuş (bas-konuş)", "team_chat": "Takım Sohbeti", "chat": "Sohbet", "scoreboard": "Skor Tablosu", "last_weapon": "Son Silah", "buy_menu": "Silah Menüsü", "ping": "İşaret Koy (takıma göster)",
	"drop": "Silahı Yere At", "spray": "Sprey Boya", "radio": "Telsiz Menüsü", "radio_enemy": "Hızlı: Düşman görüldü", "radio_help": "Hızlı: Yardım lazım", "radio_ok": "Hızlı: Anlaşıldı",
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
	# v3.8 key migration: G = drop weapon, T = spray, B = radio (old saves had grenade on G / chat on T / buy on B)
	if not settings.get("binds_v38", false):
		settings["binds_v38"] = true
		for a in ["grenade", "chat", "buy_menu"]:
			b.erase(a)
		settings["binds"] = b
	# v4.1: B = weapon menu again (as in Zula / CS), the radio lives on F1 (F2-F4 = quick call-outs)
	if not settings.get("binds_v41b", false):
		settings["binds_v41b"] = true
		for a in ["radio", "buy_menu"]:
			b.erase(a)
		settings["binds"] = b
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
	_cat_cache = {}
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
		if WEAPONS.has(wid) and not mod_weapon_model.has(wid):
			push_warning("Eklenti orijinal silahı değiştiremez: " + wid)
			continue
		var b0: Dictionary = WEAPONS[base]
		var w: Dictionary = b0.duplicate(true)
		for k in wd.keys():
			if k != "base" and k != "model":
				w[k] = wd[k]
		# balance guard: a mod weapon can never be much stronger than the weapon it is based on
		for lim in [["dmg", 1.1], ["rpm", 1.15], ["mag", 1.5], ["head", 1.0], ["range", 1.2], ["pellets", 1.0]]:
			if b0.has(lim[0]) and w.has(lim[0]):
				w[lim[0]] = min(float(w[lim[0]]), float(b0[lim[0]]) * lim[1])
				if lim[0] in ["mag", "rpm", "pellets"]:
					w[lim[0]] = int(w[lim[0]])
		for lim2 in ["spread", "ads_spread", "recoil", "hrec", "reload"]:
			if b0.has(lim2) and w.has(lim2):
				w[lim2] = max(float(w[lim2]), float(b0[lim2]) * 0.85)
		w["mod"] = true
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
## FPS limit. -1 = automatic: just under the monitor refresh rate (e.g. 141 on 144 Hz) — the GPU never queues
## frames, so frame times stay even (no micro-stutter) and input lag stays low
func fps_limit() -> int:
	var c := int(settings.get("fps_cap", -1))
	if c >= 0:
		return c
	var hz := int(round(DisplayServer.screen_get_refresh_rate()))
	if hz >= 70:
		return hz - 3
	return 0

var _wscene_cache := {}
func weapon_scene(id: String) -> PackedScene:
	var mm: Dictionary = mod_weapon_model.get(id, {})
	if mm.has("glb"):
		var ps := _load_ext_glb(mm["glb"])
		if ps:
			return ps
	var base: String = mm.get("base", str(WEAPONS.get(id, {}).get("base", id)))
	# keep loaded weapon scenes in memory: without a reference Godot frees them and reads them from disk again
	if not _wscene_cache.has(base):
		_wscene_cache[base] = load("res://assets/models/w_%s.glb" % base)
	return _wscene_cache[base]

func weapon_base(id: String) -> String:
	return str(mod_weapon_model.get(id, {}).get("base", str(WEAPONS.get(id, {}).get("base", id))))

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
		"skins": {"pembe": {"name": "Pembe Şeker", "price": 900, "rarity": 1, "color": "#ff5fb0"}},
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
