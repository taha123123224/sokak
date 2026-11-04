extends Node3D
## Pooled visual effects: impacts, decals, tracers, blood, explosions.

var decals: Array[Decal] = []
var decal_i := 0
var tracers: Array = []
var tex := {}
var spark_mat: StandardMaterial3D
var dust_mat: StandardMaterial3D
var blood_mat: StandardMaterial3D
var blood_mist: StandardMaterial3D
var tracer_mat: StandardMaterial3D
var fire_mat: StandardMaterial3D
var smoke_mat: StandardMaterial3D
var quad: QuadMesh
var shake := 0.0

func _ready() -> void:
	for n in ["hole", "blood", "scorch", "spark", "smoke", "fire", "flash", "blood_drop", "blood_splat0", "blood_splat1", "blood_splat2"]:
		if ResourceLoader.exists("res://assets/fx/%s.png" % n):
			tex[n] = load("res://assets/fx/%s.png" % n)
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	spark_mat = _pmat(tex["spark"], Color(1, 0.8, 0.4), true, 4.0)
	dust_mat = _pmat(tex["smoke"], Color(0.55, 0.5, 0.45, 0.6), false, 0.0)
	blood_mat = _pmat(tex.get("blood_drop", tex["smoke"]), Color(1, 1, 1, 1), false, 0.0)
	blood_mist = _pmat(tex["smoke"], Color(0.5, 0.03, 0.03, 0.7), false, 0.0)
	fire_mat = _pmat(tex["fire"], Color(1, 0.7, 0.3), true, 6.0)
	smoke_mat = _pmat(tex["smoke"], Color(0.18, 0.17, 0.16, 0.85), false, 0.0)
	tracer_mat = StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.albedo_color = Color(1.0, 0.8, 0.45, 0.85)
	tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dmax := 80
	for i in dmax:
		var d := Decal.new()
		d.size = Vector3(0.12, 0.12, 0.12)
		d.texture_albedo = tex["hole"]
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.0; d.lower_fade = 0.0
		add_child(d)
		decals.append(d)

func _pmat(t: Texture2D, c: Color, add: bool, emit: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if add else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## particle bursts are pooled: an emitter with the same look is reused instead of being created + freed on every
## shot / hit (creating nodes, meshes and curves during a firefight caused hitches)
var _ppool := {}        # signature -> Array[CPUParticles3D]
var _pmesh := {}        # "mat_id:size" -> QuadMesh
var _pcurve := {}       # scale_end -> Curve

func _particles(pos: Vector3, normal: Vector3, mat: Material, amount: int, life: float, vel: float, spread: float, size: float, gravity: float, color_ramp: Gradient = null, scale_end: float = 1.0) -> void:
	var sig := "%d|%d|%.2f|%.2f|%.1f|%.3f|%.1f|%d|%.2f" % [mat.get_instance_id(), amount, life, vel, spread, size, gravity, 0 if color_ramp == null else color_ramp.get_color(0).to_rgba32(), scale_end]
	var pool: Array = _ppool.get(sig, [])
	var p: CPUParticles3D = null
	for c in pool:
		if not c.emitting:
			p = c
			break
	if p == null:
		if pool.size() >= 6:
			p = pool[0]          # all busy: steal the oldest
			pool.push_back(pool.pop_front())
		else:
			p = _new_emitter(mat, amount, life, vel, spread, size, gravity, color_ramp, scale_end)
			pool.append(p)
			_ppool[sig] = pool
	p.global_position = pos
	if normal.length() > 0.1:
		var up := Vector3.UP if abs(normal.y) < 0.95 else Vector3.RIGHT
		p.look_at(pos + normal, up)
		p.rotate_object_local(Vector3.UP, PI)
	p.restart()

func _new_emitter(mat: Material, amount: int, life: float, vel: float, spread: float, size: float, gravity: float, color_ramp: Gradient, scale_end: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	var mk := "%d:%.3f" % [mat.get_instance_id(), size]
	if not _pmesh.has(mk):
		var m := QuadMesh.new()
		m.size = Vector2(size, size)
		m.material = mat
		_pmesh[mk] = m
	p.mesh = _pmesh[mk]
	p.direction = Vector3(0, 0, 1)
	p.spread = spread
	p.initial_velocity_min = vel * 0.4
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 1.0; p.damping_max = 3.0
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.2
	if scale_end != 1.0:
		if not _pcurve.has(scale_end):
			var c := Curve.new()
			c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(1, scale_end))
			_pcurve[scale_end] = c
		p.scale_amount_curve = _pcurve[scale_end]
	if color_ramp:
		p.color_ramp = color_ramp
	p.angle_min = 0; p.angle_max = 360
	add_child(p)
	return p

## warm every effect once during the loading screen so their pipelines exist before the first shot
func prewarm() -> void:
	var far := Vector3(0, -500, 0)
	impact(far, Vector3.UP, "metal")
	impact(far, Vector3.UP)
	var g: bool = bool(GS.settings.get("blood", true))
	GS.settings["blood"] = true
	blood(far, Vector3.FORWARD)
	death_burst(far, Vector3.FORWARD, true)
	death_burst(far, Vector3.FORWARD, false)
	GS.settings["blood"] = g
	explosion(far)
	muzzle_light(far)
	tracer(far, far + Vector3(0, 0, 20))

var _ramps := {}
func _fade_ramp(c: Color) -> Gradient:
	if _ramps.has(c):
		return _ramps[c]
	var g := Gradient.new()
	_ramps[c] = g
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0))
	return g

func impact(pos: Vector3, normal: Vector3, surface: String = "concrete") -> void:
	# decal
	var d: Decal = decals[decal_i]
	decal_i = (decal_i + 1) % decals.size()
	d.visible = true
	d.texture_albedo = tex["hole"]
	d.modulate = Color(1, 1, 1, 1)
	d.size = Vector3(0.11, 0.06, 0.11)
	d.global_position = pos
	var up := Vector3.UP if abs(normal.y) < 0.95 else Vector3.FORWARD
	d.look_at(pos + normal, up)
	d.rotate_object_local(Vector3.RIGHT, -PI / 2)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	# sparks + dust
	if surface == "metal":
		_particles(pos, normal, spark_mat, 10, 0.35, 6.0, 35, 0.04, 9.0, _fade_ramp(Color(1, 0.8, 0.4)))
	else:
		_particles(pos, normal, spark_mat, 4, 0.2, 4.0, 30, 0.03, 9.0, _fade_ramp(Color(1, 0.8, 0.4)))
	_particles(pos, normal, dust_mat, 5, 0.9, 1.4, 25, 0.35, 0.3, _fade_ramp(Color(0.6, 0.55, 0.5, 0.5)), 2.5)

func _gore_on() -> bool:
	return GS.settings.get("blood", true)

func blood(pos: Vector3, dir: Vector3) -> void:
	if not _gore_on():
		return
	# entry spurt (back toward shooter) + exit spray + red mist
	_particles(pos, dir, blood_mat, 14, 0.55, 3.2, 28, 0.07, 9.8, _fade_ramp(Color(0.75, 0.05, 0.05, 1)), 0.6)
	_particles(pos, -dir, blood_mat, 18, 0.7, 4.5, 22, 0.06, 9.8, _fade_ramp(Color(0.7, 0.04, 0.04, 1)), 0.5)
	_particles(pos, -dir, blood_mist, 6, 0.6, 1.2, 40, 0.28, 0.4, _fade_ramp(Color(0.55, 0.04, 0.04, 0.55)), 2.4)

func death_burst(pos: Vector3, dir: Vector3, head: bool) -> void:
	if not _gore_on():
		return
	var n := 34 if head else 20
	_particles(pos, dir, blood_mat, n, 0.9, 5.5 if head else 3.5, 40 if head else 30, 0.09, 9.8, _fade_ramp(Color(0.72, 0.04, 0.04, 1)), 0.5)
	_particles(pos, dir, blood_mist, 10 if head else 6, 1.0, 1.6, 60, 0.45 if head else 0.35, 0.3, _fade_ramp(Color(0.5, 0.03, 0.03, 0.6)), 3.0)
	if head:
		_particles(pos, Vector3.UP, blood_mat, 12, 0.8, 3.0, 70, 0.05, 9.8, _fade_ramp(Color(0.4, 0.02, 0.02, 1)), 0.7)
	SFX.play3d("gore%d" % (randi() % 2), pos, -5 if head else -9, randf_range(0.9, 1.1), 30.0, 4.0)
	# wall splatter behind the victim
	var space := get_world_3d().direct_space_state
	for k in (3 if head else 2):
		var d := (dir + Vector3(randf_range(-0.25, 0.25), randf_range(-0.3, 0.1), randf_range(-0.25, 0.25))).normalized()
		var q := PhysicsRayQueryParameters3D.create(pos, pos + d * 3.5, 1)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			blood_decal(r["position"], r["normal"], randf_range(0.6, 1.2) * (1.3 if head else 1.0))

func blood_pool(pos: Vector3) -> void:
	if not _gore_on():
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos - Vector3(0, 2.0, 0), 1)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return
	var d := blood_decal(r["position"], r["normal"], 0.3)
	if d:
		var tw := d.create_tween()
		tw.tween_property(d, "size", Vector3(1.5, 0.4, 1.5), 4.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func blood_decal(pos: Vector3, normal: Vector3, sz: float = 0.9) -> Decal:
	if not _gore_on():
		return null
	var d: Decal = decals[decal_i]
	decal_i = (decal_i + 1) % decals.size()
	d.visible = true
	d.texture_albedo = tex.get("blood_splat%d" % (randi() % 3), tex["blood"])
	d.modulate = Color(1, 1, 1, 1)
	d.albedo_mix = 1.0
	d.size = Vector3(sz, 0.4, sz)
	d.global_position = pos
	var up := Vector3.UP if abs(normal.y) < 0.95 else Vector3.FORWARD
	d.look_at(pos + normal, up)
	d.rotate_object_local(Vector3.RIGHT, -PI / 2)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	return d

var _tracers: Array = []
var _tracer_i := 0
var _tracer_mesh: BoxMesh
func tracer(a: Vector3, b: Vector3, width: float = 0.018) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(1, 1, 1)
		_tracer_mesh.material = tracer_mat
	var mi: MeshInstance3D
	if _tracers.size() < 32:
		mi = MeshInstance3D.new()
		mi.mesh = _tracer_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tracers.append(mi)
	else:
		mi = _tracers[_tracer_i]
		_tracer_i = (_tracer_i + 1) % _tracers.size()
		if mi.has_meta("tw"):
			var otw: Tween = mi.get_meta("tw")
			if otw and otw.is_valid(): otw.kill()
	mi.visible = true
	var seg: float = min(len, 6.0)
	var dir := (b - a).normalized()
	var start := a + dir * 1.0
	mi.global_position = start + dir * seg * 0.5
	mi.look_at(b, Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT)
	mi.scale = Vector3(width, width, seg)
	var speed := 380.0
	var travel: float = max(len - 1.0 - seg * 0.5, 0.0)
	var tw := create_tween()
	tw.tween_property(mi, "global_position", mi.global_position + dir * travel, maxf(travel / speed, 0.01))
	tw.tween_callback(func(): mi.visible = false)
	mi.set_meta("tw", tw)

func explosion(pos: Vector3) -> void:
	_particles(pos + Vector3.UP * 0.3, Vector3.UP, fire_mat, 26, 0.6, 7.0, 90, 1.6, -1.0, _fade_ramp(Color(1, 0.7, 0.3)), 2.5)
	_particles(pos + Vector3.UP * 0.5, Vector3.UP, smoke_mat, 22, 3.2, 3.0, 80, 2.2, -0.4, _fade_ramp(Color(0.2, 0.19, 0.18, 0.8)), 3.5)
	_particles(pos, Vector3.UP, spark_mat, 40, 1.2, 16.0, 80, 0.06, 9.8, _fade_ramp(Color(1, 0.7, 0.3)))
	_particles(pos, Vector3.UP, dust_mat, 14, 1.5, 6.0, 90, 1.0, 2.0, _fade_ramp(Color(0.5, 0.45, 0.38, 0.6)), 3.0)
	var l := _light()
	l.light_color = Color(1, 0.65, 0.3)
	l.light_energy = 14.0
	l.omni_range = 14.0
	l.omni_attenuation = 1.0
	l.global_position = pos + Vector3.UP
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(func(): l.visible = false)
	var d: Decal = decals[decal_i]
	decal_i = (decal_i + 1) % decals.size()
	d.visible = true
	d.texture_albedo = tex["scorch"]
	d.size = Vector3(4, 1.5, 4)
	d.global_position = pos
	d.rotation = Vector3(0, randf() * TAU, 0)

var _lights: Array = []
var _light_i := 0
func _light() -> OmniLight3D:
	var l: OmniLight3D
	if _lights.size() < 6:
		l = OmniLight3D.new()
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
	else:
		l = _lights[_light_i]
		_light_i = (_light_i + 1) % _lights.size()
	l.visible = true
	return l

func muzzle_light(pos: Vector3, energy: float = 3.0) -> void:
	var l := _light()
	l.light_color = Color(1, 0.75, 0.4)
	l.light_energy = energy
	l.omni_range = 5.0
	l.omni_attenuation = 1.5
	l.global_position = pos
	var t := Time.get_ticks_msec()
	l.set_meta("t", t)
	get_tree().create_timer(0.05).timeout.connect(func(): if l.get_meta("t", 0) == t: l.visible = false)
