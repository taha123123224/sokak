extends RigidBody3D

var match_node
var thrower
var fuse := 2.4
var last_bounce := 0.0

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
		match_node.explode(global_position, thrower)
		queue_free()
