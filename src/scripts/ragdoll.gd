## v3.4 death ragdoll: a light physical skeleton (11 capsules) built once per character and switched on
## when it dies. Works on both rigs the game uses (Rocketbox "Bip01 *" and Mixamo "mixamorig_*").
## Bodies only collide with the world (layer 1), so corpses never block bullets or players.
extends RefCounted

const RB := {
	"pelvis": "Bip01 Pelvis", "chest": "Bip01 Spine2", "head": "Bip01 Head",
	"luarm": "Bip01 L UpperArm", "lfarm": "Bip01 L Forearm", "lhand": "Bip01 L Hand",
	"ruarm": "Bip01 R UpperArm", "rfarm": "Bip01 R Forearm", "rhand": "Bip01 R Hand",
	"lthigh": "Bip01 L Thigh", "lcalf": "Bip01 L Calf", "lfoot": "Bip01 L Foot",
	"rthigh": "Bip01 R Thigh", "rcalf": "Bip01 R Calf", "rfoot": "Bip01 R Foot", "neck": "Bip01 Neck",
}
const MX := {
	"pelvis": "mixamorig_Hips", "chest": "mixamorig_Spine2", "head": "mixamorig_Head",
	"luarm": "mixamorig_LeftArm", "lfarm": "mixamorig_LeftForeArm", "lhand": "mixamorig_LeftHand",
	"ruarm": "mixamorig_RightArm", "rfarm": "mixamorig_RightForeArm", "rhand": "mixamorig_RightHand",
	"lthigh": "mixamorig_LeftUpLeg", "lcalf": "mixamorig_LeftLeg", "lfoot": "mixamorig_LeftFoot",
	"rthigh": "mixamorig_RightUpLeg", "rcalf": "mixamorig_RightLeg", "rfoot": "mixamorig_RightFoot", "neck": "mixamorig_Neck",
}
# [part, end part (capsule runs bone -> end), radius (m), mass, joint]
const SEGS := [
	["pelvis", "chest", 0.13, 12.0, "pin"],
	["chest", "neck", 0.15, 14.0, "cone"],
	["head", "", 0.11, 5.0, "cone"],
	["luarm", "lfarm", 0.055, 2.5, "cone"], ["lfarm", "lhand", 0.045, 1.6, "hinge"],
	["ruarm", "rfarm", 0.055, 2.5, "cone"], ["rfarm", "rhand", 0.045, 1.6, "hinge"],
	["lthigh", "lcalf", 0.08, 7.0, "cone"], ["lcalf", "lfoot", 0.06, 4.0, "hinge"],
	["rthigh", "rcalf", 0.08, 7.0, "cone"], ["rcalf", "rfoot", 0.06, 4.0, "hinge"],
]

static func build(sk: Skeleton3D) -> PhysicalBoneSimulator3D:
	var map: Dictionary = RB if sk.find_bone(RB["pelvis"]) >= 0 else (MX if sk.find_bone(MX["pelvis"]) >= 0 else {})
	if map.is_empty():
		return null
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	sk.add_child(sim)
	var sc: float = sk.global_transform.basis.get_scale().x
	if sc <= 0.0001:
		sc = 1.0
	for sg in SEGS:
		var bi := sk.find_bone(map[sg[0]])
		if bi < 0:
			continue
		var bp: Transform3D = sk.get_bone_global_rest(bi)
		var a: Vector3 = bp.origin
		var b: Vector3
		if str(sg[1]) != "" and sk.find_bone(map[sg[1]]) >= 0:
			b = sk.get_bone_global_rest(sk.find_bone(map[sg[1]])).origin
		else:
			b = a + bp.basis.y.normalized() * (0.24 / sc)
		var pb := PhysicalBone3D.new()
		pb.name = "pb_" + sg[0]
		pb.bone_name = map[sg[0]]
		pb.mass = float(sg[3])
		pb.friction = 0.8
		pb.bounce = 0.0
		pb.linear_damp = 0.2
		pb.angular_damp = 2.5
		pb.collision_layer = 0
		pb.collision_mask = 1
		pb.transform = bp
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var r: float = float(sg[2]) / sc
		var ln: float = maxf(a.distance_to(b), r * 2.2)
		cap.radius = r
		cap.height = ln + r
		cs.shape = cap
		# capsule from the joint toward the next joint, expressed in the bone's frame
		var dir_l: Vector3 = (bp.basis.inverse() * (b - a)).normalized()
		var up := Vector3.UP
		var bas := Basis.IDENTITY
		if dir_l.cross(up).length() > 0.001:
			bas = Basis(dir_l.cross(up).normalized(), dir_l.angle_to(up) * -1.0)
		elif dir_l.dot(up) < 0:
			bas = Basis(Vector3.RIGHT, PI)
		var sc_l: Vector3 = bp.basis.get_scale()
		cs.transform = Transform3D(bas, dir_l * (a.distance_to(b) * 0.5) / maxf(sc_l.x, 0.0001))
		pb.add_child(cs)
		match str(sg[4]):
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", 50.0)
				pb.set("joint_constraints/twist_span", 25.0)
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_upper", 5.0)
				pb.set("joint_constraints/angular_limit_lower", -130.0)
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		sim.add_child(pb)
	return sim

## switch the other skeleton modifiers off so they do not fight the simulation
static func start(sk: Skeleton3D, sim: PhysicalBoneSimulator3D, impulse: Vector3, at: Vector3, head: bool) -> void:
	for c in sk.get_children():
		if c is SkeletonModifier3D and c != sim:
			c.set_meta("rd_was", (c as SkeletonModifier3D).active)
			(c as SkeletonModifier3D).active = false
	sk.move_child(sim, sk.get_child_count() - 1)
	sim.active = true
	sim.influence = 1.0
	sim.physical_bones_start_simulation()
	var best: PhysicalBone3D = null
	var bd := INF
	for pb in sim.get_children():
		if pb is PhysicalBone3D:
			var d: float = (pb as PhysicalBone3D).global_position.distance_to(at)
			if head and str(pb.name) == "pb_head":
				d = -1.0
			if d < bd:
				bd = d; best = pb
			(pb as PhysicalBone3D).apply_central_impulse(impulse * 0.12 * (pb as PhysicalBone3D).mass)
	if best:
		best.apply_central_impulse(impulse * best.mass * 0.6)

static func stop(sk: Skeleton3D, sim: PhysicalBoneSimulator3D) -> void:
	if sim == null or not is_instance_valid(sim):
		return
	sim.physical_bones_stop_simulation()
	sim.active = false
	for c in sk.get_children():
		if c is SkeletonModifier3D and c.has_meta("rd_was"):
			(c as SkeletonModifier3D).active = bool(c.get_meta("rd_was"))
			c.remove_meta("rd_was")
