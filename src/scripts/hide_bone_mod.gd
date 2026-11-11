extends SkeletonModifier3D
## Collapses a bone chain to nothing (CS-style knife view: only the knife hand is shown)
var bones: PackedInt32Array = []

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in bones:
		sk.set_bone_pose_scale(b, Vector3.ONE * 0.0005)
