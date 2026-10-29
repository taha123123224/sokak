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
const SERVERS := [["TR-İstanbul #1", 18], ["TR-Ankara #2", 24], ["EU-Frankfurt", 46]]

func _ready() -> void:
	_build_world()
	_build_ui()
	SFX.play_music("music_menu")

func _build_world() -> void:
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
	sg.set_color(0, Color(0.01, 0.015, 0.03, 0.0)); sg.set_color(1, Color(0.01, 0.015, 0.03, 0.88))
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
	logo.anchor_top = 0.5; logo.anchor_bottom = 0.5
	logo.offset_left = 80; logo.offset_right = 900; logo.offset_top = -300; logo.offset_bottom = -54
	logo.pivot_offset = Vector2(410, 123)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(logo)
	var em := TextureRect.new()
	em.texture = load("res://assets/ui/emblem.png")
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.anchor_top = 0.5; em.anchor_bottom = 0.5
	em.offset_left = 400; em.offset_right = 580; em.offset_top = -480; em.offset_bottom = -300
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(em)
	var tag := UI.lbl("Türkiye'nin sokaklarında taktik çatışma.  Eski Mahalle • Safranbolu • Gemi • Liman", 22, Color(1, 1, 1, 0.85), "Rajdhani-SemiBold")
	tag.anchor_top = 0.5; tag.anchor_bottom = 0.5
	tag.offset_left = 120; tag.offset_top = -40; tag.offset_right = 1000
	ui.add_child(tag)
	# login panel (right)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(0.03, 0.04, 0.06, 0.82), Color(1, 0.55, 0.12, 0.55), 1, 10, 28))
	p.anchor_left = 1; p.anchor_right = 1; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -560; p.offset_right = -90; p.offset_top = -300; p.offset_bottom = 300
	ui.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	var hh := UI.hbox(10)
	v.add_child(hh)
	var acc := ColorRect.new(); acc.color = UI.ACCENT; acc.custom_minimum_size = Vector2(6, 40)
	hh.add_child(acc)
	hh.add_child(UI.lbl("GİRİŞ", 38, Color.WHITE, "RussoOne-Regular"))
	# --- tabs: GİRİŞ / KAYIT OL
	var tabs := UI.hbox(8)
	v.add_child(tabs)
	var tb_login := UI.btn("GİRİŞ YAP", func(): _set_mode(false), 18, true, 0, 42)
	var tb_reg := UI.btn("KAYIT OL", func(): _set_mode(true), 18, false, 0, 42)
	tb_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tb_reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tb_login); tabs.add_child(tb_reg)
	tab_btns = [tb_login, tb_reg]
	v.add_child(UI.lbl("KULLANICI ADI", 16, UI.DIM, "Rajdhani-Bold"))
	name_edit = _field(str(GS.profile.get("name", "")) if not str(GS.profile.get("name", "")).begins_with("Oyuncu") else "", false)
	name_edit.placeholder_text = "3-16 karakter: harf, rakam, _"
	v.add_child(name_edit)
	v.add_child(UI.lbl("ŞİFRE", 16, UI.DIM, "Rajdhani-Bold"))
	pass_edit = _field("", true)
	pass_edit.placeholder_text = "en az 6 karakter"
	v.add_child(pass_edit)
	pass2_lbl = UI.lbl("ŞİFRE (TEKRAR)", 16, UI.DIM, "Rajdhani-Bold")
	v.add_child(pass2_lbl)
	pass2_edit = _field("", true)
	v.add_child(pass2_edit)
	name_edit.text_submitted.connect(func(_t): pass_edit.grab_focus())
	pass_edit.text_submitted.connect(func(_t): _login())
	pass2_edit.text_submitted.connect(func(_t): _login())
	v.add_child(UI.spacer())
	status_lbl = UI.lbl("", 18, UI.ACCENT2, "Rajdhani-Bold")
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_lbl)
	bar = UI.bar(0, 1, UI.ACCENT, 6)
	bar.visible = false
	v.add_child(bar)
	go_btn = UI.btn("GİRİŞ YAP", _login, 30, true, 0, 70)
	go_btn.add_theme_font_override("font", UI.font("RussoOne-Regular"))
	v.add_child(go_btn)
	var row := UI.hbox(10)
	v.add_child(row)
	var b0 := UI.btn("ÇEVRİMDIŞI OYNA", _offline, 18, false, 0, 44)
	b0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b1 := UI.btn("AYARLAR", func(): if main: main.go_menu("settings"), 18, false, 0, 44)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := UI.btn("ÇIKIŞ", func(): get_tree().quit(), 18, false, 0, 44)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b0); row.add_child(b1); row.add_child(b2)
	_set_mode(false)
	if not Online.configured():
		status_lbl.text = "Online servis henüz yapılandırılmadı. Çevrimdışı oynayabilirsin."
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
	ticker = UI.lbl("YENİ: Animasyonlu şarjör değiştirme ve bıçak hareketleri   •   SCAR-H, UMP-45 ve Magnum .357 markette   •   Osmanlı, Operasyon ve Efsane kasaları   •   Eklenti desteği: kendi silah ve stillerini ekle!   •   Büyütülen Eski Mahalle ve Gemi haritaları   •   Haftasonu 2x malzeme", 19, Color(1, 1, 1, 0.9), "Rajdhani-SemiBold")
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
	e.add_theme_stylebox_override("normal", UI.sb(Color(0.08, 0.1, 0.14, 1), Color(1, 1, 1, 0.12), 1, 6, 14))
	e.add_theme_stylebox_override("focus", UI.sb(Color(0.1, 0.12, 0.17, 1), UI.ACCENT, 2, 6, 14))
	return e

func _set_mode(reg: bool) -> void:
	register_mode = reg
	pass2_lbl.visible = reg
	pass2_edit.visible = reg
	go_btn.text = "KAYIT OL" if reg else "GİRİŞ YAP"
	for i in tab_btns.size():
		var on: bool = (i == 1) == reg
		var bt: Button = tab_btns[i]
		bt.add_theme_stylebox_override("normal", UI.sb(UI.ACCENT if on else Color(0.07, 0.085, 0.12), UI.ACCENT2 if on else Color(1, 1, 1, 0.08), 1, 6, 8))
		bt.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02) if on else UI.TEXT)
	status_lbl.text = "Kullanıcı adın oyunda ve arkadaş listelerinde görünür." if reg else ""

func _msg(t: String, err: bool) -> void:
	status_lbl.text = t
	status_lbl.add_theme_color_override("font_color", UI.RED if err else UI.ACCENT2)
	if err:
		SFX.play("fail", -6)

func _try_resume() -> void:
	if not Online.configured() or not FileAccess.file_exists(Online.SESSION):
		return
	busy = true
	_msg("Hesabına bağlanılıyor...", false)
	bar.visible = true; bar.value = 0.5
	var ok: bool = await Online.try_resume()
	busy = false
	bar.visible = false
	if ok:
		_enter("Hoş geldin, %s!" % Online.username)
	else:
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
	if register_mode and pw != pass2_edit.text:
		_msg("Şifreler aynı değil", true); return
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

func _offline() -> void:
	if busy:
		return
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
	tw.tween_callback(func(): if main: main.go_menu())

func _on_update(info: Dictionary) -> void:
	upd_panel.visible = true
	upd_title.text = "YENİ SÜRÜM: %s" % str(info.get("version", "?"))
	upd_notes.text = str(info.get("notes", "Yeni içerik ve düzeltmeler. Verilerin hesabında güvende, güncelleme sonrası kaldığın yerden devam edersin."))
	upd_btn.disabled = false
