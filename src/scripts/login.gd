extends Node3D
## Giriş ekranı: cinematic sunset flyover of the ship map, big logo, login form, server list, news ticker.

var main
var cam: Camera3D
var t := 0.0
var ui: Control
var name_edit: LineEdit
var pass_edit: LineEdit
var pass2_edit: LineEdit
var pass2_lbl: Label
var go_btn: Button
var tab_btns: Array = []
var register_mode := false
var upd_panel: PanelContainer
var upd_title: Label
var upd_notes: Label
var upd_bar: ProgressBar
var upd_btn: Button
var server := 0
var status_lbl: Label
var bar: ProgressBar
var ticker: Label
var logo: TextureRect
var busy := false
var resume_box: PanelContainer
var resume_lbl: Label
var resume_sub: Label
var card: PanelContainer
var form: VBoxContainer
var title_lbl: Label
var sub_lbl: Label
var avatar
var name_hint: Label
var strength: ProgressBar
var pass2_box: Control
var status_pill: PanelContainer

class Glyph extends Control:
	## tiny vector icons (the UI fonts have no emoji): user / lock / eye
	var kind := "user"
	var col := Color(0.55, 0.6, 0.68)
	var slash := false
	func _draw() -> void:
		var c := size / 2
		var k := minf(size.x, size.y) / 20.0
		match kind:
			"user":
				draw_circle(c + Vector2(0, -4) * k, 4.2 * k, col)
				draw_arc(c + Vector2(0, 9) * k, 7.5 * k, PI, TAU, 20, col, 3.0 * k, true)
			"lock":
				draw_arc(c + Vector2(0, -2) * k, 4.5 * k, PI, TAU, 16, col, 2.4 * k, true)
				draw_line(c + Vector2(-4.5, -2) * k, c + Vector2(-4.5, 1) * k, col, 2.4 * k)
				draw_line(c + Vector2(4.5, -2) * k, c + Vector2(4.5, 1) * k, col, 2.4 * k)
				draw_rect(Rect2(c + Vector2(-7, 0) * k, Vector2(14, 10) * k), col)
				draw_circle(c + Vector2(0, 4.5) * k, 1.6 * k, Color(0.07, 0.085, 0.12))
			"eye":
				var pts := PackedVector2Array()
				for i in 25:
					var a := i / 24.0 * TAU
					pts.append(c + Vector2(cos(a) * 8.5, sin(a) * 4.8) * k)
				draw_polyline(pts, col, 2.0 * k, true)
				draw_circle(c, 2.6 * k, col)
				if slash:
					draw_line(c + Vector2(-8, 6) * k, c + Vector2(8, -6) * k, col, 2.0 * k, true)

class Avatar extends Control:
	## round avatar: animated accent ring + the account's initial
	var letter := "?"
	var col := Color("ff8a1f")
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size / 2
		var r := minf(size.x, size.y) / 2 - 3
		draw_circle(c, r + 3, Color(col.r, col.g, col.b, 0.18))
		draw_circle(c, r, Color(0.08, 0.09, 0.12))
		draw_arc(c, r, t * 1.2, t * 1.2 + TAU * 0.7, 48, col, 3.0, true)
		draw_arc(c, r, t * 1.2 + TAU * 0.75, t * 1.2 + TAU * 0.95, 16, Color(1, 1, 1, 0.5), 3.0, true)
		var f := UI.font("RussoOne-Regular")
		var fs := int(r * 1.05)
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w / 2, c.y + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
const SERVERS := [["TR-İstanbul #1", 18], ["TR-Ankara #2", 24], ["EU-Frankfurt", 46]]

func _ready() -> void:
	_build_world()
	_build_ui()
	SFX.play_music("music_menu")

var bg_still: TextureRect
var bg_live: ShaderMaterial
## light positions (UV) in login_keyart.jpg for the live shader
var LOGIN_LIGHTS := {"lantern0": Vector2(0.13, 0.075), "lantern1": Vector2(0.484, 0.512), "lantern2": Vector2(0.536, 0.565), "sun": Vector2(0.638, 0.295)}
func _build_world() -> void:
	# CS2-style: a sunlit street still (same art as the lobby) with a slow drift instead of loading a whole map
	for p in ["res://assets/ui/login_keyart.jpg", "res://assets/ui/lobby_bg_1.jpg", "res://assets/ui/lobby_bg_0.jpg"]:
		if ResourceLoader.exists(p):
			var cl := CanvasLayer.new()
			cl.layer = -1
			add_child(cl)
			bg_still = TextureRect.new()
			bg_still.texture = load(p)
			bg_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_still.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if p.ends_with("login_keyart.jpg"):
				# living key art: drifting smoke, flickering lanterns, sun rays (same shader as the launcher)
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/bg_live.gdshader")
				sm.set_shader_parameter("art", bg_still.texture)
				for kv in LOGIN_LIGHTS.keys():
					sm.set_shader_parameter(kv, LOGIN_LIGHTS[kv])
				bg_still.material = sm
				bg_live = sm
			cl.add_child(bg_still)
			return
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2a4f9a")
	sm.sky_horizon_color = Color("ffb27a")
	sm.ground_horizon_color = Color("ffb27a")
	sm.ground_bottom_color = Color(0.1, 0.12, 0.18)
	sm.sun_angle_max = 30
	sm.sky_energy_multiplier = 1.2
	if ResourceLoader.exists("res://assets/tex/clouds.png"):
		sm.sky_cover = load("res://assets/tex/clouds.png")
		sm.sky_cover_modulate = Color(1, 0.8, 0.7, 0.9)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.8; e.glow_bloom = 0.1; e.glow_hdr_threshold = 1.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_depth_begin = 60.0; e.fog_depth_end = 400.0
	e.fog_light_color = Color("f5b48a")
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.2
	e.ssao_enabled = true
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14, 280, 0)
	sun.light_color = Color(1.0, 0.72, 0.48)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200
	add_child(sun)
	var ps: PackedScene = GS.map_scene("gemi")
	if ps:
		var m := ps.instantiate()
		MatLib.apply(m)
		add_child(m)
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 55
	cam.far = 3000
	add_child(cam)
	cam.current = true

func _process(delta: float) -> void:
	t += delta
	if bg_live:
		bg_live.set_shader_parameter("t", t)
	if bg_still and bg_live == null:
		var vs := get_viewport().get_visible_rect().size
		var k := 1.06 + sin(t * 0.05) * 0.03
		bg_still.size = vs * k
		bg_still.position = -(vs * (k - 1.0)) * Vector2(0.5 + sin(t * 0.031) * 0.35, 0.5)
		bg_still.pivot_offset = Vector2.ZERO
	if bg_still:
		if logo:
			var k2 := 1.0 + sin(t * 1.6) * 0.012
			logo.scale = Vector2(k2, k2)
		if ticker:
			ticker.position.x -= delta * 70.0
			if ticker.position.x < -ticker.size.x:
				ticker.position.x = get_viewport().get_visible_rect().size.x
		return
	# slow cinematic orbit around the ship at sunset
	var a := t * 0.045 + 0.6
	var r := 95.0 + sin(t * 0.07) * 12.0
	cam.position = Vector3(cos(a) * r, 26.0 + sin(t * 0.11) * 6.0, sin(a) * r * 0.55)
	cam.look_at(Vector3(-10 + sin(t * 0.05) * 15, 4, 0))
	if logo:
		var k := 1.0 + sin(t * 1.6) * 0.012
		logo.scale = Vector2(k, k)
	if ticker:
		ticker.position.x -= delta * 70.0
		if ticker.position.x < -ticker.size.x:
			ticker.position.x = get_viewport().get_visible_rect().size.x

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = main.theme if main else UI.build_theme()
	cl.add_child(ui)
	# cinematic letterbox gradients
	for top in [true, false]:
		var gr := TextureRect.new()
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.75)); g.set_color(1, Color(0, 0, 0, 0))
		gt.gradient = g
		gt.fill_from = Vector2(0, 0 if top else 1); gt.fill_to = Vector2(0, 1 if top else 0)
		gr.texture = gt
		gr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gr.anchor_right = 1
		if top:
			gr.anchor_bottom = 0; gr.offset_bottom = 220
		else:
			gr.anchor_top = 1; gr.anchor_bottom = 1; gr.offset_top = -260
		gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(gr)
	var side := TextureRect.new()
	var st := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(0.02, 0.022, 0.026, 0.0)); sg.set_color(1, Color(0.02, 0.022, 0.026, 0.82))
	st.gradient = sg; st.fill_from = Vector2(0.45, 0); st.fill_to = Vector2(1, 0)
	side.texture = st
	side.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(side)
	# logo
	logo = TextureRect.new()
	logo.texture = load("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# v3.1: the key art has the operators on the left, so the wordmark sits top-right above the login card
	logo.anchor_left = 1; logo.anchor_right = 1
	logo.offset_left = -585; logo.offset_right = -85; logo.offset_top = 58; logo.offset_bottom = 208
	logo.pivot_offset = Vector2(250, 75)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(logo)
	var em := TextureRect.new()
	em.texture = load("res://assets/ui/emblem.png")
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.anchor_top = 0.5; em.anchor_bottom = 0.5
	em.offset_left = 400; em.offset_right = 580; em.offset_top = -480; em.offset_bottom = -300
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	em.visible = false
	ui.add_child(em)
	var tag := UI.lbl("TÜRKİYE'NİN SOKAKLARINDA TAKTİK ÇATIŞMA", 18, Color(1, 1, 1, 0.8), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	tag.anchor_left = 1; tag.anchor_right = 1
	tag.offset_left = -585; tag.offset_right = -85; tag.offset_top = 212; tag.offset_bottom = 240
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	ui.add_child(tag)
	# ---------------- account card (right): glass panel, segmented tabs, icon fields, saved-account profile card
	card = PanelContainer.new()
	var csb := UI.sb(Color(0.045, 0.05, 0.058, 0.8), Color(1, 1, 1, 0.1), 1, 8, 34)
	csb.shadow_color = Color(0, 0, 0, 0.55); csb.shadow_size = 30
	card.add_theme_stylebox_override("panel", csb)
	card.anchor_left = 1; card.anchor_right = 1; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -580; card.offset_right = -90; card.offset_top = 70; card.offset_bottom = 70
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.add_child(card)
	var strip := ColorRect.new()
	strip.color = UI.ACCENT
	strip.custom_minimum_size = Vector2(0, 3)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(12)
	card.add_child(v)
	var hv := UI.vbox(-2)
	v.add_child(hv)
	var sh := UI.hbox(8)
	hv.add_child(sh)
	var dot := UI.lbl("●", 13, UI.GREEN if Online.configured() else UI.DIM, "Rajdhani-Bold")
	sh.add_child(dot)
	var dt := create_tween().set_loops()
	dt.tween_property(dot, "modulate:a", 0.35, 0.9)
	dt.tween_property(dot, "modulate:a", 1.0, 0.9)
	sh.add_child(UI.lbl(("SUNUCULAR ÇEVRİMİÇİ  •  %s  %d ms" % [SERVERS[0][0], SERVERS[0][1]]) if Online.configured() else "ÇEVRİMDIŞI MOD", 14, UI.DIM, "Rajdhani-Bold"))
	title_lbl = UI.lbl("HESABINA GİRİŞ YAP", 34, Color.WHITE, "RussoOne-Regular")
	hv.add_child(title_lbl)
	sub_lbl = UI.lbl("Kaldığın yerden devam et: envanterin ve rütben hesabında.", 16, Color(1, 1, 1, 0.55), "Rajdhani-SemiBold")
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(sub_lbl)
	v.add_child(strip)
	# saved account ("önceki hesap") profile card
	resume_box = PanelContainer.new()
	var rsb := UI.sb(Color(1, 1, 1, 0.04), Color(1, 0.55, 0.12, 0.45), 1, 12, 16)
	resume_box.add_theme_stylebox_override("panel", rsb)
	resume_box.visible = false
	v.add_child(resume_box)
	var rv := UI.vbox(12)
	resume_box.add_child(rv)
	var rtop := UI.hbox(14)
	rv.add_child(rtop)
	avatar = Avatar.new()
	avatar.custom_minimum_size = Vector2(72, 72)
	rtop.add_child(avatar)
	var rinfo := UI.vbox(0)
	rinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtop.add_child(rinfo)
	rinfo.add_child(UI.lbl("KAYITLI HESAP", 13, UI.ACCENT2, "Rajdhani-Bold"))
	resume_lbl = UI.lbl("", 30, Color.WHITE, "RussoOne-Regular")
	rinfo.add_child(resume_lbl)
	resume_sub = UI.lbl("", 16, Color(1, 1, 1, 0.6), "Rajdhani-Bold")
	rinfo.add_child(resume_sub)
	var rb1 := UI.btn("▶   DEVAM ET", func(): if not busy: _enter("Hoş geldin, %s!" % Online.username), 24, true, 0, 62)
	rb1.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	rv.add_child(rb1)
	var rh := UI.hbox(8)
	rv.add_child(rh)
	var rb3 := _ghost_btn("BAŞKA HESAPLA GİR", func(): _show_form(true))
	var rb2 := _ghost_btn("✕  ÇIKIŞ YAP", _switch_account)
	rh.add_child(rb3); rh.add_child(rb2)
	# form
	form = UI.vbox(10)
	v.add_child(form)
	var seg := PanelContainer.new()
	seg.add_theme_stylebox_override("panel", UI.sb(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.06), 1, 10, 4))
	form.add_child(seg)
	var tabs := UI.hbox(4)
	seg.add_child(tabs)
	var tb_login := UI.btn("GİRİŞ YAP", func(): _set_mode(false), 18, false, 0, 44)
	var tb_reg := UI.btn("KAYIT OL", func(): _set_mode(true), 18, false, 0, 44)
	tb_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tb_reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tb_login); tabs.add_child(tb_reg)
	tab_btns = [tb_login, tb_reg]
	var nf := _icon_field("user", "KULLANICI ADI", str(GS.profile.get("name", "")) if not str(GS.profile.get("name", "")).begins_with("Oyuncu") else "", false)
	form.add_child(nf[0]); name_edit = nf[1]
	name_edit.placeholder_text = "3-16 karakter: harf, rakam, _"
	name_hint = UI.lbl("", 13, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	form.add_child(name_hint)
	name_edit.text_changed.connect(func(_tx): _validate())
	var pf := _icon_field("lock", "ŞİFRE", "", true)
	form.add_child(pf[0]); pass_edit = pf[1]
	pass_edit.placeholder_text = "en az 6 karakter"
	pass_edit.text_changed.connect(func(_tx): _validate())
	strength = UI.bar(0, 4, UI.RED, 4)
	strength.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 2, 0))
	form.add_child(strength)
	var p2 := _icon_field("lock", "ŞİFRE (TEKRAR)", "", true)
	pass2_box = p2[0]; pass2_edit = p2[1]
	pass2_lbl = UI.lbl("", 1, UI.DIM)  # kept for compatibility
	form.add_child(pass2_box)
	pass2_edit.text_changed.connect(func(_tx): _validate())
	name_edit.text_submitted.connect(func(_t): pass_edit.grab_focus())
	# Enter and the button go through the same _login() checks (password repeat included)
	pass_edit.text_submitted.connect(func(_t):
		if register_mode: pass2_edit.grab_focus()
		else: _login())
	pass2_edit.text_submitted.connect(func(_t): _login())
	go_btn = UI.btn("GİRİŞ YAP", _login, 26, true, 0, 64)
	go_btn.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	form.add_child(go_btn)
	# status pill
	status_pill = PanelContainer.new()
	status_pill.add_theme_stylebox_override("panel", UI.sb(Color(1, 0.55, 0.12, 0.1), Color(1, 0.55, 0.12, 0.35), 1, 8, 10))
	status_pill.visible = false
	v.add_child(status_pill)
	status_lbl = UI.lbl("", 17, UI.ACCENT2, "Rajdhani-Bold")
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_pill.add_child(status_lbl)
	bar = UI.bar(0, 1, UI.ACCENT, 4)
	bar.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 2, 0))
	bar.visible = false
	v.add_child(bar)
	# divider + secondary actions
	var dv := UI.hbox(10)
	v.add_child(dv)
	for k in 2:
		var ln := ColorRect.new(); ln.color = Color(1, 1, 1, 0.08); ln.custom_minimum_size = Vector2(0, 1)
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dv.add_child(ln)
		if k == 0:
			dv.add_child(UI.lbl("VEYA", 13, UI.DIM, "Rajdhani-Bold"))
	var row := UI.hbox(8)
	v.add_child(row)
	row.add_child(_ghost_btn("⚡  ÇEVRİMDIŞI", _offline))
	row.add_child(_ghost_btn("⚙  AYARLAR", _open_settings))
	row.add_child(_ghost_btn("✕  ÇIKIŞ", func(): get_tree().quit()))
	_set_mode(false)
	if not Online.configured():
		_msg("Online servis henüz yapılandırılmadı. Çevrimdışı oynayabilirsin.", false)
	# entrance: the card slides in from the right
	card.modulate.a = 0.0
	var ct := create_tween()
	ct.tween_interval(0.15)
	ct.tween_property(card, "modulate:a", 1.0, 0.45)
	ct.parallel().tween_property(card, "offset_left", -580.0, 0.55).from(-500.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(card, "offset_right", -90.0, 0.55).from(-10.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# update banner (filled by the updater)
	upd_panel = PanelContainer.new()
	upd_panel.add_theme_stylebox_override("panel", UI.sb(Color(0.2, 0.1, 0.02, 0.95), UI.ACCENT, 2, 8, 16))
	upd_panel.anchor_left = 0.5; upd_panel.anchor_right = 0.5
	upd_panel.offset_left = -420; upd_panel.offset_right = 420; upd_panel.offset_top = 30
	upd_panel.visible = false
	ui.add_child(upd_panel)
	var uh := UI.hbox(16)
	upd_panel.add_child(uh)
	var uv := UI.vbox(4)
	uv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uh.add_child(uv)
	upd_title = UI.lbl("GÜNCELLEME VAR", 24, UI.ACCENT2, "RussoOne-Regular")
	uv.add_child(upd_title)
	upd_notes = UI.lbl("", 16, Color.WHITE, "Rajdhani-SemiBold")
	upd_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	uv.add_child(upd_notes)
	upd_bar = UI.bar(0, 1, UI.ACCENT, 6)
	upd_bar.visible = false
	uv.add_child(upd_bar)
	upd_btn = UI.btn("GÜNCELLE", func(): Updater.download_and_install(), 22, true, 200, 56)
	upd_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	uh.add_child(upd_btn)
	Updater.update_available.connect(_on_update)
	Updater.progress.connect(func(f: float, txt: String):
		upd_bar.visible = true; upd_bar.value = f; upd_notes.text = txt; upd_btn.disabled = true)
	Updater.failed.connect(func(msg: String): upd_notes.text = msg; upd_btn.disabled = false)
	if Updater.latest.size() > 0 and Updater.has_update():
		_on_update(Updater.latest)
	else:
		Updater.check()
	_try_resume()
	# news ticker + version
	var tb := ColorRect.new()
	tb.color = Color(0.02, 0.025, 0.04, 0.85)
	tb.anchor_top = 1; tb.anchor_bottom = 1; tb.anchor_right = 1; tb.offset_top = -40
	ui.add_child(tb)
	var badge := UI.lbl("  HABERLER  ", 18, Color(0.08, 0.05, 0.02), "Rajdhani-Bold")
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", UI.sb(UI.ACCENT, Color(0, 0, 0, 0), 0, 0, 6))
	bp.add_child(badge)
	bp.anchor_top = 1; bp.anchor_bottom = 1; bp.offset_top = -40; bp.offset_bottom = 0
	var clip := Control.new()
	clip.clip_contents = true
	clip.anchor_top = 1; clip.anchor_bottom = 1; clip.anchor_right = 1
	clip.offset_top = -40; clip.offset_left = 150; clip.offset_right = -260
	ui.add_child(clip)
	ui.add_child(bp)
	ticker = UI.lbl("YENİ v3.1: CS2 tarzı MAĞAZA ve AJAN kartları   •   Tek ekranda OYNA: mod sekmeleri + harita seçimi   •   2K gerçek dokular ve sinematik gün batımı ışığı   •   Canlı lobi karakteri   •   Yeni SCAR-H   •   CS:GO tarzı bıçak görünümü   •   Yeni başlatıcı ve açılış animasyonu", 19, Color(1, 1, 1, 0.9), "Rajdhani-SemiBold")
	ticker.position = Vector2(1400, 8)
	clip.add_child(ticker)
	var ver := UI.lbl("SOKAK: Operasyon  v%s   " % Updater.VERSION, 16, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
	ver.anchor_left = 1; ver.anchor_right = 1; ver.anchor_top = 1; ver.anchor_bottom = 1
	ver.offset_left = -260; ver.offset_top = -32
	ui.add_child(ver)

func _field(t: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.text = t
	e.secret = secret
	e.max_length = 16 if not secret else 64
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_stylebox_override("normal", UI.sb(Color(0.1, 0.105, 0.115, 1), Color(1, 1, 1, 0.12), 1, 4, 14))
	e.add_theme_stylebox_override("focus", UI.sb(Color(0.13, 0.135, 0.15, 1), UI.ACCENT, 2, 4, 14))
	return e

func _icon_field(icon: String, label: String, t: String, secret: bool) -> Array:
	## label + framed field with a leading icon (and a show/hide eye for passwords); returns [container, LineEdit]
	var box := UI.vbox(4)
	box.add_child(UI.lbl(label, 13, UI.DIM, "Rajdhani-Bold"))
	var fr := PanelContainer.new()
	var nsb := UI.sb(Color(0.09, 0.095, 0.105, 1), Color(1, 1, 1, 0.1), 1, 4, 0)
	nsb.content_margin_left = 14; nsb.content_margin_right = 8
	var fsb := UI.sb(Color(0.115, 0.12, 0.13, 1), UI.ACCENT, 2, 4, 0)
	fsb.content_margin_left = 14; fsb.content_margin_right = 8
	fsb.shadow_color = Color(1, 0.55, 0.12, 0.25); fsb.shadow_size = 8
	fr.add_theme_stylebox_override("panel", nsb)
	box.add_child(fr)
	var h := UI.hbox(10)
	fr.add_child(h)
	var ic := Glyph.new()
	ic.kind = icon
	ic.custom_minimum_size = Vector2(22, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var e := _field(t, secret)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var clear := StyleBoxEmpty.new()
	e.add_theme_stylebox_override("normal", clear)
	e.add_theme_stylebox_override("focus", clear)
	h.add_child(e)
	e.focus_entered.connect(func(): fr.add_theme_stylebox_override("panel", fsb); ic.col = UI.ACCENT2; ic.queue_redraw())
	e.focus_exited.connect(func(): fr.add_theme_stylebox_override("panel", nsb); ic.col = UI.DIM; ic.queue_redraw())
	if secret:
		var eye := Button.new()
		eye.flat = true
		eye.custom_minimum_size = Vector2(36, 36)
		var eg := Glyph.new()
		eg.kind = "eye"; eg.slash = true
		eg.set_anchors_preset(Control.PRESET_FULL_RECT)
		eg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eye.add_child(eg)
		eye.focus_mode = Control.FOCUS_NONE
		eye.tooltip_text = "Şifreyi göster / gizle"
		eye.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		eye.add_theme_font_size_override("font_size", 18)
		eye.modulate = Color(1, 1, 1, 0.5)
		eye.pressed.connect(func():
			e.secret = not e.secret
			eg.slash = e.secret; eg.queue_redraw()
			eye.modulate = Color(1, 1, 1, 0.5 if e.secret else 1.0))
		h.add_child(eye)
	return [box, e]

func _ghost_btn(t: String, cb: Callable) -> Button:
	var b := UI.btn(t, cb, 15, false, 0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UI.sb(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08), 1, 8, 6))
	b.add_theme_stylebox_override("hover", UI.sb(Color(1, 1, 1, 0.08), Color(1, 0.55, 0.12, 0.5), 1, 8, 6))
	b.add_theme_stylebox_override("pressed", UI.sb(Color(1, 0.55, 0.12, 0.15), UI.ACCENT, 1, 8, 6))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	return b

func _validate() -> void:
	## live hints under the fields
	var n := name_edit.text.strip_edges()
	if n == "":
		name_hint.text = ""
	else:
		var bad: String = Online.valid_username(n)
		name_hint.text = ("✓  %d/16" % n.length()) if bad == "" else ("✕  " + bad)
		name_hint.add_theme_color_override("font_color", UI.GREEN if bad == "" else UI.RED)
	var pw := pass_edit.text
	var sc := 0
	if pw.length() >= 6: sc += 1
	if pw.length() >= 10: sc += 1
	var has_d := false
	var has_u := false
	for ch in pw:
		if ch >= "0" and ch <= "9": has_d = true
		if ch != ch.to_lower(): has_u = true
	if has_d: sc += 1
	if has_u: sc += 1
	strength.value = sc
	var sc_col: Color = [UI.RED, UI.RED, UI.GOLD, UI.GREEN, UI.GREEN][sc]
	strength.add_theme_stylebox_override("fill", UI.sb(sc_col, Color(0, 0, 0, 0), 0, 2, 0))
	strength.visible = register_mode and pw != ""

func _show_form(on: bool) -> void:
	form.visible = on
	if on:
		resume_box.visible = false
		title_lbl.text = "YENİ HESAP OLUŞTUR" if register_mode else "HESABINA GİRİŞ YAP"
		name_edit.grab_focus()

func _set_mode(reg: bool) -> void:
	register_mode = reg
	pass2_box.visible = reg
	go_btn.text = "HESAP OLUŞTUR" if reg else "GİRİŞ YAP"
	title_lbl.text = "YENİ HESAP OLUŞTUR" if reg else "HESABINA GİRİŞ YAP"
	sub_lbl.text = "Kullanıcı adın oyunda ve arkadaş listelerinde görünür." if reg else "Kaldığın yerden devam et: envanterin ve rütben hesabında."
	for i in tab_btns.size():
		var on: bool = (i == 1) == reg
		var bt: Button = tab_btns[i]
		for stn in ["normal", "hover", "pressed"]:
			var bsb := UI.sb(UI.ACCENT if on else (Color(1, 1, 1, 0.05) if stn == "hover" else Color(0, 0, 0, 0)), Color(0, 0, 0, 0), 0, 8, 8)
			bt.add_theme_stylebox_override(stn, bsb)
		bt.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02) if on else Color(1, 1, 1, 0.6))
		bt.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02) if on else Color.WHITE)
	_validate()
	if status_lbl:
		_msg("", false)

func _msg(t: String, err: bool) -> void:
	status_lbl.text = (("⚠  " if err else "ℹ  ") + t) if t != "" else ""
	status_lbl.add_theme_color_override("font_color", UI.RED.lightened(0.2) if err else UI.ACCENT2)
	if status_pill:
		status_pill.visible = t != ""
		var c: Color = UI.RED if err else UI.ACCENT
		status_pill.add_theme_stylebox_override("panel", UI.sb(Color(c.r, c.g, c.b, 0.1), Color(c.r, c.g, c.b, 0.4), 1, 8, 10))
		if err and t != "":
			var x0 := card.position.x
			var tw := card.create_tween()
			for k in 4:
				tw.tween_property(card, "position:x", x0 + (7.0 if k % 2 == 0 else -7.0), 0.04)
			tw.tween_property(card, "position:x", x0, 0.04)
	if err:
		SFX.play("fail", -6)

func _try_resume() -> void:
	if OS.has_environment("LOGIN_MOCK"):   # screenshot test of the saved-account card
		Online.username = "sokakoperasyon"
		_show_resume()
		return
	if not Online.configured() or not FileAccess.file_exists(Online.SESSION):
		return
	busy = true
	_msg("Hesabına bağlanılıyor...", false)
	bar.visible = true; bar.value = 0.5
	var ok: bool = await Online.try_resume()
	busy = false
	bar.visible = false
	if ok:
		# never enter automatically: show the saved account and let the player choose
		_show_resume()
	else:
		_msg("", false)

func _show_resume() -> void:
	resume_lbl.text = Online.username
	resume_sub.text = "Seviye %d   •   %s Altın" % [int(GS.profile.get("level", 1)), UI.money(int(GS.profile.get("gold", 0)))]
	avatar.letter = Online.username.substr(0, 1).to_upper() if Online.username != "" else "?"
	resume_box.visible = true
	form.visible = false
	title_lbl.text = "TEKRAR HOŞ GELDİN"
	sub_lbl.text = "Kayıtlı hesabınla tek tıkla devam et ya da başka bir hesapla giriş yap."
	_msg("", false)

func _login() -> void:
	if busy:
		return
	if not Online.configured():
		_msg("Online servis henüz yapılandırılmadı. Şimdilik ÇEVRİMDIŞI OYNA ile devam et.", true)
		return
	var n := name_edit.text.strip_edges()
	var pw := pass_edit.text
	var bad: String = Online.valid_username(n)
	if bad != "":
		_msg(bad, true); return
	if pw.length() < 6:
		_msg("Şifre en az 6 karakter olmalı", true); return
	if register_mode and (pass2_edit.text == "" or pw != pass2_edit.text):
		_msg("Şifreler aynı değil", true); pass2_edit.grab_focus(); return
	busy = true
	SFX.play("ui_click")
	bar.visible = true; bar.value = 0.3
	_msg("Kayıt oluşturuluyor..." if register_mode else "Giriş yapılıyor...", false)
	var err: String = ""
	if register_mode:
		err = await Online.register(n, pw)
	else:
		err = await Online.login(n, pw)
	busy = false
	if err != "":
		bar.visible = false
		_msg(err, true)
		return
	_enter("Hoş geldin, %s!" % Online.username)

func _switch_account() -> void:
	if busy:
		return
	busy = true
	await Online.logout()
	busy = false
	resume_box.visible = false
	name_edit.text = ""
	pass_edit.text = ""
	_show_form(true)
	_msg("Çıkış yapıldı. Başka bir hesapla giriş yapabilir ya da KAYIT OL ile yeni hesap açabilirsin.", false)

func _open_settings() -> void:
	## settings as an overlay on the login screen (no account is entered)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var su := preload("res://scripts/settings_ui.gd").new()
	su.set_anchors_preset(Control.PRESET_FULL_RECT)
	su.offset_left = 120; su.offset_top = 24; su.offset_right = -120; su.offset_bottom = -24
	su.on_close = func(): bg.queue_free(); su.queue_free()
	ui.add_child(su)

func _offline() -> void:
	if busy:
		return
	# offline play never uses an online account: sign out of the saved session and load the local profile
	if Online.is_logged_in():
		await Online.go_offline()
		resume_box.visible = false
	var n := name_edit.text.strip_edges()
	if n.length() >= 3:
		GS.profile["name"] = n
		GS.save_profile(true)
	_enter("Çevrimdışı mod")

func _enter(t: String) -> void:
	busy = true
	bar.visible = true
	_msg(t, false)
	SFX.play("success", -6)
	var tw := create_tween()
	tw.tween_property(bar, "value", 1.0, 0.6)
	tw.tween_callback(func(): if main: main.go_menu("mode"))

func _on_update(info: Dictionary) -> void:
	upd_panel.visible = true
	upd_title.text = "YENİ SÜRÜM: %s" % str(info.get("version", "?"))
	upd_notes.text = str(info.get("notes", "Yeni içerik ve düzeltmeler. Verilerin hesabında güvende, güncelleme sonrası kaldığın yerden devam edersin."))
	upd_btn.disabled = false
