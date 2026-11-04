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
	var testrun := args.has("shot") or args.has("econtest") or args.has("match") or args.has("simstat") or args.has("netsim") or args.has("nettest") or args.has("dumpcatalog")
	if not testrun or args.has("gfxtest"):
		# make sure 3D really draws on this PC (switches to DirectX 12 / OpenGL and restarts if not)
		if await preload("res://scripts/gfx.gd").startup(self):
			return
		if args.has("gfxtest"):
			get_tree().quit()
			return
	if args.has("econtest"):
		for a in [["match_start", {}], ["buy_weapon", {"id": "m4a1"}], ["buy_skin", {"wid": "ak47", "skin": "kar"}], ["open_crate", {"id": "sokak"}], ["upgrade", {"wid": "ak47"}], ["sync", {"active_set": 3}]]:
			var r: Dictionary = await GS.act(a[0], a[1])
			print("ECON ", a[0], " ", r)
		print("ECON gold=", GS.profile["gold"], " sets=", GS.profile["sets"].size(), " active=", GS.profile["active_set"], " file=", FileAccess.file_exists(GS.SAVE_PATH))
		get_tree().quit()
		return
	if args.has("dumpcatalog"):
		load("res://tools/dump_catalog.gd").run()
		get_tree().quit()
		return
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
	if true:
		GS.settings["dyn_res"] = false
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
		start_match({"map": parts[0], "mode": parts[1] if parts.size() > 1 else "ffa", "bots": int(args.get("bots", "6")), "diff": 1, "time": float(args.get("time", "8")), "target": 40, "team": "a", "no": 1, "name": "test"})
	elif args.get("page", "") == "login":
		go_login()
	else:
		go_menu(args.get("page", "lobby"))
	if args.has("simstat"):
		# headless bot-combat check: --simstat=SECONDS (game time, runs at time_scale 4)
		Engine.time_scale = 4.0
		Engine.physics_ticks_per_second = 30
		var secs := float(args["simstat"])
		if OS.has_environment("SIMMID"):
			await get_tree().create_timer(6.0).timeout
			if current and "player" in current and current.player:
				var bb = null
				for c in current.combatants:
					if not c["is_player"]: bb = c["node"]; break
				if bb: current.player.global_position = bb.global_position + Vector3(2, 0.3, 0)
		var waited := 0.0
		while waited < secs:
			await get_tree().create_timer(5.0).timeout
			waited += 5.0
			if current and "combatants" in current:
				var tk := 0
				for c in current.combatants:
					tk += int(c["kills"])
				print("SIM t=%d kills=%d" % [int(waited), tk] + ((" | SAB tur=%d faz=%s skor=%s kurulu=%s tasiyan=%s" % [current.sab.round_no, current.sab.phase, str(current.team_score), current.sab.planted, (str(current.sab.carrier.global_position.distance_to(current.sab.sites[current.sab.target_site]["pos"])) + " tv=" + str(current.sab.carrier.target_visible if "target_visible" in current.sab.carrier else "-") + " obj=" + str(current.sab.carrier.obj_goal if "obj_goal" in current.sab.carrier else "-") + " pos=" + str(current.sab.carrier.global_position) if current.sab.carrier else "yok")]) if "sab" in current and current.sab else ""))
				if OS.has_environment("SIMDBG"):
					for c in current.combatants:
						var nn = c["node"]
						var extra := ""
						if "nav" in nn and nn.nav:
							var mp: RID = nn.get_world_3d().navigation_map
							var cp := NavigationServer3D.map_get_closest_point(mp, nn.global_position)
							extra = " navpath=%d tgtpos=%s closest=%s roam=%s" % [nn.nav.get_current_navigation_path().size(), str(nn.nav.target_position.snapped(Vector3.ONE)), str(cp.snapped(Vector3.ONE * 0.1)), str(nn.roam_target.snapped(Vector3.ONE)) + " has_roam=%s pp=%s vel=%s ls=%.1f now=%.1f" % [nn.has_roam, nn.is_physics_processing(), str(nn.velocity.snapped(Vector3.ONE*0.1)), nn.last_seen_t, Time.get_ticks_msec()/1000.0]]
						print("  %s team=%s pos=%s alive=%s tgt=%s vis=%s%s" % [c["name"], c["team"], str(nn.global_position.snapped(Vector3.ONE)), nn.alive, ("target" in nn and nn.target != null), ("target_visible" in nn and nn.target_visible), extra])
				if OS.has_environment("SIMDBG"):
					for c in current.combatants:
						var nd = c["node"]
						var extra := (" shots=%d hits=%d hp=%s" % [nd.dbg_shots, nd.dbg_hits, str(nd.hp) if "hp" in nd else "?"]) if "dbg_shots" in nd else ""
						print("   %s team=%s alive=%s pos=%s tv=%s%s" % [c["name"], c["team"], nd.alive, (nd.global_position as Vector3).snapped(Vector3.ONE), nd.target_visible if "target_visible" in nd else "-", extra])
		if current and "combatants" in current:
			var parts := []
			for c in current.combatants:
				parts.append("%s:%s k%d d%d" % [c["name"], c["node"].wid if "wid" in c["node"] else "?", int(c["kills"]), int(c["deaths"])])
			print("SIMEND mode=%s %s" % [current.mode, ", ".join(parts)])
		get_tree().quit()
		return
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

var _perf_t := 0.0
var _perf_max := 0.0
func _process(_d: float) -> void:
	if OS.has_environment("PERF"):
		_perf_t += _d
		_perf_max = maxf(_perf_max, _d)
		var vr := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vr, true)
		var vmr := RID()
		if current and "player" in current and current.player and current.player.vm_vp:
			vmr = current.player.vm_vp.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vmr, true)
		if _perf_t > 2.0:
			_perf_t = 0.0
			print("PERFGPU main=%.1fms vm=%.1fms" % [RenderingServer.viewport_get_measured_render_time_gpu(vr), RenderingServer.viewport_get_measured_render_time_gpu(vmr) if vmr.is_valid() else 0.0])
			print("PERF fps=%d proc=%.2fms phys=%.2fms maxframe=%.1fms nodes=%d draws=%d objs=%d" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				_perf_max * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			_perf_max = 0.0
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
