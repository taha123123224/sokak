class_name UI
extends RefCounted
## UI helpers + theme

const ACCENT := Color("ff8a1f")
const ACCENT2 := Color("ffb347")
# CS2-like neutral palette: smoky graphite glass instead of navy, hairline white borders
const BG := Color(0.055, 0.06, 0.07, 0.84)
const BG2 := Color(0.085, 0.09, 0.105, 0.9)
const LINE := Color(1, 1, 1, 0.1)
const TEXT := Color(0.92, 0.93, 0.95)
const DIM := Color(0.6, 0.63, 0.68)
const GLASS := Color(0.045, 0.05, 0.058, 0.68)
const RED := Color("ff3b3b")
const GREEN := Color("38e07b")
const GOLD := Color("ffc23d")

static var _fonts := {}
static var _icons := {}

## v4.18 typography (all SIL OFL 1.1, Google Fonts):
##   Rajdhani Bold        -> headings, level / rank numbers, competitive read-outs ("RussoOne-Regular", "Teko")
##   Roboto Condensed     -> navigation, buttons, scores and stats ("Rajdhani-Bold", "Rajdhani-SemiBold")
##   Inter                -> descriptions, settings, dialogs, notifications, inputs ("Inter", "InterSemi", default font)
## Fixed-width layouts tuned for condensed type keep Roboto Condensed ("Rajdhani-Medium") so nothing overflows.
## Old names are kept as aliases so every existing call site follows the new roles. Barlow stays as glyph fallback.
const FONT_ROLES := {
	"RussoOne-Regular": ["Rajdhani-Bold", 0], "Teko": ["Rajdhani-Bold", 0], "Display": ["Rajdhani-Bold", 0],
	"Rajdhani-Bold": ["RobotoCondensed-VF", 700], "Nav": ["RobotoCondensed-VF", 700],
	"Rajdhani-SemiBold": ["RobotoCondensed-VF", 600], "Stat": ["RobotoCondensed-VF", 600],
	"Rajdhani-Medium": ["RobotoCondensed-VF", 400], "Inter": ["Inter-VF", 450], "InterSemi": ["Inter-VF", 600],
	"BarlowSemiCondensed-Bold": ["RobotoCondensed-VF", 700]}
static func font(n: String) -> Font:
	if _fonts.has(n):
		return _fonts[n]
	var spec: Array = FONT_ROLES.get(n, [n, 0])
	var base: FontFile = load("res://assets/fonts/%s.ttf" % str(spec[0]))
	if base == null:
		base = load("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
	var fb: FontFile = load("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
	if fb and fb != base and base.fallbacks.is_empty():
		base.fallbacks = [fb]
	var f: Font = base
	if int(spec[1]) > 0:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {"wght": int(spec[1])}
		f = fv
	elif str(spec[0]) == "Rajdhani-Bold":
		# display face: a touch narrower so headings sized for the old condensed face never overflow
		var fd := FontVariation.new()
		fd.base_font = base
		fd.spacing_glyph = -1
		f = fd
	_fonts[n] = f
	return f

## Icon library: Lucide (ISC, UI chrome) under assets/icons/lucide, game-icons.net (CC BY 3.0, game items/medals)
## under assets/icons/game. All SVGs are white so they can be tinted with modulate / draw colour.
static func icon_tex(n: String) -> Texture2D:
	if _icons.has(n):
		return _icons[n]
	var p := "res://assets/icons/%s.svg" % (n if "/" in n else "lucide/" + n)
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_icons[n] = t
	return t

static func icon(n: String, sz: int = 20, col: Color = TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_tex(n)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(sz, sz)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## button with a leading icon (Button.icon is tinted by the theme's icon colours)
static func ibtn(ic: String, text: String, cb: Callable = Callable(), size: int = 18, primary: bool = false, minw: int = 0, minh: int = 44) -> Button:
	var b := btn(text, cb, size, primary, minw, minh)
	b.icon = icon_tex(ic)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", int(size * 1.15))
	b.add_theme_constant_override("h_separation", 8)
	b.add_theme_color_override("icon_normal_color", Color(0.08, 0.05, 0.02) if primary else Color(1, 1, 1, 0.8))
	b.add_theme_color_override("icon_hover_color", Color(0.05, 0.03, 0.0) if primary else Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color.WHITE)
	return b

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
	t.default_font = font("Inter")
	t.default_font_size = 18
	# type variations (Godot "Theme type variations"): Label + theme_type_variation = "H1" etc.
	for tv in [["H1", "Display", 40, Color.WHITE], ["H2", "Display", 28, Color.WHITE], ["H3", "Nav", 20, TEXT],
			["StatValue", "Stat", 26, Color.WHITE], ["StatLabel", "Nav", 13, DIM], ["Body", "Inter", 16, TEXT], ["Caption", "Inter", 13, DIM]]:
		t.set_type_variation(tv[0], "Label")
		t.set_font("font", tv[0], font(tv[1])); t.set_font_size("font_size", tv[0], tv[2]); t.set_color("font_color", tv[0], tv[3])
	t.set_type_variation("NavButton", "Button")
	t.set_font("font", "NavButton", font("Nav"))
	for c in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_font("font", c, font("Nav"))
	# Button
	var bn := sb(Color(0.12, 0.125, 0.14, 0.9), LINE, 1, 3, 14)
	var bh := sb(Color(0.19, 0.2, 0.22, 0.95), Color(1, 1, 1, 0.32), 1, 3, 14)
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
	t.set_font("font", "LineEdit", font("Inter")); t.set_font("font", "TextEdit", font("Inter"))
	t.set_font("normal_font", "RichTextLabel", font("Inter")); t.set_font("bold_font", "RichTextLabel", font("InterSemi"))
	# CheckBox / CheckButton inherit Button styles otherwise (orange "pressed" plate behind the box)
	var cb_empty := StyleBoxEmpty.new()
	cb_empty.content_margin_left = 4; cb_empty.content_margin_right = 6; cb_empty.content_margin_top = 4; cb_empty.content_margin_bottom = 4
	var cb_hover := sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 6)
	for ct in ["CheckBox", "CheckButton"]:
		for st in ["normal", "pressed", "disabled", "hover_pressed", "focus"]:
			t.set_stylebox(st, ct, cb_empty)
		t.set_stylebox("hover", ct, cb_hover)
		t.set_color("font_pressed_color", ct, Color.WHITE); t.set_color("font_hover_pressed_color", ct, Color.WHITE)
	# Kenney UI Pack (CC0) grey check / radio glyphs, tinted to the palette
	for pair in [["checked", "check_on"], ["unchecked", "check_off"], ["radio_checked", "radio_on"], ["radio_unchecked", "radio_off"]]:
		var ct: Texture2D = load("res://assets/ui/kenney/%s.png" % pair[1]) if ResourceLoader.exists("res://assets/ui/kenney/%s.png" % pair[1]) else null
		if ct:
			t.set_icon(pair[0], "CheckBox", ct)
	var arrow: Texture2D = load("res://assets/ui/kenney/arrow_down.png") if ResourceLoader.exists("res://assets/ui/kenney/arrow_down.png") else null
	if arrow:
		t.set_icon("arrow", "OptionButton", arrow)
	# Scroll
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber", "VScrollBar", sb(Color(0.25, 0.28, 0.35), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(ACCENT, Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", sb(ACCENT, Color(0, 0, 0, 0), 0, 3, 2))
	# popups / dialogs: Kenney Sci-Fi notched glass, tinted graphite
	t.set_stylebox("panel", "PopupPanel", notch_sb(Color(0.075, 0.08, 0.095, 0.98), "panel_notches", 16))
	t.set_stylebox("panel", "AcceptDialog", notch_sb(Color(0.075, 0.08, 0.095, 0.98), "panel_notches", 16))
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
		var n := sb(ACCENT, Color(1, 0.75, 0.45, 0.9), 1, 3, 18)
		n.shadow_color = Color(1, 0.5, 0.1, 0.25); n.shadow_size = 10
		var h := sb(ACCENT2, Color.WHITE, 1, 3, 18)
		h.shadow_color = Color(1, 0.55, 0.15, 0.4); h.shadow_size = 14
		var p := sb(ACCENT.darkened(0.25), ACCENT2, 1, 3, 18)
		b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h); b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.0))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.set_meta("sfx", true)
	if cb.is_valid():
		b.pressed.connect(func():
			if bool(GS.settings.get("ui_sounds", true)):
				SFX.ui("ui_click", -4)
			cb.call())
	b.mouse_entered.connect(func():
		if bool(GS.settings.get("ui_sounds", true)) and not b.disabled:
			SFX.ui("ui_hover", -16))
	return b

## Kenney Sci-Fi UI (CC0) notched glass panel as a 9-slice, tinted to graphite. Used for toasts,
## notifications, dialogs and HUD read-outs so every popup shares one silhouette.
static func notch_sb(tint: Color = Color(0.11, 0.115, 0.13, 0.96), kind: String = "panel_notch_tr", pad: int = 14) -> StyleBox:
	var p := "res://assets/ui/kenney/%s.png" % kind
	if not ResourceLoader.exists(p):
		return sb(tint, LINE, 1, 4, pad)
	var s := StyleBoxTexture.new()
	s.texture = load(p)
	s.texture_margin_left = 22; s.texture_margin_right = 22; s.texture_margin_top = 22; s.texture_margin_bottom = 22
	s.modulate_color = tint
	s.content_margin_left = pad + 4; s.content_margin_right = pad + 4
	s.content_margin_top = pad * 0.7; s.content_margin_bottom = pad * 0.7
	return s

## CS2-style frosted panel
static func glass(pad: int = 14, radius: int = 4) -> PanelContainer:
	var p := PanelContainer.new()
	var st := sb(GLASS, Color(1, 1, 1, 0.08), 1, radius, pad)
	st.shadow_color = Color(0, 0, 0, 0.18); st.shadow_size = 12
	p.add_theme_stylebox_override("panel", st)
	return p

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

## "+4" upgrade badge: slanted tier-coloured chip with a chevron and a light sweep that runs over it
static func lvl_badge(lvl: int, fs: int = 15) -> Control:
	## v3.5.1 weapon level emblem (Higgsfield art): cyan +1/+2, violet +3/+4, ember +5/+6, gold +7
	var c: Color = GS.lvl_color(lvl)
	var tier: int = 0 if lvl <= 2 else (1 if lvl <= 4 else (2 if lvl <= 6 else 3))
	var box := Control.new()
	var sz := float(fs) * 2.1
	box.custom_minimum_size = Vector2(sz * 1.05, sz)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pth := "res://assets/ui/lvl/t%d.png" % tier
	if ResourceLoader.exists(pth):
		var em := TextureRect.new()
		em.texture = load(pth)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.set_anchors_preset(Control.PRESET_FULL_RECT)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(em)
		if lvl >= 5:
			em.tree_entered.connect(func():
				var tw := em.create_tween().set_loops()
				tw.tween_property(em, "modulate", Color(1.35, 1.25, 1.15), 0.6).set_trans(Tween.TRANS_SINE)
				tw.tween_property(em, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE), CONNECT_ONE_SHOT)
	var t := lbl("+%d" % lvl, int(fs * 0.95), Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 5)
	t.add_theme_color_override("font_outline_color", Color(c.r * 0.25, c.g * 0.25, c.b * 0.25))
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_top = -sz * 0.04
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	return box

