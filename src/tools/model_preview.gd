extends SceneTree
# usage: godot --path . -s tools/model_preview.gd -- res://model.glb out.png
func _init():
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45,0.55,0.7)
	e.ambient_light_color = Color(0.7,0.7,0.75); e.ambient_light_energy = 0.8; env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 35, 0); root.add_child(sun)
	var w: Node3D = load(a[0]).instantiate(); root.add_child(w)
	await process_frame
	var aabb := AABB(); var first := true
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = mi.global_transform * mi.get_aabb()
		aabb = bb if first else aabb.merge(bb); first = false
	print("AABB ", aabb)
	var c := aabb.get_center(); var r := aabb.size.length() * 0.9
	var cam := Camera3D.new(); root.add_child(cam)
	var img := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	var angs := [0.0, 90.0, 180.0, 270.0]
	for i in 4:
		var an := deg_to_rad(angs[i])
		cam.position = c + Vector3(sin(an) * r, r * 0.35, cos(an) * r); cam.look_at(c); cam.make_current()
		for k in 3: await process_frame
		var s := get_root().get_texture().get_image(); s.convert(Image.FORMAT_RGBA8); s.resize(640, 360)
		img.blit_rect(s, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	img.save_png(a[1]); quit()
