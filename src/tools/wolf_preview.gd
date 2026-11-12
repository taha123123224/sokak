extends SceneTree
# usage: godot --path . -s tools/wolf_preview.gd -- out.png
func _init():
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45,0.55,0.7)
	e.ambient_light_color = Color(0.7,0.7,0.75); e.ambient_light_energy = 0.8; env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 35, 0); root.add_child(sun)
	var anims := ["run", "run", "run", "attack"]; var ts := [0.0, 0.25, 0.5, 0.5]; var angs := [90.0, 90.0, 90.0, 30.0]
	var vp_imgs := []
	for i in 4:
		var w: Node3D = load(OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "res://assets/models/wolf.glb").instantiate(); root.add_child(w); w.position.x = i * 8.0
		var ap: AnimationPlayer = w.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play(anims[i]); ap.seek(ap.current_animation_length * ts[i], true); ap.pause()
	await process_frame
	var cam := Camera3D.new(); root.add_child(cam)
	var img := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	for i in 4:
		var a := deg_to_rad(angs[i]); var c := Vector3(i * 8.0, 0.9, 0)
		cam.position = c + Vector3(sin(a) * 3.2, 0.4, cos(a) * 3.2); cam.look_at(c); cam.make_current()
		for k in 3: await process_frame
		var s := get_root().get_texture().get_image(); s.convert(Image.FORMAT_RGBA8); s.resize(640, 360)
		img.blit_rect(s, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	img.save_png(OS.get_cmdline_user_args()[0]); quit()
