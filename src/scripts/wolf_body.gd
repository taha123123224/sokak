extends Node3D
## v3.6.1 Kurt Adam: the visible wolf (third person). Loads the procedural rigged wolf (tools/wolf_model.py),
## dresses it in fur, and drives idle / run (gallop) / jump / attack / howl from its own motion,
## so the same node works for the player, bots and online puppets.

const SCALE := 1.0
const MODEL := "res://assets/models/wolf_hd.glb"   # CC-BY werewolf by Daniele De Filippis, rigged by tools/wolf_hd.py
static var _fur_mat: ShaderMaterial

var ap: AnimationPlayer
var mdl: Node3D
var _last := Vector3.ZERO
var _spd := 0.0
var _act_t := 0.0                # attack / howl in progress
var _flip := 0.0                 # double-jump flip (0..1 progress), set by the owner
var on_floor := true
var mesh_root: Node3D

func _ready() -> void:
	mdl = (load(MODEL) if ResourceLoader.exists(MODEL) else load("res://assets/models/wolf.glb")).instantiate()
	mdl.scale = Vector3.ONE * SCALE
	mesh_root = Node3D.new()      # pivot at the body centre so the flip turns around the middle
	mesh_root.position.y = 1.0 * SCALE
	add_child(mesh_root)
	mesh_root.add_child(mdl)
	mdl.position.y = -1.0 * SCALE
	for mi in mdl.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var base: Material = m.mesh.surface_get_material(si)
			if not (base is StandardMaterial3D):
				continue
			var nm := base.resource_name.to_lower()
			var mat: StandardMaterial3D = base.duplicate()
			if nm.contains("fur"):
				# hair cards: cut-out alpha, both sides, soft sheen
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.18
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.roughness = 0.85
				mat.albedo_color = Color(1.5, 1.45, 1.4)
			elif nm.contains("eye"):
				# Wolfteam-style glowing eyes
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.32, 0.06)
				mat.emission_energy_multiplier = 3.5
			else:
				# the texture is very dark: lift it a little and add a cool rim so it reads at dusk
				mat.albedo_color = Color(1.55, 1.5, 1.45)
				mat.rim_enabled = true
				mat.rim = 0.55
				mat.rim_tint = 0.35
			m.set_surface_override_material(si, mat)
	var aps := mdl.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		ap = aps[0]
		for n in ["idle", "run", "walk"]:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
	_last = global_position

## the player's own wolf gets a faint fill light so it never turns into a black silhouette against the sun
func add_fill() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.72, 0.8, 1.0)
	l.light_energy = 0.7
	l.omni_range = 4.5
	l.shadow_enabled = false
	l.light_specular = 0.2
	l.position = Vector3(0, 2.4, 1.6)
	add_child(l)

var _alt := false
func attack(heavy: bool = false) -> void:
	if ap == null:
		return
	var nm := "attack3" if heavy and ap.has_animation("attack3") else ("attack2" if _alt and ap.has_animation("attack2") else "attack")
	_alt = not _alt
	if not ap.has_animation(nm):
		return
	var sp := 1.35 if heavy else 1.45
	ap.speed_scale = 1.0
	ap.play(nm, 0.05, sp)
	_act_t = ap.get_animation(nm).length / sp - 0.06

func howl() -> void:
	if ap and ap.has_animation("howl"):
		ap.speed_scale = 1.0
		ap.play("howl", 0.12, 1.0)
		_act_t = ap.get_animation("howl").length - 0.1

func set_flip(f: float) -> void:
	_flip = f

func _process(delta: float) -> void:
	var p := global_position
	var v := (p - _last) / maxf(delta, 0.0001)
	_last = p
	var hs := Vector2(v.x, v.z).length()
	if hs > 40.0:                  # teleport / respawn
		hs = 0.0
		v = Vector3.ZERO
	_spd = lerpf(_spd, hs, minf(delta * 8.0, 1.0))
	# double-jump flip: a full forward somersault around the body's centre, eased in and out
	if _flip > 0.0:
		mesh_root.rotation.x = -TAU * (0.5 - 0.5 * cos(PI * clampf(_flip, 0.0, 1.0)))
	else:
		mesh_root.rotation.x = lerp_angle(mesh_root.rotation.x, 0.0, minf(delta * 12.0, 1.0))
	if ap == null:
		return
	_act_t = maxf(_act_t - delta, 0.0)
	if _flip > 0.0 and ap.has_animation("tuck"):
		if ap.current_animation != "tuck":
			ap.play("tuck", 0.08)
		ap.speed_scale = 0.0
		ap.seek(ap.current_animation_length * clampf(0.15 + _flip * 0.75, 0.0, 0.95), true)
		return
	if _act_t > 0.0:
		return
	if not on_floor and absf(v.y) > 0.8:
		# airborne: the jump pose follows the vertical speed (stretch up, tuck at the top, reach down)
		if ap.current_animation != "jump":
			ap.play("jump", 0.12)
		ap.speed_scale = 0.0
		ap.seek(ap.current_animation_length * clampf(0.45 - v.y / 18.0, 0.05, 0.95), true)
		return
	var want := "idle"
	var rate := 1.0
	if _spd > 4.6 or (_spd > 1.0 and not ap.has_animation("walk")):
		want = "run"
		rate = clampf(_spd / 8.5, 0.7, 1.5)
	elif _spd > 0.6:
		want = "walk"
		rate = clampf(_spd / 2.6, 0.6, 1.6)
	if ap.current_animation != want:
		ap.play(want, 0.22)
	ap.speed_scale = rate

static func _fur_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D fur : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
void fragment() {
	// triplanar fur, darker on the back, lighter on the belly and muzzle, silver rim
	vec3 w = pow(abs(ln), vec3(4.0)); w /= (w.x + w.y + w.z);
	vec3 f = texture(fur, lp.yz * 1.6).rgb * w.x + texture(fur, lp.xz * 1.6).rgb * w.y + texture(fur, lp.xy * 1.6).rgb * w.z;
	float belly = smoothstep(0.2, -0.6, ln.y);
	vec3 col = mix(vec3(0.085, 0.07, 0.065), vec3(0.36, 0.3, 0.25), belly);
	col *= 0.35 + f * 1.3;
	float stripe = smoothstep(0.7, 1.0, ln.y) * 0.35;
	ALBEDO = col * (1.0 - stripe);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.5, 0.55, 0.7) * rim * 0.12;
}
"""
	return sh
