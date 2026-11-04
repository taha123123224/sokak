extends Node3D
## SABOTAJ modu: KARTAL (a) bombayı A ya da B noktasına kurar, AKREP (b) engeller / çözer.
## Turlu: ölen tur sonuna kadar bekler. İlk 6 turu alan kazanır.

const ROUND_TIME := 105.0
const BOMB_TIME := 35.0
const PLANT_T := 3.2
const DEFUSE_T := 5.0
const SITE_R := 3.6
const WIN_ROUNDS := 6
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

func setup(match_node) -> void:
	m = match_node
	_make_sites()
	ui = SabUI.new()
	ui.sab = self
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.hud.root.add_child(ui)
	_new_round(true)

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

func _site_marker(s: Dictionary) -> void:
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = SITE_R; cm.bottom_radius = SITE_R; cm.height = 0.03; cm.radial_segments = 48
	ring.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.22)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = s["pos"] + Vector3(0, 0.03, 0)
	var lb := Label3D.new()
	lb.text = s["name"]
	lb.font = UI.font("RussoOne-Regular")
	lb.font_size = 96
	lb.outline_size = 18
	lb.modulate = Color(1.0, 0.62, 0.2)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0006
	add_child(lb)
	lb.global_position = s["pos"] + Vector3(0, 3.2, 0)

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
	progress = 0.0; prog_kind = ""
	m.team_score[winner] += 1
	var mine: bool = m.player and m.player.team == winner
	m.hud.center_msg("%s  —  TURU %s KAZANDI" % [why, GS.TEAMS[winner]], UI.GREEN if mine else UI.RED)
	SFX.play("success" if mine else "fail", -4)
	for c in m.combatants:
		if "obj_goal" in c["node"]:
			c["node"].obj_goal = Vector3.INF

func on_death(victim) -> void:
	if phase == "post":
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
	if m.ended or m.paused:
		return
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
				elif not carrier.target_visible:
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
			progress = 0.0; prog_kind = ""
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
			elif not n.target_visible:
				who2 = n
			if who2:
				break
		_progress(who2, "defuse", delta)
		if prog_kind == "defuse" and progress >= DEFUSE_T:
			_end_round("b", "BOMBA ÇÖZÜLDÜ")

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
	var sab

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if sab == null or sab.m == null or sab.m.player == null:
			return
		var f: Font = UI.font("Rajdhani-Bold")
		var fr: Font = UI.font("RussoOne-Regular")
		var pl = sab.m.player
		var c := size / 2.0
		# round strip under the timer
		var rs := "TUR %d  •  İLK %d TUR" % [sab.round_no, sab.WIN_ROUNDS]
		draw_string(f, Vector2(c.x - 150, 104), rs, HORIZONTAL_ALIGNMENT_CENTER, 300, 17, Color(1, 1, 1, 0.75))
		if sab.phase == "planted":
			var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * (6.0 + 10.0 * (1.0 - sab.m.time_left / sab.BOMB_TIME)))
			var pr := Rect2(c.x - 170, 116, 340, 34)
			draw_set_transform(Vector2(pr.position.x + 170, pr.position.y), 0.0, Vector2.ONE)
			draw_colored_polygon(PackedVector2Array([Vector2(-160, 0), Vector2(170, 0), Vector2(160, 34), Vector2(-170, 34)]), Color(0.35, 0.02, 0.02, 0.75 * a + 0.2))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_string(fr, Vector2(c.x - 170, 141), "BOMBA KURULU  •  %s  •  %d sn" % [sab.planted_site, int(sab.m.time_left)], HORIZONTAL_ALIGNMENT_CENTER, 340, 19, Color(1, 0.85, 0.8, 0.6 + 0.4 * a))
		# big banner right after planting
		if sab.banner_t > 0.0:
			sab.banner_t -= get_process_delta_time()
			var k2 := clampf(sab.banner_t / 3.0, 0.0, 1.0)
			var al := minf(1.0, k2 * 3.0)
			var w := 620.0 * minf(1.0, (1.0 - k2) * 8.0 + 0.2)
			draw_rect(Rect2(c.x - w / 2, c.y - 190, w, 70), Color(0.45, 0.02, 0.02, 0.8 * al))
			draw_rect(Rect2(c.x - w / 2, c.y - 190, w, 4), Color(1, 0.3, 0.2, al))
			draw_rect(Rect2(c.x - w / 2, c.y - 124, w, 4), Color(1, 0.3, 0.2, al))
			draw_string(fr, Vector2(c.x - 310, c.y - 143), "BOMBA KURULDU  —  %s NOKTASI" % sab.planted_site, HORIZONTAL_ALIGNMENT_CENTER, 620, 36, Color(1, 1, 1, al))
		# carrier badge
		if sab.carrier == pl:
			var r := Rect2(c.x - 120, size.y - 210, 240, 34)
			draw_rect(r, Color(0.35, 0.15, 0.02, 0.85))
			draw_rect(r, Color(1, 0.55, 0.12), false, 2.0)
			var si: int = sab._near_site(pl.global_position)
			draw_string(f, r.position + Vector2(0, 24), ("E BASILI TUT: BOMBAYI KUR (%s)" % sab.sites[si]["name"]) if si >= 0 else "BOMBA SENDE  •  A / B NOKTASINA GİT", HORIZONTAL_ALIGNMENT_CENTER, 240, 17, Color.WHITE)
		elif sab.phase == "planted" and pl.team == "b" and pl.alive and pl.global_position.distance_to(sab.bomb_pos) < 1.9 and sab.prog_kind != "defuse":
			draw_string(f, Vector2(c.x - 160, size.y - 186), "E BASILI TUT: BOMBAYI ÇÖZ", HORIZONTAL_ALIGNMENT_CENTER, 320, 20, Color(0.5, 0.85, 1.0))
		# progress bar (whoever is planting / defusing, visible to the player when it is them)
		if sab.prog_kind != "" and sab.prog_who == pl:
			var total: float = sab.PLANT_T if sab.prog_kind == "plant" else sab.DEFUSE_T
			var k := clampf(sab.progress / total, 0.0, 1.0)
			var col := Color(1, 0.55, 0.12) if sab.prog_kind == "plant" else Color(0.35, 0.75, 1.0)
			var pnl := Rect2(c.x - 210, c.y + 40, 420, 150)
			draw_rect(pnl, Color(0.02, 0.025, 0.035, 0.85))
			draw_rect(pnl, Color(col.r, col.g, col.b, 0.8), false, 2.0)
			draw_string(fr, pnl.position + Vector2(0, 30), "BOMBA KURULUYOR" if sab.prog_kind == "plant" else "BOMBA ÇÖZÜLÜYOR", HORIZONTAL_ALIGNMENT_CENTER, 420, 22, col)
			if sab.prog_kind == "plant":
				# keypad display: the arming code is typed digit by digit
				var code := "1923145"
				var shown := code.substr(0, int(k * 7.0))
				var disp := Rect2(pnl.position + Vector2(60, 44), Vector2(300, 46))
				draw_rect(disp, Color(0.03, 0.08, 0.03))
				draw_rect(disp, Color(0.2, 0.5, 0.2), false, 1.5)
				var txt := ""
				for i in 7:
					txt += (shown[i] if i < shown.length() else "*") + " "
				draw_string(fr, disp.position + Vector2(0, 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 300, 30, Color(0.45, 1.0, 0.45))
			else:
				# wires: cut one after another
				var wcols := [Color(0.9, 0.15, 0.1), Color(0.95, 0.85, 0.1), Color(0.2, 0.45, 1.0)]
				for i in 3:
					var y := pnl.position.y + 56 + i * 14
					var cut := k > (i + 1) / 3.0
					if cut:
						draw_line(Vector2(pnl.position.x + 60, y), Vector2(c.x - 14, y + 4), wcols[i], 4.0)
						draw_line(Vector2(c.x + 14, y - 4), Vector2(pnl.position.x + 360, y), wcols[i], 4.0)
					else:
						draw_line(Vector2(pnl.position.x + 60, y), Vector2(pnl.position.x + 360, y), wcols[i], 4.0)
			var br := Rect2(pnl.position.x + 30, pnl.position.y + 112, 360, 12)
			draw_rect(br.grow(2), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(br.position, Vector2(br.size.x * k, br.size.y)), col)
			draw_string(f, Vector2(pnl.position.x, pnl.position.y + 143), "%.1f sn" % maxf(total - sab.progress, 0.0), HORIZONTAL_ALIGNMENT_CENTER, 420, 16, Color(1, 1, 1, 0.75))
		# dead: waiting for next round
		if not pl.alive and sab.phase != "post":
			draw_string(fr, Vector2(c.x - 300, size.y - 150), "ÖLDÜN  •  TUR SONUNU BEKLE   (Kalan: %s %d  -  %d %s)" % [GS.TEAMS["a"], sab.alive_count("a"), sab.alive_count("b"), GS.TEAMS["b"]], HORIZONTAL_ALIGNMENT_CENTER, 600, 20, Color(1, 1, 1, 0.85))
