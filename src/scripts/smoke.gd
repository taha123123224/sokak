## CS2-style smoke grenade cloud.
## Forward+ with volumetric fog: a FogVolume whose density is a noise field (fog shader) — the engine raymarches it,
## so the smoke fills the space, is lit by the sun, blocks sight properly and bullets flying through it leave no
## holes. The cloud blooms over ~1.2 s, holds ~14 s and thins out over ~4 s.
## Low settings / no volumetric fog: a billboard particle cloud stands in (same radius and timing).
## Bots and the line-of-sight checks treat the sphere as opaque while it is dense.
extends Node3D

const RADIUS := 4.2
const BLOOM := 1.2
const HOLD := 14.0
const FADE := 4.0

var match_node
var t := 0.0
var fog: FogVolume
var fog_mat: ShaderMaterial
var cloud: GPUParticles3D
var cloud_mat: ParticleProcessMaterial
var light: OmniLight3D

static var _shader: Shader
static var _noise: NoiseTexture3D

func _ready() -> void:
	if match_node and "smokes" in match_node:
		match_node.smokes.append(self)
	var e: Environment = match_node.world_env.environment if match_node and match_node.world_env else null
	var vol := e != null and e.volumetric_fog_enabled
	if vol:
		_make_fog()
	else:
		_make_particles()
	# faint light bounce inside the cloud (the sun lights the fog itself; this lifts the ground under it)
	light = OmniLight3D.new()
	light.light_color = Color(0.95, 0.96, 1.0)
	light.light_energy = 0.0
	light.omni_range = RADIUS * 1.3
	light.shadow_enabled = false
	light.light_specular = 0.0
	add_child(light)
	set_process(true)

func _make_fog() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type fog;
uniform sampler3D noise_tex : repeat_enable;
uniform float radius = 4.2;
uniform float grow = 0.0;      // 0..1 cloud size
uniform float dens = 1.0;      // overall density 0..1
uniform float t = 0.0;
void fog() {
	vec3 p = (WORLD_POSITION - OBJECT_POSITION);
	float r = radius * grow;
	// wider than tall, sitting on the ground
	vec3 q = p * vec3(1.0, 1.3, 1.0);
	// billowy edge: two octaves of 3D noise push the boundary in and out (cauliflower lumps)
	float n = texture(noise_tex, p * 0.11 + vec3(t * 0.02, t * 0.03, 0.0)).r;
	float n2 = texture(noise_tex, p * 0.31 - vec3(0.0, t * 0.05, t * 0.02)).r;
	float d = length(q) / max(r, 0.01) + (n - 0.5) * 0.7 + (n2 - 0.5) * 0.3;
	float edge = 1.0 - smoothstep(0.62, 0.98, d);
	float body = 0.55 + 0.45 * mix(n, n2, 0.4);
	DENSITY = edge * body * dens * 9.0;
	ALBEDO = vec3(0.72, 0.76, 0.84);
	EMISSION = vec3(0.05, 0.052, 0.058);
}
"""
	if _noise == null:
		_noise = NoiseTexture3D.new()
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.08
		fn.fractal_octaves = 3
		_noise.noise = fn
		_noise.width = 48; _noise.height = 48; _noise.depth = 48
		_noise.seamless = true
	fog = FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fog.size = Vector3.ONE * RADIUS * 2.4
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = _shader
	fog_mat.set_shader_parameter("noise_tex", _noise)
	fog_mat.set_shader_parameter("radius", RADIUS)
	fog_mat.set_shader_parameter("grow", 0.05)
	fog_mat.set_shader_parameter("dens", 1.0)
	fog.material = fog_mat
	add_child(fog)
	fog.position = Vector3(0, RADIUS * 0.42, 0)

func _make_particles() -> void:
	cloud = GPUParticles3D.new()
	cloud.amount = 150
	cloud.lifetime = 8.0
	cloud.explosiveness = 0.55     # a big initial puff, then a steady top-up
	cloud.randomness = 0.6
	cloud.fixed_fps = 24
	cloud.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	cloud_mat = ParticleProcessMaterial.new()
	cloud_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cloud_mat.emission_sphere_radius = RADIUS * 0.35
	cloud_mat.direction = Vector3.UP
	cloud_mat.spread = 180.0
	cloud_mat.initial_velocity_min = 0.3
	cloud_mat.initial_velocity_max = 1.1
	cloud_mat.gravity = Vector3(0, 0.08, 0)
	cloud_mat.damping_min = 0.4; cloud_mat.damping_max = 0.8
	cloud_mat.scale_min = 3.2; cloud_mat.scale_max = 4.6
	cloud_mat.angle_min = -180; cloud_mat.angle_max = 180
	cloud_mat.angular_velocity_min = -12; cloud_mat.angular_velocity_max = 12
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.45)); sc.add_point(Vector2(0.15, 1.0)); sc.add_point(Vector2(1, 1.2))
	var sct := CurveTexture.new(); sct.curve = sc
	cloud_mat.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.9, 0.92, 0.0), Color(0.8, 0.82, 0.86, 0.95), Color(0.76, 0.78, 0.82, 0.92), Color(0.8, 0.8, 0.84, 0.0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	cloud_mat.color_ramp = gt
	cloud.process_material = cloud_mat
	var qm := QuadMesh.new(); qm.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_texture = match_node.fx.tex["smoke"] if match_node and match_node.fx and match_node.fx.tex.has("smoke") else null
	sm.roughness = 1.0
	sm.disable_receive_shadows = false
	sm.proximity_fade_enabled = true; sm.proximity_fade_distance = 1.2
	qm.material = sm
	cloud.draw_pass_1 = qm
	cloud.position = Vector3(0, 1.6, 0)
	add_child(cloud)
	cloud.emitting = true

## 0..1 how much the cloud blocks sight right now
func opacity() -> float:
	if t < BLOOM:
		return clampf(t / BLOOM, 0.0, 1.0)
	if t < BLOOM + HOLD:
		return 1.0
	return clampf(1.0 - (t - BLOOM - HOLD) / FADE, 0.0, 1.0)

func radius_now() -> float:
	return RADIUS * (0.3 + 0.7 * clampf(t / BLOOM, 0.0, 1.0))

## does the segment a->b pass through the dense part of the cloud?
func blocks(a: Vector3, b: Vector3) -> bool:
	if opacity() < 0.35:
		return false
	var c := global_position + Vector3(0, RADIUS * 0.42, 0)
	var ab := b - a
	var l2 := ab.length_squared()
	var tt := 0.0 if l2 < 0.0001 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	var r := radius_now() * 0.8
	return (a + ab * tt).distance_squared_to(c) < r * r

func _process(delta: float) -> void:
	t += delta
	var op := opacity()
	var g := clampf(t / BLOOM, 0.0, 1.0)
	g = 1.0 - pow(1.0 - g, 2.2)      # fast bloom, soft settle
	if fog_mat:
		fog_mat.set_shader_parameter("grow", maxf(g, 0.05))
		fog_mat.set_shader_parameter("dens", op)
		fog_mat.set_shader_parameter("t", t)
	if cloud_mat:
		cloud_mat.emission_sphere_radius = RADIUS * (0.35 + 0.4 * g)
		if t > BLOOM + HOLD - 2.0 and cloud and cloud.emitting:
			cloud.emitting = false
	if light:
		light.light_energy = 0.35 * op
	if t > BLOOM + HOLD + FADE + (6.0 if cloud else 0.3):
		if match_node and "smokes" in match_node:
			match_node.smokes.erase(self)
		queue_free()
