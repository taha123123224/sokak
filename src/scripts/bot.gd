extends CharacterBody3D
## AI soldier: navigation, perception, aiming, shooting; Mixamo soldier model with IK rifle pose.

var match_node
var display_name := "Bot"
var team := ""
var is_player := false
var alive := true
var health := 100.0
var difficulty := 1   # 0 easy, 1 normal, 2 hard

var wid := "ak47"
var wdata := {}
var mag := 30
var reload_t := 0.0
var fire_cd := 0.0
var burst_left := 0
var burst_pause := 0.0

var nav: NavigationAgent3D
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var aim_node: Node3D
var gun: Node3D
var muzzle: Node3D
var cur_anim := ""
var crouching := false

var target = null
var target_visible := false
var last_seen := Vector3.ZERO
var last_seen_t := -100.0
var react_t := 0.0
var think_t := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var roam_target := Vector3.ZERO
var has_roam := false
var stuck_t := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var aim_err := Vector2.ZERO
var heard_pos := Vector3.ZERO
var heard_t := -100.0
var death_t := 0.0
var death_axis := Vector3.RIGHT
var death_head := false
var death_spin := 0.0
var death_fx_done := false
var name_tag: Label3D

const D_REACT := [0.75, 0.42, 0.22]
const D_AIM := [2.6, 4.5, 7.5]
const D_SPREAD := [0.075, 0.042, 0.022]
const D_VIEW := [55.0, 80.0, 120.0]
const D_HEAD := [0.08, 0.18, 0.35]

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36; cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	nav.radius = 0.4
	nav.height = 1.8
	nav.avoidance_enabled = false
	add_child(nav)
	aim_node = Node3D.new()
	aim_node.position = Vector3(0, 1.42, 0)
	add_child(aim_node)
	name_tag = Label3D.new()
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = true
	name_tag.fixed_size = true
	name_tag.pixel_size = 0.0009
	name_tag.font = UI.font("Rajdhani-Bold")
	name_tag.font_size = 22
	name_tag.outline_size = 6
	name_tag.position.y = 2.15
	add_child(name_tag)

func setup(soldier: PackedScene, n: String, tm: String, diff: int, weapon: String) -> void:
	display_name = n
	team = tm
	difficulty = diff
	model = soldier.instantiate()
	add_child(model)
	model.rotation.y = PI
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		for a in ["Idle", "Run", "Walk"]:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_tint_team()
	name_tag.text = n
	name_tag.modulate = GS.TEAM_COLORS.get(tm, Color(1, 0.4, 0.35)) if tm != "" else Color(1, 0.4, 0.35)
	set_weapon(weapon)

func _tint_team() -> void:
	if model == null:
		return
	MatLib.apply(model)
	if team == "":
		return
	var tint: Color = GS.TEAM_COLORS[team]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var orig := m.mesh.surface_get_material(i)
			var ov := m.get_surface_override_material(i)
			var rn := String(orig.resource_name) if orig else ""
			if orig and rn.begins_with("rb_") and team != "" and ("body" in rn.to_lower() or "cloth" in rn.to_lower()):
				var dd := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
				dd.albedo_color = Color(1, 1, 1).lerp(tint, 0.18)
				m.set_surface_override_material(i, dd)
			elif orig and ov is StandardMaterial3D and rn.begins_with("cloth|"):
				var d := (ov as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.albedo_color = d.albedo_color.lerp(tint, 0.22)
				m.set_surface_override_material(i, d)

func set_weapon(w: String) -> void:
	wid = w
	wdata = GS.WEAPONS[w]
	mag = int(wdata.get("mag", 1))
	if gun:
		gun.queue_free()
	var ps: PackedScene = GS.weapon_scene(w)
	gun = ps.instantiate()
	MatLib.apply(gun, "std" if randf() < 0.6 else GS.SKINS.keys()[randi() % GS.SKINS.size()])
	var kind := "pistol" if wdata["cat"] == "tabanca" else ("knife" if wdata.get("melee", false) or wdata.get("throwable", false) else "rifle")
	muzzle = gun.find_child("muzzle", true, false)
	if not _attach_hand(kind):
		# fallback (no aim pose data): weapon floats on the aim node
		aim_node.add_child(gun)
		gun.position = Vector3(0.14, -0.1, -0.24) if kind == "rifle" else Vector3(0.05, -0.05, -0.42)
	gun_base = gun.position

var hand_att: Node3D
var follow: SkeletonModifier3D
var pose: SkeletonModifier3D
var aim_data := {}
var hand_offsets := {}

func _attach_hand(kind: String) -> bool:
	## the weapon lives in the right hand; the upper body takes the pre-solved aim pose, so both hands grip it
	if skel == null or anim == null or not anim.has_animation("AimRifle"):
		if OS.has_environment("BOTW"):
			print("AIMPOSE missing skel=", skel, " anim=", anim, " list=", anim.get_animation_list() if anim else [])
		return false
	if pose == null:
		pose = preload("res://scripts/pose_mod.gd").new()
		skel.add_child(pose)
		skel.move_child(pose, 0)
		pose.setup(skel, anim)
		if twist == null:
			twist = preload("res://scripts/twist_mod.gd").new()
			skel.add_child(twist)
			twist.setup(skel)
		skel.move_child(twist, 1)
		var f := FileAccess.open("res://assets/models/rb_asker1_aim.json", FileAccess.READ)  # Rocketbox avatars share proportions
		aim_data = JSON.parse_string(f.get_as_text())
		hand_att = Node3D.new()
		hand_att.top_level = true
		hand_att.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		model.add_child(hand_att)
		follow = preload("res://scripts/follow_mod.gd").new()
		skel.add_child(follow)
		follow.bone = skel.find_bone("Bip01 R Hand")
		follow.target = hand_att
	var pk := "pistol" if kind != "rifle" else "rifle"
	pose.kind = pk
	pose.weight = 0.0 if kind == "knife" else 1.0
	if not hand_offsets.has(pk):
		var g: Dictionary = aim_data[pk]
		var fwd := Vector3(g["fwd"][0], g["fwd"][1], g["fwd"][2])
		var up := Vector3(g["up"][0], g["up"][1], g["up"][2])
		var z := -fwd.normalized()
		var x := up.cross(z).normalized()
		var grip_root := Transform3D(Basis(x, z.cross(x), z), Vector3(g["grip"][0], g["grip"][1], g["grip"][2]))
		var root_to_skel: Transform3D = model.global_transform.affine_inverse() * skel.global_transform
		hand_offsets[pk] = pose.hand_offset(skel, anim, pk, grip_root, root_to_skel)
	hand_att.add_child(gun)
	gun.transform = hand_offsets[pk]
	if kind == "knife":
		gun.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.08, 0.02))
	return true

var ik_r: SkeletonIK3D
var twist: SkeletonModifier3D
var fire_kick := 0.0
var hit_react := 0.0
var hit_dir := 1.0
var hit_head := false
var gun_base := Vector3.ZERO
var leg_yaw := 0.0
var step_t := 0.0
var ik_l: SkeletonIK3D
var low_ready := 0.0
var chest_idx := -1
var chest_ref := Vector3.ZERO
var chest_ref_ok := false
var chest_t := 0.0
const AIM_BASE := Vector3(0, 1.42, 0)

func _follow_chest(delta: float) -> void:
	## the weapon rides with the animated chest (bob, lean) so the IK hands never lose the grip
	if skel == null or not alive:
		return
	if chest_idx == -1:
		chest_idx = -2
		for n in ["Bip01 Spine2", "Bip01 Spine1", "mixamorig_Spine2", "mixamorig:Spine2"]:
			if skel.find_bone(n) >= 0:
				chest_idx = skel.find_bone(n)
				break
	if chest_idx < 0:
		return
	var cp: Vector3 = to_local(skel.global_transform * skel.get_bone_global_pose(chest_idx).origin)
	if not chest_ref_ok:
		chest_t += delta
		if cur_anim == "Idle" and chest_t > 0.4:
			chest_ref = cp; chest_ref_ok = true
		return
	var d := cp - chest_ref
	d.x *= 0.6
	if d.length() > 0.3:
		d = d.normalized() * 0.3
	aim_node.position = aim_node.position.lerp(AIM_BASE + d, min(delta * 18.0, 1.0))

func _bone(n: String) -> String:
	if skel == null:
		return ""
	var bip := {"RightArm": "Bip01 R UpperArm", "RightHand": "Bip01 R Hand", "LeftArm": "Bip01 L UpperArm", "LeftHand": "Bip01 L Hand", "Head": "Bip01 Head", "Spine": "Bip01 Spine", "Hips": "Bip01 Pelvis"}
	for cand in ["mixamorig_" + n, "mixamorig:" + n, n, bip.get(n, n), String(bip.get(n, n)).replace(" ", "_")]:
		if skel.find_bone(cand) >= 0:
			return cand
	return ""

var grip: SkeletonModifier3D

func _wrist_target(m: Node3D, side: String) -> Node3D:
	## IK aims the wrist slightly behind the grip marker so the palm (not the wrist) holds the gun
	if m == null:
		return null
	var t := Node3D.new()
	t.name = "wrist_" + side
	t.position = preload("res://scripts/hand_grip.gd").wrist_offset(side)
	m.add_child(t)
	return t

func _setup_ik() -> void:
	if skel == null:
		return
	if twist == null:
		twist = preload("res://scripts/twist_mod.gd").new()
		skel.add_child(twist)
		skel.move_child(twist, 0)
		twist.setup(skel)
	if ik_r: ik_r.queue_free()
	if ik_l: ik_l.queue_free()
	var rh := _wrist_target(gun.find_child("rhand", true, false) as Node3D, "R")
	var lh := _wrist_target(gun.find_child("lhand", true, false) as Node3D, "L")
	if rh:
		ik_r = SkeletonIK3D.new()
		ik_r.root_bone = _bone("RightArm")
		ik_r.tip_bone = _bone("RightHand")
		ik_r.override_tip_basis = false
		ik_r.use_magnet = true
		ik_r.magnet = Vector3(1.5, -1.0, 0.5)
		skel.add_child(ik_r)
		ik_r.target_node = ik_r.get_path_to(rh)
		ik_r.start()
	if lh and wdata["cat"] != "tabanca" and not wdata.get("melee", false):
		ik_l = SkeletonIK3D.new()
		ik_l.root_bone = _bone("LeftArm")
		ik_l.tip_bone = _bone("LeftHand")
		ik_l.override_tip_basis = false
		ik_l.use_magnet = true
		ik_l.magnet = Vector3(-1.5, -1.0, 0.5)
		skel.add_child(ik_l)
		ik_l.target_node = ik_l.get_path_to(lh)
		ik_l.start()
	# hands turned into a proper grip with curled fingers (runs after both IK solvers)
	if grip == null:
		grip = preload("res://scripts/hand_grip.gd").new()
		skel.add_child(grip)
	skel.move_child(grip, skel.get_child_count() - 1)
	grip.setup(skel, gun, wdata["cat"] == "tabanca")
	grip.active = not wdata.get("melee", false)

func _play(a: String, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(a):
		return
	if cur_anim != a:
		anim.play(a, 0.2)
		cur_anim = a
	anim.speed_scale = speed

# ---------------------------------------------------------------- AI
var tag_t := 0.0

func _update_tag(delta: float) -> void:
	tag_t -= delta
	if tag_t > 0:
		return
	tag_t = 0.1
	var pl = match_node.player
	if not alive or pl == null:
		name_tag.visible = false
		return
	var mate: bool = match_node.teams and team == pl.team
	if mate:
		# teammates: always shown (like Zula), but small and only within 60 m
		name_tag.no_depth_test = true
		name_tag.visible = pl.global_position.distance_to(global_position) < 60.0
		return
	# enemies: only when actually visible AND near the crosshair
	name_tag.no_depth_test = false
	var cam: Camera3D = pl.cam
	var head := global_position + Vector3(0, 1.6, 0)
	var to := head - cam.global_position
	var fwd := -cam.global_transform.basis.z
	var ang := fwd.angle_to(to)
	var vis := false
	if pl.alive and ang < deg_to_rad(5.0) and to.length() < 90.0:
		vis = match_node.los(cam.global_position, head)
	name_tag.visible = vis

func _physics_process(delta: float) -> void:
	_update_tag(delta)
	if not alive:
		_death_anim(delta)
		return
	if puppet:
		_puppet_step(delta)
		return
	if match_node.ended or match_node.paused:
		velocity = Vector3.ZERO
		_play("Idle")
		return
	var frozen: bool = match_node.countdown > 0
	fire_cd = max(fire_cd - delta, 0.0)
	burst_pause = max(burst_pause - delta, 0.0)
	if reload_t > 0:
		reload_t -= delta
		if reload_t <= 0:
			mag = int(wdata.get("mag", 1))
	think_t -= delta
	if think_t <= 0:
		think_t = randf_range(0.12, 0.22)
		_perceive()
	var move_dir := Vector3.ZERO
	var speed := 5.0 * float(wdata.get("speed", 1.0))
	var t := Time.get_ticks_msec() / 1000.0
	if target != null and is_instance_valid(target) and target.alive and target_visible:
		# engage
		var tp: Vector3 = target.chest_pos()
		if randf() < D_HEAD[difficulty] * 0.02:
			aim_err.y += 0.0
		var to: Vector3 = tp - (global_position + Vector3.UP * 1.45)
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		var rate: float = D_AIM[difficulty] * delta
		aim_yaw = rotate_toward(aim_yaw, want_yaw, rate)
		aim_pitch = move_toward(aim_pitch, want_pitch, rate)
		strafe_t -= delta
		if strafe_t <= 0:
			strafe_t = randf_range(0.6, 1.6)
			strafe_dir = [-1.0, 1.0, 0.0][randi() % 3]
			crouching = wdata.get("scope", false) and randf() < 0.5
		var right := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
		var dist := to.length()
		move_dir = right * strafe_dir
		if dist > float(wdata.get("range", 100.0)) * 0.6:
			move_dir += -Vector3(sin(aim_yaw), 0, cos(aim_yaw)) * 0.8
		elif wdata.get("melee", false) or (wid == "spas" and dist > 8):
			move_dir = -Vector3(sin(aim_yaw), 0, cos(aim_yaw)) + right * strafe_dir * 0.4
		speed *= 0.55 if not wdata.get("melee", false) else 1.0
		if crouching: speed *= 0.4
		if slow_t > 0:
			slow_t -= delta
			speed *= 0.6
		react_t -= delta
		var err: float = abs(angle_difference(aim_yaw, want_yaw)) + abs(want_pitch - aim_pitch)
		if react_t <= 0 and err < 0.12 + 1.5 / max(dist, 1.0) and not frozen:
			_fire(tp, dist)
	else:
		crouching = false
		var goal := Vector3.ZERO
		var has_goal := false
		if t - last_seen_t < 7.0:
			goal = last_seen; has_goal = true
		elif t - heard_t < 5.0:
			goal = heard_pos; has_goal = true
		elif has_roam:
			goal = roam_target; has_goal = true
		if not has_goal or global_position.distance_to(goal) < 2.0:
			if t - last_seen_t < 7.0 and global_position.distance_to(last_seen) < 2.0:
				last_seen_t = -100
			if t - heard_t < 5.0 and global_position.distance_to(heard_pos) < 2.0:
				heard_t = -100
			_pick_roam()
			goal = roam_target
		if nav.target_position.distance_to(goal) > 1.0:
			nav.target_position = goal
		var nxt := nav.get_next_path_position()
		var d := nxt - global_position
		d.y = 0
		if d.length() > 0.1:
			move_dir = d.normalized()
			var want := atan2(-move_dir.x, -move_dir.z)
			aim_yaw = rotate_toward(aim_yaw, want, delta * 6.0)
			aim_pitch = move_toward(aim_pitch, 0.0, delta * 2.0)
		if reload_t <= 0 and mag < int(wdata.get("mag", 1)) * 0.4 and not wdata.get("melee", false):
			_reload()
	if frozen:
		move_dir = Vector3.ZERO
	rotation.y = aim_yaw
	# gun lowered while reloading, kicked back while firing
	var rl: float = 1.0 if reload_t > 0 else 0.0
	# low-ready carry while sprinting without a target (rifle angled across the chest, like real soldiers)
	var hs0 := Vector2(velocity.x, velocity.z).length()
	var want_lr := 1.0 if (hs0 > 3.5 and not target_visible and fire_kick <= 0.01) else 0.0
	low_ready = move_toward(low_ready, want_lr, delta * 4.0)
	aim_node.rotation.x = lerp(lerp(aim_pitch, -0.42, low_ready), -0.75, rl * 0.85) + fire_kick * 0.05
	aim_node.rotation.z = rl * 0.5 + low_ready * 0.32
	aim_node.rotation.y = low_ready * 0.28
	_follow_chest(delta)
	if gun:
		gun.position = gun_base + Vector3(0, 0.012, 0.06) * fire_kick
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(move_dir.x, move_dir.z) * speed, 30.0 * delta)
	velocity.x = hv.x; velocity.z = hv.y
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	elif velocity.y < 0:
		velocity.y = 0
	if is_on_floor():
		_try_step(delta)
	var before := global_position
	move_and_slide()
	# stuck detection
	if move_dir.length() > 0.5 and global_position.distance_to(before) < speed * delta * 0.2:
		stuck_t += delta
		if stuck_t > 1.2:
			stuck_t = 0
			has_roam = false
			last_seen_t = -100
			if is_on_floor():
				velocity.y = 4.5
	else:
		stuck_t = max(stuck_t - delta, 0.0)
	_anim_tail(delta, hv)
	if global_position.y < -20:
		take_damage(1000, null, global_position, false, "")

func _anim_tail(delta: float, hv: Vector2) -> void:
	# animation
	var hs := hv.length()
	# legs follow the movement direction, the torso twists back toward the aim
	var want_leg := 0.0
	var backwards := false
	if hs > 0.4:
		var mv_yaw := atan2(-hv.x, -hv.y)
		var rel := wrapf(mv_yaw - aim_yaw, -PI, PI)
		if abs(rel) > deg_to_rad(110):
			backwards = true
			rel = wrapf(rel + PI, -PI, PI)
		want_leg = clamp(rel, -deg_to_rad(75), deg_to_rad(75))
	leg_yaw = lerp_angle(leg_yaw, want_leg, min(delta * 10.0, 1.0))
	if model and alive:
		model.rotation.y = PI + leg_yaw
	fire_kick = move_toward(fire_kick, 0.0, delta * 6.0)
	hit_react = move_toward(hit_react, 0.0, delta * 4.5)
	if twist:
		var hr := sin(hit_react * PI) if hit_react > 0 else 0.0
		twist.twist = -leg_yaw
		twist.hit_twist = hr * 0.35 * hit_dir
		# aiming up/down bends the spine (the weapon is in the hands, so it follows the chest)
		var rl2: float = 1.0 if reload_t > 0 else 0.0
		twist.lean = fire_kick * 0.12 + hr * (0.05 if hit_head else -0.28) + aim_pitch * 0.85 * (1.0 - rl2) - rl2 * 0.12
		if pose and alive and not wdata.get("melee", false):
			pose.weight = move_toward(pose.weight, 0.55 if reload_t > 0 else 1.0, delta * 5.0)
		twist.head_kick = hr * (0.6 if hit_head else 0.12)
	if hs > 3.5:
		_play("Run", (hs / 5.5) * (-1.0 if backwards else 1.0))
	elif hs > 0.4:
		_play("Walk", (hs / 1.8) * (-1.0 if backwards else 1.0))
	else:
		_play("Idle")
	# footsteps
	if is_on_floor() and hs > 1.2:
		step_t -= delta * (hs / 4.0)
		if step_t <= 0:
			step_t = 0.36 if hs > 3.5 else 0.5
			var surf: String = "metal" if match_node.surface == "metal" else "concrete"
			SFX.play3d("step_%s%d" % [surf, randi() % 4], global_position, -9 if hs > 3.5 else -14, randf_range(0.9, 1.1), 35.0, 3.0)
	if model:
		model.position.y = -0.35 if crouching else 0.0

func _try_step(delta: float) -> void:
	var hmove := Vector3(velocity.x, 0, velocity.z) * delta
	if hmove.length() < 0.0005 or not test_move(global_transform, hmove):
		return
	if test_move(global_transform, Vector3.UP * 0.42):
		return
	if test_move(global_transform.translated(Vector3.UP * 0.42), hmove * 1.5):
		return
	global_position.y += 0.42
	apply_floor_snap()

func _pick_roam() -> void:
	var map := get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_random_point(map, 1, false)
	if p == Vector3.ZERO or p.distance_to(global_position) < 6:
		var sp: Array = match_node.spawn_points
		if sp.size() > 0:
			p = sp[randi() % sp.size()]["pos"]
	roam_target = p
	has_roam = true

func _perceive() -> void:
	var best = null
	var best_d := 1e9
	var eye := global_position + Vector3.UP * 1.6
	var fwd := -Vector3(sin(aim_yaw), 0, cos(aim_yaw))
	var view: float = D_VIEW[difficulty]
	for c in match_node.combatants:
		var n = c["node"]
		if n == self or not is_instance_valid(n) or not n.alive:
			continue
		if team != "" and n.team == team:
			continue
		var tp: Vector3 = n.chest_pos()
		var to := tp - eye
		var d := to.length()
		if d > view:
			continue
		var in_fov = fwd.dot(Vector3(to.x, 0, to.z).normalized()) > 0.25 or d < 9.0 or n == target
		if not in_fov:
			continue
		if not match_node.los(eye, tp, [get_rid(), n.get_rid()]):
			continue
		var score := d * (0.7 if n == target else 1.0) * (0.85 if n.is_player else 1.0)
		if score < best_d:
			best_d = score
			best = n
	var was := target_visible
	if best != null:
		if best != target or not was:
			react_t = D_REACT[difficulty] * randf_range(0.8, 1.3)
		target = best
		target_visible = true
		last_seen = best.global_position
		last_seen_t = Time.get_ticks_msec() / 1000.0
	else:
		target_visible = false

func hear(pos: Vector3) -> void:
	if target_visible:
		return
	if global_position.distance_to(pos) < 45.0:
		heard_pos = pos
		heard_t = Time.get_ticks_msec() / 1000.0

func _fire(tp: Vector3, dist: float) -> void:
	if fire_cd > 0 or reload_t > 0 or burst_pause > 0:
		return
	if wdata.get("melee", false):
		if dist < 2.3:
			fire_cd = 0.7
			SFX.play3d("knife_swing", global_position, -2)
			match_node.melee(self, global_position + Vector3.UP * 1.5, (tp - (global_position + Vector3.UP * 1.5)).normalized(), float(wdata["dmg"]), wid)
		return
	if mag <= 0:
		_reload()
		return
	if dist > float(wdata.get("range", 100.0)) * 1.2:
		return
	mag -= 1
	fire_kick = min(fire_kick + 0.55, 1.0)
	fire_cd = 60.0 / float(wdata["rpm"]) * (1.0 if difficulty > 0 else 1.25)
	if wdata.get("auto", false):
		if burst_left <= 0:
			burst_left = randi_range(3, 4 + difficulty * 3) if dist > 15 else randi_range(5, 12)
		burst_left -= 1
		if burst_left <= 0:
			burst_pause = randf_range(0.25, 0.6) * (1.6 - difficulty * 0.3)
	var eye := global_position + Vector3.UP * (1.5 if not crouching else 1.1)
	var aim_pt := tp
	if randf() < D_HEAD[difficulty]:
		aim_pt = target.global_position + Vector3.UP * (1.62 if not target.crouching else 1.05)
	var dir := (aim_pt - eye).normalized()
	var sp: float = D_SPREAD[difficulty] * (1.0 + dist / 60.0)
	if wdata.get("scope", false):
		sp *= 0.5
	var pellets := int(wdata.get("pellets", 1))
	for i in pellets:
		var d2 := _spread(dir, sp + (float(wdata.get("spread", 0.0)) if pellets > 1 else 0.0))
		var res: Dictionary = match_node.hitscan(self, eye, d2, wid, float(wdata["dmg"]), float(wdata.get("range", 150.0)), float(wdata.get("head", 2.5)))
		if i < 2:
			var mp: Vector3 = muzzle.global_position if muzzle else eye
			match_node.fx.tracer(mp, res.get("pos", eye + d2 * 60.0))
	var mp2: Vector3 = muzzle.global_position if muzzle else eye
	# distant gunfire gets its own low-passed, echoey recording
	var snd: String = wdata["snd"]
	var pl = match_node.player
	if pl and is_instance_valid(pl) and pl.global_position.distance_to(mp2) > 38.0 and ResourceLoader.exists("res://assets/sfx/%s.wav" % snd.replace("shot_", "shotfar_")):
		snd = snd.replace("shot_", "shotfar_")
	SFX.play3d(snd, mp2, 2.0, randf_range(0.96, 1.04), 220.0, 14.0)
	match_node.fx.muzzle_light(mp2, 2.0)
	match_node.on_shot_fired(self, global_position)
	_bot_flash(mp2)

var _flash: MeshInstance3D
func _bot_flash(p: Vector3) -> void:
	if _flash == null:
		_flash = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.35)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_texture = load("res://assets/fx/flash.png")
		fm.albedo_color = Color(1, 0.85, 0.6) * 1.5
		q.material = fm
		_flash.mesh = q
		_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flash)
	_flash.global_position = p
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture = load("res://assets/fx/flash%d.png" % (randi() % 3))
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	get_tree().create_timer(0.04).timeout.connect(func(): if is_instance_valid(_flash): _flash.visible = false)

func _spread(fwd: Vector3, sp: float) -> Vector3:
	var r := sqrt(randf()) * sp
	var a := randf() * TAU
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	return (fwd + right * cos(a) * r + up * sin(a) * r).normalized()

func _reload() -> void:
	if reload_t > 0 or wdata.get("melee", false):
		return
	reload_t = float(wdata.get("reload", 2.0)) * (int(wdata.get("mag", 1)) if wdata.get("shell_reload", false) else 1) * 0.6
	SFX.play3d("mag_out", global_position, -6, 1.0, 25.0, 3.0)

## ---------------------------------------------------------------- network puppet (another real player)
var puppet := false
var net_id := ""
var net_pos := Vector3.ZERO
var net_vel := Vector2.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_t := 0.0
var _net_force := false

func net_state(d: Dictionary) -> void:
	var p: Array = d.get("p", [0, 0, 0])
	var np := Vector3(float(p[0]), float(p[1]), float(p[2]))
	if net_t == 0.0 or np.distance_to(global_position) > 6.0:
		global_position = np        # first packet or teleport (respawn)
		reset_physics_interpolation()
	net_pos = np
	var v: Array = d.get("v", [0, 0])
	net_vel = Vector2(float(v[0]), float(v[1]))
	net_yaw = float(d.get("yw", 0.0))
	net_pitch = float(d.get("pt", 0.0))
	crouching = bool(d.get("c", false))
	net_t = Time.get_ticks_msec() / 1000.0
	var w := str(d.get("w", wid))
	if w != wid and GS.WEAPONS.has(w):
		set_weapon(w)
	var al := bool(d.get("a", true))
	if al and not alive:
		respawn(np, net_yaw, w)
	reload_t = 0.3 if bool(d.get("r", false)) else 0.0

func _puppet_step(delta: float) -> void:
	# smooth toward the last network state, extrapolating a little with its velocity
	var age: float = clamp(Time.get_ticks_msec() / 1000.0 - net_t, 0.0, 0.25)
	var goal := net_pos + Vector3(net_vel.x, 0, net_vel.y) * age
	global_position = global_position.lerp(goal, min(delta * 14.0, 1.0))
	aim_yaw = lerp_angle(aim_yaw, net_yaw, min(delta * 18.0, 1.0))
	aim_pitch = lerp(aim_pitch, net_pitch, min(delta * 18.0, 1.0))
	rotation.y = aim_yaw
	fire_cd = max(fire_cd - delta, 0.0)
	_follow_chest(delta)
	if gun:
		gun.position = gun_base + Vector3(0, 0.012, 0.06) * fire_kick
	_anim_tail(delta, net_vel)

func net_fire(w: String) -> void:
	## visual + audio of a remote player's shot (hits are reported by the shooter)
	if not alive:
		return
	if w != wid and GS.WEAPONS.has(w):
		set_weapon(w)
	fire_kick = min(fire_kick + 0.55, 1.0)
	var mp2: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 1.45
	var fs := GS.full_stats(w) if GS.WEAPONS.has(w) else wdata
	var snd: String = "shot_sup" if fs.get("silenced", false) else str(wdata.get("snd", "shot_ak"))
	var pl = match_node.player
	if not fs.get("silenced", false) and pl and is_instance_valid(pl) and pl.global_position.distance_to(mp2) > 38.0 and ResourceLoader.exists("res://assets/sfx/%s.wav" % snd.replace("shot_", "shotfar_")):
		snd = snd.replace("shot_", "shotfar_")
	SFX.play3d(snd, mp2, 2.0, randf_range(0.96, 1.04), 220.0, 14.0)
	if not fs.get("silenced", false):
		match_node.fx.muzzle_light(mp2, 2.0)
		_bot_flash(mp2)
	var dir := Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))
	match_node.fx.tracer(mp2, mp2 + dir * 60.0)

func net_die(killer, w: String, head: bool) -> void:
	if not alive:
		return
	_net_force = true
	take_damage(99999, killer, global_position + Vector3.UP * 1.4 - Vector3(-sin(aim_yaw), 0, -cos(aim_yaw)) * 2.0, head, w)
	_net_force = false

var slow_t := 0.0

func take_damage(amount: float, attacker, pos: Vector3, headshot: bool, w: String) -> void:
	if not alive or match_node.ended:
		return
	if puppet and not _net_force:
		# another real player: tell them they were hit; they apply the damage and report their death
		if attacker == match_node.player and match_node.net:
			match_node.net.send_hit(self, amount, pos, headshot, w)
		hit_react = 1.0
		hit_head = headshot
		return
	health -= amount
	if GS.ball(w).get("abil", "") == "slow":
		slow_t = 0.9
	# hit reaction: torso jerks, head snaps on headshots, small stagger away from the shot
	if health > 0:
		var away := global_position - pos
		away.y = 0
		if away.length() > 0.01:
			velocity += away.normalized() * (1.6 if headshot else 1.0)
		hit_react = 1.0
		hit_dir = -1.0 if randf() < 0.5 else 1.0
		hit_head = headshot
		SFX.play3d("hurt", global_position, -10, randf_range(0.85, 1.05), 30.0, 3.0)
	if attacker != null and is_instance_valid(attacker) and attacker != self:
		if not target_visible:
			last_seen = attacker.global_position
			last_seen_t = Time.get_ticks_msec() / 1000.0
			var to: Vector3 = attacker.global_position - global_position
			aim_yaw = rotate_toward(aim_yaw, atan2(-to.x, -to.z), 1.2)
	if health <= 0:
		health = 0
		alive = false
		death_t = 0.0
		death_head = headshot
		death_spin = randf_range(-0.8, 0.8) if not headshot else randf_range(-0.25, 0.25)
		if twist:
			twist.twist = 0.0; twist.hit_twist = 0.0
			twist.lean = 0.18 if headshot else -0.1
			twist.head_kick = 0.9 if headshot else 0.25
		death_fx_done = false
		var fd := global_position - pos
		fd.y = 0
		if fd.length() < 0.01:
			fd = global_transform.basis.z
		fd = global_transform.basis.inverse() * fd.normalized()
		fd = fd.rotated(Vector3.UP, randf_range(-0.35, 0.35))
		death_axis = Vector3.UP.cross(fd).normalized()
		var hp: Vector3 = global_position + Vector3(0, 1.6 if not crouching else 1.05, 0)
		match_node.fx.death_burst(hp if headshot else global_position + Vector3(0, 1.15, 0), (global_position - pos).normalized(), headshot)
		collision_layer = 0
		collision_mask = 1
		name_tag.visible = false
		if ik_r: ik_r.stop()
		if ik_l: ik_l.stop()
		if pose: pose.weight = 0.0
		if anim: anim.pause()
		_drop_gun()
		match_node.on_death(self, attacker, w, headshot)

func _drop_gun() -> void:
	if gun == null:
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(0.08, 0.15, 0.7)
	cs.shape = bs
	rb.add_child(cs)
	match_node.add_child(rb)
	rb.global_transform = gun.global_transform
	gun.reparent(rb)
	rb.linear_velocity = velocity * 0.5 + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
	rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	gun = null
	get_tree().create_timer(6.0).timeout.connect(rb.queue_free)

func _death_anim(delta: float) -> void:
	death_t += delta
	if model:
		# knees buckle first, then the body topples away from the shooter
		var buckle: float = clamp(death_t / 0.18, 0.0, 1.0)
		var t0 := 0.06 if death_head else 0.16
		var k: float = clamp((death_t - t0) / (0.42 if death_head else 0.6), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var bounce := 0.0
		if k >= 1.0:
			bounce = sin(clamp((death_t - t0 - 0.6) / 0.25, 0.0, 1.0) * PI) * 0.06
		var ang := k * PI * 0.5 * 0.97 - bounce
		var b := Basis(death_axis, ang) * Basis(Vector3.UP, PI + leg_yaw + death_spin * k)
		model.transform = Transform3D(b, Vector3(0, -0.22 * buckle * (1.0 - k) - 0.1 * k, 0))
		if k >= 1.0 and not death_fx_done:
			death_fx_done = true
			SFX.play3d("bodyfall", global_position, -4, randf_range(0.9, 1.1), 30.0, 4.0)
			match_node.fx.blood_pool(global_position + global_transform.basis * (death_axis.cross(Vector3.UP) * 0.9))
	if not is_on_floor():
		velocity.y -= 16.0 * delta
		move_and_slide()

func respawn(pos: Vector3, yaw_: float, weapon: String) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	aim_yaw = yaw_
	aim_pitch = 0
	health = 100
	alive = true
	collision_layer = 2
	collision_mask = 1 | 2
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	target = null
	target_visible = false
	last_seen_t = -100
	has_roam = false
	if anim: anim.play("Idle")
	set_weapon(weapon)

func chest_pos() -> Vector3:
	return global_position + Vector3.UP * (1.25 if not crouching else 0.9)

func eye_pos() -> Vector3:
	return global_position + Vector3.UP * 1.6
