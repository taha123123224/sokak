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
var sab = null   # sabotage.gd in SABOTAJ mode
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

class LoadFx extends Control:
	## v3.7.1 loading bar: one thin line along the bottom with a soft glowing head — nothing else
	var col := Color(1.0, 0.56, 0.16)
	var prog := 0.0
	var shown := 0.0
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		shown = lerpf(shown, prog, minf(d * 5.0, 1.0))
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var by := h - 64.0
		var bx0 := 80.0
		var bx1 := w - 80.0
		draw_rect(Rect2(bx0, by, bx1 - bx0, 2), Color(1, 1, 1, 0.12))
		var px := lerpf(bx0, bx1, clampf(shown / 100.0, 0.0, 1.0))
		draw_rect(Rect2(bx0, by, px - bx0, 2), col)
		# soft head glow + a slow shimmer travelling along the filled part
		for k in 4:
			draw_rect(Rect2(px - 40.0 + k * 10.0, by - 1, 40.0 - k * 10.0, 4), Color(1, 0.85, 0.6, 0.08 + k * 0.06))
		var sx := bx0 + fmod(t * 260.0, maxf(px - bx0, 1.0))
		if px - bx0 > 60.0:
			draw_rect(Rect2(sx - 30.0, by, 60.0, 2), Color(1, 1, 1, 0.35))

var _load_tips := ["Z tuşu ile nişangahın altını takımına işaretle.", "Eğilerek ateş etmek isabeti artırır.", "Nişancı tüfeklerinde nefesini tut: hareket etme!", "Tab tuşu ile skor tablosunu aç.",
	"F tuşu ile silahını incele.", "Kafadan vuruşlar 2.5 kat hasar verir.", "Shift ile yürürsen adım sesin duyulmaz.",
	"Enter ile sohbet et, V tuşu ile takımınla konuş.", "Silahını yükselttikçe hasar artar ve parıltısı değişir.",
	"Sabotajda öldükten sonra takım arkadaşlarını izleyebilirsin.", "Eklentiler (dürbün, susturucu) Çanta > ÖZELLEŞTİR menüsünde."]
var _load_fx: LoadFx
var _load_pct: Label

func _show_loading() -> void:
	## v3.7.1 clean loading screen: full-bleed map art, map name + one line of info bottom-left,
	## a thin progress line, a single tip. No panels, chips or brackets.
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.012, 0.014, 0.02)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(loading)
	var minfo: Dictionary = GS.MAPS.get(map_id, {})
	var minf: Dictionary = GS.MODES.get(mode, {})
	var ip := "res://assets/ui/load_%s.jpg" % map_id
	if not ResourceLoader.exists(ip):
		ip = "res://assets/ui/map_%s.jpg" % map_id
	if ResourceLoader.exists(ip):
		var bg := TextureRect.new()
		bg.texture = load(ip)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.modulate = Color(0.86, 0.86, 0.9)
		loading.add_child(bg)
		bg.resized.connect(func(): bg.pivot_offset = bg.size * Vector2(0.55, 0.45))
		var kb := bg.create_tween()
		kb.tween_property(bg, "scale", Vector2(1.06, 1.06), 16.0).from(Vector2(1.0, 1.0)).set_trans(Tween.TRANS_SINE)
	# one soft gradient from the bottom so the text reads, plus a light vignette
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gr.colors = PackedColorArray([Color(0.01, 0.012, 0.018, 0.96), Color(0.01, 0.012, 0.018, 0.66), Color(0.01, 0.012, 0.018, 0.0)])
	gt.gradient = gr
	gt.fill_from = Vector2(0.5, 1.0); gt.fill_to = Vector2(0.5, 0.35)
	gt.width = 64; gt.height = 256
	var gtr := TextureRect.new()
	gtr.texture = gt
	gtr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gtr.stretch_mode = TextureRect.STRETCH_SCALE
	gtr.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(gtr)
	_load_fx = LoadFx.new()
	_load_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.add_child(_load_fx)
	var bl := UI.vbox(2)
	bl.anchor_top = 1.0; bl.anchor_bottom = 1.0
	bl.offset_left = 80; bl.offset_top = -420; bl.offset_right = 1000; bl.offset_bottom = -112
	bl.alignment = BoxContainer.ALIGNMENT_END
	loading.add_child(bl)
	var md := UI.lbl("  ".join(str(minf.get("name", mode)).to_upper().split("")), 15, UI.ACCENT, "Rajdhani-Bold")
	bl.add_child(md)
	var title := UI.lbl(str(minfo.get("name", map_id)).to_upper(), 76, Color.WHITE, "RussoOne-Regular")
	title.modulate.a = 0.0
	bl.add_child(title)
	var tin := title.create_tween()
	tin.tween_property(title, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	var desc := UI.lbl(str(minfo.get("desc", "")), 19, Color(1, 1, 1, 0.68), "Rajdhani-SemiBold")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(700, 0)
	bl.add_child(desc)
	var infos: Array[String] = []
	if mode == "sabotaj":
		infos.append("%d TUR" % int(cfg.get("target", 5)))
	else:
		infos.append("%d DK" % int(cfg.get("time", 8)))
		infos.append("HEDEF %d" % int(cfg.get("target", 40)))
	if not cfg.get("net", false):
		infos.append("%d BOT" % int(cfg.get("bots", 9)))
		infos.append(["KOLAY", "NORMAL", "ZOR", "UZMAN"][clampi(int(cfg.get("diff", 1)), 0, 3)])
	else:
		infos.append("ONLINE")
	var meta := UI.hbox(14)
	meta.add_theme_constant_override("separation", 14)
	bl.add_child(meta)
	meta.add_child(UI.lbl("   ·   ".join(infos), 16, Color(1, 1, 1, 0.5), "Rajdhani-Bold"))
	if teams:
		var my: String = str(cfg.get("team", "a"))
		meta.add_child(UI.lbl("|", 16, Color(1, 1, 1, 0.2), "Rajdhani-Bold"))
		meta.add_child(UI.lbl("KARTAL" + ("  (SEN)" if my == "a" else ""), 16, GS.TEAM_COLORS["a"].lightened(0.25), "Rajdhani-Bold"))
		meta.add_child(UI.lbl("vs", 16, Color(1, 1, 1, 0.4), "Rajdhani-Bold"))
		meta.add_child(UI.lbl("AKREP" + ("  (SEN)" if my == "b" else ""), 16, GS.TEAM_COLORS["b"].lightened(0.25), "Rajdhani-Bold"))
	# status (left) and percentage (right), just above the line
	var st := UI.lbl("Harita yükleniyor...", 14, Color(1, 1, 1, 0.5), "Rajdhani-Bold")
	st.name = "st"
	st.anchor_top = 1.0; st.anchor_bottom = 1.0
	st.offset_left = 80; st.offset_top = -92; st.offset_right = 800; st.offset_bottom = -70
	loading.add_child(st)
	_load_pct = UI.lbl("0%", 18, Color(1, 1, 1, 0.85), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	_load_pct.anchor_left = 1.0; _load_pct.anchor_right = 1.0; _load_pct.anchor_top = 1.0; _load_pct.anchor_bottom = 1.0
	_load_pct.offset_left = -280; _load_pct.offset_right = -80; _load_pct.offset_top = -94; _load_pct.offset_bottom = -70
	loading.add_child(_load_pct)
	# one quiet tip under the line
	var tipl := UI.lbl(_load_tips[randi() % _load_tips.size()], 15, Color(1, 1, 1, 0.42), "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER)
	tipl.anchor_left = 0.0; tipl.anchor_right = 1.0; tipl.anchor_top = 1.0; tipl.anchor_bottom = 1.0
	tipl.offset_top = -50; tipl.offset_bottom = -26
	loading.add_child(tipl)
	var tt := tipl.create_tween().set_loops(8)
	tt.tween_interval(4.5)
	tt.tween_property(tipl, "modulate:a", 0.0, 0.3)
	tt.tween_callback(func(): tipl.text = _load_tips[randi() % _load_tips.size()])
	tt.tween_property(tipl, "modulate:a", 1.0, 0.3)
	loading.modulate.a = 0.0
	var fin := loading.create_tween()
	fin.tween_property(loading, "modulate:a", 1.0, 0.3)

func _loading_roster() -> void:
	## loading screen roster: removed in v3.7.1 (clean screen) — kept as a no-op for callers
	return
	if loading == null or not is_instance_valid(loading) or combatants.is_empty():
		return
	var box := UI.panel(Color(0.02, 0.025, 0.035, 0.82), Color(1, 1, 1, 0.1), 12, 1)
	box.anchor_left = 1.0; box.anchor_right = 1.0
	box.offset_left = -520; box.offset_right = -70; box.offset_top = 120
	loading.add_child(box)
	var v := UI.vbox(6)
	box.add_child(v)
	v.add_child(UI.lbl("OYUNCULAR  •  %d" % combatants.size(), 14, UI.ACCENT2, "Rajdhani-Bold"))
	var cols := UI.hbox(18)
	v.add_child(cols)
	var groups := [["a", "KARTAL"], ["b", "AKREP"]] if teams else [["", ""]]
	for g in groups:
		var cv := UI.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(cv)
		var gc: Color = GS.TEAM_COLORS.get(g[0], Color.WHITE)
		if g[1] != "":
			cv.add_child(UI.lbl(g[1], 16, gc, "RussoOne-Regular"))
		var n := 0
		for c in combatants:
			if teams and c["team"] != g[0]:
				continue
			n += 1
			if n > 8:
				continue
			var row := UI.hbox(6)
			cv.add_child(row)
			var dot := ColorRect.new()
			dot.color = gc if teams else UI.ACCENT
			dot.custom_minimum_size = Vector2(3, 18)
			row.add_child(dot)
			row.add_child(UI.lbl(str(c["name"]), 16, Color.WHITE if not c["is_player"] else UI.GOLD, "Rajdhani-Bold"))
			row.add_child(UI.spacer())
			row.add_child(UI.lbl("Sv %d" % int(c.get("lvl", 1)), 13, UI.DIM, "Rajdhani-SemiBold"))
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.3)

func _process_loading_pct() -> void:
	if _load_pct and is_instance_valid(_load_pct) and _load_fx and is_instance_valid(_load_fx):
		_load_pct.text = "%d%%" % int(round(_load_fx.shown))

func _progress(p: float, t: String) -> void:
	if OS.has_environment("MEMLOG"):
		print("MEM %d%% static=%dMB vram=%dMB tex=%dMB buf=%dMB  %s" % [int(p), int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0), t])
	if _load_fx and is_instance_valid(_load_fx):
		_load_fx.prog = p
	var st := loading.find_child("st", true, false) as Label
	if st: st.text = t.to_upper()
	# give the bar a few frames to glide (also keeps the window responsive)
	if OS.has_environment("DBGLOAD"): print("PROG ", p, " ", t)
	for k in 3:
		_process_loading_pct()
		await get_tree().process_frame
		if OS.has_environment("DBGLOAD"): print("  frame ok ", k)

func _build() -> void:
	fx = preload("res://scripts/fx.gd").new()
	add_child(fx)
	await _progress(10, "Harita modeli yükleniyor...")
	var f := FileAccess.open(GS.map_paths(map_id)["json"], FileAccess.READ)
	map_data = JSON.parse_string(f.get_as_text())
	bounds = map_data["bounds"]
	if not map_data.has("env"):
		map_data["env"] = {"preset": "day"}
	# v3.1 cinematic look, matching the map key art: warm low sun on the old-town maps
	if MAP_LOOK.has(map_id) and not OS.has_environment("ENVPRESET"):
		map_data["env"]["preset"] = MAP_LOOK[map_id]
	if mode == "kurt" and not OS.has_environment("ENVPRESET"):
		# Kurt Adam: cinematic blue-hour dusk (deep blue sky, amber horizon, moonrise, faint aurora)
		map_data["env"]["preset"] = "alaca"
	if OS.has_environment("ENVPRESET"):
		map_data["env"]["preset"] = OS.get_environment("ENVPRESET")
	var ps: PackedScene = GS.map_scene(map_id)
	var vis := ps.instantiate()
	vis.name = "Map"
	map_vis = vis
	add_child(vis)
	await _progress(30, "Malzemeler ve dokular hazırlanıyor...")
	MatLib.apply(vis)
	if map_data.get("mesh_collision", false):
		_fix_imported_mats(vis)
	_apply_baked_ao(vis)
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
	# v3.4 imported maps: their own meshes are the collision (trimesh, world layer)
	if map_data.get("mesh_collision", false):
		var nocol: Array = map_data.get("nocol", [])
		for mi in vis.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			var skip := false
			for nc in nocol:
				if str(nc) in String(m3.name):
					skip = true
			for si in m3.mesh.get_surface_count():
				var sm := m3.mesh.surface_get_material(si)
				if sm and str(sm.resource_name).to_lower().contains("decal"):
					skip = true
			if skip:
				continue
			var shp := m3.mesh.create_trimesh_shape()
			if shp == null:
				continue
			var msb := StaticBody3D.new()
			msb.collision_layer = 1
			var mcs := CollisionShape3D.new()
			mcs.shape = shp
			msb.add_child(mcs)
			statics.add_child(msb)
			msb.global_transform = m3.global_transform
	# v3.4 imported maps that end in the void: a wide textured ground plane out to the horizon
	if map_data.has("ground"):
		var gd: Dictionary = map_data["ground"]
		var gm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1600, 1600)
		gm.mesh = pm
		var gmat := StandardMaterial3D.new()
		var gt := str(gd.get("tex", "dirt"))
		if ResourceLoader.exists("res://assets/tex/%s_albedo.png" % gt):
			gmat.albedo_texture = load("res://assets/tex/%s_albedo.png" % gt)
		if ResourceLoader.exists("res://assets/tex/%s_normal.png" % gt):
			gmat.normal_enabled = true
			gmat.normal_texture = load("res://assets/tex/%s_normal.png" % gt)
		var tn: Array = gd.get("tint", [1, 1, 1])
		gmat.albedo_color = Color(float(tn[0]), float(tn[1]), float(tn[2]))
		gmat.roughness = 0.95
		gmat.uv1_scale = Vector3(400, 400, 1)
		gm.material_override = gmat
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.position = Vector3(0, float(gd.get("y", -0.03)), 0)
		vis.add_child(gm)
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
	if not GS.has_meta("nonav"):
		await _bake_nav()
	_add_occluders()
	_add_reflection_probes()
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
	if mode == "kurt":
		for c in combatants:
			var wc = preload("res://scripts/wolf.gd").new()
			wc.host = c["node"]
			wc.is_player = c["is_player"]
			if OS.has_environment("WOLFFULL") and (c["is_player"] or not OS.has_environment("WOLFPONLY")): wc.energy = 100.0
			c["node"].wolf_ctl = wc
			c["node"].add_child(wc)
	if OS.has_environment("DBGLOAD"): print("SPAWNED")
	_fill_gun_pool()
	_loading_roster()
	await _progress(92, "Efektler ve gölgelendiriciler hazırlanıyor...")
	if GRASS_MAPS.has(map_id) and str(GS.settings.get("quality", "high")) != "low" and bool(GS.settings.get("grass", true)):
		await _scatter_grass(GRASS_MAPS[map_id])
	await _prewarm()
	await _progress(100, "Hazır!")
	for k in 8:
		_process_loading_pct()
		await get_tree().process_frame
	SFX.play_music("music_match", -13, false)
	SFX.play_amb(GS.MAPS.get(map_id, {}).get("amb", {"mahalle": "amb_city", "safranbolu": "amb_town", "gemi": "amb_ship", "liman": "amb_port", "insaat": "amb_wind", "canakkale": "amb_sea"}.get(map_id, "amb_town")))
	# dip to black, then reveal the match (no messy cross-fade of the loading art over the HUD)
	var blk := ColorRect.new()
	blk.color = Color(0, 0, 0, 0)
	blk.set_anchors_preset(Control.PRESET_FULL_RECT)
	blk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.get_parent().add_child(blk)
	var tw := create_tween()
	tw.tween_property(blk, "color:a", 1.0, 0.22)
	tw.tween_callback(func(): loading.visible = false)
	tw.tween_property(blk, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(loading.get_parent().queue_free)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	countdown = 3.0
	hud.show_countdown()
	if mode == "sabotaj":
		sab = preload("res://scripts/sabotage.gd").new()
		add_child(sab)
		sab.setup(self)
	GS.act("match_start")   # the server measures real match time (bounds the rewards)

func _frame_drawn() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame   # no renderer: frame_post_draw never fires
	else:
		await RenderingServer.frame_post_draw

func _prewarm() -> void:
	## draw every effect once behind the loading screen so shaders/pipelines are compiled now,
	## not in the middle of a fight (prevents first-shot / first-kill stutters)
	var cam: Camera3D = player.cam
	var _pw := OS.get_environment("PWSKIP")
	if _pw == "all": return
	var p: Vector3 = cam.global_position - cam.global_transform.basis.z * 3.0
	var n: Vector3 = cam.global_transform.basis.z
	SFX.silent = true
	if _pw != "fx":
		fx.impact(p, n, "concrete")
		fx.impact(p, n, "metal")
		fx.blood(p, n)
		fx.death_burst(p, n, true)
		fx.blood_decal(p, n, 0.5)
		fx.tracer(p - Vector3(1, 0, 0), p + Vector3(1, 0, 0))
		fx.muzzle_light(p, 1.0)
		fx.explosion(p + n * -8.0)
	if OS.has_environment("DBGLOAD"): print("PW fx done")
	if _pw == "guns":
		SFX.silent = false
		return
	# weapon models that can actually appear in this match (bot pool + player loadout), drawn a few per frame:
	# drawing all 33 weapons in one frame overflowed the D3D12 sampler-descriptor heap on AMD (device lost -> crash)
	var ids: Array = gun_pool.keys().duplicate()
	for c in player.slots.keys():
		if not player.slots[c] in ids:
			ids.append(player.slots[c])
	if OS.has_environment("PWONLY"):
		ids = Array(OS.get_environment("PWONLY").split(","))
	var tmp := Node3D.new()
	add_child(tmp)
	tmp.global_position = p
	var batch := 0
	for wid in ids:
		var ps := GS.weapon_scene(wid)
		if ps == null:
			continue
		var w := ps.instantiate()
		MatLib.apply(w, GS.wskin(wid))
		tmp.add_child(w)
		batch += 1
		if OS.has_environment("DBGLOAD"): print("PW gun ", wid)
		if batch >= 4:
			batch = 0
			for i in 2:
				await _frame_drawn()
				if OS.has_environment("DBGLOAD"): print("PW drawn")
			for ch in tmp.get_children():
				ch.queue_free()
	for i in 2:
		await _frame_drawn()
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

## CS2-style local cubemaps: a grid of ReflectionProbes over the playable area, each rendered once at load.
## Metal, glass, wet ground and gun bodies then mirror their real surroundings instead of only the sky.
## Update-once probes cost nothing per frame; the grid is coarser on lower settings.
func _add_reflection_probes() -> void:
	var qi := ["low", "medium", "high", "ultra"].find(str(GS.settings.get("quality", "high")))
	if qi <= 0 or GS.has_meta("noprobes"):
		return
	var root := Node3D.new()
	root.name = "Probes"
	add_child(root)
	var w: float = bounds[2] - bounds[0]
	var h: float = bounds[3] - bounds[1]
	var cell: float = [0.0, 36.0, 26.0, 20.0][qi]
	var nx := maxi(1, int(ceil(w / cell)))
	var nz := maxi(1, int(ceil(h / cell)))
	var cx: float = w / nx
	var cz: float = h / nz
	var base_y := 0.0 if map_id != "gemi" else 30.0
	for ix in nx:
		for iz in nz:
			var p := ReflectionProbe.new()
			p.update_mode = ReflectionProbe.UPDATE_ONCE
			p.size = Vector3(cx + 4.0, 18.0, cz + 4.0)
			p.origin_offset = Vector3(0, -5.0, 0)
			p.box_projection = true
			p.interior = false
			p.enable_shadows = false
			p.max_distance = 60.0
			p.intensity = 0.85
			p.cull_mask = 1
			p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			root.add_child(p)
			p.global_position = Vector3(bounds[0] + cx * (ix + 0.5), base_y + 7.0, -(bounds[1] + cz * (iz + 0.5)))

# ---------------------------------------------------------------- bot gun pool
## guns are built during the loading screen and handed to bots when they (re)spawn: building a gun model
## mid-match took 5-28 ms (a visible hitch every time a bot respawned with a new weapon)
var gun_pool := {}
func give_gun(g: Node3D) -> void:
	var id: String = g.get_meta("wid", "")
	if id == "":
		g.queue_free(); return
	if not gun_pool.has(id):
		gun_pool[id] = []
	gun_pool[id].append(g)

func take_gun(id: String) -> Node3D:
	var arr: Array = gun_pool.get(id, [])
	while not arr.is_empty():
		var g = arr.pop_back()
		if is_instance_valid(g):
			return g
	return null

func _fill_gun_pool() -> void:
	var ids: Array = []
	if mode == "gungame":
		ids = GS.GUNGAME_ORDER.duplicate()
	else:
		for k in 30:
			var w := _bot_weapon(0)
			if not w in ids: ids.append(w)
	for id in ids:
		if not GS.WEAPONS.has(id):
			continue
		var ps: PackedScene = GS.weapon_scene(id)
		if ps == null:
			continue
		for k in 2:
			var g := ps.instantiate()
			g.set_meta("wid", id)
			MatLib.apply(g, "std" if k == 0 else GS.SKINS.keys()[randi() % GS.SKINS.size()])
			give_gun(g)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for id in gun_pool.keys():
			for g in gun_pool[id]:
				if is_instance_valid(g) and not g.is_inside_tree():
					g.free()
		gun_pool.clear()

func _bot_weapon(gg: int) -> String:
	match mode:
		"knife":
			return "knife" if randf() < 0.6 else "karambit"
		"sniper":
			return ["awp", "kar98", "awm"][randi() % 3]
		"gungame":
			return GS.GUNGAME_ORDER[min(gg, GS.GUNGAME_ORDER.size() - 1)]
	var pool := ["ak47", "ak47", "m4a1", "m4a1", "scar", "aug", "vector", "m249", "mp5", "p90", "ump45", "spas", "awp", "kar98", "deagle", "revolver", "vityaz", "rpk16", "r870", "m1911", "fn502", "awm", "uzi", "kuzgun", "m4k", "usp", "kartal", "akm"]
	return pool[randi() % pool.size()]

var env_exp := 1.0
var map_vis: Node3D
var _cams_i := 0

## CS2-style baked contact shading: tools/bake_ao.py bakes an ambient-occlusion atlas (UV2) per map with Cycles;
## here it goes into the AO slot of every map material. Corners, under eaves, between crates, inside the
## building: all get the soft darkening that real light bounce produces, at zero per-frame cost.
func _apply_baked_ao(vis: Node3D) -> void:
	var path := "res://assets/maps/%s_ao.png" % map_id
	if GS.has_meta("noao") or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var done := {}
	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).begins_with("chunk"):
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if mat is StandardMaterial3D:
				var key := mat.get_instance_id()
				if not done.has(key):
					var m2: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					m2.ao_enabled = true
					m2.ao_texture = tex
					m2.ao_on_uv2 = true
					m2.ao_light_affect = 0.25
					m2.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					done[key] = m2
				m.set_surface_override_material(si, done[key])

const MAP_LOOK := {"mahalle": "golden", "safranbolu": "golden"}

func _setup_env(env_cfg: Dictionary) -> void:
	Engine.max_fps = GS.fps_limit()   # menu caps at 144, the match uses the player's setting
	var preset: String = env_cfg.get("preset", "day")
	var s := GS.settings
	world_env = WorldEnvironment.new()
	var e := Environment.new()
	sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_512 if int(s["shadows"]) >= 3 else Sky.RADIANCE_SIZE_256
	sun = DirectionalLight3D.new()
	# natural, filmic light (Zula-like): warm key sun, sky-blue ambient in the shadows, deep contact shadows,
	# colours kept realistic (no washed-out white, no candy saturation)
	var P := {
		"day":      {"elev": -52.0, "az": 35.0, "sun": Color(1.0, 0.93, 0.82), "se": 2.3, "top": Color("1f6bd2"), "hor": Color("a3cdf0"), "amb": Color(0.72, 0.73, 0.76), "ae": 0.85, "fog": Color("bfcad6"), "exp": 0.97, "sat": 0.93, "fill": Color(0.8, 0.84, 0.92)},
		"golden":   {"elev": -36.0, "az": 220.0, "sun": Color(1.0, 0.83, 0.62), "se": 2.3, "top": Color("2463c0"), "hor": Color("f0cfa6"), "amb": Color(0.72, 0.7, 0.7), "ae": 0.82, "fog": Color("d9c0a4"), "exp": 0.96, "sat": 1.0, "fill": Color(0.7, 0.75, 0.92)},
		"sunset":   {"elev": -22.0, "az": 280.0, "sun": Color(1.0, 0.74, 0.52), "se": 2.15, "top": Color("2a539f"), "hor": Color("ffab7a"), "amb": Color(0.7, 0.66, 0.68), "ae": 0.8, "fog": Color("d9ab8e"), "exp": 0.95, "sat": 0.98, "fill": Color(0.62, 0.66, 0.9)},
		"twilight": {"elev": -16.0, "az": 250.0, "sun": Color(1.0, 0.72, 0.5), "se": 2.4, "top": Color("2a3a9a"), "hor": Color("ffa86a"), "amb": Color(0.78, 0.76, 0.84), "ae": 1.15, "fog": Color("b9a3b8"), "exp": 1.05, "sat": 1.1, "fill": Color(0.6, 0.6, 1.0)},
		"night":    {"elev": -38.0, "az": 140.0, "sun": Color(0.62, 0.72, 1.0), "se": 0.75, "top": Color("08101f"), "hor": Color("2b3350"), "amb": Color(0.3, 0.34, 0.48), "ae": 0.62, "fog": Color("1d2438"), "exp": 1.05, "sat": 0.85, "fill": Color(0.4, 0.48, 0.85)},
		"alaca":    {"elev": -14.0, "az": 235.0, "sun": Color(1.0, 0.68, 0.46), "se": 2.1, "top": Color("0f1a3a"), "hor": Color("e8925a"), "amb": Color(0.56, 0.63, 0.8), "ae": 0.95, "fog": Color("6d7d99"), "exp": 1.0, "sat": 0.98, "fill": Color(0.5, 0.6, 0.95)},
		"overcast": {"elev": -55.0, "az": 120.0, "sun": Color(1.0, 0.96, 0.9), "se": 1.9, "top": Color("4f7fb8"), "hor": Color("c6d5e4"), "amb": Color(0.7, 0.72, 0.76), "ae": 0.75, "fog": Color("c2ccd6"), "exp": 1.0, "sat": 0.92, "fill": Color(0.8, 0.84, 0.9)},
	}
	var c: Dictionary = P.get(preset, P["day"])
	sun.rotation_degrees = Vector3(c["elev"], c["az"], 0)
	sun.light_color = c["sun"]
	sun.light_energy = c["se"]
	sun.shadow_enabled = int(s["shadows"]) > 0
	# every shadow split re-renders the map from the sun: 4 splits only on ULTRA+, shorter range on lower tiers
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(s["shadows"]) >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [40.0, 55.0, 80.0, 120.0, 180.0][clamp(int(s["shadows"]), 0, 4)] * clampf(float(s.get("shadow_dist", 1.0)), 0.5, 1.5)
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.shadow_opacity = 0.93
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
	sm.sky_energy_multiplier = 1.0
	sm.ground_energy_multiplier = 0.6
	sm.sky_cover = load("res://assets/tex/clouds.png") if ResourceLoader.exists("res://assets/tex/clouds.png") else null
	sm.sky_cover_modulate = Color(1, 1, 1, 0.9)
	if str(env_cfg.get("preset", "")) == "alaca":
		var ssm := ShaderMaterial.new()
		ssm.shader = preload("res://shaders/sky_alaca.gdshader")
		var sdir: Vector3 = Basis.from_euler(Vector3(deg_to_rad(float(c["elev"])), deg_to_rad(float(c["az"])), 0.0)).z
		ssm.set_shader_parameter("sun_dir", sdir)
		ssm.set_shader_parameter("moon_dir", (Vector3(-sdir.x, 0.0, -sdir.z).normalized() * 0.92 + Vector3(0.25, 0.0, 0.0)).normalized() + Vector3.UP * 0.32)
		sky.sky_material = ssm
	elif str(env_cfg.get("preset", "")) == "night":
		# moonlit night: dim blue-grey clouds, a big pale moon, dark ground, cool ambient
		sm.sky_cover_modulate = Color(0.16, 0.19, 0.28, 0.85)
		sm.ground_bottom_color = Color(0.03, 0.035, 0.05)
		sm.sun_angle_max = 2.5
		sm.sun_curve = 0.05
		sm.sky_energy_multiplier = 0.55
	var pack := str(s.get("color_pack", "canli"))
	if preset in ["day", "golden", "sunset", "overcast", "twilight"] and pack != "gercekci":
		# v3.7 modern sky with lit clouds (+ studio panels in the reflection pass for crisp metal)
		var mm := ShaderMaterial.new()
		mm.shader = preload("res://shaders/sky_modern.gdshader")
		mm.set_shader_parameter("zen", c["top"])
		mm.set_shader_parameter("hor", c["hor"])
		mm.set_shader_parameter("gnd", Color(0.32, 0.31, 0.29))
		mm.set_shader_parameter("sun_col", c["sun"])
		mm.set_shader_parameter("cover", {"day": 0.5, "golden": 0.46, "sunset": 0.5, "overcast": 0.82, "twilight": 0.5}[preset])
		mm.set_shader_parameter("cloud_dark", Color(c["top"]).lerp(Color(0.62, 0.66, 0.74), 0.6))
		mm.set_shader_parameter("studio", 0.55)
		sky.sky_material = mm
	elif str(env_cfg.get("preset", "")) != "alaca":
		sky.sky_material = sm
	# soft fill light from the opposite side (lifts shadows, no extra shadow pass)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, float(c["az"]) + 180.0, 0)
	fill.light_color = c["fill"]
	fill.light_energy = 0.3
	fill.light_specular = 0.05
	fill.shadow_enabled = false
	add_child(fill)
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = c["amb"]
	e.ambient_light_sky_contribution = 0.5
	e.ambient_light_energy = c["ae"]
	if str(env_cfg.get("preset", "")) == "night":
		e.ambient_light_sky_contribution = 0.25
		e.ambient_light_energy = 0.42
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES if pack == "gercekci" else Environment.TONE_MAPPER_AGX
	env_exp = float(c["exp"]) * (1.0 if pack == "gercekci" else 1.04)
	e.tonemap_exposure = env_exp * float(s.get("brightness", 1.0))
	e.tonemap_white = 6.0
	e.fog_enabled = not GS.has_meta("nofog")
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = c["fog"]
	e.fog_light_energy = 1.0
	e.fog_density = 0.6
	e.fog_depth_begin = 45.0
	e.fog_depth_end = 520.0 * float(s["draw_distance"])
	e.fog_depth_curve = 2.0
	e.fog_sun_scatter = 0.12
	e.fog_sky_affect = 0.0
	e.ssao_enabled = bool(s["ssao"])
	e.ssao_radius = 1.4; e.ssao_intensity = 2.3; e.ssao_power = 1.6; e.ssao_detail = 1.0; e.ssao_horizon = 0.06
	e.ssao_sharpness = 0.98; e.ssao_light_affect = 0.18; e.ssao_ao_channel_affect = 0.4
	e.ssil_enabled = bool(s["ssil"])
	e.ssil_radius = 4.0; e.ssil_intensity = 1.25; e.ssil_sharpness = 0.98; e.ssil_normal_rejection = 1.0
	e.ssr_enabled = bool(s["ssr"])
	e.ssr_max_steps = 64 if int(s["shadows"]) >= 3 else 40; e.ssr_fade_in = 0.15; e.ssr_fade_out = 2.0; e.ssr_depth_tolerance = 0.3
	e.sdfgi_enabled = bool(s["sdfgi"])
	if e.sdfgi_enabled:
		e.sdfgi_use_occlusion = true
		e.sdfgi_cascades = 4
		e.sdfgi_energy = 1.0
		e.sdfgi_bounce_feedback = 0.6
	e.glow_enabled = bool(s["glow"])
	e.glow_intensity = 0.5; e.glow_strength = 0.95; e.glow_bloom = 0.025; e.glow_hdr_threshold = 1.25
	e.glow_hdr_scale = 2.2; e.glow_mix = 0.09; e.glow_bloom = 0.04
	e.set_glow_level(0, 0.0); e.set_glow_level(1, 0.6); e.set_glow_level(2, 1.0); e.set_glow_level(3, 0.8); e.set_glow_level(4, 0.4); e.set_glow_level(5, 0.2)
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.volumetric_fog_enabled = bool(s["volumetric"])
	e.volumetric_fog_density = 0.0018
	e.volumetric_fog_albedo = Color(1, 0.97, 0.92)
	e.volumetric_fog_length = 80.0
	e.volumetric_fog_anisotropy = 0.35
	e.volumetric_fog_sky_affect = 1.0   # smoke grenades must also hide the sky behind them
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.13
	e.adjustment_saturation = float(c["sat"]) * 1.06
	e.adjustment_color_correction = _grade_lut()
	if pack == "canli":
		# "Canlı" (Valorant-like): clean, vivid colour with punchy but not neon contrast
		e.adjustment_contrast = 1.08
		e.adjustment_saturation = float(c["sat"]) * 1.24
		e.adjustment_color_correction = grade_lut3d("canli")
	elif pack == "sinematik":
		e.adjustment_contrast = 1.14
		e.adjustment_saturation = float(c["sat"]) * 1.1
		e.adjustment_color_correction = grade_lut3d("sinematik")
	if preset == "alaca":
		# cinematic blue hour: cool shadows, warm low sun, light haze in the valley
		e.volumetric_fog_albedo = Color(0.8, 0.86, 1.0)
		e.volumetric_fog_density = 0.0024
		e.fog_sun_scatter = 0.28
		e.fog_density = 0.45
		e.glow_intensity = 0.6; e.glow_mix = 0.1
		e.adjustment_contrast = 1.12
	world_env.environment = e
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	world_env.camera_attributes = ca
	add_child(world_env)
	add_child(sun)

## Film-style grade: gentle S-curve, cool shadows, warm highlights (modern shooter look)
## v3.7 colour packs: a 33³ 3D LUT applied after tonemapping
static var _lut_cache := {}
static func grade_lut3d(pack: String) -> ImageTexture3D:
	if _lut_cache.has(pack):
		return _lut_cache[pack]
	var N := 33
	var imgs: Array[Image] = []
	for bz in N:
		var im := Image.create(N, N, false, Image.FORMAT_RGB8)
		for gy in N:
			for rx in N:
				var c := Vector3(float(rx), float(gy), float(bz)) / float(N - 1)
				im.set_pixel(rx, gy, _grade(c, pack))
		imgs.append(im)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, N, N, N, false, imgs)
	_lut_cache[pack] = t
	return t

static func _grade(c: Vector3, pack: String) -> Color:
	var lum := c.dot(Vector3(0.2126, 0.7152, 0.0722))
	var mx := maxf(c.x, maxf(c.y, c.z)); var mn := minf(c.x, minf(c.y, c.z))
	var sat := mx - mn
	var vib := 0.38 if pack == "canli" else 0.15
	c = Vector3(lum, lum, lum) + (c - Vector3(lum, lum, lum)) * (1.0 + vib * (1.0 - sat))
	if pack == "canli":
		# cool clean shadows, warm sunny highlights, gentle S-curve, no crushed blacks
		c += Vector3(-0.012, 0.006, 0.03) * pow(1.0 - lum, 2.0)
		c += Vector3(0.028, 0.014, -0.012) * lum * lum
		var sc := Vector3(smoothstep(0.0, 1.0, c.x), smoothstep(0.0, 1.0, c.y), smoothstep(0.0, 1.0, c.z))
		c = c.lerp(sc, 0.22)
		c = c * 0.985 + Vector3(0.012, 0.014, 0.018)
	else:
		# cinematic teal / orange
		c += Vector3(-0.03, 0.01, 0.045) * pow(1.0 - lum, 2.2)
		c += Vector3(0.05, 0.02, -0.03) * lum * lum
		var sc2 := Vector3(smoothstep(0.0, 1.0, c.x), smoothstep(0.0, 1.0, c.y), smoothstep(0.0, 1.0, c.z))
		c = c.lerp(sc2, 0.35)
	return Color(clampf(c.x, 0, 1), clampf(c.y, 0, 1), clampf(c.z, 0, 1))

static func _grade_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.3, 0.55, 0.8, 1.0])
	g.colors = PackedColorArray([
		Color(0.0, 0.006, 0.014), Color(0.098, 0.112, 0.126), Color(0.28, 0.292, 0.3),
		Color(0.556, 0.553, 0.545), Color(0.822, 0.808, 0.785), Color(1.0, 0.99, 0.965)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t

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

## dynamic resolution: keeps the frame rate up on weaker PCs by lowering the 3D render scale (FSR upscales it back),
## and raises it again when there is headroom. The HUD / text always stay at full resolution.
var _dr_acc := 0.0
var _dr_n := 0
var _dr_scale := -1.0
func _dyn_res(delta: float) -> void:
	if not bool(GS.settings.get("dyn_res", true)) or paused or loading != null and is_instance_valid(loading):
		return
	_dr_acc += delta
	_dr_n += 1
	if _dr_acc < 1.5:
		return
	var fps := _dr_n / _dr_acc
	_dr_acc = 0.0; _dr_n = 0
	var vp := get_viewport()
	var user_s := float(GS.settings.get("resolution_scale", 1.0))
	if _dr_scale < 0:
		_dr_scale = user_s
	var target := float(GS.settings.get("dyn_target", 60))
	var old := _dr_scale
	if fps < target * 0.92:
		_dr_scale = maxf(0.67, _dr_scale - (0.1 if fps < target * 0.7 else 0.05))
	elif fps > target * 1.35 and _dr_scale < user_s:
		_dr_scale = minf(user_s, _dr_scale + 0.05)
	if absf(old - _dr_scale) > 0.001:
		vp.scaling_3d_scale = _dr_scale
		if player and player.vm_vp:
			player.vm_vp.scaling_3d_scale = minf(1.0, _dr_scale + 0.15)
		if _dr_scale < 0.99:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.fsr_sharpness = 0.25
		else:
			GS.apply_settings()

# ---------------------------------------------------------------- grass
## maps that get real grass tufts on open ground. exclude = rectangles in map (Blender) coordinates x0,y0,x1,y1
const GRASS_MAPS := {
	"canakkale": {"step": 0.85, "tint": Color(0.86, 0.8, 0.55), "exclude": [[-11.5, -50, -4.5, 50], [-6, -35, 90, -25], [0, 6, 44, 38]]},
}
const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fade_end = 38.0;
varying float vfade;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(UV.y < 0.5 ? 1.0 : 0.0, 0.0, 1.0);
	float w = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.27) * 0.08 + sin(TIME * 3.1 + wp.x * 1.3) * 0.025;
	VERTEX.x += w * h;
	VERTEX.z += w * 0.6 * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vfade = 1.0 - smoothstep(fade_end * 0.75, fade_end, length(wp - CAMERA_POSITION_WORLD));
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * tint.rgb * mix(0.72, 1.0, 1.0 - UV.y);
	ALPHA = t.a * vfade;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.25, 0.22, 0.1);
}
"""

func _scatter_grass(cfg: Dictionary) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var b: Array = bounds
	var step: float = float(cfg["step"]) * (1.0 if str(GS.settings.get("quality", "high")) != "medium" else 1.35)
	# two crossed quads, 0.55 m tall
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.4
		var d := Vector3(cos(a), 0, sin(a)) * 0.42
		var v0 := -d; var v1 := d
		var hgt := Vector3(0, 0.55, 0)
		for tri in [[v0, Vector2(0, 1)], [v1, Vector2(1, 1)], [v1 + hgt, Vector2(1, 0)], [v0, Vector2(0, 1)], [v1 + hgt, Vector2(1, 0)], [v0 + hgt, Vector2(0, 0)]]:
			st.set_uv(tri[1]); st.set_normal(Vector3.UP); st.add_vertex(tri[0])
	st.commit(am)
	var mat := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = GRASS_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tex", load("res://assets/tex/grass_tuft.png"))
	mat.set_shader_parameter("tint", cfg["tint"])
	am.surface_set_material(0, mat)
	var chunks := {}
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var x: float = b[0]
	var excl: Array = cfg["exclude"]
	while x < float(b[2]):
		var y: float = b[1]
		while y < float(b[3]):
			var px := x + rng.randf_range(-0.4, 0.4) * step
			var py := y + rng.randf_range(-0.4, 0.4) * step
			y += step
			var skip := false
			for r in excl:
				if px > r[0] and px < r[2] and py > r[1] and py < r[3]:
					skip = true; break
			if skip:
				continue
			var q := PhysicsRayQueryParameters3D.create(Vector3(px, 40, -py), Vector3(px, -5, -py))
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit["position"].y > 0.25 or hit["normal"].y < 0.85:
				continue
			var key := Vector2i(int(floor(px / 16.0)), int(floor(py / 16.0)))
			if not chunks.has(key):
				chunks[key] = []
			var tr := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.35)), hit["position"])
			chunks[key].append(tr)
		x += step
	var n := 0
	for key in chunks:
		var arr: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = am
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 48.0
		add_child(mmi)
		n += arr.size()
	print("GRASS ", n)

func _process(delta: float) -> void:
	_dyn_res(delta)
	_spec_tick(delta)
	if world_env and world_env.environment:  # live brightness slider
		world_env.environment.tonemap_exposure = env_exp * float(GS.settings.get("brightness", 1.0))
	if test_follow.size() == 2 and is_instance_valid(test_follow[1]):
		var b: Node3D = test_follow[1]
		var cam3: Camera3D = test_follow[0]
		var side := b.global_transform.basis.x
		cam3.global_position = b.global_position + side * 4.5 + Vector3.UP * 1.4
		cam3.look_at(b.global_position + Vector3.UP * 1.0)
	if loading and is_instance_valid(loading) and loading.visible and loading.modulate.a > 0.99:
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
		match_time += delta
		if sab:
			return   # round timer and bomb timer are run by sabotage.gd
		time_left -= delta
		if time_left <= 0:
			time_left = 0
			end_match()

func _input(e: InputEvent) -> void:
	if spectating and e is InputEventMouseButton and e.pressed and not paused:
		if e.button_index == MOUSE_BUTTON_LEFT: spec_next(1)
		elif e.button_index == MOUSE_BUTTON_RIGHT: spec_next(-1)
	if spectating and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
		spec_next(1)
	# text chat (Enter / T = everyone, Y = team) and push-to-talk voice (V basılı tut, online)
	# handled in _input (before any UI / player code) so nothing can swallow the keys
	if hud == null or hud.typing or paused or ended:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var enter: bool = e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER
		if enter or e.is_action_pressed("chat") or e.is_action_pressed("team_chat"):
			if sab and sab.has_method("is_typing") and sab.is_typing():
				return
			hud.open_chat(e.is_action_pressed("team_chat") and not enter)
			get_viewport().set_input_as_handled()
			return
	if e is InputEventKey and not e.echo and e.is_action("voice"):
		if not net:
			if e.is_pressed():
				hud.voice_notice("Sesli sohbet sadece ÇEVRİMİÇİ odalarda çalışır (bot maçında konuşacak kimse yok).")
			return
		Voice.enabled = bool(GS.settings.get("voice_on", true))
		if e.is_pressed() and not Voice.enabled:
			hud.voice_notice("Sesli sohbet kapalı — Ayarlar > Ses bölümünden açabilirsin.")
			return
		Voice.set_talking(e.is_pressed())
		if e.is_pressed() and not Voice.talking:
			hud.voice_notice("Mikrofon bulunamadı veya izin yok — Windows Ayarlar > Gizlilik > Mikrofon'dan izin ver.")

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
var smokes: Array = []

func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = exclude
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	for sm in smokes:
		if is_instance_valid(sm) and sm.blocks(a, b):
			return false
	return true

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

func throw_grenade(thrower, pos: Vector3, vel: Vector3, smoke: bool = false) -> void:
	var g := preload("res://scripts/grenade.gd").new()
	g.match_node = self
	g.thrower = thrower
	g.is_smoke = smoke
	add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	if net and thrower == player and not smoke:
		net.send_nade(pos, vel)

## CS2-style volumetric smoke: a FogVolume raymarched by the engine's volumetric fog (Forward+), so it fills the
## space, is lit by the sun and blocks sight properly; a particle cloud stands in on low / no-volumetric settings.
func spawn_smoke(pos: Vector3, thrower) -> void:
	if net and thrower == player:
		net.send_smoke(pos)
	SFX.play3d("smoke_pop", pos, 2, 1.0, 120.0, 10.0)
	var sm := preload("res://scripts/smoke.gd").new()
	sm.match_node = self
	add_child(sm)
	sm.global_position = pos

func explode(pos: Vector3, thrower, visual_only: bool = false) -> void:
	fx.explosion(pos)
	SFX.play3d("explosion", pos, 6, 1.0, 200.0, 20.0)
	var pd: float = player.global_position.distance_to(pos)
	player.shake = max(player.shake, clamp(1.6 - pd / 15.0, 0.0, 1.6))
	if visual_only:
		return
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
	if OS.has_environment("PERF"): print("EV death t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	var __t := Time.get_ticks_usec()
	if attacker != null and is_instance_valid(attacker) and attacker != victim and "wolf_ctl" in attacker and attacker.wolf_ctl:
		attacker.wolf_ctl.on_kill()
	_sp_on_death(victim, attacker, wid, head)
	var __d := Time.get_ticks_usec() - __t
	if __d > 3000: print("SPIKE match.gd.on_death ", __d / 1000.0, "ms")

func _sp_on_death(victim, attacker, wid: String, head: bool) -> void:
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
		if teams and sab == null:
			team_score[ae["team"]] += 1
	elif teams:
		pass
	var klvl := 0
	if attacker == player:
		klvl = GS.wlvl(wid)
	elif attacker != null and is_instance_valid(attacker) and "net_wlvl" in attacker and attacker.get("puppet") == true:
		klvl = int(attacker.net_wlvl)
	hud.kill_feed(ae.get("name", ve["name"]), ve["name"], wid, head, ae.get("team", ""), ve["team"], attacker == player, victim == player, klvl)
	if attacker == player and victim != player:
		_player_kill(head, wid)
	if victim == player:
		player_streak = 0
		var dinfo := {"team": str(ae.get("team", "")), "lvl": int(ae.get("lvl", 1)), "wlvl": klvl, "self": attacker == null or attacker == player}
		if attacker != null and is_instance_valid(attacker) and attacker != player:
			var lg: Array = player.dmg_log.get(attacker.get_instance_id(), [0.0, 0, 0])
			dinfo["dmg"] = lg[0]; dinfo["hits"] = lg[1]; dinfo["heads"] = lg[2]
			dinfo["dist"] = attacker.global_position.distance_to(player.global_position)
			dinfo["my_dmg"] = float(attacker.get("dmg_from_player")) if "dmg_from_player" in attacker else 0.0
			if not bool(attacker.get("puppet")):
				dinfo["hp"] = maxf(float(attacker.health), 0.0)
				var ag = attacker.get("gun")
				if ag and is_instance_valid(ag):
					dinfo["skin"] = str((ag as Node).get_meta("skin", "std"))
			else:
				if float(attacker.get("net_hp")) >= 0.0:
					dinfo["hp"] = float(attacker.get("net_hp"))
				dinfo["skin"] = str(attacker.get("net_skin"))
				dinfo["parts"] = attacker.get("net_parts")
		hud.show_death(ae.get("name", "Kendini"), wid, head, dinfo)
		if attacker != null and is_instance_valid(attacker) and attacker != player:
			_killcam(attacker)
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
	if sab:
		sab.on_death(victim)   # rounds: no respawn until the next round
		if victim == player:
			get_tree().create_timer(2.8).timeout.connect(func(): if not player.alive and not ended: start_spectate())
		elif spectating and spec_target == victim:
			get_tree().create_timer(1.2).timeout.connect(func(): if spectating: spec_next(1))
		return
	# respawn timer
	get_tree().create_timer(3.5 if victim == player else 3.0).timeout.connect(func(): if not ended: _spawn(ve, false))
	_check_win()

func _player_kill(head: bool, wid: String) -> void:
	# kills / headshots are reported once at match end (economy rules count them, see econ.gd)
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

# ---------------------------------------------------------------- spectate teammates (sabotage: dead until next round)
var spectating := false
var spec_cam: Camera3D
var spec_target = null
var spec_idx := 0

func _spec_mates() -> Array:
	var out: Array = []
	for c in combatants:
		var n = c["node"]
		if n != player and is_instance_valid(n) and n.alive and (not teams or c["team"] == player.team):
			out.append(n)
	return out

func start_spectate() -> void:
	var mates := _spec_mates()
	if mates.is_empty():
		return
	if killcam and is_instance_valid(killcam):
		killcam.queue_free()
	killcam = null
	if spec_cam == null or not is_instance_valid(spec_cam):
		spec_cam = Camera3D.new()
		spec_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		spec_cam.fov = 70
		add_child(spec_cam)
	spectating = true
	spec_idx = 0
	spec_target = mates[0]
	spec_cam.global_transform = player.cam.global_transform
	spec_cam.current = true
	player.vm_rect.visible = false
	hud.show_spectate(true)

func stop_spectate() -> void:
	if not spectating:
		return
	spectating = false
	spec_target = null
	if spec_cam and is_instance_valid(spec_cam):
		spec_cam.queue_free()
	spec_cam = null
	if hud:
		hud.show_spectate(false)

func spec_next(d: int) -> void:
	var mates := _spec_mates()
	if mates.is_empty():
		stop_spectate()
		if player: player.cam.current = true
		return
	spec_idx = (mates.find(spec_target) + d + mates.size()) % mates.size() if mates.has(spec_target) else 0
	spec_target = mates[spec_idx]
	SFX.play("ui_click", -8)

func _spec_facing(n) -> float:
	if "puppet" in n and n.puppet:
		return float(n.net_yaw)
	if "aim_yaw" in n:
		return float(n.aim_yaw)
	return n.global_rotation.y

func _spec_tick(delta: float) -> void:
	if not spectating or spec_cam == null or not is_instance_valid(spec_cam):
		return
	if spec_target == null or not is_instance_valid(spec_target) or not spec_target.alive:
		spec_next(1)
		if not spectating:
			return
	var n = spec_target
	var yw := _spec_facing(n)
	var bz := Basis(Vector3.UP, yw)
	var headp: Vector3 = n.global_position + Vector3.UP * 1.62
	var back: Vector3 = bz.z
	var right: Vector3 = bz.x
	var want: Vector3 = headp + back * 2.3 + right * 0.55 + Vector3.UP * 0.25
	# keep the camera out of walls
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(headp, want, 1))
	if hit:
		want = headp + (hit["position"] - headp) * 0.85
	spec_cam.global_position = spec_cam.global_position.lerp(want, minf(1.0, delta * 10.0))
	var look: Vector3 = headp - back * 8.0
	spec_cam.look_at(look, Vector3.UP)

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
	stop_spectate()
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
	if OS.has_environment("PERF") and not initial: print("EV spawn t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	var __t := Time.get_ticks_usec()
	_sp__spawn(e, initial)
	var __d := Time.get_ticks_usec() - __t
	if __d > 3000: print("SPIKE match.gd._spawn ", __d / 1000.0, "ms")

func _sp__spawn(e: Dictionary, initial: bool) -> void:
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
		# bots mostly keep their weapon when they respawn (fewer model swaps = no respawn hitch)
		var keep: bool = mode != "gungame" and "wid" in n and n.wid != "" and randf() < 0.75
		n.respawn(pos, best["yaw"], n.wid if keep else _bot_weapon(int(e["gg"])))

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
	var summary := {"mode": mode, "kills": int(pe["kills"]), "head": int(pe["head"]), "deaths": int(pe["deaths"]), "won": won, "place": place,
		"shots": int(player.shots_fired) if player else 0, "hits": int(player.shots_hit) if player else 0, "online": net != null,
		"ranked": net != null and bool(cfg.get("ranked", false))}
	var rr: Dictionary = await GS.act("match_end", summary)
	var rw: Dictionary = rr.get("res", {})
	var xp: int = int(rw.get("xp", 0))
	var gold: int = int(rw.get("gold", 0))
	var mats: Dictionary = rw.get("mats", {"demir": 0, "krom": 0, "titanyum": 0, "kobalt": 0})
	var ups: int = int(rw.get("ups", 0))
	if not rr["ok"] and hud:
		hud.center_msg("Ödüller kaydedilemedi: " + str(rr["err"]), UI.RED)
	SFX.play("success" if won else "fail")
	SFX.play_music("music_win" if won else "music_lose", -3, false)
	if hud and bool(GS.settings.get("announcer", true)): hud._announce("ann_win" if won else "ann_lose")
	hud.show_end({"won": won, "place": place, "xp": xp, "gold": gold, "mats": mats, "ups": ups, "sorted": sorted, "pe": pe,
		"rp": int(rw.get("rp", GS.profile.get("rp", 0))), "rp_old": int(rw.get("rp_old", GS.profile.get("rp", 0))), "ranked": bool(summary["ranked"])})

func leave() -> void:
	Voice.clear()
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
	if i == 28 or i == 29:
		for c in combatants:
			if c["node"] != player:
				c["node"].set_physics_process(false)
		if not GS.profile.has("wparts"): GS.profile["wparts"] = {}
		GS.profile["wparts"][player.cur] = [OS.get_environment("TPART") if OS.has_environment("TPART") else "optik"]
		player.switch_to(player.cur, true)
		player.test_ads = i == 29
		return
	if i == 27:
		for c in combatants:
			if c["node"] != player:
				c["node"].set_physics_process(false)
		return
	if i == 24 and sab:
		# stand on site A with the bomb and start planting
		sab.carrier = player
		player.global_position = sab.sites[0]["pos"]
		player.reset_physics_interpolation()
		sab.prog_who = player; sab.prog_kind = "plant"; sab.progress = 1.7
		sab.set_process(false)
		return
	if i == 26 and sab:
		sab.set_process(true)
		sab.planted = true; sab.phase = "planted"; sab.bomb_pos = sab.sites[0]["pos"]; sab.planted_site = "A"; sab.banner_t = 2.0
		sab.prog_kind = ""; sab.prog_who = null
		sab._place_bomb(sab.bomb_pos, true)
		player.global_position = sab.sites[0]["pos"] + Vector3(8, 0, 8)
		player.reset_physics_interpolation()
		player.yaw = atan2(8, 8)
		return
	if i == 25:
		player.alive = false
		player.vm_rect.visible = false
		start_spectate()
		return
	if i == 23:
		hud.force_board = true
		return
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
	elif i == 90:
		# kurt mode: transform the player (and let bots charge instantly)
		if player.wolf_ctl:
			player.wolf_ctl.energy = 100.0
			player.wolf_ctl.transform()
		for c in combatants:
			if OS.has_environment("WOLFPONLY"): break
			if not c["is_player"] and c["node"].wolf_ctl:
				c["node"].wolf_ctl.energy = 100.0
				c["node"].wolf_ctl._auto_t = 99.0
	elif i == 12:
		# free camera: CAM="x,y,z,tx,ty,tz" (Godot coordinates); CAMS="a;b;c" = one per shot
		var cs: String = OS.get_environment("CAM")
		if OS.get_environment("CAMS") != "":
			var lst := OS.get_environment("CAMS").split(";")
			cs = lst[mini(_cams_i, lst.size() - 1)]
			_cams_i += 1
			for ch in get_children():
				if ch is Camera3D and ch.name.begins_with("TestCam"):
					ch.queue_free()
		var v: PackedFloat64Array = cs.split_floats(",")
		var c := Camera3D.new()
		c.name = "TestCam"
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(c)
		c.global_position = Vector3(v[0], v[1], v[2])
		c.look_at(Vector3(v[3], v[4], v[5]))
		c.far = 3000
		c.fov = float(OS.get_environment("FOV")) if OS.has_environment("FOV") else 70.0
		c.current = true
		if player: player.vm_rect.visible = false
		if OS.has_environment("NOHUD") and hud: hud.visible = false
	elif i == 19:
		# scoped sniper view at the nearest bot: player gets an AWP and aims
		var b = null
		var bd := 1e9
		for e in combatants:
			if not e["is_player"]:
				var dd: float = e["node"].global_position.distance_to(player.global_position)
				if dd < bd:
					bd = dd; b = e["node"]
		player.switch_to("awp", true)
		if b:
			b.set_physics_process(false)
			var tgt: Vector3 = b.global_position + Vector3.UP * 1.5
			var dir: Vector3 = (tgt - player.cam.global_position).normalized()
			player.rotation.y = atan2(-dir.x, -dir.z)
			player.pitch = asin(dir.y)
		player.test_ads = true
	elif i == 20 or i == 21:
		# weapon showcase: WIDS="ak47,awp,..." each call equips the next one (21 = aim down sights)
		var lst: PackedStringArray = OS.get_environment("WIDS").split(",")
		var k: int = int(get_meta("wid_i", 0))
		set_meta("wid_i", k + 1)
		var wid: String = lst[k % lst.size()]
		if not GS.profile["owned"].has(wid):
			GS.profile["owned"][wid] = {"lvl": 0, "skins": ["std"], "skin": "std"}
		if OS.has_environment("WLV"):
			GS.profile["owned"][wid]["lvl"] = int(OS.get_environment("WLV"))
		if OS.has_environment("WSKIN"):
			var sks: PackedStringArray = OS.get_environment("WSKIN").split(",")
			GS.profile["owned"][wid]["skin"] = sks[k % sks.size()]
		player.test_ads = i == 21
		player.slots[GS.WEAPONS[wid]["cat"]] = wid
		player.ammo[wid] = [int(GS.WEAPONS[wid].get("mag", 1)), 99]
		player.cur = ""
		player.switch_to(wid, true)
	elif i == 40 or i == 41 or i == 42:
		# 40 slash / 41 stab / 42 inspect, frozen at env FR (0..1)
		var frs: PackedStringArray = (OS.get_environment("FR") if OS.has_environment("FR") else "0.4").split(",")
		var fk: int = int(get_meta("fr_i", 0))
		set_meta("fr_i", fk + 1)
		var fr := float(frs[fk % frs.size()])
		player.test_freeze = -1.0
		player.inspect_t = 0.0
		if i == 42:
			player.inspect_t = 3.2
			player._fp_play("inspect", 0.0)
			player.test_freeze_kind = "insp"
		else:
			player._melee(i == 41)
			player.test_freeze_kind = "melee"
		player.test_freeze = fr
	elif i >= 65 and i <= 79:
		var lst := ["m4a1", "awm", "uzi", "akm", "rpk16", "vityaz", "spas", "deagle", "usp", "karambit", "m4k", "kuzgun", "mp5", "ump45", "scar"]
		var w2: String = lst[i - 65]
		if OS.has_environment("TESTW"): w2 = OS.get_environment("TESTW")
		var c3: String = GS.WEAPONS[w2]["cat"]
		player.slots[c3] = w2
		player.ammo[w2] = [10, 90]
		player.switch_to("frag" if player.cur != "frag" else player.slots["bicak"])
		await get_tree().create_timer(0.5).timeout
		player.switch_to(w2)
		await get_tree().create_timer(1.0).timeout
		print("SWITCH ", w2, " cur=", player.cur, " fp=", player.fp_root.name if player.fp_root and is_instance_valid(player.fp_root) else "-")
	elif i >= 60 and i <= 64:
		# real (non-instant) weapon switching, like the keys do
		var c2: String = ["tabanca", "bicak", "ana", "bomba", "ana"][i - 60]
		print("SWITCH before cur=", player.cur, " slots=", player.slots)
		if player.slots.has(c2):
			player.switch_to(player.slots[c2])
		await get_tree().create_timer(0.08).timeout
		if i == 64:
			for r in 12:
				player._cycle(1 if r % 3 else -1)
				await get_tree().create_timer(randf_range(0.02, 0.2)).timeout
		await get_tree().create_timer(1.2).timeout
		print("SWITCH after cur=", player.cur, " vm=", player.vm_weapon.name if player.vm_weapon else "-", " fp=", player.fp_root.name if player.fp_root and is_instance_valid(player.fp_root) else "-", " vmvis=", player.vm_weapon.visible if player.vm_weapon else false)
	elif i == 52:
		print("NADE before g=", player.grenades, " s=", player.smokes, " cur=", player.cur)
		player.switch_to("smoke", true)
		print("NADE switched cur=", player.cur)
		player._start_throw()
		await get_tree().create_timer(0.3).timeout
		await get_tree().create_timer(2.5).timeout
		print("NADE after g=", player.grenades, " s=", player.smokes, " cur=", player.cur, " smokes_in_world=", smokes.size())
	elif i == 51:
		var fwd: Vector3 = -player.cam.global_transform.basis.z
		fwd.y = 0.0
		spawn_smoke(player.global_position + fwd.normalized() * float(OS.get_environment("SMK_D") if OS.get_environment("SMK_D") != "" else "9"), player)
		var sm = smokes.back()
		if OS.get_environment("SMK_T") != "":
			sm.t = float(OS.get_environment("SMK_T"))
	elif i == 46:
		hud.toggle_buy(true)
	elif i == 47:
		hud.toggle_buy(false)
		hud.show_pause(true)
	elif i == 45:
		# death card check
		hud.show_death("GeceKurdu", "m4a1", true, {"team": "b", "lvl": 37, "wlvl": 5, "self": false, "dmg": 100, "hits": 3, "heads": 1, "my_dmg": 64, "dist": 23.4, "hp": 36.0, "skin": "ejderha", "parts": ["sus", "optik", "sarjor"]})
	elif i == 22:
		# HUD check: kill feed with weapon icons + inspect card + inspect pose
		hud.kill_feed("Oyuncu", "Kartal07", "ak47", true, "a", "b", true, false, GS.wlvl("ak47"))
		hud.kill_feed("Tilki", "Bora", "m4a1", false, "b", "a", false, false, 4)
		hud.kill_feed("Kurt", "Bora", "awp", false, "b", "a", false, false, 7)
		hud.kill_feed("Efsane06", "Oyuncu", "r870", false, "b", "a", false, true)
		hud.kill_feed("Çelik", "GeceKurdu", "knife", false, "a", "b", false, false)
		hud.kill_confirm(true, "", 1, player.cur, 3)
		player.inspect_t = 3.2 * (1.0 - float(OS.get_environment("INSP_T")) if OS.has_environment("INSP_T") else 0.6)
		hud.inspect_card(player.cur)
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
			player.test_ads = true
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

# ---------------------------------------------------------------- v3.4 tactical ping
var _ping_cd := 0.0
var _pings: Array = []
func place_ping(pos: Vector3, who: String, tm: String, mine: bool) -> void:
	if mine:
		if Time.get_ticks_msec() / 1000.0 < _ping_cd:
			return
		_ping_cd = Time.get_ticks_msec() / 1000.0 + 0.8
		if net != null:
			Net.send({"t": "ping", "p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "team": tm if teams else "", "n": who})
	while _pings.size() >= 4:
		var old = _pings.pop_front()
		if is_instance_valid(old): old.queue_free()
	var col: Color = GS.TEAM_COLORS.get(tm, UI.ACCENT) if teams else UI.ACCENT
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	_pings.append(root)
	var lb := Label3D.new()
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0011
	lb.font = UI.font("RussoOne-Regular")
	lb.font_size = 26
	lb.outline_size = 8
	lb.modulate = col.lightened(0.2)
	lb.outline_modulate = Color(0, 0, 0, 0.8)
	lb.position = Vector3(0, 0.35, 0)
	lb.render_priority = 10
	root.add_child(lb)
	var dot := Label3D.new()
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.no_depth_test = true
	dot.fixed_size = true
	dot.pixel_size = 0.0016
	dot.font_size = 40
	dot.text = "◆"
	dot.modulate = col
	dot.outline_size = 10
	dot.outline_modulate = Color(0, 0, 0, 0.7)
	dot.render_priority = 10
	root.add_child(dot)
	var ring := MeshInstance3D.new()
	var tm2 := TorusMesh.new(); tm2.inner_radius = 0.45; tm2.outer_radius = 0.55; tm2.rings = 24; tm2.ring_segments = 6
	ring.mesh = tm2
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(col.r, col.g, col.b, 0.8)
	rm.no_depth_test = true
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	SFX.play("tick", -2, 1.6)
	if hud:
		if hud.has_method("chat_line"): hud.chat_line("◆ " + who, "burayı işaretledi", true, col)
	var life := 4.0
	var t0 := Time.get_ticks_msec() / 1000.0
	while is_instance_valid(root):
		var age := Time.get_ticks_msec() / 1000.0 - t0
		if age > life:
			break
		var k := clampf(age * 4.0, 0.0, 1.0)
		ring.scale = Vector3.ONE * (0.3 + 1.2 * fmod(age, 1.0))
		rm.albedo_color.a = 0.8 * (1.0 - fmod(age, 1.0))
		dot.position.y = 0.12 + 0.05 * sin(age * 6.0)
		var fade := 1.0 - smoothstep(life - 0.6, life, age)
		dot.modulate.a = k * fade
		lb.modulate.a = k * fade
		if player and is_instance_valid(player):
			lb.text = "%s  •  %dm" % [who.to_upper(), int(player.global_position.distance_to(pos))]
		await get_tree().process_frame
	if is_instance_valid(root):
		_pings.erase(root)
		root.queue_free()

## v3.4 imported (Sketchfab) maps: their exporter marks everything fully metallic and some packs keep the
## colour in the emissive slot (baked / unlit atlases) -> plain lit dielectric surfaces, cut-out alpha
func _fix_imported_mats(vis: Node) -> void:
	var done := {}
	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for si in m3.mesh.get_surface_count():
			var mt = m3.get_active_material(si)
			if not (mt is StandardMaterial3D) or done.has(mt):
				continue
			done[mt] = true
			var sm := mt as StandardMaterial3D
			sm.metallic = 0.0
			sm.metallic_specular = 0.35
			sm.roughness = maxf(sm.roughness, 0.82)
			if sm.albedo_texture == null and sm.emission_enabled and sm.emission_texture:
				sm.albedo_texture = sm.emission_texture
				sm.albedo_color = Color.WHITE
				sm.emission_enabled = false
			elif sm.emission_enabled and sm.emission_texture == null:
				sm.emission_enabled = false
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
