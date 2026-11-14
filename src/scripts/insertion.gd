extends Node3D
## v4.7 / v4.8 match insertion (PUBG-style): a CH-47 Chinook flies in high over the map, you jump off the ramp,
## free-fall through the cloud layer (wind streaks, wider FOV, altimeter), the parachute opens with a jolt and you
## glide ~7 s down towards your spawn while your squad's canopies drift beside you; the mouse looks around.
## Then a short dip to black and the match starts at the real spawn. Purely local and visual: the match clock is
## held while it plays. SPACE / ESC skips it.

const T_HELI := 2.6      # exterior shot of the helicopter
const T_FALL := 3.0      # free fall
const T_CHUTE := 7.0     # under canopy
const T_FADE := 0.35
const ALT := 150.0       # jump altitude above the landing spot

var m                    # match.gd
var cam: Camera3D
var heli: Node3D
var rotors: Array[Node3D] = []
var chute: Node3D
var spawn := Vector3.ZERO
var dir := Vector3.FORWARD
var side := Vector3.RIGHT
var t := 0.0
var jump_pos := Vector3.ZERO
var heli_start := Vector3.ZERO
var heli_speed := 34.0
var done := false
var skip := false
var snd_heli: AudioStreamPlayer
var fade: ColorRect
var title: Label
var sub: Label
var alt_lbl: Label
var alt_bar: Control
var streaks: Control
var _yaw := 0.0
var _open_t := -1.0
var _chute_start := Vector3.ZERO
var _fall_v := Vector3.ZERO
var _fall_p := Vector3.ZERO
var land := Vector3.ZERO
var look := Vector2.ZERO           # mouse free-look offset (yaw, pitch) in degrees
var mates: Array = []              # [{node, chute, off, delay}]
var clouds: Array[MeshInstance3D] = []
var _env: Environment
var _fog0 := {}

func _find_landing() -> Vector3:
	## the spawn may be indoors (under a roof): glide to the nearest open-sky spot next to it instead,
	## the fade to black then hides the last few metres to the real spawn
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for c in m.combatants:
		if c["node"] is CollisionObject3D:
			ex.append((c["node"] as CollisionObject3D).get_rid())
	for r in [0.0, 3.0, 6.0, 9.0, 13.0, 18.0, 24.0, 30.0]:
		var n: int = 1 if float(r) == 0.0 else 16
		for i in n:
			var a := TAU * i / n
			var p: Vector3 = spawn + Vector3(cos(a), 0, sin(a)) * float(r)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 80.0, p + Vector3.DOWN * 4.0)
			q.exclude = ex
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				continue
			var hy: float = hit["position"].y
			if absf(hy - spawn.y) < 1.5:
				return Vector3(p.x, hy, p.z)
	# nothing open nearby: come down onto whatever is above the spawn
	var q2 := PhysicsRayQueryParameters3D.create(spawn + Vector3.UP * 80.0, spawn)
	q2.exclude = ex
	var h2: Dictionary = space.intersect_ray(q2)
	return (h2["position"] as Vector3) + Vector3.UP * 0.5 if not h2.is_empty() else spawn

signal finished

func play(match_node, spawn_pos: Vector3, yaw: float) -> void:
	m = match_node
	spawn = spawn_pos
	_yaw = yaw
	dir = Vector3(-sin(yaw), 0, -cos(yaw))
	side = dir.cross(Vector3.UP).normalized()
	land = _find_landing()
	# the glide covers some ground too: jump ~70 m short of the landing zone
	heli_start = land - dir * (heli_speed * T_HELI + 70.0)
	heli_start.y = land.y + ALT
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	_air_fog(true)
	# helicopter
	var ps: PackedScene = load("res://assets/models/heli_ch47.glb")
	heli = ps.instantiate()
	add_child(heli)
	for n in ["rotor_f", "rotor_r"]:
		var r := heli.find_child(n, true, false) as Node3D
		if r:
			rotors.append(r)
	heli.global_basis = Basis(Vector3.UP, atan2(-dir.z, dir.x))
	heli.global_position = heli_start
	chute = _make_chute(Color(0.95, 0.42, 0.08))
	chute.visible = false
	_make_mates()
	_make_clouds()
	# sound
	snd_heli = AudioStreamPlayer.new()
	var hs = SFX.get_stream("heli")
	if hs is AudioStreamWAV:
		hs = (hs as AudioStreamWAV).duplicate()
		hs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hs.loop_begin = 0
		hs.loop_end = int(hs.get_length() * hs.mix_rate)
	snd_heli.stream = hs
	snd_heli.volume_db = -4.0
	snd_heli.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(snd_heli)
	snd_heli.play()
	_build_overlay()
	set_process(true)
	await finished

func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 60
	add_child(cl)
	streaks = Streaks.new()
	streaks.set_anchors_preset(Control.PRESET_FULL_RECT)
	streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(streaks)
	# cinematic letterbox
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 54)
		bar.size = Vector2(0, 54)
		if not top:
			bar.position.y = -54
			bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		cl.add_child(bar)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 0.6)
	title = UI.lbl(GS.MAPS[m.map_id]["name"].to_upper(), 44, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	title.position = Vector2(-500, -190)
	title.size = Vector2(1000, 60)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	cl.add_child(title)
	sub = UI.lbl("HAVA İNDİRME  •  " + str(GS.MODES.get(m.mode, {}).get("name", "")).to_upper(), 17, Color(1.0, 0.78, 0.35), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.position = Vector2(-400, -132)
	sub.size = Vector2(800, 30)
	cl.add_child(sub)
	title.modulate.a = 0.0; sub.modulate.a = 0.0
	# altimeter on the right
	alt_bar = AltBar.new()
	alt_bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	alt_bar.position = Vector2(-110, -150)
	alt_bar.size = Vector2(80, 300)
	alt_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alt_bar.modulate.a = 0.0
	cl.add_child(alt_bar)
	var hint := UI.lbl("FARE  etrafa bak     BOŞLUK  atla", 15, Color(1, 1, 1, 0.6), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-420, -42)
	hint.size = Vector2(390, 30)
	cl.add_child(hint)

func _air_fog(on: bool) -> void:
	## up high the far terrain melts into a light haze instead of a hard horizon cut
	if m.world_env == null or m.world_env.environment == null:
		return
	_env = m.world_env.environment
	if on:
		_fog0 = {"b": _env.fog_depth_begin, "e": _env.fog_depth_end, "d": _env.fog_density, "c": _env.fog_depth_curve}
		_env.fog_depth_begin = 120.0
		_env.fog_depth_end = 2600.0
		_env.fog_density = 0.88
		_env.fog_depth_curve = 1.4
	elif not _fog0.is_empty():
		_env.fog_depth_begin = _fog0["b"]; _env.fog_depth_end = _fog0["e"]; _env.fog_density = _fog0["d"]; _env.fog_depth_curve = _fog0["c"]

func _make_chute(col: Color) -> Node3D:
	## canopy: half-dome with coloured / white gores + suspension lines, hangs above the jumper
	var ch := Node3D.new()
	add_child(ch)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.2; sm.height = 4.2; sm.is_hemisphere = true
	sm.radial_segments = 32; sm.rings = 8
	dome.mesh = sm
	var sh := Shader.new()
	sh.code = """shader_type spatial; render_mode cull_disabled;
	uniform vec3 a = vec3(0.95, 0.42, 0.08);
	void fragment(){ float g = step(0.5, fract(UV.x * 8.0)); vec3 b = vec3(0.92, 0.9, 0.86);
	ALBEDO = mix(a, b, g) * (0.75 + 0.25 * UV.y); ROUGHNESS = 0.8; BACKLIGHT = vec3(0.35); }"""
	var mt := ShaderMaterial.new()
	mt.shader = sh
	mt.set_shader_parameter("a", Vector3(col.r, col.g, col.b))
	dome.material_override = mt
	dome.scale = Vector3(1.0, 0.55, 1.0)
	dome.position = Vector3(0, 6.5, 0)
	ch.add_child(dome)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.85, 0.85, 0.8)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 12:
		var a := TAU * i / 12.0
		var top := Vector3(cos(a) * 4.1, 6.5, sin(a) * 4.1)
		var bot := Vector3(cos(a) * 0.25, 0.4, sin(a) * 0.25)
		var line := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012; cm.bottom_radius = 0.012; cm.height = top.distance_to(bot); cm.radial_segments = 4
		line.mesh = cm
		line.material_override = lm
		line.position = (top + bot) * 0.5
		line.look_at_from_position(line.position, top, Vector3.FORWARD if absf((top - bot).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP)
		line.rotate_object_local(Vector3.RIGHT, PI / 2)
		ch.add_child(line)
	return ch

func _make_mates() -> void:
	## the rest of the squad jumps right behind you (team colour canopies, small figures under them)
	var team_col := Color(0.2, 0.45, 0.95) if str(m.player.team) != "b" else Color(0.85, 0.15, 0.12)
	var body_m := StandardMaterial3D.new()
	body_m.albedo_color = Color(0.18, 0.2, 0.16)
	for i in 3:
		var root := Node3D.new()
		add_child(root)
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.28; cm.height = 1.7
		body.mesh = cm
		body.material_override = body_m
		root.add_child(body)
		var ch := _make_chute(team_col if i != 1 else Color(0.95, 0.42, 0.08))
		ch.visible = false
		var off: Vector3 = side * [-14.0, 16.0, -6.0][i] + dir * [10.0, 4.0, -12.0][i] + Vector3.UP * [-3.0, 2.0, 5.0][i]
		mates.append({"node": root, "chute": ch, "off": off, "delay": 0.25 + i * 0.3})
		root.visible = false

func _make_clouds() -> void:
	## a broken cloud layer you fall through: soft camera-facing puffs around the drop path
	var sh := Shader.new()
	sh.code = """shader_type spatial; render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
	uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
	uniform float seed = 0.0;
	uniform vec3 tint = vec3(1.0);
	void vertex(){ MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); }
	void fragment(){
		vec2 p = UV * 2.0 - 1.0;
		float n = texture(noise_tex, UV * 0.8 + seed).r * 0.6 + texture(noise_tex, UV * 2.3 - seed).r * 0.4;
		float a = smoothstep(1.0, 0.15, length(p) + (n - 0.5) * 0.9);
		ALBEDO = tint * mix(0.82, 1.05, n);
		ALPHA = a * 0.85;
	}"""
	var tex: Texture2D = MatLib.tex("macro_noise.png")
	var base_y := land.y + ALT * 0.7
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var sun_col := Color(1, 1, 1)
	for i in 34:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		var mt := ShaderMaterial.new()
		mt.shader = sh
		mt.set_shader_parameter("noise_tex", tex)
		mt.set_shader_parameter("seed", rng.randf())
		mt.set_shader_parameter("tint", Vector3(sun_col.r, sun_col.g, sun_col.b) * rng.randf_range(0.9, 1.0))
		mi.material_override = mt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(28, 70)
		mi.scale = Vector3(s, s * rng.randf_range(0.45, 0.7), 1)
		# around the fall line (from the jump point to the landing zone), some right on it
		var along := rng.randf_range(-40, 140)
		var acr := rng.randf_range(-110, 110) if i > 6 else rng.randf_range(-12, 12)
		mi.position = land - dir * along + side * acr + Vector3.UP * (base_y - land.y + rng.randf_range(-10, 10))
		add_child(mi)
		clouds.append(mi)

func _unhandled_input(e: InputEvent) -> void:
	if done:
		return
	if e is InputEventMouseMotion and t > T_HELI:
		var sens := float(GS.settings.get("sens", 1.0)) * 0.08
		look.x = clampf(look.x - e.relative.x * sens, -75.0, 75.0)
		look.y = clampf(look.y - e.relative.y * sens, -35.0, 40.0)
	if (e is InputEventKey and e.pressed and (e.keycode == KEY_SPACE or e.keycode == KEY_ESCAPE)) or (e is InputEventMouseButton and e.pressed and t > 1.0):
		skip = true

func _cam_basis(pitch: float, roll: float) -> Basis:
	return Basis(Vector3.UP, _yaw + deg_to_rad(look.x)) * Basis(Vector3.RIGHT, deg_to_rad(clampf(pitch + look.y, -88.0, 80.0))) * Basis(Vector3.FORWARD, deg_to_rad(roll))

func _process(d: float) -> void:
	if done:
		return
	if OS.has_environment("INTRO_T"):
		# test hook: step through the sequence in game time up to INTRO_T and hold that frame
		d = minf(d, 0.2)
		if t + d > float(OS.get_environment("INTRO_T")):
			d = 0.0
	t += d
	look = look.move_toward(Vector2.ZERO, d * 6.0) if t < T_HELI else look
	for i in rotors.size():
		rotors[i].rotate_object_local(Vector3.UP, d * (26.0 if i == 0 else -26.0))
	heli.global_position = heli_start + dir * heli_speed * t
	var t1 := T_HELI
	var t2 := T_HELI + T_FALL
	var t3 := t2 + T_CHUTE
	if skip and t < t3:
		t = t3
	var alt_now := 0.0
	if t < t1:
		# exterior: camera beside and slightly behind the helicopter, slow dolly, map far below
		var hp := heli.global_position
		var k := t / t1
		var cp := hp - dir * (18.0 - 8.0 * k) + side * (14.0 - 4.0 * k) + Vector3.UP * (5.0 - 3.0 * k)
		cam.global_position = cp
		cam.look_at(hp + Vector3.UP * 1.0 - dir * 3.0 + Vector3.DOWN * 6.0 * k, Vector3.UP)
		title.modulate.a = clampf(t / 0.6, 0.0, 1.0)
		sub.modulate.a = clampf((t - 0.3) / 0.6, 0.0, 1.0)
		alt_now = hp.y - land.y
	elif t < t2:
		if jump_pos == Vector3.ZERO:
			# jump off the rear ramp
			jump_pos = heli.global_position - dir * 9.0 + Vector3.UP * 0.5
			_fall_p = jump_pos
			_fall_v = dir * heli_speed * 0.5
			SFX.play("freefall", -4)
			create_tween().tween_property(title, "modulate:a", 0.0, 0.4)
			create_tween().tween_property(sub, "modulate:a", 0.0, 0.4)
			create_tween().tween_property(alt_bar, "modulate:a", 1.0, 0.4)
			for mt in mates:
				mt["node"].visible = true
		var ft := t - t1
		# real-ish free fall: gravity with a terminal velocity, forward speed bleeding off
		_fall_v.y = maxf(_fall_v.y - 9.8 * d * 1.6, -48.0)
		var hv := Vector3(_fall_v.x, 0, _fall_v.z).move_toward(dir * 6.0, d * 8.0)
		_fall_v.x = hv.x; _fall_v.z = hv.z
		_fall_p += _fall_v * d
		var sh := clampf(-_fall_v.y / 48.0, 0.0, 1.0)
		cam.global_position = _fall_p + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06 * sh
		var pitch := lerpf(-20.0, -68.0, smoothstep(0.0, 1.0, ft / 1.2))
		cam.global_basis = _cam_basis(pitch, sin(ft * 5.0) * 4.0 * sh)
		cam.fov = lerpf(70.0, 92.0, sh)
		streaks.set("k", sh)
		snd_heli.volume_db = lerpf(-4.0, -26.0, ft / T_FALL)
		alt_now = _fall_p.y - land.y
		for mt in mates:
			var tt := maxf(ft - float(mt["delay"]), 0.0)
			mt["node"].global_position = jump_pos + mt["off"] + dir * 7.0 * tt - Vector3.UP * (0.5 * 9.8 * 1.6 * minf(tt, 3.0) * minf(tt, 3.0))
			mt["node"].rotation = Vector3(deg_to_rad(70), atan2(-dir.x, -dir.z), 0)
	elif t < t3:
		if _open_t < 0.0:
			_open_t = t
			_chute_start = cam.global_position
			chute.visible = true
			chute.scale = Vector3(0.2, 0.2, 0.2)
			create_tween().tween_property(chute, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			SFX.play("chute_open", -2)
			streaks.set("k", 0.0)
			for mt in mates:
				mt["chute"].visible = true
				mt["start"] = mt["node"].global_position
				mt["chute"].scale = Vector3(0.2, 0.2, 0.2)
				create_tween().tween_property(mt["chute"], "scale", Vector3.ONE, 0.5).set_delay(float(mt["delay"]) * 0.6).set_trans(Tween.TRANS_BACK)
		var jt := t - _open_t
		var ct := jt / T_CHUTE
		var e := 1.0 - pow(1.0 - ct, 1.7)
		var target := land + Vector3.UP * 1.8
		var p2 := _chute_start.lerp(target, e)
		var sway := sin(jt * 1.5) * 0.8 * (1.0 - ct)
		p2 += side * sway
		if jt < 0.4:
			p2.y += sin(jt / 0.4 * PI) * 2.0
		cam.global_position = p2
		chute.global_position = p2 + Vector3.UP * 0.4
		chute.rotation = Vector3(0, _yaw, sway * 0.08)
		cam.fov = lerpf(cam.fov, 72.0, minf(d * 4.0, 1.0))
		# look up at the canopy right after it opens, then down to the landing zone
		var look_up := 1.0 - smoothstep(0.4, 1.5, jt)
		var pitch2 := lerpf(-40.0, 62.0, look_up * smoothstep(0.0, 0.25, jt)) if jt < 1.5 else lerpf(-40.0, -14.0, smoothstep(0.55, 1.0, ct))
		cam.global_basis = _cam_basis(pitch2, sway * 3.0)
		snd_heli.volume_db = lerpf(-26.0, -45.0, ct)
		alt_now = p2.y - land.y
		for mt in mates:
			# the squad lands spread out a bit ahead of you
			var tgt: Vector3 = land + mt["off"] * Vector3(1.6, 0, 1.6) + Vector3.UP * 1.2
			var mp: Vector3 = (mt["start"] as Vector3).lerp(tgt, minf(e * 1.05, 1.0))
			mp += side * sin(jt * 1.3 + float(mt["delay"]) * 5.0) * 0.7
			mt["node"].global_position = mp
			mt["node"].rotation = Vector3.ZERO
			mt["chute"].global_position = mp + Vector3.UP * 0.4
	else:
		_finish()
	if alt_bar:
		alt_bar.set("alt", maxf(alt_now, 0.0))
		alt_bar.set("max_alt", ALT)
		alt_bar.set("speed", -_fall_v.y if t < t2 else (6.0 if t < t3 else 0.0))

func _finish() -> void:
	done = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, T_FADE)
	await tw.finished
	_air_fog(false)
	cam.current = false
	snd_heli.stop()
	heli.visible = false
	chute.visible = false
	for mt in mates:
		mt["node"].visible = false
		mt["chute"].visible = false
	for cl in clouds:
		cl.visible = false
	streaks.visible = false
	alt_bar.visible = false
	finished.emit()
	var tw2 := create_tween()
	tw2.tween_interval(0.15)
	tw2.tween_property(fade, "color:a", 0.0, 0.45)
	tw2.tween_callback(queue_free)

class Streaks extends Control:
	## free-fall wind streaks rushing up past the edges of the screen
	var k := 0.0
	var _p: Array = []
	func _ready() -> void:
		for i in 60:
			_p.append(Vector3(randf(), randf(), randf_range(0.4, 1.0)))
	func _process(d: float) -> void:
		if k <= 0.01 and modulate.a <= 0.01:
			return
		modulate.a = move_toward(modulate.a, k, d * 3.0)
		for i in _p.size():
			var p: Vector3 = _p[i]
			p.y -= d * (1.4 + 2.4 * p.z) * maxf(k, 0.2)
			if p.y < -0.2:
				p = Vector3(randf(), 1.15, randf_range(0.4, 1.0))
			_p[i] = p
		queue_redraw()
	func _draw() -> void:
		var s := size
		for p in _p:
			var x: float = p.x
			# keep the centre clear: push streaks towards the edges
			x = 0.5 + (x - 0.5) * 1.0
			if absf(x - 0.5) < 0.18:
				continue
			var a: float = 0.08 + 0.22 * p.z
			var L: float = 60.0 + 160.0 * p.z
			draw_line(Vector2(x * s.x, p.y * s.y), Vector2(x * s.x, p.y * s.y + L), Color(1, 1, 1, a), 1.0 + p.z * 1.5, true)

class AltBar extends Control:
	## altimeter: a vertical scale with the current height and fall speed
	var alt := 0.0
	var max_alt := 150.0
	var speed := 0.0
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var h := size.y
		var x := 40.0
		draw_rect(Rect2(Vector2(x - 2, 0), Vector2(4, h)), Color(1, 1, 1, 0.18))
		var f := ThemeDB.fallback_font
		for i in 7:
			var y := h * float(i) / 6.0
			draw_line(Vector2(x - 8, y), Vector2(x + 8, y), Color(1, 1, 1, 0.35), 2.0)
		var yk := h * (1.0 - clampf(alt / maxf(max_alt, 1.0), 0.0, 1.0))
		draw_rect(Rect2(Vector2(x - 2, yk), Vector2(4, h - yk)), Color(1.0, 0.72, 0.2, 0.85))
		var tri := PackedVector2Array([Vector2(x - 14, yk - 7), Vector2(x - 4, yk), Vector2(x - 14, yk + 7)])
		draw_colored_polygon(tri, Color(1.0, 0.75, 0.25))
		draw_string(f, Vector2(x - 80, yk + 6), "%d m" % int(round(alt)), HORIZONTAL_ALIGNMENT_RIGHT, 62, 18, Color.WHITE)
		draw_string(f, Vector2(x - 40, h + 26), "YÜKSEKLİK", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(1, 1, 1, 0.7))
		if speed > 0.5:
			draw_string(f, Vector2(x - 40, h + 46), "%d km/sa" % int(speed * 3.6), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(1.0, 0.75, 0.3, 0.9))
