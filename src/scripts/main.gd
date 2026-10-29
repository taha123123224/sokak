extends Node
## Root: switches between menu and match.

var current: Node = null
var theme: Theme
var fps_label: Label

func _ready() -> void:
	theme = UI.build_theme()
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	fps_label = UI.lbl("", 16, Color(0.6, 1, 0.6), "Rajdhani-Bold")
	fps_label.position = Vector2(8, 4)
	cl.add_child(fps_label)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("shot"):
		_test(args)
		return
	go_login()

func _test(args: Dictionary) -> void:
	GS.settings["fullscreen"] = false
	if args.has("lowfx"):
		GS.set_meta("lowfx", true)
		GS.settings["volumetric"] = false
		GS.settings["ssil"] = false
	if args.has("nofog"):
		GS.set_meta("nofog", true)
	if args.has("quality"):
		GS.apply_preset(args["quality"])
	GS.apply_settings()
	DisplayServer.window_set_size(Vector2i(int(args.get("w", "1600")), int(args.get("h", "900"))))
	if args.has("nettest"):
		# two-client online test: --nettest=CODE:id:name[:host]   (relay from env RELAY)
		var pp: PackedStringArray = args["nettest"].split(":")
		Online.relay_url = OS.get_environment("RELAY")
		Net.join(pp[0], pp[1], pp[2])
		await Net.connected_room
		if pp.size() > 3:
			await get_tree().create_timer(float(OS.get_environment("WAITB")) if OS.has_environment("WAITB") else 20.0).timeout
			var ids: Array = Net.members.keys()
			var tm := {}
			for i in ids.size(): tm[ids[i]] = "a" if i % 2 == 0 else "b"
			var c := {"map": args.get("map", "liman"), "mode": "tdm", "time": 8, "target": 40, "net": true, "teams_map": tm, "bots": 0, "diff": 1, "no": 0, "name": "test"}
			Net.send({"t": "start", "cfg": c})
			c["team"] = tm[Net.my_id]
			start_match(c)
		else:
			var d: Dictionary = {}
			while true:
				var mm = await Net.message
				if mm is Dictionary and mm.get("t", "") == "start":
					d = mm["cfg"]; break
			d["team"] = d["teams_map"][Net.my_id]
			start_match(d)
	elif args.has("match"):
		var parts: PackedStringArray = args["match"].split(":")
		start_match({"map": parts[0], "mode": parts[1] if parts.size() > 1 else "ffa", "bots": int(args.get("bots", "6")), "diff": 1, "time": 8, "target": 40, "team": "a", "no": 1, "name": "test"})
	elif args.get("page", "") == "login":
		go_login()
	else:
		go_menu(args.get("page", "lobby"))
	var shots: PackedStringArray = args["shot"].split(",")
	var after := float(args.get("after", "4"))
	for i in shots.size():
		await get_tree().create_timer(after).timeout
		var hooks: PackedStringArray = str(args.get("hooks", "")).split(",", false)
		var hi := int(hooks[i]) if i < hooks.size() else i
		if current and current.has_method("test_hook"):
			current.test_hook(hi)
		await get_tree().create_timer(float(args.get("settle", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(shots[i], 0.9)
		print("SHOT ", shots[i], " fps=", Engine.get_frames_per_second(), " tris=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if current and "player" in current and current.player:
			var pl = current.player
			var q := PhysicsRayQueryParameters3D.create(pl.global_position + Vector3.UP, pl.global_position + Vector3.DOWN * 50)
			var r: Dictionary = pl.get_world_3d().direct_space_state.intersect_ray(q)
			print("PLAYER pos ", pl.global_position, " ground ", r.get("position", "none"), " cam ", pl.cam.global_position)
	get_tree().quit()

func _process(_d: float) -> void:
	fps_label.visible = bool(GS.settings.get("show_fps", true))
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()

func _swap(n: Node) -> void:
	if current:
		current.queue_free()
		await get_tree().process_frame
	current = n
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(n)

func go_login() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var l := preload("res://scripts/login.gd").new()
	l.main = self
	_swap(l)

func go_menu(page: String = "lobby") -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var m := preload("res://scripts/menu.gd").new()
	m.start_page = page
	m.main = self
	_swap(m)

func start_match(cfg: Dictionary) -> void:
	GS.room = cfg
	var mt := preload("res://scripts/match.gd").new()
	mt.main = self
	_swap(mt)
