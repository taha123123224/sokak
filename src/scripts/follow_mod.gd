extends SkeletonModifier3D
## Runs last: keeps a node (the bot's weapon) locked to a bone of the FINAL modified pose.
## (BoneAttachment3D reads the pose before the other modifiers, so the weapon drifted off the hands.)

var target: Node3D
var bone := -1
var offset := Transform3D()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or bone < 0 or target == null or not is_instance_valid(target):
		return
	target.global_transform = sk.global_transform * sk.get_bone_global_pose(bone) * offset
