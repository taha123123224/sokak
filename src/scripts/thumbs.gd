extends Node
## Global weapon thumbnail renderer + cache (used by lobby and the in-match B menu).

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var cache := {}
var queue: Array = []
var busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# physics interpolation would render the camera/weapon at their previous transforms
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(512, 256)
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	cam = Camera3D.new()
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var l1 := DirectionalLight3D.new()
	l1.rotation_degrees = Vector3(-40, 50, 0)
	l1.light_energy = 2.2
	vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(-10, -130, 0)
	l2.light_energy = 1.2
	l2.light_color = Color(1, 0.7, 0.45)
	vp.add_child(l2)
	holder = Node3D.new()
	vp.add_child(holder)

func request(id: String, skin: String, rect: TextureRect) -> void:
	var key := id + ":" + skin
	if cache.has(key):
		rect.texture = cache[key]
		return
	queue.append([id, skin, rect])

func make_rect(id: String, skin: String, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	request(id, skin, r)
	return r

func _aabb(n: Node) -> AABB:
	var res := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		if first:
			res = a; first = false
		else:
			res = res.merge(a)
	return res

func _process(_d: float) -> void:
	if busy or queue.is_empty():
		return
	_job(queue.pop_front())

func _job(job: Array) -> void:
	busy = true
	var key: String = job[0] + ":" + job[1]
	if cache.has(key):
		if is_instance_valid(job[2]):
			job[2].texture = cache[key]
		busy = false
		return
	for c in holder.get_children():
		c.queue_free()
	var ps: PackedScene = GS.weapon_scene(job[0])
	var w := ps.instantiate()
	MatLib.apply(w, job[1])
	holder.add_child(w)
	await get_tree().process_frame
	var aabb := _aabb(w)
	var c := aabb.get_center()
	cam.position = c + Vector3(3, 0.6, 0.0)
	cam.look_at(c)
	cam.reset_physics_interpolation()
	cam.size = max(aabb.size.z * 0.62, aabb.size.y * 1.25) * 1.12
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if OS.has_environment("SAVE_THUMB"):
		img.save_png("/tmp/thumb_%s.png" % key.replace(":", "_"))
		print("THUMB ", key, " aabb ", aabb, " camsize ", cam.size)
	var tex := ImageTexture.create_from_image(img)
	cache[key] = tex
	if is_instance_valid(job[2]):
		job[2].texture = tex
	for j in queue:
		if j[0] + ":" + j[1] == key and is_instance_valid(j[2]):
			j[2].texture = tex
	busy = false
