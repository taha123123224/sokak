extends Node
## v3.5.1 KURT ADAM mode (Wolfteam style): every fighter charges a wolf gauge (time + kills); at 100 % the
## human can turn into a wolf (key 3 for the player, automatic for bots). The wolf is much faster, jumps higher,
## does a flip on a second jump, climbs walls, takes far less damage and kills with its claws ("pence").
## After WOLF_TIME seconds (or on death) it turns back into a human.

const WOLF_TIME := 22.0
const CHARGE_RATE := 3.2         # % per second
const KILL_CHARGE := 28.0
const DMG_TAKEN := 0.42          # wolves take 42 % of the damage
const SPEED := 1.65
const JUMP := 1.5

var host                         # player.gd or bot.gd node
var is_player := false
var energy := 0.0
var wolf := false
var wolf_t := 0.0
var prev_weapon := ""
var _auto_t := 0.0
var remote := false             # online puppet: only shows the look, the owner's game decides

func set_remote(on: bool) -> void:
	if on == wolf:
		return
	wolf = on
	host.wolf = on
	_tint(on)
	SFX.play3d("explosion" if on else "gore0", host.global_position, -8, 0.45 if on else 0.7, 40.0, 6.0)

func _process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		queue_free()
		return
	if remote:
		return
	var mn = host.match_node
	if mn == null or mn.ended:
		return
	if not host.alive:
		if wolf:
			revert(true)
		return
	if wolf:
		wolf_t -= delta
		if wolf_t <= 0.0:
			revert()
	else:
		energy = minf(energy + CHARGE_RATE * delta, 100.0)
		if not is_player and energy >= 100.0:
			# bots turn when an enemy is in sight (or after waiting a while)
			_auto_t += delta
			if ("target_visible" in host and host.target_visible) or _auto_t > 8.0:
				transform()

func on_kill() -> void:
	if not wolf:
		energy = minf(energy + KILL_CHARGE, 100.0)

func can_transform() -> bool:
	return not wolf and energy >= 100.0 and host.alive

func transform() -> void:
	if not can_transform():
		return
	wolf = true
	wolf_t = WOLF_TIME
	energy = 0.0
	_auto_t = 0.0
	prev_weapon = str(host.cur) if "cur" in host else str(host.wid)
	host.wolf = true
	SFX.play3d("explosion", host.global_position, -8, 0.45, 40.0, 6.0)
	SFX.play3d("gore1", host.global_position, -4, 0.55, 30.0, 4.0)
	if is_player:
		host.health = minf(host.health * 1.2 + 20.0, 100.0)
		host.switch_to("pence", false)
		var hud = host.match_node.hud
		if hud and hud.has_method("wolf_fx"):
			hud.wolf_fx(true)
	else:
		host.health = minf(host.health + 30.0, 100.0)
		host.set_weapon("pence")
		_tint(true)

func revert(silent: bool = false) -> void:
	if not wolf:
		return
	wolf = false
	host.wolf = false
	if not silent:
		SFX.play3d("gore0", host.global_position, -8, 0.7, 30.0, 4.0)
	if is_player:
		if host.alive and prev_weapon != "" and host._has(prev_weapon):
			host.switch_to(prev_weapon, false)
		elif host.alive and host.slots.size() > 0:
			host.switch_to(host.slots.values()[0], false)
		var hud = host.match_node.hud
		if hud and hud.has_method("wolf_fx"):
			hud.wolf_fx(false)
	else:
		_tint(false)
		if host.alive and prev_weapon != "" and prev_weapon != "pence":
			host.set_weapon(prev_weapon)

## bots: dark fur overlay, a hunched, bigger silhouette and glowing red eyes
static var _fur: StandardMaterial3D
func _tint(on: bool) -> void:
	var model: Node3D = host.model if "model" in host else null
	if model == null:
		return
	if _fur == null:
		_fur = StandardMaterial3D.new()
		_fur.albedo_color = Color(0.09, 0.075, 0.07)
		_fur.roughness = 0.95
		_fur.rim_enabled = true
		_fur.rim = 0.6
		_fur.rim_tint = 0.3
		_fur.emission_enabled = true
		_fur.emission = Color(0.25, 0.02, 0.0)
		_fur.emission_energy_multiplier = 0.25
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _fur if on else null
	model.scale = Vector3(1.18, 1.12, 1.18) if on else Vector3.ONE
	var eyes: Node3D = model.get_node_or_null("WolfEyes")
	if on and eyes == null:
		eyes = Node3D.new()
		eyes.name = "WolfEyes"
		model.add_child(eyes)
		for sx in [-0.035, 0.035]:
			var e := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.016; sm.height = 0.032
			e.mesh = sm
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.albedo_color = Color(1.0, 0.15, 0.05)
			em.emission_enabled = true; em.emission = Color(1, 0.2, 0.05); em.emission_energy_multiplier = 4.0
			e.material_override = em
			e.position = Vector3(sx, 1.66, 0.11)
			eyes.add_child(e)
	if eyes:
		eyes.visible = on
