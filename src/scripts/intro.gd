extends CanvasLayer
## FPS-style boot intro (~3.6 s, any key / click skips): a low cinematic hit, the emblem slams in with a
## flash, the SOKAK wordmark is revealed by a light sweep, OPERASYON spreads out, then everything fades
## into the login screen that has been loading underneath the whole time.

signal finished

const DUR := 3.7
var t := 0.0
var done := false
var canvas: Control
var emblem: Texture2D
var logo: Texture2D
var embers: Array = []

func _ready() -> void:
	layer = 90
	emblem = load("res://assets/ui/emblem.png")
	logo = load("res://assets/ui/logo.png")
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_intro)
	canvas.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _finish())
	add_child(canvas)
	for i in 70:
		embers.append([randf(), randf(), randf_range(0.02, 0.09), randf_range(1.0, 3.2), randf() * TAU])
	SFX.play("intro_hit", -2)

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_finish()

func _process(d: float) -> void:
	t += d
	canvas.queue_redraw()
	if t > DUR and not done:
		_finish()

func _finish() -> void:
	if done:
		return
	done = true
	var tw := create_tween()
	tw.tween_property(canvas, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func(): finished.emit(); queue_free())

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _draw_intro() -> void:
	var sz := canvas.size
	var c := sz * 0.5
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.013, 0.016))
	# warm vignette glow behind the logo
	var gl := _ease((t - 0.3) / 1.2)
	for i in 6:
		canvas.draw_circle(c + Vector2(0, -20), sz.y * (0.55 - i * 0.07), Color(1.0, 0.45, 0.1, 0.018 * gl))
	# drifting embers
	for e in embers:
		var x: float = fmod(e[0] + t * 0.012 * e[3], 1.0) * sz.x
		var y: float = fmod(e[1] - t * e[2] + 1.0, 1.0) * sz.y
		var a: float = (0.35 + 0.35 * sin(t * e[3] + e[4])) * gl
		canvas.draw_circle(Vector2(x, y), 1.4 + e[2] * 14.0, Color(1.0, 0.6, 0.25, a))
	# emblem: slams in (scale 1.7 -> 1) with a flash
	var k := _ease((t - 0.15) / 0.5)
	if t > 0.15 and emblem:
		var es: float = lerpf(1.7, 1.0, k) * sz.y * 0.2
		var ec := c + Vector2(0, -sz.y * 0.15)
		canvas.draw_texture_rect(emblem, Rect2(ec - Vector2(es, es) * 0.5, Vector2(es, es)), false, Color(1, 1, 1, k))
	var fl := clampf(1.0 - absf(t - 0.62) / 0.22, 0.0, 1.0)
	if fl > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.85, 0.65, 0.22 * fl))
	# wordmark revealed left -> right behind a light sweep
	if logo and t > 0.75:
		var lw := sz.x * 0.42
		var lh := lw * float(logo.get_height()) / float(logo.get_width())
		var lp := c + Vector2(-lw * 0.5, sz.y * 0.02)
		var rv := _ease((t - 0.75) / 0.7)
		var src := Rect2(0, 0, logo.get_width() * rv, logo.get_height())
		canvas.draw_texture_rect_region(logo, Rect2(lp, Vector2(lw * rv, lh)), src)
		var sx := lp.x + lw * rv
		if rv < 0.999:
			for i in 5:
				canvas.draw_rect(Rect2(sx - 3 - i * 6, lp.y - 8, 4 + i * 2, lh + 16), Color(1, 0.9, 0.7, 0.32 - i * 0.06))
		# tagline
		var ta := _ease((t - 1.55) / 0.6)
		if ta > 0.0:
			var f: Font = UI.font("Rajdhani-Bold")
			var tag := "TÜRKİYE'NİN SOKAKLARINDA TAKTİK ÇATIŞMA"
			var fs := int(sz.y * 0.024)
			var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			canvas.draw_string(f, Vector2(c.x - tw * 0.5, lp.y + lh + sz.y * 0.07), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 * ta))
			var bw := lw * 0.5 * ta
			canvas.draw_rect(Rect2(c.x - bw * 0.5, lp.y + lh + sz.y * 0.095, bw, 2), Color(1, 0.55, 0.12, 0.9 * ta))
	# letterbox bars that open at the start
	var lb := (1.0 - _ease(t / 0.6)) * sz.y * 0.5
	canvas.draw_rect(Rect2(0, 0, sz.x, lb), Color.BLACK)
	canvas.draw_rect(Rect2(0, sz.y - lb, sz.x, lb), Color.BLACK)
