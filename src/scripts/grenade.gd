extends RigidBody3D

var match_node
var thrower
var fuse := 2.4
var last_bounce := 0.0
var is_smoke := false
var visual_only := false   # a teammate's/opponent's grenade seen over the network: effects only, no damage

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = 0
	collision_mask = 1
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.06
	cs.shape = s
	add_child(cs)
	var ps: PackedScene = load("res://assets/models/w_frag.glb")
	var m := ps.instantiate()
	MatLib.apply(m)
	add_child(m)
	var pin := m.find_child("pin", true, false)
	if pin: pin.visible = false
	if is_smoke:
		fuse = 1.6
		# olive-drab M18 can: recolour the frag body
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			for si in (mi as MeshInstance3D).get_surface_override_material_count():
				var mat := (mi as MeshInstance3D).get_active_material(si)
				if mat is StandardMaterial3D:
					var m2: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					m2.albedo_color = Color(0.33, 0.38, 0.27)
					m2.metallic = 0.2
					(mi as MeshInstance3D).set_surface_override_material(si, m2)
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	body_entered.connect(_on_hit)

func _on_hit(_b) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - last_bounce > 0.12 and linear_velocity.length() > 1.5:
		last_bounce = t
		SFX.play3d("bounce", global_position, -4, randf_range(0.9, 1.1), 40.0, 4.0)

func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0:
		if is_smoke:
			# settle: the cloud starts where the can came to rest
			match_node.spawn_smoke(global_position, thrower)
		else:
			match_node.explode(global_position, thrower, visual_only)
		queue_free()
	elif is_smoke and linear_velocity.length() < 0.3 and fuse < 1.2:
		fuse = 0.0
