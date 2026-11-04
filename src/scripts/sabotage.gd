extends Node3D
## SABOTAJ modu: KARTAL (a) bombayı A ya da B noktasına kurar, AKREP (b) engeller / çözer.
## Turlu: ölen tur sonuna kadar bekler. İlk 6 turu alan kazanır.

const ROUND_TIME := 105.0
const BOMB_TIME := 35.0
const PLANT_T := 3.2
const DEFUSE_T := 5.0
const SITE_R := 3.6
var WIN_ROUNDS := 6
const POST_T := 5.0

var m                         # match.gd
var sites: Array = []         # [{"name": "A", "pos": Vector3}]
var round_no := 0
var phase := "pre"            # pre | live | planted | post
var post_t := 0.0
var carrier = null            # node carrying the bomb
var bomb_drop := Vector3.INF  # dropped bomb position
var planted := false
var bomb_pos := Vector3.ZERO
var target_site := 0
var progress := 0.0
var prog_kind := ""           # "plant" | "defuse" | ""
var prog_who = null
var beep_t := 0.0
var bomb_node: Node3D
var bomb_light: OmniLight3D
var ui: Control

# ---- online: the room host runs the rules and streams the state; everyone else mirrors it
var online := false
var is_host := true
var _st_t := 0.0
var _got_state := false

func setup(match_node) -> void:
	m = match_node
	WIN_ROUNDS = clampi(int(m.target_score), 3, 10) if int(m.target_score) <= 10 else 6
	online = m.net != null and Net.active()
	is_host = not online or Net.is_host()
	ui = SabUI.new()
	ui.sab = self
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.hud.root.add_child(ui)
	if online:
		Net.message.connect(_on_net)
	if is_host:
		_make_sites()
		_new_round(true)
	else:
		m.hud.center_msg("SABOTAJ  •  kurucunun turu başlatması bekleniyor...", UI.ACCENT2)

func _exit_tree() -> void:
	if online and Net.message.is_connected(_on_net):
		Net.message.disconnect(_on_net)

func _id_of(n) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if n == m.player:
		return Net.my_id
	return str(n.net_id) if "net_id" in n else ""

func _node_of(id: String):
	if id == "":
		return null
	if id == Net.my_id:
		return m.player
	return m.net.puppets.get(id, null) if m.net else null

static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.INF

static func _a(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)] if v != Vector3.INF else []

func _send_state() -> void:
	Net.send({"t": "sab", "ph": phase, "rn": round_no, "tl": snappedf(m.time_left, 0.05), "ca": _id_of(carrier),
		"bd": _a(bomb_drop), "pl": planted, "bp": _a(bomb_pos), "pk": prog_kind, "pw": _id_of(prog_who), "pg": snappedf(progress, 0.02),
		"sa": int(m.team_score["a"]), "sb": int(m.team_score["b"]), "ts": target_site, "ps": planted_site,
		"si": [_a(sites[0]["pos"]), _a(sites[1]["pos"])] if sites.size() == 2 else []})

func _on_net(d: Dictionary) -> void:
	if is_host or str(d.get("from", "")) != Net.host_id:
		return                  # only the host may drive the rounds
	match str(d.get("t", "")):
		"sab":
			_apply_state(d)
		"sabr":
			# new round: everybody respawns at their team spawn
			if m.player:
				var e: Dictionary = m.entry(m.player)
				if not e.is_empty():
					m._spawn(e, true)
			m.countdown = 0.0 if int(d.get("rn", 1)) <= 1 else 3.0
			if m.countdown > 0:
				m.hud.show_countdown()
			m.hud.center_msg("TUR %d   •   %s %d - %d %s" % [int(d.get("rn", 1)), GS.TEAMS["a"], int(d.get("sa", 0)), int(d.get("sb", 0)), GS.TEAMS["b"]], UI.ACCENT2)
			if str(d.get("ca", "")) == Net.my_id:
				m.hud.center_msg("BOMBA SENDE!  A ya da B noktasına götür, E ile kur.", UI.ACCENT)
		"sabe":
			var w := str(d.get("w", "a"))
			var mine: bool = m.player and m.player.team == w
			m.hud.center_msg("%s  —  TURU %s KAZANDI" % [str(d.get("why", "")), GS.TEAMS.get(w, "")], UI.GREEN if mine else UI.RED)
			SFX.play("success" if mine else "fail", -4)
		"sabx":
			var bp := _v(d.get("p", []))
			if bp != Vector3.INF:
				_boom_local(bp)

func _apply_state(d: Dictionary) -> void:
	var si: Array = d.get("si", [])
	if sites.is_empty() and si.size() == 2:
		sites = [{"name": "A", "pos": _v(si[0])}, {"name": "B", "pos": _v(si[1])}]
		for st in sites:
			_site_marker(st)
	_got_state = true
	var was_planted := planted
	if OS.has_environment("SABLOG") and (str(d.get("ph", "")) != phase or int(d.get("rn", 0)) != round_no):
		print("SABC phase=%s rn=%d ca=%s score=%d-%d sites=%d" % [str(d.get("ph", "")), int(d.get("rn", 0)), str(d.get("ca", "")), int(d.get("sa", 0)), int(d.get("sb", 0)), sites.size()])
	phase = str(d.get("ph", phase))
	round_no = int(d.get("rn", round_no))
	m.time_left = float(d.get("tl", m.time_left))
	carrier = _node_of(str(d.get("ca", "")))
	bomb_drop = _v(d.get("bd", []))
	planted = bool(d.get("pl", false))
	var bp := _v(d.get("bp", []))
	if bp != Vector3.INF:
		bomb_pos = bp
	prog_kind = str(d.get("pk", ""))
	prog_who = _node_of(str(d.get("pw", "")))
	progress = float(d.get("pg", 0.0))
	m.team_score["a"] = int(d.get("sa", 0)); m.team_score["b"] = int(d.get("sb", 0))
	target_site = int(d.get("ts", 0))
	planted_site = str(d.get("ps", planted_site))
	# bomb model: armed on the site, lying on the ground when dropped, gone when carried
	if planted:
		_place_bomb(bomb_pos, true)
		if not was_planted:
			banner_t = 3.0
			beep_t = 0.0
			SFX.play("beep_go", 0)
	elif bomb_drop != Vector3.INF:
		_place_bomb(bomb_drop, false)
	elif bomb_node:
		bomb_node.queue_free(); bomb_node = null

func _boom_local(pos: Vector3) -> void:
	m.fx.explosion(pos)
	SFX.play3d("explosion", pos, 6, 1.0, 300.0, 30.0)
	if m.player:
		m.player.shake = maxf(m.player.shake, 1.4)
		if m.player.alive:
			var d: float = m.player.global_position.distance_to(pos)
			if d < 14.0:
				m.player.take_damage(500.0 * (1.0 - d / 16.0), null, pos, false, "frag")
	if bomb_node:
		bomb_node.queue_free(); bomb_node = null

## is this combatant holding E right now? (remote players send it in their state packets)
func _wants_use(n) -> bool:
	if n == m.player:
		return Input.is_action_pressed("use") and m.player.alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if "puppet" in n and n.puppet:
		return bool(n.net_use)
	return not n.target_visible

# ------------------------------------------------------------------ sites
func _team_center(t: String) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for sp in m.spawn_points:
		if sp["team"] == t:
			c += sp["pos"]; n += 1
	return c / maxf(n, 1)

func _make_sites() -> void:
	var ca := _team_center("a")
	var cb := _team_center("b")
	var nav := get_world_3d().navigation_map
	var cands: Array = []
	for i in 500:
		var p := NavigationServer3D.map_get_random_point(nav, 1, false)
		if p.length() < 0.5:
			continue
		if p.y > ca.y + 1.2 or p.y > cb.y + 1.2:
			continue   # ground level only (the nav mesh also covers roofs)
		var da := p.distance_to(ca)
		var db := p.distance_to(cb)
		# on the defenders' half, but not inside their spawn
		if db < da * 0.85 and db > 9.0 and da > 18.0 and _reachable(nav, ca, p) and _reachable(nav, cb, p):
			cands.append(p)
		if cands.size() >= 80:
			break
	if cands.size() < 2:
		var mid := (ca + cb) * 0.5
		var side := (cb - ca).cross(Vector3.UP).normalized()
		cands = [mid.lerp(cb, 0.35) + side * 12.0, mid.lerp(cb, 0.35) - side * 12.0]
	var best := [cands[0], cands[1]]
	var bd := -1.0
	for i in mini(cands.size(), 120):
		for j in range(i + 1, mini(cands.size(), 120)):
			var d: float = cands[i].distance_to(cands[j])
			# far apart, and both a similar walk away for the attackers (fair rotation)
			var bal: float = absf(cands[i].distance_to(ca) - cands[j].distance_to(ca))
			var sc := d - bal * 0.6
			if sc > bd:
				bd = sc
				best = [cands[i], cands[j]]
	sites = [{"name": "A", "pos": best[0]}, {"name": "B", "pos": best[1]}]
	for s in sites:
		_site_marker(s)

func _reachable(nav: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav, NavigationServer3D.map_get_closest_point(nav, from), to, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(to) < 1.5

const SITE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.78, 0.35, 1.0);
uniform float hot = 0.0;      // 1 = bomb planted here (pulses)
uniform float dim = 0.0;      // 1 = the other site after a plant
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	float t = TIME;
	// crisp inner ring
	float ring = smoothstep(0.012, 0.0, abs(r - 0.93) - 0.012);
	// rotating dashed outer ring
	float dash = step(0.45, fract(a * 36.0 + t * 0.6));
	float outer = smoothstep(0.01, 0.0, abs(r - 0.985) - 0.008) * dash;
	// corner brackets at 4 angles
	float br = 0.0;
	for (int i = 0; i < 4; i++) {
		float ca = float(i) * 0.25 + 0.125;
		float da = abs(fract(a - ca + 0.5) - 0.5);
		br += smoothstep(0.035, 0.03, da) * smoothstep(0.02, 0.0, abs(r - 0.86) - 0.02);
	}
	// soft fill fading to the edge + expanding scan wave
	float fill = mix(0.05, 0.12, smoothstep(0.2, 0.93, r)) * step(r, 0.93);
	float wave = smoothstep(0.06, 0.0, abs(r - fract(t * 0.35) * 0.93)) * 0.18 * step(r, 0.93);
	float pulse = hot * (0.5 + 0.5 * sin(t * 7.0));
	vec3 c = mix(col.rgb, vec3(1.0, 0.18, 0.12), hot);
	ALBEDO = c;
	ALPHA = (ring * 0.95 + outer * 0.75 + br * 0.9 + fill + wave + pulse * 0.25 * step(r, 0.93)) * (1.0 - dim * 0.75);
}
"""

static func _badge_tex(letter_col: Color) -> ImageTexture:
	## hexagon badge (drawn once): dark glass inside, bright rim
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var p := (Vector2(x, y) - c) / (n * 0.5)
			# hexagon distance (pointy top)
			var q := Vector2(absf(p.x), absf(p.y))
			var d := maxf(q.x * 0.866 + q.y * 0.5, q.y)
			var col := Color(0, 0, 0, 0)
			if d < 0.78:
				col = Color(0.03, 0.035, 0.05, 0.82)
			if d >= 0.78 and d < 0.9:
				col = letter_col
			elif d >= 0.9 and d < 0.97:
				col = Color(letter_col.r, letter_col.g, letter_col.b, 0.25)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

var site_nodes := []     # per site: {"zone": ShaderMaterial, "badge": Sprite3D, "letter": Label3D, "dist": Label3D}

func _site_marker(s: Dictionary) -> void:
	var gold := Color(1.0, 0.78, 0.35)
	var zone := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SITE_R * 2.0, SITE_R * 2.0)
	zone.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = SITE_SHADER
	sm.shader = sh
	sm.set_shader_parameter("col", gold)
	zone.material_override = sm
	zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone)
	zone.global_position = s["pos"] + Vector3(0, 0.04, 0)
	# floating badge with the letter + live distance (constant size on screen, seen through walls)
	var badge := Sprite3D.new()
	badge.texture = _badge_tex(gold)
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.fixed_size = true
	badge.pixel_size = 0.0006
	badge.render_priority = 10
	add_child(badge)
	badge.global_position = s["pos"] + Vector3(0, 2.6, 0)
	var lb := Label3D.new()
	lb.text = s["name"]
	lb.font = UI.font("RussoOne-Regular")
	lb.font_size = 64
	lb.outline_size = 0
	lb.modulate = Color.WHITE
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0006
	lb.render_priority = 11
	add_child(lb)
	lb.global_position = badge.global_position
	var dl := Label3D.new()
	dl.font = UI.font("Rajdhani-Bold")
	dl.font_size = 40
	dl.outline_size = 10
	dl.outline_modulate = Color(0, 0, 0, 0.7)
	dl.modulate = Color(1, 1, 1, 0.85)
	dl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dl.no_depth_test = true
	dl.fixed_size = true
	dl.pixel_size = 0.0006
	dl.offset = Vector2(0, -90)
	dl.render_priority = 11
	add_child(dl)
	dl.global_position = badge.global_position
	site_nodes.append({"zone": sm, "badge": badge, "letter": lb, "dist": dl})

var _mk_t := 0.0
func _update_markers(delta: float) -> void:
	_mk_t -= delta
	if _mk_t > 0 or site_nodes.size() != sites.size():
		return
	_mk_t = 0.1
	var cam := get_viewport().get_camera_3d()
	for i in sites.size():
		var sn: Dictionary = site_nodes[i]
		var is_hot: bool = planted and _near_site(bomb_pos) == i
		var is_dim: bool = planted and not is_hot
		(sn["zone"] as ShaderMaterial).set_shader_parameter("hot", 1.0 if is_hot else 0.0)
		(sn["zone"] as ShaderMaterial).set_shader_parameter("dim", 1.0 if is_dim else 0.0)
		var d := 0.0
		if cam:
			d = cam.global_position.distance_to(sites[i]["pos"])
		var near := d < SITE_R + 1.0
		for k in ["badge", "letter", "dist"]:
			(sn[k] as Node3D).visible = not near and not is_dim
		(sn["dist"] as Label3D).text = ("BOMBA  %dm" % int(d)) if is_hot else "%dm" % int(d)
		(sn["badge"] as Sprite3D).modulate = Color(1, 0.35, 0.3) if is_hot else Color.WHITE

# ------------------------------------------------------------------ rounds
func alive_count(t: String) -> int:
	var n := 0
	for c in m.combatants:
		if c["team"] == t and c["node"].alive:
			n += 1
	return n

func _new_round(first: bool = false) -> void:
	round_no += 1
	planted = false
	bomb_drop = Vector3.INF
	progress = 0.0; prog_kind = ""; prog_who = null
	if bomb_node:
		bomb_node.queue_free(); bomb_node = null
	for c in m.combatants:
		m._spawn(c, true)
	var atk: Array = []
	for c in m.combatants:
		if c["team"] == "a":
			atk.append(c["node"])
	carrier = atk[randi() % atk.size()] if atk.size() > 0 else null
	if OS.has_environment("SABBOT"):
		for a0 in atk:
			if a0 != m.player:
				carrier = a0; break
	target_site = randi() % 2
	_assign_objectives()
	m.time_left = ROUND_TIME
	if not first:
		m.countdown = 3.0
		m.hud.show_countdown()
	phase = "pre"
	if OS.has_environment("SABLOG"): print("SABH new round %d carrier=%s" % [round_no, _id_of(carrier)])
	if online:
		Net.send({"t": "sabr", "rn": round_no, "ca": _id_of(carrier), "sa": int(m.team_score["a"]), "sb": int(m.team_score["b"])})
		_send_state()
	m.hud.center_msg("TUR %d   •   %s %d - %d %s" % [round_no, GS.TEAMS["a"], m.team_score["a"], m.team_score["b"], GS.TEAMS["b"]], UI.ACCENT2)
	if carrier == m.player:
		m.hud.center_msg("BOMBA SENDE!  A ya da B noktasına götür, E ile kur.", UI.ACCENT)

func _assign_objectives() -> void:
	var i := 0
	# the closest living attacker bot fetches a dropped bomb
	var picker = null
	if bomb_drop != Vector3.INF:
		var bd := 1e9
		for c in m.combatants:
			var n0 = c["node"]
			if c["team"] == "a" and n0.alive and not c["is_player"]:
				var d0: float = n0.global_position.distance_to(bomb_drop)
				if d0 < bd:
					bd = d0; picker = n0
	for c in m.combatants:
		var n = c["node"]
		if c["is_player"] or not ("obj_goal" in n):
			continue
		var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		if planted:
			n.obj_goal = bomb_pos + off * (0.0 if c["team"] == "b" and i == 0 else 1.0)
		elif c["team"] == "a":
			if n == picker:
				n.obj_goal = bomb_drop
			else:
				n.obj_goal = sites[target_site]["pos"] + (Vector3.ZERO if n == carrier else off)
		else:
			n.obj_goal = sites[i % 2]["pos"] + off * 1.4
		i += 1

func _end_round(winner: String, why: String) -> void:
	if phase == "post":
		return
	phase = "post"
	post_t = POST_T
	progress = 0.0; prog_kind = ""; prog_who = null
	m.team_score[winner] += 1
	if online:
		Net.send({"t": "sabe", "w": winner, "why": why})
		_send_state()
	var mine: bool = m.player and m.player.team == winner
	m.hud.center_msg("%s  —  TURU %s KAZANDI" % [why, GS.TEAMS[winner]], UI.GREEN if mine else UI.RED)
	SFX.play("success" if mine else "fail", -4)
	for c in m.combatants:
		if "obj_goal" in c["node"]:
			c["node"].obj_goal = Vector3.INF

func on_death(victim) -> void:
	if phase == "post" or not is_host:
		return
	if victim == carrier:
		bomb_drop = victim.global_position
		carrier = null
		_place_bomb(bomb_drop, false)
		_assign_objectives()
		if m.player and m.player.team == "a":
			m.hud.center_msg("BOMBA DÜŞTÜ!", UI.RED)
	if alive_count("b") == 0:
		_end_round("a", "TÜM AKREPLER ETKİSİZ")
	elif alive_count("a") == 0 and not planted:
		_end_round("b", "TÜM KARTALLAR ETKİSİZ")

var bomb_label: Label3D
var planted_site := ""
var banner_t := 0.0
var typed := 0

func _mat(c: Color, rough := 0.6, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c; mt.roughness = rough; mt.metallic = metal
	if emit > 0.0:
		mt.emission_enabled = true; mt.emission = c; mt.emission_energy_multiplier = emit
	return mt

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

func _place_bomb(pos: Vector3, armed: bool) -> void:
	if bomb_node == null:
		# C4-style charge: four taped cylinders, keypad/timer box with a live display, wires and a blinking LED
		bomb_node = Node3D.new()
		add_child(bomb_node)
		var olive := _mat(Color(0.28, 0.3, 0.2), 0.75)
		var tape := _mat(Color(0.05, 0.05, 0.05), 0.5)
		for i in 4:
			var cm := CylinderMesh.new(); cm.top_radius = 0.035; cm.bottom_radius = 0.035; cm.height = 0.3; cm.radial_segments = 14
			_part(bomb_node, cm, olive, Vector3(-0.105 + i * 0.07, 0.036, 0), Vector3(0, 0, PI / 2))
		for z in [-0.09, 0.09]:
			var tb := BoxMesh.new(); tb.size = Vector3(0.3, 0.08, 0.035)
			_part(bomb_node, tb, tape, Vector3(0, 0.04, z))
		var box := BoxMesh.new(); box.size = Vector3(0.17, 0.05, 0.12)
		_part(bomb_node, box, _mat(Color(0.1, 0.1, 0.11), 0.4, 0.4), Vector3(0, 0.095, -0.01))
		var scr := BoxMesh.new(); scr.size = Vector3(0.11, 0.006, 0.04)
		_part(bomb_node, scr, _mat(Color(0.02, 0.05, 0.02), 0.2), Vector3(0, 0.122, -0.035))
		for k in 9:
			var kbm := BoxMesh.new(); kbm.size = Vector3(0.022, 0.008, 0.016)
			_part(bomb_node, kbm, _mat(Color(0.6, 0.62, 0.6), 0.5), Vector3(-0.03 + (k % 3) * 0.03, 0.122, 0.01 + (k / 3) * 0.02))
		for w in [[Color(0.9, 0.1, 0.08), -0.06], [Color(0.1, 0.35, 0.95), 0.06], [Color(0.95, 0.8, 0.1), 0.0]]:
			var wm := CylinderMesh.new(); wm.top_radius = 0.004; wm.bottom_radius = 0.004; wm.height = 0.16
			_part(bomb_node, wm, _mat(w[0], 0.5), Vector3(w[1], 0.11, 0.07), Vector3(PI / 2 - 0.3, 0, 0))
		bomb_label = Label3D.new()
		bomb_label.text = "--:--"
		bomb_label.font_size = 48
		bomb_label.pixel_size = 0.0009
		bomb_label.modulate = Color(1, 0.15, 0.1)
		bomb_label.outline_size = 0
		bomb_label.shaded = false
		bomb_label.position = Vector3(0, 0.127, -0.035)
		bomb_label.rotation = Vector3(-PI / 2, 0, 0)
		bomb_node.add_child(bomb_label)
		var led := SphereMesh.new(); led.radius = 0.012; led.height = 0.024
		_part(bomb_node, led, _mat(Color(1, 0.1, 0.05), 0.3, 0.0, 4.0), Vector3(0.07, 0.125, -0.05))
		bomb_light = OmniLight3D.new()
		bomb_light.light_color = Color(1, 0.15, 0.05)
		bomb_light.omni_range = 3.5
		bomb_light.light_energy = 0.0
		bomb_light.position.y = 0.3
		bomb_node.add_child(bomb_light)
	bomb_node.global_position = pos
	bomb_node.set_meta("armed", armed)
	if bomb_label:
		bomb_label.visible = armed

# ------------------------------------------------------------------ per frame
func _near_site(p: Vector3) -> int:
	for i in sites.size():
		if p.distance_to(sites[i]["pos"]) < SITE_R:
			return i
	return -1

func _process(delta: float) -> void:
	_update_markers(delta)
	if m.ended or (m.paused and not online):
		return
	if not is_host:
		_client_tick(delta)
		return
	if online:
		_st_t -= delta
		if _st_t <= 0:
			_st_t = 0.12
			_send_state()
	if phase == "post":
		post_t -= delta
		if post_t <= 0:
			if m.team_score["a"] >= WIN_ROUNDS or m.team_score["b"] >= WIN_ROUNDS:
				phase = "done"
				m.end_match()
			else:
				_new_round()
		return
	if m.countdown > 0:
		return
	if phase == "pre":
		phase = "live"
	m.time_left = maxf(m.time_left - delta, 0.0)
	var pl = m.player
	var use_down: bool = Input.is_action_pressed("use") and pl != null and pl.alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if phase == "live":
		if m.time_left <= 0:
			_end_round("b", "SÜRE DOLDU")
			return
		# dropped bomb pickup
		if bomb_drop != Vector3.INF:
			for c in m.combatants:
				var n = c["node"]
				if c["team"] == "a" and n.alive and n.global_position.distance_to(bomb_drop) < 1.6:
					carrier = n
					bomb_drop = Vector3.INF
					if bomb_node:
						bomb_node.queue_free(); bomb_node = null
					if n == pl:
						m.hud.center_msg("BOMBAYI ALDIN!", UI.ACCENT)
					_assign_objectives()
					break
		# planting
		var who = null
		if carrier and is_instance_valid(carrier) and carrier.alive:
			var si := _near_site(carrier.global_position)
			if si >= 0:
				if carrier == pl:
					if use_down and Vector2(pl.velocity.x, pl.velocity.z).length() < 1.0:
						who = pl
				elif _wants_use(carrier):
					who = carrier
		_progress(who, "plant", delta)
		if prog_kind == "plant" and progress >= PLANT_T:
			planted = true
			bomb_pos = carrier.global_position
			carrier = null
			phase = "planted"
			m.time_left = BOMB_TIME
			beep_t = 0.0
			_place_bomb(bomb_pos, true)
			progress = 0.0; prog_kind = ""; prog_who = null
			planted_site = sites[_near_site(bomb_pos) if _near_site(bomb_pos) >= 0 else 0]["name"]
			banner_t = 3.0
			SFX.play("beep_go", 0)
			_assign_objectives()
	elif phase == "planted":
		# beeping speeds up, light blinks
		beep_t -= delta
		var rate := clampf(m.time_left / BOMB_TIME, 0.08, 1.0)
		if beep_t <= 0:
			beep_t = 0.12 + rate * 0.9
			SFX.play3d("beep", bomb_pos, -4)
			if bomb_light:
				bomb_light.light_energy = 3.0
		if bomb_light:
			bomb_light.light_energy = maxf(bomb_light.light_energy - delta * 12.0, 0.0)
		if bomb_label:
			bomb_label.text = "%02d.%d" % [int(m.time_left), int(fmod(m.time_left, 1.0) * 10.0)]
		if m.time_left <= 0:
			_explode()
			return
		var who2 = null
		for c in m.combatants:
			var n = c["node"]
			if c["team"] != "b" or not n.alive or n.global_position.distance_to(bomb_pos) > 1.9:
				continue
			if n == pl:
				if use_down:
					who2 = pl
			elif _wants_use(n):
				who2 = n
			if who2:
				break
		_progress(who2, "defuse", delta)
		if prog_kind == "defuse" and progress >= DEFUSE_T:
			_end_round("b", "BOMBA ÇÖZÜLDÜ")

## clients: no rules, only the local effects of the host's state (beeps, light, timer text, smooth progress)
func _client_tick(delta: float) -> void:
	if m.countdown <= 0 and phase in ["live", "planted"]:
		m.time_left = maxf(m.time_left - delta, 0.0)
	if prog_kind != "" and prog_who != null:
		progress += delta
		if prog_who == m.player and prog_kind == "plant":
			var dg := int(progress / PLANT_T * 7.0)
			if dg > typed and dg <= 7:
				typed = dg
				SFX.play("tick", -2, 1.0 + dg * 0.06)
	else:
		typed = 0
	if planted:
		beep_t -= delta
		var rate := clampf(m.time_left / BOMB_TIME, 0.08, 1.0)
		if beep_t <= 0:
			beep_t = 0.12 + rate * 0.9
			SFX.play3d("beep", bomb_pos, -4)
			if bomb_light:
				bomb_light.light_energy = 3.0
		if bomb_light:
			bomb_light.light_energy = maxf(bomb_light.light_energy - delta * 12.0, 0.0)
		if bomb_label:
			bomb_label.text = "%02d.%d" % [int(m.time_left), int(fmod(m.time_left, 1.0) * 10.0)]

func _progress(who, kind: String, delta: float) -> void:
	if who == null:
		if prog_kind == kind:
			progress = 0.0; prog_kind = ""; prog_who = null
			typed = 0
		return
	if prog_who != who or prog_kind != kind:
		progress = 0.0
		if who == m.player:
			SFX.play("equip", -6)
	prog_who = who
	prog_kind = kind
	progress += delta
	if who == m.player and kind == "plant":
		var dg := int(progress / PLANT_T * 7.0)
		if dg > typed and dg <= 7:
			typed = dg
			SFX.play("tick", -2, 1.0 + dg * 0.06)
	elif kind == "plant":
		typed = 0

func _explode() -> void:
	if online:
		Net.send({"t": "sabx", "p": _a(bomb_pos)})
		_boom_local(bomb_pos)
		_end_round("a", "BOMBA PATLADI")
		return
	m.fx.explosion(bomb_pos)
	SFX.play3d("explosion", bomb_pos, 6, 1.0, 300.0, 30.0)
	m.player.shake = maxf(m.player.shake, 1.4)
	for c in m.combatants:
		var n = c["node"]
		if n.alive:
			var d: float = n.global_position.distance_to(bomb_pos)
			if d < 14.0:
				n.take_damage(500.0 * (1.0 - d / 16.0), null, bomb_pos, false, "frag")
	if bomb_node:
		bomb_node.queue_free(); bomb_node = null
	_end_round("a", "BOMBA PATLADI")

# ------------------------------------------------------------------ HUD
class SabUI extends Control:
	## esports-style sabotage HUD: round pill, bomb status, progress ring at the crosshair, prompts
	var sab

	func _process(_d: float) -> void:
		queue_redraw()

	func _box(r: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), rad: int = 8) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(rad)
		if border.a > 0:
			sb.border_color = border
			sb.set_border_width_all(1)
		draw_style_box(sb, r)

	func _hex(c: Vector2, r: float, fill: Color, rim: Color) -> void:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(c + Vector2.from_angle(PI / 6.0 + i * PI / 3.0) * r)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, rim, 2.0, true)

	func _c4_icon(c: Vector2, s: float, col: Color) -> void:
		for i in 3:
			draw_rect(Rect2(c + Vector2(-s, -s * 0.55 + i * s * 0.38), Vector2(s * 2.0, s * 0.3)), col)
		draw_rect(Rect2(c + Vector2(-s * 0.35, -s * 0.8), Vector2(s * 0.7, s * 0.5)), col.darkened(0.3))

	func _draw() -> void:
		if sab == null or sab.m == null or sab.m.player == null:
			return
		var f: Font = UI.font("Rajdhani-Bold")
		var fr: Font = UI.font("RussoOne-Regular")
		var ft: Font = UI.font("Teko")
		var pl = sab.m.player
		var c := size / 2.0
		var red := Color(1.0, 0.27, 0.22)
		var gold := Color(1.0, 0.78, 0.35)
		var blue := Color(0.42, 0.78, 1.0)
		# ---- round pill under the score bar
		var rs := "TUR %d  •  İLK %d" % [sab.round_no, sab.WIN_ROUNDS]
		var rw := f.get_string_size(rs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 28
		_box(Rect2(c.x - rw / 2, 96, rw, 24), Color(0.02, 0.025, 0.035, 0.75), Color(1, 1, 1, 0.12), 12)
		draw_string(f, Vector2(c.x - rw / 2, 113), rs, HORIZONTAL_ALIGNMENT_CENTER, rw, 15, Color(1, 1, 1, 0.8))
		# ---- planted: bomb pill with countdown bar
		if sab.phase == "planted":
			var tl: float = sab.m.time_left
			var k := clampf(tl / sab.BOMB_TIME, 0.0, 1.0)
			var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * (5.0 + 12.0 * (1.0 - k)))
			var pr := Rect2(c.x - 150, 128, 300, 46)
			_box(pr, Color(0.12, 0.02, 0.02, 0.85), Color(red.r, red.g, red.b, 0.5 + 0.5 * blink), 10)
			_c4_icon(Vector2(pr.position.x + 28, pr.position.y + 23), 11, red.lerp(Color.WHITE, blink * 0.4))
			draw_string(fr, Vector2(pr.position.x + 52, pr.position.y + 30), "BOMBA  •  %s" % sab.planted_site, HORIZONTAL_ALIGNMENT_LEFT, 150, 17, Color.WHITE)
			draw_string(ft, Vector2(pr.end.x - 86, pr.position.y + 38), "%d" % int(ceil(tl)), HORIZONTAL_ALIGNMENT_RIGHT, 72, 40, red.lerp(Color.WHITE, 0.3 + blink * 0.3))
			draw_rect(Rect2(pr.position.x + 10, pr.end.y - 6, (pr.size.x - 20), 3), Color(1, 1, 1, 0.1))
			draw_rect(Rect2(pr.position.x + 10, pr.end.y - 6, (pr.size.x - 20) * k, 3), red)
		elif sab.bomb_drop != Vector3.INF and pl.team == "a":
			var dr := Rect2(c.x - 110, 128, 220, 30)
			_box(dr, Color(0.12, 0.06, 0.02, 0.85), Color(gold.r, gold.g, gold.b, 0.6), 10)
			draw_string(f, Vector2(dr.position.x, dr.position.y + 21), "⚠ BOMBA YERDE  •  %dm" % int(pl.global_position.distance_to(sab.bomb_drop)), HORIZONTAL_ALIGNMENT_CENTER, 220, 16, gold)
		# ---- big banner right after the plant
		if sab.banner_t > 0.0:
			sab.banner_t -= get_process_delta_time()
			var k2 := clampf(sab.banner_t / 3.0, 0.0, 1.0)
			var al := minf(1.0, k2 * 3.0)
			var grow := minf(1.0, (1.0 - k2) * 7.0 + 0.15)
			var w := 760.0 * grow
			var by := c.y - 210
			var pts := PackedVector2Array([Vector2(c.x - w / 2, by), Vector2(c.x + w / 2, by), Vector2(c.x + w / 2 - 24, by + 66), Vector2(c.x - w / 2 + 24, by + 66)])
			draw_polygon(pts, PackedColorArray([Color(0.4, 0.02, 0.02, 0.0), Color(0.4, 0.02, 0.02, 0.0), Color(0.5, 0.03, 0.03, 0.88 * al), Color(0.5, 0.03, 0.03, 0.88 * al)]))
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.35, by + 18), Vector2(c.x + w * 0.35, by + 18), Vector2(c.x + w * 0.35 - 16, by + 66), Vector2(c.x - w * 0.35 + 16, by + 66)]), Color(0.45, 0.03, 0.03, 0.9 * al))
			draw_rect(Rect2(c.x - w * 0.35, by + 64, w * 0.7, 3), Color(1, 0.35, 0.25, al))
			_hex(Vector2(c.x - 200, by + 42), 22, Color(0.05, 0.02, 0.02, al), Color(1, 0.5, 0.4, al))
			draw_string(fr, Vector2(c.x - 222, by + 52), sab.planted_site, HORIZONTAL_ALIGNMENT_CENTER, 44, 26, Color(1, 1, 1, al))
			draw_string(fr, Vector2(c.x - 170, by + 54), "BOMBA KURULDU", HORIZONTAL_ALIGNMENT_LEFT, 400, 32, Color(1, 1, 1, al))
		# ---- prompts (bottom centre)
		var prompt := ""
		var pcol := gold
		if sab.carrier == pl and pl.alive and sab.prog_kind == "":
			var si: int = sab._near_site(pl.global_position)
			prompt = ("[E] BASILI TUT  —  BOMBAYI KUR  (%s)" % sab.sites[si]["name"]) if si >= 0 else "BOMBA SENDE  —  A ya da B noktasına götür"
		elif sab.phase == "planted" and pl.team == "b" and pl.alive and pl.global_position.distance_to(sab.bomb_pos) < 1.9 and sab.prog_kind != "defuse":
			prompt = "[E] BASILI TUT  —  BOMBAYI ÇÖZ"
			pcol = blue
		if prompt != "":
			var pw := f.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 64
			var pr2 := Rect2(c.x - pw / 2, size.y - 214, pw, 38)
			_box(pr2, Color(0.02, 0.025, 0.035, 0.85), Color(pcol.r, pcol.g, pcol.b, 0.7), 19)
			_c4_icon(Vector2(pr2.position.x + 24, pr2.position.y + 19), 8, pcol)
			draw_string(f, Vector2(pr2.position.x + 40, pr2.position.y + 26), prompt, HORIZONTAL_ALIGNMENT_LEFT, pw - 40, 18, Color.WHITE)
		# ---- progress ring at the crosshair
		if sab.prog_kind != "" and sab.prog_who == pl:
			var total: float = sab.PLANT_T if sab.prog_kind == "plant" else sab.DEFUSE_T
			var k := clampf(sab.progress / total, 0.0, 1.0)
			var col := gold if sab.prog_kind == "plant" else blue
			var rc := c
			draw_arc(rc, 48, 0, TAU, 64, Color(0, 0, 0, 0.45), 9.0, true)
			draw_arc(rc, 48, -PI / 2, -PI / 2 + TAU * k, 64, col, 6.0, true)
			draw_arc(rc, 56, 0, TAU, 64, Color(col.r, col.g, col.b, 0.18), 1.5, true)
			var title := "KURULUYOR" if sab.prog_kind == "plant" else "ÇÖZÜLÜYOR"
			_box(Rect2(rc.x - 120, rc.y + 66, 240, 54), Color(0.02, 0.025, 0.035, 0.85), Color(col.r, col.g, col.b, 0.5), 10)
			draw_string(fr, Vector2(rc.x - 120, rc.y + 88), title, HORIZONTAL_ALIGNMENT_CENTER, 240, 17, col)
			if sab.prog_kind == "plant":
				var code := "1923145"
				var shown := int(k * 7.0)
				for i in 7:
					var cr := Rect2(rc.x - 98 + i * 28, rc.y + 96, 24, 18)
					_box(cr, Color(0.03, 0.09, 0.03) if i < shown else Color(1, 1, 1, 0.06), Color(0.3, 0.8, 0.3, 0.5) if i < shown else Color(0, 0, 0, 0), 3)
					draw_string(f, Vector2(cr.position.x, cr.position.y + 15), code[i] if i < shown else "•", HORIZONTAL_ALIGNMENT_CENTER, 24, 15, Color(0.5, 1.0, 0.5) if i < shown else Color(1, 1, 1, 0.35))
			else:
				draw_string(f, Vector2(rc.x - 120, rc.y + 112), "%.1f sn  •  hareket etme" % maxf(total - sab.progress, 0.0), HORIZONTAL_ALIGNMENT_CENTER, 240, 15, Color(1, 1, 1, 0.75))
		# ---- alive counter (dead players see who is left)
		if not pl.alive and sab.phase != "post":
			var s2 := "%s %d   —   %d %s" % [GS.TEAMS["a"], sab.alive_count("a"), sab.alive_count("b"), GS.TEAMS["b"]]
			_box(Rect2(c.x - 150, 186, 300, 28), Color(0.02, 0.025, 0.035, 0.75), Color(1, 1, 1, 0.1), 14)
			draw_string(f, Vector2(c.x - 150, 206), "HAYATTA:  " + s2, HORIZONTAL_ALIGNMENT_CENTER, 300, 15, Color(1, 1, 1, 0.85))
