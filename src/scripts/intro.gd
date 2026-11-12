extends CanvasLayer
## v3.7.1 boot intro (~3.4 s, any key / click skips). Calm and cinematic: a slow drifting smoke backdrop,
## an anamorphic light line opens from the centre, the emblem fades in with a soft glow, a light sweep
## crosses the SOKAK wordmark, the tagline settles, then it dissolves into the login screen underneath.
## Everything is shader-drawn with dithering, so there are no colour bands.

signal finished

const DUR := 3.4
var t := 0.0
var done := false
var root: Control
var bg: ColorRect
var bg_mat: ShaderMaterial
var emblem: TextureRect
var logo: TextureRect
var logo_mat: ShaderMaterial
var tag: Label
var line: ColorRect

const BG_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;
uniform float line_y = 0.5;
uniform vec2 res = vec2(1920.0, 1080.0);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { s += a * n(p); p = p * 2.02 + 7.3; a *= 0.5; } return s; }
void fragment() {
	vec2 uv = UV;
	vec2 p = (uv - 0.5) * vec2(res.x / res.y, 1.0);
	float fade_in = smoothstep(0.0, 0.9, t);
	// slow warm smoke
	float sm = fbm(p * 2.2 + vec2(t * 0.05, -t * 0.03)) * fbm(p * 1.3 - vec2(t * 0.02, 0.0) + 4.0);
	vec3 col = vec3(0.018, 0.02, 0.026);
	col += vec3(0.32, 0.16, 0.06) * sm * 0.55 * fade_in;
	// soft central glow behind the logo
	float r = length(p * vec2(0.8, 1.15) - vec2(0.0, -0.04));
	col += vec3(1.0, 0.48, 0.12) * exp(-r * r * 7.0) * 0.16 * fade_in;
	// anamorphic light line through the centre (opens at the start, then fades to a faint streak)
	float open = smoothstep(0.05, 0.75, t);
	float lw = mix(0.0, 0.9, open);
	float ln = exp(-pow((uv.y - line_y) * res.y / 1.6, 2.0)) * smoothstep(lw, 0.0, abs(p.x));
	col += vec3(1.0, 0.62, 0.25) * ln * mix(1.4, 0.35, smoothstep(0.7, 1.6, t));
	// vignette
	col *= 1.0 - smoothstep(0.45, 1.15, length(p));
	// fine film grain + dithering (kills banding)
	col += (h(uv * res + fract(t) * 100.0) - 0.5) * 0.018;
	COLOR = vec4(col, 1.0);
}
"""

const SWEEP_SHADER := """
shader_type canvas_item;
uniform float sweep = -0.3;   // -0.3 .. 1.3 across the logo
uniform float reveal = 0.0;   // 0..1 soft left -> right reveal
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = 1.0 - smoothstep(reveal * 1.2 - 0.2, reveal * 1.2, UV.x);
	float band = exp(-pow((UV.x - UV.y * 0.25 - sweep) * 9.0, 2.0));
	c.rgb += vec3(1.0, 0.92, 0.8) * band * 0.85 * c.a;
	COLOR = vec4(c.rgb, c.a * m) * COLOR;
}
"""

func _ready() -> void:
	layer = 90
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _finish())
	add_child(root)
	bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_mat = ShaderMaterial.new()
	var sh := Shader.new(); sh.code = BG_SHADER
	bg_mat.shader = sh
	bg.material = bg_mat
	root.add_child(bg)
	emblem = TextureRect.new()
	emblem.texture = load("res://assets/ui/emblem.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.modulate.a = 0.0
	root.add_child(emblem)
	logo = TextureRect.new()
	logo.texture = load("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_mat = ShaderMaterial.new()
	var sh2 := Shader.new(); sh2.code = SWEEP_SHADER
	logo_mat.shader = sh2
	logo.material = logo_mat
	root.add_child(logo)
	tag = Label.new()
	tag.text = "T Ü R K İ Y E ' N İ N   S O K A K L A R I N D A   T A K T İ K   Ç A T I Ş M A"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UI.font("Rajdhani-SemiBold"))
	tag.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	tag.modulate.a = 0.0
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	line = ColorRect.new()
	line.color = Color(1.0, 0.55, 0.15, 0.9)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(line)
	get_viewport().size_changed.connect(_layout)
	_layout()
	SFX.play("intro_hit", -4)

func _layout() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	bg_mat.set_shader_parameter("res", sz)
	var es := sz.y * 0.16
	emblem.size = Vector2(es, es)
	emblem.pivot_offset = emblem.size * 0.5
	emblem.position = Vector2(sz.x * 0.5 - es * 0.5, sz.y * 0.30 - es * 0.5)
	var lw := sz.x * 0.34
	var lh := lw * float(logo.texture.get_height()) / float(logo.texture.get_width())
	logo.size = Vector2(lw, lh)
	logo.position = Vector2(sz.x * 0.5 - lw * 0.5, sz.y * 0.43)
	bg_mat.set_shader_parameter("line_y", (logo.position.y + lh * 0.36) / sz.y)
	tag.add_theme_font_size_override("font_size", int(sz.y * 0.019))
	tag.size = Vector2(sz.x, sz.y * 0.04)
	tag.position = Vector2(0, logo.position.y + lh + sz.y * 0.045)
	line.size = Vector2(0, 2)
	line.position = Vector2(sz.x * 0.5, tag.position.y + sz.y * 0.05)

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_finish()

static func _e(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _process(d: float) -> void:
	t += minf(d, 0.1)
	bg_mat.set_shader_parameter("t", t)
	var sz: Vector2 = get_viewport().get_visible_rect().size
	# emblem: gentle fade + settle (1.06 -> 1.0)
	var k := _e((t - 0.35) / 0.8)
	emblem.modulate.a = k
	emblem.scale = Vector2.ONE * lerpf(1.06, 1.0, k)
	# wordmark: soft reveal, then a light sweep
	logo_mat.set_shader_parameter("reveal", _e((t - 0.75) / 0.75))
	logo_mat.set_shader_parameter("sweep", lerpf(-0.4, 1.4, clampf((t - 1.25) / 0.7, 0.0, 1.0)))
	# tagline + thin accent line
	var ta := _e((t - 1.55) / 0.6)
	tag.modulate.a = ta * 0.85
	tag.position.y = logo.position.y + logo.size.y + sz.y * 0.045 + (1.0 - ta) * 8.0
	var lw2 := sz.x * 0.16 * _e((t - 1.7) / 0.6)
	line.size.x = lw2
	line.position.x = sz.x * 0.5 - lw2 * 0.5
	if t > DUR and not done:
		_finish()

func _finish() -> void:
	if done:
		return
	done = true
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): finished.emit(); queue_free())
