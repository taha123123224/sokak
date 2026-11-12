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

var throw_k := -1.0         # v4.1: 0..1 while the bot throws a grenade (procedural overarm throw)
var fwd_world := Vector3.FORWARD
var _ua := -2
var _fa := -1
var _hd := -1
var _lua := -1
var _lfa := -1
var _lhd := -1

func _aim_bone(sk: Skeleton3D, b: int, child: int, want: Vector3, w: float) -> void:
	## rotate bone b (skeleton space) so that the segment b -> child points along `want`
	var gp := sk.get_bone_global_pose(b)
	var cp := sk.get_bone_global_pose(child)
	var cur := (cp.origin - gp.origin).normalized()
	var wd := want.normalized()
	if cur.length() < 0.5 or wd.length() < 0.5:
		return
	var full := Quaternion(cur, wd)
	var q := Quaternion.IDENTITY.slerp(full, w)
	var ng := Transform3D(Basis(q) * gp.basis, gp.origin)
	sk.set_bone_global_pose(b, ng)

func _throw_pose(sk: Skeleton3D) -> void:
	if _ua == -2:
		_ua = sk.find_bone("Bip01 R UpperArm"); _fa = sk.find_bone("Bip01 R Forearm"); _hd = sk.find_bone("Bip01 R Hand")
		_lua = sk.find_bone("Bip01 L UpperArm"); _lfa = sk.find_bone("Bip01 L Forearm"); _lhd = sk.find_bone("Bip01 L Hand")
	if _ua < 0 or _fa < 0 or _hd < 0:
		return
	var inv := sk.global_transform.basis.inverse()
	var f := (inv * fwd_world).normalized()
	var u := (inv * Vector3.UP).normalized()
	var r := f.cross(u).normalized()
	var k := throw_k
	var w := smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.75, 1.0, k))
	var ua_d: Vector3; var fa_d: Vector3
	if k < 0.4:
		var e := smoothstep(0.0, 0.4, k)
		ua_d = (-u).lerp(u * 0.55 - f * 0.55 + r * 0.55, e)
		fa_d = (-u * 0.3 + f).lerp(u * 0.9 - f * 0.2, e)
	elif k < 0.55:
		var e2 := smoothstep(0.4, 0.55, k)
		ua_d = (u * 0.55 - f * 0.55 + r * 0.55).lerp(f * 0.9 + u * 0.35 + r * 0.25, e2)
		fa_d = (u * 0.9 - f * 0.2).lerp(f + u * 0.15, e2)
	else:
		var e3 := smoothstep(0.55, 1.0, k)
		ua_d = (f * 0.9 + u * 0.35 + r * 0.25).lerp(f * 0.4 - u * 0.8 - r * 0.1, e3)
		fa_d = (f + u * 0.15).lerp(f * 0.6 - u * 0.6, e3)
	_aim_bone(sk, _ua, _fa, ua_d, w)
	_aim_bone(sk, _fa, _hd, fa_d, w)
	# off hand points at the target during the wind-up (classic throw stance)
	if _lua >= 0 and _lfa >= 0 and _lhd >= 0:
		var lw := w * (1.0 - smoothstep(0.45, 0.7, k))
		_aim_bone(sk, _lua, _lfa, f * 0.85 + u * 0.25 - r * 0.25, lw)
		_aim_bone(sk, _lfa, _lhd, f + u * 0.2, lw)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk != null and throw_k >= 0.0:
		_throw_pose(sk)
		return
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
