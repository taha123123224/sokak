extends Node3D
## v3.8 BAYRAK SAVAŞI (capture the flag): each team has a flag at its base. Grab the enemy flag, bring it to
## your own base while YOUR flag is home = 1 point. A carrier who dies drops the flag; a team-mate touching
## their own dropped flag returns it at once, otherwise it goes home after 20 s. Kills give no team points.
## Online: the room host runs the rules (it sees every puppet) and streams the state; others mirror it.

const TOUCH_R := 1.7
const RETURN_T := 20.0
const CAP_R := 2.4

var m                         # match.gd
var flags := {}               # team -> {home: Vector3, st: "home"|"carried"|"dropped", pos, ca: node, t: float, node: Node3D}
var online := false
var is_host := true
var _st_t := 0.0
var ui: Control
var caps := {}                # carrier entry name -> captures (for the scoreboard bonus)

func setup(match_node) -> void:
	m = match_node
	online = m.net != null and Net.active()
	is_host = not online or Net.is_host()
	if int(m.target_score) > 10:
		m.target_score = 3
	for t in ["a", "b"]:
		var h := _ground(_team_center(t))
		flags[t] = {"home": h, "st": "home", "pos": h, "ca": null, "t": 0.0, "node": null, "base": null}
		flags[t]["base"] = _make_base(t, h)
		flags[t]["node"] = _make_flag(t)
	ui = CtfUI.new()
	ui.ctf = self
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.hud.root.add_child(ui)
	if online:
		Net.message.connect(_on_net)
	if m.player:
		var en := "AKREP" if m.player.team == "a" else "KARTAL"
		m.hud.round_banner("BAYRAK SAVAŞI", "%s BAYRAĞINI ÇAL, KENDİ ÜSSÜNE GETİR  •  İLK %d SAYI" % [en, int(m.target_score)], UI.ACCENT2, 0, 0)

func _exit_tree() -> void:
	if online and Net.message.is_connected(_on_net):
		Net.message.disconnect(_on_net)

# ------------------------------------------------------------------ helpers
func _team_center(t: String) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for sp in m.spawn_points:
		if sp["team"] == t:
			c += sp["pos"]; n += 1
	return c / maxf(n, 1)

func _ground(p: Vector3) -> Vector3:
	var r := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 30.0, 0), 1))
	return r["position"] if not r.is_empty() else p

static func enemy(t: String) -> String:
	return "b" if t == "a" else "a"

func _id_of(n) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if n == m.player:
		return Net.my_id if online else "me"
	if "net_id" in n:
		return str(n.net_id)
	return "bot:" + str(n.name)

func _node_of(id: String):
	if id == "":
		return null
	if id == Net.my_id or id == "me":
		return m.player
	if id.begins_with("bot:"):
		for c in m.combatants:
			if is_instance_valid(c["node"]) and str(c["node"].name) == id.substr(4):
				return c["node"]
		return null
	return m.net.puppets.get(id, null) if m.net else null

static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.INF

static func _a(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

func carrying(n) -> String:
	## the team whose flag node n carries ("" when none)
	for t in flags:
		if flags[t]["st"] == "carried" and flags[t]["ca"] == n:
			return t
	return ""

# ------------------------------------------------------------------ visuals
func _mat(c: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(c.r, c.g, c.b, alpha)
	mt.roughness = 0.55
	if emit > 0.0:
		mt.emission_enabled = true; mt.emission = c; mt.emission_energy_multiplier = emit
	if alpha < 1.0:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt

func _make_base(t: String, at: Vector3) -> Node3D:
	var col: Color = GS.TEAM_COLORS[t]
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = CAP_R; cm.bottom_radius = CAP_R + 0.1; cm.height = 0.12
	pad.mesh = cm
	pad.material_override = _mat(Color(0.12, 0.13, 0.15))
	pad.position.y = 0.06
	root.add_child(pad)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = CAP_R - 0.12; tm.outer_radius = CAP_R
	ring.mesh = tm
	ring.material_override = _mat(col, 3.0)
	ring.position.y = 0.13
	ring.scale = Vector3(1, 0.3, 1)
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new(); bm.top_radius = 0.6; bm.bottom_radius = 1.1; bm.height = 26.0; bm.cap_top = false; bm.cap_bottom = false
	beam.mesh = bm
	beam.material_override = _mat(col, 1.0, 0.07)
	beam.position.y = 13.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var l := OmniLight3D.new()
	l.light_color = col; l.light_energy = 0.7; l.omni_range = 4.5
	l.position.y = 1.5
	root.add_child(l)
	return root

const CLOTH := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color;
uniform sampler2D emb : source_color, filter_linear_mipmap;
void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 6.0 - UV.x * 6.0) * 0.12 * w + sin(TIME * 3.7 - UV.x * 9.0 + UV.y * 2.0) * 0.04 * w;
}
void fragment() {
	vec4 e = texture(emb, vec2(UV.x * 1.5 - 0.25, UV.y));
	float inside = step(0.0, UV.x * 1.5 - 0.25) * step(UV.x * 1.5 - 0.25, 1.0);
	vec3 c = mix(col.rgb, vec3(1.0), e.a * inside * 0.85);
	float shade = 0.75 + 0.25 * sin(TIME * 6.0 - UV.x * 6.0);
	ALBEDO = c * shade;
	EMISSION = col.rgb * 0.35;
	ROUGHNESS = 0.8;
}
"""

func _make_flag(t: String) -> Node3D:
	var col: Color = GS.TEAM_COLORS[t]
	var root := Node3D.new()
	add_child(root)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new(); pm.top_radius = 0.035; pm.bottom_radius = 0.045; pm.height = 2.6
	pole.mesh = pm
	var pmat := _mat(Color(0.78, 0.78, 0.8)); pmat.metallic = 0.8; pmat.roughness = 0.3
	pole.material_override = pmat
	pole.position.y = 1.3
	root.add_child(pole)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.07; sm.height = 0.14
	tip.mesh = sm
	tip.material_override = _mat(Color(1, 0.8, 0.3), 1.5)
	tip.position.y = 2.64
	root.add_child(tip)
	var cloth := MeshInstance3D.new()
	var qm := PlaneMesh.new(); qm.size = Vector2(1.3, 0.85); qm.subdivide_width = 16; qm.subdivide_depth = 4
	qm.orientation = PlaneMesh.FACE_Z
	cloth.mesh = qm
	var cm := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = CLOTH
	cm.shader = sh
	cm.set_shader_parameter("col", col)
	var ep := "res://assets/ui/spray/%s.png" % ("kartal" if t == "a" else "akrep")
	if ResourceLoader.exists(ep):
		cm.set_shader_parameter("emb", load(ep))
	cloth.material_override = cm
	cloth.position = Vector3(0.68, 2.12, 0)
	root.add_child(cloth)
	root.name = "Flag_" + t
	return root

func _update_visuals(delta: float) -> void:
	for t in flags:
		var f: Dictionary = flags[t]
		var n: Node3D = f["node"]
		if n == null:
			continue
		match str(f["st"]):
			"home":
				n.global_position = f["home"]
				n.rotation.y += delta * 0.4
				n.scale = Vector3.ONE
			"dropped":
				n.global_position = f["pos"]
				n.rotation.y += delta * 1.5
				n.scale = Vector3.ONE
			"carried":
				var c = f["ca"]
				if c and is_instance_valid(c):
					var yaw: float = c.yaw if "yaw" in c else c.global_rotation.y
					var back := Basis(Vector3.UP, yaw) * Vector3(0.25, 0.0, 0.32)
					n.global_position = c.global_position + back + Vector3(0, 0.55, 0)
					n.global_rotation = Vector3(0.0, yaw + PI * 0.5, 0.25)
					n.scale = Vector3.ONE * 0.75
					# the local player's own flag on the back would block the view: hide it in first person
					n.visible = not (c == m.player and not ("wolf" in c and c.wolf))
					continue
		n.visible = true

# ------------------------------------------------------------------ rules (host / offline)
func _process(delta: float) -> void:
	_update_visuals(delta)
	_update_bots()
	if m.ended or m.countdown > 0.0:
		return
	if not is_host:
		return
	for t in flags:
		var f: Dictionary = flags[t]
		if f["st"] == "dropped":
			f["t"] = float(f["t"]) - delta
			if f["t"] <= 0.0:
				_return_flag(t, "")
		if f["st"] == "carried" and (f["ca"] == null or not is_instance_valid(f["ca"]) or not f["ca"].alive):
			_drop_flag(t, f["ca"].global_position if f["ca"] and is_instance_valid(f["ca"]) else f["home"])
	for c in m.combatants:
		var n = c["node"]
		if n == null or not is_instance_valid(n) or not n.alive or not ("team" in n):
			continue
		if "wolf" in n and n.wolf:
			continue
		var tm: String = n.team
		var en := enemy(tm)
		var p: Vector3 = n.global_position
		var ef: Dictionary = flags[en]
		var of: Dictionary = flags[tm]
		# grab the enemy flag (from their base or from the ground)
		if ef["st"] != "carried" and p.distance_to(ef["pos"] if ef["st"] == "dropped" else ef["home"]) < TOUCH_R:
			_take_flag(en, n)
		# touch your own dropped flag: it goes home
		if of["st"] == "dropped" and p.distance_to(of["pos"]) < TOUCH_R:
			_return_flag(tm, c["name"])
		# capture: carrying the enemy flag, standing on your base, your flag at home
		if ef["st"] == "carried" and ef["ca"] == n and of["st"] == "home" and p.distance_to(of["home"]) < CAP_R:
			_capture(tm, n, c)
	if online:
		_st_t -= delta
		if _st_t <= 0.0:
			_st_t = 0.2
			_send_state()

func _take_flag(t: String, n) -> void:
	var f: Dictionary = flags[t]
	f["st"] = "carried"; f["ca"] = n
	_event("take", t, _name_of(n))

func _drop_flag(t: String, pos: Vector3) -> void:
	var f: Dictionary = flags[t]
	f["st"] = "dropped"; f["ca"] = null
	f["pos"] = _ground(pos)
	f["t"] = RETURN_T
	_event("drop", t, "")

func _return_flag(t: String, who: String) -> void:
	var f: Dictionary = flags[t]
	f["st"] = "home"; f["ca"] = null; f["pos"] = f["home"]
	_event("return", t, who)

func _capture(tm: String, n, c: Dictionary) -> void:
	var en := enemy(tm)
	flags[en]["st"] = "home"; flags[en]["ca"] = null; flags[en]["pos"] = flags[en]["home"]
	m.team_score[tm] += 1
	c["score"] = int(c["score"]) + 300
	caps[c["name"]] = int(caps.get(c["name"], 0)) + 1
	_event("cap", tm, _name_of(n))
	m._check_win()

func _name_of(n) -> String:
	var e: Dictionary = m.entry(n) if n else {}
	return str(e.get("name", "?"))

func on_death(victim) -> void:
	if not is_host:
		return
	var t := carrying(victim)
	if t != "":
		_drop_flag(t, victim.global_position)

# ------------------------------------------------------------------ events (banners + sounds)
func _event(kind: String, t: String, who: String) -> void:
	_show_event(kind, t, who)
	if online and is_host:
		Net.send({"t": "ctfe", "k": kind, "f": t, "w": who})

func _show_event(kind: String, t: String, who: String) -> void:
	if m.player == null:
		return
	var mine: bool = t == str(m.player.team)            # it is about MY flag
	var col: Color = GS.TEAM_COLORS.get(t, UI.ACCENT)
	match kind:
		"take":
			m.hud.center_msg(("BAYRAĞIMIZ ALINDI!  %s" if mine else "%s DÜŞMAN BAYRAĞINI ALDI!") % who, Color(1, 0.35, 0.3) if mine else Color(0.4, 1, 0.55))
			SFX.play("fail" if mine else "beep_go", -4)
		"drop":
			m.hud.center_msg("BAYRAĞIMIZ YERE DÜŞTÜ — GERİ AL!" if mine else "DÜŞMAN BAYRAĞI YERDE!", col.lightened(0.3))
			SFX.play("beep", -6)
		"return":
			m.hud.center_msg("BAYRAĞIMIZ ÜSSE DÖNDÜ" if mine else "DÜŞMAN BAYRAĞI ÜSSÜNE DÖNDÜ", col.lightened(0.3))
			SFX.play("equip", -6)
		"cap":
			var us: bool = t == m.player.team
			m.hud.round_banner(("SAYI!  %s BAYRAĞI GETİRDİ" % who) if us else ("%s SAYI ALDI" % GS.TEAMS.get(t, "")), "%d  —  %d" % [int(m.team_score["a"]), int(m.team_score["b"])], col, int(m.team_score["a"]), int(m.team_score["b"]))
			SFX.play("success" if us else "fail", -2)

# ------------------------------------------------------------------ online
func _send_state() -> void:
	var fl := {}
	for t in flags:
		var f: Dictionary = flags[t]
		fl[t] = {"st": f["st"], "p": _a(f["pos"]), "ca": _id_of(f["ca"]), "t": snappedf(float(f["t"]), 0.1)}
	Net.send({"t": "ctf", "fl": fl, "sa": int(m.team_score["a"]), "sb": int(m.team_score["b"])})

func _on_net(d: Dictionary) -> void:
	if is_host or str(d.get("from", "")) != Net.host_id:
		return
	match str(d.get("t", "")):
		"ctf":
			var fl: Dictionary = d.get("fl", {})
			for t in fl:
				if not flags.has(t):
					continue
				var s: Dictionary = fl[t]
				flags[t]["st"] = str(s.get("st", "home"))
				var p := _v(s.get("p", []))
				if p != Vector3.INF:
					flags[t]["pos"] = p
				flags[t]["ca"] = _node_of(str(s.get("ca", "")))
				flags[t]["t"] = float(s.get("t", 0.0))
				if flags[t]["st"] == "carried" and flags[t]["ca"] == null:
					flags[t]["st"] = "dropped"   # carrier unknown here (host bot): show it at the last spot
			m.team_score["a"] = int(d.get("sa", 0)); m.team_score["b"] = int(d.get("sb", 0))
		"ctfe":
			_show_event(str(d.get("k", "")), str(d.get("f", "a")), str(d.get("w", "")))

# ------------------------------------------------------------------ bots: attack / escort / defend / chase
var _bot_t := 0.0
func _update_bots() -> void:
	_bot_t -= get_process_delta_time()
	if _bot_t > 0.0:
		return
	_bot_t = 0.5
	var idx := {"a": 0, "b": 0}
	for c in m.combatants:
		var n = c["node"]
		if n == null or not is_instance_valid(n) or n == m.player or not ("obj_goal" in n) or not n.alive:
			continue
		if "puppet" in n and n.puppet:
			continue
		var tm: String = n.team
		var en := enemy(tm)
		var ef: Dictionary = flags[en]
		var of: Dictionary = flags[tm]
		var i: int = idx[tm]
		idx[tm] = i + 1
		var goal := Vector3.INF
		if ef["st"] == "carried" and ef["ca"] == n:
			goal = of["home"]                                   # run it home
		elif of["st"] == "carried" and of["ca"] and is_instance_valid(of["ca"]):
			goal = of["ca"].global_position                     # hunt our flag carrier
		elif of["st"] == "dropped":
			goal = of["pos"]                                    # pick our flag back up
		elif i % 3 == 2:
			# defenders hold around our base
			var a := float(hash(str(n.name)) % 628) / 100.0
			goal = of["home"] + Vector3(cos(a), 0, sin(a)) * 5.0
		elif ef["st"] == "carried" and ef["ca"] and is_instance_valid(ef["ca"]):
			goal = ef["ca"].global_position                     # escort our carrier
		else:
			goal = ef["pos"] if ef["st"] == "dropped" else ef["home"]
		n.obj_goal = goal

# ------------------------------------------------------------------ HUD: flag status + on-screen markers
class CtfUI extends Control:
	var ctf
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if ctf == null or ctf.m == null or ctf.m.player == null:
			return
		var f: Font = UI.font("Rajdhani-Bold")
		var w := size.x
		var cam: Camera3D = get_viewport().get_camera_3d()
		# status strip under the score
		var i := 0
		for t in ["a", "b"]:
			var fl: Dictionary = ctf.flags[t]
			var col: Color = GS.TEAM_COLORS[t]
			var st := str(fl["st"])
			var txt := "ÜSTE" if st == "home" else ("ALINDI" if st == "carried" else "YERDE %d" % int(ceil(float(fl["t"]))))
			var x := w * 0.5 + (-150.0 if t == "a" else 30.0)
			var r := Rect2(x, 78, 120, 24)
			draw_rect(r, Color(0.02, 0.025, 0.035, 0.7))
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), col)
			var warn := st != "home"
			var tc := Color(1, 0.85, 0.5) if warn else Color(1, 1, 1, 0.85)
			if warn and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4:
				tc = col.lightened(0.4)
			_flag_icon(Vector2(x + 18, 90), col, 0.8)
			draw_string(f, Vector2(x + 32, 96), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tc)
			i += 1
		# markers on screen (flags and bases)
		if cam == null:
			return
		for t in ["a", "b"]:
			var fl2: Dictionary = ctf.flags[t]
			var col2: Color = GS.TEAM_COLORS[t]
			var wp: Vector3 = fl2["pos"] if fl2["st"] == "dropped" else fl2["home"]
			if fl2["st"] == "carried" and fl2["ca"] and is_instance_valid(fl2["ca"]):
				if fl2["ca"] == ctf.m.player:
					continue
				wp = fl2["ca"].global_position
			wp += Vector3(0, 3.0, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			sp.x = clampf(sp.x, 30, w - 30); sp.y = clampf(sp.y, 60, size.y - 60)
			var dist := int(cam.global_position.distance_to(wp))
			_flag_icon(sp, col2, 1.2)
			var lbl := "%dm" % dist
			var lw := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(f, sp + Vector2(-lw * 0.5, 26), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
			var mine: bool = (t == str(ctf.m.player.team))
			var tag := ""
			if fl2["st"] == "carried":
				tag = "KURTAR" if mine else "KORU"
			elif fl2["st"] == "dropped":
				tag = "GERİ AL" if mine else "AL"
			elif not mine:
				tag = "ÇAL"
			if tag != "":
				var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				draw_string(f, sp + Vector2(-tw * 0.5, -18), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col2.lightened(0.35))
		# you carry the flag
		if ctf.carrying(ctf.m.player) != "":
			var msg := "BAYRAK SENDE!  Kendi üssüne götür"
			var mw := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_rect(Rect2(w * 0.5 - mw * 0.5 - 16, size.y - 250, mw + 32, 32), Color(0.02, 0.025, 0.035, 0.7))
			draw_string(f, Vector2(w * 0.5 - mw * 0.5, size.y - 227), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.4))
	func _flag_icon(c: Vector2, col: Color, s: float) -> void:
		draw_line(c + Vector2(-6, 10) * s, c + Vector2(-6, -11) * s, Color(0.9, 0.9, 0.92), 2.0 * s)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -11) * s, c + Vector2(9, -7) * s, c + Vector2(-5, -2) * s]), col)
