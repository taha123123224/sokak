extends SkeletonModifier3D
## Runs after the arm IK: turns both hands to a real weapon grip (right hand around the pistol
## grip, left hand cupping the handguard) and curls the fingers, so bots hold guns like the
## first-person arms do instead of with flat, twisted hands.

var gun: Node3D
var pistol := false
var hands := {}      # side -> {bone, parent, fl, sl, fingers:[{bone, amt}], fw, pw}

const FWD_R := Vector3(-0.25, -0.3, -0.92)   # weapon space, wrist -> knuckles (wraps the grip)
const PALM_R := Vector3(-1.0, 0.1, 0.0)      # palm faces the grip (to the left)
const FWD_L := Vector3(0.32, 0.12, -0.94)
const PALM_L := Vector3(0.42, 0.9, 0.0)      # palm under the handguard

func setup(sk: Skeleton3D, g: Node3D, is_pistol: bool) -> void:
	gun = g
	pistol = is_pistol
	hands.clear()
	for side in ["R", "L"]:
		var hb := sk.find_bone("Bip01 %s Hand" % side)
		if hb < 0:
			continue
		var mid := sk.find_bone("Bip01 %s Finger2" % side)
		var th := sk.find_bone("Bip01 %s Finger0" % side)
		if mid < 0 or th < 0:
			continue
		var fl: Vector3 = sk.get_bone_rest(mid).origin.normalized()
		var tl: Vector3 = sk.get_bone_rest(th).origin
		var side_l: Vector3 = (tl - fl * tl.dot(fl)).normalized()   # toward the thumb
		var palm_l: Vector3 = fl.cross(side_l).normalized()
		# palm is the side the fingers curl toward: curl is a +Z rotation in Biped finger space
		var curl_dir: Vector3 = Basis(Vector3(0, 0, 1), 0.5) * fl
		if (curl_dir - fl).dot(palm_l) < 0:
			palm_l = -palm_l
		var fingers := []
		for fi in [1, 2, 3, 4]:
			for seg in ["", "1", "2"]:
				var b := sk.find_bone("Bip01 %s Finger%d%s" % [side, fi, seg])
				if b >= 0:
					var amt := 1.05
					if side == "R" and fi == 1:
						amt = 0.35 if seg == "" else 0.55   # trigger finger stays straighter
					elif side == "L":
						amt = 0.85
					fingers.append({"bone": b, "amt": amt})
		for seg in ["", "1", "2"]:
			var b2 := sk.find_bone("Bip01 %s Finger0%s" % [side, seg])
			if b2 >= 0 and seg != "":
				fingers.append({"bone": b2, "amt": 0.45})
		hands[side] = {"bone": hb, "parent": sk.get_bone_parent(hb), "fl": fl, "pl": palm_l, "fingers": fingers,
			"fw": (FWD_R if side == "R" else FWD_L).normalized(), "pw": (PALM_R if side == "R" else PALM_L).normalized()}

## wrist position (weapon space) for a grip marker, so the palm, not the wrist, sits on the grip
static func wrist_offset(side: String) -> Vector3:
	if side == "R":
		# pistol grip centre sits ~4 cm under the receiver origin
		return Vector3(0, -0.04, 0.012) - FWD_R.normalized() * 0.06 - PALM_R.normalized() * 0.032
	return -FWD_L.normalized() * 0.07 - PALM_L.normalized() * 0.035

func _basis_from(f: Vector3, p: Vector3) -> Basis:
	var x := f.normalized()
	var z := x.cross(p).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or gun == null or not is_instance_valid(gun) or not gun.is_inside_tree():
		return
	var gb: Basis = (sk.global_transform.basis.inverse() * gun.global_transform.basis).orthonormalized()
	for side in hands.keys():
		if side == "L" and pistol:
			# two-handed pistol: support hand wraps the shooting hand
			pass
		var h: Dictionary = hands[side]
		var want_f: Vector3 = gb * (h["fw"] as Vector3)
		var want_p: Vector3 = gb * (h["pw"] as Vector3)
		var bw := _basis_from(want_f, want_p)
		var bl := _basis_from(h["fl"], h["pl"])
		var target_global: Basis = bw * bl.inverse()
		var pg: Basis = sk.get_bone_global_pose(h["parent"]).basis if int(h["parent"]) >= 0 else Basis()
		var local: Basis = (pg.inverse() * target_global).orthonormalized()
		sk.set_bone_pose_rotation(h["bone"], local.get_rotation_quaternion())
		for fd in h["fingers"]:
			var b: int = fd["bone"]
			var rest_q: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(b, rest_q * Quaternion(Vector3(0, 0, 1), float(fd["amt"])))
