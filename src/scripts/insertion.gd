extends Node3D
## v4.7 match insertion (PUBG-style): a CH-47 Chinook flies in over the map, you jump off the ramp,
## free-fall, the parachute opens with a jolt and you glide ~6 s down towards your spawn point;
## then a short dip to black and the match starts at the real spawn. Purely local and visual:
## the match clock is held while it plays. SPACE / ESC skips it.

const T_HELI := 2.2      # exterior shot of the helicopter
const T_FALL := 1.3      # free fall
const T_CHUTE := 6.2     # under canopy
const T_FADE := 0.35

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
var heli_speed := 32.0
var alt := 70.0
var done := false
var skip := false
var snd_heli: AudioStreamPlayer
var fade: ColorRect
var title: Label
var _yaw := 0.0
var _pitch := 0.0
var _open_t := -1.0
var _chute_start := Vector3.ZERO
var land := Vector3.ZERO

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
	# keep the flight inside the map: start over the map centre side opposite to the spawn
	alt = 40.0
	land = _find_landing()
	heli_start = land - dir * 80.0
	heli_start.y = land.y + alt
	jump_pos = Vector3.ZERO
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
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
	_build_chute()
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
	# overlay: fade + mission title
	var cl := CanvasLayer.new()
	cl.layer = 60
	add_child(cl)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 0.5)
	title = UI.lbl(GS.MAPS[m.map_id]["name"].to_upper() + "  •  İNİŞ", 34, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	title.position = Vector2(-400, -150)
	title.size = Vector2(800, 50)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	cl.add_child(title)
	var hint := UI.lbl("BOŞLUK  atla", 15, Color(1, 1, 1, 0.55), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-220, -50)
	hint.size = Vector2(190, 30)
	cl.add_child(hint)
	set_process(true)
	await finished

func _build_chute() -> void:
	## canopy: half-dome with orange/white gores + suspension lines, hangs above the camera
	chute = Node3D.new()
	add_child(chute)
	chute.visible = false
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.2; sm.height = 4.2; sm.is_hemisphere = true
	sm.radial_segments = 32; sm.rings = 8
	dome.mesh = sm
	var sh := Shader.new()
	sh.code = """shader_type spatial; render_mode cull_disabled;
	void fragment(){ float g = step(0.5, fract(UV.x * 8.0)); vec3 a = vec3(0.95, 0.42, 0.08); vec3 b = vec3(0.92, 0.9, 0.86);
	ALBEDO = mix(a, b, g) * (0.75 + 0.25 * UV.y); ROUGHNESS = 0.8; BACKLIGHT = vec3(0.35); }"""
	var mt := ShaderMaterial.new()
	mt.shader = sh
	dome.material_override = mt
	dome.scale = Vector3(1.0, 0.55, 1.0)
	dome.position = Vector3(0, 6.5, 0)
	chute.add_child(dome)
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
		chute.add_child(line)

func _unhandled_input(e: InputEvent) -> void:
	if done:
		return
	if (e is InputEventKey and e.pressed and (e.keycode == KEY_SPACE or e.keycode == KEY_ESCAPE)) or (e is InputEventMouseButton and e.pressed and t > 1.0):
		skip = true

func _process(d: float) -> void:
	if done:
		return
	t += d
	for i in rotors.size():
		rotors[i].rotate_object_local(Vector3.UP, d * (26.0 if i == 0 else -26.0))
	heli.global_position = heli_start + dir * heli_speed * t
	var t1 := T_HELI
	var t2 := T_HELI + T_FALL
	var t3 := t2 + T_CHUTE
	if skip and t < t3:
		t = t3
	if t < t1:
		# exterior: camera beside and slightly behind the helicopter, slow dolly
		var hp := heli.global_position
		var k := t / t1
		var cp := hp - dir * (16.0 - 6.0 * k) + side * (13.0 - 3.0 * k) + Vector3.UP * (4.0 - 2.0 * k)
		cam.global_position = cp
		cam.look_at(hp + Vector3.UP * 2.0 - dir * 2.0, Vector3.UP)
		title.modulate.a = clampf(t / 0.5, 0.0, 1.0)
	elif t < t2:
		if jump_pos == Vector3.ZERO:
			# jump off the rear ramp
			jump_pos = heli.global_position - dir * 9.0 + Vector3.UP * 1.0
			SFX.play("freefall", -6)
			create_tween().tween_property(title, "modulate:a", 0.0, 0.4)
		var ft := t - t1
		var p := jump_pos + dir * 9.0 * ft - Vector3.UP * (4.9 * ft * ft)
		cam.global_position = p + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.04
		# look from the helicopter down to the ground while tumbling a little
		var pitch := lerpf(-15.0, -50.0, clampf(ft / 0.6, 0.0, 1.0))
		cam.global_basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.FORWARD, deg_to_rad(sin(ft * 7.0) * 6.0))
		snd_heli.volume_db = lerpf(-4.0, -20.0, ft / T_FALL)
	elif t < t3:
		if _open_t < 0.0:
			_open_t = t
			_chute_start = cam.global_position
			chute.visible = true
			chute.scale = Vector3(0.2, 0.2, 0.2)
			create_tween().tween_property(chute, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			SFX.play("chute_open", -2)
		var ct := (t - _open_t) / T_CHUTE
		var e := 1.0 - pow(1.0 - ct, 2.0)
		var target := land + Vector3.UP * 1.8
		var p2 := _chute_start.lerp(target, e)
		# sway under the canopy
		var sway := sin((t - _open_t) * 1.6) * 0.6 * (1.0 - ct)
		p2 += side * sway
		# opening jolt: a short tug upwards
		var jt := t - _open_t
		if jt < 0.35:
			p2.y += sin(jt / 0.35 * PI) * 1.2
		cam.global_position = p2
		chute.global_position = p2 + Vector3.UP * 0.4
		chute.rotation = Vector3(0, 0, sway * 0.08)
		# look up at the canopy right after it opens, then down to the landing zone
		var look_up := 1.0 - smoothstep(0.35, 1.35, jt)
		var pitch2 := lerpf(-38.0, 62.0, look_up * smoothstep(0.0, 0.25, jt)) if jt < 1.35 else lerpf(-38.0, -12.0, smoothstep(0.6, 1.0, ct))
		cam.global_basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch2)) * Basis(Vector3.FORWARD, deg_to_rad(sway * 3.0))
		snd_heli.volume_db = lerpf(-20.0, -40.0, ct)
	else:
		_finish()

func _finish() -> void:
	done = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, T_FADE)
	await tw.finished
	cam.current = false
	snd_heli.stop()
	heli.visible = false
	chute.visible = false
	finished.emit()
	var tw2 := create_tween()
	tw2.tween_interval(0.15)
	tw2.tween_property(fade, "color:a", 0.0, 0.45)
	tw2.tween_callback(queue_free)
