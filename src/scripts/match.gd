extends Node3D
## Match controller: map, environment, combatants, combat resolution, modes, scoring.

var main
var cfg := {}
var mode := "ffa"
var teams := false
var map_id := "mahalle"
var map_data := {}
var fx
var hud
var player
var combatants: Array = []
var net = null   # net_match.gd when playing online
var spawn_points: Array = []
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky: Sky
var navreg: NavigationRegion3D
var statics: Node3D
var soldier_scene: PackedScene
var time_left := 600.0
var target_score := 50
var countdown := 0.0
var paused := false
var ended := false
var surface := "concrete"
var team_score := {"a": 0, "b": 0}
var loading: Control
var minimap_img: Image
var bounds := [-50, -50, 50, 50]
var player_streak := 0
var last_kill_t := -10.0
var multi := 0
var match_time := 0.0

func _ready() -> void:
	# only physics bodies (player, bots, grenades) are interpolated; scenery, FX and tweens are not
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cfg = GS.room
	mode = cfg.get("mode", "ffa")
	teams = GS.MODES[mode]["teams"]
	map_id = cfg.get("map", "mahalle")
	time_left = float(cfg.get("time", 8)) * 60.0
	target_score = int(cfg.get("target", 40))
	SFX.stop_music()
	SFX.world = self
	_show_loading()
	call_deferred("_build")

func _show_loading() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.02, 0.025, 0.035)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(loading)
	var v := UI.vbox(14)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-400, -120)
	v.custom_minimum_size = Vector2(800, 240)
	loading.add_child(v)
	v.add_child(UI.lbl(GS.MAPS[map_id]["name"].to_upper(), 64, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.lbl(GS.MODES[mode]["name"] + "  •  " + GS.MAPS[map_id]["desc"], 22, UI.DIM, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER))
	var pb := UI.bar(0, 100, UI.ACCENT, 6, 800)
	pb.name = "pb"
	v.add_child(pb)
	var tip := UI.lbl("İPUCU: " + ["Eğilerek ateş etmek isabeti artırır.", "Nişancı tüfeklerinde nefesini tut: hareket etme!", "Tab tuşu ile skor tablosunu aç.", "F tuşu ile silahını incele.", "Kafadan vuruşlar 2.5 kat hasar verir.", "Shift ile yürürsen adım sesin duyulmaz."][randi() % 6], 20, UI.ACCENT2, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(tip)
	var st := UI.lbl("Harita yükleniyor...", 18, UI.DIM, "Rajdhani-Medium", HORIZONTAL_ALIGNMENT_CENTER)
	st.name = "st"
	v.add_child(st)

func _progress(p: float, t: String) -> void:
	var pb := loading.find_child("pb", true, false) as ProgressBar
	if pb: pb.value = p
	var st := loading.find_child("st", true, false) as Label
	if st: st.text = t
	await get_tree().process_frame
	await get_tree().process_frame

func _build() -> void:
	fx = preload("res://scripts/fx.gd").new()
	add_child(fx)
	await _progress(10, "Harita modeli yükleniyor...")
	var f := FileAccess.open(GS.map_paths(map_id)["json"], FileAccess.READ)
	map_data = JSON.parse_string(f.get_as_text())
	bounds = map_data["bounds"]
	if not map_data.has("env"):
		map_data["env"] = {"preset": "day"}
	var ps: PackedScene = GS.map_scene(map_id)
	var vis := ps.instantiate()
	add_child(vis)
	await _progress(30, "Malzemeler ve dokular hazırlanıyor...")
	MatLib.apply(vis)
	var dd := float(GS.settings["draw_distance"])
	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		var nm := String(m3.name)
		if nm.begins_with("det"):
			# small props: no shadow casting, fade out at medium range
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m3.visibility_range_end = 70.0 * dd
			m3.visibility_range_end_margin = 8.0
		elif nm.begins_with("far"):
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m3.visibility_range_end = 900.0 * dd
		else:
			m3.visibility_range_end = 320.0 * dd
			m3.visibility_range_end_margin = 20.0
	await _progress(45, "Çarpışma ve fizik kuruluyor...")
	navreg = NavigationRegion3D.new()
	add_child(navreg)
	statics = Node3D.new()
	navreg.add_child(statics)
	for c in map_data["colliders"]:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(c["s"][0], c["s"][1], c["s"][2])
		cs.shape = bs
		sb.add_child(cs)
		statics.add_child(sb)
		sb.position = Vector3(c["c"][0], c["c"][1], c["c"][2])
		sb.rotation = Vector3(c["r"][0], c["r"][1], c["r"][2])
	# floor safety
	var fl := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(600, 1, 600)
	fcs.shape = fbs
	fl.add_child(fcs)
	fl.position = Vector3(0, -0.5 - (0.0 if map_id != "gemi" else 30.0), 0)
	statics.add_child(fl)
	for s in map_data["spawns"]:
		spawn_points.append({"pos": Vector3(s["p"][0], s["p"][1], s["p"][2]), "yaw": float(s["yaw"]), "team": s["team"] if s["team"] != null else ""})
	_build_minimap()
	await _progress(55, "Atmosfer ve ışıklandırma...")
	_setup_env(map_data["env"])
	await _progress(65, "Yol ağı (navigasyon) hesaplanıyor...")
	await _bake_nav()
	_add_occluders()
	await _render_minimap()
	await _progress(85, "Oyuncular hazırlanıyor...")
	var char_scenes := {}
	for cid in GS.CHARACTERS.keys():
		var cps := GS.char_scene(cid)
		if cps:
			char_scenes[cid] = cps
	soldier_scene = char_scenes.get("asker1", load("res://assets/models/soldier.glb"))
	surface = "metal" if map_id == "gemi" else "concrete"
	hud = preload("res://scripts/hud.gd").new()
	hud.match_node = self
	add_child(hud)
	player = preload("res://scripts/player.gd").new()
	player.match_node = self
	player.display_name = str(GS.profile["name"])
	add_child(player)
	player.died.connect(func(k, w, h):
		if net: net.send_death(k, w, h)
		on_death(player, k, w, h))
	var pteam := ""
	if teams:
		pteam = cfg.get("team", "a")
	player.team = pteam
	combatants.append({"node": player, "name": player.display_name, "team": pteam, "kills": 0, "deaths": 0, "score": 0, "head": 0, "is_player": true, "gg": 0, "lvl": int(GS.profile["level"])})
	hud.setup(player)
	player.attach_vm_rect(hud.vm_holder)
	player.set_vm_env(sky, sun.global_transform.basis, sun.light_color, sun.light_energy, world_env.environment.ambient_light_energy)
	var nb := int(cfg.get("bots", 9))
	if cfg.get("net", false) and Net.active():
		nb = 0
		net = preload("res://scripts/net_match.gd").new()
		add_child(net)
		net.setup(self)
	var names := GS.BOT_NAMES.duplicate()
	names.shuffle()
	for i in nb:
		var b := preload("res://scripts/bot.gd").new()
		b.match_node = self
		add_child(b)
		var bt := ""
		if teams:
			var on_a := 0
			for c in combatants:
				if c["team"] == "a": on_a += 1
			bt = "a" if on_a <= (combatants.size()) / 2 else "b"
			if i == nb - 1 and on_a * 2 > combatants.size():
				bt = "b"
		var bn: String = names[i % names.size()]
		var pool: Array = GS.team_chars("a") if bt == "a" else (GS.team_chars("b") if bt == "b" else GS.CHARACTERS.keys())
		var cs: PackedScene = char_scenes.get(pool[randi() % pool.size()], soldier_scene)
		b.setup(cs, bn, bt, int(cfg.get("diff", 1)), _bot_weapon(0))
		combatants.append({"node": b, "name": bn, "team": bt, "kills": 0, "deaths": 0, "score": 0, "head": 0, "is_player": false, "gg": 0, "lvl": randi_range(5, 80)})
	for c in combatants:
		_spawn(c, true)
	await _progress(92, "Efektler ve gölgelendiriciler hazırlanıyor...")
	await _prewarm()
	await _progress(100, "Hazır!")
	SFX.play_music("music_match", -16)
	SFX.play_amb(GS.MAPS.get(map_id, {}).get("amb", {"mahalle": "amb_city", "safranbolu": "amb_town", "gemi": "amb_ship", "liman": "amb_port"}.get(map_id, "amb_town")))
	var tw := create_tween()
	tw.tween_property(loading, "modulate:a", 0.0, 0.5)
	tw.tween_callback(loading.get_parent().queue_free)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	countdown = 3.0
	hud.show_countdown()

func _prewarm() -> void:
	## draw every effect once behind the loading screen so shaders/pipelines are compiled now,
	## not in the middle of a fight (prevents first-shot / first-kill stutters)
	var cam: Camera3D = player.cam
	var p: Vector3 = cam.global_position - cam.global_transform.basis.z * 3.0
	var n: Vector3 = cam.global_transform.basis.z
	SFX.silent = true
	fx.impact(p, n, "concrete")
	fx.impact(p, n, "metal")
	fx.blood(p, n)
	fx.death_burst(p, n, true)
	fx.blood_decal(p, n, 0.5)
	fx.tracer(p - Vector3(1, 0, 0), p + Vector3(1, 0, 0))
	fx.muzzle_light(p, 1.0)
	fx.explosion(p + n * -8.0)
	# every weapon model + skin material once
	var tmp := Node3D.new()
	add_child(tmp)
	tmp.global_position = p
	for wid in GS.WEAPONS.keys():
		var ps := GS.weapon_scene(wid)
		if ps:
			var w := ps.instantiate()
			MatLib.apply(w, GS.wskin(wid))
			tmp.add_child(w)
	for i in 3:
		await RenderingServer.frame_post_draw
	tmp.queue_free()
	SFX.silent = false
	# pre-load all sound streams into memory
	for snd in ["shot_scar", "shot_ump", "shot_revolver", "shot_kar", "shotfar_ak", "equip_pistol", "equip_heavy", "shot_ak", "shot_m4", "shot_smg", "shot_p90", "shot_shotgun", "shot_sniper", "shot_pistol", "shot_deagle", "shot_far", "shot_far_heavy",
			"headshot", "kill", "multikill", "gore0", "gore1", "bodyfall", "explosion", "mag_out", "mag_in", "bolt_back", "bolt_fwd", "pump", "shell_in", "hitmarker", "whiz"]:
		SFX.get_stream(snd)

func _add_occluders() -> void:
	## box occluders for every big solid block (buildings, containers, hulls) -> hidden geometry is not drawn
	var occ_root := Node3D.new()
	occ_root.name = "Occluders"
	add_child(occ_root)
	for c in map_data["colliders"]:
		var sz := Vector3(c["s"][0], c["s"][1], c["s"][2])
		var r: Array = c["r"]
		if abs(float(r[0])) > 0.01 or abs(float(r[2])) > 0.01:
			continue
		if sz.y < 2.6 or min(sz.x, sz.z) < 2.0:
			continue
		var ctr := Vector3(c["c"][0], c["c"][1], c["c"][2])
		# skip the invisible boundary walls (they are not drawn, so they must not hide the skyline)
		if ctr.x <= bounds[0] + 1.5 or ctr.x >= bounds[2] - 1.5 or -ctr.z <= bounds[1] + 1.5 or -ctr.z >= bounds[3] - 1.5:
			if min(sz.x, sz.z) < 1.5:
				continue
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = sz * Vector3(0.92, 0.95, 0.92)
		oi.occluder = bo
		occ_root.add_child(oi)
		oi.global_transform = Transform3D(Basis(Vector3.UP, float(r[1])), ctr)

func _bot_weapon(gg: int) -> String:
	match mode:
		"knife":
			return "knife" if randf() < 0.6 else "karambit"
		"sniper":
			return "awp" if randf() < 0.5 else "kar98"
		"gungame":
			return GS.GUNGAME_ORDER[min(gg, GS.GUNGAME_ORDER.size() - 1)]
	var pool := ["ak47", "ak47", "m4a1", "m4a1", "scar", "aug", "vector", "m249", "mp5", "p90", "ump45", "spas", "awp", "kar98", "deagle", "revolver"]
	return pool[randi() % pool.size()]

var env_exp := 1.0

func _setup_env(env_cfg: Dictionary) -> void:
	var preset: String = env_cfg.get("preset", "day")
	var s := GS.settings
	world_env = WorldEnvironment.new()
	var e := Environment.new()
	sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sun = DirectionalLight3D.new()
	# bright, colourful, high sun for every map (narrow streets need a steep sun)
	var P := {
		"day":      {"elev": -58.0, "az": 35.0, "sun": Color(1.0, 0.96, 0.88), "se": 2.8, "top": Color("4579bd"), "hor": Color("a8d0f5"), "amb": Color(0.74, 0.74, 0.76), "ae": 1.1, "fog": Color("b6d3f0"), "exp": 1.0, "sat": 1.02, "fill": Color(0.85, 0.85, 0.88)},
		"golden":   {"elev": -38.0, "az": 220.0, "sun": Color(1.0, 0.84, 0.62), "se": 2.6, "top": Color("3a7cd0"), "hor": Color("f2c79a"), "amb": Color(0.72, 0.66, 0.62), "ae": 1.05, "fog": Color("f0cfa8"), "exp": 0.98, "sat": 1.05, "fill": Color(0.85, 0.8, 0.82)},
		"sunset":   {"elev": -24.0, "az": 280.0, "sun": Color(1.0, 0.72, 0.48), "se": 2.3, "top": Color("2f5fae"), "hor": Color("ffb27a"), "amb": Color(0.7, 0.6, 0.62), "ae": 1.0, "fog": Color("f5b48a"), "exp": 0.95, "sat": 1.05, "fill": Color(0.8, 0.72, 0.8)},
		"overcast": {"elev": -55.0, "az": 120.0, "sun": Color(1.0, 0.97, 0.92), "se": 2.4, "top": Color("4a7fbf"), "hor": Color("c4dcf0"), "amb": Color(0.75, 0.75, 0.77), "ae": 1.2, "fog": Color("c8dcee"), "exp": 1.0, "sat": 1.02, "fill": Color(0.85, 0.86, 0.9)},
	}
	var c: Dictionary = P.get(preset, P["day"])
	sun.rotation_degrees = Vector3(c["elev"], c["az"], 0)
	sun.light_color = c["sun"]
	sun.light_energy = c["se"]
	sun.shadow_enabled = int(s["shadows"]) > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(s["shadows"]) >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [40.0, 70.0, 110.0, 150.0, 220.0][clamp(int(s["shadows"]), 0, 4)]
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.shadow_opacity = 0.82
	sun.light_angular_distance = 0.5
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = c["top"]
	sm.sky_horizon_color = c["hor"]
	sm.ground_horizon_color = c["hor"]
	sm.ground_bottom_color = Color(0.35, 0.33, 0.3)
	sm.sky_curve = 0.12
	# small, crisp sun disc (a 25° halo washed out the whole sky at sunset)
	sm.sun_angle_max = 7
	sm.sun_curve = 0.18
	sm.sky_energy_multiplier = 1.1
	sm.ground_energy_multiplier = 0.6
	sm.sky_cover = load("res://assets/tex/clouds.png") if ResourceLoader.exists("res://assets/tex/clouds.png") else null
	sm.sky_cover_modulate = Color(1, 1, 1, 0.9)
	sky.sky_material = sm
	# soft fill light from the opposite side (lifts shadows, no extra shadow pass)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, float(c["az"]) + 180.0, 0)
	fill.light_color = c["fill"]
	fill.light_energy = 0.55
	fill.light_specular = 0.15
	fill.shadow_enabled = false
	add_child(fill)
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = c["amb"]
	e.ambient_light_sky_contribution = 0.35
	e.ambient_light_energy = c["ae"]
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_exp = float(c["exp"])
	e.tonemap_exposure = env_exp * float(s.get("brightness", 1.0))
	e.tonemap_white = 6.0
	e.fog_enabled = not GS.has_meta("nofog")
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = c["fog"]
	e.fog_light_energy = 1.0
	e.fog_density = 0.55
	e.fog_depth_begin = 70.0
	e.fog_depth_end = 520.0 * float(s["draw_distance"])
	e.fog_depth_curve = 2.0
	e.fog_sun_scatter = 0.06
	e.fog_sky_affect = 0.0
	e.ssao_enabled = bool(s["ssao"])
	e.ssao_radius = 1.0; e.ssao_intensity = 1.1; e.ssao_power = 1.3; e.ssao_detail = 0.5; e.ssao_light_affect = 0.0
	e.ssil_enabled = bool(s["ssil"])
	e.ssil_radius = 4.0; e.ssil_intensity = 1.0
	e.ssr_enabled = bool(s["ssr"])
	e.ssr_max_steps = 56; e.ssr_fade_in = 0.15; e.ssr_fade_out = 2.0; e.ssr_depth_tolerance = 0.3
	e.sdfgi_enabled = bool(s["sdfgi"])
	if e.sdfgi_enabled:
		e.sdfgi_use_occlusion = true
		e.sdfgi_cascades = 4
		e.sdfgi_energy = 1.0
		e.sdfgi_bounce_feedback = 0.6
	e.glow_enabled = bool(s["glow"])
	e.glow_intensity = 0.45; e.glow_strength = 0.95; e.glow_bloom = 0.0; e.glow_hdr_threshold = 1.45
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.volumetric_fog_enabled = bool(s["volumetric"])
	e.volumetric_fog_density = 0.0018
	e.volumetric_fog_albedo = Color(1, 0.97, 0.92)
	e.volumetric_fog_length = 80.0
	e.volumetric_fog_anisotropy = 0.35
	e.volumetric_fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.04
	e.adjustment_saturation = c["sat"]
	world_env.environment = e
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	world_env.camera_attributes = ca
	add_child(world_env)
	add_child(sun)

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.3
	nm.cell_height = 0.2
	nm.agent_radius = 0.45
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.45
	nm.agent_max_slope = 46
	nm.region_min_size = 4
	nm.filter_baking_aabb = AABB(Vector3(bounds[0] - 2, -2, -bounds[3] - 2), Vector3(bounds[2] - bounds[0] + 4, 30, bounds[3] - bounds[1] + 4))
	var map_rid := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map_rid, 0.3)
	NavigationServer3D.map_set_cell_height(map_rid, 0.2)
	navreg.navigation_mesh = nm
	navreg.bake_navigation_mesh(true)
	await navreg.bake_finished

func _build_minimap() -> void:
	var w: float = bounds[2] - bounds[0]
	var h: float = bounds[3] - bounds[1]
	var sz := 512
	var sc: float = sz / max(w, h)
	minimap_img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	minimap_img.fill(Color(0.12, 0.14, 0.17, 0.85))
	for c in map_data["colliders"]:
		var hgt: float = c["s"][1]
		if hgt < 0.8 or hgt > 40:
			continue
		var cx: float = c["c"][0]; var cz: float = c["c"][2]
		var sx: float = c["s"][0]; var sz2: float = c["s"][2]
		var ry: float = c["r"][1]
		if abs(sin(ry)) > 0.7:
			var t := sx; sx = sz2; sz2 = t
		var x0 := int((cx - sx / 2 - bounds[0]) * sc)
		var y0 := int((cz - sz2 / 2 + bounds[3]) * sc)
		var col := Color(0.42, 0.46, 0.52, 1) if hgt > 2.0 else Color(0.3, 0.33, 0.38, 1)
		minimap_img.fill_rect(Rect2i(x0, y0, max(int(sx * sc), 1), max(int(sz2 * sc), 1)), col)

func _render_minimap() -> void:
	## real top-down photo of the map (orthographic), stylised for the HUD radar
	if DisplayServer.get_name() == "headless":
		return
	var w: float = bounds[2] - bounds[0]
	var h: float = bounds[3] - bounds[1]
	var S: float = max(w, h)
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var ctr := Vector3(bounds[0] + S / 2.0, 160.0, -bounds[3] + S / 2.0)
	var c := Camera3D.new()
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = S
	c.near = 1.0
	c.far = 400.0
	c.cull_mask = 1
	c.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), ctr)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	c.environment = env
	vp.add_child(c)
	c.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	# stylise: slightly desaturated, darker, cool tint; overlay walls from the collision data
	for y in 512:
		for x in 512:
			var col := img.get_pixel(x, y)
			var l := col.get_luminance()
			col = col.lerp(Color(l, l, l), 0.35).darkened(0.25)
			col = col.lerp(Color(0.1, 0.16, 0.22), 0.15)
			col.a = 0.95
			img.set_pixel(x, y, col)
	minimap_img = img
	if OS.has_environment("SAVE_MM"):
		img.save_png("/tmp/mm_%s.png" % map_id)

func world_to_minimap(p: Vector3) -> Vector2:
	var w: float = bounds[2] - bounds[0]
	var h: float = bounds[3] - bounds[1]
	var sc: float = 512.0 / max(w, h)
	return Vector2((p.x - bounds[0]) * sc, (p.z + bounds[3]) * sc)

# ---------------------------------------------------------------- loop
var test_follow: Array = []

func _process(delta: float) -> void:
	if world_env and world_env.environment:  # live brightness slider
		world_env.environment.tonemap_exposure = env_exp * float(GS.settings.get("brightness", 1.0))
	if test_follow.size() == 2 and is_instance_valid(test_follow[1]):
		var b: Node3D = test_follow[1]
		var cam3: Camera3D = test_follow[0]
		var side := b.global_transform.basis.x
		cam3.global_position = b.global_position + side * 4.5 + Vector3.UP * 1.4
		cam3.look_at(b.global_position + Vector3.UP * 1.0)
	if loading and is_instance_valid(loading) and loading.modulate.a > 0.99:
		return
	if ended:
		return
	if countdown > 0:
		var prev := countdown
		countdown -= delta
		if int(ceil(prev)) != int(ceil(countdown)) and countdown > 0:
			SFX.play("beep", -2)
		if countdown <= 0:
			SFX.play("beep_go", -2)
			if hud and bool(GS.settings.get("announcer", true)): hud._announce("ann_start")
			hud.center_msg("ÇATIŞMA BAŞLADI!", UI.ACCENT)
		return
	if not paused:
		time_left -= delta
		match_time += delta
		if time_left <= 0:
			time_left = 0
			end_match()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and not ended and player != null:
		if hud and hud.buy_open:
			hud.toggle_buy(false)
			return
		set_paused(not paused)
	if e is InputEventMouseButton and e.pressed and not paused and not ended and not (hud and hud.buy_open) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and (loading == null or not is_instance_valid(loading)):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_paused(p: bool) -> void:
	paused = p
	hud.show_pause(p)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED

# ---------------------------------------------------------------- combat
func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func hitscan(shooter, origin: Vector3, dir: Vector3, wid: String, dmg: float, rng: float, head_mult: float, wd: Dictionary = {}, depth: int = 0) -> Dictionary:
	var to := origin + dir * rng
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | 2)
	q.exclude = [shooter.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	# near-miss whiz for the player
	if shooter != player and player.alive:
		var pp: Vector3 = player.eye_pos()
		var t := (pp - origin).dot(dir)
		if t > 2 and (r.is_empty() or t < origin.distance_to(r["position"])):
			var closest := origin + dir * t
			if closest.distance_to(pp) < 1.4:
				SFX.play("whiz", -8, randf_range(0.9, 1.15))
	if r.is_empty():
		return {"pos": to, "hit_char": false}
	var col = r["collider"]
	var pos: Vector3 = r["position"]
	if col.has_method("take_damage"):
		if not col.alive:
			return {"pos": pos, "hit_char": false}
		if teams and col.team == shooter.team:
			return {"pos": pos, "hit_char": false}
		var rel: float = pos.y - col.global_position.y
		var head: bool = rel > (1.48 if not col.crouching else 0.95)
		var d := origin.distance_to(pos)
		var bl: Dictionary = GS.ball(wid)
		# per-weapon damage falloff: full damage up to f0, linear down to fmin at f1
		var fall: float = 1.0 - clamp((d - float(bl["f0"])) / max(float(bl["f1"]) - float(bl["f0"]), 1.0), 0.0, 1.0) * (1.0 - float(bl["fmin"]))
		var amount := dmg * fall * (head_mult if head else (float(bl.get("limb", 0.8)) if rel < 0.8 else 1.0))
		fx.blood(pos, -dir)
		if randf() < 0.3:
			var q2 := PhysicsRayQueryParameters3D.create(pos, pos + dir * 3.0, 1)
			var r2 := get_world_3d().direct_space_state.intersect_ray(q2)
			if not r2.is_empty():
				fx.blood_decal(r2["position"], r2["normal"], randf_range(0.5, 0.9))
		SFX.play3d("imp_flesh%d" % (randi() % 3), pos, -4, 1.0, 40.0, 4.0)
		var was_alive: bool = col.alive
		col.take_damage(amount, shooter, origin, head, wid)
		if shooter == player:
			hud.hitmarker(head, was_alive and not col.alive, amount, pos)
			if head:
				SFX.play("headshot", -8)
			else:
				SFX.play("hitmarker", -6)
		return {"pos": pos, "hit_char": true}
	fx.impact(pos, r["normal"], surface)
	var sname := "imp_metal" if surface == "metal" else "imp_concrete"
	SFX.play3d("%s%d" % [sname, randi() % 3], pos, -6, randf_range(0.9, 1.1), 50.0, 4.0)
	# wall penetration: look for the exit face within the weapon's penetration depth
	var pen: float = float(GS.ball(wid).get("pen", 0.0))
	if pen > 0.0 and depth == 0:
		var far := pos + dir * pen
		var rb := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(far, pos, 1))
		if not rb.is_empty():
			var exit_p: Vector3 = rb["position"]
			fx.impact(exit_p, rb["normal"], surface)
			var keep: float = clamp(1.0 - pos.distance_to(exit_p) / pen, 0.25, 0.8)
			var r3 := hitscan(shooter, exit_p + dir * 0.02, dir, wid, dmg * keep, max(rng - origin.distance_to(exit_p), 1.0), head_mult, wd, 1)
			r3["pos"] = pos
			return r3
	return {"pos": pos, "hit_char": false}

func melee(attacker, origin: Vector3, dir: Vector3, dmg: float, wid: String) -> void:
	var best = null
	var best_d := 2.4
	for c in combatants:
		var n = c["node"]
		if n == attacker or not n.alive:
			continue
		if teams and n.team == attacker.team:
			continue
		var to: Vector3 = n.chest_pos() - origin
		var d := to.length()
		if d < best_d and dir.dot(to.normalized()) > 0.55 and los(origin, n.chest_pos(), [attacker.get_rid(), n.get_rid()]):
			best = n
			best_d = d
	if best:
		# backstab: target facing away
		var tf: Vector3 = -best.global_transform.basis.z
		var back: bool = tf.dot(dir) > 0.5
		var amount := dmg * (2.5 if back else 1.0)
		var was_alive: bool = best.alive
		best.take_damage(amount, attacker, origin, false, wid)
		fx.blood(best.chest_pos(), -dir)
		SFX.play3d("knife_hit", best.chest_pos(), 0)
		if attacker == player:
			hud.hitmarker(back, was_alive and not best.alive, amount, best.chest_pos())
	else:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 2.0, 1)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			SFX.play3d("knife_wall", r["position"], -4)
			fx.impact(r["position"], r["normal"], surface)

func throw_grenade(thrower, pos: Vector3, vel: Vector3) -> void:
	var g := preload("res://scripts/grenade.gd").new()
	g.match_node = self
	g.thrower = thrower
	add_child(g)
	g.global_position = pos
	g.linear_velocity = vel

func explode(pos: Vector3, thrower) -> void:
	fx.explosion(pos)
	SFX.play3d("explosion", pos, 6, 1.0, 200.0, 20.0)
	var pd: float = player.global_position.distance_to(pos)
	player.shake = max(player.shake, clamp(1.6 - pd / 15.0, 0.0, 1.6))
	for c in combatants:
		var n = c["node"]
		if not n.alive:
			continue
		var d: float = n.chest_pos().distance_to(pos)
		if d > 8.0:
			continue
		if teams and n.team == thrower.team and n != thrower:
			continue
		if not los(pos + Vector3.UP * 0.3, n.chest_pos(), [n.get_rid()]):
			continue
		var dmg: float = 130.0 * pow(1.0 - d / 8.0, 1.4)
		if n == thrower:
			dmg *= 0.6
		var was_alive: bool = n.alive
		n.take_damage(dmg, thrower, pos, false, "frag")
		if thrower == player and n != player:
			hud.hitmarker(false, was_alive and not n.alive, dmg, n.chest_pos())
	for b in combatants:
		if not b["is_player"] and b["node"].alive:
			b["node"].hear(pos)

func on_shot_fired(shooter, pos: Vector3) -> void:
	for c in combatants:
		var n = c["node"]
		if n != shooter and not c["is_player"] and n.alive and (not teams or n.team != shooter.team):
			n.hear(pos)
	if shooter != player and hud:
		hud.ping_minimap(shooter)

func entry(n) -> Dictionary:
	for c in combatants:
		if c["node"] == n:
			return c
	return {}

func gg_level(n) -> int:
	return int(entry(n).get("gg", 0))

func on_death(victim, attacker, wid: String, head: bool) -> void:
	if ended:
		return
	var ve := entry(victim)
	ve["deaths"] += 1
	var ae := {}
	if attacker != null and is_instance_valid(attacker) and attacker != victim:
		ae = entry(attacker)
		ae["kills"] += 1
		ae["score"] += 100 + (50 if head else 0)
		if head: ae["head"] += 1
		if teams:
			team_score[ae["team"]] += 1
	elif teams:
		pass
	hud.kill_feed(ae.get("name", ve["name"]), ve["name"], wid, head, ae.get("team", ""), ve["team"], attacker == player, victim == player)
	if attacker == player and victim != player:
		_player_kill(head, wid)
	if victim == player:
		player_streak = 0
		hud.show_death(ae.get("name", "Kendini"), wid, head)
		if attacker != null and is_instance_valid(attacker) and attacker != player:
			_killcam(attacker)
		GS.profile["stats"]["deaths"] = int(GS.profile["stats"]["deaths"]) + 1
	# gun game progression
	if mode == "gungame" and not ae.is_empty():
		var a = attacker
		var prev_lvl: int = ae["gg"]
		if wid == "knife" or wid == "karambit" or GS.WEAPONS.get(wid, {}).get("melee", false) and prev_lvl < GS.GUNGAME_ORDER.size() - 1:
			# knife kill: steal a level
			ve["gg"] = max(int(ve["gg"]) - 1, 0)
		ae["gg"] = prev_lvl + 1
		if ae["gg"] >= GS.GUNGAME_ORDER.size():
			end_match()
			return
		var nw: String = GS.GUNGAME_ORDER[ae["gg"]]
		if a == player:
			player.setup_loadout({}, "gungame")
			hud.center_msg("YENİ SİLAH: " + GS.WEAPONS[nw]["name"], UI.ACCENT2)
		elif a.alive:
			a.set_weapon(nw)
	# respawn timer
	get_tree().create_timer(3.5 if victim == player else 3.0).timeout.connect(func(): if not ended: _spawn(ve, false))
	_check_win()

func _player_kill(head: bool, wid: String) -> void:
	GS.profile["stats"]["kills"] = int(GS.profile["stats"]["kills"]) + 1
	GS.profile["missions"]["kills"] = int(GS.profile["missions"]["kills"]) + 1
	if head:
		GS.profile["stats"]["headshots"] = int(GS.profile["stats"]["headshots"]) + 1
		GS.profile["missions"]["head"] = int(GS.profile["missions"]["head"]) + 1
	player_streak += 1
	var now := match_time
	if now - last_kill_t < 4.0:
		multi += 1
	else:
		multi = 1
	last_kill_t = now
	SFX.play("kill", -4)
	var txt := ""
	match multi:
		2: txt = "ÇİFTE ÖLDÜRME!"
		3: txt = "ÜÇLÜ ÖLDÜRME!"
		4: txt = "DÖRTLÜ ÖLDÜRME!"
		5: txt = "KATLİAM!"
	if txt == "" and player_streak in [3, 5, 7, 10, 15]:
		txt = {3: "SERİ KATİL x3", 5: "DURDURULAMAZ x5", 7: "EFSANE x7", 10: "TANRISAL x10", 15: "SOKAĞIN KRALI x15"}[player_streak]
	hud.kill_confirm(head, txt, multi, wid, player_streak)

var killcam: Camera3D

func _killcam(killer: Node3D) -> void:
	## after death the camera flies from your eyes to the killer and keeps them framed
	if killcam and is_instance_valid(killcam):
		killcam.queue_free()
	killcam = Camera3D.new()
	killcam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	killcam.fov = 62
	add_child(killcam)
	killcam.global_transform = player.cam.global_transform
	killcam.current = true
	player.vm_rect.visible = false
	var start: Vector3 = player.cam.global_position
	var tw := killcam.create_tween()
	tw.tween_interval(0.6)
	tw.tween_method(func(t: float):
		if not is_instance_valid(killer) or not is_instance_valid(killcam):
			return
		var kp: Vector3 = killer.global_position + Vector3.UP * 1.5
		var away: Vector3 = (start - kp)
		away.y = 0
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		var goal: Vector3 = kp + away * 3.2 + Vector3.UP * 0.4 + away.cross(Vector3.UP) * 0.9
		# never let the camera pass through walls: stop just in front of the first obstacle
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(kp, goal, 1))
		if hit:
			goal = kp + (hit["position"] - kp) * 0.85
		var e := t * t * (3.0 - 2.0 * t)
		var cp: Vector3 = start.lerp(goal, e)
		var hit2 := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(kp, cp, 1))
		if hit2:
			cp = kp + (hit2["position"] - kp) * 0.85
		killcam.global_position = cp
		killcam.look_at(kp.lerp(kp, 1.0), Vector3.UP)
		killcam.fov = lerp(62.0, 45.0, e), 0.0, 1.0, 1.1)
	tw.tween_method(func(_t: float):
		if is_instance_valid(killer) and is_instance_valid(killcam):
			killcam.look_at(killer.global_position + Vector3.UP * 1.4, Vector3.UP), 0.0, 1.0, 1.8)

func _end_killcam() -> void:
	if killcam and is_instance_valid(killcam):
		killcam.queue_free()
	killcam = null
	if player:
		player.cam.current = true
		player.vm_rect.visible = true

func _check_win() -> void:
	if teams:
		if team_score["a"] >= target_score or team_score["b"] >= target_score:
			end_match()
	else:
		for c in combatants:
			if c["kills"] >= target_score:
				end_match()
				return

func _spawn(e: Dictionary, initial: bool) -> void:
	if e.has("net_id"):
		return
	var n = e["node"]
	if n == player:
		_end_killcam()
	var best = null
	var best_score := -1e9
	var cand := spawn_points.duplicate()
	cand.shuffle()
	for sp in cand:
		if teams and sp["team"] != "" and sp["team"] != e["team"] and not initial:
			pass
		var mind := 1e9
		for c in combatants:
			var o = c["node"]
			if o == n or not o.alive or (teams and c["team"] == e["team"]):
				continue
			mind = min(mind, o.global_position.distance_to(sp["pos"]))
		var sc: float = min(mind, 60.0) + randf() * 8.0
		# never stack on top of someone (teammates included)
		for c in combatants:
			var o2 = c["node"]
			if o2 != n and o2.alive and o2.global_position.distance_to(sp["pos"]) < 2.2:
				sc -= 40.0
		if teams and sp["team"] == e["team"]:
			sc += 25.0
		if initial and teams and sp["team"] != "" and sp["team"] != e["team"]:
			sc -= 100.0
		if sc > best_score:
			best_score = sc
			best = sp
	var pos: Vector3 = best["pos"] + Vector3(randf_range(-1.2, 1.2), 0.2, randf_range(-1.2, 1.2))
	if e["is_player"]:
		n.respawn(pos, best["yaw"])
		hud.on_respawn()
	else:
		n.respawn(pos, best["yaw"], _bot_weapon(int(e["gg"])))

# ---------------------------------------------------------------- end
func end_match() -> void:
	if net and Net.active() and Net.is_host() and not ended:
		Net.send({"t": "end"})
	if ended:
		return
	ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sorted := combatants.duplicate()
	sorted.sort_custom(func(a, b): return a["score"] > b["score"] if mode != "gungame" else a["gg"] > b["gg"])
	var pe := entry(player)
	var won := false
	if teams:
		won = team_score[pe["team"]] > team_score["b" if pe["team"] == "a" else "a"]
	else:
		won = sorted[0]["node"] == player
	var place := sorted.find(pe) + 1
	var xp: int = 200 + pe["kills"] * 100 + pe["head"] * 50 + (600 if won else 0) + max(0, 4 - place) * 100
	var gold: int = 150 + pe["kills"] * 45 + (400 if won else 0)
	var mats := {"demir": randi_range(6, 14) + pe["kills"], "krom": randi_range(2, 6) if randf() < 0.75 else 0, "titanyum": randi_range(1, 3) if randf() < 0.35 + (0.2 if won else 0.0) else 0, "kobalt": 1 if randf() < 0.12 + (0.1 if won else 0.0) else 0}
	var ups := GS.add_xp(xp)
	GS.profile["gold"] = int(GS.profile["gold"]) + gold
	for m in mats.keys():
		GS.profile["mats"][m] = int(GS.profile["mats"].get(m, 0)) + mats[m]
	GS.profile["stats"]["matches"] = int(GS.profile["stats"]["matches"]) + 1
	GS.profile["missions"]["matches"] = int(GS.profile["missions"]["matches"]) + 1
	if won:
		GS.profile["stats"]["wins"] = int(GS.profile["stats"]["wins"]) + 1
		GS.profile["missions"]["wins"] = int(GS.profile["missions"].get("wins", 0)) + 1
	GS.save_profile()
	SFX.play("success" if won else "fail")
	SFX.play_music("music_win" if won else "music_lose", -3, false)
	if hud and bool(GS.settings.get("announcer", true)): hud._announce("ann_win" if won else "ann_lose")
	hud.show_end({"won": won, "place": place, "xp": xp, "gold": gold, "mats": mats, "ups": ups, "sorted": sorted, "pe": pe})

func leave() -> void:
	SFX.stop_amb()
	SFX.clear_world()
	if net and Net.active():
		Online.set_status("room", Net.code)
		if Net.is_host():
			Online.publish_room(Net.code, cfg, Net.members.size(), "lobby")
		main.go_menu("netroom")    # back to the online room with your friends
	else:
		main.go_menu("lobby")

func test_hook(i: int) -> void:
	if i == 1:
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		var b = null
		for e in combatants:
			if not e["is_player"]:
				b = e["node"]
				break
		b.set_physics_process(false)
		var fwd: Vector3 = -b.global_transform.basis.z
		c.global_position = b.global_position + fwd * 3.0 + Vector3.UP * 1.5
		c.look_at(b.global_position + Vector3.UP * 1.1)
		c.far = 2000
		c.current = true
		if player: player.vm_rect.visible = false
	elif i == 12:
		# free camera: CAM="x,y,z,tx,ty,tz" (Godot coordinates)
		var v: PackedFloat64Array = OS.get_environment("CAM").split_floats(",")
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		c.global_position = Vector3(v[0], v[1], v[2])
		c.look_at(Vector3(v[3], v[4], v[5]))
		c.far = 3000
		c.fov = 70
		c.current = true
		if player: player.vm_rect.visible = false
	elif i == 15:
		# close-up of a bot's hands on the weapon: HC env = "angle" (0 side, 1 front-left, 2 top)
		var b = null
		for e in combatants:
			if not e["is_player"]:
				b = e["node"]; break
		b.set_physics_process(false)
		var ang := int(OS.get_environment("HC")) if OS.has_environment("HC") else 0
		var bb: Basis = b.global_transform.basis
		var focus: Vector3 = b.global_position + Vector3.UP * 1.35 - bb.z * 0.25
		var offs := [bb.x * 1.3 + Vector3.UP * 0.15, bb.x * 0.9 - bb.z * 1.0 + Vector3.UP * 0.2, -bb.x * 1.3 + Vector3.UP * 0.1, Vector3.UP * 1.1 + bb.x * 0.3 - bb.z * 0.3]
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		c.global_position = focus + offs[ang]
		c.look_at(focus)
		c.fov = 45
		c.current = true
		if player: player.vm_rect.visible = false
	elif i == 13 or i == 14:
		# side view of a bot getting hit (13) then killed by a headshot (14)
		var b = null
		for e in combatants:
			if not e["is_player"]:
				b = e["node"]; break
		if i == 13:
			b.set_physics_process(false)
			var rt: Vector3 = b.global_transform.basis.x
			var c := Camera3D.new()
			c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(c)
			c.global_position = b.global_position + rt * 4.0 + Vector3.UP * 1.4 - b.global_transform.basis.z * 1.5
			c.look_at(b.global_position + Vector3.UP * 0.9)
			c.current = true
			if player: player.vm_rect.visible = false
			var fwd: Vector3 = -b.global_transform.basis.z
			player.global_position = b.global_position + fwd * 6.0
			b.take_damage(25, player, b.global_position + fwd * 6.0 + Vector3.UP * 1.4, false, "ak47")
		else:
			b.set_physics_process(true)
			b.take_damage(999, player, player.global_position + Vector3.UP * 1.6, true, "ak47")
	elif i == 16:
		# close look at a bot holding a given weapon: BOTW=ak47 CAMOFF="x,y,z" (bot-local, +z = in front of the bot)
		var b = null
		for e in combatants:
			if not e["is_player"]:
				b = e["node"]; break
		b.set_physics_process(false)
		if OS.has_environment("BOTW"):
			b.set_weapon(OS.get_environment("BOTW"))
		b.aim_pitch = 0.0
		b.crouching = false
		b.model.position.y = 0.0
		b.model.rotation.y = PI
		b.leg_yaw = 0.0
		if b.twist:
			b.twist.twist = 0.0; b.twist.lean = 0.0; b.twist.hit_twist = 0.0; b.twist.head_kick = 0.0
		if b.anim: b.anim.play("Idle")
		var o: PackedFloat64Array = (OS.get_environment("CAMOFF") if OS.has_environment("CAMOFF") else "1.6,1.5,2.2").split_floats(",")
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		var bz: Vector3 = -b.global_transform.basis.z
		var bx: Vector3 = b.global_transform.basis.x
		c.global_position = b.global_position + bx * o[0] + Vector3.UP * o[1] + bz * o[2]
		c.look_at(b.global_position + Vector3.UP * 1.3)
		c.fov = 40
		c.current = true
		if player: player.vm_rect.visible = false
		if OS.has_environment("PLAYAIM"):
			b.pose.weight = 0.0
			b.set_process(false)
			b.anim.play("AimRifle")
			b.twist.twist = 0; b.twist.lean = 0
		print("HOOK15 pose=", b.pose, " gunparent=", b.gun.get_parent().name if b.gun else "none")
		if b.pose:
			var sk: Skeleton3D = b.skel
			var lh := sk.find_bone("Bip01 L Hand")
			var lw: Vector3 = sk.global_transform * sk.get_bone_global_pose(lh).origin
			var mk = b.gun.find_child("lhand", true, false)
			print("POSE kinds ", b.pose.poses.keys(), " n=", (b.pose.poses.get("rifle", {}) as Dictionary).size(), " w=", b.pose.weight, " lhand-dist ", lw.distance_to(mk.global_position) if mk else -1)
			var names := []
			for bi in (b.pose.poses.get("rifle", {}) as Dictionary).keys():
				names.append(sk.get_bone_name(bi))
			print("POSE bones ", names)
			print("MODS ", sk.get_children())
			var g: Dictionary = b.aim_data["rifle"]
			var exp_w: Vector3 = b.model.global_transform * Vector3(g["grip"][0], g["grip"][1], g["grip"][2])
			var rh := sk.find_bone("Bip01 R Hand")
			print("GRIPDBG expected ", exp_w, " gun ", b.gun.global_position, " rhand ", sk.global_transform * sk.get_bone_global_pose(rh).origin, " skel_xf ", b.model.global_transform.affine_inverse() * sk.global_transform)
	elif i == 17 or i == 18:
		# attachments + upgrade glow on the viewmodel: PARTS="sus,optik,tutamak" WLVL=5 ; 18 = aim down sights
		var ps: PackedStringArray = (OS.get_environment("PARTS") if OS.has_environment("PARTS") else "sus,optik,tutamak").split(",")
		GS.profile["wparts"] = {"ak47": Array(ps)}
		GS.profile["owned"]["ak47"]["lvl"] = int(OS.get_environment("WLVL")) if OS.has_environment("WLVL") else 5
		player.cur = ""
		player.switch_to("ak47", true)
		if i == 18:
			await get_tree().create_timer(0.3).timeout
			player.ads = true
	elif i == 2:
		# kill test: player headshots two bots in a row -> medal + blood
		var bots := []
		for e in combatants:
			if not e["is_player"]:
				bots.append(e["node"])
		var b = bots[0]
		b.set_physics_process(true)
		var fwd: Vector3 = -b.global_transform.basis.z
		player.global_position = b.global_position + fwd * 4.0
		var to: Vector3 = b.global_position - player.global_position
		player.yaw = atan2(-to.x, -to.z)
		player.pitch = -0.05
		await get_tree().physics_frame
		b.take_damage(999, player, player.global_position + Vector3.UP * 1.6, true, "ak47")
		await get_tree().create_timer(0.3).timeout
		if bots.size() > 1:
			bots[1].take_damage(999, player, player.global_position + Vector3.UP * 1.6, false, "ak47")
		hud.on_damaged(b.global_position, 40)
	elif i == 3:
		# character lineup
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		var base: Vector3 = player.global_position
		var ids: Array = GS.CHARACTERS.keys()
		var fwd: Vector3 = -player.global_transform.basis.z
		var right: Vector3 = player.global_transform.basis.x
		for k in ids.size():
			var ps: PackedScene = load("res://assets/models/rb_%s.glb" % ids[k])
			var m := ps.instantiate()
			MatLib.apply(m)
			add_child(m)
			m.global_position = base + fwd * 4.0 + right * ((k - (ids.size() - 1) / 2.0) * 0.9)
			m.look_at(base, Vector3.UP, true)
			var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and ap.has_animation("Idle"):
				ap.play("Idle")
		c.global_position = base + Vector3.UP * 1.2 - fwd * 0.5
		c.look_at(base + fwd * 4.0 + Vector3.UP * 0.95)
		c.fov = 60
		c.current = true
		for e in combatants:
			if not e["is_player"]:
				e["node"].visible = false
		player.vm_rect.visible = false
	elif i == 9:
		hud.toggle_buy(true)
	elif i == 8:
		# grenade aim preview
		for c in player.slots.keys():
			if c == "bomba":
				player.switch_to(player.slots[c], true)
		player.equip_t = 0
		Input.action_press("fire")
		player.pitch = 0.25
		player._start_throw()
	elif i == 6 or i == 7 or i == 5:
		# freeze a first-person animation pose for inspection
		var want: String = {6: "ak47", 7: "knife", 5: "frag"}[i]
		var cat: String = GS.WEAPONS[want]["cat"]
		player.slots[cat] = want
		player.ammo[want] = [5, 90]
		player.grenades = 2
		player.switch_to(want, true)
		player.equip_t = 0
		await get_tree().process_frame
		await get_tree().process_frame
		var a: String = {6: "reload", 7: "slash", 5: "throw"}[i]
		var tt: float = {6: 0.4, 7: float(OS.get_environment("KT") if OS.has_environment("KT") else "0.4"), 5: 0.33}[i]
		player._fp_play(a, 0.0)
		player.fp_ap.seek(tt * player._fp_len(a), true)
		if i == 6:
			player._mag_grab()
			player.reload_t = 1.0
			player.reload_total = 2.4
		player.fp_ap.pause()
		player.set_physics_process(false)
		player.set_process(false)
	elif i == 10:
		var c := Camera3D.new()
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		c.current = true
		c.fov = 50
		player.vm_rect.visible = false
		test_follow = [c, null]
		for e in combatants:
			if not e["is_player"]:
				test_follow[1] = e["node"]
				break
	elif i == 11:
		# navigation reachability audit between all spawn points
		var nm: RID = get_world_3d().navigation_map
		var bad := 0
		var a: Vector3 = spawn_points[0]["pos"]
		for k in spawn_points.size():
			var b: Vector3 = spawn_points[k]["pos"]
			var path := NavigationServer3D.map_get_path(nm, NavigationServer3D.map_get_closest_point(nm, a), NavigationServer3D.map_get_closest_point(nm, b), true)
			var endp: Vector3 = path[path.size() - 1] if path.size() > 0 else a
			var off_mesh: float = NavigationServer3D.map_get_closest_point(nm, b).distance_to(b)
			if path.size() == 0 or endp.distance_to(b) > 2.5 or off_mesh > 1.5:
				bad += 1
				print("NAV unreachable spawn ", k, " ", b, " end ", endp, " offmesh ", off_mesh)
		var stuck := 0
		print("NAV audit ", map_id, ": ", spawn_points.size(), " spawns, unreachable ", bad)
		get_tree().quit()
