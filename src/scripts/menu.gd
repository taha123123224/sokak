extends Node

var UPGRADE_GLOW := _make_glow_shader()

static func _make_glow_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// v3.5.1 upgrade energy: soft wide light sweep with a hot core + chromatic fringes,
// flowing energy plasma inside the silhouette, hex grid shimmer, pulsing aura and sparkles on the rim
uniform float sweep = -1.0;
uniform vec4 glow_col : source_color = vec4(1.0, 0.7, 0.25, 1.0);
uniform float glow = 0.0;
uniform float outline = 0.0;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; } return v; }
float hexline(vec2 p) {
	p *= vec2(1.0, 1.1547);
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 f = abs(fract(p) - 0.5);
	return smoothstep(0.42, 0.5, max(f.x * 1.5 + f.y, f.y * 2.0));
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float a = t.a;
	vec2 px = TEXTURE_PIXEL_SIZE;
	float m = 0.0;
	for (int r = 1; r <= 4; r++) {
		float rad = float(r) * 4.0;
		for (int k = 0; k < 10; k++) {
			float ang = float(k) * 0.6283;
			m = max(m, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * rad).a * (1.0 - float(r - 1) * 0.22));
		}
	}
	float edge = clamp(m - a, 0.0, 1.0);
	float tm = TIME;
	float lum = dot(t.rgb, vec3(0.3, 0.55, 0.15));
	// diagonal sweep: wide soft halo + hot core + chromatic fringes
	float d = (UV.x + (1.0 - UV.y) * 0.45) - sweep;
	float halo = exp(-d * d * 60.0);
	float core = exp(-d * d * 1400.0);
	vec3 fringe = vec3(exp(-pow(d + 0.012, 2.0) * 2200.0), exp(-d * d * 2200.0), exp(-pow(d - 0.012, 2.0) * 2200.0));
	// flowing plasma inside the weapon
	vec2 q = UV * vec2(7.0, 3.0);
	float fl = fbm(q + vec2(tm * 0.6, -tm * 0.25) + fbm(q * 1.7 - tm * 0.3) * 1.6);
	float plasma = smoothstep(0.55, 0.85, fl) * (0.25 + glow * 0.6);
	float hx = hexline(UV * vec2(38.0, 14.0)) * (0.5 + 0.5 * sin(tm * 3.0 + UV.x * 12.0)) * (0.08 + glow * 0.25 + halo * 0.6);
	vec3 gc = glow_col.rgb;
	vec3 col = t.rgb * (1.0 + glow * 0.1 + halo * 0.35);
	col += gc * (halo * 0.45 + plasma + hx) * a * (0.4 + lum * 0.9);
	col += (vec3(1.0) * core * 0.9 + fringe * gc * 0.7) * a;
	// rim aura: pulsing, noisy, with sparkles travelling along the outline
	float pul = 0.75 + 0.25 * sin(tm * 4.0);
	float rn = fbm(UV * vec2(24.0, 9.0) + vec2(tm * 1.2, 0.0));
	float sp = step(0.985, h21(floor(UV / px / 3.0) + floor(tm * 8.0))) * edge;
	float rim = edge * outline * (0.55 + 0.45 * rn) * pul;
	col = mix(col, gc * 1.6, clamp(rim * 0.8, 0.0, 1.0));
	col += vec3(1.0) * sp * outline * 1.5;
	COLOR = vec4(col, max(a, (rim + sp * outline) * 0.9) * COLOR.a);
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
var mode_chip: Button
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
var local_room := false      # inside a bot room (kept while visiting other pages)
var _room_key := ""
var _room_log: Array = []
var room_countdown := -1.0

var online
var adminp

func _on_announce(t: String) -> void:
	## admin announcement: big banner sliding in under the top bar
	if not is_inside_tree():
		return
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.sb(Color(0.35, 0.05, 0.08, 0.95), Color("ff5d72"), 2, 6, 14))
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.position = Vector2(-460, 100); bar.custom_minimum_size = Vector2(920, 0)
	ui.add_child(bar)
	var h := UI.hbox(12)
	bar.add_child(h)
	h.add_child(UI.lbl("◆ DUYURU", 22, Color("ffd0d6"), "RussoOne-Regular"))
	var l := UI.lbl(t, 20, Color.WHITE, "Rajdhani-Bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	SFX.play("medal", -4)
	bar.modulate.a = 0.0
	var tw := bar.create_tween()
	tw.tween_property(bar, "modulate:a", 1.0, 0.3)
	tw.tween_interval(9.0)
	tw.tween_property(bar, "modulate:a", 0.0, 0.6)
	tw.tween_callback(bar.queue_free)

func _on_gifts(mail: Array) -> void:
	if not is_inside_tree():
		return
	var v := _modal(620, 0)
	v.add_child(UI.header("★ HEDİYE GELDİ!", 30))
	for mm in mail:
		var g: Dictionary = mm.get("gift", {}) if mm.get("gift") is Dictionary else {}
		v.add_child(UI.lbl(str(mm.get("msg", "Yöneticiden hediye!")), 22, UI.GOLD, "Rajdhani-Bold"))
		var parts: Array = []
		if int(g.get("gold", 0)) > 0: parts.append("◉ %s altın" % UI.money(int(g["gold"])))
		for k in (g.get("mats", {}) as Dictionary).keys():
			if int(g["mats"][k]) > 0: parts.append("%d %s" % [int(g["mats"][k]), GS.MATS.get(k, k)])
		if int(g.get("crates", 0)) > 0: parts.append("%d kasa" % int(g["crates"]))
		if str(g.get("weapon", "")) != "": parts.append("SİLAH: %s%s" % [GS.WEAPONS.get(g["weapon"], {}).get("name", g["weapon"]), "" if int(g.get("days", 0)) == 0 else " (%d gün)" % int(g["days"])])
		if str(g.get("skin", "")) != "": parts.append("STİL: " + str(GS.SKINS.get(g["skin"], {}).get("name", g["skin"])))
		v.add_child(_wrap("  •  ".join(parts) if parts.size() > 0 else "Sürpriz!", 19))
	v.add_child(UI.btn("TEŞEKKÜRLER!", func(): _close_modal(); show_page(page), 20, true, 260, 50))
	SFX.play("success")
	_refresh_currency()

func _exit_tree() -> void:
	if online:
		online.cleanup()
	if Online.announced.is_connected(_on_announce): Online.announced.disconnect(_on_announce)
	if Online.gifts_arrived.is_connected(_on_gifts): Online.gifts_arrived.disconnect(_on_gifts)

func _ready() -> void:
	# menus don't need more than 144 FPS: less GPU heat, no fan spin-up, smoother frame pacing
	if GS.fps_limit() == 0 or GS.fps_limit() > 144:
		Engine.max_fps = 144
	online = preload("res://scripts/menu_online.gd").new(self)
	adminp = preload("res://scripts/menu_admin.gd").new(self)
	Online.announced.connect(_on_announce)
	Online.gifts_arrived.connect(_on_gifts)
	if GS.has_meta("crash_notice"):
		var cn := str(GS.get_meta("crash_notice"))
		GS.remove_meta("crash_notice")
		get_tree().create_timer(1.0).timeout.connect(func():
			if not is_inside_tree(): return
			var v := _modal(640, 260)
			v.add_child(UI.header("GÜVENLİ MOD", 26))
			var l := UI.lbl(cn, 19, UI.TEXT, "Rajdhani-SemiBold")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
			v.add_child(UI.btn("TAMAM", _close_modal, 20, true, 0, 50)))
	_build_world()
	var cl := CanvasLayer.new()
	add_child(cl)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = main.theme
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ui)
	if OS.get_environment("KEYART") != "":
		ui.visible = false     # key-art renders for the launcher: scene only
	# soft vignette (edges a touch darker so the panels read on the bright street, centre stays clean)
	var vig := TextureRect.new()
	var vt := GradientTexture2D.new()
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0)); vg.set_color(1, Color(0.01, 0.012, 0.018, 0.5))
	vg.add_point(0.55, Color(0, 0, 0, 0.0))
	vt.gradient = vg; vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.45); vt.fill_to = Vector2(1.05, 1.05)
	vig.texture = vt
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(vig)
	_build_topbar()
	content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 76
	content.offset_right = -72      # friends rail
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(content)
	GS.profile_changed.connect(_refresh_currency)
	SFX.play_music("music_menu")
	show_page(start_page)

# ================================================================ 3D showcase
## Clean modern lobby set (CS-style): dark reflective floor, curved wall with light strips,
## a big screen with the game logo and two team banners. Replaces the old map backdrop.
func _build_lobby_set() -> void:
	var setn := Node3D.new()
	world.add_child(setn)
	var dbg: String = OS.get_environment("SETDBG")
	if dbg.contains("old") or dbg.contains("hidmap"):
		var bd: Node3D = (load("res://assets/maps/safranbolu.glb") as PackedScene).instantiate()
		MatLib.apply(bd)
		bd.position = Vector3(-10.0, -0.02, -18.0)
		world.add_child(bd)
		if dbg.contains("old"):
			return
		bd.visible = false
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = MatLib.tex("concrete_albedo.png")
	fm.normal_enabled = true; fm.normal_texture = MatLib.tex("concrete_normal.png")
	fm.uv1_scale = Vector3(14, 14, 14)
	fm.albedo_color = Color(0.085, 0.09, 0.1)
	fm.roughness = 0.22; fm.metallic = 0.35
	if dbg.contains("plainfloor"):
		fm.roughness = 0.7; fm.metallic = 0.0
	floor_mi.material_override = fm
	if not dbg.contains("nofloor"): setn.add_child(floor_mi)
	# curved back wall (inner side of a cylinder segment)
	var wall := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 9.0; cm.bottom_radius = 9.0; cm.height = 9.0; cm.radial_segments = 64; cm.cap_top = false; cm.cap_bottom = false
	wall.mesh = cm
	var wsh := Shader.new()
	wsh.code = """shader_type spatial;
render_mode cull_front;
uniform vec3 acc = vec3(1.0, 0.55, 0.12);
varying vec3 wp;
void vertex() { wp = VERTEX; }
void fragment() {
	float ang = atan(wp.x, wp.z);
	float strip = smoothstep(0.03, 0.0, abs(fract(ang * 6.0) - 0.5) - 0.47);
	float band = smoothstep(0.06, 0.0, abs(wp.y - 1.2)) + smoothstep(0.04, 0.0, abs(wp.y + 2.0)) * 0.6;
	vec3 base = mix(vec3(0.035, 0.04, 0.05), vec3(0.07, 0.075, 0.09), smoothstep(-4.5, 4.5, wp.y));
	float panel = step(0.5, fract(ang * 12.0)) * 0.012;
	ALBEDO = base + panel;
	ROUGHNESS = 0.6;
	EMISSION = acc * (band * 2.2 + strip * 0.25 * smoothstep(-1.0, 3.0, wp.y));
}"""
	var wm := ShaderMaterial.new(); wm.shader = wsh
	wm.set_shader_parameter("acc", Vector3(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b))
	wall.material_override = wm
	wall.position = Vector3(0.6, 4.0, 1.0)
	if not dbg.contains("nowall"): setn.add_child(wall)
	# big screen with the logo
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(5.2, 2.2)
	scr.mesh = qm
	var sm2 := StandardMaterial3D.new()
	sm2.albedo_texture = load("res://assets/ui/logo.png")
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sm2.alpha_scissor_threshold = 0.4
	sm2.emission_enabled = true; sm2.emission_texture = sm2.albedo_texture; sm2.emission_energy_multiplier = 0.9
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scr.material_override = sm2
	scr.position = Vector3(0.6, 3.6, -7.6)
	if not dbg.contains("noscr"): setn.add_child(scr)
	# team banners left / right
	for side in [[-3.6, GS.TEAM_COLORS.get("a", Color(0.2, 0.45, 1.0))], [4.8, GS.TEAM_COLORS.get("b", Color(1.0, 0.25, 0.2))]]:
		var bn := MeshInstance3D.new()
		var bq := BoxMesh.new(); bq.size = Vector3(1.1, 3.6, 0.04)
		bn.mesh = bq
		var bmm := StandardMaterial3D.new()
		bmm.albedo_color = (side[1] as Color).darkened(0.45)
		bmm.emission_enabled = true; bmm.emission = side[1]; bmm.emission_energy_multiplier = 0.35
		bmm.roughness = 0.8
		bn.material_override = bmm
		bn.position = Vector3(side[0], 2.6, -6.4)
		bn.rotation_degrees.y = 18.0 if side[0] < 0 else -18.0
		setn.add_child(bn)
	# light strips on the floor edge
	for k in 2:
		var ls := MeshInstance3D.new()
		var lb := BoxMesh.new(); lb.size = Vector3(9.0, 0.02, 0.05)
		ls.mesh = lb
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true; lm.emission = UI.ACCENT; lm.emission_energy_multiplier = 3.0; lm.albedo_color = Color.BLACK
		ls.material_override = lm
		ls.position = Vector3(0.6, 0.01, -2.6 - k * 2.2)
		setn.add_child(ls)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.6, 3.0, -4.5); fill.light_color = UI.ACCENT; fill.light_energy = 1.2; fill.omni_range = 9.0
	if not dbg.contains("nolight"): setn.add_child(fill)

## CS2-style lobby: the soldier stands on a sunlit street of one of our maps. The street is a high-quality still
## (rendered offline from the map at ultra, tools: mapshot) drawn as the 3D background; a shadow-catcher floor
## lets the soldier cast a real shadow onto it. Costs a fraction of loading the map itself.
const LOBBY_BGS := ["res://assets/ui/lobby_bg_0.jpg", "res://assets/ui/lobby_bg_1.jpg", "res://assets/ui/lobby_bg_2.jpg"]
const LOBBY_CAM := Vector3(0.5, 1.22, 3.3)
const LOBBY_LOOK := Vector3(0.5, 0.97, 0.0)
var bg_rect: TextureRect
var pedestal: Array = []
var lobby_bg := ""

func _build_backdrop() -> bool:
	var avail: Array = LOBBY_BGS.filter(func(p): return ResourceLoader.exists(p))
	if OS.get_environment("SETDBG") != "" or avail.is_empty():
		return false
	# a different street each day
	lobby_bg = avail[int(Time.get_unix_time_from_system() / 86400.0) % avail.size()]
	if OS.get_environment("LOBBYBG") != "":
		lobby_bg = avail[clampi(int(OS.get_environment("LOBBYBG")), 0, avail.size() - 1)]
	var cl := CanvasLayer.new()
	cl.layer = -1
	add_child(cl)
	bg_rect = TextureRect.new()
	bg_rect.texture = load(lobby_bg)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.offset_left = -24; bg_rect.offset_right = 24; bg_rect.offset_top = -14; bg_rect.offset_bottom = 14
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(bg_rect)
	# shadow catcher: invisible ground that only shows the soldier's shadow (+ a soft contact shadow)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(14, 14)
	g.mesh = pm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode shadow_to_opacity, cull_disabled, depth_draw_never;
uniform vec3 c = vec3(0.5, 0.0, 0.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = vec3(0.0);
	float d = length((wp.xz - c.xz) * vec2(1.0, 1.6));
	ALPHA = 0.42 * exp(-d * d * 7.0);
}"""
	var gm := ShaderMaterial.new(); gm.shader = sh
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = Vector3(0, 0.002, 0)
	world.add_child(g)
	return true

func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4a7bb7")
	sm.sky_horizon_color = Color("d9d2c4")
	sm.ground_horizon_color = Color("d9d2c4")
	sm.ground_bottom_color = Color(0.45, 0.42, 0.38)
	sm.sun_angle_max = 20
	sky.sky_material = sm
	var qi: int = ["low", "medium", "high", "ultra", "uhd"].find(str(GS.settings.get("quality", "high")))
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.75
	e.ambient_light_color = Color(0.72, 0.72, 0.74)
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.35; e.glow_bloom = 0.02; e.glow_hdr_threshold = 1.3
	e.ssao_enabled = qi >= 1
	e.ssao_intensity = 1.4; e.ssao_radius = 0.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.02
	e.adjustment_contrast = 1.04
	we.environment = e
	world.add_child(we)
	var street := _build_backdrop()
	if street:
		e.background_mode = Environment.BG_CANVAS
		e.background_canvas_max_layer = -1
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.022, 0.03)
		e.fog_enabled = true
		e.fog_mode = Environment.FOG_MODE_DEPTH
		e.fog_depth_begin = 6.0; e.fog_depth_end = 30.0
		e.fog_light_color = Color(0.03, 0.035, 0.045)
		_build_lobby_set()
	# warm midday sun from behind-left (matches the street stills), sharp shadow on the ground
	var sun := DirectionalLight3D.new()
	# same sun as the map the still was rendered in, turned by the still's camera heading
	var bi := LOBBY_BGS.find(lobby_bg)
	sun.rotation_degrees = Vector3(-52, [35.0, 215.0, 215.0][bi] if bi >= 0 else -35.0, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.directional_shadow_max_distance = 20.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 0.8
	world.add_child(sun)
	# soft front fill so the face/vest read (no colored rim lights: natural daylight like CS2)
	var key := SpotLight3D.new()
	key.position = Vector3(2.0, 2.6, 4.2)
	key.look_at_from_position(key.position, Vector3(0.5, 1.1, 0))
	key.light_energy = 2.2; key.spot_range = 10; key.spot_angle = 34
	key.light_color = Color(1, 0.97, 0.92)
	key.shadow_enabled = false
	world.add_child(key)
	rim = SpotLight3D.new()
	rim.position = Vector3(-2.5, 2.8, -2.0)
	rim.look_at_from_position(rim.position, Vector3(0.5, 1.3, 0))
	rim.light_energy = 2.5; rim.spot_range = 9; rim.spot_angle = 35
	rim.light_color = Color(1.0, 0.92, 0.8)
	rim.shadow_enabled = false
	world.add_child(rim)
	cam_target = LOBBY_CAM
	cam_look = LOBBY_LOOK
	# soldier, holding the active set's main weapon at low ready
	soldier = _make_soldier(GS.cur_char())
	# weapon pedestal
	var ped := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.42; cm.bottom_radius = 0.46; cm.height = 0.85
	ped.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.21, 0.24); pmat.metallic = 0.6; pmat.roughness = 0.32
	ped.material_override = pmat
	ped.position = Vector3(1.6, 0.425, -0.4)
	world.add_child(ped)
	pedestal.append(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.41; tm.outer_radius = 0.44
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.emission_enabled = true; rmat.emission = UI.ACCENT; rmat.emission_energy_multiplier = 4.0; rmat.albedo_color = Color.BLACK
	ring.material_override = rmat
	ring.position = Vector3(1.6, 0.86, -0.4)
	world.add_child(ring)
	pedestal.append(ring)
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

func _inspect(id: String, skin: String = "") -> void:
	if inspecting and insp_ui:
		insp_ui.queue_free(); insp_ui = null
	inspecting = true
	if studio: studio.visible = true
	insp_rot = Vector2(show_pivot.rotation.y, 0.0)
	insp_zoom = 1.0
	content.visible = false
	set_showcase(id, skin)
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
	var shown_skin: String = skin if skin != "" else GS.wskin(id)
	var ssd: Dictionary = GS.SKINS.get(shown_skin, {"name": "Standart", "rarity": 0})
	v.add_child(UI.lbl(str(w["cls"]).to_upper() + "   •   " + str(ssd["name"]), 18, GS.RARITY_COLORS[int(ssd.get("rarity", 0))] if shown_skin != "std" else UI.ACCENT2, "Rajdhani-Bold"))
	if skin != "" and GS.owned(id) and not (GS.profile["owned"][id]["skins"] as Array).has(skin):
		v.add_child(UI.lbl("ÖNİZLEME — bu stile henüz sahip değilsin", 16, UI.GOLD, "Rajdhani-Bold"))
	elif not GS.owned(id):
		v.add_child(UI.lbl("ÖNİZLEME — bu silaha henüz sahip değilsin", 16, UI.GOLD, "Rajdhani-Bold"))
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
	var lobby_view := cam_target == LOBBY_CAM
	var amt := 0.05 if lobby_view and bg_rect else 0.25
	cam.position = cam.position.lerp(cam_target + Vector3(mp.x * amt, -mp.y * amt * 0.6, 0), min(delta * 3.0, 1.0))
	cam.look_at(cam_look)
	if bg_rect:
		# the street drifts a little against the soldier: cheap depth
		bg_rect.position = bg_rect.position.lerp(Vector2(-24, -14) - mp * Vector2(30, 16), min(delta * 3.0, 1.0))
	_pose_soldier(delta)
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
## CS2-style top bar: a soft dark gradient (no hard box) with icon buttons on the left, the page tabs centred
## with the LOBİ tab in the middle, and currencies + level on the right; friends live in a slim rail on the right edge.
const NAV_L := [["bag", "ÇANTA"], ["market", "MARKET"], ["crate", "KASA"], ["pass", "SEZON"]]
const NAV_R := [["rooms", "ODALAR"], ["leader", "SIRALAMA"], ["mods", "EKLENTİLER"]]
var friends_rail: VBoxContainer

func _build_topbar() -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 72)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.03, 0.88)); g.set_color(1, Color(0.02, 0.025, 0.03, 0.0))
	g.add_point(0.6, Color(0.02, 0.025, 0.03, 0.62))
	gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 64
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = 104
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	# left: icons
	var lh := UI.hbox(2)
	lh.position = Vector2(18, 12)
	bar.add_child(lh)
	var home := NavIcon.make("home", "Lobi", func(): show_page("lobby"))
	nav_btns["lobby_icon"] = home
	lh.add_child(home)
	lh.add_child(NavIcon.make("gear", "Ayarlar", func(): show_page("settings")))
	lh.add_child(NavIcon.make("user", "Profil", func(): show_page("profile")))
	if Online.is_admin:
		lh.add_child(NavIcon.make("shield", "Yönetim", func(): show_page("admin")))
	lh.add_child(NavIcon.make("power", "Oyundan çık", func(): _confirm_quit()))
	lh.add_child(UI.spacer(false, 10))
	mode_chip = UI.btn("", func(): show_page("mode"), 14, false, 0, 34)
	mode_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_chip.tooltip_text = "Oyun modunu değiştir"
	for st in ["normal", "hover", "pressed"]:
		var ms := UI.sb(Color(1, 1, 1, 0.1 if st == "hover" else 0.05), Color(1, 1, 1, 0.16 if st == "normal" else 0.3), 1, 4, 0)
		ms.content_margin_left = 12; ms.content_margin_right = 12
		mode_chip.add_theme_stylebox_override(st, ms)
	lh.add_child(mode_chip)
	# centre: tabs (lobby in the middle, bigger)
	topbar = UI.hbox(0)
	topbar.alignment = BoxContainer.ALIGNMENT_CENTER
	topbar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	topbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	topbar.offset_top = 6
	bar.add_child(topbar)
	var items: Array = NAV_L + [["lobby", "LOBİ"]] + NAV_R
	for i in items.size():
		var it: Array = items[i]
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.18)
			sep.custom_minimum_size = Vector2(1, 18)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			topbar.add_child(sep)
		var big: bool = it[0] == "lobby"
		var b := UI.btn(it[1], func(): show_page(it[0]), 30 if big else 19, false, 0, 56)
		b.add_theme_font_override("font", UI.font("Teko" if big else "Rajdhani-SemiBold"))
		for st in ["normal", "hover", "pressed", "focus"]:
			var sbx := UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
			sbx.content_margin_left = 22 if big else 13; sbx.content_margin_right = sbx.content_margin_left
			b.add_theme_stylebox_override(st, sbx)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_constant_override("outline_size", 0)
		nav_btns[it[0]] = b
		topbar.add_child(b)
	# keep the friends page reachable from code paths that style nav_btns["friends"] (badge)
	# right: rank + level + currencies
	cur_box = UI.hbox(8)
	cur_box.alignment = BoxContainer.ALIGNMENT_END
	cur_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cur_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cur_box.offset_right = -92; cur_box.offset_top = 10
	bar.add_child(cur_box)
	_build_friends_rail()
	_refresh_currency()
	get_viewport().size_changed.connect(_topbar_fit)
	_topbar_fit.call_deferred()

## CS2-style friends rail on the right edge: friend count on top, online friends as avatars below
func _build_friends_rail() -> void:
	var rail := PanelContainer.new()
	var rsb := UI.sb(Color(0.03, 0.035, 0.045, 0.72), Color(0, 0, 0, 0), 0, 0, 0)
	rsb.border_width_left = 1; rsb.border_color = Color(1, 1, 1, 0.06)
	rsb.content_margin_top = 8; rsb.content_margin_bottom = 8; rsb.content_margin_left = 6; rsb.content_margin_right = 6
	rail.add_theme_stylebox_override("panel", rsb)
	rail.anchor_left = 1; rail.anchor_right = 1; rail.anchor_bottom = 1
	rail.offset_left = -72; rail.offset_right = 0
	ui.add_child(rail)
	friends_rail = UI.vbox(8)
	rail.add_child(friends_rail)
	Online.friends_updated.connect(func(_l): _fill_friends_rail())
	_fill_friends_rail()

func _fill_friends_rail() -> void:
	if friends_rail == null or not is_instance_valid(friends_rail):
		return
	UI.clear(friends_rail)
	var all: Array = Online.friends if Online.is_logged_in() else []
	var on: Array = []
	for f in all:
		if f is Dictionary and not bool(f.get("pending", false)) and bool(f.get("online", false)) and str(f.get("status", "")) != "offline":
			on.append(f)
	var top := NavIcon.make("friends", "Arkadaşlar", func(): show_page("friends"))
	top.custom_minimum_size = Vector2(60, 52)
	top.badge = str(on.size()) if Online.is_logged_in() else ""
	nav_btns["friends"] = top
	friends_rail.add_child(top)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08); line.custom_minimum_size = Vector2(0, 1)
	friends_rail.add_child(line)
	for f in on.slice(0, 12):
		var av := FriendAvatar.new()
		av.uname = str(f.get("username", "?"))
		av.status = str(f.get("status", "online"))
		av.custom_minimum_size = Vector2(60, 52)
		av.tooltip_text = "%s  •  %s" % [av.uname, {"match": "Maçta", "room": "Odada", "lobby": "Lobide"}.get(av.status, "Çevrimiçi")]
		av.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: show_page("friends"))
		friends_rail.add_child(av)
	if on.is_empty():
		var add := NavIcon.make("plus", "Arkadaş ekle", func(): show_page("friends"))
		add.custom_minimum_size = Vector2(60, 52)
		add.dim = true
		friends_rail.add_child(add)

class NavIcon extends Control:
	## flat white vector icons (CS2 style): home, gear, user, shield, power, friends, plus
	var kind := "home"
	var on := false
	var dim := false
	var badge := ""
	var _hover := false
	var cb: Callable
	static func make(k: String, tip: String, c: Callable) -> NavIcon:
		var n := NavIcon.new()
		n.kind = k; n.cb = c; n.tooltip_text = tip
		n.custom_minimum_size = Vector2(46, 46)
		n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		n.mouse_entered.connect(func(): n._hover = true; n.queue_redraw())
		n.mouse_exited.connect(func(): n._hover = false; n.queue_redraw())
		n.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				SFX.play("ui_click", -8)
				n.cb.call())
		return n
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.26
		if _hover:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		var col := UI.ACCENT2 if on else (Color(1, 1, 1, 0.45) if dim else (Color.WHITE if _hover else Color(1, 1, 1, 0.82)))
		var w := 2.2
		match kind:
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.05, -r * 0.05), c + Vector2(0, -r * 1.05), c + Vector2(r * 1.05, -r * 0.05)]), col)
				draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.1), Vector2(r * 1.5, r * 1.05)), col)
				draw_rect(Rect2(c + Vector2(-r * 0.2, r * 0.35), Vector2(r * 0.4, r * 0.6)), Color(0.05, 0.06, 0.07))
			"gear":
				for i in 8:
					var a := i * TAU / 8.0
					draw_line(c + Vector2.from_angle(a) * r * 0.7, c + Vector2.from_angle(a) * r * 1.12, col, r * 0.42)
				draw_circle(c, r * 0.78, col)
				draw_circle(c, r * 0.34, Color(0.05, 0.06, 0.07))
			"user":
				draw_circle(c + Vector2(0, -r * 0.42), r * 0.46, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, r * 1.0), c + Vector2(-r * 0.7, r * 0.25), c + Vector2(0, r * 0.05), c + Vector2(r * 0.7, r * 0.25), c + Vector2(r * 0.95, r * 1.0)]), col)
			"friends":
				draw_circle(c + Vector2(-r * 0.45, -r * 0.38), r * 0.4, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.25, r * 0.9), c + Vector2(-r * 1.0, r * 0.2), c + Vector2(-r * 0.45, r * 0.05), c + Vector2(r * 0.1, r * 0.2), c + Vector2(r * 0.35, r * 0.9)]), col)
				draw_circle(c + Vector2(r * 0.55, -r * 0.5), r * 0.32, col.darkened(0.25))
				draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.25, r * 0.0), c + Vector2(r * 0.55, -r * 0.1), c + Vector2(r * 1.05, r * 0.05), c + Vector2(r * 1.25, r * 0.7), c + Vector2(r * 0.5, r * 0.7)]), col.darkened(0.25))
			"shield":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 0.9, -r * 0.65), c + Vector2(r * 0.75, r * 0.4), c + Vector2(0, r * 1.05), c + Vector2(-r * 0.75, r * 0.4), c + Vector2(-r * 0.9, -r * 0.65)]), Color("ff7a8a") if not _hover else Color("ffb0b8"))
			"power":
				draw_arc(c, r * 0.85, deg_to_rad(-55), deg_to_rad(235), 28, col, w, true)
				draw_line(c + Vector2(0, -r * 1.05), c + Vector2(0, -r * 0.15), col, w)
			"plus":
				draw_arc(c, r * 0.95, 0, TAU, 32, col, 1.6, true)
				draw_line(c + Vector2(-r * 0.45, 0), c + Vector2(r * 0.45, 0), col, w)
				draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.45), col, w)
		if badge != "":
			var f: Font = UI.font("Rajdhani-Bold")
			var tw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(f, Vector2(c.x - tw * 0.5, size.y - 2), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))

class FriendAvatar extends Control:
	## round avatar with the friend's initial, coloured by name; green bar = online, orange = in a match
	var uname := "?"
	var status := "online"
	var _hover := false
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())
	func _draw() -> void:
		var h := absi(hash(uname))
		var col := Color.from_hsv(float(h % 360) / 360.0, 0.45, 0.62)
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.4
		if _hover:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), col.darkened(0.35))
		draw_rect(Rect2(c - Vector2(r, r) + Vector2(2, 2), Vector2(r * 2 - 4, r * 2 - 4)), col)
		var f: Font = UI.font("RussoOne-Regular")
		var t := uname.substr(0, 1).to_upper()
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.15)).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + r * 0.42), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.15), Color.WHITE)
		var sc := UI.ACCENT if status == "match" else (Color("7fd1ff") if status == "room" else UI.GREEN)
		draw_rect(Rect2(c.x - r - 5, c.y - r, 3, r * 2), sc)

## narrow screens (4:3, 16:10, small laptops): drop the least important bits so nothing is cut off
var _fit_busy := false
func _topbar_fit() -> void:
	## adaptive: start roomy, then step down (tighter tabs, hide optional chips, smaller tabs, compact
	## level badge) until the centred tabs no longer touch the left icons or the right currency block
	if topbar == null or not is_instance_valid(topbar) or _fit_busy:
		return
	_fit_busy = true
	for lvl in 5:
		_topbar_apply(lvl)
		await get_tree().process_frame
		if not is_instance_valid(topbar):
			break
		var t: Rect2 = topbar.get_global_rect()
		var r: Rect2 = cur_box.get_global_rect() if cur_box and is_instance_valid(cur_box) else Rect2()
		var l_right: float = 0.0
		var lh: Control = topbar.get_parent().get_child(1) if topbar.get_parent().get_child_count() > 1 else null
		if lh and lh is HBoxContainer:
			l_right = lh.get_global_rect().end.x
		if t.position.x > l_right + 12 and (r.size.x <= 0 or t.end.x < r.position.x - 12):
			break
	_fit_busy = false

func _topbar_apply(lvl: int) -> void:
	var fs: int = [19, 18, 17, 15, 14][lvl]
	var big_fs: int = [30, 28, 27, 24, 22][lvl]
	var mg: int = [16, 12, 10, 7, 5][lvl]
	for k in nav_btns.keys():
		var b = nav_btns[k]
		if not is_instance_valid(b) or not (b is Button) or b.get_parent() != topbar:
			continue
		var big: bool = k == "lobby"
		b.add_theme_font_size_override("font_size", big_fs if big else fs)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sbx: StyleBox = b.get_theme_stylebox(st)
			if sbx:
				sbx.content_margin_left = mg + (8 if big else 0)
				sbx.content_margin_right = sbx.content_margin_left
	if cur_box and is_instance_valid(cur_box):
		cur_box.add_theme_constant_override("separation", 8 if lvl < 3 else 4)
		for c in cur_box.get_children():
			if c.has_meta("optional"):
				(c as Control).visible = lvl < 2
			if c is LevelBadge:
				(c as Control).custom_minimum_size.x = 180 if lvl < 4 else 56
				c.set("compact", lvl >= 4)
				c.queue_redraw()

func _confirm_quit() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := UI.panel(Color(0.03, 0.035, 0.05, 0.98), Color(1, 0.35, 0.3, 0.7), 22, 10)
	cc.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	v.add_child(UI.lbl("OYUNDAN ÇIKILSIN MI?", 28, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(UI.btn("ÇIK", func(): get_tree().quit(), 20, true, 180, 50))
	h.add_child(UI.btn("VAZGEÇ", func(): dim.queue_free(), 20, false, 180, 50))

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
	lv.custom_minimum_size = Vector2(180, 48)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.tooltip_text = "Seviye %d  •  %d / %d TP" % [int(p["level"]), int(p["xp"]), GS.xp_for_level(int(p["level"]))]
	cur_box.add_child(lv)
	cur_box.add_child(_cur("gold", UI.money(int(p["gold"])), UI.GOLD, "Altın"))
	# the four upgrade materials share one compact chip
	var mc := PanelContainer.new()
	var msb := UI.sb(Color(0.04, 0.045, 0.05, 0.55), Color(1, 1, 1, 0.1), 1, 4, 0)
	msb.content_margin_left = 6; msb.content_margin_right = 8; msb.content_margin_top = 3; msb.content_margin_bottom = 3
	mc.add_theme_stylebox_override("panel", msb)
	mc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mc.mouse_filter = Control.MOUSE_FILTER_PASS
	mc.set_meta("optional", true)
	var tip := "Silah geliştirme malzemeleri:"
	var mh := UI.hbox(4)
	mh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(mh)
	for k in [["demir", Color("aab3bb")], ["krom", Color("d9ecff")], ["titanyum", Color("62c8ff")], ["kobalt", Color("5b7cff")]]:
		var ic := CurIcon.new()
		ic.kind = "gem"; ic.col = k[1]; ic.mat = k[0]
		ic.custom_minimum_size = Vector2(18, 18)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mh.add_child(ic)
		var n := int(p["mats"].get(k[0], 0))
		var nl := UI.lbl(str(n) if n < 1000 else "%.1fB" % (n / 1000.0), 16, Color.WHITE, "Rajdhani-Bold")
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mh.add_child(nl)
		tip += "\n%s: %d" % [GS.MATS[k[0]], n]
	mc.tooltip_text = tip
	cur_box.add_child(mc)
	cur_box.add_child(_cur("crate", str(int(p.get("crates", 0))), Color("ff8a1f"), "Kasa"))
	_topbar_fit.call_deferred()

func _cur(kind: String, v: String, c: Color, tip: String = "Altın") -> Control:
	var chip := PanelContainer.new()
	var sbx := UI.sb(Color(0.04, 0.045, 0.05, 0.55), Color(1, 1, 1, 0.1), 1, 4, 0)
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
	ic.custom_minimum_size = Vector2(22, 22)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var l := UI.lbl(v, 18, Color.WHITE, "Rajdhani-Bold")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return chip

class CurIcon extends Control:
	## vector currency icons: gold coin, cut gems for upgrade materials, crate
	var kind := "gold"
	var col := Color.WHITE
	var mat := ""
	static var _icons := {}
	func _draw() -> void:
		var c := size * 0.5
		var r: float = min(size.x, size.y) * 0.46
		# painted icons (v3.1) when present: gold coin, crate, one per upgrade material
		var key := mat if mat != "" else kind
		if not _icons.has(key):
			var pth := "res://assets/ui/icons/%s.png" % key
			_icons[key] = load(pth) if ResourceLoader.exists(pth) else null
		if _icons[key]:
			var sz: float = min(size.x, size.y) * 1.12
			draw_texture_rect(_icons[key], Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)
			return
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
	var compact := false
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
		if compact or size.x < x0 + 30:
			return
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
	# while you are in a room, ODALAR takes you back into it (you only leave with the ÇIKIŞ button)
	if p == "rooms":
		if Net.active():
			p = "netroom"
		elif local_room and not room_cfg.is_empty():
			p = "room"
	page = p
	room_countdown = -1
	room_chat = null
	if modal:
		modal.queue_free(); modal = null
	for k in nav_btns.keys():
		var nb = nav_btns[k]
		if not is_instance_valid(nb):
			continue
		var on: bool = k == p or (k == "rooms" and (p == "room" or p == "netroom")) or (k == "lobby_icon" and p == "lobby")
		if nb is NavIcon:
			nb.on = on
			nb.queue_redraw()
			continue
		var b: Button = nb
		b.add_theme_color_override("font_color", Color.WHITE if on else Color(1, 1, 1, 0.68))
		var old_sb: StyleBox = b.get_theme_stylebox("normal")
		var nsb := StyleBoxFlat.new()
		nsb.bg_color = Color(0, 0, 0, 0)
		nsb.border_color = UI.ACCENT
		nsb.border_width_bottom = 3 if on else 0
		nsb.content_margin_left = old_sb.content_margin_left if old_sb else 18
		nsb.content_margin_right = nsb.content_margin_left
		b.add_theme_stylebox_override("normal", nsb)
	UI.clear(content)
	if p != "lobby" and char_view != "" and char_view != GS.cur_char():
		char_view = GS.cur_char()
		_swap_soldier(char_view)
	spin_speed = 0.5
	if studio:
		studio.visible = p in ["bag", "market"]
	cam_target = LOBBY_CAM
	cam_look = LOBBY_LOOK
	soldier.visible = true
	for pd in pedestal:
		pd.visible = p in ["bag", "market"]
	if show_pivot:
		show_pivot.visible = p in ["bag", "market"] or studio == null
	_refresh_mode_chip()
	if mode_chip:
		mode_chip.visible = p != "mode"
	match p:
		"mode": _page_mode()
		"play": _page_play()
		"lobby": _page_lobby()
		"bag": _page_bag()
		"market": _page_market()
		"crate": _page_crate()
		"pass": _page_pass()
		"mods": _page_mods()
		"rooms": _page_rooms()
		"room": _page_room()
		"friends": online.page_friends()
		"admin": adminp.page()
		"leader": online.page_leaderboard()
		"netroom": online.page_room()
		"profile": _page_profile()
		"settings": _page_settings()
	_refresh_currency()
	_update_friend_badge.call_deferred()
	if p != "room" and p != "netroom" and (Net.active() or (local_room and not room_cfg.is_empty())):
		_room_return_bar()

## floating "you are still in a room" bar on every other page
var _fr_badge: Label
func _update_friend_badge() -> void:
	## pending friend requests: red dot on the friends icon of the rail
	if not nav_btns.has("friends") or not is_instance_valid(nav_btns["friends"]):
		return
	var n: int = Online.incoming_count() if Online.is_logged_in() else 0
	var b: Control = nav_btns["friends"]
	if _fr_badge == null or not is_instance_valid(_fr_badge):
		_fr_badge = UI.lbl("", 12, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		_fr_badge.add_theme_stylebox_override("normal", UI.sb(UI.RED, Color(0, 0, 0, 0), 0, 9, 0))
		_fr_badge.custom_minimum_size = Vector2(18, 18)
		_fr_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fr_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(_fr_badge)
	_fr_badge.text = str(n)
	_fr_badge.visible = n > 0
	_fr_badge.position = Vector2(b.size.x - 20, 2)

func _room_return_bar() -> void:
	var online_r := Net.active()
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.sb(Color(0.05, 0.06, 0.08, 0.95), UI.ACCENT, 2, 10, 10))
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 0; bar.anchor_bottom = 0
	bar.offset_left = -300; bar.offset_right = 300; bar.offset_top = 8; bar.offset_bottom = 66
	content.add_child(bar)
	var h := UI.hbox(12)
	bar.add_child(h)
	var dot := UI.lbl("●", 22, UI.GREEN, "Rajdhani-Bold")
	h.add_child(dot)
	var tw := dot.create_tween().set_loops()
	tw.tween_property(dot, "modulate:a", 0.25, 0.6)
	tw.tween_property(dot, "modulate:a", 1.0, 0.6)
	var v := UI.vbox(-4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nm := str(online.room_cfg.get("name", "Oda")) if online_r else str(room_cfg.get("name", "Oda"))
	v.add_child(UI.lbl("ODADASIN: " + nm, 19, Color.WHITE, "Rajdhani-Bold"))
	v.add_child(UI.lbl(("Kod %s  •  %d oyuncu" % [Net.code, Net.members.size()]) if online_r else "Bot odası  •  %s" % str(GS.MAPS.get(room_cfg.get("map", ""), {}).get("name", "")), 14, UI.DIM, "Rajdhani-SemiBold"))
	h.add_child(UI.btn("ODAYA DÖN", func(): show_page("netroom" if Net.active() else "room"), 18, true, 160, 44))

func _margin(c: Control, l: int, t: int, r: int, b: int) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = l; c.offset_top = t; c.offset_right = -r; c.offset_bottom = -b

# ================================================================ sets panel (shared)
func _sets_panel(compact: bool = false) -> Control:
	var p := UI.glass(12) if compact else UI.panel(UI.BG, UI.LINE, 14)
	var v := UI.vbox(7 if compact else 8)
	p.add_child(v)
	if compact:
		var hh := UI.hbox(8)
		hh.add_child(UI.lbl("TEÇHİZAT", 17, Color.WHITE, "Rajdhani-Bold"))
		hh.add_child(UI.spacer())
		var eb := UI.btn("DÜZENLE", func(): show_page("bag"), 13, false, 0, 26)
		hh.add_child(eb)
		v.add_child(hh)
	else:
		v.add_child(UI.header("SETLER", 22))
	var tabs := UI.hbox(4)
	v.add_child(tabs)
	for i in GS.Econ.SET_COUNT:
		var b := UI.btn("Set %d" % (i + 1), func(): GS.profile["active_set"] = i; GS.save_profile(); show_page(page), 14 if compact else 15, GS.profile["active_set"] == i, 0, 32 if compact else 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	var set := GS.active_set()
	for c in GS.SLOT_ORDER:
		var id: String = set.get(c, "")
		var card := UI.panel(Color(1, 1, 1, 0.04) if compact else Color(0.07, 0.085, 0.115, 0.95), Color(1, 1, 1, 0.06) if compact else UI.LINE, 6 if compact else 8)
		var h := UI.hbox(8)
		card.add_child(h)
		if id != "":
			h.add_child(thumb_rect(id, GS.wskin(id), Vector2(150 if not compact else 110, 62 if not compact else 46)))
			var tv := UI.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lv := GS.wlvl(id)
			var nh := UI.hbox(6)
			nh.add_child(UI.lbl(GS.WEAPONS[id]["name"], 18 if compact else 20, Color.WHITE, "Rajdhani-Bold"))
			if lv > 0:
				var bd := preload("res://scripts/ui.gd").lvl_badge(lv, 11)
				bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				nh.add_child(bd)
			tv.add_child(nh)
			var sk: Dictionary = GS.SKINS[GS.wskin(id)]
			tv.add_child(UI.lbl(GS.CATS[c] + "  ·  " + sk["name"], 14 if compact else 15, GS.RARITY_COLORS[int(sk["rarity"])], "Rajdhani-SemiBold"))
			h.add_child(tv)
		v.add_child(card)
	return p

# ================================================================ LOBBY
var char_view := ""

func _char_owned(c: String) -> bool:
	var own: Array = GS.profile.get("chars", ["takim", "deri", "asker1"])
	return c in own or int(GS.CHARACTERS[c]["price"]) == 0

## the lobby soldier is a "puppet" bot: same model, weapon, IK hands and finger grip as in a match,
## with all AI / physics switched off and the rifle held at low ready across the chest
func _make_soldier(cid: String) -> Node3D:
	var wid: String = str(GS.active_set().get("ana", "ak47"))
	if not GS.WEAPONS.has(wid):
		wid = "ak47"
	var b = preload("res://scripts/bot.gd").new()
	b.name = "LobbySoldier"
	world.add_child(b)
	b.set_physics_process(false)
	b.collision_layer = 0; b.collision_mask = 0
	b.setup(GS.char_scene(cid), "", "", 1, wid)
	b.name_tag.visible = false
	if b.gun:
		MatLib.apply(b.gun, GS.wskin(wid))
		GS.parts_visual(b.gun, wid)
		GS.level_glow(b.gun, wid)
	b.position = Vector3(0.5, 0, 0)
	b.rotation.y = deg_to_rad(float(OS.get_environment("LYAW")) if OS.get_environment("LYAW") != "" else 235.0)
	b.set_meta("wid", wid)
	if b.anim and b.anim.has_animation("Idle"):
		b._play("Idle")
	_lobby_left_hand(b)
	return b

## the lobby low-ready lowers both arms together; an IK pass (after the weapon follow) then puts the
## support hand back on the handguard with curled fingers, so the gun is held with both hands
func _lobby_left_hand(b) -> void:
	if b.skel == null or b.gun == null or GS.WEAPONS[str(b.get_meta("wid"))]["cat"] == "tabanca":
		return
	var m := b.gun.find_child("lhand", true, false) as Node3D
	if m == null:
		return
	var t: Node3D = b._wrist_target(m, "L")
	var ik := SkeletonIK3D.new()
	ik.root_bone = b._bone("LeftArm")
	ik.tip_bone = b._bone("LeftHand")
	ik.override_tip_basis = false
	ik.use_magnet = true
	ik.magnet = Vector3(-1.5, -1.0, 0.5)
	b.skel.add_child(ik)
	ik.target_node = ik.get_path_to(t)
	ik.start()
	var gr = preload("res://scripts/hand_grip.gd").new()
	b.skel.add_child(gr)
	gr.setup(b.skel, b.gun, false)
	gr.active = true

func _swap_soldier(c: String) -> void:
	var old_vis := soldier.visible
	soldier.queue_free()
	soldier = _make_soldier(c)
	soldier.visible = old_vis
	# little 'spawn' pop
	soldier.scale = Vector3(0.94, 0.94, 0.94)
	create_tween().tween_property(soldier, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var _idle_t := 0.0
var _idle_next := 3.0
var _idle_act := ""
var _look_goal := Vector2.ZERO
var _head_look := Vector2.ZERO
func _pose_soldier(delta: float) -> void:
	if soldier == null or not is_instance_valid(soldier) or not soldier.visible or not ("aim_node" in soldier):
		return
	# weapon changed in the bag: re-arm
	if str(soldier.get_meta("wid", "")) != str(GS.active_set().get("ana", "ak47")):
		var vis := soldier.visible
		var t := soldier.transform
		soldier.queue_free()
		soldier = _make_soldier(GS.cur_char())
		soldier.transform = t
		soldier.visible = vis
		return
	# living idle (CS2 lobby agents never stand still): breathing, a slow weight shift, the head
	# looking around, and every few seconds a weapon check (gun brought up and turned to the light)
	var tt := Time.get_ticks_msec() * 0.001
	_idle_t += delta
	if _idle_t > _idle_next:
		_idle_t = 0.0
		_idle_act = ["check", "look", "look", "shift"][randi() % 4]
		_idle_next = randf_range(4.5, 8.0)
		_look_goal = Vector2(randf_range(-0.5, 0.45), randf_range(-0.12, 0.1))
	var ph: float = clampf(_idle_t / 2.6, 0.0, 1.0)
	var bump: float = sin(ph * PI)   # 0 -> 1 -> 0 over the action
	bump = bump * bump * (3.0 - 2.0 * bump)
	var br := sin(tt * 1.5) * 0.018 + sin(tt * 0.37) * 0.01
	var drop := 0.6 + br
	var tw := 0.35 + sin(tt * 0.23) * 0.04
	var lean := 0.05 + sin(tt * 1.5 + 0.6) * 0.012
	var look := Vector2(sin(tt * 0.31) * 0.08, sin(tt * 0.53) * 0.03)
	match _idle_act:
		"check":
			drop -= 0.38 * bump
			tw += 0.12 * bump
			look += Vector2(0.35, 0.22) * bump
		"look":
			look += _look_goal * bump
			tw += _look_goal.x * 0.25 * bump
		"shift":
			lean += 0.03 * bump
	_head_look = _head_look.lerp(look, minf(delta * 4.0, 1.0))
	if soldier.twist:
		soldier.twist.lean = float(OS.get_environment("LLEAN")) if OS.get_environment("LLEAN") != "" else lean
		soldier.twist.twist = float(OS.get_environment("LTWIST")) if OS.get_environment("LTWIST") != "" else tw
		soldier.twist.arms_drop = float(OS.get_environment("LDROP")) if OS.get_environment("LDROP") != "" else drop
		soldier.twist.head_yaw = _head_look.x
		soldier.twist.head_pitch = _head_look.y
	# weight shift: hips sway a couple of centimetres
	soldier.position.x = 0.5 + sin(tt * 0.42) * 0.012
	soldier.position.z = sin(tt * 0.42 + 1.3) * 0.006
	soldier._follow_chest(delta)

## CS2-style agent card art (assets/ui/agents/<id>.jpg), cropped to fill
func _agent_art(cid: String, sz: Vector2, face: bool = false) -> TextureRect:
	var pth := "res://assets/ui/agents/%s.jpg" % cid
	if not ResourceLoader.exists(pth):
		return null
	var tr := TextureRect.new()
	tr.texture = load(pth)
	if face:
		# head-and-shoulders crop for small slots
		var at := AtlasTexture.new()
		at.atlas = tr.texture
		var w: float = tr.texture.get_width()
		at.region = Rect2(0, w * 0.02, w, w * 0.62)
		tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = sz
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _char_picker() -> Control:
	if char_view == "":
		char_view = GS.cur_char()
	var ids: Array = GS.CHARACTERS.keys()
	var c: String = char_view
	var info: Dictionary = GS.CHARACTERS[c]
	var p := UI.glass(12, 4)
	var v := UI.vbox(6)
	p.add_child(v)
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.lbl("KARAKTER", 18, Color.WHITE, "Rajdhani-Bold"))
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
	var portrait := _agent_art(c, Vector2(0, 150), true)
	if portrait:
		mid.add_child(portrait)
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
			var r: Dictionary = await _act("buy_char", {"id": c})
			if r["ok"]:
				SFX.play("buy")
				show_page("lobby"), 20, false, 0, 44)
		b.disabled = int(GS.profile["gold"]) < price
		v.add_child(b)
	return p

func _page_lobby() -> void:
	## CS2-style lobby: the soldier on a sunlit street is the centrepiece; a compact player card under him,
	## the loadout on the left, news + missions on the right and the PLAY block bottom-right — all frosted glass.
	var p := GS.profile
	var ri: Dictionary = GS.rank_info(int(p.get("rp", 0)))
	# ---- left: loadout
	var left := UI.vbox(10)
	left.position = Vector2(26, 14)
	left.custom_minimum_size = Vector2(372, 0)
	content.add_child(left)
	left.add_child(_sets_panel(true))
	left.add_child(_char_picker())
	# ---- centre bottom: player card (click -> profile)
	var card := UI.glass(12, 4)
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 1; card.anchor_bottom = 1
	card.offset_left = -170; card.offset_right = 170; card.offset_top = -132; card.offset_bottom = -26
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Profilini aç"
	card.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: show_page("profile"))
	content.add_child(card)
	var ch := UI.hbox(12)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ch)
	var em := TextureRect.new()
	em.texture = ri["icon"]; em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; em.custom_minimum_size = Vector2(72, 72)
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(em)
	var cv := UI.vbox(1)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(cv)
	var nm := UI.lbl(str(p["name"]), 24, Color.WHITE, "RussoOne-Regular")
	nm.clip_text = true
	cv.add_child(nm)
	cv.add_child(UI.lbl("%s  ·  SEVİYE %d  ·  %d RP" % [str(ri["name"]).to_upper(), int(p["level"]), int(ri["rp"])], 14, ri["color"], "Rajdhani-Bold"))
	var xb := UI.bar(float(p["xp"]), float(GS.xp_for_level(int(p["level"]))), Color("7fd1ff"), 4)
	xb.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 2, 0))
	cv.add_child(xb)
	var st: Dictionary = p["stats"]
	cv.add_child(UI.lbl("%d MAÇ   ·   %d GALİBİYET   ·   %.2f K/D" % [int(st["matches"]), int(st["wins"]), float(st["kills"]) / max(1.0, float(st["deaths"]))], 13, UI.DIM, "Rajdhani-Bold"))
	for c in cv.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- right: news + missions
	var right := UI.vbox(10)
	right.anchor_left = 1; right.anchor_right = 1
	right.offset_left = -396; right.offset_right = -22; right.offset_top = 14
	content.add_child(right)
	var news := PanelContainer.new()
	var nsb := UI.sb(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.1), 1, 4, 0)
	news.add_theme_stylebox_override("panel", nsb)
	news.custom_minimum_size = Vector2(374, 196)
	news.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	right.add_child(news)
	var nimg := TextureRect.new()
	var nimg_p := "res://assets/ui/pass_banner.jpg"
	nimg.texture = load(nimg_p) if ResourceLoader.exists(nimg_p) else load("res://assets/ui/map_liman.jpg")
	nimg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nimg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	news.add_child(nimg)
	var shade := TextureRect.new()
	var sgt := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(0, 0, 0, 0.0)); sg.set_color(1, Color(0, 0, 0, 0.88))
	sgt.gradient = sg; sgt.fill_from = Vector2(0, 0.2); sgt.fill_to = Vector2(0, 1)
	shade.texture = sgt; shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	news.add_child(shade)
	var nm2 := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		nm2.add_theme_constant_override("margin_" + side, 14)
	news.add_child(nm2)
	var nv := UI.vbox(0)
	nv.alignment = BoxContainer.ALIGNMENT_END
	nm2.add_child(nv)
	nv.add_child(UI.lbl("YENİ GÜNCELLEME  ·  v" + str(preload("res://scripts/updater.gd").VERSION), 13, UI.ACCENT2, "Rajdhani-Bold"))
	nv.add_child(UI.lbl("KURT ADAM MODU", 26, Color.WHITE, "RussoOne-Regular"))
	nv.add_child(_wrap("Gece çöktü: 3'e bas, kurda dönüş! Yeni SEZON PASOSU ile 30 seviye ödül, hareketli özel eklentiler ve yeni silah seviye rozetleri.", 15))
	var mp := UI.glass(12, 4)
	right.add_child(mp)
	var mv := UI.vbox(7)
	mp.add_child(mv)
	var mh := UI.hbox(8)
	mv.add_child(mh)
	mh.add_child(UI.lbl("GÜNLÜK GÖREVLER", 17, Color.WHITE, "Rajdhani-Bold"))
	mh.add_child(UI.spacer())
	var ndone := 0
	for ms in GS.MISSIONS:
		if p["missions"]["claimed"].has(ms["id"]): ndone += 1
	mh.add_child(UI.lbl("%d / %d" % [ndone, GS.MISSIONS.size()], 15, UI.DIM, "Rajdhani-Bold"))
	for ms in GS.MISSIONS:
		var have := int(p["missions"].get(ms["key"], 0))
		var done := have >= int(ms["goal"])
		var claimed: bool = p["missions"]["claimed"].has(ms["id"])
		var rh := UI.hbox(8)
		var ml := UI.lbl(("✓ " if claimed else "") + str(ms["text"]), 15, UI.DIM if claimed else Color(1, 1, 1, 0.92), "Rajdhani-SemiBold")
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.clip_text = true
		rh.add_child(ml)
		if done and not claimed:
			rh.add_child(UI.btn("ÖDÜLÜ AL", func(): _claim(ms), 13, true, 0, 26))
		elif not claimed:
			rh.add_child(UI.lbl("%d/%d" % [min(have, int(ms["goal"])), int(ms["goal"])], 14, UI.ACCENT2, "Rajdhani-Bold"))
		mv.add_child(rh)
		if not claimed:
			var pb0 := UI.bar(min(have, int(ms["goal"])), int(ms["goal"]), UI.GREEN if done else UI.ACCENT, 3)
			pb0.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 2, 0))
			mv.add_child(pb0)
	# ---- PLAY block (bottom right)
	var pb := UI.vbox(8)
	pb.anchor_left = 1; pb.anchor_right = 1; pb.anchor_top = 1; pb.anchor_bottom = 1
	pb.offset_left = -396; pb.offset_right = -22; pb.offset_top = -176; pb.offset_bottom = -26
	content.add_child(pb)
	var mode_txt := "ÇEVRİMİÇİ" if GS.play_mode == "online" else "BOT MAÇI"
	var info := UI.lbl(mode_txt + "  ·  " + str(GS.MAPS.size()) + " HARİTA  ·  " + str(GS.MODES.size()) + " MOD", 14, Color(1, 1, 1, 0.8), "Rajdhani-Bold")
	info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	info.add_theme_constant_override("shadow_outline_size", 4)
	pb.add_child(info)
	var quick := UI.btn("OYNA", func(): show_page("play"), 44, true, 374, 82)
	quick.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	pb.add_child(quick)
	var pulse := quick.create_tween().set_loops()
	pulse.tween_property(quick, "modulate", Color(1.1, 1.1, 1.1), 1.0).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(quick, "modulate", Color(1, 1, 1), 1.0).set_trans(Tween.TRANS_SINE)
	var h2 := UI.hbox(8)
	pb.add_child(h2)
	var b1 := UI.btn("ODA LİSTESİ", func(): show_page("rooms"), 17, false, 0, 42)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := UI.btn("ODA KUR", _create_room_dialog, 17, false, 0, 42)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(b1); h2.add_child(b2)

func _wrap(t: String, s: int) -> Label:
	var l := UI.lbl(t, s, UI.TEXT, "Rajdhani-Medium")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	return l

func _rank(l: int) -> String:
	var ranks := ["ER", "ONBAŞI", "ÇAVUŞ", "ÜSTÇAVUŞ", "ASTSUBAY", "TEĞMEN", "ÜSTEĞMEN", "YÜZBAŞI", "BİNBAŞI", "YARBAY", "ALBAY", "GENERAL"]
	return ranks[min(l / 5, ranks.size() - 1)]

func _claim(ms: Dictionary) -> void:
	var r: Dictionary = await _act("claim_mission", {"id": ms["id"]})
	if r["ok"]:
		SFX.play("buy")
	show_page("lobby")

# ================================================================ PLAY (CS2-style matchmaking panel)
var play_sel_mode := "tdm"
var play_maps: Array = []        # empty = any map
var play_diff := 1
var play_bots := 9
var play_time := 8

func _page_play() -> void:
	## CS2: one screen, mode tabs on top, a grid of maps to tick, one big GO button. No room, no chat.
	soldier.visible = false
	var online_mode: bool = GS.play_mode == "online"
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.018, 0.024, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dim)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 90)
	root.add_theme_constant_override("margin_top", 26)
	root.add_theme_constant_override("margin_bottom", 34)
	content.add_child(root)
	var v := UI.vbox(18)
	root.add_child(v)
	# header
	var hh := UI.hbox(16)
	v.add_child(hh)
	hh.add_child(UI.lbl("OYNA", 52, Color.WHITE, "Teko"))
	var sub := UI.lbl("ÇEVRİMİÇİ MAÇ" if online_mode else "BOTLARLA MAÇ", 20, UI.ACCENT2, "Rajdhani-Bold")
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(sub)
	hh.add_child(UI.spacer())
	var sw := UI.btn("MODU DEĞİŞTİR ⇄", func(): show_page("mode"), 16, false, 0, 40)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(sw)
	# mode tabs (CS2 top tabs)
	var tabs := UI.hbox(0)
	v.add_child(tabs)
	for md in GS.MODES.keys():
		var on: bool = md == play_sel_mode
		var b := Button.new()
		b.text = str(GS.MODES[md]["name"]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
		b.add_theme_font_size_override("font_size", 20)
		var nsb := UI.sb(Color(1, 1, 1, 0.08) if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
		nsb.content_margin_left = 26; nsb.content_margin_right = 26
		nsb.border_width_bottom = 3; nsb.border_color = UI.ACCENT if on else Color(1, 1, 1, 0.08)
		b.add_theme_stylebox_override("normal", nsb)
		var hsb := nsb.duplicate()
		hsb.bg_color = Color(1, 1, 1, 0.12)
		b.add_theme_stylebox_override("hover", hsb)
		b.add_theme_stylebox_override("pressed", hsb)
		b.add_theme_color_override("font_color", Color.WHITE if on else Color(1, 1, 1, 0.6))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(func(): SFX.play("ui_click", -8); play_sel_mode = md; show_page("play"))
		tabs.add_child(b)
	v.add_child(UI.lbl(str(GS.MODES[play_sel_mode]["desc"]), 18, UI.DIM, "Rajdhani-SemiBold"))
	# body: map grid + summary
	var body := UI.hbox(26)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var gv := UI.vbox(10)
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(gv)
	var gh := UI.hbox(10)
	gv.add_child(gh)
	gh.add_child(UI.lbl("HARİTALAR", 18, Color.WHITE, "Rajdhani-Bold"))
	gh.add_child(UI.lbl("(boş bırakırsan rastgele)" if play_maps.is_empty() else "%d seçili" % play_maps.size(), 16, UI.DIM, "Rajdhani-SemiBold"))
	gh.add_child(UI.spacer())
	gh.add_child(_chip("TÜMÜNÜ TEMİZLE", false, func(): play_maps.clear(); show_page("play")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	gv.add_child(grid)
	for mid in GS.MAPS.keys():
		grid.add_child(_play_map_card(mid))
	# summary column
	var side := UI.glass(20, 4)
	side.custom_minimum_size = Vector2(430, 0)
	body.add_child(side)
	var sv := UI.vbox(12)
	side.add_child(sv)
	sv.add_child(UI.lbl("MAÇ AYARI", 16, UI.DIM, "Rajdhani-Bold"))
	sv.add_child(UI.lbl(str(GS.MODES[play_sel_mode]["name"]), 34, Color.WHITE, "RussoOne-Regular"))
	var mn: Array = []
	for m in play_maps:
		mn.append(GS.MAPS[m]["name"])
	sv.add_child(UI.lbl("Harita: " + (", ".join(mn) if mn.size() > 0 else "Rastgele"), 17, UI.TEXT, "Rajdhani-SemiBold"))
	if not online_mode:
		sv.add_child(UI.lbl("ZORLUK", 15, UI.DIM, "Rajdhani-Bold"))
		var dh := UI.hbox(6)
		sv.add_child(dh)
		for i in 3:
			dh.add_child(_chip(["KOLAY", "NORMAL", "ZOR"][i], play_diff == i, func(): play_diff = i; show_page("play"), 120))
		sv.add_child(UI.lbl("BOT SAYISI", 15, UI.DIM, "Rajdhani-Bold"))
		var bh := UI.hbox(6)
		sv.add_child(bh)
		for n in [5, 7, 9, 11, 13]:
			bh.add_child(_chip(str(n), play_bots == n, func(): play_bots = n; show_page("play"), 66))
		if play_sel_mode != "sabotaj":
			sv.add_child(UI.lbl("SÜRE", 15, UI.DIM, "Rajdhani-Bold"))
			var th := UI.hbox(6)
			sv.add_child(th)
			for n in [5, 8, 10, 15]:
				th.add_child(_chip("%d dk" % n, play_time == n, func(): play_time = n; show_page("play"), 80))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(sp)
	var go := UI.btn("BAŞLAT", func(): _play_go(), 40, true, 0, 84)
	go.add_theme_font_override("font", UI.font("Teko"))
	sv.add_child(go)
	var adv := UI.btn("Gelişmiş oda kur (sohbet, takım, şifre)", func(): show_page("rooms"), 15, false, 0, 36)
	sv.add_child(adv)

func _play_map_card(mid: String) -> Control:
	var on: bool = mid in play_maps
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, 205)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var nsb := UI.sb(Color(0, 0, 0, 0.3), UI.ACCENT if on else Color(1, 1, 1, 0.08), 3 if on else 1, 4, 0)
	card.add_theme_stylebox_override("normal", nsb)
	var hsb := nsb.duplicate()
	hsb.border_color = UI.ACCENT2 if on else Color(1, 1, 1, 0.45)
	card.add_theme_stylebox_override("hover", hsb)
	card.add_theme_stylebox_override("pressed", hsb)
	var img := TextureRect.new()
	var pth := "res://assets/ui/map_%s.jpg" % mid
	if ResourceLoader.exists(pth):
		img.texture = load(pth)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.offset_left = 3; img.offset_top = 3; img.offset_right = -3; img.offset_bottom = -3
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.modulate = Color.WHITE if on or play_maps.is_empty() else Color(0.62, 0.62, 0.62)
	card.add_child(img)
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0)); g.set_color(1, Color(0, 0, 0, 0.85))
	gt.gradient = g; gt.fill_from = Vector2(0, 0.35); gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.offset_left = 3; shade.offset_top = 3; shade.offset_right = -3; shade.offset_bottom = -3
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shade)
	var nm := UI.lbl(str(GS.MAPS[mid]["name"]).to_upper(), 24, Color.WHITE, "RussoOne-Regular")
	nm.position = Vector2(16, 146)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(nm)
	var sz := UI.lbl(str(GS.MAPS[mid]["size"]).to_upper() + " HARİTA", 14, UI.DIM, "Rajdhani-Bold")
	sz.position = Vector2(17, 178)
	sz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sz)
	# tick box (CS2 map checkbox)
	var tick := UI.lbl("✔" if on else "", 20, Color.BLACK, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", UI.sb(UI.ACCENT if on else Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.6), 1, 3, 0))
	tp.custom_minimum_size = Vector2(30, 30)
	tp.position = Vector2(14, 14)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.add_child(tick)
	card.add_child(tp)
	card.pressed.connect(func():
		SFX.play("ui_click", -8)
		if on: play_maps.erase(mid)
		else: play_maps.append(mid)
		show_page("play"))
	return card

func _play_go() -> void:
	SFX.play("beep_go", -4)
	if GS.play_mode == "online":
		online.quick_join()
		return
	var pool: Array = play_maps if play_maps.size() > 0 else GS.MAPS.keys()
	var md := play_sel_mode
	if md == "kurt" and play_maps.size() == 0:
		pool = ["ayvadisi"]     # Kurt Adam has its own map
	var tgt := 6 if md == "sabotaj" else (99 if md == "gungame" else (60 if GS.MODES[md]["teams"] else 40))
	var cfg := {"name": "Hızlı Oyun", "map": pool[randi() % pool.size()], "mode": md, "bots": play_bots, "diff": play_diff,
		"time": play_time, "target": tgt, "team": "a", "no": randi_range(100, 999)}
	room_cfg = cfg
	main.start_match(cfg)

func _quick_play() -> void:
	if GS.play_mode == "online":
		online.quick_join()
		return
	var maps := GS.MAPS.keys()
	var cfg := {"name": "Hızlı Oyun", "map": maps[randi() % maps.size()], "mode": ["ffa", "tdm", "tdm", "ffa", "gungame"][randi() % 5], "bots": 9, "diff": 1, "time": 8, "target": 40, "team": "a", "no": randi_range(100, 999)}
	if cfg["mode"] == "tdm": cfg["target"] = 60
	if cfg["mode"] == "gungame": cfg["target"] = 99
	room_cfg = cfg
	show_page("room")

# ================================================================ BAG (Çanta)
func _page_bag() -> void:
	## modern inventory: 3D weapon in the middle, details + skins on the right, weapon carousel at the bottom
	cam_target = Vector3(1.6, 1.38, 1.65)
	cam_look = Vector3(1.6, 1.28, -0.4)
	soldier.visible = false
	var left := _sets_panel(true)
	left.position = Vector2(24, 12)
	left.custom_minimum_size = Vector2(380, 0)
	content.add_child(left)
	var ids: Array = []
	for id in GS.WEAPONS.keys():
		if GS.WEAPONS[id].get("hidden", false):
			continue
		if GS.owned(id) and (bag_cat == "tum" or GS.WEAPONS[id]["cat"] == bag_cat):
			ids.append(id)
	if bag_sel == "" or not GS.owned(bag_sel):
		bag_sel = ids[0] if ids.size() > 0 else "ak47"
	set_showcase(bag_sel)
	var w: Dictionary = GS.WEAPONS[bag_sel]
	var lvl := GS.wlvl(bag_sel)
	# ---- bottom carousel
	var bot := UI.panel(Color(0.02, 0.025, 0.035, 0.93), UI.LINE, 10)
	bot.anchor_left = 0; bot.anchor_right = 1; bot.anchor_top = 1; bot.anchor_bottom = 1
	bot.offset_left = 24; bot.offset_right = -24; bot.offset_top = -232; bot.offset_bottom = -14
	content.add_child(bot)
	var bv := UI.vbox(6)
	bot.add_child(bv)
	var th := UI.hbox(6)
	bv.add_child(th)
	th.add_child(UI.lbl("ÇANTA", 24, Color.WHITE, "RussoOne-Regular"))
	th.add_child(UI.lbl("%d silah" % ids.size(), 16, UI.DIM, "Rajdhani-Bold"))
	th.add_child(UI.spacer(false, 16))
	for c in [["tum", "TÜMÜ"], ["ana", "ANA SİLAH"], ["tabanca", "TABANCA"], ["bicak", "BIÇAK"], ["bomba", "BOMBA"]]:
		th.add_child(UI.btn(c[1], func(): bag_cat = c[0]; show_page("bag"), 15, bag_cat == c[0], 0, 32))
	var csc := ScrollContainer.new()
	csc.custom_minimum_size = Vector2(0, 160)
	csc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(csc)
	var row := UI.hbox(8)
	csc.add_child(row)
	for id in ids:
		var wc := _weapon_card(id, id == bag_sel, func(): bag_sel = id; show_page("bag"))
		wc.custom_minimum_size = Vector2(250, 150)
		row.add_child(wc)
	# ---- right detail column
	var det := UI.panel(Color(0.025, 0.03, 0.045, 0.94), GS.RARITY_COLORS[int(GS.SKINS[GS.wskin(bag_sel)]["rarity"])].darkened(0.3), 16, 2)
	det.anchor_left = 1; det.anchor_right = 1; det.anchor_top = 0; det.anchor_bottom = 1
	det.offset_left = -470; det.offset_right = -24; det.offset_top = 12; det.offset_bottom = -244
	content.add_child(det)
	var dv := UI.vbox(6)
	det.add_child(dv)
	var nh := UI.hbox(8)
	dv.add_child(nh)
	nh.add_child(UI.lbl(str(w["name"]).to_upper(), 30, Color.WHITE, "RussoOne-Regular"))
	if lvl > 0:
		nh.add_child(UI.lbl("+%d" % lvl, 26, UI.GOLD, "Teko"))
	var tl: String = GS.wtime_label(bag_sel)
	dv.add_child(UI.lbl(str(w["cls"]).to_upper() + "   •   " + ("⏱ " + tl if tl != "" else "∞ SÜRESİZ"), 15, Color("ff9a4a") if tl != "" else UI.DIM, "Rajdhani-Bold"))
	dv.add_child(_lvl_pips(lvl, 18))
	var st := GS.full_stats(bag_sel)
	if not w.get("melee", false) and not w.get("throwable", false):
		var sgd := GridContainer.new()
		sgd.columns = 1
		dv.add_child(sgd)
		for r in _stat_rows(bag_sel).slice(0, 5):
			sgd.add_child(_stat(r[0], r[1], r[2], true))
		if st.has("ability"):
			dv.add_child(_wrap("★ " + str(st["ability"]), 15))
	var in_set: bool = GS.active_set().get(w["cat"], "") == bag_sel
	var ab := GridContainer.new()
	ab.columns = 2
	ab.add_theme_constant_override("h_separation", 6); ab.add_theme_constant_override("v_separation", 6)
	dv.add_child(ab)
	ab.add_child(UI.btn("✔ KUŞANILDI" if in_set else "KUŞAN (Set %d)" % (int(GS.profile["active_set"]) + 1), func(): GS.active_set()[w["cat"]] = bag_sel; GS.save_profile(); SFX.play("equip"); show_page("bag"), 17, not in_set, 212, 44))
	var up_btn := UI.btn("YÜKSELT ⬆" if lvl < GS.MAX_LVL else "MAKS. SEVİYE", func(): _upgrade_dialog(bag_sel), 17, false, 212, 44)
	up_btn.disabled = lvl >= GS.MAX_LVL
	ab.add_child(up_btn)
	ab.add_child(UI.btn("ÖZELLEŞTİR ⚙", func(): _parts_dialog(bag_sel), 16, false, 212, 40))
	ab.add_child(UI.btn("◎ 3D İNCELE", func(): _inspect(bag_sel), 16, false, 212, 40))
	# skins: owned first, then locked (click a locked one to preview / buy in the market)
	var owned_sk: Array = GS.profile["owned"][bag_sel]["skins"]
	dv.add_child(UI.lbl("STİLLER  (%d / %d)" % [owned_sk.size(), GS.SKINS.size()], 16, UI.ACCENT2, "Rajdhani-Bold"))
	var ssc := ScrollContainer.new()
	ssc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ssc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(ssc)
	var sg := GridContainer.new()
	sg.columns = 3
	sg.add_theme_constant_override("h_separation", 6); sg.add_theme_constant_override("v_separation", 6)
	ssc.add_child(sg)
	var order: Array = []
	for sk in GS.SKINS.keys():
		if owned_sk.has(sk): order.append(sk)
	for sk in GS.SKINS.keys():
		if not owned_sk.has(sk): order.append(sk)
	for sk in order:
		var sd: Dictionary = GS.SKINS[sk]
		var have := owned_sk.has(sk)
		var on: bool = GS.wskin(bag_sel) == sk
		var rc: Color = GS.RARITY_COLORS[int(sd["rarity"])]
		var b := Button.new()
		b.custom_minimum_size = Vector2(134, 92)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.sb(rc.darkened(0.6) if on else Color(0.06, 0.07, 0.09), rc if on else rc.darkened(0.55), 2 if on else 1, 4, 0))
		b.add_theme_stylebox_override("hover", UI.sb(rc.darkened(0.55), rc, 1, 4, 0))
		var bvv := UI.vbox(0)
		bvv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bvv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bvv)
		var tr := thumb_rect(bag_sel, sk, Vector2(0, 58))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not have:
			tr.modulate = Color(1, 1, 1, 0.45)
		bvv.add_child(tr)
		var nl := UI.lbl(("" if have else "⊘ ") + str(sd["name"]), 13, Color.WHITE if have else UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		nl.clip_text = true
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bvv.add_child(nl)
		var bar := ColorRect.new(); bar.color = rc; bar.custom_minimum_size = Vector2(0, 3); bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bvv.add_child(bar)
		b.mouse_entered.connect(func(): set_showcase(bag_sel, sk))
		b.mouse_exited.connect(func(): set_showcase(bag_sel))
		b.pressed.connect(func():
			if have:
				GS.profile["owned"][bag_sel]["skin"] = sk
				GS.save_profile(); SFX.play("equip", -4); show_page("bag")
			else:
				_inspect(bag_sel, sk))
		sg.add_child(b)

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
		var tl: String = GS.wtime_label(id)
		if tl == "":
			bh.add_child(UI.lbl("∞ Süresiz", 15, UI.DIM, "Rajdhani-SemiBold"))
		else:
			bh.add_child(UI.lbl("⏱ " + tl, 16, Color("ff9a4a"), "Rajdhani-Bold"))
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
					var r: Dictionary = await _act("buy_part", {"id": pid})
					if not r["ok"]: return
					GS.fit_part(id, pid)
					SFX.play("buy"); _refresh_currency(); set_showcase(id); _parts_dialog(id), 15, false, 0, 34)
			cv.add_child(b)
	v.add_child(UI.lbl("Eklentileri Eklenti Paketi kasasından kazanabilir ya da buradan satın alabilirsin. Bir eklentiye sahip olunca tüm uyumlu silahlarına takabilirsin.", 15, UI.DIM, "Rajdhani-SemiBold"))

class UpgStage extends Control:
	## upgrade stage behind the weapon: tier glow, 7 level segments on a turning ring,
	## a charge arc while upgrading and a shockwave + flash on the result
	var col := Color(0.3, 0.75, 1.0)
	var lvl := 0
	var charge := 0.0
	var burst := -1.0
	var flash := 0.0
	var spin := 0.25
	var t := 0.0
	var bg: Texture2D = preload("res://assets/ui/upgrade/bg.jpg")
	var ring: Texture2D = preload("res://assets/ui/upgrade/ring.png")
	func _process(d: float) -> void:
		t += d
		if burst >= 0.0:
			burst += d
			if burst > 1.4: burst = -1.0
		flash = maxf(flash - d * 2.2, 0.0)
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.y * 0.46, 170.0)
		var p := 0.6 + charge * 0.9 + flash
		# v3.4.1 painted workshop behind the stage (cover fit, darkened) + rotating holo ring
		if bg:
			var ts := bg.get_size()
			var k0: float = maxf(size.x / ts.x, size.y / ts.y)
			var ds := ts * k0
			draw_texture_rect(bg, Rect2((size - ds) * 0.5 + Vector2(0, ds.y * 0.06), ds), false, Color(0.55 + flash * 0.4, 0.58 + flash * 0.4, 0.62 + flash * 0.4, 1))
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.35))
		if ring:
			var rr := r * (2.05 + charge * 0.25 + flash * 0.3)
			draw_set_transform(c, -t * (0.15 + charge * 2.5), Vector2.ONE)
			draw_texture_rect(ring, Rect2(-Vector2(rr, rr) * 0.5, Vector2(rr, rr)), false, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.35 + charge * 0.5 + flash * 0.5))
			draw_set_transform(c, t * 0.08, Vector2.ONE * 0.62)
			draw_texture_rect(ring, Rect2(-Vector2(rr, rr) * 0.5, Vector2(rr, rr)), false, Color(col.r, col.g, col.b, 0.18 + charge * 0.4))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for k in 12:
			draw_circle(c, r * 2.2 - k * r * 0.16, Color(col.r, col.g, col.b, 0.012 * p * (k + 1) * 0.5))
		for i in 18:
			var a0 := t * 0.1 + i * TAU / 18.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r * 2.6, c + Vector2.from_angle(a0 + 0.045) * r * 2.6]), Color(col.r, col.g, col.b, 0.02 * p))
		var rot := t * (spin + charge * 4.0)
		draw_arc(c, r * 1.12, 0, TAU, 96, Color(1, 1, 1, 0.05), 1.5, true)
		for i in 7:
			var a := rot + i * TAU / 7.0
			var on := i < lvl
			var cc := col if on else Color(1, 1, 1, 0.12)
			draw_arc(c, r, a, a + TAU / 7.0 - 0.14, 18, cc, 6.0 if on else 4.0, true)
			if on:
				draw_arc(c, r, a, a + TAU / 7.0 - 0.14, 18, Color(cc.r, cc.g, cc.b, 0.25), 14.0, true)
		for i in 36:
			var a := -rot * 0.6 + i * TAU / 36.0
			var l := 8.0 if i % 3 == 0 else 4.0
			draw_line(c + Vector2.from_angle(a) * (r * 0.86), c + Vector2.from_angle(a) * (r * 0.86 - l), Color(col.r, col.g, col.b, 0.35), 1.5, true)
		if charge > 0.0:
			draw_arc(c, r * 1.12, -PI / 2, -PI / 2 + TAU * charge, 96, col.lightened(0.3), 4.0, true)
			draw_arc(c, r * 1.12, -PI / 2, -PI / 2 + TAU * charge, 96, Color(col.r, col.g, col.b, 0.3), 12.0, true)
			var hp := c + Vector2.from_angle(-PI / 2 + TAU * charge) * r * 1.12
			draw_circle(hp, 6.0, Color(1, 1, 1, 0.9))
		if burst >= 0.0:
			var k := burst / 1.4
			draw_arc(c, r * (0.4 + k * 2.6), 0, TAU, 96, Color(col.r, col.g, col.b, (1.0 - k) * 0.9), 10.0 * (1.0 - k) + 2.0, true)
			draw_arc(c, r * (0.2 + k * 1.8), 0, TAU, 96, Color(1, 1, 1, (1.0 - k) * 0.5), 4.0, true)
		if flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(col.r, col.g, col.b, flash * 0.35))

class UpgTrack extends Control:
	## +1 .. +7 level path; reached nodes lit in their tier colour, the next one pulses
	var lvl := 0
	var t := 0.0
	var pop := -1
	var pop_t := 0.0
	func _process(d: float) -> void:
		t += d
		pop_t += d
		queue_redraw()
	func _draw() -> void:
		var n := 7
		var x0 := 30.0
		var x1 := size.x - 30.0
		var y := size.y * 0.42
		var f := get_theme_default_font()
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.1), 4.0, true)
		if lvl > 0:
			draw_line(Vector2(x0, y), Vector2(lerpf(x0, x1, float(lvl - 1) / (n - 1)), y), GS.lvl_color(lvl), 4.0, true)
		for i in n:
			var lv := i + 1
			var x := lerpf(x0, x1, float(i) / (n - 1))
			var c: Color = GS.lvl_color(lv)
			var reached := lv <= lvl
			var rr := 13.0
			if lv == pop and pop_t < 0.6:
				rr += sin(pop_t / 0.6 * PI) * 10.0
			if lv == lvl + 1:
				var pu := 0.5 + 0.5 * sin(t * 4.0)
				draw_circle(Vector2(x, y), rr + 6.0 + pu * 4.0, Color(c.r, c.g, c.b, 0.18 * pu))
				draw_arc(Vector2(x, y), rr, 0, TAU, 32, c, 2.5, true)
				draw_circle(Vector2(x, y), rr - 3.0, Color(0.05, 0.06, 0.08))
			elif reached:
				draw_circle(Vector2(x, y), rr + 5.0, Color(c.r, c.g, c.b, 0.25))
				draw_circle(Vector2(x, y), rr, c)
			else:
				draw_circle(Vector2(x, y), rr, Color(0.12, 0.13, 0.16))
				draw_arc(Vector2(x, y), rr, 0, TAU, 32, Color(1, 1, 1, 0.12), 1.5, true)
			var txt := "+%d" % lv
			var fs := 15
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(x - tw / 2, y + 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.06) if reached else (Color.WHITE if lv == lvl + 1 else Color(1, 1, 1, 0.35)))
			var tn: String = ["", "SİBER", "SİBER", "MOR", "MOR", "KOR", "KOR", "ALTIN"][lv]
			if lv % 2 == 1 or lv == 7:
				var w2 := f.get_string_size(tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(f, Vector2(x - w2 / 2, y + 34), tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(c.r, c.g, c.b, 0.85 if reached else 0.4))

const UPG_ICON := {"HASAR": "dmg", "ŞARJÖR": "mag", "GERİ TEPME": "recoil", "PARILTI": "glow"}
func _upg_stat(title: String, a: String, b: String, better: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(1, 1, 1, 0.035), Color(1, 0.62, 0.2, 0.25) if better else Color(1, 1, 1, 0.08), 1, 10, 8))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox(6)
	p.add_child(row)
	var ip := "res://assets/ui/upgrade/%s.png" % str(UPG_ICON.get(title, ""))
	if ResourceLoader.exists(ip):
		var ic := TextureRect.new()
		ic.texture = load(ip)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(40, 40); ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		if better:
			var itw := ic.create_tween().set_loops()
			itw.tween_property(ic, "modulate", Color(1.35, 1.25, 1.1), 0.7).set_trans(Tween.TRANS_SINE)
			itw.tween_property(ic, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.lbl(title, 13, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	var h := UI.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(UI.lbl(a, 22, Color(1, 1, 1, 0.75), "Teko"))
	h.add_child(UI.lbl("➜", 18, UI.ACCENT, "Rajdhani-Bold"))
	h.add_child(UI.lbl(b, 24, UI.GREEN if better else Color.WHITE, "Teko"))
	return p

func _upgrade_dialog(id: String) -> void:
	var lvl := GS.wlvl(id)
	var cost := GS.upgrade_cost(lvl)
	var v := _modal(940, 700)
	var top := UI.hbox(10)
	v.add_child(top)
	var tv0 := UI.vbox(-4)
	top.add_child(tv0)
	tv0.add_child(UI.lbl("SİLAH YÜKSELTME", 14, UI.ACCENT2, "Rajdhani-Bold"))
	var nh := UI.hbox(10)
	tv0.add_child(nh)
	nh.add_child(UI.lbl(str(GS.WEAPONS[id]["name"]).to_upper(), 32, Color.WHITE, "RussoOne-Regular"))
	if lvl > 0:
		nh.add_child(UI.lvl_badge(lvl, 18))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("✕", _close_modal, 20, false, 44, 40))
	# ---- stage: tier ring + weapon
	var nc: Color = GS.lvl_color(lvl + 1)
	var stage := UpgStage.new()
	stage.custom_minimum_size = Vector2(0, 270)
	stage.col = GS.lvl_color(maxi(lvl, 1))
	stage.lvl = lvl
	stage.clip_contents = true
	v.add_child(stage)
	var tr := thumb_rect(id, GS.wskin(id), Vector2(620, 220))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tr)
	var gm := ShaderMaterial.new()
	gm.shader = UPGRADE_GLOW
	gm.set_shader_parameter("sweep", -1.0)
	gm.set_shader_parameter("glow_col", stage.col)
	gm.set_shader_parameter("glow", 0.25 if lvl > 0 else 0.08)
	gm.set_shader_parameter("outline", 0.45 if lvl > 0 else 0.15)
	tr.material = gm
	# idle: a slow light pass every few seconds so the weapon never looks static
	var itw := tr.create_tween().set_loops()
	itw.tween_interval(1.6)
	itw.tween_method(func(x): gm.set_shader_parameter("sweep", x), -0.5, 1.7, 1.4).set_trans(Tween.TRANS_SINE)
	var big := UI.lbl("", 64, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	big.add_theme_constant_override("outline_size", 10)
	big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	big.modulate.a = 0.0
	stage.add_child(big)
	var place := func():
		tr.size = Vector2(620, 220)
		tr.position = (stage.size - tr.size) / 2
		tr.pivot_offset = tr.size / 2
		big.size = Vector2(stage.size.x, 90)
		big.position = Vector2(0, stage.size.y / 2 - 45)
		big.pivot_offset = big.size / 2
	stage.resized.connect(place)
	var sparks := CPUParticles2D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 140
	sparks.lifetime = 1.3
	sparks.explosiveness = 0.95
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 30.0
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180
	sparks.initial_velocity_min = 120; sparks.initial_velocity_max = 520
	sparks.gravity = Vector2(0, 340)
	sparks.damping_min = 40; sparks.damping_max = 90
	sparks.scale_amount_min = 2.0; sparks.scale_amount_max = 5.0
	stage.add_child(sparks)
	stage.resized.connect(func(): sparks.position = stage.size / 2)
	# ---- level path
	var track := UpgTrack.new()
	track.lvl = lvl
	track.custom_minimum_size = Vector2(0, 66)
	v.add_child(track)
	# ---- stat changes
	var s0 := GS.stats_for(id, lvl)
	var s1 := GS.stats_for(id, mini(lvl + 1, GS.MAX_LVL))
	var sh := UI.hbox(10)
	v.add_child(sh)
	sh.add_child(_upg_stat("HASAR", str(s0["dmg"]), str(s1["dmg"]), int(s1["dmg"]) > int(s0["dmg"])))
	sh.add_child(_upg_stat("ŞARJÖR", str(s0.get("mag", 0)), str(s1.get("mag", 0)), int(s1.get("mag", 0)) > int(s0.get("mag", 0))))
	sh.add_child(_upg_stat("GERİ TEPME", "%d%%" % int(100 - lvl * 3), "%d%%" % int(100 - (lvl + 1) * 3), true))
	sh.add_child(_upg_stat("PARILTI", ["YOK", "SİBER", "SİBER", "MOR", "MOR", "KOR", "KOR", "ALTIN"][lvl], ["YOK", "SİBER", "SİBER", "MOR", "MOR", "KOR", "KOR", "ALTIN"][mini(lvl + 1, 7)], lvl + 1 in [1, 3, 5, 7]))
	# ---- cost
	var ch := UI.hbox(10)
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
		var p := UI.panel(Color(1, 1, 1, 0.04), (r[2] as Color).darkened(0.4) if have >= need else UI.RED.darkened(0.3), 10)
		var pv := UI.vbox(-2)
		p.add_child(pv)
		var ci := CurIcon.new()
		if r[0] == "gold":
			ci.kind = "gold"
		else:
			ci.kind = "gem"; ci.mat = str(r[0])
		ci.custom_minimum_size = Vector2(34, 34)
		ci.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pv.add_child(ci)
		pv.add_child(UI.lbl(UI.money(need), 24, Color.WHITE if have >= need else UI.RED, "Teko", HORIZONTAL_ALIGNMENT_CENTER))
		pv.add_child(UI.lbl("%s · %s" % [r[1], UI.money(have)], 13, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		p.custom_minimum_size = Vector2(118, 0)
		ch.add_child(p)
	# ---- chance + action
	var bh := UI.hbox(14)
	v.add_child(bh)
	var cv := UI.vbox(4)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(cv)
	var chance := int(cost["chance"])
	var risky: bool = lvl >= GS.Econ.FAIL_DROP_FROM
	var cc := UI.GREEN if chance >= 75 else (UI.GOLD if chance >= 50 else UI.RED)
	var chh := UI.hbox(8)
	cv.add_child(chh)
	chh.add_child(UI.lbl("BAŞARI ŞANSI", 15, UI.DIM, "Rajdhani-Bold"))
	chh.add_child(UI.lbl("%%%d" % chance, 22, cc, "Teko"))
	chh.add_child(UI.spacer())
	chh.add_child(UI.lbl("⚠ Başarısızlıkta seviye 1 DÜŞER" if risky else "Başarısızlıkta seviye düşmez", 14, UI.RED if risky else UI.DIM, "Rajdhani-Bold"))
	var pb := UI.bar(0, 1, nc, 12)
	pb.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 6, 0))
	pb.add_theme_stylebox_override("fill", UI.sb(nc, Color(0, 0, 0, 0), 0, 6, 0))
	cv.add_child(pb)
	var res := UI.lbl("", 22, UI.GOLD, "RussoOne-Regular")
	cv.add_child(res)
	var go := UI.btn("YÜKSELT  ➜  +%d" % (lvl + 1), Callable(), 24, true, 280, 64)
	go.icon = preload("res://assets/ui/upgrade/hammer.png")
	go.expand_icon = false
	go.add_theme_constant_override("icon_max_width", 40)
	go.disabled = not GS.can_afford(cost) or lvl >= GS.MAX_LVL
	bh.add_child(go)
	go.pressed.connect(func():
		go.disabled = true
		itw.kill()
		var ur: Dictionary = await _act("upgrade", {"wid": id})
		if not ur["ok"]:
			go.disabled = false
			return
		var up: Dictionary = ur["res"]
		SFX.play("upgrade_charge", -2)
		spin_speed = 9.0
		stage.col = nc
		gm.set_shader_parameter("glow_col", nc)
		res.text = "YÜKSELTİLİYOR..."
		res.add_theme_color_override("font_color", nc)
		# charging: arc fills, ring spins up, light sweeps over the weapon faster and faster, the weapon trembles
		var gtw := create_tween()
		for k in 5:
			gtw.tween_method(func(x): gm.set_shader_parameter("sweep", x), -0.4, 1.6, 0.6 - k * 0.09)
		var tw := create_tween()
		tw.tween_method(func(x):
			stage.charge = x
			pb.value = x
			gm.set_shader_parameter("glow", x * 0.9)
			gm.set_shader_parameter("outline", x)
			tr.position = (stage.size - tr.size) / 2 + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * x * 3.0
			rim.light_energy = 9.0 + x * 70.0, 0.0, 1.0, 2.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			spin_speed = 0.5
			rim.light_energy = 9
			stage.charge = 0.0
			tr.position = (stage.size - tr.size) / 2
			var ok := bool(up.get("success", false))
			var nl := int(up.get("lvl", lvl + 1 if ok else lvl))
			if ok:
				SFX.play("success")
				stage.lvl = nl; stage.burst = 0.0; stage.flash = 1.0
				track.lvl = nl; track.pop = nl; track.pop_t = 0.0
				big.text = "+%d" % nl
				big.add_theme_color_override("font_color", nc.lightened(0.35))
				big.add_theme_color_override("font_outline_color", Color(nc.r * 0.25, nc.g * 0.25, nc.b * 0.25, 0.9))
				big.scale = Vector2(2.4, 2.4)
				var t2 := big.create_tween()
				t2.tween_property(big, "modulate:a", 1.0, 0.12)
				t2.parallel().tween_property(big, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t2.tween_interval(0.9)
				t2.tween_property(big, "modulate:a", 0.0, 0.5)
				t2.parallel().tween_property(big, "position:y", big.position.y - 40, 0.5)
				res.text = "BAŞARILI!  %s  +%d" % [str(GS.WEAPONS[id]["name"]).to_upper(), nl]
				res.add_theme_color_override("font_color", nc.lightened(0.2))
				var sg := Gradient.new()
				sg.set_color(0, Color(1, 1, 1, 1)); sg.add_point(0.25, nc.lightened(0.3)); sg.set_color(sg.get_point_count() - 1, Color(nc.r, nc.g, nc.b, 0))
				sparks.color_ramp = sg
				sparks.restart()
				gm.set_shader_parameter("glow_col", nc)
				gm.set_shader_parameter("glow", 2.4)
				gm.set_shader_parameter("outline", 1.8)
				var t3 := tr.create_tween()
				t3.tween_property(tr, "scale", Vector2(1.08, 1.08), 0.12)
				t3.tween_property(tr, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				t3.parallel().tween_method(func(x): gm.set_shader_parameter("sweep", x), -0.4, 1.6, 0.6)
				t3.parallel().tween_method(func(x): gm.set_shader_parameter("glow", x), 2.4, 0.25, 1.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				t3.parallel().tween_method(func(x): gm.set_shader_parameter("outline", x), 1.8, 0.35, 2.0).set_ease(Tween.EASE_OUT)
			else:
				SFX.play("fail")
				stage.col = UI.RED; stage.flash = 0.8; stage.lvl = nl
				track.lvl = nl
				gm.set_shader_parameter("glow_col", Color(1.0, 0.15, 0.1))
				var t5 := tr.create_tween()
				t5.tween_method(func(x): gm.set_shader_parameter("glow", x), 1.4, 0.0, 0.9)
				t5.parallel().tween_method(func(x): gm.set_shader_parameter("outline", x), 1.2, 0.0, 0.9)
				big.text = "✖"
				big.add_theme_color_override("font_color", UI.RED)
				big.scale = Vector2(1.8, 1.8)
				var t6 := big.create_tween()
				t6.tween_property(big, "modulate:a", 1.0, 0.1)
				t6.parallel().tween_property(big, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t6.tween_interval(0.7)
				t6.tween_property(big, "modulate:a", 0.0, 0.4)
				res.text = "BAŞARISIZ!" if nl >= lvl else "BAŞARISIZ!  SEVİYE DÜŞTÜ: +%d" % nl
				res.add_theme_color_override("font_color", UI.RED)
				var t4 := v.create_tween()
				for k in 8:
					t4.tween_property(v, "position:x", 12.0 * (1 if k % 2 == 0 else -1) * (1.0 - k / 8.0), 0.035)
				t4.tween_property(v, "position:x", 0.0, 0.04)
			_refresh_currency()
			get_tree().create_timer(2.2).timeout.connect(func(): if page == "bag": show_page("bag"))))

# ================================================================ SEZON PASOSU (v3.5.1)
func _pass_reward_name(it: Dictionary) -> String:
	match str(it.get("type", "")):
		"gold": return "%s ALTIN" % UI.money(int(it["n"]))
		"mat": return "%d %s" % [int(it["n"]), str(GS.MATS.get(it["id"], it["id"])).to_upper()]
		"crate": return ("%d× " % int(it.get("n", 1)) if int(it.get("n", 1)) > 1 else "") + str(GS.CRATES.get(it["id"], {}).get("name", "Kasa")).to_upper()
		"skin": return "%s | %s" % [str(GS.WEAPONS.get(it["wid"], {}).get("name", it["wid"])).to_upper(), str(GS.SKINS.get(it["id"], {}).get("name", it["id"]))]
		"weapon": return str(GS.WEAPONS.get(it["id"], {}).get("name", it["id"])).to_upper() + ("  •  KALICI" if int(it.get("days", 0)) == 0 else "  •  %d GÜN" % int(it["days"]))
		"char": return "AJAN: " + str(GS.CHARACTERS.get(it["id"], {}).get("name", it["id"])).to_upper()
	return ""

func _pass_reward_art(it: Dictionary, sz: Vector2) -> Control:
	match str(it.get("type", "")):
		"gold", "mat":
			var ci := CurIcon.new()
			if it["type"] == "gold": ci.kind = "gold"
			else: ci.kind = "gem"; ci.mat = str(it["id"])
			ci.custom_minimum_size = sz * 0.62
			return ci
		"crate":
			var tx := _crate_tex(str(it["id"]))
			if tx == null and str(it["id"]) == "sokak" and ResourceLoader.exists("res://assets/ui/icons/crate.png"):
				tx = load("res://assets/ui/icons/crate.png")
			if tx:
				var tr := TextureRect.new(); tr.texture = tx
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = sz
				return tr
		"skin":
			var v := UI.vbox(2)
			var th := thumb_rect(str(it["wid"]), str(it["id"]), Vector2(sz.x, sz.y * 0.62))
			th.custom_minimum_size = Vector2(sz.x, sz.y * 0.62)
			v.add_child(th)
			return v
		"weapon":
			var th2 := thumb_rect(str(it["id"]), "std", Vector2(sz.x, sz.y * 0.6))
			th2.custom_minimum_size = Vector2(sz.x, sz.y * 0.6)
			return th2
		"char":
			var ag := _agent_art(str(it["id"]), sz * Vector2(0.75, 1.0), true)
			if ag:
				return ag
	return Control.new()

func _pass_reward_col(it: Dictionary) -> Color:
	match str(it.get("type", "")):
		"skin": return GS.RARITY_COLORS[clampi(int(GS.SKINS.get(it["id"], {}).get("rarity", 0)), 0, 3)]
		"crate": return GS.CRATES.get(it["id"], {}).get("color", UI.ACCENT)
		"weapon": return Color("ff4d5e")
		"char": return Color("4fb3ff")
		"mat": return PACK_COL.get(str(it["id"]), UI.ACCENT)
	return UI.GOLD

func _page_pass() -> void:
	soldier.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.019, 0.025, 0.95)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dim)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for sd in ["left", "right"]:
		root.add_theme_constant_override("margin_" + sd, 44)
	root.add_theme_constant_override("margin_top", 86)
	root.add_theme_constant_override("margin_bottom", 26)
	content.add_child(root)
	var v := UI.vbox(14)
	root.add_child(v)
	var ps: Dictionary = GS.profile.get("pass", {"xp": 0, "claimed": []})
	var pxp := int(ps.get("xp", 0))
	var claimed: Array = ps.get("claimed", [])
	var per: int = GS.Econ.PASS_XP
	var tiers: Array = GS.Econ.PASS
	var cur_t: int = mini(pxp / per, tiers.size())
	# banner
	var ban := Control.new()
	ban.custom_minimum_size = Vector2(0, 230)
	ban.clip_contents = true
	v.add_child(ban)
	if ResourceLoader.exists("res://assets/ui/pass_banner.jpg"):
		var bt := TextureRect.new()
		bt.texture = load("res://assets/ui/pass_banner.jpg")
		bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bt.set_anchors_preset(Control.PRESET_FULL_RECT)
		ban.add_child(bt)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(0.016, 0.019, 0.025, 0.95)); g.set_color(1, Color(0.016, 0.019, 0.025, 0.0))
	gt.gradient = g; gt.fill_from = Vector2(0, 0.5); gt.fill_to = Vector2(0.7, 0.5)
	grad.texture = gt; grad.set_anchors_preset(Control.PRESET_FULL_RECT); grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ban.add_child(grad)
	var bv := UI.vbox(2)
	bv.position = Vector2(30, 26)
	ban.add_child(bv)
	bv.add_child(UI.lbl("SEZON PASOSU", 16, UI.ACCENT2, "Rajdhani-Bold"))
	bv.add_child(UI.lbl(GS.Econ.PASS_SEASON, 44, Color.WHITE, "Teko"))
	bv.add_child(UI.lbl("Her maçta kazandığın XP ve her tamamladığın görev (+500) seni yeni seviyelere taşır. Ödüller ücretsiz!", 16, UI.TEXT, "Rajdhani-SemiBold"))
	var prog := UI.hbox(14)
	bv.add_child(prog)
	var tb := PanelContainer.new()
	tb.add_theme_stylebox_override("panel", UI.sb(Color(0.7, 0.3, 1.0, 0.2), Color("b84bff"), 2, 8, 6))
	tb.add_child(UI.lbl("SEVİYE %d / %d" % [cur_t, tiers.size()], 26, Color.WHITE, "Teko"))
	prog.add_child(tb)
	var pv := UI.vbox(2)
	prog.add_child(pv)
	var into := pxp - cur_t * per if cur_t < tiers.size() else per
	var bar := UI.bar(into, per, Color("b84bff"), 12)
	bar.custom_minimum_size = Vector2(420, 12)
	pv.add_child(bar)
	pv.add_child(UI.lbl(("SONRAKİ SEVİYEYE %s XP" % UI.money(per - into)) if cur_t < tiers.size() else "TÜM SEVİYELER AÇILDI!", 14, UI.DIM, "Rajdhani-Bold"))
	var ready := 0
	for i in cur_t:
		if not claimed.has(i + 1):
			ready += 1
	if ready > 0:
		var allb := UI.btn("TÜMÜNÜ AL (%d)" % ready, func():
			for i in cur_t:
				if not GS.profile.get("pass", {}).get("claimed", []).has(i + 1):
					var r: Dictionary = await GS.act("pass_claim", {"tier": i + 1})
					if not r["ok"]:
						_toast(str(r["err"]), UI.RED)
						break
			SFX.play("success")
			_refresh_currency()
			show_page("pass"), 18, true, 200, 46)
		prog.add_child(allb)
	# tiers
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 340)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var row := UI.hbox(10)
	sc.add_child(row)
	for i in tiers.size():
		row.add_child(_pass_tier_card(i + 1, tiers[i], i + 1 <= cur_t, claimed.has(i + 1)))
	# scroll to the first unclaimed / current tier
	var focus: int = maxi(0, mini(cur_t - 2, tiers.size() - 1))
	sc.ready.connect(func(): sc.scroll_horizontal = focus * 178, CONNECT_DEFERRED)
	get_tree().create_timer(0.05).timeout.connect(func(): if is_instance_valid(sc): sc.scroll_horizontal = focus * 178)

func _pass_tier_card(tier: int, it: Dictionary, open: bool, got: bool) -> Control:
	var c := _pass_reward_col(it)
	var big: bool = tier % 5 == 0
	var p := PanelContainer.new()
	var sb := _store_bg(c if open else c.darkened(0.55))
	if big:
		sb.border_width_top = 3
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(168, 320)
	var v := UI.vbox(4)
	p.add_child(v)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 10); hm.add_theme_constant_override("margin_right", 6)
	v.add_child(hm)
	var hh := UI.hbox(6)
	hm.add_child(hh)
	var tl := UI.lbl("%d" % tier, 30, (c.lightened(0.3) if open else UI.DIM), "Teko")
	hh.add_child(tl)
	hh.add_child(UI.spacer())
	if big:
		hh.add_child(_store_grade_chip("BÜYÜK ÖDÜL", c))
	var art_wrap := CenterContainer.new()
	art_wrap.custom_minimum_size = Vector2(0, 150)
	v.add_child(art_wrap)
	var art := _pass_reward_art(it, Vector2(140, 130))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not open:
		art.modulate = Color(0.45, 0.45, 0.5, 0.8)
	art_wrap.add_child(art)
	if open and not got:
		var tw := art.create_tween().set_loops()
		tw.tween_property(art, "modulate", Color(1.3, 1.25, 1.15), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(art, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	var nl := UI.lbl(_pass_reward_name(it), 15, Color.WHITE if open else UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(150, 40)
	v.add_child(nl)
	v.add_child(UI.spacer())
	if got:
		v.add_child(UI.lbl("✓ ALINDI", 18, UI.GREEN, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	elif open:
		v.add_child(UI.btn("ÖDÜLÜ AL", func():
			var r: Dictionary = await _act("pass_claim", {"tier": tier})
			if r["ok"]:
				SFX.play("success")
				var rs: Dictionary = r.get("res", {})
				_toast(("Ödül alındı: " + _pass_reward_name(it)) if not rs.has("dup") else "Zaten sendeydi: +%s altın" % UI.money(int(rs["dup"])), UI.GREEN)
				show_page("pass"), 16, true, 0, 40))
	else:
		v.add_child(UI.lbl("KİLİTLİ  •  %s XP" % UI.money(tier * GS.Econ.PASS_XP), 14, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	return p

# ================================================================ MARKET
func _page_market() -> void:
	## CS2 Store: full-width dark page, tabs on top, a featured hero row, then a grid of item tiles,
	## each with a rarity stripe; clicking a tile opens a clean purchase card
	soldier.visible = false
	cam_target = Vector3(1.6, 1.42, 1.5)
	cam_look = Vector3(1.6, 1.3, -0.4)
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.019, 0.025, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dim)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 70)
	root.add_theme_constant_override("margin_right", 70)
	root.add_theme_constant_override("margin_top", 18)
	root.add_theme_constant_override("margin_bottom", 22)
	content.add_child(root)
	var v := UI.vbox(14)
	root.add_child(v)
	var th := UI.hbox(0)
	v.add_child(th)
	var ttl := UI.lbl("MAĞAZA", 50, Color.WHITE, "Teko")
	ttl.custom_minimum_size = Vector2(210, 0)
	th.add_child(ttl)
	for t in [["silah", "SİLAHLAR"], ["stil", "KAPLAMALAR"], ["kasa", "KASALAR"], ["karakter", "AJANLAR"], ["eklenti", "EKLENTİLER"], ["malzeme", "MALZEME"]]:
		var on: bool = market_tab == t[0]
		var tb := Button.new()
		tb.text = t[1]
		tb.focus_mode = Control.FOCUS_NONE
		tb.size_flags_vertical = Control.SIZE_SHRINK_END
		tb.custom_minimum_size = Vector2(0, 48)
		tb.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
		tb.add_theme_font_size_override("font_size", 19)
		var nsb := UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
		nsb.content_margin_left = 22; nsb.content_margin_right = 22
		nsb.border_width_bottom = 3; nsb.border_color = UI.ACCENT if on else Color(1, 1, 1, 0.07)
		tb.add_theme_stylebox_override("normal", nsb)
		var hsb := nsb.duplicate(); hsb.bg_color = Color(1, 1, 1, 0.07)
		tb.add_theme_stylebox_override("hover", hsb)
		tb.add_theme_stylebox_override("pressed", hsb)
		tb.add_theme_color_override("font_color", Color.WHITE if on else Color(1, 1, 1, 0.55))
		tb.add_theme_color_override("font_hover_color", Color.WHITE)
		tb.pressed.connect(func(): SFX.play("ui_click", -8); market_tab = t[0]; show_page("market"))
		th.add_child(tb)
	# hidden legacy preview card (other tabs still feed it on hover)
	mk_info = UI.panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	mk_info.visible = false
	content.add_child(mk_info)
	_mk_preview("", "")
	if market_tab == "silah":
		v.add_child(_store_hero())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5 if market_tab == "silah" else 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	match market_tab:
		"silah":
			var any := false
			var ids: Array = []
			for id in GS.WEAPONS.keys():
				if GS.WEAPONS[id].get("hidden", false) or GS.WEAPONS[id].get("throwable", false):
					continue
				if GS.owned(id) and GS.wtime_left(id) <= 0.0:
					continue      # timed (crate) weapons stay buyable: buying makes them permanent
				ids.append(id)
			ids.sort_custom(func(x, y): return int(GS.WEAPONS[x]["price"]) > int(GS.WEAPONS[y]["price"]))
			for id in ids:
				any = true
				grid.add_child(_store_tile(id))
			if not any:
				v.add_child(UI.lbl("Tüm silahlara sahipsin!", 24, UI.GREEN))
		"stil":
			var target_id := bag_sel if bag_sel != "" and GS.owned(bag_sel) else "ak47"
			var sel := UI.hbox(6)
			v.add_child(sel)
			v.move_child(sel, 1)
			sel.add_child(UI.lbl("Stil uygulanacak silah:", 17, UI.DIM, "Rajdhani-Bold"))
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(280, 36)
			for id in GS.profile["owned"].keys():
				if GS.WEAPONS.has(id) and not GS.WEAPONS[id].get("throwable", false):
					ob.add_item(str(GS.WEAPONS[id]["name"]))
					ob.set_item_metadata(ob.item_count - 1, id)
					if id == target_id:
						ob.select(ob.item_count - 1)
			ob.item_selected.connect(func(i): bag_sel = str(ob.get_item_metadata(i)); show_page("market"))
			sel.add_child(ob)
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
				var brow := UI.hbox(6)
				cv.add_child(brow)
				var pv := UI.btn("◎ ÖNİZLE", func(): _inspect(target_id, sk), 16, false, 0, 38)
				brow.add_child(pv)
				if have:
					var ow := UI.lbl("✔ SAHİPSİN", 18, UI.GREEN, "Rajdhani-Bold")
					ow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					brow.add_child(ow)
				else:
					var bb := UI.btn("◉ " + UI.money(sd["price"]) + "  SATIN AL", func(): _buy_skin(target_id, sk), 18, true, 0, 38)
					bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					brow.add_child(bb)
				card.mouse_entered.connect(func(): set_showcase(target_id, sk); _mk_preview(target_id, sk))
				grid.add_child(card)
		"karakter":
			for c in GS.CHARACTERS.keys():
				grid.add_child(_agent_card(c))
		"kasa":
			for t in GS.CRATES.keys():
				grid.add_child(_store_crate_tile(t))
		"eklenti":
			set_showcase(GS.active_set().get("ana", "ak47"))
			for pid in GS.PARTS.keys():
				grid.add_child(_store_part_tile(pid))
		"malzeme":
			set_showcase("frag")
			for pi in GS.Econ.PACKS.size():
				grid.add_child(_store_pack_tile(pi))

var mk_info: PanelContainer
func _mk_preview(id: String, skin: String) -> void:
	if mk_info == null or not is_instance_valid(mk_info):
		return
	UI.clear(mk_info)
	var v := UI.vbox(4)
	mk_info.add_child(v)
	if id == "":
		v.add_child(UI.lbl("ÖNİZLEME", 15, UI.DIM, "Rajdhani-Bold"))
		v.add_child(_wrap("Bir silahın ya da stilin üzerine gel: burada 3D olarak görürsün. Satın almadan önce ◎ ÖNİZLE ile yakından incele.", 17))
		return
	var w: Dictionary = GS.full_stats(id)
	var sd: Dictionary = GS.SKINS.get(skin if skin != "" else "std", GS.SKINS["std"])
	var rc: Color = GS.RARITY_COLORS[int(sd["rarity"])]
	v.add_child(UI.lbl((str(sd["name"]).to_upper() + "  •  ") if skin != "" and skin != "std" else "" + "", 15, rc, "Rajdhani-Bold"))
	v.add_child(UI.lbl(str(w["name"]).to_upper(), 28, Color.WHITE, "RussoOne-Regular"))
	if not w.get("melee", false) and not w.get("throwable", false):
		var g := GridContainer.new(); g.columns = 2
		g.add_theme_constant_override("h_separation", 14)
		v.add_child(g)
		for r in _stat_rows(id).slice(0, 4):
			g.add_child(_stat(r[0], r[1], r[2], true))

func _agent_card(c: String) -> Control:
	var cd: Dictionary = GS.CHARACTERS[c]
	var tc: Color = GS.TEAM_COLORS[cd["team"]]
	var p := PanelContainer.new()
	var sb := UI.sb(Color(0.05, 0.056, 0.068, 1.0), Color(1, 1, 1, 0.06), 1, 3, 0)
	sb.border_width_bottom = 4; sb.border_color = tc
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, 470)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cc := Control.new()
	cc.clip_contents = true
	p.add_child(cc)
	var art := _agent_art(c, Vector2.ZERO)
	if art:
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.add_child(art)
	var sh := TextureRect.new()
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0)); g.set_color(1, Color(0.02, 0.02, 0.03, 0.95))
	gt.gradient = g; gt.fill_from = Vector2(0, 0.45); gt.fill_to = Vector2(0, 1)
	sh.texture = gt; sh.set_anchors_preset(Control.PRESET_FULL_RECT); sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(sh)
	var v := UI.vbox(4)
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_left = 16; v.offset_right = -16; v.offset_top = -150; v.offset_bottom = -14
	cc.add_child(v)
	v.add_child(UI.lbl(GS.TEAMS[cd["team"]] + "  •  AJAN", 14, tc.lightened(0.3), "Rajdhani-Bold"))
	v.add_child(UI.lbl(str(cd["name"]).to_upper(), 34, Color.WHITE, "Teko"))
	var dl := UI.lbl(cd["desc"], 15, UI.TEXT, "Rajdhani-SemiBold")
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dl)
	if c == GS.cur_char():
		v.add_child(UI.lbl("✔ KUŞANILDI", 18, UI.GREEN, "Rajdhani-Bold"))
	elif _char_owned(c):
		v.add_child(UI.btn("KUŞAN", func(): GS.profile["char"] = c; GS.save_profile(); char_view = c; _swap_soldier(c); _toast(cd["name"] + " kuşanıldı", UI.GREEN); show_page("market"), 18, false, 0, 40))
	else:
		var pr := int(cd["price"])
		var bb := UI.btn("◉ " + UI.money(pr) + "  SATIN AL", func():
			var r: Dictionary = await _act("buy_char", {"id": c})
			if not r["ok"]: return
			SFX.play("buy"); show_page("market"), 18, true, 0, 40)
		bb.disabled = int(GS.profile["gold"]) < pr
		v.add_child(bb)
	return p

## price tier -> CS2-like rarity colour (grade stripe on the tile)
func _store_grade(id: String) -> int:
	var pr := int(GS.WEAPONS[id].get("price", 0))
	return 3 if pr >= 5000 else (2 if pr >= 3500 else (1 if pr >= 2000 else 0))

const STORE_GRADE_COL := [Color("5e98d9"), Color("8847ff"), Color("d32ce6"), Color("eb4b4b")]
const STORE_GRADE_NAME := ["ASKERİ", "SINIRLI", "GİZLİ", "ÖZEL"]

func _store_bg(col: Color) -> StyleBoxFlat:
	var sb := UI.sb(Color(0.055, 0.062, 0.075, 1.0), Color(1, 1, 1, 0.05), 1, 3, 0)
	sb.border_width_bottom = 4
	sb.border_color = col
	return sb

func _store_tile(id: String) -> Control:
	var w: Dictionary = GS.WEAPONS[id]
	var gi := _store_grade(id)
	var gc: Color = STORE_GRADE_COL[gi]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 236)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := _store_bg(gc)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate(); h.bg_color = Color(0.09, 0.1, 0.12, 1.0); h.border_color = gc.lightened(0.25)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	# soft rarity glow from the bottom
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(gc, 0.0)); g.set_color(1, Color(gc, 0.22))
	gt.gradient = g; gt.fill_from = Vector2(0, 0.2); gt.fill_to = Vector2(0, 1)
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -4
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glow)
	var tr := thumb_rect(id, "std", Vector2(300, 130))
	tr.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tr.offset_top = 22; tr.offset_bottom = 160; tr.offset_left = 18; tr.offset_right = -18
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	var cls := UI.lbl(str(w.get("cls", "")).to_upper(), 13, Color(1, 1, 1, 0.45), "Rajdhani-Bold")
	cls.position = Vector2(14, 8)
	cls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cls)
	var nm := UI.lbl(str(w["name"]), 21, Color.WHITE, "Rajdhani-Bold")
	nm.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nm.offset_top = -66; nm.offset_bottom = -40; nm.offset_left = 14; nm.offset_right = -10
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var gl := UI.lbl(STORE_GRADE_NAME[gi], 13, gc.lightened(0.2), "Rajdhani-Bold")
	gl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	gl.offset_top = -38; gl.offset_bottom = -14; gl.offset_left = 14; gl.offset_right = -10
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(gl)
	var pr := UI.lbl("◉ " + UI.money(int(w["price"])), 20, UI.GOLD, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	pr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pr.offset_top = -40; pr.offset_bottom = -12; pr.offset_left = 14; pr.offset_right = -14
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pr)
	b.pressed.connect(func(): SFX.play("ui_click", -6); _store_detail(id))
	return b

func _store_crate_tile(t: String) -> Control:
	var cd: Dictionary = GS.CRATES[t]
	var c: Color = cd["color"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 330)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := _store_bg(c)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate(); h.bg_color = Color(0.09, 0.1, 0.12, 1.0); h.border_color = c.lightened(0.25)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(c, 0.28)); g.set_color(1, Color(c, 0.0))
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.4); gt.fill_to = Vector2(1.0, 0.9)
	glow.texture = gt; glow.set_anchors_preset(Control.PRESET_FULL_RECT); glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glow)
	var tx := _crate_tex(t)
	if tx:
		var art := CrateBox.new()
		art.col = c; art.tex = tx; art.glow = 0.15
		art.set_anchors_preset(Control.PRESET_TOP_WIDE); art.offset_top = 12; art.offset_bottom = 200; art.offset_left = 30; art.offset_right = -30
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
	var v := UI.vbox(2)
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_left = 16; v.offset_right = -16; v.offset_top = -124; v.offset_bottom = -14
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(UI.lbl(str(cd["name"]).to_upper(), 28, Color.WHITE, "Teko"))
	var dl := UI.lbl(str(cd["desc"]), 14, UI.DIM, "Rajdhani-SemiBold")
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.max_lines_visible = 2
	v.add_child(dl)
	var ph := UI.hbox(8)
	v.add_child(ph)
	ph.add_child(UI.lbl("◉ " + UI.money(int(cd["price"])), 20, UI.GOLD, "Rajdhani-Bold"))
	ph.add_child(UI.spacer())
	var cnt := _crate_count(t)
	if cnt > 0:
		ph.add_child(UI.lbl("SENDE x%d" % cnt, 16, UI.GREEN, "Rajdhani-Bold"))
	for cc in b.find_children("*", "Control", true, false):
		(cc as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func(): SFX.play("ui_click", -6); crate_type = t; show_page("crate"))
	return b

## v3.4.1 material supply boxes: painted crate art (Higgsfield) floating over a spinning ray burst
const PACK_COL := {"demir": Color("d0783a"), "krom": Color("49e3ff"), "titanyum": Color("b46bff"), "kobalt": Color("3d7bff"), "crate": Color("ffb02e")}
const PACK_TIER := {"demir": "SIRADAN", "krom": "NADİR", "titanyum": "EPİK", "kobalt": "EFSANEVİ", "crate": "ÖZEL"}
func _store_pack_tile(pi: int) -> Control:
	var pack: Array = GS.Econ.PACKS[pi]
	var kind := str(pack[1])
	var c: Color = PACK_COL.get(kind, UI.ACCENT)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _store_bg(c.darkened(0.15)))
	p.custom_minimum_size = Vector2(0, 360)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(4)
	p.add_child(v)
	var art := PackArt.new()
	art.col = c
	var tp := "res://assets/ui/packs/%s.png" % kind
	if not ResourceLoader.exists(tp):
		tp = "res://assets/ui/icons/%s.png" % kind
	art.tex = load(tp) if ResourceLoader.exists(tp) else null
	art.custom_minimum_size = Vector2(0, 200)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.phase = pi * 1.3
	v.add_child(art)
	var m := MarginContainer.new()
	for sd in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + sd, 14)
	v.add_child(m)
	var iv := UI.vbox(4)
	m.add_child(iv)
	var th := UI.hbox(8)
	iv.add_child(th)
	th.add_child(_store_grade_chip(str(PACK_TIER.get(kind, "")), c))
	th.add_child(UI.spacer())
	var have := _crate_count("sokak") if kind == "crate" else int(GS.profile["mats"].get(kind, 0))
	th.add_child(UI.lbl("SENDE: %s" % UI.money(have), 14, UI.DIM, "Rajdhani-Bold"))
	var nh := UI.hbox(8)
	iv.add_child(nh)
	nh.add_child(UI.lbl(str(pack[0]).to_upper(), 26, Color.WHITE, "Teko"))
	nh.add_child(UI.spacer())
	nh.add_child(UI.lbl("x%d" % int(pack[2]), 34, c.lightened(0.25), "Teko"))
	iv.add_child(UI.lbl("Silah yükseltmede kullanılır" if kind != "crate" else "Bir kasayı açar", 13, UI.DIM, "Rajdhani-SemiBold"))
	var bb := UI.btn("◉ " + UI.money(int(pack[3])) + "  SATIN AL", func():
		art.burst = 1.0
		_buy_pack(pi), 18, true, 0, 42)
	iv.add_child(bb)
	p.mouse_entered.connect(func(): art.hover = true)
	p.mouse_exited.connect(func(): art.hover = false)
	return p

func _store_grade_chip(t: String, c: Color) -> Control:
	var pc := PanelContainer.new()
	var sb := UI.sb(Color(c.r, c.g, c.b, 0.16), Color(c.r, c.g, c.b, 0.7), 1, 4, 0)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(UI.lbl(t, 12, c.lightened(0.3), "Rajdhani-Bold"))
	return pc

class PackArt extends Control:
	var col := Color.WHITE
	var tex: Texture2D
	var phase := 0.0
	var hover := false
	var burst := 0.0
	var _hk := 0.0
	func _process(d: float) -> void:
		_hk = move_toward(_hk, 1.0 if hover else 0.0, d * 4.0)
		burst = maxf(burst - d * 1.2, 0.0)
		queue_redraw()
	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0 + phase
		var c0 := size * Vector2(0.5, 0.52)
		var r := minf(size.x, size.y) * 0.5
		# slow ray burst
		for i in 14:
			var a := i * TAU / 14.0 + t * 0.25
			var ln := r * (1.1 + 0.25 * _hk + burst * 0.8)
			draw_colored_polygon(PackedVector2Array([c0, c0 + Vector2.from_angle(a - 0.07) * ln, c0 + Vector2.from_angle(a + 0.07) * ln]), Color(col.r, col.g, col.b, 0.05 + 0.05 * _hk + 0.15 * burst))
		# pulsing glow
		var pul := 0.5 + 0.5 * sin(t * 2.2)
		for k in 9:
			draw_circle(c0, r * (0.25 + k * 0.08), Color(col.r, col.g, col.b, (0.025 + 0.015 * pul) * (1.0 + _hk + burst * 3.0)))
		# rising sparkles
		for i in 10:
			var u := fmod(t * 0.35 + i * 0.137, 1.0)
			var x := c0.x + sin(i * 12.9898) * r * 0.75
			var y := c0.y + r * 0.6 - u * r * 1.3
			draw_circle(Vector2(x, y), 1.5 + 1.5 * (1.0 - u), Color(col.r, col.g, col.b, (1.0 - u) * 0.8))
		if tex:
			var bob := sin(t * 1.6) * 6.0 - _hk * 6.0
			var sc := 1.0 + 0.06 * _hk + 0.12 * burst
			var sz := Vector2(r, r) * 1.7 * sc
			draw_texture_rect(tex, Rect2(c0 - sz * 0.5 + Vector2(0, bob), sz), false, Color(1 + burst, 1 + burst, 1 + burst, 1))

func _store_part_tile(pid: String) -> Control:
	var pd: Dictionary = GS.PARTS[pid]
	var c := Color("7dff6a")
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _store_bg(c.darkened(0.3)))
	p.custom_minimum_size = Vector2(0, 330)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	p.add_child(v)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_top", 12)
	v.add_child(top)
	var ic := PartIcon.new(); ic.pid = pid; ic.custom_minimum_size = Vector2(0, 150)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ic)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_bottom", 14)
	v.add_child(m)
	var iv := UI.vbox(4)
	m.add_child(iv)
	iv.add_child(UI.lbl(str(pd["slot"]).to_upper() + " EKLENTİSİ", 13, c, "Rajdhani-Bold"))
	iv.add_child(UI.lbl(str(pd["name"]), 22, Color.WHITE, "Rajdhani-Bold"))
	var dl := UI.lbl(str(pd["desc"]), 14, UI.DIM, "Rajdhani-SemiBold")
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(dl)
	var bh := UI.hbox(8)
	iv.add_child(bh)
	bh.add_child(UI.lbl("Sende: %d" % GS.parts_owned(pid), 15, Color.WHITE, "Rajdhani-Bold"))
	bh.add_child(UI.spacer())
	var bb := UI.btn("◉ " + UI.money(int(pd["price"])), func():
		var r: Dictionary = await _act("buy_part", {"id": pid})
		if not r["ok"]: return
		SFX.play("buy"); _toast(pd["name"] + " alındı! Çanta > Özelleştir ile tak.", UI.GREEN); show_page("market"), 17, true, 130, 38)
	bb.disabled = int(GS.profile["gold"]) < int(pd["price"])
	bh.add_child(bb)
	return p

func _store_hero() -> Control:
	var feat := ""
	for fid in ["m249", "aug", "vector", "scar", "awm", "rpk16"]:
		if GS.WEAPONS.has(fid) and not GS.owned(fid):
			feat = fid; break
	var row := UI.hbox(12)
	row.custom_minimum_size = Vector2(0, 250)
	# featured weapon (2/3)
	var big := PanelContainer.new()
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.size_flags_stretch_ratio = 2.0
	var bsb := UI.sb(Color(0.08, 0.05, 0.03, 1.0), Color(1, 0.55, 0.12, 0.5), 1, 3, 0)
	big.add_theme_stylebox_override("panel", bsb)
	row.add_child(big)
	var bc := Control.new()
	bc.clip_contents = true
	big.add_child(bc)
	var hg := TextureRect.new()
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(1, 0.5, 0.1, 0.32)); g.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.7, 0.55); gt.fill_to = Vector2(1.25, 1.1)
	hg.texture = gt; hg.set_anchors_preset(Control.PRESET_FULL_RECT); hg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(hg)
	if feat != "":
		var tr := thumb_rect(feat, "std", Vector2(560, 220))
		tr.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		tr.offset_left = -640; tr.offset_right = -30; tr.offset_top = 10; tr.offset_bottom = -10
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bc.add_child(tr)
		var fv := UI.vbox(6)
		fv.position = Vector2(34, 28)
		bc.add_child(fv)
		fv.add_child(UI.lbl("HAFTANIN SİLAHI  •  %20 İNDİRİM", 16, UI.ACCENT2, "Rajdhani-Bold"))
		fv.add_child(UI.lbl(str(GS.WEAPONS[feat]["name"]).to_upper(), 58, Color.WHITE, "Teko"))
		var ab := UI.lbl(str(GS.ball(feat).get("ability", "")), 18, UI.TEXT, "Rajdhani-SemiBold")
		ab.custom_minimum_size = Vector2(520, 0)
		ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fv.add_child(ab)
		var ph := UI.hbox(14)
		fv.add_child(ph)
		var old := UI.lbl("◉ " + UI.money(int(GS.WEAPONS[feat]["price"])), 20, Color(1, 1, 1, 0.4), "Rajdhani-Bold")
		ph.add_child(old)
		var fp: int = int(GS.WEAPONS[feat]["price"] * 0.8)
		var fbb := UI.btn("◉ %s   SATIN AL" % UI.money(fp), func():
			var r: Dictionary = await _act("buy_weapon", {"id": feat})
			if not r["ok"]: return
			SFX.play("buy"); _toast(GS.WEAPONS[feat]["name"] + " alındı!", UI.GREEN); show_page("market"), 20, true, 260, 50)
		ph.add_child(fbb)
		ph.add_child(UI.btn("3D İNCELE", func(): _inspect(feat, "std"), 17, false, 150, 50))
	else:
		var ok := UI.lbl("Bütün öne çıkan silahlara sahipsin!", 26, UI.GREEN, "Rajdhani-Bold")
		ok.position = Vector2(34, 100)
		bc.add_child(ok)
	# crates promo (1/3)
	var cr := Button.new()
	cr.focus_mode = Control.FOCUS_NONE
	cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var csb := UI.sb(Color(0.05, 0.06, 0.085, 1.0), Color(0.55, 0.3, 1.0, 0.45), 1, 3, 0)
	cr.add_theme_stylebox_override("normal", csb)
	var chs := csb.duplicate(); chs.bg_color = Color(0.08, 0.09, 0.12, 1.0)
	cr.add_theme_stylebox_override("hover", chs)
	cr.add_theme_stylebox_override("pressed", chs)
	cr.pressed.connect(func(): SFX.play("ui_click", -8); market_tab = "kasa"; show_page("market"))
	row.add_child(cr)
	var ck: String = str(GS.CRATES.keys()[0]) if GS.CRATES.size() > 0 else ""
	if ck != "":
		var ic := CurIcon.new(); ic.kind = "crate"; ic.col = GS.CRATES[ck]["color"]
		ic.position = Vector2(26, 18); ic.size = Vector2(120, 120)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(ic)
	var cv := UI.vbox(4)
	cv.position = Vector2(30, 140)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(cv)
	var l1 := UI.lbl("KASALAR", 40, Color.WHITE, "Teko"); l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(l1)
	var l2 := UI.lbl("Nadir kaplamalar, silahlar ve eklentiler →", 17, UI.DIM, "Rajdhani-SemiBold"); l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(l2)
	return row

func _store_detail(id: String) -> void:
	## CS2 purchase card: dim the page, big item art, rarity, stats, buy / inspect / cancel
	var w: Dictionary = GS.WEAPONS[id]
	var gi := _store_grade(id)
	var gc: Color = STORE_GRADE_COL[gi]
	var dimr := ColorRect.new()
	dimr.color = Color(0, 0, 0, 0.72)
	dimr.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dimr)
	dimr.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: dimr.queue_free())
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dimr.add_child(cc)
	var p := PanelContainer.new()
	var psb := UI.sb(Color(0.05, 0.056, 0.068, 0.99), Color(1, 1, 1, 0.08), 1, 4, 26)
	psb.border_width_top = 4; psb.border_color = gc
	p.add_theme_stylebox_override("panel", psb)
	p.custom_minimum_size = Vector2(860, 0)
	cc.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var hh := UI.hbox(10)
	v.add_child(hh)
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(tv)
	tv.add_child(UI.lbl(STORE_GRADE_NAME[gi] + "  •  " + str(w.get("cls", "")).to_upper(), 16, gc.lightened(0.25), "Rajdhani-Bold"))
	tv.add_child(UI.lbl(str(w["name"]).to_upper(), 56, Color.WHITE, "Teko"))
	hh.add_child(UI.btn("✕", func(): dimr.queue_free(), 20, false, 48, 48))
	var art := thumb_rect(id, "std", Vector2(808, 300))
	v.add_child(art)
	var ab := UI.lbl("★ " + str(GS.ball(id).get("ability", "")), 18, UI.TEXT, "Rajdhani-SemiBold")
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ab)
	var st := UI.hbox(26)
	v.add_child(st)
	for kv in [["HASAR", str(int(w.get("dmg", 0)))], ["ATIŞ HIZI", "%d/dk" % int(w.get("rpm", 0))], ["ŞARJÖR", str(int(w.get("mag", 0)))], ["MENZİL", "%d m" % int(w.get("range", 0))]]:
		var sv := UI.vbox(0)
		sv.add_child(UI.lbl(kv[0], 14, UI.DIM, "Rajdhani-Bold"))
		sv.add_child(UI.lbl(kv[1], 30, Color.WHITE, "Teko"))
		st.add_child(sv)
	var bh := UI.hbox(10)
	v.add_child(bh)
	bh.add_child(UI.btn("3D İNCELE", func(): dimr.queue_free(); _inspect(id, "std"), 18, false, 180, 56))
	bh.add_child(UI.spacer())
	var buy := UI.btn("◉ %s   SATIN AL" % UI.money(int(w["price"])), func(): dimr.queue_free(); _buy_weapon(id), 22, true, 320, 56)
	buy.disabled = int(GS.profile["gold"]) < int(w["price"])
	bh.add_child(buy)

func _buy_weapon(id: String) -> void:
	var r: Dictionary = await _act("buy_weapon", {"id": id})
	if not r["ok"]:
		return
	SFX.play("buy")
	_toast(GS.WEAPONS[id]["name"] + " çantana eklendi!", UI.GREEN)
	show_page("market")

func _buy_skin(id: String, sk: String) -> void:
	var r: Dictionary = await _act("buy_skin", {"wid": id, "skin": sk})
	if not r["ok"]:
		return
	SFX.play("buy")
	_toast(GS.SKINS[sk]["name"] + " stili alındı ve uygulandı!", UI.GREEN)
	show_page("market")

func _buy_pack(i: int) -> void:
	var r: Dictionary = await _act("buy_pack", {"i": i})
	if not r["ok"]:
		return
	SFX.play("buy")
	_toast(str(GS.Econ.PACKS[i][0]) + " alındı!", UI.GREEN)

func _act(a: String, args: Dictionary = {}) -> Dictionary:
	## server-checked economy action (online) or local rules (offline); shows the error itself
	var r: Dictionary = await GS.act(a, args)
	if not r["ok"]:
		_toast(r["err"] if r["err"] != "" else "İşlem yapılamadı", UI.RED)
		SFX.play("fail", -6)
	_refresh_currency()
	return r

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

func _crate_tex(t: String) -> Texture2D:
	var pth := "res://assets/ui/crates/%s.png" % t
	return load(pth) if ResourceLoader.exists(pth) else null

func _crate_tile(t: String) -> Control:
	var cd: Dictionary = GS.CRATES[t]
	var c: Color = cd["color"]
	var on: bool = t == crate_type
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 160)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := UI.sb(Color(0.05, 0.056, 0.068, 1.0), c if on else Color(1, 1, 1, 0.06), 2 if on else 1, 4, 0)
	n.border_width_bottom = 4; n.border_color = c if on else c.darkened(0.45)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate(); h.bg_color = Color(0.09, 0.1, 0.12, 1.0)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	var tx := _crate_tex(t)
	if tx:
		var tr := TextureRect.new()
		tr.texture = tx
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(25, 6); tr.size = Vector2(120, 100)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
	else:
		var ic := CrateIcon.new(); ic.col = c
		ic.position = Vector2(55, 20); ic.size = Vector2(60, 60); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
	var nm := UI.lbl(str(cd["name"]), 17, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(4, 106); nm.size = Vector2(162, 24); nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var cnt := _crate_count(t)
	var pr := UI.lbl(("x%d" % cnt) if cnt > 0 else ("◉ " + UI.money(int(cd["price"]))), 15, UI.GREEN if cnt > 0 else UI.GOLD, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	pr.position = Vector2(4, 128); pr.size = Vector2(162, 22); pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pr)
	b.pressed.connect(func(): crate_type = t; SFX.play("ui_click", -4); show_page("crate"))
	return b

func _skin_swatch(sk: String) -> Control:
	var sd: Dictionary = GS.SKINS[sk]
	var rc: Color = GS.RARITY_COLORS[clampi(int(sd.get("rarity", 0)), 0, 3)]
	var v := UI.vbox(2)
	var p := PanelContainer.new()
	var sb := UI.sb(Color(0, 0, 0, 0.4), rc, 0, 3, 0)
	sb.border_width_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(96, 58)
	v.add_child(p)
	var tp := "res://assets/tex/skin_%s_albedo.png" % sk
	if ResourceLoader.exists(tp):
		var tr := TextureRect.new()
		tr.texture = load(tp)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	elif sk == "altin":
		var cr := ColorRect.new(); cr.color = Color(0.95, 0.72, 0.32); p.add_child(cr)
	if sd.get("anim", false):
		var tag := UI.lbl("HAREKETLİ", 11, Color.WHITE, "Rajdhani-Bold")
		tag.add_theme_constant_override("outline_size", 4)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		p.add_child(tag)
	var nl := UI.lbl(str(sd["name"]), 12, rc.lightened(0.2), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	nl.custom_minimum_size = Vector2(96, 0)
	nl.clip_text = true
	v.add_child(nl)
	v.tooltip_text = "%s  •  %s" % [sd["name"], GS.RARITY_NAMES[clampi(int(sd.get("rarity", 0)), 0, 3)]]
	return v

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
	soldier.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.017, 0.022, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dim)
	var p := MarginContainer.new()
	p.anchor_left = 0.5; p.anchor_right = 0.5
	p.offset_left = -640; p.offset_right = 640; p.offset_top = 12
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var cd0: Dictionary = GS.CRATES[crate_type]
	var cc0: Color = cd0["color"]
	# ---- crate shelf: painted crate tiles (CS2 inventory cases)
	var shelf_sc := ScrollContainer.new()
	shelf_sc.custom_minimum_size = Vector2(0, 168)
	shelf_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(shelf_sc)
	var shelf := UI.hbox(10)
	shelf_sc.add_child(shelf)
	for t in GS.CRATES.keys():
		shelf.add_child(_crate_tile(t))
	# ---- hero: the selected crate big, its story and what can drop
	var hero := PanelContainer.new()
	var hsb := UI.sb(Color(cc0.r * 0.12, cc0.g * 0.12, cc0.b * 0.12, 0.95), Color(cc0.r, cc0.g, cc0.b, 0.35), 1, 4, 16)
	hero.add_theme_stylebox_override("panel", hsb)
	v.add_child(hero)
	var hh0 := UI.hbox(22)
	hero.add_child(hh0)
	var ctex := _crate_tex(crate_type)
	if ctex:
		var art := CrateBox.new()
		art.col = cc0; art.tex = ctex; art.glow = 0.25
		art.custom_minimum_size = Vector2(250, 220)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hh0.add_child(art)
	var hv := UI.vbox(6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh0.add_child(hv)
	hv.add_child(UI.lbl(str(cd0["name"]).to_upper(), 46, Color.WHITE, "Teko"))
	var dl0 := UI.lbl(str(cd0["desc"]), 17, UI.TEXT, "Rajdhani-SemiBold")
	dl0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(dl0)
	hv.add_child(UI.lbl("İÇERİK  •  ◉ %s  •  Sende: %d" % [UI.money(int(cd0["price"])), _crate_count(crate_type)], 15, UI.DIM, "Rajdhani-Bold"))
	var ct := UI.hbox(8)
	hv.add_child(ct)
	var skl: Array = cd0.get("skins", []).duplicate()
	skl.sort_custom(func(x, y): return int(GS.SKINS.get(x, {}).get("rarity", 0)) > int(GS.SKINS.get(y, {}).get("rarity", 0)))
	for sk in skl.slice(0, 8):
		if GS.SKINS.has(sk):
			ct.add_child(_skin_swatch(sk))
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(1240, 210)
	clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(clip)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	clip.add_child(strip)
	var marker := ColorRect.new()
	marker.color = GS.CRATES[crate_type]["color"]
	marker.size = Vector2(4, 210)
	marker.position = Vector2(618, 0)
	clip.add_child(marker)
	# edge fades + pointer triangles: the reel reads like a premium case opening
	for side in [0, 1]:
		var fade := TextureRect.new()
		var gt := GradientTexture2D.new()
		var gg := Gradient.new()
		gg.set_color(0, Color(0.02, 0.025, 0.035, 1.0)); gg.set_color(1, Color(0.02, 0.025, 0.035, 0.0))
		gt.gradient = gg
		gt.fill_from = Vector2(0, 0) if side == 0 else Vector2(1, 0); gt.fill_to = Vector2(1, 0) if side == 0 else Vector2(0, 0)
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.size = Vector2(220, 210); fade.position = Vector2(0 if side == 0 else 1020, 0)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(fade)
	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(0, 18)])
	tri.color = GS.CRATES[crate_type]["color"]
	tri.position = Vector2(620, 0)
	clip.add_child(tri)
	var tri2 := Polygon2D.new()
	tri2.polygon = PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(0, -18)])
	tri2.color = GS.CRATES[crate_type]["color"]
	tri2.position = Vector2(620, 210)
	clip.add_child(tri2)
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
		open.disabled = true
		var cr: Dictionary = await _act("open_crate", {"id": crate_type})
		if not cr["ok"]:
			open.disabled = false
			return
		var win_i := 38
		var win: Dictionary = _item_display(cr["res"])
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
			var label: String = win["label"] + ("  (zaten vardı: +%s altın)" % UI.money(int(win["dup"])) if win.has("dup") else "")
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

const RARITY_NAMES := ["SIRADAN", "NADİR", "EPİK", "EFSANEVİ"]

class CrateBox extends Control:
	## stylised crate drawn in code: it shakes, its seams glow brighter and brighter, then it bursts open
	var col := Color.WHITE
	var glow := 0.0
	var lid := 0.0           # 0 closed .. 1 blown off
	var tex: Texture2D       # painted crate art (v3.2); the code-drawn crate is the fallback
	func _process(_d: float) -> void:
		queue_redraw()
	func _box(r: Rect2, c: Color, rad: int) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(rad)
		draw_style_box(sb, r)
	func _draw() -> void:
		var w := size.x; var h := size.y
		if tex:
			var c0 := size * 0.5
			for k in 10:
				draw_circle(c0, w * (0.25 + k * 0.045 * (0.5 + glow)), Color(col.r, col.g, col.b, 0.03 * glow))
			var sc := 1.0 + lid * 0.35 + glow * 0.05
			var sz := Vector2(w, h) * 0.95 * sc
			draw_texture_rect(tex, Rect2(c0 - sz * 0.5, sz), false, Color(1 + glow * 0.6, 1 + glow * 0.5, 1 + glow * 0.4, 1.0 - lid))
			if glow > 0.2:
				for i in 12:
					var a := i * TAU / 12.0 + Time.get_ticks_msec() * 0.0008
					var ln := w * (0.4 + glow * 0.5)
					draw_colored_polygon(PackedVector2Array([c0, c0 + Vector2.from_angle(a - 0.05) * ln, c0 + Vector2.from_angle(a + 0.05) * ln]), Color(col.r, col.g, col.b, 0.1 * glow))
			return
		var body := Rect2(w * 0.12, h * 0.38, w * 0.76, h * 0.52)
		# glow behind
		for k in 8:
			var gr := body.grow(14.0 + k * 10.0 * (0.4 + glow))
			_box(gr, Color(col.r, col.g, col.b, 0.035 * glow), 28)
		_box(Rect2(body.position + Vector2(0, 10), body.size), Color(0, 0, 0, 0.45), 14)
		_box(body, col.darkened(0.62), 14)
		_box(body.grow(-10), col.darkened(0.5), 10)
		# metal straps
		for x in [0.22, 0.78]:
			_box(Rect2(body.position.x + body.size.x * x - 10, body.position.y, 20, body.size.y), Color(0.12, 0.13, 0.15), 4)
		# glowing seam + emblem
		var seam := Color(col.r, col.g, col.b, 0.35 + glow * 0.65).lightened(glow * 0.4)
		draw_rect(Rect2(body.position.x, body.position.y - 2, body.size.x, 4 + glow * 4), seam)
		var c := body.get_center()
		draw_circle(c, 26, Color(0.1, 0.1, 0.12))
		draw_circle(c, 20, seam)
		# lid (lifts and rotates away when it bursts)
		var lr := Rect2(w * 0.08, h * 0.24 - lid * h * 0.5, w * 0.84, h * 0.16)
		draw_set_transform(lr.get_center(), -lid * 0.6, Vector2.ONE)
		var lrr := Rect2(-lr.size / 2, lr.size)
		_box(Rect2(lrr.position + Vector2(0, 6), lrr.size), Color(0, 0, 0, 0.4 * (1.0 - lid)), 12)
		_box(lrr, col.darkened(0.55), 12)
		_box(lrr.grow(-8), col.darkened(0.42), 8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# light leaking out of the seam
		if glow > 0.2:
			for i in 9:
				var x0 := body.position.x + body.size.x * (0.08 + i * 0.105)
				var ln := 60.0 + glow * 160.0 + sin(Time.get_ticks_msec() * 0.01 + i) * 16.0
				draw_colored_polygon(PackedVector2Array([Vector2(x0 - 6, body.position.y), Vector2(x0 + 6, body.position.y), Vector2(x0 + 22, body.position.y - ln), Vector2(x0 - 22, body.position.y - ln)]),
					Color(col.r, col.g, col.b, 0.12 * glow))

class GlowBG extends Control:
	## soft radial glow + slow light rays in the rarity colour
	var col := Color.WHITE
	var t := 0.0
	var power := 1.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size * Vector2(0.5, 0.42)
		var r: float = max(size.x, size.y) * 0.8
		for i in 24:
			var a0 := t * 0.12 + i * TAU / 24.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a0 + 0.05) * r]), Color(col.r, col.g, col.b, 0.022 * power))
		for k in 14:
			draw_circle(c, 420.0 - k * 28.0, Color(col.r, col.g, col.b, 0.008 * power * (k + 1) * 0.5))

func _rar_stars(r: int) -> String:
	return "★".repeat(r + 1) + "☆".repeat(3 - r)

func _info_chip(t: String, c: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(c.r, c.g, c.b, 0.14), Color(c.r, c.g, c.b, 0.5), 1, 16, 0))
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_child(UI.lbl(t, 15, c.lightened(0.2), "Rajdhani-Bold"))
	return p

func _crate_info_box(it: Dictionary) -> Control:
	## spec sheet of the won item: chips (type, duration, value) + stat bars in two columns
	var col: Color = it["color"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(0.02, 0.025, 0.035, 0.88), Color(col.r, col.g, col.b, 0.45), 1, 14, 18))
	p.custom_minimum_size = Vector2(820, 0)
	var v := UI.vbox(10)
	p.add_child(v)
	var chips := UI.hbox(8)
	v.add_child(chips)
	match str(it.get("type", "")):
		"weapon":
			var wid: String = it["id"]
			var w: Dictionary = GS.full_stats(wid)
			var dd := int(it.get("days", 0))
			chips.add_child(_info_chip("SİLAH  •  " + str(w.get("cls", "")).to_upper(), col))
			chips.add_child(_info_chip("SÜRESİZ" if dd == 0 else "%d GÜN" % dd, UI.GOLD if dd == 0 else Color("ff9a4a")))
			chips.add_child(_info_chip("Şarjör %d" % int(w.get("mag", 0)), Color("9fc8ff")))
			if it.get("ext", false):
				chips.add_child(_info_chip("SÜRE UZATILDI", UI.GREEN))
			if w.has("ability"):
				var ab := UI.lbl("★ " + str(w["ability"]), 16, Color("ffd8a8"), "Rajdhani-SemiBold")
				ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				v.add_child(ab)
			var g := GridContainer.new()
			g.columns = 2
			g.add_theme_constant_override("h_separation", 34)
			g.add_theme_constant_override("v_separation", 6)
			v.add_child(g)
			for row in _stat_rows(wid).slice(0, 6):
				g.add_child(_stat(row[0], row[1], row[2], true))
			if it.has("dup"):
				v.add_child(UI.lbl("Bu silah zaten sende: +%s altın verildi" % UI.money(int(it["dup"])), 15, UI.DIM, "Rajdhani-SemiBold"))
		"skin":
			var sd: Dictionary = GS.SKINS.get(it.get("id", "std"), {"name": "?", "price": 0, "rarity": 0})
			chips.add_child(_info_chip("STİL", col))
			chips.add_child(_info_chip(str(GS.WEAPONS.get(it.get("wid", ""), {}).get("name", "?")).to_upper(), Color("9fc8ff")))
			chips.add_child(_info_chip("Değer ◉ %s" % UI.money(int(sd.get("price", 0))), UI.GOLD))
			v.add_child(UI.lbl("Çanta > silah > STİLLER bölümünden kuşanabilirsin.", 16, UI.TEXT, "Rajdhani-SemiBold"))
			if it.has("dup"):
				v.add_child(UI.lbl("Bu stil zaten sende: +%s altın verildi" % UI.money(int(it["dup"])), 15, UI.DIM, "Rajdhani-SemiBold"))
		"part":
			var pd: Dictionary = GS.PARTS.get(it["id"], {})
			chips.add_child(_info_chip("EKLENTİ", col))
			var dl := UI.lbl(str(pd.get("desc", "Silah eklentisi: Çanta > EKLENTİ ile tak.")), 16, UI.TEXT, "Rajdhani-SemiBold")
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(dl)
		"char":
			var cd: Dictionary = GS.CHARACTERS.get(it["id"], {})
			chips.add_child(_info_chip("KARAKTER", col))
			var cl := UI.lbl(str(cd.get("desc", "Yeni karakter")), 16, UI.TEXT, "Rajdhani-SemiBold")
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(cl)
		"mat":
			chips.add_child(_info_chip("MALZEME", col))
			chips.add_child(_info_chip("x%d" % int(it["n"]), Color.WHITE))
			v.add_child(UI.lbl("Silah yükseltmede kullanılır (Çanta > YÜKSELT).", 16, UI.TEXT, "Rajdhani-SemiBold"))
		"gold":
			chips.add_child(_info_chip("ALTIN", UI.GOLD))
			v.add_child(UI.lbl("Hesabına eklendi. Market'te silah ve stil alabilirsin.", 16, UI.TEXT, "Rajdhani-SemiBold"))
	return p

## legendary animated skin unboxed: a fire-breathing dragon sweeps across the screen behind the reward
func _dragon_splash(ov: Control, vs: Vector2, col: Color) -> void:
	var pth := "res://assets/ui/dragon_splash.png"
	if not ResourceLoader.exists(pth):
		return
	var d := TextureRect.new()
	d.texture = load(pth)
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	d.size = Vector2(vs.y * 1.05 * 1.78, vs.y * 1.05)
	d.position = Vector2(-d.size.x, vs.y * 0.5 - d.size.y * 0.55)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.modulate = Color(1, 1, 1, 0.0)
	ov.add_child(d)
	ov.move_child(d, 1)
	var fire := CPUParticles2D.new()
	fire.amount = 220; fire.lifetime = 1.4; fire.preprocess = 0.0
	fire.direction = Vector2(1, 0.15); fire.spread = 18
	fire.initial_velocity_min = 500; fire.initial_velocity_max = 1100
	fire.scale_amount_min = 4.0; fire.scale_amount_max = 14.0
	var fg := Gradient.new()
	fg.set_color(0, Color(1, 0.95, 0.6, 1)); fg.add_point(0.4, Color(1, 0.45, 0.1, 0.9)); fg.set_color(1, Color(0.3, 0.05, 0.02, 0))
	fire.color_ramp = fg
	d.add_child(fire)
	fire.position = Vector2(d.size.x * 0.9, d.size.y * 0.42)
	SFX.play("explosion", -6, 0.6)
	var tw := ov.create_tween()
	tw.tween_property(d, "modulate:a", 0.78, 0.25)
	tw.parallel().tween_property(d, "position:x", vs.x * 0.5 - d.size.x * 0.5, 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_callback(func(): fire.emitting = false)
	tw.tween_property(d, "position:x", vs.x + 40.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(d, "modulate:a", 0.0, 0.9)
	tw.tween_callback(d.queue_free)

func _crate_reveal(it: Dictionary, label: String) -> void:
	## 1) the crate shakes and its seams glow  2) flash + burst  3) the item rises in the light with its spec sheet
	var col: Color = it["color"]
	var rar: int = clamp(int(it.get("rarity", 0)), 0, 3)
	var vs := get_viewport().get_visible_rect().size
	var ov := ColorRect.new()
	ov.color = Color(0.0, 0.0, 0.0, 0.0)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(ov)
	var bg := GlowBG.new()
	bg.col = col
	bg.power = 0.0
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(bg)
	var box := CrateBox.new()
	box.col = col
	box.tex = _crate_tex(crate_type)
	box.size = Vector2(360, 300)
	box.position = Vector2(vs.x * 0.5 - 180, vs.y * 0.42 - 170)
	box.pivot_offset = box.size * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(box)
	var fl := ColorRect.new()
	fl.color = Color(1, 1, 1, 0.0)
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(fl)
	# ---- the reward: big image, rarity ribbon, name, spec sheet
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.modulate.a = 0.0
	ov.add_child(stage)
	var rib := UI.lbl(_rar_stars(rar) + "   " + RARITY_NAMES[rar] + "   " + _rar_stars(rar), 26, col.lightened(0.15), "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	rib.custom_minimum_size = Vector2(900, 0)
	rib.position = Vector2(vs.x * 0.5 - 450, vs.y * 0.08)
	rib.add_theme_constant_override("outline_size", 6)
	rib.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	stage.add_child(rib)
	var img: Control
	match str(it.get("type", "")):
		"skin": img = thumb_rect(it["wid"], it["id"], Vector2(vs.y * 0.42 * 2.15, vs.y * 0.42))
		"weapon": img = thumb_rect(it["id"], "std", Vector2(vs.y * 0.42 * 2.15, vs.y * 0.42))
		_:
			img = _crate_card(it)
			img.custom_minimum_size = Vector2(300, 260)
	img.size = img.custom_minimum_size
	img.position = Vector2(vs.x * 0.5 - img.size.x * 0.5, vs.y * 0.36 - img.size.y * 0.5)
	img.pivot_offset = img.size * 0.5
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(img)
	# soft floor shadow under the item
	var sh := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	var g0 := Gradient.new(); g0.set_color(0, Color(0, 0, 0, 0.55)); g0.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g0
	sh.texture = gt
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.size = Vector2(520, 60)
	sh.position = Vector2(vs.x * 0.5 - 260, img.position.y + img.size.y - 20)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sh)
	var nm := UI.lbl(str(it.get("label", label)).to_upper(), 40, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	nm.custom_minimum_size = Vector2(1000, 0)
	nm.position = Vector2(vs.x * 0.5 - 500, img.position.y + img.size.y + 8)
	nm.add_theme_constant_override("outline_size", 8)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	stage.add_child(nm)
	var info := _crate_info_box(it)
	stage.add_child(info)
	info.position = Vector2(vs.x * 0.5 - 410, nm.position.y + 56)
	info.size = info.get_combined_minimum_size()
	info.resized.connect(func(): if info.size.y > info.get_combined_minimum_size().y + 2: info.size = info.get_combined_minimum_size())
	var bh := UI.hbox(12)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	(info.get_child(0) as VBoxContainer).add_child(bh)
	bh.add_child(UI.btn("✔ TAMAM", func(): ov.queue_free(), 20, true, 220, 48))
	if str(it.get("type", "")) in ["weapon", "skin"]:
		bh.add_child(UI.btn("ÇANTADA GÖR", func(): ov.queue_free(); show_page("bag"), 18, false, 220, 48))
	if str(it.get("type", "")) == "skin":
		bh.add_child(UI.btn("3D İNCELE", func(): ov.queue_free(); _inspect(str(it["wid"]), str(it["id"])), 18, false, 200, 48))
	var sp := CPUParticles2D.new()
	sp.position = Vector2(vs.x * 0.5, vs.y * 0.42)
	sp.amount = 140 + 70 * rar; sp.lifetime = 1.8; sp.one_shot = true; sp.explosiveness = 0.97
	sp.direction = Vector2(0, -1); sp.spread = 180
	sp.initial_velocity_min = 220; sp.initial_velocity_max = 700
	sp.gravity = Vector2(0, 380)
	sp.scale_amount_min = 2.0; sp.scale_amount_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(col, 0))
	sp.color_ramp = g
	sp.emitting = false
	ov.add_child(sp)
	# ---- timeline
	var tw := ov.create_tween()
	tw.tween_property(ov, "color", Color(0.01, 0.012, 0.02, 0.9), 0.25)
	box.scale = Vector2(0.6, 0.6)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	SFX.play("upgrade_charge", -4, 1.2)
	var shake_n := 10 + rar * 4
	for k in shake_n:
		var amp := 3.0 + k * 0.9
		tw.tween_property(box, "rotation", deg_to_rad(amp * (1 if k % 2 == 0 else -1) * 0.35), 0.05)
		tw.parallel().tween_property(box, "glow", float(k + 1) / shake_n, 0.05)
	tw.tween_property(box, "rotation", 0.0, 0.04)
	tw.tween_callback(func():
		sp.emitting = true
		SFX.play("success")
		if rar >= 2: SFX.play("medal", -2)
		if str(it.get("type", "")) == "skin" and GS.SKINS.get(str(it.get("id", "")), {}).get("anim", false):
			_dragon_splash(ov, vs, col)
		if rar >= 3: SFX.play("multikill", -4))
	tw.tween_property(fl, "color:a", 0.9 if rar >= 2 else 0.55, 0.06)
	tw.parallel().tween_property(box, "lid", 1.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(bg, "power", 1.0 + rar * 0.35, 0.5)
	tw.tween_property(fl, "color:a", 0.0, 0.4)
	img.scale = Vector2(0.3, 0.3)
	tw.parallel().tween_property(stage, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(img, "scale", Vector2(1.08, 1.08), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(info, "position:y", info.position.y, 0.45).from(info.position.y + 40).set_ease(Tween.EASE_OUT)
	tw.tween_property(img, "scale", Vector2.ONE, 0.25)
	tw.tween_callback(func():
		box.queue_free()
		var bob := img.create_tween().set_loops()
		bob.tween_property(img, "position:y", img.position.y - 10, 1.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(img, "position:y", img.position.y, 1.4).set_trans(Tween.TRANS_SINE))

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
	elif it["type"] == "char" and _agent_art(str(it["id"]), Vector2(0, 110), true):
		v.add_child(_agent_art(str(it["id"]), Vector2(0, 110), true))
	elif it["type"] == "char":
		var l2 := UI.lbl("👤", 64, it["color"], "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		l2.custom_minimum_size = Vector2(0, 110)
		v.add_child(l2)
	elif it["type"] == "mat" or it["type"] == "gold":
		var ic := CurIcon.new()
		ic.kind = "gold" if it["type"] == "gold" else "gem"
		ic.mat = str(it["id"]) if it["type"] == "mat" else ""
		ic.col = it["color"]
		ic.custom_minimum_size = Vector2(0, 110)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
	else:
		var l := UI.lbl("■" if it["type"] == "mat" else "◉", 60, it["color"], "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(0, 110)
		v.add_child(l)
	var t := UI.lbl(it["label"], 16, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return p

func _item_display(it: Dictionary) -> Dictionary:
	## raw crate result from the economy rules -> card data (label / colour / rarity)
	var d := it.duplicate()
	match str(it.get("type", "")):
		"mat":
			d["label"] = "%d %s" % [int(it["n"]), GS.MATS.get(it["id"], it["id"])]; d["color"] = Color("c8d2dc"); d["rarity"] = 0
		"gold":
			d["label"] = "%s Altın" % UI.money(int(it["n"])); d["color"] = UI.GOLD; d["rarity"] = 1
		"part":
			d["label"] = "EKLENTİ: " + str(GS.PARTS.get(it["id"], {}).get("name", it["id"])); d["color"] = Color("7dff6a"); d["rarity"] = 2
		"weapon":
			var dd := int(it.get("days", 0))
			d["label"] = "SİLAH: " + str(GS.WEAPONS.get(it["id"], {}).get("name", it["id"])) + ("  •  SÜRESİZ" if dd == 0 else "  •  %d GÜN" % dd) + ("  (süre uzatıldı)" if it.get("ext", false) else "")
			d["color"] = Color("ff5a5a") if dd == 0 else Color("ff9a4a"); d["rarity"] = 3 if dd == 0 else 2
		"char":
			d["label"] = "KARAKTER: " + str(GS.CHARACTERS.get(it["id"], {}).get("name", it["id"])); d["color"] = Color("ff4df0"); d["rarity"] = 3
		_:
			var sd: Dictionary = GS.SKINS.get(it.get("id", "std"), {"name": "?", "rarity": 0})
			d["type"] = "skin"
			d["label"] = "%s | %s" % [GS.WEAPONS.get(it.get("wid", "ak47"), {}).get("name", "?"), sd["name"]]
			d["color"] = GS.RARITY_COLORS[int(sd["rarity"])]; d["rarity"] = int(sd["rarity"])
	return d

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

# ================================================================ MODE SELECT (after login)
func _refresh_mode_chip() -> void:
	if mode_chip == null:
		return
	var on := GS.play_mode == "online"
	mode_chip.text = ("●  ÇEVRİMİÇİ" if on else "◆  BOT MODU") + "   ⇄"
	var c: Color = UI.GREEN if on else UI.ACCENT
	for st in ["normal", "hover", "pressed"]:
		var b := UI.sb(Color(c.r, c.g, c.b, 0.22 if st == "hover" else 0.12), Color(c.r, c.g, c.b, 0.7), 1, 4, 0)
		b.content_margin_left = 12; b.content_margin_right = 12
		mode_chip.add_theme_stylebox_override(st, b)
	mode_chip.add_theme_color_override("font_color", c.lightened(0.25))
	mode_chip.add_theme_color_override("font_hover_color", Color.WHITE)

func _choose_mode(md: String) -> void:
	if md == "online" and not Online.is_logged_in():
		_toast("Çevrimiçi oynamak için hesabınla giriş yapmalısın.", UI.RED)
		main.go_login()
		return
	GS.play_mode = md
	SFX.play("success", -8)
	show_page("rooms" if md == "online" else "lobby")

func _page_mode() -> void:
	soldier.visible = false
	if studio:
		studio.visible = false
	cam_target = Vector3(0.5, 1.7, 7.5)
	var root := Control.new()
	_margin(root, 0, 0, 0, 0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.03, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var v := UI.vbox(10)
	cc.add_child(v)
	var hi := "Hoş geldin, %s!" % (Online.username if Online.is_logged_in() else str(GS.profile.get("name", "Oyuncu")))
	v.add_child(UI.lbl(hi.to_upper(), 20, UI.ACCENT2, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.lbl("OYUN MODUNU SEÇ", 54, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.lbl("İstediğin zaman üst çubuktaki mod düğmesinden değiştirebilirsin.", 19, UI.DIM, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER))
	var acc := UI.hbox(10)
	acc.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(acc)
	if Online.is_logged_in():
		acc.add_child(UI.lbl("Hesap: %s" % Online.username, 18, UI.GREEN, "Rajdhani-Bold"))
	else:
		acc.add_child(UI.lbl("Çevrimdışı profil", 18, UI.DIM, "Rajdhani-Bold"))
	acc.add_child(UI.btn("HESAP DEĞİŞTİR / YENİ HESAP", func():
		if Online.is_logged_in():
			await Online.logout()
		main.go_login(), 15, false, 0, 34))
	v.add_child(UI.spacer(false, 0, 16))
	var row := UI.hbox(34)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	# BOT card
	var bot := _mode_card("res://assets/ui/mode_bot.jpg", UI.ACCENT, "ANTRENMAN  •  İNTERNETSİZ", "BOT MODU",
		"Yapay zekâ botlarına karşı oyna. Bütün haritalar, 5 oyun modu ve istediğin zorluk.", "BOTLARLA OYNA", func(): _choose_mode("bot"))
	row.add_child(bot[0])
	var bs := UI.hbox(26)
	bot[1].add_child(bs)
	for pair in [[str(GS.MAPS.size()), "HARİTA"], [str(GS.MODES.size()), "OYUN MODU"], ["3", "ZORLUK"]]:
		bs.add_child(_mode_stat(pair[0], pair[1], UI.ACCENT2))
	# ONLINE card
	var on := _mode_card("res://assets/ui/mode_online.jpg", UI.GREEN, "●  CANLI  •  GERÇEK OYUNCULAR", "ÇEVRİMİÇİ",
		"Gerçek oyuncularla oyna. Oda kur, arkadaşlarını davet et ya da açık odalara katıl.",
		"ÇEVRİMİÇİ OYNA" if Online.is_logged_in() else "GİRİŞ YAP VE OYNA", func(): _choose_mode("online"))
	row.add_child(on[0])
	var os := UI.hbox(26)
	on[1].add_child(os)
	if Online.is_logged_in():
		var l1 := _mode_stat("…", "ÇEVRİMİÇİ OYUNCU", UI.GREEN)
		var l2 := _mode_stat("…", "AÇIK ODA", UI.GREEN)
		var l3 := _mode_stat("…", "ARKADAŞ ÇEVRİMİÇİ", UI.GREEN)
		for x in [l1, l2, l3]:
			os.add_child(x)
		_mode_live(l1, l2, l3)
		var tm := Timer.new()
		tm.wait_time = 10.0
		tm.autostart = true
		tm.timeout.connect(func(): _mode_live(l1, l2, l3))
		root.add_child(tm)
	else:
		os.add_child(UI.lbl("Çevrimiçi oynamak için hesabınla giriş yapmalısın.", 19, UI.ACCENT2, "Rajdhani-Bold"))

func _mode_stat(val: String, cap: String, c: Color) -> VBoxContainer:
	var vv := UI.vbox(-6)
	var n := UI.lbl(val, 40, c, "Teko")
	n.name = "N"
	vv.add_child(n)
	vv.add_child(UI.lbl(cap, 14, Color(0.85, 0.88, 0.92), "Rajdhani-Bold"))
	return vv

func _mode_live(l1: Control, l2: Control, l3: Control) -> void:
	var n: int = await Online.count_online()
	var rooms: Array = await Online.list_rooms()
	var fo := 0
	for f in Online.friends:
		if f is Dictionary and bool(f.get("online", false)) and not bool(f.get("pending", false)):
			fo += 1
	for pair in [[l1, maxi(n, 1)], [l2, rooms.size()], [l3, fo]]:
		if is_instance_valid(pair[0]):
			(pair[0].get_node("N") as Label).text = str(pair[1])

func _mode_card(img: String, accent: Color, tag: String, title: String, desc: String, btn_text: String, cb: Callable) -> Array:
	## returns [card, stats_box]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(640, 620)
	card.pivot_offset = Vector2(320, 310)
	var sb0 := UI.sb(Color(0.03, 0.035, 0.05, 1), Color(accent.r, accent.g, accent.b, 0.35), 2, 6, 0)
	var sb1 := UI.sb(Color(0.03, 0.035, 0.05, 1), accent, 3, 6, 0)
	card.add_theme_stylebox_override("panel", sb0)
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layer)
	var tr := TextureRect.new()
	tr.texture = load(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	var gr := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.035, 0.05))
	g.set_color(1, Color(0.02, 0.025, 0.035, 0.98))
	g.add_point(0.38, Color(0.02, 0.025, 0.035, 0.5))
	g.add_point(0.62, Color(0.02, 0.025, 0.035, 0.88))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gr.texture = gt
	gr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gr.set_anchors_preset(Control.PRESET_FULL_RECT)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(gr)
	var top := ColorRect.new()
	top.color = accent
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 5)
	top.size = Vector2(640, 5)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	var mg := MarginContainer.new()
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + k, 34)
	mg.add_theme_constant_override("margin_bottom", 30)
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mg)
	var v := UI.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mg.add_child(v)
	v.add_child(UI.lbl(tag, 17, accent.lightened(0.2), "Rajdhani-Bold"))
	var t := UI.lbl(title, 58, Color.WHITE, "RussoOne-Regular")
	v.add_child(t)
	var d := UI.lbl(desc, 20, Color(0.82, 0.85, 0.9), "Rajdhani-SemiBold")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(560, 0)
	v.add_child(d)
	var stats := UI.vbox(0)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stats)
	v.add_child(UI.spacer(false, 0, 8))
	var b := UI.btn("▶   " + btn_text, cb, 26, true, 0, 66)
	b.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	if accent == UI.GREEN:
		for st in ["normal", "hover", "pressed"]:
			var bb := UI.sb(accent.darkened(0.45 if st == "normal" else 0.3), accent, 2, 4, 0)
			b.add_theme_stylebox_override(st, bb)
		b.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(b)
	card.mouse_entered.connect(func():
		card.add_theme_stylebox_override("panel", sb1)
		var tw := card.create_tween(); tw.tween_property(card, "scale", Vector2(1.025, 1.025), 0.12)
		SFX.play("ui_hover", -14))
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", sb0)
		var tw := card.create_tween(); tw.tween_property(card, "scale", Vector2.ONE, 0.12))
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	return [card, stats]

# ================================================================ ROOMS
var fake_rooms: Array = []
func _page_rooms() -> void:
	if GS.play_mode == "online":
		online.page_online_rooms()
		return
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
	th.add_child(UI.header("BOT ODALARI", 28))
	th.add_child(UI.spacer())
	th.add_child(UI.btn("YENİLE", func(): _gen_rooms(); show_page("rooms"), 18, false, 120, 42))
	th.add_child(UI.btn("ODA KUR (BOTLARLA)", _create_room_dialog, 18, false, 210, 42))
	th.add_child(UI.btn("● ÇEVRİMİÇİ MODA GEÇ", func(): _choose_mode("online"), 16, false, 220, 42))
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
		var vals := [str(r["no"]), ("⊘ " if r.get("pass", false) else "") + r["name"], GS.MAPS[r["map"]]["name"], GS.MODES[r["mode"]]["name"], "%d/16" % (r["bots"] + 1), "Bekliyor" if not r.get("playing", false) else "Oyunda"]
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
	if GS.play_mode == "online":
		if not Online.is_logged_in():
			show_page("mode"); return
		var oc: Dictionary = online.room_cfg.duplicate()
		oc["name"] = "%s'in Odası" % Online.username
		_room_dialog(oc, true, func(c): online.room_cfg = c; online.create_room())
		return
	var cfg := {"name": str(GS.profile["name"]) + " odası", "map": "mahalle", "mode": "ffa", "bots": 9, "diff": 1, "time": 8, "target": 40, "team": "a", "no": randi_range(100, 999)}
	_room_dialog(cfg)

const MODE_ICONS := {"tdm": "⚔", "ffa": "✦", "gungame": "↑", "knife": "✂", "sniper": "◎", "sabotaj": "✹"}
const MODE_SHORT := {"tdm": "Takımlar en çok öldürmeye yarışır", "ffa": "Herkes herkese karşı", "gungame": "Her öldürmede yeni silah",
	"knife": "Sadece bıçaklar", "sniper": "Sadece nişancı tüfekleri", "sabotaj": "Bomba kur / çöz, turlu oyun"}

func _chip(text: String, on: bool, cb: Callable, w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 38)
	b.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", UI.sb(Color(1, 0.55, 0.12, 0.22) if on else Color(1, 1, 1, 0.05), UI.ACCENT if on else Color(1, 1, 1, 0.1), 1, 8, 8))
	b.add_theme_stylebox_override("hover", UI.sb(Color(1, 1, 1, 0.1), UI.ACCENT2, 1, 8, 8))
	b.add_theme_stylebox_override("pressed", UI.sb(Color(1, 0.55, 0.12, 0.3), UI.ACCENT, 1, 8, 8))
	b.add_theme_color_override("font_color", Color.WHITE if on else UI.TEXT)
	b.pressed.connect(func(): SFX.play("ui_click", -8); cb.call())
	return b

func _set_label(v: VBoxContainer, t: String) -> void:
	v.add_child(UI.lbl(t, 14, UI.DIM, "Rajdhani-Bold"))

## modern room setup, shared by bot rooms and online rooms.
## online: shows player limit / ranked instead of bots. done: called with the final cfg (null = bot room default)
func _room_dialog(cfg: Dictionary, is_online: bool = false, done: Callable = Callable()) -> void:
	var v := _modal(1280, 790)
	var top := UI.hbox(12)
	v.add_child(top)
	var tv := UI.vbox(-4)
	top.add_child(tv)
	tv.add_child(UI.lbl("ODA AYARLARI" if cfg.has("_edit") else "ODA KUR", 32, Color.WHITE, "RussoOne-Regular"))
	tv.add_child(UI.lbl(("ÇEVRİMİÇİ ODA  •  arkadaşlarınla oyna" if is_online else "BOT ODASI  •  yapay zekâya karşı"), 15, UI.ACCENT2, "Rajdhani-Bold"))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("✕", _close_modal, 20, false, 44, 40))
	var body := UI.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var redraw := func(): _room_dialog(cfg, is_online, done)
	# ---------------- left: name, map, mode
	var left := UI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_set_label(left, "ODA ADI")
	var le := LineEdit.new()
	le.text = str(cfg["name"])
	le.max_length = 28
	le.custom_minimum_size = Vector2(0, 44)
	le.text_changed.connect(func(t): cfg["name"] = t)
	left.add_child(le)
	_set_label(left, "HARİTA")
	var mg := GridContainer.new()
	mg.columns = 3
	mg.add_theme_constant_override("h_separation", 10)
	mg.add_theme_constant_override("v_separation", 10)
	left.add_child(mg)
	for mid in GS.MAPS.keys():
		var sel: bool = cfg["map"] == mid
		var b := Button.new()
		b.custom_minimum_size = Vector2(238, 118)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		b.add_theme_stylebox_override("normal", UI.sb(Color(0.05, 0.06, 0.08), UI.ACCENT if sel else Color(1, 1, 1, 0.08), 3 if sel else 1, 10, 0))
		b.add_theme_stylebox_override("hover", UI.sb(Color(0.08, 0.09, 0.12), UI.ACCENT2, 2, 10, 0))
		b.add_theme_stylebox_override("pressed", UI.sb(Color(0.05, 0.06, 0.08), UI.ACCENT, 3, 10, 0))
		var img := _map_image(mid)
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.offset_left = 3; img.offset_right = -3; img.offset_top = 3; img.offset_bottom = -3
		img.modulate = Color(1, 1, 1) if sel else Color(0.72, 0.72, 0.76)
		b.add_child(img)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.55)
		shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		shade.offset_top = -38; shade.offset_left = 3; shade.offset_right = -3; shade.offset_bottom = -3
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(shade)
		var l := UI.lbl(GS.MAPS[mid]["name"].to_upper(), 19, Color.WHITE, "RussoOne-Regular")
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -36; l.offset_left = 12
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		var sz := UI.lbl(str(GS.MAPS[mid].get("size", "")).to_upper(), 13, UI.ACCENT2, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
		sz.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		sz.offset_top = -30; sz.offset_right = -12
		sz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sz)
		if sel:
			var ck := UI.lbl("✔", 20, UI.ACCENT, "Rajdhani-Bold")
			ck.position = Vector2(12, 6)
			ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(ck)
		b.pressed.connect(func(): cfg["map"] = mid; SFX.play("ui_click", -6); redraw.call())
		mg.add_child(b)
	_set_label(left, "OYUN MODU")
	var mdg := GridContainer.new()
	mdg.columns = 3
	mdg.add_theme_constant_override("h_separation", 10)
	mdg.add_theme_constant_override("v_separation", 10)
	left.add_child(mdg)
	for md in GS.MODES.keys():
		var on: bool = cfg["mode"] == md
		var mb := Button.new()
		mb.focus_mode = Control.FOCUS_NONE
		mb.custom_minimum_size = Vector2(238, 64)
		mb.add_theme_stylebox_override("normal", UI.sb(Color(1, 0.55, 0.12, 0.16) if on else Color(1, 1, 1, 0.04), UI.ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1, 10, 0))
		mb.add_theme_stylebox_override("hover", UI.sb(Color(1, 1, 1, 0.08), UI.ACCENT2, 1, 10, 0))
		mb.add_theme_stylebox_override("pressed", UI.sb(Color(1, 0.55, 0.12, 0.25), UI.ACCENT, 2, 10, 0))
		var mh := UI.hbox(10)
		mh.set_anchors_preset(Control.PRESET_FULL_RECT)
		mh.offset_left = 12
		mh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mb.add_child(mh)
		var ic := UI.lbl(str(MODE_ICONS.get(md, "•")), 28, UI.ACCENT if on else UI.DIM, "Rajdhani-Bold")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.custom_minimum_size = Vector2(30, 0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mh.add_child(ic)
		var mv := UI.vbox(-4)
		mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mh.add_child(mv)
		var n1 := UI.lbl(str(GS.MODES[md]["name"]).to_upper(), 18, Color.WHITE, "Rajdhani-Bold")
		n1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.add_child(n1)
		var n2 := UI.lbl(str(MODE_SHORT.get(md, "")), 13, UI.DIM, "Rajdhani-SemiBold")
		n2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.add_child(n2)
		mb.pressed.connect(func():
			cfg["mode"] = md
			cfg["target"] = 6 if md == "sabotaj" else (60 if GS.MODES[md]["teams"] else 40)
			SFX.play("ui_click", -6); redraw.call())
		mdg.add_child(mb)
	# ---------------- right: settings + summary
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", UI.sb(Color(0.03, 0.035, 0.05, 0.95), Color(1, 1, 1, 0.08), 1, 12, 18))
	rp.custom_minimum_size = Vector2(430, 0)
	body.add_child(rp)
	var r := UI.vbox(10)
	rp.add_child(r)
	r.add_child(UI.lbl("KURALLAR", 20, UI.ACCENT, "RussoOne-Regular"))
	var sab: bool = cfg["mode"] == "sabotaj"
	if sab:
		_set_label(r, "KAZANMAK İÇİN TUR")
		var rh := UI.hbox(6)
		r.add_child(rh)
		for n in [3, 5, 6, 8, 10]:
			rh.add_child(_chip(str(n), int(cfg["target"]) == n, func(): cfg["target"] = n; redraw.call(), 64))
		var info := PanelContainer.new()
		info.add_theme_stylebox_override("panel", UI.sb(Color(1, 0.55, 0.12, 0.08), Color(1, 0.55, 0.12, 0.3), 1, 8, 10))
		r.add_child(info)
		var il := UI.lbl("✹ Tur süresi 1:45  •  Bomba 35 sn'de patlar\n✹ Kurma 3,2 sn  •  Çözme 5 sn (E basılı tut)\n✹ Ölen oyuncu tur sonunu bekler", 15, Color("ffd8a8"), "Rajdhani-SemiBold")
		info.add_child(il)
	else:
		_set_label(r, "SÜRE")
		var th := UI.hbox(6)
		r.add_child(th)
		for t in [5, 8, 10, 15, 20]:
			th.add_child(_chip("%d dk" % t, int(cfg["time"]) == t, func(): cfg["time"] = t; redraw.call(), 72))
		_set_label(r, "HEDEF SKOR")
		var sh := UI.hbox(6)
		r.add_child(sh)
		var targets := [20, 40, 60, 80, 100] if GS.MODES[cfg["mode"]]["teams"] else [15, 25, 40, 60, 80]
		if cfg["mode"] == "gungame":
			sh.add_child(UI.lbl("Tüm silahları ilk bitiren kazanır", 15, UI.DIM, "Rajdhani-SemiBold"))
		else:
			for t in targets:
				sh.add_child(_chip(str(t), int(cfg["target"]) == t, func(): cfg["target"] = t; redraw.call(), 72))
	if is_online:
		_set_label(r, "OYUNCU SINIRI")
		var ph := UI.hbox(6)
		r.add_child(ph)
		for n in [2, 4, 6, 8, 10]:
			ph.add_child(_chip(str(n), int(cfg.get("max", 10)) == n, func(): cfg["max"] = n; redraw.call(), 64))
		var oh := UI.hbox(6)
		r.add_child(oh)
		oh.add_child(_chip("★ DERECELİ " + ("AÇIK" if cfg.get("ranked", false) else "KAPALI"), cfg.get("ranked", false), func(): cfg["ranked"] = not cfg.get("ranked", false); redraw.call(), 200))
		oh.add_child(_chip("ÖZEL ODA (kodla)" if cfg.get("private", false) else "HERKESE AÇIK", cfg.get("private", false), func(): cfg["private"] = not cfg.get("private", false); redraw.call(), 190))
	else:
		_set_label(r, "BOT SAYISI")
		var bh := UI.hbox(6)
		r.add_child(bh)
		for n in [3, 5, 7, 9, 11, 15]:
			bh.add_child(_chip(str(n), int(cfg["bots"]) == n, func(): cfg["bots"] = n; redraw.call(), 54))
		_set_label(r, "BOT ZORLUĞU")
		var dh := UI.hbox(6)
		r.add_child(dh)
		for d in [[0, "KOLAY"], [1, "NORMAL"], [2, "ZOR"]]:
			dh.add_child(_chip(d[1], int(cfg["diff"]) == d[0], func(): cfg["diff"] = d[0]; redraw.call(), 110))
		if GS.MODES[cfg["mode"]]["teams"]:
			_set_label(r, "TAKIMIN")
			var tmh := UI.hbox(6)
			r.add_child(tmh)
			for t in ["a", "b"]:
				tmh.add_child(_chip(str(GS.TEAMS[t]) + ("  (saldırı)" if sab and t == "a" else ("  (savunma)" if sab else "")), cfg.get("team", "a") == t, func(): cfg["team"] = t; redraw.call(), 180))
	r.add_child(UI.spacer())
	# summary
	var sm := PanelContainer.new()
	sm.add_theme_stylebox_override("panel", UI.sb(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 1, 10, 10))
	r.add_child(sm)
	var smh := UI.hbox(12)
	sm.add_child(smh)
	var th2 := _map_image(cfg["map"])
	th2.custom_minimum_size = Vector2(120, 70)
	smh.add_child(th2)
	var smv := UI.vbox(0)
	smh.add_child(smv)
	smv.add_child(UI.lbl(str(GS.MAPS[cfg["map"]]["name"]).to_upper() + "  •  " + str(GS.MODES[cfg["mode"]]["name"]).to_upper(), 17, Color.WHITE, "Rajdhani-Bold"))
	var line2 := ("İlk %d tur" % int(cfg["target"])) if sab else ("%d dk  •  hedef %d" % [int(cfg["time"]), int(cfg["target"])])
	line2 += ("  •  en fazla %d oyuncu" % int(cfg.get("max", 10))) if is_online else ("  •  %d bot  •  %s" % [int(cfg["bots"]), ["Kolay", "Normal", "Zor"][int(cfg["diff"])]])
	smv.add_child(UI.lbl(line2, 14, UI.DIM, "Rajdhani-SemiBold"))
	var go := UI.btn(("✔ AYARLARI KAYDET" if cfg.has("_edit") else "▶ ODAYI OLUŞTUR"), func():
		cfg.erase("_edit")
		_close_modal()
		if done.is_valid():
			done.call(cfg)
		else:
			room_cfg = cfg; show_page("room"), 24, true, 0, 60)
	r.add_child(go)

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


# ================================================================ ROOM LAYOUT (bot + online rooms share it)
## o: title, no, map, mode, time, target, teams, players[{name,lvl,team,host,you,ready,rp}], info_extra[[k,v]],
##    on_settings, on_leave, on_invite, on_start (Callable or null), wait_text, chat_log[[who,text,color]],
##    on_chat(text), host_box(Callable(container)), start_text
func room_layout(o: Dictionary) -> Dictionary:
	var out := {}
	soldier.visible = true
	cam_target = Vector3(-0.35, 1.45, 4.3)
	cam_look = Vector3(-0.45, 1.05, 0)
	# ---- left: loadout + room card
	var left := UI.vbox(10)
	left.position = Vector2(24, 12)
	left.custom_minimum_size = Vector2(392, 0)
	content.add_child(left)
	left.add_child(_sets_panel(true))
	var card := UI.panel(Color(0.025, 0.03, 0.045, 0.94), UI.LINE, 0, 1)
	left.add_child(card)
	var cv := UI.vbox(0)
	card.add_child(cv)
	var top := UI.hbox(0)
	cv.add_child(top)
	var img := _map_image(str(o["map"]))
	img.custom_minimum_size = Vector2(170, 118)
	top.add_child(img)
	var ig := GridContainer.new()
	ig.columns = 2
	ig.add_theme_constant_override("h_separation", 10)
	ig.add_theme_constant_override("v_separation", 2)
	var igm := MarginContainer.new()
	for sd in ["left", "top", "right"]:
		igm.add_theme_constant_override("margin_" + sd, 10)
	igm.add_child(ig)
	igm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(igm)
	var rows: Array = [["Harita", GS.MAPS[o["map"]]["name"]], ["Mod", GS.MODES[o["mode"]]["name"]], ["Süre", "%d dk" % int(o["time"])], ["Hedef", str(o["target"])]]
	rows.append_array(o.get("info_extra", []))
	for pair in rows:
		ig.add_child(UI.lbl(str(pair[0]), 14, Color("ff6a5a"), "Rajdhani-Bold"))
		var vl := UI.lbl(str(pair[1]), 15, Color.WHITE, "Rajdhani-Bold")
		vl.custom_minimum_size = Vector2(130, 0)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.clip_text = true
		ig.add_child(vl)
	var brow := UI.hbox(6)
	var bm := MarginContainer.new()
	for sd in ["left", "right", "bottom", "top"]:
		bm.add_theme_constant_override("margin_" + sd, 8)
	bm.add_child(brow)
	cv.add_child(bm)
	var nm := UI.lbl(str(o.get("title", "")), 17, UI.ACCENT2, "Rajdhani-Bold")
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(nm)
	if o.get("on_settings") is Callable:
		brow.add_child(UI.btn("DEĞİŞTİR", o["on_settings"], 14, false, 96, 32))
	if o.get("on_invite") is Callable:
		brow.add_child(UI.btn("DAVET ET", o["on_invite"], 14, false, 96, 32))
	# ---- stage: two team columns with the 3D soldier between them
	var stage := Control.new()
	stage.anchor_left = 0; stage.anchor_right = 1; stage.anchor_top = 0; stage.anchor_bottom = 0.6
	stage.offset_left = 430; stage.offset_right = -24; stage.offset_top = 12
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(stage)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", UI.sb(Color(0, 0, 0, 0), Color(1, 1, 1, 0.12), 1, 6, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(frame)
	var teams: bool = o.get("teams", true)
	var groups := [["a", GS.TEAMS["a"], 0], ["b", GS.TEAMS["b"], 1]] if teams else [["", "OYUNCULAR", 0]]
	for gt in groups:
		var col := UI.vbox(3)
		col.anchor_top = 0; col.anchor_bottom = 1
		col.offset_top = 10; col.offset_bottom = -10
		if int(gt[2]) == 0:
			col.anchor_left = 0; col.anchor_right = 0; col.offset_left = 10; col.offset_right = 330
		else:
			col.anchor_left = 1; col.anchor_right = 1; col.offset_left = -330; col.offset_right = -10
		stage.add_child(col)
		var tc: Color = GS.TEAM_COLORS.get(gt[0], UI.ACCENT)
		var head := Panel.new()
		head.custom_minimum_size = Vector2(320, 44)
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = tc.darkened(0.35); hsb.skew = Vector2(-0.25 if int(gt[2]) == 0 else 0.25, 0)
		hsb.border_width_bottom = 3; hsb.border_color = tc.lightened(0.3)
		head.add_theme_stylebox_override("panel", hsb)
		col.add_child(head)
		var hl := UI.lbl(str(gt[1]), 26, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		head.add_child(hl)
		var n := 0
		for pl in o.get("players", []):
			if gt[0] != "" and str(pl.get("team", "")) != gt[0]:
				continue
			n += 1
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", UI.sb(Color(tc.r * 0.25, tc.g * 0.25, tc.b * 0.25, 0.85) if pl.get("you", false) else Color(0.03, 0.035, 0.05, 0.82), tc if pl.get("you", false) else Color(1, 1, 1, 0.06), 1, 3, 6))
			col.add_child(row)
			var rh := UI.hbox(8)
			row.add_child(rh)
			var ri: Dictionary = GS.rank_info(int(pl.get("rp", 0)))
			var em := TextureRect.new()
			em.texture = ri["icon"]; em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; em.custom_minimum_size = Vector2(26, 26)
			em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rh.add_child(em)
			var nl := UI.lbl(str(pl["name"]), 18, Color.WHITE, "Rajdhani-Bold")
			nl.clip_text = true; nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_child(nl)
			if pl.get("host", false):
				rh.add_child(UI.lbl("★", 16, UI.GOLD, "Rajdhani-Bold"))
			rh.add_child(UI.lbl("%d" % int(pl.get("lvl", 1)), 15, UI.ACCENT2, "Teko"))
			rh.add_child(UI.lbl("✔" if pl.get("ready", true) else "…", 16, UI.GREEN if pl.get("ready", true) else UI.DIM, "Rajdhani-Bold"))
		for k in maxi(0, 8 - n):
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(0, 34)
			empty.add_theme_stylebox_override("panel", UI.sb(Color(0.02, 0.025, 0.035, 0.45), Color(1, 1, 1, 0.03), 1, 3, 6))
			col.add_child(empty)
	# ---- bottom: chat (centre) + action panel (right)
	var bottom := UI.hbox(12)
	bottom.anchor_left = 0; bottom.anchor_right = 1; bottom.anchor_top = 0.6; bottom.anchor_bottom = 1
	bottom.offset_left = 430; bottom.offset_right = -24; bottom.offset_top = 10; bottom.offset_bottom = -16
	content.add_child(bottom)
	var chat_p := UI.panel(Color(0.02, 0.025, 0.035, 0.92), UI.LINE, 10)
	chat_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(chat_p)
	var chv := UI.vbox(6)
	chat_p.add_child(chv)
	var tabs := UI.hbox(4)
	chv.add_child(tabs)
	tabs.add_child(UI.btn("GENEL", func(): pass, 14, true, 90, 30))
	tabs.add_child(UI.btn("TAKIM", func(): pass, 14, false, 90, 30))
	tabs.add_child(UI.spacer())
	tabs.add_child(UI.lbl("ODA %s" % str(o.get("no", "")), 15, UI.GOLD, "Rajdhani-Bold"))
	var csc := ScrollContainer.new()
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chv.add_child(csc)
	var chat := UI.vbox(2)
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csc.add_child(chat)
	out["chat"] = chat
	out["chat_scroll"] = csc
	var ch := UI.hbox(6)
	chv.add_child(ch)
	var ce := LineEdit.new()
	ce.placeholder_text = "Mesaj yaz ve Enter'a bas..."
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.custom_minimum_size = Vector2(0, 36)
	ch.add_child(ce)
	var send := func():
		var t := ce.text.strip_edges()
		if t == "": return
		ce.text = ""
		if o.get("on_chat") is Callable:
			(o["on_chat"] as Callable).call(t)
	ce.text_submitted.connect(func(_x): send.call())
	ch.add_child(UI.btn("GÖNDER ›", send, 14, true, 100, 36))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(330, 0)
	bottom.add_child(right)
	var up := UI.panel(Color(0.02, 0.025, 0.035, 0.92), UI.LINE, 10)
	up.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(up)
	var uv := UI.vbox(4)
	up.add_child(uv)
	if o.get("host_box") is Callable:
		(o["host_box"] as Callable).call(uv)
	else:
		uv.add_child(UI.lbl("KULLANICI LİSTESİ", 16, UI.DIM, "Rajdhani-Bold"))
		for pl in o.get("players", []):
			uv.add_child(UI.lbl(("● " if pl.get("you", false) else "   ") + str(pl["name"]) + "  (%d)" % int(pl.get("lvl", 1)), 15, UI.ACCENT2 if pl.get("you", false) else UI.TEXT, "Rajdhani-SemiBold"))
	var bh := UI.hbox(6)
	right.add_child(bh)
	if o.get("on_leave") is Callable:
		bh.add_child(UI.btn("ÇIKIŞ", o["on_leave"], 16, false, 100, 64))
	if o.get("on_start") is Callable:
		var start := UI.btn(str(o.get("start_text", "BAŞLAT")), Callable(), 30, true, 0, 64)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.add_theme_font_override("font", UI.font("RussoOne-Regular"))
		start.pressed.connect(func(): (o["on_start"] as Callable).call(start))
		bh.add_child(start)
		out["start"] = start
	else:
		var wl := UI.lbl(str(o.get("wait_text", "Kurucu bekleniyor...")), 16, UI.ACCENT2, "Rajdhani-Bold")
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(wl)
	return out

# ================================================================ ROOM LOBBY
func _page_room() -> void:
	if room_cfg.is_empty():
		_quick_play()
		return
	set_showcase(GS.active_set().get("ana", "ak47"))
	var cfg := room_cfg
	var teams: bool = GS.MODES[cfg["mode"]]["teams"]
	local_room = true
	var key := "%s|%s|%s|%d|%s" % [str(cfg.get("no", "")), str(cfg["map"]), str(cfg["mode"]), int(cfg["bots"]), str(cfg.get("name", ""))]
	if key != _room_key or room_players.is_empty():
		# new room: roll the bot line-up once; coming back to the same room keeps it
		_room_key = key
		_room_log.clear()
		room_players.clear()
		room_players.append({"name": str(GS.profile["name"]), "lvl": int(GS.profile["level"]), "team": "", "you": true, "ready": true, "host": true, "rp": int(GS.profile.get("rp", 0))})
		var names := GS.BOT_NAMES.duplicate()
		names.shuffle()
		for i in int(cfg["bots"]):
			room_players.append({"name": names[i % names.size()], "lvl": randi_range(5, 80), "team": "", "you": false, "ready": randf() < 0.8, "rp": randi_range(0, 3200), "bi": i})
	for rp_ in room_players:
		if rp_["you"]:
			rp_["team"] = cfg.get("team", "a") if teams else ""
		elif teams:
			rp_["team"] = "b" if int(rp_.get("bi", 0)) % 2 == 0 else "a"
		else:
			rp_["team"] = ""
	var lay := room_layout({"title": str(cfg["name"]), "no": cfg["no"], "map": cfg["map"], "mode": cfg["mode"], "time": cfg["time"], "target": cfg["target"],
		"teams": teams, "players": room_players,
		"info_extra": [["Zorluk", ["Kolay", "Normal", "Zor"][int(cfg["diff"])]], ["Oyuncu", "%d / 16" % room_players.size()]],
		"on_settings": func(): cfg["_edit"] = true; _room_dialog(cfg),
		"on_leave": func(): local_room = false; _room_key = ""; show_page("rooms"),
		"on_chat": func(t): _chat(str(GS.profile["name"]), t, Color.WHITE); _bot_reply(),
		"host_box": func(box):
			box.add_child(UI.lbl("ODA AYARLARI", 16, UI.DIM, "Rajdhani-Bold"))
			box.add_child(UI.lbl("Botlar: %d   •   %s" % [int(cfg["bots"]), ["Kolay", "Normal", "Zor"][int(cfg["diff"])]], 17, Color.WHITE, "Rajdhani-Bold"))
			if teams:
				box.add_child(UI.btn("TAKIM DEĞİŞTİR", func(): room_cfg["team"] = "b" if room_cfg.get("team", "a") == "a" else "a"; show_page("room"), 16, false, 0, 40))
			box.add_child(UI.btn("ODA AYARLARI", func(): _room_dialog(cfg), 16, false, 0, 40)),
		"on_start": func(btn):
			if room_countdown > 0:
				return
			SFX.play("ui_click")
			btn.text = "BAŞLIYOR..."
			btn.disabled = true
			room_countdown = 5.99,
		"start_text": "BAŞLAT"})
	room_chat = lay["chat"]
	if _room_log.is_empty():
		_chat("SİSTEM", "Odaya hoş geldin! Hazır olduğunda BAŞLAT'a bas.", Color("ffd24a"))
		if teams:
			_chat("SİSTEM", "Takım dengesi oyuncu sayısına göre yapıldı.", Color("ffd24a"))
		get_tree().create_timer(1.2).timeout.connect(func(): _bot_reply())
	else:
		for ln in _room_log:
			_chat(ln[0], ln[1], ln[2], false)

func _chat(who: String, t: String, c: Color, log_it: bool = true) -> void:
	if log_it:
		_room_log.append([who, t, c])
		if _room_log.size() > 40:
			_room_log.pop_front()
	if room_chat == null or not is_instance_valid(room_chat):
		return
	t = t.replace("[", "(")
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
	# competitive rank card
	var ri: Dictionary = GS.rank_info(int(pr.get("rp", 0)))
	var rc := UI.panel(Color(ri["color"].r * 0.1, ri["color"].g * 0.1, ri["color"].b * 0.1, 0.92), ri["color"], 14, 2)
	v.add_child(rc)
	var rch := UI.hbox(16)
	rc.add_child(rch)
	var rem := TextureRect.new()
	rem.texture = ri["icon"]; rem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; rem.custom_minimum_size = Vector2(110, 110)
	rem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rch.add_child(rem)
	var rcv := UI.vbox(4)
	rcv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rch.add_child(rcv)
	rcv.add_child(UI.lbl("RÜTBE", 15, UI.DIM, "Rajdhani-Bold"))
	rcv.add_child(UI.lbl(str(ri["name"]).to_upper(), 34, ri["color"], "RussoOne-Regular"))
	rcv.add_child(UI.bar(float(ri["prog"]) * 100.0, 100.0, ri["color"], 10))
	rcv.add_child(UI.lbl("%d RP%s   •   en yüksek: %s" % [int(ri["rp"]), ("  —  sonraki rütbe %d RP" % int(ri["hi"])) if ri["hi"] > ri["lo"] else "", GS.rank_info(int(pr.get("rp_peak", 0)))["name"]], 16, UI.TEXT, "Rajdhani-SemiBold"))
	rcv.add_child(UI.lbl("Kazanınca +18…31 RP, kaybedince −8…14 RP. Dereceli online maçlar tam, bot maçları yarım puan verir.", 14, UI.DIM, "Rajdhani-SemiBold"))
	# rank ladder
	var lad := HBoxContainer.new()
	lad.add_theme_constant_override("separation", 2)
	v.add_child(lad)
	for k in GS.RANKS.size():
		var tr := TextureRect.new()
		tr.texture = load("res://assets/ui/ranks/r%d.png" % k); tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(38, 38); tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.tooltip_text = "%s — %d RP" % [GS.RANKS[k], int(GS.Econ.RANK_RP[k])]
		tr.modulate = Color.WHITE if k <= int(ri["i"]) else Color(1, 1, 1, 0.25)
		lad.add_child(tr)
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
	static var _tx := {}
	func _draw() -> void:
		var c := size * 0.5
		var s: float = min(size.x, size.y) * 0.42
		# v3.4 painted attachment renders
		if not _tx.has(pid):
			var pth := "res://assets/ui/parts/%s.png" % pid
			_tx[pid] = load(pth) if ResourceLoader.exists(pth) else null
		if _tx[pid]:
			var sz: float = min(size.x, size.y) * 1.1
			draw_texture_rect(_tx[pid], Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)
			return
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
			"durbun":
				draw_rect(Rect2(c - Vector2(s * 1.1, s * 0.32), Vector2(s * 2.2, s * 0.64)), dk)
				draw_rect(Rect2(c - Vector2(s * 1.1, s * 0.32), Vector2(s * 2.2, s * 0.64)), col, false, 2.0)
				draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.55), Vector2(s * 0.4, s * 0.23)), col)
				draw_rect(Rect2(c + Vector2(-s * 0.5, s * 0.32), Vector2(s, s * 0.3)), dk)
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
		60:
			_store_detail("scar")
		61:
			market_tab = "karakter"; show_page("market")
		67:
			market_tab = "malzeme"; show_page("market")
		66:
			crate_type = "ejder"
			_crate_reveal({"type": "skin", "id": "ejderha", "wid": "ak47", "label": "AK-47 | Kara Ejderha", "color": Color("ffb02e"), "rarity": 3}, "AK-47 | Kara Ejderha")
		62, 63, 64, 65:
			var isk: Array = ["ejderha", "kuantum", "anka", "yildirim"]
			if OS.has_environment("INSKINS"): isk = Array(OS.get_environment("INSKINS").split(","))
			_inspect(["ak47", "scar", "awm", "m4a1"][i - 62], isk[i - 62])
		38, 39:
			if not GS.owned("m4a1"):
				GS.profile["owned"]["m4a1"] = {"lvl": 0, "skins": ["std"], "skin": "std"}
			GS.profile["owned"]["m4a1"]["lvl"] = 3
			GS.profile["gold"] = 999999
			for m in GS.MATS.keys():
				GS.profile["mats"][m] = 999
			_upgrade_dialog("m4a1")
			if i == 39:
				for b in modal.find_children("*", "Button", true, false):
					if str((b as Button).text).begins_with("YÜKSELT  "):
						(b as Button).pressed.emit()
		35:
			_room_dialog({"name": "Kapışma Odası", "map": "canakkale", "mode": "sabotaj", "bots": 9, "diff": 1, "time": 8, "target": 6, "team": "a", "no": 110})
		36, 37:
			Online.token = "test"; Online.uid = "me"; Online.username = "sokakoperasyon"; Online.expires_at = 1e12
			Online.friends = [
				{"username": "KurtReis", "user_id": "u1", "level": 24, "status": "match", "online": true, "pending": false, "incoming": false, "friendship_id": 1, "room": "AB12CD"},
				{"username": "Mehmetcik_06", "user_id": "u2", "level": 12, "status": "lobby", "online": true, "pending": false, "incoming": false, "friendship_id": 2, "room": null},
				{"username": "ZulaKing", "user_id": "u3", "level": 40, "status": "offline", "online": false, "pending": false, "incoming": false, "friendship_id": 3, "room": null},
				{"username": "GeceKurdu", "user_id": "u4", "level": 7, "status": "lobby", "online": true, "pending": true, "incoming": true, "friendship_id": 4, "room": null},
				{"username": "Atmaca", "user_id": "u5", "level": 15, "status": "lobby", "online": true, "pending": true, "incoming": false, "friendship_id": 5, "room": null}]
			show_page("friends")
			if i == 37:
				online._on_friend_request(Online.friends[3])
				online._on_invite({"id": 1, "from": "KurtReis", "room_name": "Kurtlar Vadisi", "room": "AB12CD"})
		34:
			room_cfg = {"name": "Kapışma Odası", "map": "canakkale", "mode": "tdm", "bots": 9, "diff": 1, "time": 8, "target": 6, "team": "a", "no": 110}
			show_page("room")
			show_page("bag")
		32, 33:
			Online.is_admin = true
			Online.username = "sokakoperasyon"
			var now := Time.get_datetime_string_from_system(true)
			var users := []
			for k in [["sokakoperasyon", 1240, true, "", true], ["KurtReis", 820, true, "match", false], ["Mehmetcik_06", 410, false, "", false], ["hileci99", 60, false, "", false], ["ZulaKing", 2210, true, "", false]]:
				users.append({"id": k[0], "username": k[0], "level": 12, "status": k[3], "last_seen": now if k[2] else "2026-11-01T10:00:00",
					"created_at": "2026-10-20T10:00:00", "banned_until": "infinity" if k[0] == "hileci99" else null, "ban_reason": "hile" if k[0] == "hileci99" else null,
					"gold": 15400, "rp": k[1], "kills": 512, "deaths": 300, "wins": 40, "weapons": 9, "admin": k[4]})
			Online.admin_mock = {"stats": {"online": 37, "in_match": 22, "rooms": 5, "active_day": 140, "total": 612, "today": 18, "week": 96, "banned": 3, "gold_total": 9114321,
				"top": [{"username": "ZulaKing", "rp": 2210, "level": 40}, {"username": "sokakoperasyon", "rp": 1240, "level": 30}, {"username": "KurtReis", "rp": 820, "level": 22}]},
				"users": users, "anns": [{"id": 2, "text": "Bu akşam 21:00'de 2x altın etkinliği!", "created_at": now}],
				"log": [{"id": 1, "action": "ban", "admin": "sokakoperasyon", "target": "hileci99", "info": {"reason": "hile", "hours": 0}, "at": now},
					{"id": 2, "action": "gift", "admin": "sokakoperasyon", "target": "all", "info": {"gift": {"gold": 1000, "crates": 2}}, "at": now}]}
			if i == 33:
				adminp.tab = "oyuncu"; adminp._sel = users[1]
			show_page("admin")
		30:
			room_cfg = {"name": "Kapışma Odası", "map": "canakkale", "mode": "sabotaj", "bots": 9, "diff": 1, "time": 8, "target": 6, "team": "a", "no": 110}
			show_page("room")
		31:
			_crate_reveal(_item_display({"type": "weapon", "id": "awm", "days": 7}), "")
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
