extends Node3D
## v3.8 communication: spray paint (T) on walls and the radio menu (B, then 1-8) with team call-outs.
## Both are sent over the network so other players see / hear them.

const SPRAYS := ["gg", "kurt", "kurukafa", "sokak", "gulme", "ayyildiz", "like", "hedef", "tac", "ez", "kalp", "kedi", "burasi", "kartal", "akrep", "pow"]
const SPRAY_NAMES := {"gg": "GG", "kurt": "Kurt", "kurukafa": "Kurukafa", "sokak": "SOKAK", "gulme": "Kahkaha", "ayyildiz": "Ay Yıldız",
	"like": "Süper", "hedef": "Hedef", "tac": "Kral", "ez": "EZ", "kalp": "Ateşli Kalp", "kedi": "Kedi", "burasi": "Burası Bizim",
	"kartal": "Kartal", "akrep": "Akrep", "pow": "POW!"}
const RADIO := [
	["Takip edin!", "follow"], ["Düşman görüldü!", "enemy"], ["Yardım lazım!", "help"], ["Bölge temiz.", "clear"],
	["Anlaşıldı.", "ok"], ["Geri çekilin!", "back"], ["Pozisyonu tutun!", "hold"], ["Teşekkürler!", "thanks"],
]
const SPRAY_CD := 8.0

var m
var _sprays: Array = []
var _spray_cd := 0.0
var radio_open := false
var _radio_ui: Control

func setup(match_node) -> void:
	m = match_node

func _process(d: float) -> void:
	_spray_cd = maxf(_spray_cd - d, 0.0)

static func my_spray() -> String:
	var s := str(GS.settings.get("spray", "gg"))
	return s if SPRAYS.has(s) else "gg"

# ---------------------------------------------------------------- spray
func try_spray() -> void:
	var p = m.player
	if p == null or not p.alive:
		return
	if _spray_cd > 0.0:
		if m.hud and m.hud.has_method("center_msg"):
			m.hud.center_msg("SPREY %d sn" % int(ceil(_spray_cd)), Color(1, 1, 1, 0.7))
		return
	var from: Vector3 = p.cam.global_position
	var to: Vector3 = from - p.cam.global_transform.basis.z * 4.5
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [p.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		if m.hud and m.hud.has_method("center_msg"):
			m.hud.center_msg("Sprey için bir duvara yaklaş", Color(1, 1, 1, 0.7))
		return
	_spray_cd = SPRAY_CD
	var id := my_spray()
	var up: Vector3 = p.cam.global_transform.basis.y
	place_spray(r["position"], r["normal"], up, id, true)
	if m.net != null:
		var pp: Vector3 = r["position"]; var nn: Vector3 = r["normal"]
		Net.send({"t": "spray", "id": id, "p": [snappedf(pp.x, 0.01), snappedf(pp.y, 0.01), snappedf(pp.z, 0.01)],
			"nr": [snappedf(nn.x, 0.01), snappedf(nn.y, 0.01), snappedf(nn.z, 0.01)], "u": [snappedf(up.x, 0.01), snappedf(up.y, 0.01), snappedf(up.z, 0.01)]})

func place_spray(pos: Vector3, nrm: Vector3, up: Vector3, id: String, mine: bool) -> void:
	if not SPRAYS.has(id):
		return
	while _sprays.size() >= 24:
		var o = _sprays.pop_front()
		if is_instance_valid(o): o.queue_free()
	var dc := Decal.new()
	dc.texture_albedo = load("res://assets/ui/spray/%s.png" % id)
	dc.size = Vector3(1.15, 0.5, 1.15)
	dc.upper_fade = 0.2
	dc.lower_fade = 0.2
	dc.normal_fade = 0.4
	dc.albedo_mix = 1.0
	dc.modulate = Color(1, 1, 1, 0.0)
	add_child(dc)
	# decal projects along its local -Y: point it into the wall, keep the picture upright
	var y := nrm.normalized()
	var x := up.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	dc.global_transform = Transform3D(Basis(x, y, z), pos + y * 0.05)
	_sprays.append(dc)
	var tw := dc.create_tween()
	tw.tween_property(dc, "modulate:a", 0.95, 0.6)
	SFX.play("spray", -6 if mine else -14)

# ---------------------------------------------------------------- radio
func toggle_radio() -> void:
	radio_open = not radio_open
	_build_radio()
	_radio_ui.visible = radio_open

func radio_key(n: int) -> bool:
	## 1..8 while the radio menu is open; returns true when it consumed the key
	if not radio_open:
		return false
	radio_open = false
	_radio_ui.visible = false
	if n < 1 or n > RADIO.size():
		return true
	send_radio(n - 1)
	return true

func send_radio(i: int) -> void:
	var p = m.player
	var msg: String = RADIO[i][0]
	var me := str(GS.profile.get("name", "Sen"))
	var my_team: String = str(p.team) if p and "team" in p else ""
	show_radio(me, msg, my_team, true)
	if m.net != null:
		Net.send({"t": "radio", "n": me, "i": i, "team": my_team if m.teams else ""})
	# call-outs with a place: mark it for the team
	var kind: String = RADIO[i][1]
	if p and (kind == "enemy" or kind == "help" or kind == "hold") and m.has_method("place_ping"):
		var pos: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if kind == "enemy":
			var q := PhysicsRayQueryParameters3D.create(p.cam.global_position, p.cam.global_position - p.cam.global_transform.basis.z * 150.0)
			q.exclude = [p.get_rid()]
			var r := get_world_3d().direct_space_state.intersect_ray(q)
			if not r.is_empty():
				pos = r["position"]
		m.place_ping(pos, me, my_team, true)

func show_radio(who: String, msg: String, tm: String, mine: bool) -> void:
	SFX.play("radio", -8 if mine else -6)
	if m.hud and m.hud.has_method("radio_toast"):
		m.hud.radio_toast(who, msg, GS.TEAM_COLORS.get(tm, UI.ACCENT) if m.teams else UI.ACCENT)

func _build_radio() -> void:
	if _radio_ui != null or m.hud == null:
		return
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 3; sb.border_color = UI.ACCENT
	sb.content_margin_left = 16; sb.content_margin_right = 18; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	pc.offset_left = 24; pc.offset_top = -160; pc.offset_right = 300
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(4)
	pc.add_child(v)
	v.add_child(UI.lbl("TELSİZ", 15, UI.ACCENT, "Rajdhani-Bold"))
	for i in RADIO.size():
		var h := UI.hbox(10)
		var k := UI.lbl(str(i + 1), 16, Color(0.05, 0.05, 0.06), "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
		k.custom_minimum_size = Vector2(24, 24)
		var ks := StyleBoxFlat.new(); ks.bg_color = Color(1, 1, 1, 0.85); ks.set_corner_radius_all(4)
		k.add_theme_stylebox_override("normal", ks)
		h.add_child(k)
		h.add_child(UI.lbl(RADIO[i][0], 18, Color.WHITE, "Rajdhani-Bold"))
		v.add_child(h)
	v.add_child(UI.lbl("[%s] kapat" % GS.bind_label("radio"), 13, Color(1, 1, 1, 0.45), "Rajdhani-SemiBold"))
	m.hud.root.add_child(pc)
	_radio_ui = pc
