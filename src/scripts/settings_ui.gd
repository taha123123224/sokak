extends Control
## Settings screen (used in menu and pause menu).

var in_match := false
var on_close: Callable
var tab := "grafik"
var body: VBoxContainer
var tabs_box: HBoxContainer
var preview: Control
var rebinding := ""
var rebind_btn: Button

func _ready() -> void:
	theme = UI.build_theme()
	var v := UI.vbox(14)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var top := UI.hbox(12)
	v.add_child(top)
	top.add_child(UI.header("AYARLAR", 34))
	top.add_child(UI.spacer())
	top.add_child(UI.btn("VARSAYILANA DÖN", _reset, 18, false, 0, 42))
	top.add_child(UI.btn("KAYDET VE KAPAT" if on_close.is_valid() else "KAYDET", _save_close, 20, true, 220, 42))
	tabs_box = UI.hbox(6)
	v.add_child(tabs_box)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var p := UI.panel(Color(0.04, 0.05, 0.07, 0.85), UI.LINE, 22)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(p)
	body = UI.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(body)
	_build_tabs()
	_build()

func _build_tabs() -> void:
	UI.clear(tabs_box)
	for t in [["grafik", "GRAFİK"], ["nisangah", "NİŞANGAH"], ["kontrol", "KONTROLLER"], ["ses", "SES"], ["oyun", "OYUN & ARAYÜZ"]]:
		var b := UI.btn(t[1], func(): tab = t[0]; _build_tabs(); _build(), 20, tab == t[0], 190, 46)
		tabs_box.add_child(b)

func _row(label: String, ctl: Control, hint: String = "") -> void:
	var h := UI.hbox(16)
	var l := UI.lbl(label, 21, UI.TEXT, "Rajdhani-SemiBold")
	l.custom_minimum_size = Vector2(340, 40)
	h.add_child(l)
	h.add_child(ctl)
	if hint != "":
		h.add_child(UI.lbl(hint, 17, UI.DIM, "Rajdhani-Medium"))
	body.add_child(h)

func _check(key: String, label: String, hint: String = "") -> void:
	var c := CheckButton.new()
	c.button_pressed = bool(GS.settings[key])
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on): GS.settings[key] = on; GS.settings["quality"] = "custom" if key in ["ssao", "ssil", "ssr", "sdfgi", "glow", "volumetric", "taa", "fxaa"] else GS.settings["quality"]; SFX.play("ui_click", -8))
	_row(label, c, hint)

func _slide(key: String, label: String, a: float, b: float, step: float, fmt: String = "%.2f", hint: String = "") -> void:
	var h := UI.hbox(10)
	var val := UI.lbl(fmt % float(GS.settings[key]), 20, UI.ACCENT2, "Rajdhani-Bold")
	val.custom_minimum_size = Vector2(70, 0)
	var s := UI.slider(a, b, step, float(GS.settings[key]), func(x): GS.settings[key] = x; val.text = fmt % x; if preview: preview.queue_redraw(), 340)
	h.add_child(s)
	h.add_child(val)
	_row(label, h, hint)

func _options(key: String, label: String, opts: Array, hint: String = "") -> void:
	var h := UI.hbox(6)
	for o in opts:
		var sel: bool = str(GS.settings[key]) == str(o[0])
		var b := UI.btn(o[1], func(): GS.settings[key] = o[0]; _build(), 18, sel, 0, 38)
		h.add_child(b)
	_row(label, h, hint)

func _section(t: String) -> void:
	body.add_child(UI.spacer(false, 0, 6))
	body.add_child(UI.header(t, 22))

func _build() -> void:
	UI.clear(body)
	preview = null
	match tab:
		"grafik":
			_section("GRAFİK KALİTESİ ÖN AYARI")
			var h := UI.hbox(8)
			for q in [["low", "DÜŞÜK"], ["medium", "ORTA"], ["high", "YÜKSEK"], ["ultra", "ULTRA"], ["uhd", "ULTRA HD (4K)"]]:
				h.add_child(UI.btn(q[1], func(): GS.apply_preset(q[0]); _build(), 20, GS.settings["quality"] == q[0], 170, 48))
			body.add_child(h)
			body.add_child(UI.lbl("Ultra HD: 4x MSAA + TAA, 8K gölge haritası, SDFGI global aydınlatma ve uzak çizim mesafesi. Güçlü ekran kartı gerektirir.", 17, UI.DIM, "Rajdhani-Medium"))
			_section("EKRAN")
			_check("fullscreen", "Tam Ekran")
			_check("vsync", "Dikey Senkronizasyon (V-Sync)", "Yırtılmayı önler, gecikme ekler")
			_options("fps_cap", "FPS Sınırı", [[0, "Sınırsız"], [60, "60"], [144, "144"], [165, "165"], [240, "240"]])
			_slide("resolution_scale", "Çözünürlük Ölçeği", 0.5, 2.0, 0.05, "%.2fx", "1.0 üstü = süper örnekleme")
			_options("upscaler", "Ölçekleyici", [["fsr2", "AMD FSR 2.2"], ["fsr", "FSR 1.0"]], "Ölçek < 1 iken kullanılır")
			_slide("sharpen", "Keskinlik", 0.0, 1.0, 0.05)
			_slide("brightness", "Parlaklık (pozlama)", 0.6, 1.4, 0.02)
			_slide("fov", "Görüş Açısı (FOV)", 60, 110, 1, "%d°")
			_slide("draw_distance", "Çizim Mesafesi", 0.5, 1.5, 0.05, "%.2fx")
			_section("KENAR YUMUŞATMA")
			_options("msaa", "MSAA", [[0, "Kapalı"], [2, "2x"], [4, "4x"], [8, "8x"]])
			_check("taa", "TAA (Zamansal)", "En pürüzsüz görüntü")
			_check("fxaa", "FXAA")
			_section("IŞIK VE EFEKTLER")
			_options("shadows", "Gölge Kalitesi", [[0, "Kapalı"], [1, "Düşük"], [2, "Orta"], [3, "Yüksek"], [4, "Ultra"]])
			_check("ssao", "Ortam Kapatma (SSAO)", "Köşelerde gerçekçi gölgelenme")
			_check("ssil", "Dolaylı Işık (SSIL)", "Renkli ışık sekmesi")
			_check("ssr", "Ekran Uzayı Yansımalar (SSR)", "Cam, su ve ıslak yüzeyler")
			_check("sdfgi", "Global Aydınlatma (SDFGI)", "Çok ağır - sadece güçlü sistemler")
			_check("glow", "Parlama (Bloom)")
			_check("volumetric", "Hacimsel Sis / Işık Huzmeleri")
			_check("show_fps", "FPS Göstergesi")
		"nisangah":
			_section("NİŞANGAH ÖNİZLEME")
			var pv := PreviewBox.new()
			pv.custom_minimum_size = Vector2(0, 220)
			body.add_child(pv)
			preview = pv
			_section("STİL")
			_options("xh_style", "Şekil", [[0, "Klasik Artı"], [1, "Nokta"], [2, "Daire"], [3, "T-Şekli"], [4, "Artı + Nokta"]])
			var cols := UI.hbox(6)
			for c in ["3dff8a", "00e5ff", "ffffff", "ff3b3b", "ffd23d", "ff4fd8", "a46bff"]:
				var b := Button.new()
				b.custom_minimum_size = Vector2(42, 38)
				b.focus_mode = Control.FOCUS_NONE
				var st := UI.sb(Color(c), Color.WHITE if GS.settings["xh_color"] == c else Color(0, 0, 0, 0.5), 2, 4, 0)
				b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", st); b.add_theme_stylebox_override("pressed", st)
				b.pressed.connect(func(): GS.settings["xh_color"] = c; _build())
				cols.add_child(b)
			var cp := ColorPickerButton.new()
			cp.color = Color(str(GS.settings["xh_color"]))
			cp.custom_minimum_size = Vector2(90, 38)
			cp.color_changed.connect(func(col): GS.settings["xh_color"] = col.to_html(false); if preview: preview.queue_redraw())
			cols.add_child(cp)
			_row("Renk", cols)
			_slide("xh_size", "Çizgi Uzunluğu", 0, 30, 1, "%d")
			_slide("xh_gap", "Boşluk", 0, 30, 1, "%d")
			_slide("xh_thick", "Kalınlık", 1, 8, 0.5, "%.1f")
			_slide("xh_alpha", "Opaklık", 0.2, 1.0, 0.05)
			_check("xh_dot", "Merkez Nokta")
			_check("xh_outline", "Dış Çizgi (Kontur)")
			_check("xh_dynamic", "Dinamik Nişangah", "Hareket ve ateşte açılır")
			_check("hit_marker", "İsabet İşareti")
		"kontrol":
			_section("FARE")
			_slide("sens", "Fare Hassasiyeti", 0.1, 5.0, 0.01, "%.2f")
			_slide("ads_sens", "Nişan Alma Hassasiyeti", 0.1, 2.0, 0.01, "%.2f")
			_slide("scope_sens", "Dürbün Hassasiyeti", 0.1, 2.0, 0.01, "%.2f")
			_check("invert_y", "Dikey Ekseni Ters Çevir")
			_section("TUŞ ATAMALARI  (değiştirmek için tıkla, sonra tuşa bas)")
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 18)
			grid.add_theme_constant_override("v_separation", 8)
			body.add_child(grid)
			for a in GS.BIND_NAMES.keys():
				var l := UI.lbl(GS.BIND_NAMES[a], 20, UI.TEXT)
				l.custom_minimum_size = Vector2(220, 0)
				grid.add_child(l)
				var b := UI.btn(GS.bind_label(a), Callable(), 18, false, 190, 40)
				b.pressed.connect(func(): rebinding = a; rebind_btn = b; b.text = "... tuşa bas ..."; SFX.play("ui_click", -6))
				grid.add_child(b)
			body.add_child(UI.lbl("Sol Tık: Ateş  •  Sağ Tık: Nişan Al / Ağır Bıçak / Yakın Atış  •  Fare Tekerleği: Silah Değiştir", 18, UI.DIM))
		"ses":
			_section("SES SEVİYELERİ")
			_slide("vol_master", "Ana Ses", 0, 1, 0.01, "%.2f")
			_slide("vol_sfx", "Efektler (Silah, Adım)", 0, 1, 0.01, "%.2f")
			_slide("vol_music", "Müzik", 0, 1, 0.01, "%.2f")
			_check("announcer", "Yapay zeka anons sesi (Kafadan!, Çifte öldürme!...)")
			_slide("vol_amb", "Ortam Sesleri", 0, 1, 0.01, "%.2f")
			body.add_child(UI.btn("TEST: SİLAH SESİ", func(): GS.apply_settings(); SFX.play("shot_ak"), 18, false, 260, 42))
		"oyun":
			_section("ARAYÜZ")
			_check("minimap", "Mini Harita")
			_check("kill_feed", "Öldürme Akışı")
			_check("blood", "Kan Efektleri")
			_check("damage_numbers", "Hasar Göstergesi")
			if not in_match:
				_section("PROFİL")
				var le := LineEdit.new()
				le.text = str(GS.profile["name"])
				le.max_length = 16
				le.custom_minimum_size = Vector2(300, 42)
				le.text_changed.connect(func(t): if t.strip_edges().length() >= 3: GS.profile["name"] = t.strip_edges())
				_row("Oyuncu Adı", le)
				var rb := UI.btn("PROFİLİ SIFIRLA", func(): GS.profile = GS.default_profile(); GS.save_profile(); _build(), 18, false, 260, 42)
				_row("Tüm ilerleme", rb, "Dikkat: geri alınamaz!")

func _input(e: InputEvent) -> void:
	if rebinding != "" and e is InputEventKey and e.pressed:
		var b: Dictionary = GS.settings.get("binds", {})
		if e.physical_keycode == KEY_ESCAPE:
			rebinding = ""
			_build()
			get_viewport().set_input_as_handled()
			return
		b[rebinding] = [int(e.physical_keycode)]
		GS.settings["binds"] = b
		rebinding = ""
		GS.apply_binds()
		SFX.play("ui_click", -4)
		_build()
		get_viewport().set_input_as_handled()

func _reset() -> void:
	var name_keep = GS.profile["name"]
	GS.settings = GS.default_settings()
	GS.save_settings()
	_build()

func _save_close() -> void:
	GS.save_settings()
	SFX.play("success", -8)
	if on_close.is_valid():
		on_close.call()

class PreviewBox extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.42, 0.5))
		draw_rect(Rect2(Vector2(0, size.y * 0.55), Vector2(size.x, size.y * 0.45)), Color(0.32, 0.3, 0.27))
		for i in 6:
			draw_rect(Rect2(Vector2(60 + i * 180, 30), Vector2(120, size.y * 0.55 - 30)), Color(0.55, 0.5, 0.45))
		var s: Dictionary = GS.settings
		var c := size / 2
		var col := Color(str(s["xh_color"])); col.a = float(s["xh_alpha"])
		var gap: float = float(s["xh_gap"]); var ln: float = float(s["xh_size"]); var th: float = float(s["xh_thick"])
		var style := int(s["xh_style"])
		var oc := Color(0, 0, 0, col.a * 0.8)
		var rects: Array = []
		if style == 0 or style == 3 or style == 4:
			rects.append(Rect2(c.x - gap - ln, c.y - th / 2, ln, th)); rects.append(Rect2(c.x + gap, c.y - th / 2, ln, th))
			rects.append(Rect2(c.x - th / 2, c.y + gap, th, ln))
			if style != 3: rects.append(Rect2(c.x - th / 2, c.y - gap - ln, th, ln))
		if s["xh_outline"]:
			for r in rects: draw_rect(r.grow(1.0), oc)
		for r in rects: draw_rect(r, col)
		if style == 2:
			if s["xh_outline"]: draw_arc(c, gap + 4, 0, TAU, 48, oc, th + 2, true)
			draw_arc(c, gap + 4, 0, TAU, 48, col, th, true)
		if s["xh_dot"] or style == 1 or style == 4:
			if s["xh_outline"]: draw_circle(c, th + 1.2, oc)
			draw_circle(c, th, col)
