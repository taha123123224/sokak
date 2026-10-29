class_name UI
extends RefCounted
## UI helpers + theme

const ACCENT := Color("ff8a1f")
const ACCENT2 := Color("ffb347")
const BG := Color(0.05, 0.06, 0.085, 0.88)
const BG2 := Color(0.08, 0.095, 0.13, 0.92)
const LINE := Color(0.18, 0.22, 0.3, 1)
const TEXT := Color(0.9, 0.92, 0.95)
const DIM := Color(0.55, 0.6, 0.68)
const RED := Color("ff3b3b")
const GREEN := Color("38e07b")
const GOLD := Color("ffc23d")

static var _fonts := {}

static func font(n: String) -> FontFile:
	if _fonts.has(n):
		return _fonts[n]
	var f: FontFile = load("res://assets/fonts/%s.ttf" % n)
	_fonts[n] = f
	return f

static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 3, pad: int = 10, skew: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	s.skew = Vector2(skew, 0)
	s.anti_aliasing = true
	return s

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("Rajdhani-SemiBold")
	t.default_font_size = 20
	# Button
	var bn := sb(Color(0.1, 0.12, 0.165, 0.95), LINE, 1, 3, 14)
	var bh := sb(Color(0.14, 0.16, 0.22, 0.98), ACCENT, 1, 3, 14)
	var bp := sb(ACCENT.darkened(0.15), ACCENT2, 1, 3, 14)
	var bd := sb(Color(0.08, 0.09, 0.11, 0.7), Color(0.15, 0.16, 0.2), 1, 3, 14)
	var bf := sb(Color(0, 0, 0, 0), ACCENT2, 1, 3, 14)
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, bn); t.set_stylebox("hover", c, bh); t.set_stylebox("pressed", c, bp)
		t.set_stylebox("disabled", c, bd); t.set_stylebox("focus", c, bf); t.set_stylebox("hover_pressed", c, bp)
		t.set_color("font_color", c, TEXT); t.set_color("font_hover_color", c, Color.WHITE)
		t.set_color("font_pressed_color", c, Color.WHITE); t.set_color("font_disabled_color", c, DIM)
		t.set_color("font_hover_pressed_color", c, Color.WHITE)
	# Panels
	t.set_stylebox("panel", "Panel", sb(BG, LINE, 1, 4))
	t.set_stylebox("panel", "PanelContainer", sb(BG, LINE, 1, 4, 14))
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_y", "Label", 1)
	# LineEdit
	t.set_stylebox("normal", "LineEdit", sb(Color(0.03, 0.04, 0.06, 0.9), LINE, 1, 3, 10))
	t.set_stylebox("focus", "LineEdit", sb(Color(0.03, 0.04, 0.06, 0.9), ACCENT, 1, 3, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	# Slider
	var track := sb(Color(0.12, 0.14, 0.19), Color(0, 0, 0, 0), 0, 3, 0)
	track.content_margin_top = 3; track.content_margin_bottom = 3
	var fill := sb(ACCENT, Color(0, 0, 0, 0), 0, 3, 0)
	fill.content_margin_top = 3; fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var g := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	g.fill(Color(0, 0, 0, 0))
	for y in 18:
		for x in 18:
			var d := Vector2(x - 8.5, y - 8.5).length()
			if d < 8.0:
				g.set_pixel(x, y, Color.WHITE if d < 6.0 else ACCENT)
	var gt := ImageTexture.create_from_image(g)
	t.set_icon("grabber", "HSlider", gt); t.set_icon("grabber_highlight", "HSlider", gt)
	# ProgressBar
	t.set_stylebox("background", "ProgressBar", sb(Color(0.1, 0.12, 0.16), Color(0, 0, 0, 0), 0, 2, 0))
	t.set_stylebox("fill", "ProgressBar", sb(ACCENT, Color(0, 0, 0, 0), 0, 2, 0))
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	# CheckBox / CheckButton
	t.set_color("font_color", "CheckBox", TEXT); t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_color", "CheckButton", TEXT)
	# Scroll
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber", "VScrollBar", sb(Color(0.25, 0.28, 0.35), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(ACCENT, Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", sb(ACCENT, Color(0, 0, 0, 0), 0, 3, 2))
	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", sb(Color(0.02, 0.03, 0.05, 0.95), ACCENT, 1, 3, 8))
	# PopupMenu
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.06, 0.07, 0.1, 0.98), LINE, 1, 3, 6))
	t.set_stylebox("hover", "PopupMenu", sb(ACCENT.darkened(0.2), Color(0, 0, 0, 0), 0, 2, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	return t

static func lbl(text: String, size: int = 20, color: Color = TEXT, fnt: String = "Rajdhani-SemiBold", align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(fnt))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func btn(text: String, cb: Callable = Callable(), size: int = 20, primary: bool = false, minw: int = 0, minh: int = 44) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font("Rajdhani-Bold"))
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(minw, minh)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		var n := sb(ACCENT, ACCENT2, 1, 3, 18)
		var h := sb(ACCENT2, Color.WHITE, 1, 3, 18)
		var p := sb(ACCENT.darkened(0.25), ACCENT2, 1, 3, 18)
		b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h); b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.0))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	if cb.is_valid():
		b.pressed.connect(func(): SFX.play("ui_click", -4); cb.call())
	b.mouse_entered.connect(func(): SFX.play("ui_hover", -14))
	return b

static func panel(bg: Color = BG, border: Color = LINE, pad: int = 14, radius: int = 4) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, 1, radius, pad))
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func spacer(expand: bool = true, w: int = 0, h: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func header(text: String, size: int = 26) -> Control:
	var h := hbox(10)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(5, size)
	h.add_child(bar)
	h.add_child(lbl(text, size, Color.WHITE, "RussoOne-Regular"))
	return h

static func bar(value: float, maxv: float, color: Color = ACCENT, h: int = 8, w: int = 0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxv
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(w, h)
	p.add_theme_stylebox_override("fill", sb(color, Color(0, 0, 0, 0), 0, 2, 0))
	return p

static func clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

static func money(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	var i := s.length()
	while i > 3:
		out = "." + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" if v < 0 else "") + out

static func slider(minv: float, maxv: float, step: float, value: float, cb: Callable, w: int = 260) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv; s.max_value = maxv; s.step = step; s.value = value
	s.custom_minimum_size = Vector2(w, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	return s
