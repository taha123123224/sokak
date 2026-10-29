extends Node

var UPGRADE_GLOW := _make_glow_shader()

static func _make_glow_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float sweep = -1.0;
uniform vec4 glow_col : source_color = vec4(1.0, 0.7, 0.25, 1.0);
uniform float glow = 0.0;
uniform float outline = 0.0;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float a = t.a;
	float m = 0.0;
	for (int r = 1; r <= 3; r++) {
		float rad = float(r) * 4.0;
		for (int k = 0; k < 8; k++) {
			float ang = float(k) * 0.785398;
			m = max(m, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * rad).a * (1.0 - float(r - 1) * 0.28));
		}
	}
	float edge = clamp(m - a, 0.0, 1.0);
	float d = (UV.x + (1.0 - UV.y) * 0.35) - sweep;
	// narrow light sweep + soft bloom that brightens the skin instead of painting over it
	float band = (1.0 - smoothstep(0.0, 0.035, abs(d))) * 0.85 + (1.0 - smoothstep(0.0, 0.012, abs(d - 0.05))) * 0.45;
	float lum = dot(t.rgb, vec3(0.3, 0.55, 0.15));
	vec3 col = t.rgb * (1.0 + glow * 0.12) + glow_col.rgb * (band * (0.35 + lum * 0.65) + glow * 0.1 * lum) * a;
	col = mix(col, glow_col.rgb * 1.4, edge * outline * 0.75);
	COLOR = vec4(col, max(a, edge * outline * 0.85) * COLOR.a);
}
"""
	return sh
## Main menu: 3D showcase + lobby, bag, upgrade, market, crate, rooms, room lobby, profile, settings.

var main
var start_page := "lobby"
var page := ""
var ui: Control
var content: Control
var topbar: HBoxContainer
var cur_box: HBoxContainer
var nav_btns := {}
var modal: Control
# 3D showcase
var world: Node3D
var cam: Camera3D
var show_weapon: Node3D
var show_pivot: Node3D
var soldier: Node3D
var spin_speed := 0.5
var cam_target := Vector3(0.5, 1.5, 4.6)
var cam_look := Vector3(0.6, 1.1, 0)
var rim: SpotLight3D
var studio: MeshInstance3D
# thumbnails
var thumb_vp: SubViewport
var thumb_cam: Camera3D
var thumb_holder: Node3D
var thumb_cache := {}
var thumb_queue: Array = []
var thumb_busy := false
# state
var bag_cat := "tum"
var bag_sel := ""
var market_tab := "silah"
var room_cfg := {}
var room_chat: VBoxContainer
var room_players: Array = []
var room_countdown := -1.0

var online

func _exit_tree() -> void:
	if online:
		online.cleanup()

func _ready() -> void:
	online = preload("res://scripts/menu_online.gd").new(self)
	_build_world()
	var cl := CanvasLayer.new()
	add_child(cl)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = main.theme
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ui)
	# gradient overlays for readability
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.015, 0.025, 0.92)); g.set_color(1, Color(0.01, 0.015, 0.025, 0.0))
	g.add_point(0.35, Color(0.01, 0.015, 0.025, 0.55))
	gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)
	_build_topbar()
	content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 96
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(content)
	GS.profile_changed.connect(_refresh_currency)
	SFX.play_music("music_menu")
	show_page(start_page)

# ================================================================ 3D showcase
func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	# golden-hour sky over Safranbolu: the lobby stands on a real terrace of the map
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2f6fc8")
	sm.sky_horizon_color = Color("f4c08c")
	sm.ground_horizon_color = Color("f4c08c")
	sm.ground_bottom_color = Color(0.3, 0.27, 0.24)
	sm.sun_angle_max = 28
	sm.sky_energy_multiplier = 1.2
	if ResourceLoader.exists("res://assets/tex/clouds.png"):
		sm.sky_cover = load("res://assets/tex/clouds.png")
		sm.sky_cover_modulate = Color(1, 0.92, 0.85, 0.9)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.4
	e.ambient_light_color = Color(0.78, 0.72, 0.68)
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.6; e.glow_bloom = 0.05; e.glow_hdr_threshold = 1.1
	e.ssr_enabled = bool(GS.settings["ssr"])
	e.ssao_enabled = true
	e.ssao_intensity = 1.2
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18
	e.adjustment_contrast = 1.05
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_depth_begin = 40.0
	e.fog_depth_end = 220.0
	e.fog_light_color = Color("f0cfa8")
	e.fog_density = 0.5
	e.volumetric_fog_enabled = bool(GS.settings["volumetric"])
	e.volumetric_fog_density = 0.006
	e.volumetric_fog_albedo = Color(1.0, 0.9, 0.8)
	e.volumetric_fog_anisotropy = 0.75
	we.environment = e
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 150, 0)
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.light_angular_distance = 0.6
	world.add_child(sun)
	var backdrop_path := "res://assets/maps/safranbolu.glb"
	if ResourceLoader.exists(backdrop_path):
		var bd: Node3D = (load(backdrop_path) as PackedScene).instantiate()
		MatLib.apply(bd)
		bd.position = Vector3(-10.0, -0.02, -18.0)
		world.add_child(bd)
	else:
		var floor_mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
		floor_mi.mesh = pm
		floor_mi.material_override = MatLib.get_mat("cobble")
		world.add_child(floor_mi)
	# lights
	var key := SpotLight3D.new()
	key.position = Vector3(2.5, 5.5, 3.5)
	key.look_at_from_position(key.position, Vector3(0.5, 1, 0))
	key.light_energy = 6; key.spot_range = 14; key.spot_angle = 30
	key.light_color = Color(1, 0.95, 0.88)
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 1.5
	world.add_child(key)
	rim = SpotLight3D.new()
	rim.position = Vector3(-3, 3.5, -2.5)
	rim.look_at_from_position(rim.position, Vector3(0, 1.2, 0))
	rim.light_energy = 9; rim.spot_range = 12; rim.spot_angle = 35
	rim.light_color = UI.ACCENT
	rim.light_volumetric_fog_energy = 2.0
	world.add_child(rim)
	var rim2 := SpotLight3D.new()
	rim2.position = Vector3(4, 3, -2)
	rim2.look_at_from_position(rim2.position, Vector3(1.5, 1.2, 0))
	rim2.light_energy = 6; rim2.spot_range = 12; rim2.spot_angle = 35
	rim2.light_color = Color(0.3, 0.55, 1.0)
	world.add_child(rim2)
	# soldier
	var sps: PackedScene = GS.char_scene(GS.cur_char())
	soldier = sps.instantiate()
	MatLib.apply(soldier)
	soldier.position = Vector3(-0.5, 0, 0)
	soldier.rotation.y = deg_to_rad(18)
	world.add_child(soldier)
	var ap := soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("Idle"):
		ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
	# weapon pedestal
	var ped := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.42; cm.bottom_radius = 0.46; cm.height = 0.85
	ped.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.12, 0.13, 0.15); pmat.metallic = 0.85; pmat.roughness = 0.25
	ped.material_override = pmat
	ped.position = Vector3(1.6, 0.425, -0.4)
	world.add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.41; tm.outer_radius = 0.44
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.emission_enabled = true; rmat.emission = UI.ACCENT; rmat.emission_energy_multiplier = 4.0; rmat.albedo_color = Color.BLACK
	ring.material_override = rmat
	ring.position = Vector3(1.6, 0.86, -0.4)
	world.add_child(ring)
	show_pivot = Node3D.new()
	show_pivot.position = Vector3(1.6, 1.3, -0.4)
	world.add_child(show_pivot)
	# weapon studio: dark gradient backdrop with an accent glow, hides the map behind the showcase
	studio = MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(9.0, 5.5)
	studio.mesh = qm
	var stm := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 acc = vec3(1.0, 0.55, 0.12);
void fragment() {
	vec2 p = UV - vec2(0.5, 0.52);
	float r = length(p * vec2(1.0, 1.5));
	vec3 base = mix(vec3(0.09, 0.1, 0.13), vec3(0.015, 0.018, 0.025), smoothstep(0.0, 0.62, r));
	base += acc * 0.10 * exp(-r * r * 9.0);
	float grid = step(0.985, fract(UV.x * 36.0)) + step(0.985, fract(UV.y * 22.0));
	base += vec3(0.02) * grid * (1.0 - smoothstep(0.1, 0.5, r));
	ALBEDO = base;
}"""
	stm.shader = ssh
	stm.set_shader_parameter("acc", Vector3(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b))
	studio.material_override = stm
	studio.position = Vector3(1.6, 1.4, -2.2)
	studio.visible = false
	world.add_child(studio)
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 40
	cam.position = cam_target
	world.add_child(cam)
	cam.look_at(cam_look)
	cam.current = true

# ================================================================ INSPECT (full-screen weapon view)
var inspecting := false
var insp_rot := Vector2.ZERO
var insp_zoom := 1.0
var insp_ui: Control
var insp_drag := false

func _inspect(id: String) -> void:
	inspecting = true
	if studio: studio.visible = true
	insp_rot = Vector2(show_pivot.rotation.y, 0.0)
	insp_zoom = 1.0
	content.visible = false
	set_showcase(id)
	insp_ui = Control.new()
	insp_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	insp_ui.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.add_child(insp_ui)
	var w: Dictionary = GS.full_stats(id)
	var lvl := GS.wlvl(id)
	var info := UI.panel(Color(0.02, 0.03, 0.05, 0.78), UI.ACCENT.darkened(0.3), 18)
	info.position = Vector2(40, 130)
	info.custom_minimum_size = Vector2(430, 0)
	insp_ui.add_child(info)
	var v := UI.vbox(6)
	info.add_child(v)
	v.add_child(UI.lbl(str(w["name"]) + (" [+%d]" % lvl if lvl > 0 else ""), 38, Color.WHITE, "RussoOne-Regular"))
	v.add_child(UI.lbl(str(w["cls"]).to_upper() + "   •   " + GS.SKINS.get(GS.wskin(id), {}).get("name", "Standart"), 18, UI.ACCENT2, "Rajdhani-Bold"))
	if w.has("ability"):
		v.add_child(_wrap("★ " + str(w["ability"]), 17))
	if not w.get("melee", false) and not w.get("throwable", false):
		for row in _stat_rows(id):
			v.add_child(_stat(row[0], row[1], row[2]))
		var ps: Array = GS.wparts(id)
		var names: Array = []
		for p in ps:
			names.append(GS.PARTS[p]["name"])
		v.add_child(UI.lbl("Eklentiler: " + (", ".join(names) if names.size() > 0 else "yok"), 16, UI.DIM, "Rajdhani-SemiBold"))
	var hint := UI.lbl("SÜRÜKLE: döndür   •   TEKERLEK: yakınlaş   •   ESC: kapat", 18, Color(1, 1, 1, 0.7), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -70); hint.custom_minimum_size = Vector2(600, 0)
	insp_ui.add_child(hint)
	var close := UI.btn("✕  KAPAT", _end_inspect, 20, true, 160, 48)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-200, 120)
	insp_ui.add_child(close)
	SFX.play("equip", -6)

func _end_inspect() -> void:
	inspecting = false
	content.visible = true
	if insp_ui:
		insp_ui.queue_free(); insp_ui = null
	show_pivot.rotation = Vector3.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if not inspecting:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			insp_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			insp_zoom = clamp(insp_zoom - 0.08, 0.45, 1.6)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			insp_zoom = clamp(insp_zoom + 0.08, 0.45, 1.6)
	elif e is InputEventMouseMotion and insp_drag:
		insp_rot.x += (e as InputEventMouseMotion).relative.x * 0.01
		insp_rot.y = clamp(insp_rot.y + (e as InputEventMouseMotion).relative.y * 0.006, -0.8, 0.8)
	elif e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		_end_inspect()

func _stat_rows(id: String) -> Array:
	## [label, value, max] rows comparing weapons on the same scale
	var w: Dictionary = GS.full_stats(id)
	var pel := int(w.get("pellets", 1))
	var dps: float = float(w["dmg"]) * pel * float(w["rpm"]) / 60.0
	return [["Hasar", float(w["dmg"]) * pel, 150.0], ["Atış Hızı", float(w["rpm"]), 1200.0], ["Saniyede Hasar", dps, 620.0],
		["Menzil", float(w.get("f1", 60.0)) if float(w.get("f1", 60.0)) < 300 else 160.0, 160.0], ["Kontrol", (1.0 - float(w["recoil"]) / 0.09) * 100.0, 100.0],
		["İsabet", (1.0 - float(w["spread"]) / 0.1) * 100.0, 100.0], ["Zırh Delme", float(w.get("ap", 0.2)) * 100.0, 100.0],
		["Duvar Delme", float(w.get("pen", 0.0)) * 100.0 / 0.65, 100.0], ["Hareketlilik", float(w["speed"]) * 90.0, 100.0]]

func set_showcase(id: String, skin: String = "") -> void:
	if show_weapon:
		show_weapon.queue_free()
	var ps: PackedScene = GS.weapon_scene(id)
	show_weapon = ps.instantiate()
	MatLib.apply(show_weapon, skin if skin != "" else GS.wskin(id))
	var holder := Node3D.new()
	show_pivot.add_child(holder)
	holder.add_child(show_weapon)
	show_weapon = holder
	# center weapon around pivot
	var aabb: AABB = holder.global_transform.affine_inverse() * _aabb(holder)
	var w := holder.get_child(0) as Node3D
	w.position = -aabb.get_center()
	var s: float = 1.1 / max(aabb.size.length(), 0.2)
	holder.scale = Vector3.ONE * clamp(s * 1.25, 1.0, 5.0)
	GS.parts_visual(w, id)
	GS.level_glow(w, id)

func _aabb(n: Node) -> AABB:
	var res := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		if first: res = a; first = false
		else: res = res.merge(a)
	return res

func _process(delta: float) -> void:
	if inspecting:
		show_pivot.rotation.y = lerp_angle(show_pivot.rotation.y, insp_rot.x, min(delta * 10.0, 1.0))
		show_pivot.rotation.x = lerp(show_pivot.rotation.x, insp_rot.y, min(delta * 10.0, 1.0))
		var ct: Vector3 = show_pivot.global_position + Vector3(-0.18, 0.02, 1.05 * insp_zoom)
		cam.position = cam.position.lerp(ct, min(delta * 6.0, 1.0))
		cam.look_at(show_pivot.global_position + Vector3(-0.18, 0, 0))
		_process_thumbs()
		return
	if show_pivot:
		show_pivot.rotate_y(delta * spin_speed)
		show_pivot.rotation.x = lerp(show_pivot.rotation.x, 0.0, min(delta * 6.0, 1.0))
	var mp := get_viewport().get_mouse_position() / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5)
	cam.position = cam.position.lerp(cam_target + Vector3(mp.x * 0.25, -mp.y * 0.15, 0), min(delta * 3.0, 1.0))
	cam.look_at(cam_look)
	_process_thumbs()
	online.tick(delta)
	if room_countdown > 0:
		var prev := room_countdown
		room_countdown -= delta
		if int(prev) != int(room_countdown) and room_chat:
			if int(prev) >= 1:
				_chat("SİSTEM", "%d saniye sonra oyun başlayacak." % int(prev), Color("ffd24a"))
				SFX.play("beep", -6)
		if room_countdown <= 0:
			room_countdown = -1
			SFX.play("beep_go", -4)
			main.start_match(room_cfg)

# ================================================================ thumbnails
func _build_thumbs() -> void:
	thumb_vp = SubViewport.new()
	thumb_vp.own_world_3d = true
	thumb_vp.transparent_bg = true
	thumb_vp.size = Vector2i(512, 256)
	thumb_vp.msaa_3d = Viewport.MSAA_8X
	thumb_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(thumb_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	thumb_cam = Camera3D.new()
	thumb_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	thumb_cam.environment = env
	thumb_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	thumb_vp.add_child(thumb_cam)
	var l1 := DirectionalLight3D.new()
	l1.rotation_degrees = Vector3(-40, 50, 0)
	l1.light_energy = 2.2
	thumb_vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(-10, -130, 0)
	l2.light_energy = 1.2
	l2.light_color = Color(1, 0.7, 0.45)
	thumb_vp.add_child(l2)
	thumb_holder = Node3D.new()
	thumb_vp.add_child(thumb_holder)

func thumb(id: String, skin: String, rect: TextureRect) -> void:
	Thumbs.request(id, skin, rect)

func _process_thumbs() -> void:
	pass

func thumb_rect(id: String, skin: String, size: Vector2) -> TextureRect:
	return Thumbs.make_rect(id, skin, size)

# ================================================================ top bar
func _build_topbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.sb(Color(0.02, 0.025, 0.04, 0.94), Color(0, 0, 0, 0), 0, 0, 0))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 86)
	ui.add_child(bar)
	var line := TopGlow.new()
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.position.y = 85
	line.custom_minimum_size = Vector2(0, 4)
	line.size = Vector2(4000, 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(line)
	topbar = UI.hbox(4)
	topbar.alignment = BoxContainer.ALIGNMENT_BEGIN
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 22); m.add_theme_constant_override("margin_right", 18)
	bar.add_child(m)
	m.add_child(topbar)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo_bar.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(210, 70)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topbar.add_child(logo)
	topbar.add_child(UI.spacer(false, 14))
	for it in [["lobby", "LOBİ"], ["rooms", "ODALAR"], ["friends", "ARKADAŞLAR"], ["bag", "ÇANTA"], ["market", "MARKET"], ["crate", "KASA"], ["mods", "EKLENTİLER"], ["profile", "PROFİL"], ["settings", "AYARLAR"]]:
		var b := UI.btn(it[1], func(): show_page(it[0]), 18, false, 0, 86)
		for st in ["normal", "hover", "pressed"]:
			var sbx := UI.sb(Color(1, 1, 1, 0.05) if st == "hover" else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
			sbx.content_margin_left = 13; sbx.content_margin_right = 13
			b.add_theme_stylebox_override(st, sbx)
		nav_btns[it[0]] = b
		topbar.add_child(b)
	topbar.add_child(UI.spacer())
	cur_box = UI.hbox(8)
	cur_box.alignment = BoxContainer.ALIGNMENT_END
	topbar.add_child(cur_box)
	topbar.add_child(UI.spacer(false, 8))
	var q := UI.btn("⏻", func(): get_tree().quit(), 24, false, 48, 48)
	q.tooltip_text = "Oyundan çık"
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	topbar.add_child(q)
	_refresh_currency()

func _refresh_currency() -> void:
	if cur_box == null:
		return
	UI.clear(cur_box)
	var p := GS.profile
	# level badge with XP progress
	var lv := LevelBadge.new()
	lv.level = int(p["level"])
	lv.frac = clamp(float(p["xp"]) / max(float(GS.xp_for_level(int(p["level"]))), 1.0), 0.0, 1.0)
	lv.pname = str(p["name"])
	lv.custom_minimum_size = Vector2(190, 56)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.tooltip_text = "Seviye %d  •  %d / %d TP" % [int(p["level"]), int(p["xp"]), GS.xp_for_level(int(p["level"]))]
	cur_box.add_child(lv)
	cur_box.add_child(_cur("gold", UI.money(int(p["gold"])), UI.GOLD, "Altın"))
	for k in [["demir", Color("aab3bb")], ["krom", Color("d9ecff")], ["titanyum", Color("62c8ff")], ["kobalt", Color("5b7cff")]]:
		cur_box.add_child(_cur("gem", str(int(p["mats"].get(k[0], 0))), k[1], GS.MATS[k[0]] + " (silah geliştirme malzemesi)"))
	cur_box.add_child(_cur("crate", str(int(p.get("crates", 0))), Color("ff8a1f"), "Kasa"))

func _cur(kind: String, v: String, c: Color, tip: String = "Altın") -> Control:
	var chip := PanelContainer.new()
	var sbx := UI.sb(Color(0.07, 0.085, 0.11, 0.95), Color(c.r, c.g, c.b, 0.35), 1, 6, 0)
	sbx.content_margin_left = 6; sbx.content_margin_right = 10; sbx.content_margin_top = 3; sbx.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sbx)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(h)
	var ic := CurIcon.new()
	ic.kind = kind; ic.col = c
	ic.custom_minimum_size = Vector2(26, 26)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var l := UI.lbl(v, 20, Color.WHITE, "Rajdhani-Bold")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return chip

class CurIcon extends Control:
	## vector currency icons: gold coin, cut gems for upgrade materials, crate
	var kind := "gold"
	var col := Color.WHITE
	func _draw() -> void:
		var c := size * 0.5
		var r: float = min(size.x, size.y) * 0.46
		match kind:
			"gold":
				draw_circle(c, r, col.darkened(0.35))
				draw_circle(c, r * 0.86, col)
				draw_arc(c, r * 0.62, 0, TAU, 24, col.darkened(0.25), 2.0)
				draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.38), Vector2(r * 0.24, r * 0.76)), col.darkened(0.3))
				draw_circle(c + Vector2(-r * 0.4, -r * 0.42), r * 0.16, Color(1, 1, 1, 0.7))
			"gem":
				var top := [c + Vector2(-r * 0.55, -r * 0.55), c + Vector2(r * 0.55, -r * 0.55), c + Vector2(r, -r * 0.1), c + Vector2(0, r), c + Vector2(-r, -r * 0.1)]
				draw_colored_polygon(PackedVector2Array(top), col.darkened(0.15))
				draw_colored_polygon(PackedVector2Array([top[0], top[1], c + Vector2(r * 0.3, -r * 0.1), c + Vector2(-r * 0.3, -r * 0.1)]), col.lightened(0.35))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.1), c + Vector2(r * 0.3, -r * 0.1), top[3]]), col)
				draw_colored_polygon(PackedVector2Array([top[4], c + Vector2(-r * 0.3, -r * 0.1), top[3]]), col.darkened(0.35))
				draw_polyline(PackedVector2Array(top + [top[0]]), Color(1, 1, 1, 0.55), 1.2)
			"crate":
				var rc := Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6))
				draw_rect(rc, col.darkened(0.3))
				draw_rect(Rect2(rc.position, Vector2(rc.size.x, rc.size.y * 0.32)), col)
				draw_rect(Rect2(c.x - r * 0.18, rc.position.y, r * 0.36, rc.size.y), col.lightened(0.3))
				draw_rect(rc, Color(0, 0, 0, 0.6), false, 1.5)

class LevelBadge extends Control:
	## hexagonal level badge + player name + XP bar
	var level := 1
	var frac := 0.0
	var pname := ""
	func _draw() -> void:
		var h := size.y
		var c := Vector2(h * 0.5, h * 0.5)
		var r := h * 0.47
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * r)
		draw_colored_polygon(pts, Color(0.12, 0.08, 0.03))
		pts.append(pts[0])
		draw_polyline(pts, UI.ACCENT, 2.5)
		var inner := PackedVector2Array()
		for i in 7:
			inner.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * r * 0.78)
		draw_polyline(inner, Color(1, 0.7, 0.3, 0.3), 1.0)
		var f: Font = UI.font("Teko")
		var t := str(level)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.62)).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + h * 0.22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.62), UI.ACCENT2)
		var x0 := h + 8
		var fb: Font = UI.font("Rajdhani-Bold")
		draw_string(fb, Vector2(x0, h * 0.42), pname, HORIZONTAL_ALIGNMENT_LEFT, size.x - x0, 17, Color.WHITE)
		draw_string(fb, Vector2(x0, h * 0.68), "SEVİYE %d" % level, HORIZONTAL_ALIGNMENT_LEFT, size.x - x0, 12, UI.DIM)
		var bw := size.x - x0 - 4
		draw_rect(Rect2(x0, h * 0.78, bw, 5), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(x0, h * 0.78, bw * frac, 5), UI.ACCENT)

class TopGlow extends Control:
	## accent line under the top bar that fades out toward the edges
	func _draw() -> void:
		var w := size.x
		var n := 24
		for i in n:
			var t0 := float(i) / n
			var a := sin(t0 * PI)
			draw_rect(Rect2(w * t0, 0, w / n + 1, 2), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.25 + 0.75 * a))
			draw_rect(Rect2(w * t0, 2, w / n + 1, 2), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.12 * a))

func show_page(p: String) -> void:
	page = p
	room_countdown = -1
	room_chat = null
	if modal:
		modal.queue_free(); modal = null
	for k in nav_btns.keys():
		var b: Button = nav_btns[k]
		var on: bool = k == p or (k == "rooms" and (p == "room" or p == "netroom"))
		b.add_theme_color_override("font_color", UI.ACCENT2 if on else UI.TEXT)
		var nsb := StyleBoxFlat.new()
		nsb.bg_color = Color(1, 0.55, 0.12, 0.10) if on else Color(0, 0, 0, 0)
		nsb.border_color = UI.ACCENT
		nsb.border_width_bottom = 4 if on else 0
		nsb.content_margin_left = 13; nsb.content_margin_right = 13
		b.add_theme_stylebox_override("normal", nsb)
	UI.clear(content)
	if p != "lobby" and char_view != "" and char_view != GS.cur_char():
		char_view = GS.cur_char()
		_swap_soldier(char_view)
	spin_speed = 0.5
	if studio:
		studio.visible = p in ["bag", "market"]
	cam_target = Vector3(0.5, 1.5, 4.6)
	cam_look = Vector3(0.5, 1.1, 0)
	soldier.visible = true
	match p:
		"lobby": _page_lobby()
		"bag": _page_bag()
		"market": _page_market()
		"crate": _page_crate()
		"mods": _page_mods()
		"rooms": _page_rooms()
		"room": _page_room()
		"friends": online.page_friends()
		"netroom": online.page_room()
		"profile": _page_profile()
		"settings": _page_settings()
	_refresh_currency()

func _margin(c: Control, l: int, t: int, r: int, b: int) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = l; c.offset_top = t; c.offset_right = -r; c.offset_bottom = -b

# ================================================================ sets panel (shared)
func _sets_panel(compact: bool = false) -> Control:
	var p := UI.panel(UI.BG, UI.LINE, 14)
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.header("SETLER", 22))
	var tabs := UI.hbox(4)
	v.add_child(tabs)
	for i in 3:
		var b := UI.btn("Set %d" % (i + 1), func(): GS.profile["active_set"] = i; GS.save_profile(); show_page(page), 18, GS.profile["active_set"] == i, 0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	var set := GS.active_set()
	for c in GS.SLOT_ORDER:
		var id: String = set.get(c, "")
		var card := UI.panel(Color(0.07, 0.085, 0.115, 0.95), UI.LINE, 8)
		var h := UI.hbox(8)
		card.add_child(h)
		if id != "":
			h.add_child(thumb_rect(id, GS.wskin(id), Vector2(150 if not compact else 110, 62 if not compact else 46)))
			var tv := UI.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lv := GS.wlvl(id)
			tv.add_child(UI.lbl(GS.WEAPONS[id]["name"] + (" [+%d]" % lv if lv > 0 else ""), 20, Color.WHITE, "Rajdhani-Bold"))
			var sk: Dictionary = GS.SKINS[GS.wskin(id)]
			tv.add_child(UI.lbl(GS.CATS[c] + "  •  " + sk["name"], 15, GS.RARITY_COLORS[int(sk["rarity"])], "Rajdhani-SemiBold"))
			h.add_child(tv)
		v.add_child(card)
	return p

# ================================================================ LOBBY
var char_view := ""

func _char_owned(c: String) -> bool:
	var own: Array = GS.profile.get("chars", ["takim", "deri", "asker1"])
	return c in own or int(GS.CHARACTERS[c]["price"]) == 0

func _swap_soldier(c: String) -> void:
	var ps: PackedScene = GS.char_scene(c)
	if ps == null:
		return
	var old_vis := soldier.visible
	var t := soldier.transform
	soldier.queue_free()
	soldier = ps.instantiate()
	MatLib.apply(soldier)
	soldier.transform = t
	soldier.visible = old_vis
	world.add_child(soldier)
	var ap := soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("Idle"):
		ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
	# little 'spawn' pop
	soldier.scale = Vector3(0.92, 0.92, 0.92)
	create_tween().tween_property(soldier, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _char_picker() -> Control:
	if char_view == "":
		char_view = GS.cur_char()
	var ids: Array = GS.CHARACTERS.keys()
	var c: String = char_view
	var info: Dictionary = GS.CHARACTERS[c]
	var p := UI.panel(UI.BG, UI.LINE, 12)
	var v := UI.vbox(6)
	p.add_child(v)
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.lbl("KARAKTER", 18, UI.ACCENT2, "Rajdhani-Bold"))
	h.add_child(UI.spacer())
	h.add_child(UI.lbl(GS.TEAMS[info["team"]], 16, GS.TEAM_COLORS[info["team"]], "Rajdhani-Bold"))
	var row := UI.hbox(8)
	v.add_child(row)
	var step := func(d: int):
		var i := ids.find(char_view)
		char_view = ids[(i + d + ids.size()) % ids.size()]
		_swap_soldier(char_view)
		show_page("lobby")
	row.add_child(UI.btn("◀", func(): step.call(-1), 22, false, 48, 48))
	var mid := UI.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(UI.lbl(info["name"], 26, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	mid.add_child(UI.lbl(info["desc"], 15, UI.DIM, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(mid)
	row.add_child(UI.btn("▶", func(): step.call(1), 22, false, 48, 48))
	if c == GS.cur_char():
		v.add_child(UI.lbl("✔ KUŞANILDI", 18, UI.GREEN, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	elif _char_owned(c):
		v.add_child(UI.btn("KUŞAN", func():
			GS.profile["char"] = c
			GS.save_profile()
			show_page("lobby"), 20, true, 0, 44))
	else:
		var price := int(info["price"])
		var b := UI.btn("SATIN AL   %s ALTIN" % UI.money(price), func():
			if int(GS.profile["gold"]) >= price:
				GS.profile["gold"] = int(GS.profile["gold"]) - price
				var own: Array = GS.profile.get("chars", ["takim", "deri", "asker1"])
				own.append(c)
				GS.profile["chars"] = own
				GS.profile["char"] = c
				GS.save_profile()
				SFX.play("buy")
				_refresh_currency()
				show_page("lobby")
			else:
				SFX.play("fail"), 20, false, 0, 44)
		b.disabled = int(GS.profile["gold"]) < price
		v.add_child(b)
	return p

func _page_lobby() -> void:
	set_showcase(GS.active_set().get("ana", "ak47"))
	var left := UI.vbox(12)
	left.position = Vector2(28, 18)
	left.custom_minimum_size = Vector2(430, 0)
	content.add_child(left)
	left.add_child(_sets_panel())
	# player card
	var pc := UI.panel(UI.BG, UI.LINE, 14)
	var pv := UI.vbox(6)
	pc.add_child(pv)
	var p := GS.profile
	var top := UI.hbox(10)
	pv.add_child(top)
	top.add_child(UI.lbl(str(p["name"]), 28, Color.WHITE, "RussoOne-Regular"))
	top.add_child(UI.spacer())
	top.add_child(UI.lbl(_rank(int(p["level"])), 18, UI.ACCENT2, "Rajdhani-Bold"))
	var lvl := int(p["level"])
	pv.add_child(UI.lbl("Seviye %d   •   %s / %s XP" % [lvl, UI.money(int(p["xp"])), UI.money(GS.xp_for_level(lvl))], 17, UI.DIM))
	pv.add_child(UI.bar(float(p["xp"]), float(GS.xp_for_level(lvl)), Color("7fd1ff"), 8))
	var st: Dictionary = p["stats"]
	var sh := UI.hbox(18)
	pv.add_child(sh)
	for pair in [["Maç", st["matches"]], ["Galibiyet", st["wins"]], ["K/D", "%.2f" % (float(st["kills"]) / max(1.0, float(st["deaths"])))], ["Kafadan", st["headshots"]]]:
		var vv := UI.vbox(-4)
		vv.add_child(UI.lbl(str(pair[1]), 26, Color.WHITE, "Teko"))
		vv.add_child(UI.lbl(pair[0], 14, UI.DIM, "Rajdhani-Bold"))
		sh.add_child(vv)
	left.add_child(pc)
	left.add_child(_char_picker())
	# play buttons (bottom center)
	var pb := UI.vbox(10)
	pb.anchor_left = 0.5; pb.anchor_right = 0.5; pb.anchor_top = 1; pb.anchor_bottom = 1
	pb.offset_left = -260; pb.offset_right = 260; pb.offset_top = -230; pb.offset_bottom = -40
	content.add_child(pb)
	var quick := UI.btn("▶   HIZLI OYUN", _quick_play, 34, true, 520, 84)
	quick.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	pb.add_child(quick)
	var h2 := UI.hbox(10)
	pb.add_child(h2)
	var b1 := UI.btn("ODA LİSTESİ", func(): show_page("rooms"), 22, false, 0, 56)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := UI.btn("ODA KUR", _create_room_dialog, 22, false, 0, 56)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(b1); h2.add_child(b2)
	# right column: news + missions
	var right := UI.vbox(12)
	right.anchor_left = 1; right.anchor_right = 1
	right.offset_left = -470; right.offset_right = -28; right.offset_top = 18
	content.add_child(right)
	var news := UI.panel(Color(0.12, 0.06, 0.02, 0.88), UI.ACCENT, 16)
	var nv := UI.vbox(6)
	news.add_child(nv)
	nv.add_child(UI.lbl("YENİ HARİTALAR YAYINDA!", 26, UI.ACCENT2, "RussoOne-Regular"))
	nv.add_child(_wrap("Safranbolu konakları ve Marmara'daki yük gemisi artık oynanabilir. Silah Oyunu ve Bıçak Arenası modlarını dene!", 18))
	nv.add_child(UI.lbl("Hafta sonu: 2x Malzeme düşme şansı", 17, UI.GOLD, "Rajdhani-Bold"))
	right.add_child(news)
	var mp := UI.panel(UI.BG, UI.LINE, 14)
	var mv := UI.vbox(10)
	mp.add_child(mv)
	mv.add_child(UI.header("GÜNLÜK GÖREVLER", 22))
	for ms in GS.MISSIONS:
		var have := int(p["missions"].get(ms["key"], 0))
		var done := have >= int(ms["goal"])
		var claimed: bool = p["missions"]["claimed"].has(ms["id"])
		var row := UI.vbox(4)
		var rh := UI.hbox(8)
		rh.add_child(UI.lbl(ms["text"], 19, Color.WHITE if not claimed else UI.DIM, "Rajdhani-Bold"))
		rh.add_child(UI.spacer())
		var rew := []
		for k in ms["reward"].keys():
			rew.append("%s %s" % [UI.money(ms["reward"][k]), "Altın" if k == "gold" else GS.MATS[k]])
		rh.add_child(UI.lbl(", ".join(rew), 15, UI.GOLD, "Rajdhani-SemiBold"))
		row.add_child(rh)
		var bh := UI.hbox(8)
		var pbar := UI.bar(min(have, int(ms["goal"])), int(ms["goal"]), UI.GREEN if done else UI.ACCENT, 8)
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bh.add_child(pbar)
		bh.add_child(UI.lbl("%d/%d" % [min(have, int(ms["goal"])), int(ms["goal"])], 16, UI.DIM))
		if done and not claimed:
			bh.add_child(UI.btn("ÖDÜLÜ AL", func(): _claim(ms), 16, true, 0, 32))
		elif claimed:
			bh.add_child(UI.lbl("✔ ALINDI", 16, UI.GREEN, "Rajdhani-Bold"))
		row.add_child(bh)
		mv.add_child(row)
	right.add_child(mp)

func _wrap(t: String, s: int) -> Label:
	var l := UI.lbl(t, s, UI.TEXT, "Rajdhani-Medium")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	return l

func _rank(l: int) -> String:
	var ranks := ["ER", "ONBAŞI", "ÇAVUŞ", "ÜSTÇAVUŞ", "ASTSUBAY", "TEĞMEN", "ÜSTEĞMEN", "YÜZBAŞI", "BİNBAŞI", "YARBAY", "ALBAY", "GENERAL"]
	return ranks[min(l / 5, ranks.size() - 1)]

func _claim(ms: Dictionary) -> void:
	for k in ms["reward"].keys():
		if k == "gold":
			GS.profile["gold"] = int(GS.profile["gold"]) + int(ms["reward"][k])
		else:
			GS.profile["mats"][k] = int(GS.profile["mats"].get(k, 0)) + int(ms["reward"][k])
	GS.profile["missions"]["claimed"][ms["id"]] = true
	GS.save_profile()
	SFX.play("buy")
	show_page("lobby")

func _quick_play() -> void:
	var maps := GS.MAPS.keys()
	var cfg := {"name": "Hızlı Oyun", "map": maps[randi() % maps.size()], "mode": ["ffa", "tdm", "tdm", "ffa", "gungame"][randi() % 5], "bots": 9, "diff": 1, "time": 8, "target": 40, "team": "a", "no": randi_range(100, 999)}
	if cfg["mode"] == "tdm": cfg["target"] = 60
	if cfg["mode"] == "gungame": cfg["target"] = 99
	room_cfg = cfg
	show_page("room")

# ================================================================ BAG (Çanta)
func _page_bag() -> void:
	cam_target = Vector3(1.6, 1.42, 1.5)
	cam_look = Vector3(1.6, 1.3, -0.4)
	soldier.visible = false
	var left := _sets_panel(true)
	left.position = Vector2(28, 18)
	left.custom_minimum_size = Vector2(400, 0)
	content.add_child(left)
	var right := UI.panel(UI.BG, UI.LINE, 14)
	right.anchor_left = 0; right.anchor_right = 1; right.anchor_bottom = 1
	right.offset_left = 448; right.offset_right = -28; right.offset_top = 18; right.offset_bottom = -330
	content.add_child(right)
	var rv := UI.vbox(10)
	right.add_child(rv)
	var th := UI.hbox(6)
	rv.add_child(th)
	th.add_child(UI.header("ÇANTA", 26))
	th.add_child(UI.spacer(false, 20))
	for c in [["tum", "Tümü"], ["ana", "Ana"], ["tabanca", "Tabanca"], ["bicak", "Bıçak"], ["bomba", "Bomba"]]:
		th.add_child(UI.btn(c[1], func(): bag_cat = c[0]; show_page("bag"), 18, bag_cat == c[0], 110, 38))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	var ids: Array = []
	for id in GS.WEAPONS.keys():
		if GS.owned(id) and (bag_cat == "tum" or GS.WEAPONS[id]["cat"] == bag_cat):
			ids.append(id)
	if bag_sel == "" or not GS.owned(bag_sel):
		bag_sel = ids[0] if ids.size() > 0 else "ak47"
	for id in ids:
		grid.add_child(_weapon_card(id, id == bag_sel, func(): bag_sel = id; show_page("bag")))
	# detail panel
	set_showcase(bag_sel)
	var det := UI.panel(UI.BG2, UI.ACCENT.darkened(0.4), 16)
	det.anchor_left = 0; det.anchor_right = 1; det.anchor_top = 1; det.anchor_bottom = 1
	det.offset_left = 448; det.offset_right = -28; det.offset_top = -316; det.offset_bottom = -24
	content.add_child(det)
	var dh := UI.hbox(24)
	det.add_child(dh)
	var w: Dictionary = GS.WEAPONS[bag_sel]
	var lvl := GS.wlvl(bag_sel)
	var c1 := UI.vbox(6)
	c1.custom_minimum_size = Vector2(420, 0)
	dh.add_child(c1)
	c1.add_child(UI.lbl(w["name"] + (" [+%d]" % lvl if lvl > 0 else ""), 34, Color.WHITE, "RussoOne-Regular"))
	c1.add_child(UI.lbl(w["cls"].to_upper(), 18, UI.RED, "Rajdhani-Bold"))
	c1.add_child(_lvl_pips(lvl, 22))
	var st := GS.full_stats(bag_sel)
	if not w.get("melee", false) and not w.get("throwable", false):
		var rows := _stat_rows(bag_sel)
		var sgd := GridContainer.new()
		sgd.columns = 2
		sgd.add_theme_constant_override("h_separation", 18)
		c1.add_child(sgd)
		for row in rows:
			sgd.add_child(_stat(row[0], row[1], row[2], true))
		c1.add_child(UI.lbl("Şarjör: %d   •   Yedek: %d   •   Kafa x%.1f" % [st["mag_max"], w["reserve"], float(w.get("head", 2.5))], 16, UI.DIM))
		if st.has("ability"):
			c1.add_child(_wrap("★ " + str(st["ability"]), 16))
	else:
		c1.add_child(_stat("Hasar", st["dmg"], 140))
		c1.add_child(_stat("Hareketlilik", int(w["speed"] * 90), 110))
	# skins
	var c2 := UI.vbox(8)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(c2)
	c2.add_child(UI.header("STİLLER", 20))
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 8)
	c2.add_child(sg)
	var owned_sk: Array = GS.profile["owned"][bag_sel]["skins"]
	for sk in GS.SKINS.keys():
		var sd: Dictionary = GS.SKINS[sk]
		var have := owned_sk.has(sk)
		var on: bool = GS.wskin(bag_sel) == sk
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.text = sd["name"] if have else "🔒 " + sd["name"]
		b.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
		b.add_theme_font_size_override("font_size", 16)
		var rc: Color = GS.RARITY_COLORS[int(sd["rarity"])]
		b.add_theme_stylebox_override("normal", UI.sb(Color(0.08, 0.09, 0.12) if not on else rc.darkened(0.55), rc if on else rc.darkened(0.5), 2 if on else 1, 3, 6))
		b.add_theme_stylebox_override("hover", UI.sb(rc.darkened(0.6), rc, 1, 3, 6))
		b.add_theme_color_override("font_color", Color.WHITE if have else UI.DIM)
		b.mouse_entered.connect(func(): set_showcase(bag_sel, sk))
		b.mouse_exited.connect(func(): set_showcase(bag_sel))
		b.pressed.connect(func():
			if have:
				GS.profile["owned"][bag_sel]["skin"] = sk
				GS.save_profile(); SFX.play("equip", -4); show_page("bag")
			else:
				market_tab = "stil"; show_page("market"))
		sg.add_child(b)
	# actions
	var c3 := UI.vbox(10)
	c3.custom_minimum_size = Vector2(260, 0)
	dh.add_child(c3)
	var in_set: bool = GS.active_set().get(w["cat"], "") == bag_sel
	c3.add_child(UI.btn("✔ KUŞANILDI" if in_set else "KUŞAN (Set %d)" % (int(GS.profile["active_set"]) + 1), func(): GS.active_set()[w["cat"]] = bag_sel; GS.save_profile(); SFX.play("equip"); show_page("bag"), 22, not in_set, 260, 56))
	var up_btn := UI.btn("YÜKSELT  ⬆" if lvl < GS.MAX_LVL else "MAKSİMUM SEVİYE", func(): _upgrade_dialog(bag_sel), 22, false, 260, 56)
	up_btn.disabled = lvl >= GS.MAX_LVL
	c3.add_child(up_btn)
	c3.add_child(UI.btn("ÖZELLEŞTİR  ⚙", func(): _parts_dialog(bag_sel), 20, false, 260, 50))
	c3.add_child(UI.btn("İNCELE  👁", func(): _inspect(bag_sel), 18, false, 260, 46))

func _weapon_card(id: String, selected: bool, cb: Callable, price: int = -1) -> Control:
	var w: Dictionary = GS.WEAPONS[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 150)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := Color(0.07, 0.085, 0.11, 0.96)
	b.add_theme_stylebox_override("normal", UI.sb(bg, UI.ACCENT if selected else UI.LINE, 2 if selected else 1, 4, 0))
	b.add_theme_stylebox_override("hover", UI.sb(bg.lightened(0.05), UI.ACCENT2, 1, 4, 0))
	b.add_theme_stylebox_override("pressed", UI.sb(bg, UI.ACCENT, 2, 4, 0))
	b.pressed.connect(func(): SFX.play("ui_click", -6); cb.call())
	b.mouse_entered.connect(func(): SFX.play("ui_hover", -14))
	var v := UI.vbox(0)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10; v.offset_right = -10; v.offset_top = 6; v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var h := UI.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var lvl := GS.wlvl(id) if price < 0 else 0
	var nl := UI.lbl(w["name"] + (" [+%d]" % lvl if lvl > 0 else ""), 19, Color.WHITE, "Rajdhani-Bold")
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nl)
	h.add_child(UI.spacer())
	var cl := UI.lbl(w["cls"], 16, UI.RED, "Rajdhani-Bold")
	h.add_child(cl)
	var tr := thumb_rect(id, GS.wskin(id) if price < 0 else "std", Vector2(0, 92))
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tr)
	var bh := UI.hbox(6)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bh)
	if price < 0:
		bh.add_child(_lvl_pips(lvl, 14))
		bh.add_child(UI.spacer())
		bh.add_child(UI.lbl("Süresiz", 15, UI.DIM, "Rajdhani-SemiBold"))
	else:
		var bl: Dictionary = GS.ball(id)
		if bl.has("ability"):
			var al := UI.lbl("★ " + str(bl["ability"]), 13, UI.ACCENT2, "Rajdhani-SemiBold")
			al.mouse_filter = Control.MOUSE_FILTER_IGNORE
			al.clip_text = true
			v.add_child(al)
			v.move_child(al, 1)
		bh.add_child(UI.spacer())
		bh.add_child(UI.lbl("◉ " + UI.money(price), 20, UI.GOLD, "Rajdhani-Bold"))
	return b

func _lvl_pips(lvl: int, s: int) -> Control:
	var h := UI.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in GS.MAX_LVL:
		var on := i < lvl
		var l := UI.lbl(str(i + 1), s, UI.ACCENT if on else Color(0.35, 0.38, 0.42), "Rajdhani-Bold")
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
	return h

func _stat(name: String, val: float, maxv: float, compact: bool = false) -> Control:
	var h := UI.hbox(8)
	var l := UI.lbl(name, 15 if compact else 17, UI.DIM, "Rajdhani-SemiBold")
	l.custom_minimum_size = Vector2(108 if compact else 120, 0)
	h.add_child(l)
	var frac: float = clamp(val / maxv, 0.0, 1.0)
	var col := UI.ACCENT if frac < 0.75 else UI.GOLD
	var b := UI.bar(clamp(val, 0, maxv), maxv, col, 7, 120 if compact else 200)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	h.add_child(UI.lbl(str(int(val)), 17, Color.WHITE, "Rajdhani-Bold"))
	return h

# ================================================================ UPGRADE
func _modal(w: int, h: int) -> VBoxContainer:
	if modal: modal.queue_free()
	modal = ColorRect.new()
	(modal as ColorRect).color = Color(0, 0, 0, 0.7)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(modal)
	var p := UI.panel(UI.BG2, UI.ACCENT, 24, 6)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(w, h)
	p.position = Vector2(-w / 2, -h / 2)
	modal.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	p.resized.connect(func(): p.position = (modal.size - p.size) / 2)
	return v

func _close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null

# ================================================================ CUSTOMISE (attachments)
func _parts_dialog(id: String) -> void:
	var w: Dictionary = GS.WEAPONS[id]
	if w.get("melee", false) or w.get("throwable", false):
		_toast("Bu silaha eklenti takılamaz.", UI.RED)
		return
	var v := _modal(1180, 640)
	var top := UI.hbox(10)
	v.add_child(top)
	top.add_child(UI.header("SİLAH ÖZELLEŞTİRME  •  " + str(w["name"]).to_upper(), 28))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("✕", _close_modal, 20, false, 44, 40))
	var body := UI.hbox(22)
	v.add_child(body)
	# left: weapon preview with current parts + live stat comparison
	var lv := UI.vbox(8)
	lv.custom_minimum_size = Vector2(420, 0)
	body.add_child(lv)
	var tr := thumb_rect(id, GS.wskin(id), Vector2(420, 190))
	lv.add_child(tr)
	var base := GS.full_stats(id, [])
	var now := GS.full_stats(id)
	var cmp := [["Hasar", "dmg", false], ["Sekme", "recoil", true], ["İsabet (nişan)", "ads_spread", true], ["Belden isabet", "spread", true], ["Şarjör", "mag_max", false], ["Doldurma", "reload", true]]
	for c in cmp:
		var a: float = float(base.get(c[1], 0)); var b: float = float(now.get(c[1], 0))
		var better: bool = (b < a) if c[2] else (b > a)
		var txt := ("%.3f" % b) if b < 1.0 else ("%d" % int(round(b))) if c[1] != "reload" else ("%.1f sn" % b)
		var hh := UI.hbox(8)
		var l := UI.lbl(c[0], 17, UI.DIM, "Rajdhani-SemiBold"); l.custom_minimum_size = Vector2(150, 0)
		hh.add_child(l)
		var colr := Color.WHITE if abs(a - b) < 0.0001 else (UI.GREEN if better else UI.RED)
		var pct := "" if abs(a - b) < 0.0001 or a == 0 else ("  (%+d%%)" % int(round((b - a) / a * 100.0)))
		hh.add_child(UI.lbl(txt + pct, 17, colr, "Rajdhani-Bold"))
		lv.add_child(hh)
	if now.get("silenced", false):
		lv.add_child(UI.lbl("🔇 Susturuculu: haritada görünmezsin, namlu alevi yok", 15, UI.GREEN, "Rajdhani-Bold"))
	# right: one column per slot
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	body.add_child(grid)
	var slot_names := {"namlu": "NAMLU", "optik": "NİŞANGAH", "sarjor": "ŞARJÖR", "alt": "ALT RAY"}
	for slot in GS.PART_SLOTS:
		var col := UI.vbox(8)
		col.custom_minimum_size = Vector2(170, 0)
		grid.add_child(col)
		col.add_child(UI.lbl(slot_names[slot], 18, UI.ACCENT2, "Rajdhani-Bold"))
		for pid in GS.PARTS.keys():
			var pd: Dictionary = GS.PARTS[pid]
			if pd["slot"] != slot:
				continue
			var fits := GS.part_fits(pid, id)
			var have := GS.parts_owned(pid) > 0
			var on: bool = pid in GS.wparts(id)
			var card := UI.panel(Color(0.06, 0.075, 0.1) if not on else Color(0.1, 0.2, 0.08), Color("7dff6a") if on else UI.LINE, 10)
			card.custom_minimum_size = Vector2(170, 0)
			col.add_child(card)
			var cv := UI.vbox(4)
			card.add_child(cv)
			var ic := PartIcon.new(); ic.pid = pid; ic.custom_minimum_size = Vector2(0, 60)
			cv.add_child(ic)
			cv.add_child(UI.lbl(pd["name"], 16, Color.WHITE if fits else UI.DIM, "Rajdhani-Bold"))
			var dl := UI.lbl(pd["desc"], 13, UI.DIM, "Rajdhani-SemiBold")
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size = Vector2(150, 0)
			cv.add_child(dl)
			var b: Button
			if not fits:
				b = UI.btn("UYUMSUZ", Callable(), 15, false, 0, 34); b.disabled = true
			elif on:
				b = UI.btn("ÇIKAR", func(): GS.remove_part(id, pid); SFX.play("equip", -6); _parts_dialog(id), 15, false, 0, 34)
			elif have:
				b = UI.btn("TAK  (x%d)" % GS.parts_owned(pid), func(): GS.fit_part(id, pid); SFX.play("bolt_fwd", -4); set_showcase(id); _parts_dialog(id), 15, true, 0, 34)
			else:
				b = UI.btn("◉ %s" % UI.money(int(pd["price"])), func():
					if int(GS.profile["gold"]) < int(pd["price"]):
						_toast("Yetersiz altın!", UI.RED); return
					GS.profile["gold"] = int(GS.profile["gold"]) - int(pd["price"])
					if not GS.profile.has("parts"): GS.profile["parts"] = {}
					GS.profile["parts"][pid] = GS.parts_owned(pid) + 1
					GS.fit_part(id, pid)
					SFX.play("buy"); _refresh_currency(); set_showcase(id); _parts_dialog(id), 15, false, 0, 34)
			cv.add_child(b)
	v.add_child(UI.lbl("Eklentileri Eklenti Paketi kasasından kazanabilir ya da buradan satın alabilirsin. Bir eklentiye sahip olunca tüm uyumlu silahlarına takabilirsin.", 15, UI.DIM, "Rajdhani-SemiBold"))

func _upgrade_dialog(id: String) -> void:
	var lvl := GS.wlvl(id)
	var cost := GS.upgrade_cost(lvl)
	var v := _modal(760, 560)
	var top := UI.hbox(10)
	v.add_child(top)
	top.add_child(UI.header("SİLAH YÜKSELTME", 28))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("✕", _close_modal, 20, false, 44, 40))
	var tr := thumb_rect(id, GS.wskin(id), Vector2(0, 170))
	tr.pivot_offset = Vector2(356, 85)
	var gm := ShaderMaterial.new()
	gm.shader = UPGRADE_GLOW
	gm.set_shader_parameter("sweep", -1.0)
	tr.material = gm
	v.add_child(tr)
	var sparks := CPUParticles2D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 90
	sparks.lifetime = 1.1
	sparks.explosiveness = 0.9
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = Vector2(240, 50)
	sparks.direction = Vector2(0, -1)
	sparks.spread = 70
	sparks.initial_velocity_min = 80; sparks.initial_velocity_max = 320
	sparks.gravity = Vector2(0, 260)
	sparks.scale_amount_min = 2.0; sparks.scale_amount_max = 4.5
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 0.95, 0.7, 1)); sg.set_color(1, Color(1, 0.55, 0.1, 0))
	sparks.color_ramp = sg
	tr.add_child(sparks)
	tr.resized.connect(func(): sparks.position = tr.size / 2)
	var lh := UI.hbox(20)
	lh.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(lh)
	lh.add_child(UI.lbl(GS.WEAPONS[id]["name"] + " [+%d]" % lvl, 30, Color.WHITE, "RussoOne-Regular"))
	lh.add_child(UI.lbl("➜", 30, UI.ACCENT, "Rajdhani-Bold"))
	lh.add_child(UI.lbl("[+%d]" % (lvl + 1), 34, UI.ACCENT2, "RussoOne-Regular"))
	var s0 := GS.stats_for(id, lvl)
	var s1 := GS.stats_for(id, lvl + 1)
	v.add_child(UI.lbl("Hasar %d ➜ %d    •    Geri Tepme -%d%%    •    Şarjör %d ➜ %d" % [s0["dmg"], s1["dmg"], 3, s0["mag"], s1["mag"]], 19, UI.GREEN, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	var ch := UI.hbox(16)
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(ch)
	var reqs := [["gold", "Altın", UI.GOLD]]
	for m in GS.MATS.keys():
		reqs.append([m, GS.MATS[m], Color("c8d2dc")])
	for r in reqs:
		var need := int(cost.get(r[0], 0))
		if need <= 0:
			continue
		var have := int(GS.profile["gold"]) if r[0] == "gold" else int(GS.profile["mats"].get(r[0], 0))
		var p := UI.panel(Color(1, 1, 1, 0.04), r[2].darkened(0.4), 10)
		var pv := UI.vbox(0)
		p.add_child(pv)
		pv.add_child(UI.lbl(UI.money(need), 26, Color.WHITE if have >= need else UI.RED, "Teko", HORIZONTAL_ALIGNMENT_CENTER))
		pv.add_child(UI.lbl("%s (%s)" % [r[1], UI.money(have)], 14, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		p.custom_minimum_size = Vector2(120, 0)
		ch.add_child(p)
	v.add_child(UI.lbl("Başarı şansı: %%%d   (başarısız olursa malzemeler harcanır, seviye düşmez)" % cost["chance"], 18, UI.ACCENT2, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	var pb := UI.bar(0, 1, UI.ACCENT, 14)
	v.add_child(pb)
	var res := UI.lbl("", 40, UI.GOLD, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(res)
	var go := UI.btn("YÜKSELT", Callable(), 26, true, 0, 60)
	go.disabled = not GS.can_afford(cost)
	v.add_child(go)
	go.pressed.connect(func():
		go.disabled = true
		GS.pay(cost)
		GS.save_profile()
		SFX.play("upgrade_charge", -2)
		spin_speed = 9.0
		# charging: repeated light sweeps over the weapon, getting faster and brighter
		gm.set_shader_parameter("glow_col", Color(1.0, 0.62, 0.18))
		var gtw := create_tween()
		for k in 4:
			var d := 0.62 - k * 0.1
			gtw.tween_method(func(x): gm.set_shader_parameter("sweep", x), -0.4, 1.6, d)
		gtw.parallel().tween_method(func(x): gm.set_shader_parameter("glow", x), 0.0, 0.9, 2.2)
		gtw.parallel().tween_method(func(x): gm.set_shader_parameter("outline", x), 0.0, 1.0, 2.2)
		var tw := create_tween()
		tw.tween_property(pb, "value", 1.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(rim, "light_energy", 80.0, 2.2)
		tw.tween_callback(func():
			spin_speed = 0.5
			rim.light_energy = 9
			var ok := randi_range(1, 100) <= int(cost["chance"])
			if ok:
				GS.profile["owned"][id]["lvl"] = lvl + 1
				GS.save_profile()
				SFX.play("success")
				res.text = "BAŞARILI!  +%d" % (lvl + 1)
				res.add_theme_color_override("font_color", UI.GOLD)
				res.scale = Vector2(1.6, 1.6)
				res.pivot_offset = res.size / 2
				var t2 := res.create_tween()
				t2.tween_property(res, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				# success: gold flash washes over the weapon, then slowly fades
				gm.set_shader_parameter("glow_col", Color(1.0, 0.82, 0.32))
				gm.set_shader_parameter("glow", 2.2)
				gm.set_shader_parameter("outline", 1.6)
				sparks.position = tr.size / 2
				sparks.restart()
				var t3 := tr.create_tween()
				t3.tween_method(func(x): gm.set_shader_parameter("sweep", x), -0.4, 1.6, 0.55)
				t3.parallel().tween_method(func(x): gm.set_shader_parameter("glow", x), 2.2, 0.0, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				t3.parallel().tween_method(func(x): gm.set_shader_parameter("outline", x), 1.6, 0.0, 1.8).set_ease(Tween.EASE_OUT)
			else:
				SFX.play("fail")
				gm.set_shader_parameter("glow_col", Color(1.0, 0.15, 0.1))
				var t5 := tr.create_tween()
				t5.tween_method(func(x): gm.set_shader_parameter("glow", x), 1.4, 0.0, 0.9)
				t5.parallel().tween_method(func(x): gm.set_shader_parameter("outline", x), 1.2, 0.0, 0.9)
				res.text = "BAŞARISIZ!"
				res.add_theme_color_override("font_color", UI.RED)
				var t4 := v.create_tween()
				for k in 6:
					t4.tween_property(v, "position:x", 10.0 * (1 if k % 2 == 0 else -1), 0.04)
				t4.tween_property(v, "position:x", 0.0, 0.04)
			_refresh_currency()
			get_tree().create_timer(1.6).timeout.connect(func(): if page == "bag": show_page("bag"))))

# ================================================================ MARKET
func _page_market() -> void:
	soldier.visible = false
	cam_target = Vector3(1.6, 1.42, 1.5)
	cam_look = Vector3(1.6, 1.3, -0.4)
	var p := UI.panel(UI.BG, UI.LINE, 16)
	_margin(p, 28, 18, 640, 24)
	content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var th := UI.hbox(6)
	v.add_child(th)
	th.add_child(UI.header("MARKET", 28))
	th.add_child(UI.spacer(false, 20))
	for t in [["silah", "Silahlar"], ["eklenti", "Eklentiler"], ["stil", "Stiller"], ["karakter", "Karakterler"], ["kasa", "Kasalar"], ["malzeme", "Malzemeler"]]:
		th.add_child(UI.btn(t[1], func(): market_tab = t[0]; show_page("market"), 18, market_tab == t[0], 128, 40))
	# featured offer banner
	if market_tab == "silah":
		var feat := ""
		for fid in ["m249", "aug", "vector", "scar"]:
			if not GS.owned(fid):
				feat = fid; break
		if feat != "":
			var fb := UI.panel(Color(0.12, 0.07, 0.02, 0.95), UI.ACCENT, 12)
			v.add_child(fb)
			var fh := UI.hbox(18)
			fb.add_child(fh)
			var ftr := thumb_rect(feat, "std", Vector2(300, 110))
			fh.add_child(ftr)
			var fv := UI.vbox(4)
			fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fh.add_child(fv)
			fv.add_child(UI.lbl("HAFTANIN SİLAHI", 15, UI.ACCENT2, "Rajdhani-Bold"))
			fv.add_child(UI.lbl(GS.WEAPONS[feat]["name"], 34, Color.WHITE, "RussoOne-Regular"))
			fv.add_child(UI.lbl("★ " + str(GS.ball(feat).get("ability", "")), 17, UI.TEXT, "Rajdhani-SemiBold"))
			var fp: int = int(GS.WEAPONS[feat]["price"] * 0.8)
			var fbb := UI.btn("◉ %s   (-%%20)  SATIN AL" % UI.money(fp), func():
				if int(GS.profile["gold"]) < fp:
					_toast("Yetersiz altın!", UI.RED); return
				GS.profile["gold"] = int(GS.profile["gold"]) - fp
				GS.profile["owned"][feat] = {"lvl": 0, "skin": "std", "skins": ["std"]}
				GS.save_profile(); SFX.play("buy"); _refresh_currency(); _toast(GS.WEAPONS[feat]["name"] + " alındı!", UI.GREEN); show_page("market"), 20, true, 330, 50)
			fh.add_child(fbb)
			fbb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	match market_tab:
		"silah":
			var any := false
			for id in GS.WEAPONS.keys():
				if GS.owned(id):
					continue
				any = true
				var price: int = GS.WEAPONS[id]["price"]
				grid.add_child(_weapon_card(id, false, func(): _buy_weapon(id), price))
			if not any:
				v.add_child(UI.lbl("Tüm silahlara sahipsin!", 24, UI.GREEN))
			set_showcase("awp" if not GS.owned("awp") else "m4a1")
		"stil":
			var target_id := bag_sel if bag_sel != "" and GS.owned(bag_sel) else "ak47"
			var sel := UI.hbox(6)
			v.add_child(sel)
			v.move_child(sel, 1)
			sel.add_child(UI.lbl("Silah:", 18, UI.DIM))
			for id in GS.profile["owned"].keys():
				if GS.WEAPONS[id].get("throwable", false):
					continue
				sel.add_child(UI.btn(GS.WEAPONS[id]["name"], func(): bag_sel = id; show_page("market"), 16, id == target_id, 0, 34))
			set_showcase(target_id)
			for sk in GS.SKINS.keys():
				if sk == "std":
					continue
				var sd: Dictionary = GS.SKINS[sk]
				var have: bool = GS.profile["owned"][target_id]["skins"].has(sk)
				var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), GS.RARITY_COLORS[int(sd["rarity"])], 10)
				card.custom_minimum_size = Vector2(300, 200)
				var cv := UI.vbox(4)
				card.add_child(cv)
				cv.add_child(UI.lbl(sd["name"], 20, Color.WHITE, "Rajdhani-Bold"))
				cv.add_child(UI.lbl(GS.RARITY_NAMES[int(sd["rarity"])], 15, GS.RARITY_COLORS[int(sd["rarity"])], "Rajdhani-Bold"))
				cv.add_child(thumb_rect(target_id, sk, Vector2(0, 90)))
				if have:
					cv.add_child(UI.lbl("✔ SAHİPSİN", 18, UI.GREEN, "Rajdhani-Bold"))
				else:
					cv.add_child(UI.btn("◉ " + UI.money(sd["price"]) + "  SATIN AL", func(): _buy_skin(target_id, sk), 18, true, 0, 38))
				card.mouse_entered.connect(func(): set_showcase(target_id, sk))
				grid.add_child(card)
		"karakter":
			set_showcase(GS.active_set().get("ana", "ak47"))
			for c in GS.CHARACTERS.keys():
				var cd: Dictionary = GS.CHARACTERS[c]
				var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), GS.TEAM_COLORS[cd["team"]], 12)
				card.custom_minimum_size = Vector2(300, 170)
				var cv := UI.vbox(4)
				card.add_child(cv)
				cv.add_child(UI.lbl(cd["name"], 24, Color.WHITE, "RussoOne-Regular"))
				cv.add_child(UI.lbl(GS.TEAMS[cd["team"]] + "  •  " + cd["desc"], 15, UI.DIM, "Rajdhani-SemiBold"))
				if _char_owned(c):
					cv.add_child(UI.lbl("✔ SAHİPSİN", 18, UI.GREEN, "Rajdhani-Bold"))
					cv.add_child(UI.btn("KUŞAN", func(): GS.profile["char"] = c; GS.save_profile(); char_view = c; _swap_soldier(c); _toast(cd["name"] + " kuşanıldı", UI.GREEN), 18, false, 0, 38))
				else:
					var pr := int(cd["price"])
					cv.add_child(UI.btn("◉ " + UI.money(pr) + "  SATIN AL", func():
						if int(GS.profile["gold"]) < pr:
							_toast("Yetersiz altın!", UI.RED); return
						GS.profile["gold"] = int(GS.profile["gold"]) - pr
						var own: Array = GS.profile.get("chars", ["takim", "deri", "asker1"])
						own.append(c); GS.profile["chars"] = own
						GS.save_profile(); SFX.play("buy"); _refresh_currency(); show_page("market"), 18, true, 0, 38))
				card.mouse_entered.connect(func(): _swap_soldier(c))
				grid.add_child(card)
			soldier.visible = true
		"kasa":
			for t in GS.CRATES.keys():
				var cd: Dictionary = GS.CRATES[t]
				var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), cd["color"], 12)
				card.custom_minimum_size = Vector2(300, 190)
				var cv := UI.vbox(6)
				card.add_child(cv)
				var hh := UI.hbox(8)
				cv.add_child(hh)
				var ic := CrateIcon.new(); ic.col = cd["color"]; ic.custom_minimum_size = Vector2(50, 50)
				hh.add_child(ic)
				hh.add_child(UI.lbl(cd["name"], 22, Color.WHITE, "RussoOne-Regular"))
				var dl := UI.lbl(cd["desc"], 15, UI.DIM, "Rajdhani-SemiBold")
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cv.add_child(dl)
				cv.add_child(UI.lbl("Sende: %d" % _crate_count(t), 16, Color.WHITE, "Rajdhani-Bold"))
				cv.add_child(UI.btn("◉ " + UI.money(int(cd["price"])) + "  SATIN AL", func():
					if int(GS.profile["gold"]) < int(cd["price"]):
						_toast("Yetersiz altın!", UI.RED); return
					GS.profile["gold"] = int(GS.profile["gold"]) - int(cd["price"])
					if t == "sokak":
						GS.profile["crates"] = int(GS.profile.get("crates", 0)) + 1
					else:
						var d: Dictionary = GS.profile.get("crates2", {})
						d[t] = int(d.get(t, 0)) + 1
						GS.profile["crates2"] = d
					GS.save_profile(); SFX.play("buy"); _refresh_currency(); show_page("market"), 18, true, 0, 38))
				grid.add_child(card)
		"eklenti":
			set_showcase(GS.active_set().get("ana", "ak47"))
			for pid in GS.PARTS.keys():
				var pd: Dictionary = GS.PARTS[pid]
				var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), Color("7dff6a").darkened(0.35), 12)
				card.custom_minimum_size = Vector2(300, 220)
				var cv := UI.vbox(6)
				card.add_child(cv)
				var ic := PartIcon.new(); ic.pid = pid; ic.custom_minimum_size = Vector2(0, 76)
				cv.add_child(ic)
				cv.add_child(UI.lbl(pd["name"], 21, Color.WHITE, "RussoOne-Regular"))
				var dl := UI.lbl(pd["desc"], 15, UI.DIM, "Rajdhani-SemiBold")
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cv.add_child(dl)
				cv.add_child(UI.lbl("Sende: %d   •   Yuva: %s" % [GS.parts_owned(pid), str(pd["slot"]).to_upper()], 15, Color.WHITE, "Rajdhani-Bold"))
				cv.add_child(UI.btn("◉ " + UI.money(int(pd["price"])) + "  SATIN AL", func():
					if int(GS.profile["gold"]) < int(pd["price"]):
						_toast("Yetersiz altın!", UI.RED); return
					GS.profile["gold"] = int(GS.profile["gold"]) - int(pd["price"])
					if not GS.profile.has("parts"): GS.profile["parts"] = {}
					GS.profile["parts"][pid] = GS.parts_owned(pid) + 1
					GS.save_profile(); SFX.play("buy"); _refresh_currency(); _toast(pd["name"] + " alındı! Çanta > Özelleştir ile tak.", UI.GREEN); show_page("market"), 18, true, 0, 38))
				grid.add_child(card)
		"malzeme":
			set_showcase("frag")
			for pack in [["Demir Paketi", "demir", 50, 600], ["Krom Paketi", "krom", 25, 900], ["Titanyum Paketi", "titanyum", 10, 1500], ["Kobalt Paketi", "kobalt", 5, 2500], ["Kasa Anahtarı", "crate", 1, 1000]]:
				var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), UI.LINE, 14)
				card.custom_minimum_size = Vector2(300, 170)
				var cv := UI.vbox(8)
				card.add_child(cv)
				cv.add_child(UI.lbl(pack[0], 24, Color.WHITE, "RussoOne-Regular"))
				cv.add_child(UI.lbl("x%d" % pack[2], 40, Color("c8d2dc"), "Teko"))
				cv.add_child(UI.btn("◉ " + UI.money(pack[3]) + "  SATIN AL", func(): _buy_pack(pack), 18, true, 0, 40))
				grid.add_child(card)

func _buy_weapon(id: String) -> void:
	var price: int = GS.WEAPONS[id]["price"]
	if int(GS.profile["gold"]) < price:
		_toast("Yetersiz altın!", UI.RED)
		SFX.play("fail", -6)
		return
	GS.profile["gold"] = int(GS.profile["gold"]) - price
	GS.profile["owned"][id] = {"lvl": 0, "skins": ["std"], "skin": "std"}
	GS.save_profile()
	SFX.play("buy")
	_toast(GS.WEAPONS[id]["name"] + " çantana eklendi!", UI.GREEN)
	show_page("market")

func _buy_skin(id: String, sk: String) -> void:
	var price: int = GS.SKINS[sk]["price"]
	if int(GS.profile["gold"]) < price:
		_toast("Yetersiz altın!", UI.RED)
		SFX.play("fail", -6)
		return
	GS.profile["gold"] = int(GS.profile["gold"]) - price
	GS.profile["owned"][id]["skins"].append(sk)
	GS.profile["owned"][id]["skin"] = sk
	GS.save_profile()
	SFX.play("buy")
	_toast(GS.SKINS[sk]["name"] + " stili alındı ve uygulandı!", UI.GREEN)
	show_page("market")

func _buy_pack(pack: Array) -> void:
	if int(GS.profile["gold"]) < int(pack[3]):
		_toast("Yetersiz altın!", UI.RED)
		SFX.play("fail", -6)
		return
	GS.profile["gold"] = int(GS.profile["gold"]) - int(pack[3])
	if pack[1] == "crate":
		GS.profile["crates"] = int(GS.profile.get("crates", 0)) + 1
	else:
		GS.profile["mats"][pack[1]] = int(GS.profile["mats"].get(pack[1], 0)) + int(pack[2])
	GS.save_profile()
	SFX.play("buy")
	_toast(pack[0] + " alındı!", UI.GREEN)

func _toast(t: String, c: Color) -> void:
	var p := UI.panel(Color(0.03, 0.04, 0.06, 0.95), c, 14)
	p.add_child(UI.lbl(t, 22, c, "Rajdhani-Bold"))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.position = Vector2(ui.size.x / 2 - 220, ui.size.y - 140)
	ui.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

# ================================================================ CRATE (Kasa)
var crate_items: Array = []
var crate_type := "sokak"

func _crate_count(t: String) -> int:
	if t == "sokak":
		return int(GS.profile.get("crates", 0))
	return int(GS.profile.get("crates2", {}).get(t, 0))

func _crate_take(t: String) -> void:
	if t == "sokak":
		GS.profile["crates"] = int(GS.profile["crates"]) - 1
	else:
		var d: Dictionary = GS.profile.get("crates2", {})
		d[t] = int(d.get(t, 0)) - 1
		GS.profile["crates2"] = d

func _page_crate() -> void:
	soldier.visible = true
	var p := UI.panel(UI.BG, UI.LINE, 20)
	p.anchor_left = 0.5; p.anchor_right = 0.5
	p.offset_left = -640; p.offset_right = 640; p.offset_top = 24
	content.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	var top := UI.hbox(10)
	v.add_child(top)
	top.add_child(UI.header("KASALAR", 30))
	top.add_child(UI.spacer())
	# crate type selector cards
	var row := UI.hbox(10)
	v.add_child(row)
	for t in GS.CRATES.keys():
		var cd: Dictionary = GS.CRATES[t]
		var on: bool = t == crate_type
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(300, 96)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var c: Color = cd["color"]
		b.add_theme_stylebox_override("normal", UI.sb(c.darkened(0.7 if not on else 0.45), c if on else c.darkened(0.4), 2 if on else 1, 6, 10))
		b.add_theme_stylebox_override("hover", UI.sb(c.darkened(0.4), c.lightened(0.2), 2, 6, 10))
		b.add_theme_stylebox_override("pressed", UI.sb(c.darkened(0.3), Color.WHITE, 2, 6, 10))
		var bv := UI.vbox(2)
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.offset_left = 14; bv.offset_top = 8; bv.offset_right = -10
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var hh := UI.hbox(8); hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(hh)
		var ic := CrateIcon.new(); ic.col = c; ic.custom_minimum_size = Vector2(44, 44); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hh.add_child(ic)
		var tv := UI.vbox(0); tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hh.add_child(tv)
		tv.add_child(UI.lbl(cd["name"], 21, Color.WHITE, "Rajdhani-Bold"))
		tv.add_child(UI.lbl("◉ %s   •   Sende: %d" % [UI.money(int(cd["price"])), _crate_count(t)], 15, UI.GOLD, "Rajdhani-Bold"))
		var dl := UI.lbl(cd["desc"], 13, Color(1, 1, 1, 0.7), "Rajdhani-SemiBold")
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(270, 0)
		bv.add_child(dl)
		for cc in b.find_children("*", "Control", true, false):
			(cc as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(func(): crate_type = t; SFX.play("ui_click", -4); show_page("crate"))
		row.add_child(b)
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(1240, 210)
	v.add_child(clip)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	clip.add_child(strip)
	var marker := ColorRect.new()
	marker.color = GS.CRATES[crate_type]["color"]
	marker.size = Vector2(4, 210)
	marker.position = Vector2(618, 0)
	clip.add_child(marker)
	crate_items.clear()
	for i in 46:
		var it := _roll_item(crate_type)
		crate_items.append(it)
		strip.add_child(_crate_card(it))
	var info := UI.lbl("", 22, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(info)
	var res := UI.lbl("", 32, UI.GOLD, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(res)
	var hb := UI.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hb)
	var cprice := int(GS.CRATES[crate_type]["price"])
	var open := UI.btn("", Callable(), 26, true, 380, 60)
	var refresh := func():
		info.text = "%s  •  Sende: %d" % [GS.CRATES[crate_type]["name"], _crate_count(crate_type)]
		open.text = "KASAYI AÇ" if _crate_count(crate_type) > 0 else "SATIN AL & AÇ (◉ %s)" % UI.money(cprice)
	refresh.call()
	hb.add_child(open)
	open.pressed.connect(func():
		if _crate_count(crate_type) > 0:
			_crate_take(crate_type)
		elif int(GS.profile["gold"]) >= cprice:
			GS.profile["gold"] = int(GS.profile["gold"]) - cprice
		else:
			_toast("Yetersiz altın!", UI.RED); return
		open.disabled = true
		var win_i := 38
		var win: Dictionary = _roll_item(crate_type)
		crate_items[win_i] = win
		var old := strip.get_child(win_i)
		strip.remove_child(old); old.queue_free()
		var nc := _crate_card(win)
		strip.add_child(nc); strip.move_child(nc, win_i)
		strip.position.x = 0
		var target_x := -(win_i * 190.0 + 90.0) + 620.0 + randf_range(-60, 60)
		# unlock: the panel shakes, a coloured flash bursts out, then the reel starts
		SFX.play("upgrade_charge", -6, 1.4)
		var flash := ColorRect.new()
		flash.color = Color(GS.CRATES[crate_type]["color"], 0.0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.add_child(flash)
		var sh := create_tween()
		for k in 8:
			sh.tween_property(clip, "position:x", 6.0 * (1 if k % 2 == 0 else -1), 0.045)
		sh.tween_property(clip, "position:x", 0.0, 0.04)
		sh.parallel().tween_property(flash, "color:a", 0.65, 0.12)
		sh.tween_property(flash, "color:a", 0.0, 0.35)
		sh.tween_callback(flash.queue_free)
		var tw := create_tween()
		tw.tween_interval(0.42)
		tw.tween_property(strip, "position:x", target_x, 5.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		var last_idx := [-1]
		var ticker := func(_v):
			var idx := int((-strip.position.x + 620.0) / 190.0)
			if idx != last_idx[0]:
				last_idx[0] = idx
				SFX.play("tick", -8)
		tw.parallel().tween_method(ticker, 0.0, 1.0, 5.5)
		tw.tween_callback(func():
			var label := _grant(win)
			SFX.play("success")
			res.text = "KAZANDIN: " + label
			res.add_theme_color_override("font_color", win["color"])
			nc.modulate = Color(2, 2, 2)
			nc.create_tween().tween_property(nc, "modulate", Color.WHITE, 0.8)
			_crate_reveal(win, label)
			GS.save_profile()
			open.disabled = false
			refresh.call()
			_refresh_currency()))
	set_showcase(GS.active_set().get("ana", "ak47"))

class Rays extends Control:
	## rotating light rays behind a crate reward
	var col := Color.WHITE
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r: float = max(size.x, size.y) * 0.75
		for i in 18:
			var a0 := t * 0.35 + i * TAU / 18.0
			var pts := PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a0 + 0.09) * r])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.13))
		for k in 6:
			draw_circle(c, 120.0 - k * 18.0, Color(col.r, col.g, col.b, 0.05 + k * 0.025))

func _crate_reveal(it: Dictionary, label: String) -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.0)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(ov)
	var rays := Rays.new()
	rays.col = it["color"]
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(rays)
	var card := _crate_card(it)
	card.custom_minimum_size = Vector2(300, 330)
	ov.add_child(card)
	var vs := get_viewport().get_visible_rect().size
	card.position = vs * 0.5 - Vector2(150, 190)
	card.pivot_offset = Vector2(150, 165)
	card.scale = Vector2(0.2, 0.2)
	card.modulate = Color(3, 3, 3, 0)
	var rar: String = ["SIRADAN", "NADİR", "EPİK", "EFSANEVİ"][clamp(int(it.get("rarity", 0)), 0, 3)]
	var tl := UI.lbl(rar, 30, it["color"], "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	tl.custom_minimum_size = Vector2(700, 0)
	tl.position = Vector2(vs.x * 0.5 - 350, vs.y * 0.5 - 260)
	ov.add_child(tl)
	var nl := UI.lbl(label, 26, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	nl.custom_minimum_size = Vector2(900, 0)
	nl.position = Vector2(vs.x * 0.5 - 450, vs.y * 0.5 + 160)
	ov.add_child(nl)
	var ok := UI.btn("HARİKA!", func(): ov.queue_free(), 22, true, 220, 52)
	ok.position = Vector2(vs.x * 0.5 - 110, vs.y * 0.5 + 220)
	ov.add_child(ok)
	var sp := CPUParticles2D.new()
	sp.position = vs * 0.5
	sp.amount = 140; sp.lifetime = 1.4; sp.one_shot = true; sp.explosiveness = 0.95
	sp.direction = Vector2(0, -1); sp.spread = 180
	sp.initial_velocity_min = 180; sp.initial_velocity_max = 520
	sp.gravity = Vector2(0, 380)
	sp.scale_amount_min = 2.0; sp.scale_amount_max = 5.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(it["color"], 0))
	sp.color_ramp = g
	ov.add_child(sp)
	var tw := ov.create_tween()
	tw.tween_property(ov, "color:a", 0.78, 0.25)
	tw.parallel().tween_property(card, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate", Color(1.6, 1.6, 1.6, 1), 0.3)
	tw.tween_property(card, "scale", Vector2.ONE, 0.2)
	tw.parallel().tween_property(card, "modulate", Color.WHITE, 0.4)
	sp.emitting = true
	if int(it.get("rarity", 0)) >= 2:
		SFX.play("medal", -2)

func _roll_item(t: String = "sokak") -> Dictionary:
	var cd: Dictionary = GS.CRATES.get(t, GS.CRATES["sokak"])
	var r := randf()
	var epic_min: bool = t == "efsane"
	if not epic_min and r < (0.3 if t == "sokak" else 0.18):
		var m: String = ["demir", "demir", "krom", "titanyum", "kobalt"][randi() % 5]
		var n: int = {"demir": 40, "krom": 20, "titanyum": 8, "kobalt": 3}[m]
		return {"type": "mat", "id": m, "n": n, "label": "%d %s" % [n, GS.MATS[m]], "color": Color("c8d2dc"), "rarity": 0}
	if not epic_min and r < (0.5 if t == "sokak" else 0.3):
		var g: int = [500, 800, 1200, 2500][randi() % 4]
		return {"type": "gold", "n": g, "label": "%s Altın" % UI.money(g), "color": UI.GOLD, "rarity": 1}
	var parts: Array = cd.get("parts", [])
	if parts.size() > 0 and randf() < (0.85 if t == "eklenti" else 0.12):
		var pid: String = parts[randi() % parts.size()]
		return {"type": "part", "id": pid, "label": "EKLENTİ: " + GS.PARTS[pid]["name"], "color": Color("7dff6a"), "rarity": 2}
	if (cd["weapons"] as Array).size() > 0 and randf() < 0.14:
		var w: String = cd["weapons"][randi() % cd["weapons"].size()]
		return {"type": "weapon", "id": w, "label": "SİLAH: " + GS.WEAPONS[w]["name"], "color": Color("ff5a5a"), "rarity": 3}
	if (cd["chars"] as Array).size() > 0 and randf() < 0.08:
		var ch: String = cd["chars"][randi() % cd["chars"].size()]
		return {"type": "char", "id": ch, "label": "KARAKTER: " + GS.CHARACTERS[ch]["name"], "color": Color("ff4df0"), "rarity": 3}
	var owned_ids: Array = []
	for id in GS.profile["owned"].keys():
		if not GS.WEAPONS[id].get("throwable", false):
			owned_ids.append(id)
	var wid: String = owned_ids[randi() % owned_ids.size()]
	var pool: Array = (cd["skins"] as Array).duplicate()
	pool.sort_custom(func(a, b): return int(GS.SKINS[a]["rarity"]) < int(GS.SKINS[b]["rarity"]))
	# weighted: common skins appear far more often than legendary ones
	var weights: Array = []
	var tot := 0.0
	for sk in pool:
		var rr: int = int(GS.SKINS[sk]["rarity"])
		var wgt: float = [10.0, 5.0, 2.0, 0.6][rr] if not epic_min else [0.0, 0.0, 4.0, 1.5][rr]
		weights.append(wgt); tot += wgt
	var pick: float = randf() * max(tot, 0.001)
	var sk: String = pool[0]
	for i in pool.size():
		pick -= weights[i]
		if pick <= 0:
			sk = pool[i]; break
	var sd: Dictionary = GS.SKINS[sk]
	return {"type": "skin", "wid": wid, "id": sk, "label": "%s | %s" % [GS.WEAPONS[wid]["name"], sd["name"]], "color": GS.RARITY_COLORS[int(sd["rarity"])], "rarity": int(sd["rarity"])}

func _crate_card(it: Dictionary) -> Control:
	var p := UI.panel(Color(0.07, 0.085, 0.11), it["color"], 6)
	p.custom_minimum_size = Vector2(180, 200)
	var v := UI.vbox(2)
	p.add_child(v)
	var bar := ColorRect.new()
	bar.color = it["color"]
	bar.custom_minimum_size = Vector2(0, 4)
	v.add_child(bar)
	if it["type"] == "skin":
		v.add_child(thumb_rect(it["wid"], it["id"], Vector2(0, 110)))
	elif it["type"] == "weapon":
		v.add_child(thumb_rect(it["id"], "std", Vector2(0, 110)))
	elif it["type"] == "part":
		var pi := PartIcon.new()
		pi.pid = it["id"]
		pi.custom_minimum_size = Vector2(0, 110)
		pi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pi)
	elif it["type"] == "char":
		var l2 := UI.lbl("👤", 64, it["color"], "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		l2.custom_minimum_size = Vector2(0, 110)
		v.add_child(l2)
	else:
		var l := UI.lbl("■" if it["type"] == "mat" else "◉", 60, it["color"], "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(0, 110)
		v.add_child(l)
	var t := UI.lbl(it["label"], 16, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return p

func _grant(it: Dictionary) -> String:
	match it["type"]:
		"part":
			if not GS.profile.has("parts"):
				GS.profile["parts"] = {}
			GS.profile["parts"][it["id"]] = int(GS.profile["parts"].get(it["id"], 0)) + 1
		"mat": GS.profile["mats"][it["id"]] = int(GS.profile["mats"].get(it["id"], 0)) + int(it["n"])
		"gold": GS.profile["gold"] = int(GS.profile["gold"]) + int(it["n"])
		"skin":
			var sk: Array = GS.profile["owned"][it["wid"]]["skins"]
			if not sk.has(it["id"]):
				sk.append(it["id"])
			else:
				GS.profile["gold"] = int(GS.profile["gold"]) + int(GS.SKINS[it["id"]]["price"]) / 2
				return it["label"] + "  (zaten vardı: +%s altın)" % UI.money(int(GS.SKINS[it["id"]]["price"]) / 2)
		"weapon":
			if GS.owned(it["id"]):
				var g: int = int(GS.WEAPONS[it["id"]]["price"]) / 2
				GS.profile["gold"] = int(GS.profile["gold"]) + g
				return it["label"] + "  (zaten vardı: +%s altın)" % UI.money(g)
			GS.profile["owned"][it["id"]] = {"lvl": 0, "skin": "std", "skins": ["std"]}
		"char":
			var own: Array = GS.profile.get("chars", ["takim", "deri", "asker1"])
			if own.has(it["id"]):
				GS.profile["gold"] = int(GS.profile["gold"]) + 1500
				return it["label"] + "  (zaten vardı: +1.500 altın)"
			own.append(it["id"])
			GS.profile["chars"] = own
	return it["label"]

# ================================================================ ROOMS
var fake_rooms: Array = []
func _page_rooms() -> void:
	set_showcase(GS.active_set().get("ana", "ak47"))
	if fake_rooms.is_empty():
		_gen_rooms()
	var p := UI.panel(UI.BG, UI.LINE, 16)
	_margin(p, 28, 18, 560, 24)
	content.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	var th := UI.hbox(8)
	v.add_child(th)
	th.add_child(UI.header("ODA LİSTESİ", 28))
	th.add_child(UI.spacer())
	th.add_child(UI.btn("YENİLE", func(): _gen_rooms(); show_page("rooms"), 18, false, 120, 42))
	th.add_child(UI.btn("ODA KUR (BOTLARLA)", _create_room_dialog, 18, false, 210, 42))
	online.rooms_panel(v)
	var head := UI.hbox(0)
	v.add_child(head)
	var cols := [["No", 70], ["Oda Adı", 360], ["Harita", 180], ["Mod", 200], ["Oyuncu", 110], ["Durum", 130]]
	for c in cols:
		var l := UI.lbl(c[0], 17, UI.DIM, "Rajdhani-Bold")
		l.custom_minimum_size = Vector2(c[1], 30)
		head.add_child(l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var list := UI.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for r in fake_rooms:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_stylebox_override("normal", UI.sb(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 2, 0))
		b.add_theme_stylebox_override("hover", UI.sb(Color(1, 0.55, 0.12, 0.15), UI.ACCENT, 1, 2, 0))
		b.add_theme_stylebox_override("pressed", UI.sb(Color(1, 0.55, 0.12, 0.25), UI.ACCENT, 1, 2, 0))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func(): SFX.play("ui_click", -4); room_cfg = r.duplicate(); show_page("room"))
		var h := UI.hbox(0)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var vals := [str(r["no"]), ("🔒 " if r.get("pass", false) else "") + r["name"], GS.MAPS[r["map"]]["name"], GS.MODES[r["mode"]]["name"], "%d/16" % (r["bots"] + 1), "Bekliyor" if not r.get("playing", false) else "Oyunda"]
		for i in vals.size():
			var l := UI.lbl(vals[i], 19, Color.WHITE if i != 5 else (UI.GREEN if not r.get("playing", false) else UI.ACCENT2), "Rajdhani-SemiBold" if i != 1 else "Rajdhani-Bold")
			l.custom_minimum_size = Vector2(cols[i][1], 46)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(l)
		list.add_child(b)

func _gen_rooms() -> void:
	fake_rooms.clear()
	var names := ["Takılalım gelin", "Sadece AWP!", "Pro Oyuncular", "Gece Operasyonu", "Klan Savaşı - KRTL", "Yeni başlayanlar", "Bıçak düellosu", "Safranbolu sever", "Gemide kapışma", "1v1 gel", "Tetikçiler Kulübü", "Hızlı maç", "Sokak Kralları", "Hile yok!"]
	var maps := GS.MAPS.keys()
	var modes := GS.MODES.keys()
	for i in names.size():
		var md: String = modes[randi() % modes.size()]
		if names[i] == "Sadece AWP!": md = "sniper"
		if names[i] == "Bıçak düellosu": md = "knife"
		var mp: String = maps[randi() % maps.size()]
		if names[i] == "Safranbolu sever": mp = "safranbolu"
		if names[i] == "Gemide kapışma": mp = "gemi"
		fake_rooms.append({"no": randi_range(10, 400), "name": names[i], "map": mp, "mode": md, "bots": randi_range(3, 13), "diff": randi_range(0, 2), "time": [5, 8, 10][randi() % 3], "target": 40 if md != "tdm" and md != "sniper" else 60, "team": "a", "playing": randf() < 0.3, "pass": randf() < 0.15})

func _create_room_dialog() -> void:
	var cfg := {"name": str(GS.profile["name"]) + " odası", "map": "mahalle", "mode": "ffa", "bots": 9, "diff": 1, "time": 8, "target": 40, "team": "a", "no": randi_range(100, 999)}
	_room_dialog(cfg)

func _room_dialog(cfg: Dictionary) -> void:
	var v := _modal(1060, 760)
	var top := UI.hbox(10)
	v.add_child(top)
	top.add_child(UI.header("ODA KUR", 30))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("✕", _close_modal, 20, false, 44, 40))
	var le := LineEdit.new()
	le.text = cfg["name"]
	le.custom_minimum_size = Vector2(0, 44)
	le.text_changed.connect(func(t): cfg["name"] = t)
	v.add_child(UI.lbl("Oda Adı", 18, UI.DIM))
	v.add_child(le)
	v.add_child(UI.lbl("Harita", 18, UI.DIM))
	var mh := UI.hbox(10)
	v.add_child(mh)
	for m in GS.MAPS.keys():
		var sel: bool = cfg["map"] == m
		var b := Button.new()
		b.custom_minimum_size = Vector2(245, 150)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.sb(Color(0.06, 0.07, 0.1), UI.ACCENT if sel else UI.LINE, 3 if sel else 1, 4, 0))
		b.add_theme_stylebox_override("hover", UI.sb(Color(0.08, 0.09, 0.12), UI.ACCENT2, 1, 4, 0))
		b.add_theme_stylebox_override("pressed", UI.sb(Color(0.06, 0.07, 0.1), UI.ACCENT, 2, 4, 0))
		var img := _map_image(m)
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.offset_left = 3; img.offset_right = -3; img.offset_top = 3; img.offset_bottom = -34
		b.add_child(img)
		var l := UI.lbl(GS.MAPS[m]["name"], 20, Color.WHITE if sel else UI.TEXT, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -34
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		b.pressed.connect(func(): cfg["map"] = m; SFX.play("ui_click", -6); _room_dialog(cfg))
		mh.add_child(b)
	v.add_child(UI.lbl("Mod", 18, UI.DIM))
	var mdh := UI.hbox(8)
	v.add_child(mdh)
	for md in GS.MODES.keys():
		mdh.add_child(UI.btn(GS.MODES[md]["name"], func(): cfg["mode"] = md; cfg["target"] = 60 if GS.MODES[md]["teams"] else 40; _room_dialog(cfg), 18, cfg["mode"] == md, 0, 42))
	v.add_child(UI.lbl(GS.MODES[cfg["mode"]]["desc"], 17, UI.ACCENT2))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var bl := UI.lbl("Bot Sayısı: %d" % cfg["bots"], 19, Color.WHITE)
	grid.add_child(bl)
	grid.add_child(UI.slider(1, 15, 1, cfg["bots"], func(x): cfg["bots"] = int(x); bl.text = "Bot Sayısı: %d" % int(x), 420))
	var tl := UI.lbl("Süre: %d dk" % cfg["time"], 19, Color.WHITE)
	grid.add_child(tl)
	grid.add_child(UI.slider(3, 20, 1, cfg["time"], func(x): cfg["time"] = int(x); tl.text = "Süre: %d dk" % int(x), 420))
	var sl := UI.lbl("Hedef Skor: %d" % cfg["target"], 19, Color.WHITE)
	grid.add_child(sl)
	grid.add_child(UI.slider(10, 150, 5, cfg["target"], func(x): cfg["target"] = int(x); sl.text = "Hedef Skor: %d" % int(x), 420))
	grid.add_child(UI.lbl("Bot Zorluğu", 19, Color.WHITE))
	var dh := UI.hbox(6)
	for d in [[0, "Kolay"], [1, "Normal"], [2, "Zor"]]:
		dh.add_child(UI.btn(d[1], func(): cfg["diff"] = d[0]; _room_dialog(cfg), 17, cfg["diff"] == d[0], 120, 38))
	grid.add_child(dh)
	var go := UI.btn("ODAYI OLUŞTUR", func(): room_cfg = cfg; _close_modal(); show_page("room"), 24, true, 0, 58)
	v.add_child(go)

func _map_image(m: String) -> Control:
	var path := "res://assets/ui/map_%s.jpg" % m
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var cr := ColorRect.new()
	cr.color = {"mahalle": Color(0.45, 0.35, 0.25), "safranbolu": Color(0.6, 0.4, 0.25), "gemi": Color(0.3, 0.2, 0.3), "liman": Color(0.25, 0.3, 0.35)}[m]
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cr

# ================================================================ ROOM LOBBY
func _page_room() -> void:
	if room_cfg.is_empty():
		_quick_play()
		return
	soldier.visible = false
	set_showcase(GS.active_set().get("ana", "ak47"))
	var cfg := room_cfg
	var teams: bool = GS.MODES[cfg["mode"]]["teams"]
	room_players.clear()
	room_players.append({"name": str(GS.profile["name"]), "lvl": int(GS.profile["level"]), "team": "a" if teams else "", "you": true, "ready": true})
	var names := GS.BOT_NAMES.duplicate()
	names.shuffle()
	for i in int(cfg["bots"]):
		var t := ""
		if teams:
			t = "b" if i % 2 == 0 else "a"
		room_players.append({"name": names[i % names.size()], "lvl": randi_range(5, 80), "team": t, "you": false, "ready": randf() < 0.7})
	var left := _sets_panel(true)
	left.position = Vector2(28, 18)
	left.custom_minimum_size = Vector2(400, 0)
	content.add_child(left)
	var info := UI.panel(UI.BG, UI.LINE, 0)
	info.position = Vector2(28, 520)
	info.custom_minimum_size = Vector2(400, 0)
	content.add_child(info)
	var iv := UI.vbox(0)
	info.add_child(iv)
	var img := _map_image(cfg["map"])
	img.custom_minimum_size = Vector2(400, 200)
	iv.add_child(img)
	var ig := GridContainer.new()
	ig.columns = 2
	ig.add_theme_constant_override("h_separation", 20)
	var im := MarginContainer.new()
	im.add_theme_constant_override("margin_left", 14); im.add_theme_constant_override("margin_top", 10); im.add_theme_constant_override("margin_bottom", 12)
	im.add_child(ig)
	iv.add_child(im)
	for pair in [["Harita", GS.MAPS[cfg["map"]]["name"]], ["Mod", GS.MODES[cfg["mode"]]["name"]], ["Süre", "%d dk" % cfg["time"]], ["Hedef", str(cfg["target"])], ["Zorluk", ["Kolay", "Normal", "Zor"][cfg["diff"]]], ["Oda No", str(cfg["no"])]]:
		ig.add_child(UI.lbl(pair[0], 17, UI.RED, "Rajdhani-Bold"))
		ig.add_child(UI.lbl(pair[1], 19, Color.WHITE, "Rajdhani-Bold"))
	# center teams
	var center := UI.vbox(10)
	center.anchor_left = 0; center.anchor_right = 1; center.anchor_bottom = 1
	center.offset_left = 452; center.offset_right = -28; center.offset_top = 18; center.offset_bottom = -24
	content.add_child(center)
	var th := UI.hbox(10)
	center.add_child(th)
	th.add_child(UI.header(("ODA %d  •  " % cfg["no"]) + cfg["name"], 26))
	th.add_child(UI.spacer())
	th.add_child(UI.btn("AYARLAR", func(): _room_dialog(cfg), 18, false, 130, 42))
	th.add_child(UI.btn("ODADAN ÇIK", func(): show_page("rooms"), 18, false, 150, 42))
	var tbox := UI.hbox(14)
	tbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(tbox)
	var groups := [["a", GS.TEAMS["a"]], ["b", GS.TEAMS["b"]]] if teams else [["", "OYUNCULAR"]]
	for gtuple in groups:
		var tp := UI.panel(UI.BG, GS.TEAM_COLORS.get(gtuple[0], UI.LINE), 12)
		tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbox.add_child(tp)
		var tv := UI.vbox(4)
		tp.add_child(tv)
		var hp := UI.panel(GS.TEAM_COLORS.get(gtuple[0], UI.ACCENT).darkened(0.45), Color(0, 0, 0, 0), 10, 2)
		hp.add_child(UI.lbl(gtuple[1], 24, Color.WHITE, "RussoOne-Regular"))
		tv.add_child(hp)
		for pl in room_players:
			if gtuple[0] != "" and pl["team"] != gtuple[0]:
				continue
			var row := UI.panel(Color(1, 0.55, 0.12, 0.18) if pl["you"] else Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 8, 2)
			var rh := UI.hbox(10)
			row.add_child(rh)
			rh.add_child(UI.lbl("SVY %d" % pl["lvl"], 16, UI.ACCENT2, "Rajdhani-Bold"))
			rh.add_child(UI.lbl(pl["name"] + ("  (Oda Sahibi)" if pl["you"] else ""), 20, Color.WHITE, "Rajdhani-Bold"))
			rh.add_child(UI.spacer())
			rh.add_child(UI.lbl("HAZIR" if pl["ready"] else "Bekliyor", 16, UI.GREEN if pl["ready"] else UI.DIM, "Rajdhani-Bold"))
			tv.add_child(row)
	# chat + start
	var bottom := UI.hbox(14)
	bottom.custom_minimum_size = Vector2(0, 230)
	center.add_child(bottom)
	var chat_p := UI.panel(Color(0.02, 0.03, 0.05, 0.9), UI.LINE, 10)
	chat_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(chat_p)
	var cv := UI.vbox(6)
	chat_p.add_child(cv)
	var csc := ScrollContainer.new()
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(csc)
	room_chat = UI.vbox(2)
	csc.add_child(room_chat)
	var ce := LineEdit.new()
	ce.placeholder_text = "Mesaj yaz ve Enter'a bas..."
	ce.text_submitted.connect(func(t): if t.strip_edges() != "": _chat(str(GS.profile["name"]), t, Color.WHITE); ce.text = ""; _bot_reply())
	cv.add_child(ce)
	_chat("SİSTEM", "Odaya hoş geldin! Hazır olduğunda BAŞLAT'a bas.", Color("ffd24a"))
	if teams:
		_chat("SİSTEM", "Takım dengesi oyuncu sayısına göre yapıldı.", Color("ffd24a"))
	get_tree().create_timer(1.2).timeout.connect(func(): _bot_reply())
	var sv := UI.vbox(10)
	sv.custom_minimum_size = Vector2(300, 0)
	bottom.add_child(sv)
	if teams:
		sv.add_child(UI.btn("TAKIM DEĞİŞTİR", func(): room_cfg["team"] = "b" if room_cfg.get("team", "a") == "a" else "a"; _chat("SİSTEM", "Takımın: " + GS.TEAMS[room_cfg["team"]], Color("ffd24a")), 20, false, 300, 54))
	var start := UI.btn("BAŞLAT", Callable(), 34, true, 300, 110)
	start.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	start.pressed.connect(func():
		if room_countdown > 0:
			return
		SFX.play("ui_click")
		start.text = "BAŞLIYOR..."
		start.disabled = true
		room_countdown = 5.99)
	sv.add_child(start)

func _chat(who: String, t: String, c: Color) -> void:
	if room_chat == null or not is_instance_valid(room_chat):
		return
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.add_theme_font_override("normal_font", UI.font("Rajdhani-SemiBold"))
	l.add_theme_font_size_override("normal_font_size", 18)
	l.text = "[color=#%s]%s:[/color] %s" % [c.to_html(false) if who != "SİSTEM" else "ffd24a", who, t]
	room_chat.add_child(l)

func _bot_reply() -> void:
	if room_players.size() < 2 or room_chat == null or not is_instance_valid(room_chat):
		return
	var msgs := ["selam", "hazırım", "gg", "bu sefer alıyoruz", "AWP bende", "takım olalım", "sa", "as kardeşim", "hadi başlat", "mahalle haritası efsane", "kafadan vuracağım hepinizi :D"]
	var p: Dictionary = room_players[randi_range(1, room_players.size() - 1)]
	_chat(p["name"], msgs[randi() % msgs.size()], Color("8fd3ff"))

# ================================================================ PROFILE
func _page_profile() -> void:
	set_showcase(GS.active_set().get("ana", "ak47"))
	var p := UI.panel(UI.BG, UI.LINE, 22)
	p.position = Vector2(28, 18)
	p.custom_minimum_size = Vector2(760, 0)
	content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var pr := GS.profile
	v.add_child(UI.lbl(str(pr["name"]), 44, Color.WHITE, "RussoOne-Regular"))
	v.add_child(UI.lbl(_rank(int(pr["level"])) + "   •   Seviye %d" % int(pr["level"]), 24, UI.ACCENT2, "Rajdhani-Bold"))
	v.add_child(UI.bar(float(pr["xp"]), float(GS.xp_for_level(int(pr["level"]))), Color("7fd1ff"), 10))
	var st: Dictionary = pr["stats"]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var acc: float = 100.0 * float(st.get("hits", 0)) / max(1.0, float(st.get("shots", 0)))
	for pair in [["Maç", st["matches"]], ["Galibiyet", st["wins"]], ["Öldürme", st["kills"]], ["Ölüm", st["deaths"]], ["K/D", "%.2f" % (float(st["kills"]) / max(1.0, float(st["deaths"])))], ["Kafadan", st["headshots"]], ["İsabet", "%%%.1f" % acc], ["Kazanma", "%%%d" % int(100.0 * float(st["wins"]) / max(1.0, float(st["matches"])))]]:
		var c := UI.panel(Color(1, 1, 1, 0.04), UI.LINE, 12)
		c.custom_minimum_size = Vector2(170, 0)
		var cv := UI.vbox(0)
		c.add_child(cv)
		cv.add_child(UI.lbl(str(pair[1]), 40, Color.WHITE, "Teko"))
		cv.add_child(UI.lbl(pair[0], 16, UI.DIM, "Rajdhani-Bold"))
		grid.add_child(c)
	v.add_child(UI.header("SİLAH KOLEKSİYONU", 22))
	var owned_n: int = pr["owned"].size()
	var skins_n := 0
	for id in pr["owned"].keys():
		skins_n += pr["owned"][id]["skins"].size() - 1
	v.add_child(UI.lbl("%d / %d silah   •   %d stil" % [owned_n, GS.WEAPONS.size(), skins_n], 20, Color.WHITE))

# ================================================================ SETTINGS
func _page_settings() -> void:
	soldier.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(bg)
	var su := preload("res://scripts/settings_ui.gd").new()
	_margin(su, 120, 24, 120, 24)
	content.add_child(su)


class PartIcon extends Control:
	## vector icons for weapon attachments
	var pid := "sus"
	func _draw() -> void:
		var c := size * 0.5
		var s: float = min(size.x, size.y) * 0.42
		var col := Color("7dff6a")
		var dk := Color(0.12, 0.14, 0.16)
		match pid:
			"sus":
				draw_rect(Rect2(c - Vector2(s, s * 0.22), Vector2(s * 2, s * 0.44)), dk)
				draw_rect(Rect2(c - Vector2(s, s * 0.22), Vector2(s * 2, s * 0.44)), col, false, 2.0)
				for i in 5:
					draw_line(c + Vector2(-s * 0.7 + i * s * 0.35, -s * 0.22), c + Vector2(-s * 0.7 + i * s * 0.35, s * 0.22), col.darkened(0.3), 1.5)
			"kompen":
				draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.28), Vector2(s * 1.2, s * 0.56)), dk)
				draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.28), Vector2(s * 1.2, s * 0.56)), col, false, 2.0)
				for i in 3:
					draw_rect(Rect2(c + Vector2(-s * 0.35 + i * s * 0.3, -s * 0.28), Vector2(s * 0.12, s * 0.2)), col)
			"optik":
				draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.5), Vector2(s * 1.6, s)), dk)
				draw_arc(c, s * 0.38, 0, TAU, 32, col, 2.5)
				draw_circle(c, s * 0.07, Color(1, 0.2, 0.1))
			"sarjor":
				var pts := PackedVector2Array([c + Vector2(-s * 0.35, -s), c + Vector2(s * 0.25, -s), c + Vector2(s * 0.55, s), c + Vector2(-s * 0.05, s)])
				draw_colored_polygon(pts, dk)
				pts.append(pts[0]); draw_polyline(pts, col, 2.0)
			"tutamak":
				draw_rect(Rect2(c - Vector2(s, s * 0.6), Vector2(s * 2, s * 0.3)), dk)
				draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.3), Vector2(s * 0.36, s * 1.2)), dk)
				draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.3), Vector2(s * 0.36, s * 1.2)), col, false, 2.0)
			"lazer":
				draw_rect(Rect2(c - Vector2(s * 0.7, s * 0.25), Vector2(s * 0.9, s * 0.5)), dk)
				draw_line(c + Vector2(s * 0.2, 0), c + Vector2(s * 1.2, 0), Color(1, 0.15, 0.1), 3.0)
				draw_circle(c + Vector2(s * 0.2, 0), s * 0.09, Color(1, 0.3, 0.2))

class CrateIcon extends Control:
	var col := Color.ORANGE
	func _draw() -> void:
		var r := Rect2(Vector2(4, 8), size - Vector2(8, 12))
		draw_rect(r, col.darkened(0.5))
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.32)), col.darkened(0.2))
		draw_rect(r, col, false, 2.0)
		draw_rect(Rect2(r.position.x + r.size.x / 2 - 5, r.position.y + r.size.y * 0.22, 10, 12), Color(1, 0.85, 0.4))
		for k in 3:
			draw_line(Vector2(r.position.x + 6, r.position.y + r.size.y * (0.5 + k * 0.15)), Vector2(r.end.x - 6, r.position.y + r.size.y * (0.5 + k * 0.15)), col.darkened(0.25), 1.0)


# ================================================================ EKLENTİLER
func _page_mods() -> void:
	soldier.visible = true
	var p := UI.panel(UI.BG, UI.LINE, 18)
	_margin(p, 28, 18, 760, 24)
	content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var th := UI.hbox(8)
	v.add_child(th)
	th.add_child(UI.header("EKLENTİLER", 28))
	th.add_child(UI.spacer())
	th.add_child(UI.btn("ÖRNEK EKLENTİ OLUŞTUR", func():
		var d := GS.write_example_mod()
		_toast("Örnek eklenti oluşturuldu. Oyunu yeniden başlatınca yüklenecek.", UI.GREEN)
		OS.shell_open(d.get_base_dir()), 17, false, 0, 40))
	th.add_child(UI.btn("KLASÖRÜ AÇ", func():
		var d := ProjectSettings.globalize_path("user://mods")
		DirAccess.make_dir_recursive_absolute(d)
		OS.shell_open(d), 17, true, 0, 40))
	v.add_child(UI.lbl("Yeni silah, stil, karakter, harita ve kasa ekleyen eklentileri buradan yönet. Eklentiler 'mods' klasöründen okunur; açma/kapama oyunu yeniden başlatınca uygulanır.", 16, UI.DIM, "Rajdhani-SemiBold"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 420)
	v.add_child(sc)
	var list := UI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if GS.mods.is_empty():
		var e := UI.panel(Color(1, 1, 1, 0.03), UI.LINE, 18)
		var ev := UI.vbox(6)
		e.add_child(ev)
		ev.add_child(UI.lbl("Henüz eklenti yok", 24, Color.WHITE, "RussoOne-Regular"))
		ev.add_child(UI.lbl("'ÖRNEK EKLENTİ OLUŞTUR' ile hazır bir paket oluştur, sonra mod.json dosyasını düzenleyerek kendi silahlarını ve stillerini ekle.", 16, UI.DIM))
		list.add_child(e)
	for m in GS.mods:
		var card := UI.panel(Color(0.07, 0.085, 0.11, 0.96), UI.ACCENT if m["enabled"] else UI.LINE, 14)
		var h := UI.hbox(14)
		card.add_child(h)
		var mv := UI.vbox(3)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(mv)
		mv.add_child(UI.lbl("%s   v%s" % [m["name"], m["version"]], 22, Color.WHITE, "RussoOne-Regular"))
		mv.add_child(UI.lbl("Yapımcı: %s   •   %s" % [m["author"], m["desc"]], 15, UI.DIM, "Rajdhani-SemiBold"))
		var c: Dictionary = m.get("counts", {})
		var parts: Array = []
		for k in ["silah", "stil", "karakter", "harita", "kasa"]:
			if int(c.get(k, 0)) > 0:
				parts.append("%d %s" % [int(c[k]), k])
		mv.add_child(UI.lbl(("İçerik: " + ", ".join(parts)) if parts.size() > 0 else ("Kapalı" if not m["enabled"] else "İçerik yok"), 15, UI.ACCENT2, "Rajdhani-Bold"))
		var mid: String = m["id"]
		var on: bool = m["enabled"]
		h.add_child(UI.btn("KAPAT" if on else "AÇ", func():
			GS.set_mod_enabled(mid, not on)
			for mm in GS.mods:
				if mm["id"] == mid:
					mm["enabled"] = not on
			_toast("Değişiklik yeniden başlatınca uygulanacak.", UI.ACCENT2)
			show_page("mods"), 18, not on, 120, 44))
		list.add_child(card)

# ---------------------------------------------------------------- screenshot test hooks
func test_hook(i: int) -> void:
	match i:
		1:
			_inspect(bag_sel if bag_sel != "" else "ak47")
		2:
			GS.profile["parts"] = {"sus": 1, "optik": 1, "sarjor": 2, "tutamak": 1}
			GS.fit_part("ak47", "sus"); GS.fit_part("ak47", "tutamak")
			_parts_dialog("ak47")
		3:
			_crate_reveal({"type": "part", "id": "optik", "label": "EKLENTİ: Holografik Nişangah", "color": Color("7dff6a"), "rarity": 2}, "EKLENTİ: Holografik Nişangah")
		4:
			GS.profile["owned"]["ak47"]["lvl"] = 5
			set_showcase("ak47")
			_inspect("ak47")
