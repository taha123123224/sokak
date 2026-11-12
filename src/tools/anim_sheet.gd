extends SceneTree
# godot --path . -s tools/anim_sheet.gd -- res://model.glb anim angle_deg out.png
func _init():
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5,0.58,0.68)
	e.ambient_light_color = Color(0.8,0.8,0.85); e.ambient_light_energy = 1.0; env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); sun.light_energy = 1.4; root.add_child(sun)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); fl.mesh = pm; root.add_child(fl)
	var w: Node3D = load(a[0]).instantiate(); root.add_child(w)
	var ap: AnimationPlayer = w.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play(a[1]); ap.pause()
	var L := ap.current_animation_length
	var ang := deg_to_rad(float(a[2]))
	await process_frame
	var cam := Camera3D.new(); root.add_child(cam)
	cam.position = Vector3(sin(ang) * 3.4, 1.1, cos(ang) * 3.4); cam.look_at(Vector3(0, 0.9, 0)); cam.make_current()
	var img := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	for i in 8:
		ap.seek(L * i / 8.0, true)
		for k in 3: await process_frame
		var s := get_root().get_texture().get_image(); s.convert(Image.FORMAT_RGBA8)
		s = s.get_region(Rect2i(s.get_width() / 2 - s.get_height() / 2 * 9 / 16 - 60, 0, s.get_height() * 9 / 16 + 120, s.get_height()))
		s.resize(320, 360)
		img.blit_rect(s, Rect2i(0, 0, 320, 360), Vector2i((i % 4) * 320, (i / 4) * 360))
	img.save_png(a[3]); quit()
