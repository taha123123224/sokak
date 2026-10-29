extends SkeletonModifier3D
## Upper-body weapon pose for bots: shouldered rifle / two-hand pistol, solved offline in Blender
## (tools/rb_aim.py) so both hands sit exactly on the weapon. Legs keep their walk/run animation.

var poses := {}            # kind -> {bone_idx: Quaternion}
var kind := "rifle"
var weight := 1.0          # 0 = animation only, 1 = full aim pose
var dbg_chain := Vector3.ZERO

func setup(sk: Skeleton3D, ap: AnimationPlayer) -> void:
	for k: String in ["rifle", "pistol"]:
		var an: String = "Aim" + k.capitalize()
		if ap == null or not ap.has_animation(an):
			continue
		var a: Animation = ap.get_animation(an)
		var d := {}
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bn := String(a.track_get_path(t).get_concatenated_subnames())
			if not _upper(bn):
				continue
			var bi := sk.find_bone(bn)
			if bi >= 0:
				d[bi] = a.rotation_track_interpolate(t, 0.0)
		poses[k] = d

static func _upper(bn: String) -> bool:
	for key in ["Clavicle", "UpperArm", "Forearm", "ForeTwist", "UpArmTwist", "Hand", "Finger", "Neck", "Head", "Spine1", "Spine2"]:
		if key in bn:
			return true
	return false

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.001 or not poses.has(kind):
		return
	var d: Dictionary = poses[kind]
	for bi in d:
		var q: Quaternion = d[bi]
		if weight >= 0.999:
			sk.set_bone_pose_rotation(bi, q)
		else:
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(q, weight))
	if OS.has_environment("POSEDBG") and Engine.get_process_frames() % 60 == 0:
		var l := sk.get_bone_global_pose(sk.find_bone("Bip01 L Hand")).origin
		var r := sk.get_bone_global_pose(sk.find_bone("Bip01 R Hand")).origin
		var ua := sk.get_bone_global_pose(sk.find_bone("Bip01 R UpperArm")).origin
		print("POSEDBG hands ", l.distance_to(r), " L ", l, " R ", r, " Rchain ", dbg_chain)

## weapon grip transform in skeleton space, relative to the right hand bone, for the given pose
func hand_offset(sk: Skeleton3D, ap: AnimationPlayer, k: String, grip_root: Transform3D, root_to_skel: Transform3D) -> Transform3D:
	var a: Animation = ap.get_animation("Aim" + k.capitalize())
	var rot := {}; var pos := {}
	for t in a.get_track_count():
		var bn := String(a.track_get_path(t).get_concatenated_subnames())
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot[bi] = a.rotation_track_interpolate(t, 0.0)
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos[bi] = a.position_track_interpolate(t, 0.0)
	var hand := sk.find_bone("Bip01 R Hand")
	var chain: Array = []
	var b := hand
	while b >= 0:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	var T := Transform3D()
	for bi in chain:
		var rest := sk.get_bone_rest(bi)
		var q: Quaternion = rot.get(bi, rest.basis.get_rotation_quaternion())
		var p: Vector3 = pos.get(bi, rest.origin)
		T = T * Transform3D(Basis(q), p)
	dbg_chain = T.origin
	var gsk := root_to_skel.affine_inverse() * grip_root
	return T.affine_inverse() * gsk
