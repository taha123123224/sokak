extends SkeletonModifier3D
## Upper-body twist (legs follow movement, torso keeps aiming) + firing recoil lean.

var twist := 0.0     # radians around the character's up axis, spread over the spine chain
var lean := 0.0      # radians, positive = torso leans back (recoil)
var bones: PackedInt32Array = []
var head_kick := 0.0   # radians, head snaps back when hit in the head
var hit_twist := 0.0  # extra torso twist from a body hit
var head := -1
var head_yaw := 0.0   # radians: head turns (lobby idle look-around)
var head_pitch := 0.0
var arms_drop := 0.0  # radians: both arms swing down together about the shoulder line (lobby low-ready)
var arms: PackedInt32Array = []

func setup(sk: Skeleton3D) -> void:
	bones.clear()
	for hn in ["Bip01 Head", "mixamorig_Head"]:
		if sk.find_bone(hn) >= 0:
			head = sk.find_bone(hn)
	arms.clear()
	for an in ["Bip01 R UpperArm", "Bip01 L UpperArm", "mixamorig_RightArm", "mixamorig_LeftArm"]:
		if sk.find_bone(an) >= 0:
			arms.append(sk.find_bone(an))
	for n in ["Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]:
		var i := sk.find_bone(n)
		if i >= 0:
			bones.append(i)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or bones.is_empty():
		return
	if abs(arms_drop) > 0.001:
		for a in arms:
			var pa := sk.get_bone_parent(a)
			var pgb: Basis = sk.get_bone_global_pose(pa).basis.orthonormalized() if pa >= 0 else Basis()
			var axis := (pgb.inverse() * Vector3.RIGHT).normalized()
			sk.set_bone_pose_rotation(a, Quaternion(axis, arms_drop) * sk.get_bone_pose_rotation(a))
	if abs(twist) < 0.001 and abs(lean) < 0.001 and abs(head_kick) < 0.001 and abs(hit_twist) < 0.001 and abs(head_yaw) < 0.001 and abs(head_pitch) < 0.001:
		return
	var per_t := (twist + hit_twist) / bones.size()
	var per_l := lean / bones.size()
	for b in bones:
		var par := sk.get_bone_parent(b)
		var pg: Basis = sk.get_bone_global_pose(par).basis if par >= 0 else Basis()
		var inv := pg.inverse()
		var up_l := (inv * Vector3.UP).normalized()
		var right_l := (inv * Vector3.RIGHT).normalized()
		var r := sk.get_bone_pose_rotation(b)
		var q := Quaternion(up_l, per_t) * Quaternion(right_l, per_l)
		sk.set_bone_pose_rotation(b, q * r)
	if head >= 0 and (abs(head_yaw) > 0.001 or abs(head_pitch) > 0.001):
		var par3 := sk.get_bone_parent(head)
		var pg3: Basis = sk.get_bone_global_pose(par3).basis.orthonormalized() if par3 >= 0 else Basis()
		var inv3 := pg3.inverse()
		var q3 := Quaternion((inv3 * Vector3.UP).normalized(), head_yaw) * Quaternion((inv3 * Vector3.RIGHT).normalized(), head_pitch)
		sk.set_bone_pose_rotation(head, q3 * sk.get_bone_pose_rotation(head))
	if head >= 0 and abs(head_kick) > 0.001:
		var par2 := sk.get_bone_parent(head)
		var pg2: Basis = sk.get_bone_global_pose(par2).basis if par2 >= 0 else Basis()
		var right2 := (pg2.inverse() * Vector3.RIGHT).normalized()
		sk.set_bone_pose_rotation(head, Quaternion(right2, head_kick) * sk.get_bone_pose_rotation(head))
