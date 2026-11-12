extends SceneTree
# godot --path . -s tools/wsheet.gd -- out.png id1 id2 ...  : side views of w_<id>.glb with marker dots
func _init():
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.62,0.66,0.72)
	e.ambient_light_color = Color(0.9,0.9,0.92); e.ambient_light_energy = 0.9; env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 60, 0); sun.light_energy = 1.3; root.add_child(sun)
	await process_frame
	var ids := a.slice(1)
	var cols := 2
	var cw := 640; var ch := 360
	var rows := int(ceil(ids.size() / float(cols)))
	var img := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	var cam := Camera3D.new(); root.add_child(cam); cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	for i in ids.size():
		var w: Node3D = load("res://assets/models/w_%s.glb" % ids[i]).instantiate(); root.add_child(w)
		var aabb := AABB(); var first := true
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = mi.global_transform * mi.get_aabb()
			aabb = bb if first else aabb.merge(bb); first = false
		var marks := []
		for nm in ["muzzle", "sight", "lhand", "rhand", "eject"]:
			var n := w.find_child(nm, true, false) as Node3D
			if n:
				var s := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = aabb.size.length() * 0.012; sm.height = sm.radius * 2; s.mesh = sm
				var mt := StandardMaterial3D.new(); mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mt.albedo_color = {"muzzle": Color.RED, "sight": Color.CYAN, "lhand": Color.GREEN, "rhand": Color.YELLOW, "eject": Color.MAGENTA}[nm]
				mt.no_depth_test = true
				s.material_override = mt; root.add_child(s); s.global_position = n.global_position + Vector3(0.3, 0, 0); marks.append(s)
		var c := aabb.get_center()
		cam.size = maxf(aabb.size.z * 1.1, aabb.size.y * 2.3)
		cam.position = c + Vector3(3, 0, 0); cam.look_at(c); cam.make_current()
		for k in 3: await process_frame
		var s2 := get_root().get_texture().get_image(); s2.convert(Image.FORMAT_RGBA8)
		var sw := s2.get_width(); var sh := s2.get_height()
		s2 = s2.get_region(Rect2i(sw / 2 - sh * cw / ch / 2, 0, sh * cw / ch, sh)); s2.resize(cw, ch)
		img.blit_rect(s2, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
		w.queue_free()
		for m in marks: m.queue_free()
		print(ids[i], " aabb ", aabb.size)
	img.save_png(a[0]); quit()
