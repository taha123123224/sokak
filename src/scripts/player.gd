extends CharacterBody3D
## First-person player: movement, weapons, viewmodel (rendered in its own SubViewport/World3D).

signal died(killer, wid, head)

const STAND_H := 1.8
const CROUCH_H := 1.15
const EYE_STAND := 1.64
const EYE_CROUCH := 1.05
const RUN := 5.4
const GRAV := 16.0
const JUMP := 5.0
const STEP := 0.42

var match_node
var display_name := "Oyuncu"
var team := ""
var is_player := true
var alive := true
var health := 100.0
var armor := 100.0

var head: Node3D
var cam: Camera3D
var col: CollisionShape3D
var capsule: CapsuleShape3D
var yaw := 0.0
var pitch := 0.0
var recoil_pitch := 0.0      # accumulated kick still to recover
var recoil_vel := Vector2.ZERO
var punch := Vector3.ZERO
var shake := 0.0
var crouching := false
var eye := EYE_STAND
var was_on_floor := true
var step_dist := 0.0
var land_dip := 0.0

# weapons
var slots := {}          # cat -> weapon id
var ammo := {}           # id -> [mag, reserve]
var cur := ""
var last := ""
var fire_cd := 0.0
var reload_t := 0.0
var reload_total := 0.0
var equip_t := 0.0
var draw_total := 0.3
var holster_t := 0.0
var pending_id := ""
const HOLSTER := 0.11
var bolt_t := 0.0
var inspect_t := 0.0
var melee_t := 0.0
var melee_heavy := false
var throw_t := 0.0
# animated first-person arms
var fp_ap: AnimationPlayer
var fp_skel: Skeleton3D
var fp_meta: Dictionary = {}
var fp_anim := ""
var mag_att: Node3D
var mag_home: Node
var held_att: Node3D
var nade_primed := false
var nade_prime_t := 0.0
var fp_root: Node3D
var arc_mi: MeshInstance3D
var arc_mesh: ImmediateMesh
var arc_mark: MeshInstance3D
const THROW_TIME := 0.17
var grenades := 0
var ads := false
var ads_k := 0.0
var shots_in_burst := 0
var bloom := 0.0
var trigger_released := true
var wdata := {}

# viewmodel
var vm_vp: SubViewport
var vm_cam: Camera3D
var vm_root: Node3D
var vm_off: Node3D
var vm_weapon: Node3D
var vm_parts := {}
var vm_sun: DirectionalLight3D
var vm_env: Environment
var vm_rect: TextureRect
var flash_mi: MeshInstance3D
var flash_tex: Array = []
var flash_side_tex: Array = []
var flash_side: MeshInstance3D
var shells: Array = []
var sway := Vector2.ZERO
var mouse_delta := Vector2.ZERO
var bob_t := 0.0
var kick := 0.0
var kick_rot := 0.0
var weapon_cache := {}
var arms_scene: PackedScene

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48)
	col = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = STAND_H
	col.shape = capsule
	col.position.y = STAND_H / 2
	add_child(col)
	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	cam = Camera3D.new()
	cam.fov = GS.settings["fov"]
	cam.near = 0.05
	cam.far = 900.0 * float(GS.settings["draw_distance"])
	cam.cull_mask = 0xFFFFF & ~(1 << 19)
	head.add_child(cam)
	# the body is physics-interpolated (60 Hz ticks); the camera follows it every rendered frame
	# itself so mouse look has zero tick latency and movement stays smooth at any refresh rate
	cam.top_level = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.current = true
	arms_scene = load("res://assets/models/arms.glb")
	_build_viewmodel()

func setup_loadout(set: Dictionary, mode: String) -> void:
	slots.clear()
	if mode == "knife":
		slots = {"bicak": set.get("bicak", "knife"), "bomba": "frag"}
	elif mode == "sniper":
		var sn: String = set.get("ana", "awp")
		if not GS.WEAPONS.get(sn, {}).get("scope", false):
			sn = "awp" if GS.owned("awp") else "kar98"
		slots = {"ana": sn, "tabanca": set.get("tabanca", "glock"), "bicak": set.get("bicak", "knife")}
	elif mode == "gungame":
		var lv: int = match_node.gg_level(self)
		var w: String = GS.GUNGAME_ORDER[min(lv, GS.GUNGAME_ORDER.size() - 1)]
		slots = {GS.WEAPONS[w]["cat"]: w}
		if w != "knife":
			slots["bicak"] = "knife"
	else:
		for c in GS.SLOT_ORDER:
			if set.has(c):
				slots[c] = set[c]
	ammo.clear()
	for c in slots.keys():
		var id: String = slots[c]
		var st := GS.stats_for(id)
		ammo[id] = [st["mag"], int(GS.WEAPONS[id].get("reserve", 0))]
	grenades = 2 if slots.has("bomba") else 0
	cur = ""
	var first = "ana" if slots.has("ana") else ("tabanca" if slots.has("tabanca") else slots.keys()[0])
	switch_to(slots[first], true)

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not alive or match_node.paused or match_node.ended:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(e)

func _look(e: InputEventMouseMotion) -> void:
	var s: float = float(GS.settings["sens"]) * 0.0022
	if ads_k > 0.5:
		s *= float(GS.settings["scope_sens"]) / max(wdata.get("zoom", 1.0) * 0.35, 1.0) if wdata.get("scope", false) else float(GS.settings["ads_sens"])
	var inv := -1.0 if GS.settings["invert_y"] else 1.0
	yaw -= e.relative.x * s
	pitch -= e.relative.y * s * inv
	pitch = clamp(pitch, -1.53, 1.53)
	mouse_delta += e.relative

func _unhandled_input(e: InputEvent) -> void:
	if not alive or match_node.paused or match_node.ended:
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
	if e.is_action_pressed("slot1") and slots.has("ana"): switch_to(slots["ana"])
	if e.is_action_pressed("slot2") and slots.has("tabanca"): switch_to(slots["tabanca"])
	if e.is_action_pressed("slot3") and slots.has("bicak"): switch_to(slots["bicak"])
	if (e.is_action_pressed("slot4") or e.is_action_pressed("grenade")) and slots.has("bomba") and grenades > 0: switch_to(slots["bomba"])
	if e.is_action_pressed("last_weapon") and last != "" and _has(last): switch_to(last)
	if e.is_action_pressed("reload"): start_reload()
	if e.is_action_pressed("inspect") and reload_t <= 0 and equip_t <= 0 and not ads:
		inspect_t = 3.2
	if e.is_action_pressed("jump") and is_on_floor() and not crouching:
		velocity.y = JUMP

func equip_from_menu(cat: String, id: String) -> void:
	var setd: Dictionary = GS.active_set()
	setd[cat] = id
	GS.save_profile()
	if not alive:
		return
	var old: String = slots.get(cat, "")
	slots[cat] = id
	if old != "" and old != id:
		ammo.erase(old)
	var st := GS.stats_for(id)
	ammo[id] = [st["mag"], int(GS.WEAPONS[id].get("reserve", 0))]
	switch_to(id, true)

func _has(id: String) -> bool:
	for c in slots.keys():
		if slots[c] == id:
			return true
	return false

func _cycle(d: int) -> void:
	var order: Array = []
	for c in GS.SLOT_ORDER:
		if slots.has(c) and (c != "bomba" or grenades > 0):
			order.append(slots[c])
	if order.size() < 2:
		return
	var i := order.find(cur)
	switch_to(order[(i + d + order.size()) % order.size()])

# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	if not alive:
		return
	var frozen: bool = match_node.paused or match_node.ended or match_node.countdown > 0
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	rotation.y = yaw
	# crouch
	var want_crouch: bool = Input.is_action_pressed("crouch") and not frozen
	if not want_crouch and crouching:
		# check headroom
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new(); s.radius = 0.3
		q.shape = s
		q.transform = Transform3D(Basis(), global_position + Vector3.UP * (STAND_H - 0.3))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_shape(q, 1).size() > 0:
			want_crouch = true
	crouching = want_crouch
	var h := CROUCH_H if crouching else STAND_H
	capsule.height = lerp(capsule.height, h, min(delta * 14.0, 1.0))
	col.position.y = capsule.height / 2
	eye = lerp(eye, EYE_CROUCH if crouching else EYE_STAND, min(delta * 12.0, 1.0))
	# speed
	var spd := RUN * float(wdata.get("speed", 1.0))
	if slow_t > 0:   # hit by a slowing (.45) round
		slow_t -= delta
		spd *= 0.62
	if Input.is_action_pressed("walk"): spd *= 0.52
	if crouching: spd *= 0.48
	if ads_k > 0.5: spd *= 0.72
	var wish := (transform.basis * Vector3(input.x, 0, input.y))
	wish.y = 0
	if wish.length() > 1: wish = wish.normalized()
	var hv := Vector2(velocity.x, velocity.z)
	var target := Vector2(wish.x, wish.z) * spd
	if is_on_floor():
		var acc := 55.0 if target.length() > hv.length() else 70.0
		hv = hv.move_toward(target, acc * delta)
	else:
		hv = hv.move_toward(target, 10.0 * delta) if target.length() > 0.1 else hv
		velocity.y -= GRAV * delta
	velocity.x = hv.x; velocity.z = hv.y
	if is_on_floor() and velocity.y <= 0:
		_try_step(delta)
	move_and_slide()
	# landing / footsteps
	if is_on_floor() and not was_on_floor:
		land_dip = 0.08
		SFX.play("land", -6, randf_range(0.9, 1.1))
	was_on_floor = is_on_floor()
	if is_on_floor() and hv.length() > 3.0 and not Input.is_action_pressed("walk") and not crouching:
		step_dist += hv.length() * delta
		if step_dist > 2.1:
			step_dist = 0
			SFX.play_var("step_" + match_node.surface, 4, -10)
	if global_position.y < -20:
		take_damage(1000, null, global_position, false, "")

func _try_step(delta: float) -> void:
	var hmove := Vector3(velocity.x, 0, velocity.z) * delta
	if hmove.length() < 0.0005:
		return
	if not test_move(global_transform, hmove):
		return
	if test_move(global_transform, Vector3.UP * STEP):
		return
	var up := global_transform.translated(Vector3.UP * STEP)
	if test_move(up, hmove * 1.5):
		return
	global_position.y += STEP
	apply_floor_snap()

# ---------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	if not alive:
		return
	var frozen: bool = match_node.paused or match_node.ended or match_node.countdown > 0
	# recoil recovery
	if recoil_vel.length() > 0.0001:
		var step = recoil_vel * min(delta * 22.0, 1.0)
		pitch += step.x
		yaw += step.y
		recoil_vel -= step
	if not Input.is_action_pressed("fire") or fire_cd > 0.12:
		var rec: float = min(recoil_pitch, delta * 0.6)
		recoil_pitch -= rec
		pitch -= rec * 0.9
	if not Input.is_action_pressed("fire"):
		shots_in_burst = 0
		trigger_released = true
	bloom = max(bloom - delta * 0.12, 0.0)
	head.position.y = eye - land_dip
	land_dip = lerp(land_dip, 0.0, min(delta * 10.0, 1.0))
	shake = max(shake - delta * 2.5, 0.0)
	punch = punch.lerp(Vector3.ZERO, min(delta * 12.0, 1.0))
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.03
	head.rotation = Vector3(pitch, 0, 0) + punch + sh
	_sync_cam()
	# timers
	fire_cd = max(fire_cd - delta, 0.0)
	equip_t = max(equip_t - delta, 0.0)
	if holster_t > 0:
		holster_t -= delta
		if holster_t <= 0 and pending_id != "":
			_do_switch(pending_id, false)
	inspect_t = max(inspect_t - delta, 0.0)
	melee_t = max(melee_t - delta, 0.0)
	if bolt_t > 0:
		bolt_t -= delta
		if bolt_t <= 0.45 and bolt_t + delta > 0.45:
			SFX.play("bolt_fwd", -6)
	if reload_t > 0:
		_update_reload(delta)
	_update_nade(delta)
	if throw_t > 0:
		throw_t -= delta
		if throw_t <= 0:
			_finish_throw()
	# ADS
	var want_ads: bool = Input.is_action_pressed("aim") and not frozen and reload_t <= 0 and equip_t <= 0 and bolt_t <= 0 and not wdata.get("melee", false) and not wdata.get("throwable", false)
	if want_ads != ads:
		ads = want_ads
		if ads:
			inspect_t = 0
			if wdata.get("scope", false):
				SFX.play("scope_in", -6)
	ads_k = move_toward(ads_k, 1.0 if ads else 0.0, delta * (7.0 if not wdata.get("scope", false) else 9.0))
	var zoom: float = wdata.get("zoom", 1.2)
	var target_fov: float = float(GS.settings["fov"]) / lerp(1.0, zoom, ads_k)
	cam.fov = lerp(cam.fov, target_fov, min(delta * 20.0, 1.0))
	# firing
	if not frozen and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_fire()
	elif not Input.is_action_pressed("fire"):
		trigger_released = true
	_update_viewmodel(delta)

# ---------------------------------------------------------------- weapons
func switch_to(id: String, instant: bool = false) -> void:
	if not instant:
		if id == cur and holster_t <= 0:
			return
		if cur != "" and alive:
			# quick holster of the current weapon, the real swap happens when it is out of view
			pending_id = id
			if holster_t <= 0:
				holster_t = HOLSTER
				nade_primed = false
				SFX.play("equip", -16, 1.35)
			return
	_do_switch(id, instant)

func _draw_time(id: String) -> float:
	var w: Dictionary = GS.WEAPONS[id]
	if w.get("melee", false):
		return 0.2
	if w.get("throwable", false):
		return 0.22
	if w["cat"] == "tabanca":
		return 0.24
	if w.get("scope", false):
		return 0.42
	if w.get("shell_reload", false):
		return 0.36
	return 0.32

func _do_switch(id: String, instant: bool) -> void:
	holster_t = 0.0
	pending_id = ""
	if cur != "" and cur != id:
		last = cur
	cur = id
	wdata = GS.full_stats(id)     # base + upgrades + fitted attachments + ballistics
	reload_t = 0
	bolt_t = 0
	inspect_t = 0
	ads = false
	draw_total = _draw_time(id)
	equip_t = 0.0 if instant else draw_total
	_mag_release()
	_load_vm_weapon(id)
	if not instant:
		var w: Dictionary = GS.WEAPONS[id]
		if w.get("melee", false):
			SFX.play("knife_swing", -12, 1.4)
		elif w["cat"] == "tabanca":
			SFX.play("equip_pistol", -7)
		elif w.get("scope", false) or w.get("pellets", 0) > 0 or float(w.get("speed", 1.0)) < 0.96:
			SFX.play("equip_heavy", -5)
		else:
			SFX.play("equip", -5)
	if match_node and match_node.hud:
		match_node.hud.on_weapon_changed()

func _try_fire() -> void:
	if fire_cd > 0 or equip_t > draw_total * 0.25 or holster_t > 0 or bolt_t > 0 or throw_t > 0:
		return
	if wdata.get("melee", false):
		_melee(false)
		return
	if wdata.get("throwable", false):
		if trigger_released and grenades > 0 and not nade_primed:
			_start_throw()
		trigger_released = false
		return
	if reload_t > 0:
		if wdata.get("shell_reload", false) and ammo[cur][0] > 0:
			reload_t = 0
		else:
			return
	if not wdata.get("auto", false) and not trigger_released:
		return
	trigger_released = false
	if ammo[cur][0] <= 0:
		SFX.play("dryfire", -4)
		fire_cd = 0.25
		if ammo[cur][1] > 0:
			start_reload()
		return
	ammo[cur][0] -= 1
	fire_cd = 60.0 / float(wdata["rpm"])
	inspect_t = 0
	shots_in_burst += 1
	GS.profile["stats"]["shots"] = int(GS.profile["stats"]["shots"]) + 1
	if match_node.net:
		match_node.net.send_fire(cur)
	if wdata.get("silenced", false):
		SFX.play("shot_sup", -6, randf_range(0.95, 1.05))
	else:
		SFX.play(wdata["snd"], -2, randf_range(0.95, 1.05))
	# spread
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var sp: float = lerp(float(wdata["spread"]), float(wdata["ads_spread"]), ads_k)
	sp += float(wdata["move"]) * clamp(hspeed / 5.0, 0.0, 1.0) * (1.0 - ads_k * 0.6)
	if not is_on_floor(): sp += 0.08
	if crouching: sp *= 0.75
	sp += bloom
	if wdata.get("scope", false) and ads_k < 0.95:
		sp = max(sp, float(wdata["spread"]))
	var pellets := int(wdata.get("pellets", 1))
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var muzzle := _muzzle_world()
	var hit_any := false
	for i in pellets:
		var dir := _spread_dir(fwd, sp)
		var res: Dictionary = match_node.hitscan(self, origin, dir, cur, float(wdata["dmg"]), float(wdata.get("range", 150.0)), float(wdata.get("head", 2.5)), wdata)
		if res.get("hit_char", false):
			hit_any = true
		if i < 3:
			match_node.fx.tracer(muzzle, res.get("pos", origin + dir * 80.0))
	if hit_any:
		GS.profile["stats"]["hits"] = int(GS.profile["stats"]["hits"]) + 1
	if not wdata.get("silenced", false):
		match_node.fx.muzzle_light(muzzle, 2.5)
		match_node.on_shot_fired(self, global_position)
	bloom = min(bloom + float(wdata["recoil"]) * 0.22, 0.04)
	# recoil (camera)
	var rk: float = float(wdata["recoil"]) * 0.55 * (1.0 + min(shots_in_burst, 10) * 0.03) * (0.75 if crouching else 1.0) * lerp(1.0, 0.8, ads_k)
	var hr: float = float(wdata.get("hrec", 0.006)) * 0.5 * randf_range(-1.0, 1.0) * (1.0 + min(shots_in_burst, 10) * 0.03)
	if shots_in_burst > 8:
		hr += float(wdata.get("hrec", 0.006)) * 0.5 * sin(shots_in_burst * 0.7) * 0.8
	recoil_vel += Vector2(rk, hr)
	recoil_pitch += rk
	punch += Vector3(rk * 0.6, 0, randf_range(-0.004, 0.004))
	kick = 1.0
	if not wdata.get("silenced", false):
		_spawn_flash()
	_spawn_shell()
	if wdata.get("bolt", false):
		bolt_t = 1.1
		SFX.play("bolt_back", -6)
		if _fp_has("bolt"):
			_fp_play("bolt", 0.08, _fp_len("bolt") / 1.1)
			get_tree().create_timer(1.12).timeout.connect(func(): if fp_anim == "bolt": _fp_play("idle", 0.15))
	elif cur == "spas":
		bolt_t = 0.55
		get_tree().create_timer(0.18).timeout.connect(func(): SFX.play("pump", -4))
		if _fp_has("pump"):
			_fp_play("pump", 0.05, _fp_len("pump") / 0.55)
			get_tree().create_timer(0.57).timeout.connect(func(): if fp_anim == "pump": _fp_play("idle", 0.1))
	if ammo[cur][0] == 0 and ammo[cur][1] > 0:
		get_tree().create_timer(0.25).timeout.connect(start_reload)
	if match_node.hud:
		match_node.hud.on_fire()

func _spread_dir(fwd: Vector3, sp: float) -> Vector3:
	var r := sqrt(randf()) * sp
	var a := randf() * TAU
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	return (fwd + right * cos(a) * r + up * sin(a) * r).normalized()

func current_spread() -> float:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var sp: float = lerp(float(wdata.get("spread", 0.02)), float(wdata.get("ads_spread", 0.01)), ads_k)
	sp += float(wdata.get("move", 0.0)) * clamp(hspeed / 5.0, 0.0, 1.0)
	if not is_on_floor(): sp += 0.08
	return sp + bloom

func start_reload() -> void:
	if wdata.get("melee", false) or wdata.get("throwable", false) or reload_t > 0 or equip_t > 0:
		return
	var a: Array = ammo[cur]
	if a[0] >= int(wdata["mag_max"]) or a[1] <= 0:
		return
	ads = false
	inspect_t = 0
	reload_total = float(wdata["reload"])
	reload_t = reload_total
	if wdata.get("shell_reload", false):
		SFX.play("equip", -10)
		_fp_play("shell", 0.1, _fp_len("shell") / reload_total)
	elif _fp_has("reload"):
		_fp_play("reload", 0.1, _fp_len("reload") / reload_total)
	else:
		SFX.play("mag_out", -4)

func _update_reload(delta: float) -> void:
	var prev := reload_t
	reload_t -= delta
	if wdata.get("shell_reload", false):
		if reload_t <= 0:
			var a: Array = ammo[cur]
			if a[0] < int(wdata["mag_max"]) and a[1] > 0:
				a[0] += 1; a[1] -= 1
				SFX.play("shell_in", -4, randf_range(0.95, 1.05))
				if a[0] < int(wdata["mag_max"]) and a[1] > 0:
					reload_t = reload_total
					_fp_play("shell", 0.05, _fp_len("shell") / reload_total)
					fp_ap.seek(0.0, true) if fp_ap else null
				else:
					reload_t = 0
					_fp_play("pump", 0.1)
					get_tree().create_timer(0.2).timeout.connect(func(): SFX.play("pump", -4))
			else:
				reload_t = 0
		return
	var f := 1.0 - reload_t / reload_total
	var pf := 1.0 - prev / reload_total
	var rm: Dictionary = fp_meta.get("reload", {})
	if not rm.is_empty() and _fp_has("reload"):
		var at: Array = rm.get("attach", [0.22, 0.79])
		if pf < float(rm.get("mag_out", 0.24)) and f >= float(rm.get("mag_out", 0.24)):
			SFX.play("mag_out_p" if wdata["cat"] == "tabanca" else "mag_out", -4)
		if pf < float(at[0]) and f >= float(at[0]):
			_mag_grab()
		if pf < float(at[1]) and f >= float(at[1]):
			_mag_release()
			SFX.play("mag_in_p" if wdata["cat"] == "tabanca" else "mag_in", -3)
		if pf < float(rm.get("bolt", 0.9)) and f >= float(rm.get("bolt", 0.9)):
			SFX.play("bolt_fwd", -7)
	else:
		if pf < 0.55 and f >= 0.55:
			SFX.play("mag_in", -4)
		if pf < 0.8 and f >= 0.8:
			SFX.play("bolt_fwd", -8)
	if reload_t <= 0:
		_mag_release()
		_fp_play("idle", 0.2)
		var a: Array = ammo[cur]
		var need: int = int(wdata["mag_max"]) - a[0]
		var take: int = min(need, a[1])
		a[0] += take; a[1] -= take
		reload_t = 0

func _melee(heavy: bool) -> void:
	heavy = Input.is_action_pressed("aim")
	melee_heavy = heavy
	melee_t = 0.75 if heavy else 0.45
	fire_cd = 1.0 if heavy else 60.0 / float(wdata["rpm"])
	SFX.play("knife_swing", -4, randf_range(0.9, 1.1))
	var ma := "stab" if heavy else "slash"
	if _fp_has(ma):
		_fp_play(ma, 0.05, _fp_len(ma) / melee_t)
		get_tree().create_timer(melee_t + 0.02).timeout.connect(func(): if fp_anim == ma: _fp_play("idle", 0.15))
	var dmg: float = float(wdata["dmg"]) * (1.9 if heavy else 1.0)
	get_tree().create_timer(0.12).timeout.connect(func(): match_node.melee(self, cam.global_position, -cam.global_transform.basis.z, dmg, cur))

func _start_throw() -> void:
	# pull the pin and hold: trajectory preview is shown until fire is released
	nade_primed = true
	nade_prime_t = 0.0
	SFX.play("pin", -4)
	_fp_play("throw", 0.05, 1.0)

func _throw_velocity() -> Vector3:
	var dir := -cam.global_transform.basis.z
	var strong := not Input.is_action_pressed("aim")
	return dir * (17.0 if strong else 8.0) + Vector3.UP * (2.5 if strong else 1.5) + velocity * 0.5

func _throw_origin() -> Vector3:
	var dir := -cam.global_transform.basis.z
	return cam.global_position + dir * 0.5 + cam.global_transform.basis.x * 0.15

func _update_nade(delta: float) -> void:
	if nade_primed:
		nade_prime_t += delta
		if not wdata.get("throwable", false) or not alive:
			nade_primed = false
		elif not Input.is_action_pressed("fire") and nade_prime_t > 0.15:
			nade_primed = false
			throw_t = THROW_TIME
			if fp_ap and fp_anim == "throw":
				fp_ap.speed_scale = 1.0
				fp_ap.play("throw")
		if nade_primed and fp_ap and fp_anim == "throw":
			var hold: float = float(fp_meta.get("throw", {}).get("hold", 0.33)) * _fp_len("throw")
			fp_ap.speed_scale = 0.0 if fp_ap.current_animation_position >= hold else 1.0
	_draw_arc(nade_primed and alive)

func _draw_arc(show: bool) -> void:
	if arc_mi == null:
		arc_mesh = ImmediateMesh.new()
		arc_mi = MeshInstance3D.new()
		arc_mi.mesh = arc_mesh
		arc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var am := StandardMaterial3D.new()
		am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		am.vertex_color_use_as_albedo = true
		am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		am.no_depth_test = true
		am.cull_mode = BaseMaterial3D.CULL_DISABLED
		arc_mi.material_override = am
		arc_mi.top_level = true
		add_child(arc_mi)
		arc_mark = MeshInstance3D.new()
		var tm := TorusMesh.new(); tm.inner_radius = 0.42; tm.outer_radius = 0.5; tm.rings = 32
		arc_mark.mesh = tm
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(1, 0.55, 0.15, 0.85)
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.emission_enabled = true; mm.emission = Color(1, 0.5, 0.1); mm.emission_energy_multiplier = 2.0
		arc_mark.material_override = mm
		arc_mark.top_level = true
		add_child(arc_mark)
	arc_mesh.clear_surfaces()
	arc_mi.visible = show
	arc_mark.visible = false
	if not show:
		return
	var p := _throw_origin()
	var v := _throw_velocity()
	var g := Vector3(0, -float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0)
	var space := get_world_3d().direct_space_state
	var pts: Array = [p]
	var dt := 0.03
	var hit := {}
	var bounces := 0
	for i in 110:
		var np := p + v * dt
		v += g * dt
		var q := PhysicsRayQueryParameters3D.create(p, np, 1)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			pts.append(r["position"])
			var n: Vector3 = r["normal"]
			if bounces >= 1 or n.y > 0.7:
				hit = r
				break
			v = v.bounce(n) * 0.35
			p = r["position"] + n * 0.02
			bounces += 1
			continue
		pts.append(np)
		p = np
	arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam_p := cam.global_position
	for i in range(pts.size() - 1):
		if i % 2 == 1 or (pts[i] as Vector3).distance_to(cam_p) < 1.6:
			continue  # dashed, and nothing right in front of the eyes
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var side := (b - a).cross(cam_p - a).normalized() * 0.025
		var t := float(i) / pts.size()
		var c := Color(1, 0.85 - t * 0.35, 0.3, 0.9 - t * 0.3)
		arc_mesh.surface_set_color(c)
		arc_mesh.surface_add_vertex(a - side); arc_mesh.surface_add_vertex(a + side); arc_mesh.surface_add_vertex(b + side)
		arc_mesh.surface_add_vertex(a - side); arc_mesh.surface_add_vertex(b + side); arc_mesh.surface_add_vertex(b - side)
	arc_mesh.surface_end()
	if not hit.is_empty():
		arc_mark.visible = true
		var hp: Vector3 = hit["position"]
		var hn: Vector3 = hit["normal"]
		arc_mark.global_position = hp + hn * 0.03
		var up := hn
		var fwd := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		arc_mark.global_basis = Basis(fwd.cross(up).normalized(), up, up.cross(fwd.cross(up)).normalized())
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.08
		arc_mark.scale = Vector3(pulse, 1, pulse)

func _finish_throw() -> void:
	if not alive:
		return
	SFX.play("throw", -4)
	match_node.throw_grenade(self, _throw_origin(), _throw_velocity())
	grenades -= 1
	if vm_weapon and fp_anim == "throw":
		var wv := vm_weapon
		wv.visible = false
		get_tree().create_timer(0.35).timeout.connect(func(): if is_instance_valid(wv): wv.visible = true)
		get_tree().create_timer(0.55).timeout.connect(func(): if fp_anim == "throw": _fp_play("idle", 0.15))
	if grenades <= 0:
		switch_to(last if last != "" and _has(last) and last != cur else slots.get("ana", slots.get("tabanca", slots.get("bicak", cur))))

# ---------------------------------------------------------------- damage
var slow_t := 0.0

func take_damage(amount: float, attacker, pos: Vector3, headshot: bool, wid: String) -> void:
	if not alive or match_node.ended:
		return
	var dmg := amount
	var bl: Dictionary = GS.ball(wid) if wid != "" else {}
	if bl.get("abil", "") == "slow":
		slow_t = 0.9
	elif bl.get("abil", "") == "suppress":
		shake = max(shake, 0.55)
	if armor > 0 and wid != "" and not GS.WEAPONS.get(wid, {}).get("throwable", false):
		var absorbed: float = min(armor, dmg * 0.45 * (1.0 - float(bl.get("ap", 0.2))))
		armor -= absorbed
		dmg -= absorbed
	health -= dmg
	shake = max(shake, 0.4 if amount < 50 else 0.8)
	punch += Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), 0)
	SFX.play("hurt", -6, randf_range(0.9, 1.1))
	if match_node.hud:
		match_node.hud.on_damaged(pos, amount)
	if health <= 0:
		health = 0
		alive = false
		vm_rect.visible = false
		died.emit(attacker, wid, headshot)

func _sync_cam() -> void:
	var o: Vector3 = get_global_transform_interpolated().origin if is_physics_interpolated_and_enabled() else global_position
	cam.global_transform = Transform3D(Basis(Vector3.UP, yaw), o) * head.transform

func respawn(pos: Vector3, yaw_: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	yaw = yaw_
	pitch = 0
	recoil_pitch = 0
	recoil_vel = Vector2.ZERO
	health = 100
	armor = 100
	alive = true
	crouching = false
	vm_rect.visible = true
	setup_loadout(GS.active_set(), GS.room.get("mode", "ffa"))

func eye_pos() -> Vector3:
	return cam.global_position

func chest_pos() -> Vector3:
	return global_position + Vector3.UP * (1.25 if not crouching else 0.8)

# ---------------------------------------------------------------- viewmodel
func _build_viewmodel() -> void:
	vm_vp = SubViewport.new()
	vm_vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vm_vp.own_world_3d = true
	vm_vp.transparent_bg = true
	vm_vp.msaa_3d = Viewport.MSAA_4X
	vm_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vm_vp.size = get_viewport().get_visible_rect().size
	add_child(vm_vp)
	vm_cam = Camera3D.new()
	vm_cam.fov = 56
	vm_cam.near = 0.01
	vm_cam.far = 10
	vm_vp.add_child(vm_cam)
	vm_env = Environment.new()
	vm_env.background_mode = Environment.BG_CLEAR_COLOR
	vm_env.background_color = Color(0, 0, 0, 0)
	vm_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	vm_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	vm_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	vm_cam.environment = vm_env
	vm_sun = DirectionalLight3D.new()
	vm_sun.shadow_enabled = false
	vm_vp.add_child(vm_sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.3, 0.2, 0.2)
	fill.light_energy = 0.25
	fill.omni_range = 2.0
	vm_vp.add_child(fill)
	vm_root = Node3D.new()
	vm_vp.add_child(vm_root)
	vm_off = Node3D.new()
	vm_root.add_child(vm_off)
	# muzzle flash meshes (3 random variants per shot)
	for i in 3:
		flash_tex.append(load("res://assets/fx/flash%d.png" % i))
		flash_side_tex.append(load("res://assets/fx/flash_side%d.png" % i))
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = load("res://assets/fx/flash.png")
	fm.albedo_color = Color(1, 0.85, 0.6) * 2.0
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mi = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.16, 0.16); q.material = fm
	flash_mi.mesh = q
	flash_mi.visible = false
	vm_root.add_child(flash_mi)
	var fm2 := fm.duplicate()
	fm2.albedo_texture = load("res://assets/fx/flash_side.png")
	flash_side = MeshInstance3D.new()
	var q2 := QuadMesh.new(); q2.size = Vector2(0.3, 0.09); q2.material = fm2
	flash_side.mesh = q2
	flash_side.visible = false
	vm_root.add_child(flash_side)

func attach_vm_rect(parent: Control) -> void:
	vm_rect = TextureRect.new()
	vm_rect.texture = vm_vp.get_texture()
	vm_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	parent.add_child(vm_rect)
	parent.move_child(vm_rect, 0)
	get_viewport().size_changed.connect(func(): vm_vp.size = get_viewport().get_visible_rect().size)

func set_vm_env(sky: Sky, sun_dir_basis: Basis, sun_color: Color, sun_energy: float, amb: float) -> void:
	vm_env.sky = sky
	vm_env.ambient_light_sky_contribution = 1.0
	vm_env.ambient_light_energy = amb
	vm_sun.light_color = sun_color
	vm_sun.light_energy = sun_energy * 0.9
	vm_sun.set_meta("world_basis", sun_dir_basis)

const GRIP := {"ak47": 20, "m4a1": 22, "mp5": 15, "p90": 0, "spas": 20, "awp": 10, "kar98": 10, "glock": 22, "deagle": 18}
const HIP := {
	"rifle": Vector3(0.14, -0.165, -0.36), "pistol": Vector3(0.13, -0.14, -0.4), "knife": Vector3(0.17, -0.18, -0.36), "frag": Vector3(0.16, -0.17, -0.34), "sniper": Vector3(0.14, -0.17, -0.33),
}

func _vm_kind(id: String) -> String:
	var w: Dictionary = GS.WEAPONS[id]
	if w.get("melee", false): return "knife"
	if w.get("throwable", false): return "frag"
	if w["cat"] == "tabanca": return "pistol"
	if w.get("scope", false): return "sniper"
	return "rifle"

func _load_vm_weapon(id: String) -> void:
	if vm_weapon:
		vm_weapon.queue_free()
	vm_parts.clear()
	var ps: PackedScene = GS.weapon_scene(id)
	vm_weapon = ps.instantiate()
	MatLib.apply(vm_weapon, GS.wskin(id))
	vm_off.add_child(vm_weapon)
	GS.parts_visual(vm_weapon, id)
	GS.level_glow(vm_weapon, id, 0.45)
	for n in ["body", "mag", "bolt", "slide", "muzzle", "sight", "lhand", "rhand", "eject", "pin"]:
		var f := vm_weapon.find_child(n, true, false)
		if f:
			vm_parts[n] = f
			if f is Node3D:
				f.set_meta("rest", (f as Node3D).transform)
	_set_no_shadow(vm_weapon)
	if cur == "spas" and vm_parts.has("mag"):
		vm_parts["mag"].visible = false
	# realistic first-person arms (MakeHuman anatomy) baked in weapon space
	if vm_parts.has("arms") and is_instance_valid(vm_parts["arms"]):
		pass
	if fp_root and is_instance_valid(fp_root):
		fp_root.queue_free()
	fp_ap = null; fp_skel = null; fp_meta = {}; fp_anim = ""; mag_att = null; held_att = null
	var fp_path := "res://assets/models/fp_%s.glb" % GS.weapon_base(id)
	if ResourceLoader.exists(fp_path):
		var fp: Node3D = (load(fp_path) as PackedScene).instantiate()
		MatLib.apply(fp)
		_set_no_shadow(fp)
		vm_off.add_child(fp)
		fp_root = fp
		vm_parts["arms"] = fp
		fp_ap = fp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		fp_skel = fp.find_child("Skeleton3D", true, false) as Skeleton3D
		var mp := "res://assets/models/fp_%s.json" % GS.weapon_base(id)
		if FileAccess.file_exists(mp):
			fp_meta = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if fp_ap:
			if fp_ap.has_animation("idle"):
				fp_ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			_fp_play("idle", 0.0)
			fp_ap.advance(0.0)
		# knives and grenades live in the right hand and follow every swing/throw
		if fp_skel and (wdata.get("melee", false) or wdata.get("throwable", false)):
			held_att = _attach_to_bone(vm_weapon, "RightHand")

func _fp_bone(n: String) -> int:
	if fp_skel == null:
		return -1
	for cand in ["mixamorig_" + n, "mixamorig:" + n, n]:
		var i := fp_skel.find_bone(cand)
		if i >= 0:
			return i
	return -1

func _attach_to_bone(node: Node3D, bone: String) -> Node3D:
	## keeps `node` exactly where it is now, but from now on it follows `bone`
	var bi := _fp_bone(bone)
	if bi < 0 or node == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_idx = bi
	fp_skel.add_child(ba)
	ba.global_transform = fp_skel.global_transform * fp_skel.get_bone_global_pose(bi)
	var holder := Node3D.new()
	ba.add_child(holder)
	holder.global_transform = node.global_transform
	node.reparent(holder, true)
	return ba

func _fp_play(a: String, blend: float = 0.12, speed: float = 1.0) -> void:
	if fp_ap == null or not fp_ap.has_animation(a):
		return
	fp_anim = a
	fp_ap.play(a, blend, speed)

func _fp_len(a: String) -> float:
	if fp_ap and fp_ap.has_animation(a):
		return fp_ap.get_animation(a).length
	return 1.0

func _fp_has(a: String) -> bool:
	return fp_ap != null and fp_ap.has_animation(a)

func _mag_grab() -> void:
	if mag_att or not vm_parts.has("mag"):
		return
	var mag: Node3D = vm_parts["mag"]
	mag_home = mag.get_parent()
	mag_att = _attach_to_bone(mag, "LeftHand")

func _mag_release() -> void:
	if mag_att == null:
		return
	var mag: Node3D = vm_parts.get("mag")
	if mag and is_instance_valid(mag) and mag_home and is_instance_valid(mag_home):
		mag.reparent(mag_home, false)
		mag.transform = mag.get_meta("rest")
	if is_instance_valid(mag_att):
		mag_att.queue_free()
	mag_att = null

func _set_no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_no_shadow(c)

func _muzzle_world() -> Vector3:
	if vm_parts.has("muzzle"):
		var local: Vector3 = vm_cam.global_transform.affine_inverse() * (vm_parts["muzzle"] as Node3D).global_position
		# vm camera fov differs; approximate world muzzle position relative to the real camera
		return cam.global_transform * (local * Vector3(1.0, 1.0, 1.0))
	return cam.global_position - cam.global_transform.basis.z * 0.6

func _spawn_flash() -> void:
	if not vm_parts.has("muzzle"):
		return
	var m: Node3D = vm_parts["muzzle"]
	var p := m.global_position
	flash_mi.global_position = p + Vector3(0, 0, -0.03)
	flash_mi.rotation = Vector3(0, 0, randf() * TAU)
	var fv := randi() % 3
	((flash_mi.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture = flash_tex[fv]
	((flash_side.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture = flash_side_tex[fv]
	var s := randf_range(0.8, 1.3) * (1.6 if cur in ["spas", "awp", "kar98", "deagle"] else 1.0)
	flash_mi.scale = Vector3(s, s, s)
	flash_mi.visible = ads_k < 0.9 or not wdata.get("scope", false)
	flash_side.global_position = p + Vector3(0, 0, -0.09) * s
	flash_side.rotation = Vector3(0, PI / 2, randf() * 0.4)
	flash_side.scale = Vector3(s, s, s)
	flash_side.visible = flash_mi.visible
	get_tree().create_timer(0.035).timeout.connect(func(): flash_mi.visible = false; flash_side.visible = false)

func _spawn_shell() -> void:
	if wdata.get("bolt", false) or not vm_parts.has("eject"):
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045 if cur != "spas" else 0.009
	cm.bottom_radius = cm.top_radius
	cm.height = 0.022 if cur != "spas" else 0.05
	cm.radial_segments = 8
	cm.material = MatLib.get_mat("gun_brass" if cur != "spas" else "gun_shell")
	mi.mesh = cm
	vm_root.add_child(mi)
	mi.global_position = (vm_parts["eject"] as Node3D).global_position
	mi.rotation = Vector3(randf(), randf(), PI / 2)
	shells.append({"n": mi, "v": Vector3(randf_range(1.2, 1.8), randf_range(1.0, 1.6), randf_range(0.1, 0.4)), "r": Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20)), "t": 0.0})
	get_tree().create_timer(0.45).timeout.connect(func(): SFX.play_var("shell", 3, -16))

func _update_viewmodel(delta: float) -> void:
	# sun orientation relative to camera so lighting matches world
	if vm_sun.has_meta("world_basis"):
		var wb: Basis = vm_sun.get_meta("world_basis")
		vm_sun.basis = cam.global_transform.basis.inverse() * wb
		vm_env.sky_rotation = (cam.global_transform.basis.inverse()).get_euler()
	vm_cam.fov = lerp(56.0, 40.0, ads_k * (0.0 if wdata.get("scope", false) else 1.0) * 0.5)
	var kind := _vm_kind(cur)
	var hip: Vector3 = HIP[kind]
	# sway & bob
	sway = sway.lerp(mouse_delta * 0.0006, min(delta * 10.0, 1.0))
	mouse_delta = Vector2.ZERO
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.5:
		bob_t += delta * hs * 1.75
	var bob_amt: float = clamp(hs / 5.0, 0.0, 1.0) * (1.0 - ads_k * 0.85)
	var bob := Vector3(sin(bob_t) * 0.007, -abs(cos(bob_t)) * 0.008, 0) * bob_amt
	var breath := Vector3(0, sin(Time.get_ticks_msec() * 0.0015) * 0.0012, 0) * (1.0 - ads_k)
	kick = move_toward(kick, 0.0, delta * 9.0)
	var kz := kick * kick
	# ADS target: sight point to camera axis
	var pos := hip
	var rot := Vector3.ZERO
	if vm_parts.has("sight") and kind != "knife" and kind != "frag":
		var sight_rest: Transform3D = (vm_parts["sight"] as Node3D).get_meta("rest")
		var sp: Vector3 = sight_rest.origin
		var ads_pos := Vector3(-sp.x, -sp.y, -sp.z - (0.14 if kind != "pistol" else 0.3))
		if wdata.get("scope", false):
			ads_pos.z = -sp.z - 0.06
		pos = hip.lerp(ads_pos, ads_k)
	pos += bob + breath + Vector3(-sway.x * 0.6, sway.y * 0.6, 0) * (1.0 - ads_k * 0.7)
	rot += Vector3(sway.y * 1.2, -sway.x * 1.2, -sway.x * 0.8) * (1.0 - ads_k * 0.7)
	# recoil kick
	var kmul: float = float(wdata.get("recoil", 0.02)) * 12.0
	pos.z += kz * 0.045 * kmul * lerp(1.0, 0.6, ads_k)
	pos.y += kz * 0.006 * kmul
	rot.x += kz * 0.09 * kmul * lerp(1.0, 0.35, ads_k)
	rot.z += kz * randf_range(-0.02, 0.02)
	# equip
	if holster_t > 0:
		var hk: float = 1.0 - holster_t / HOLSTER
		hk = hk * hk
		pos.y -= hk * 0.22
		pos.x += hk * 0.04
		rot.x -= hk * 0.55
		rot.z += hk * 0.25
	if equip_t > 0:
		# draw: rises from bottom-right with an eased curve and a tiny settle overshoot
		var e: float = clamp(equip_t / max(draw_total, 0.01), 0.0, 1.0)
		var k := e * e * (3.0 - 2.0 * e)
		var settle := sin((1.0 - e) * PI) * (1.0 - e) * 0.012
		pos.y -= k * 0.2 - settle
		pos.x += k * 0.05
		pos.z += k * 0.04
		rot.x -= k * 0.6
		rot.y += k * 0.15
		rot.z += k * 0.3
	# reload animation
	if reload_t > 0 and not wdata.get("shell_reload", false) and _fp_has("reload"):
		# weapon rolls toward the camera so the magazine change is visible
		var f := 1.0 - reload_t / reload_total
		var tilt := smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.82, 1.0, f))
		rot += Vector3(0.18, 0.28, 0.5) * tilt
		pos += Vector3(-0.02, 0.01, 0.02) * tilt
	elif reload_t > 0 and not wdata.get("shell_reload", false):
		var f := 1.0 - reload_t / reload_total
		var tilt := sin(clamp(f, 0.0, 1.0) * PI)
		rot += Vector3(0.25, 0.35, 0.55) * tilt
		pos += Vector3(-0.03, -0.05, 0.03) * tilt
		if vm_parts.has("mag"):
			var mag: Node3D = vm_parts["mag"]
			var rest: Transform3D = mag.get_meta("rest")
			var mo := 0.0
			if f < 0.25: mo = f / 0.25
			elif f < 0.45: mo = 1.0
			elif f < 0.58: mo = 1.0 - (f - 0.45) / 0.13
			mag.transform = rest.translated_local(Vector3(0, -0.25 * mo, 0.04 * mo))
			mag.visible = not (f > 0.25 and f < 0.42)
	elif reload_t > 0:
		var tilt := 0.6
		rot += Vector3(0.15, 0.25, 0.4) * tilt
		pos += Vector3(-0.02, -0.03, 0.02) * tilt
	elif mag_att == null:
		if vm_parts.has("mag") and cur != "spas":
			(vm_parts["mag"] as Node3D).transform = (vm_parts["mag"] as Node3D).get_meta("rest")
			(vm_parts["mag"] as Node3D).visible = true
	# bolt / pump
	if bolt_t > 0:
		var b := 1.0 - bolt_t / (1.1 if wdata.get("bolt", false) else 0.55)
		var s := sin(clamp(b, 0.0, 1.0) * PI)
		if wdata.get("bolt", false):
			rot += Vector3(0.15, 0.1, 0.35) * s * (1.0 - ads_k)
			if vm_parts.has("bolt"):
				var bn: Node3D = vm_parts["bolt"]
				bn.transform = (bn.get_meta("rest") as Transform3D).translated_local(Vector3(0, 0, 0.08 * s))
		else:
			pos.z += 0.05 * s
	elif vm_parts.has("bolt") and wdata.get("bolt", false):
		(vm_parts["bolt"] as Node3D).transform = (vm_parts["bolt"] as Node3D).get_meta("rest")
	# pistol slide
	if vm_parts.has("slide"):
		var sl: Node3D = vm_parts["slide"]
		var back := kz * 0.035
		if ammo.has(cur) and ammo[cur][0] == 0:
			back = 0.03
		sl.transform = (sl.get_meta("rest") as Transform3D).translated_local(Vector3(0, 0, back))
	# inspect
	if inspect_t > 0:
		var it := 1.0 - inspect_t / 3.2
		var s1 := smoothstep(0.0, 0.2, it) * (1.0 - smoothstep(0.85, 1.0, it))
		var flip := smoothstep(0.4, 0.6, it)
		rot += Vector3(0.2, 0.9 - flip * 1.6, 0.6 - flip * 1.0) * s1
		pos += Vector3(-0.1, 0.04, 0.05) * s1
	# melee
	if melee_t > 0 and not _fp_has("slash"):
		var tot := 0.75 if melee_heavy else 0.45
		var m := 1.0 - melee_t / tot
		if melee_heavy:
			var s2 := sin(clamp(m * 1.3, 0.0, 1.0) * PI)
			pos += Vector3(-0.08, 0.05, -0.18) * s2
			rot += Vector3(-0.6, 0.2, 0.0) * s2
		else:
			var s3 := sin(clamp(m * 1.4, 0.0, 1.0) * PI)
			pos += Vector3(-0.22 * s3, 0.03 * s3, -0.06 * s3)
			rot += Vector3(-0.2, 0.9, 1.2) * s3
	# throw
	if _fp_has("throw"):
		pass
	elif nade_primed:
		# cocked back over the shoulder, slight tremble
		var k := smoothstep(0.0, 0.25, nade_prime_t)
		pos += Vector3(0.05, 0.1, 0.16) * k + Vector3(sin(nade_prime_t * 9.0), cos(nade_prime_t * 7.0), 0) * 0.002
		rot += Vector3(0.75, -0.15, 0.2) * k
	elif throw_t > 0:
		var tt := 1.0 - throw_t / THROW_TIME
		var sw := smoothstep(0.0, 0.55, tt)
		pos += Vector3(0.05, 0.1, 0.16) * (1.0 - sw) + Vector3(-0.08, -0.05, -0.38) * sin(sw * PI * 0.5) - Vector3(0, 0.25, 0) * smoothstep(0.6, 1.0, tt)
		rot += Vector3(0.75, -0.15, 0.2) * (1.0 - sw) + Vector3(-1.1, 0.25, -0.3) * sin(sw * PI * 0.5) * (1.0 - smoothstep(0.7, 1.0, tt))
	if kind == "knife":
		rot += Vector3(0.0, -0.25, 0.15)
	vm_off.position = vm_off.position.lerp(pos, min(delta * 30.0, 1.0))
	vm_off.rotation = vm_off.rotation.lerp(rot, min(delta * 25.0, 1.0))
	# hide for scope
	var scoped: bool = wdata.get("scope", false) and ads_k > 0.92
	vm_off.visible = not scoped
	# shells physics
	for s in shells.duplicate():
		s["t"] += delta
		s["v"].y -= 9.0 * delta
		(s["n"] as Node3D).position += s["v"] * delta * 0.5
		(s["n"] as Node3D).rotation += s["r"] * delta
		if s["t"] > 0.6:
			(s["n"] as Node3D).queue_free()
			shells.erase(s)
