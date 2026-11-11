extends CanvasLayer
## In-match HUD.

var match_node
var player
var root: Control
var vm_holder: Control
var xhair: Control
var hit_ctl: Control
var dmg_ctl: Control
var minimap: Control
var hp_bar: ProgressBar
var hp_lbl: Label
var ar_bar: ProgressBar
var ammo_lbl: Label
var reserve_lbl: Label
var wname_lbl: Label
var nade_lbl: Label
var timer_lbl: Label
var score_box: HBoxContainer
var feed: VBoxContainer
var center: Label
var center2: Label
var target_lbl: Label
var scope_ov: Control
var scope_rect: ColorRect
const SCOPE_SHADER := """
shader_type canvas_item;
uniform float aspect = 1.7778;
uniform float radius = 0.47;
uniform vec2 sway = vec2(0.0);
float line_mask(float d, float w) { return 1.0 - smoothstep(w, w + fwidth(d) * 1.5, d); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0) - sway;
	float d = length(p);
	float aa = fwidth(d) * 1.5;
	float outside = smoothstep(radius - aa, radius + aa, d);
	// tube edge: dark ring + soft inner vignette
	float ring = smoothstep(radius - 0.035, radius, d);
	float vig = smoothstep(radius * 0.55, radius, d);
	float a = max(outside, ring * 0.85 + vig * 0.22);
	vec3 c = vec3(0.0);
	// reticle: thin cross, thick posts towards the edge, mil-dots
	float thin = max(line_mask(abs(p.y), 0.0009) * step(abs(p.x), radius), line_mask(abs(p.x), 0.0009) * step(abs(p.y), radius));
	float posts = max(line_mask(abs(p.y), 0.004) * step(0.14, abs(p.x)), line_mask(abs(p.x), 0.004) * step(0.14, p.y));
	posts = max(posts, line_mask(abs(p.x), 0.004) * step(0.14, -p.y));
	float dots = 0.0;
	for (int i = 1; i <= 5; i++) {
		float o = float(i) * 0.025;
		dots = max(dots, 1.0 - smoothstep(0.0028, 0.0028 + aa, length(abs(p) - vec2(o, 0.0))));
		dots = max(dots, 1.0 - smoothstep(0.0028, 0.0028 + aa, length(abs(p) - vec2(0.0, o))));
	}
	float ret = max(max(thin * 0.9, posts), dots) * (1.0 - outside);
	a = max(a, ret);
	// red illuminated centre dot with a soft glow
	float cd = 1.0 - smoothstep(0.0024, 0.0024 + aa, d);
	float glow = exp(-d * d / 0.00004) * 0.35;
	c = mix(c, vec3(1.0, 0.12, 0.06), clamp(cd + glow, 0.0, 1.0));
	a = max(a, clamp(cd + glow, 0.0, 1.0));
	// faint lens glare in the upper-left of the glass
	float glare = smoothstep(0.2, 0.0, length(p - vec2(-0.16, -0.18))) * 0.06 * (1.0 - outside);
	c = mix(c, vec3(0.75, 0.85, 1.0), glare / max(a + glare, 0.001));
	a = max(a, glare);
	COLOR = vec4(c, a);
}
"""
var vignette: TextureRect
var death_panel: Control
var death_lbl: Label
var death_timer_lbl: Label
var board: PanelContainer
var pause_panel: Control
var settings_holder: Control
var end_panel: Control
var count_lbl: Label
var reload_bar: ProgressBar
var hit_t := 0.0
var hit_head := false
var hit_kill := false
var dmg_list: Array = []
var pings := {}
var death_t := 0.0
var board_t := 0.0
var force_board := false   # test only
var target_t := 0.0
var hb_t := 0.0
var medal_box: Control
var ammo_panel: Control
var score_bar: Control
var hp_shown := 100.0
var hp_trail := 100.0
var medal_tex: TextureRect
var medal_ring: Control
var medal_title: Label
var medal_sub: Label
var medal_skulls: HBoxContainer
var medal_tw: Tween
var blood_ov: TextureRect
var blood_a := 0.0
var medals := {}
var buy_panel: Control
var buy_open := false

func _exit_tree() -> void:
	if Online.announced.is_connected(_on_announce): Online.announced.disconnect(_on_announce)

func _on_announce(t: String) -> void:
	center_msg("◆ DUYURU: " + t, Color("ff9aa6"))

func _ready() -> void:
	Online.announced.connect(_on_announce)
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build_theme()
	add_child(root)
	vm_holder = Control.new()
	vm_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	vm_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vm_holder)

func setup(p) -> void:
	player = p
	# scope overlay
	scope_ov = Control.new()
	scope_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_ov.visible = false
	root.add_child(scope_ov)
	# procedural sniper scope: clear lens, thin reticle with mil-dots, red centre dot, black outside the tube
	scope_rect = ColorRect.new()
	scope_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SCOPE_SHADER
	sm.shader = sh
	scope_rect.material = sm
	scope_ov.add_child(scope_rect)
	# vignette (low hp)
	vignette = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0, 0, 0)); g.set_color(1, Color(0.55, 0, 0, 0.85))
	g.add_point(0.55, Color(0.6, 0, 0, 0))
	gt.gradient = g
	gt.width = 256; gt.height = 256
	vignette.texture = gt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0
	root.add_child(vignette)
	# crosshair, hitmarker, damage dirs
	xhair = Crosshair.new()
	xhair.hud = self
	xhair.set_anchors_preset(Control.PRESET_FULL_RECT)
	xhair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xhair)
	hit_ctl = HitMarker.new()
	hit_ctl.hud = self
	hit_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hit_ctl)
	dmg_ctl = DmgDir.new()
	dmg_ctl.hud = self
	dmg_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dmg_ctl)
	target_lbl = UI.lbl("", 22, UI.RED, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	target_lbl.set_anchors_preset(Control.PRESET_CENTER)
	target_lbl.position = Vector2(-200, 40)
	target_lbl.size = Vector2(400, 30)
	root.add_child(target_lbl)
	# legacy text widgets are kept (hidden) so the update loop stays simple; the new panels draw everything
	var legacy := Control.new()
	legacy.visible = false
	root.add_child(legacy)
	hp_lbl = UI.lbl("100", 52); legacy.add_child(hp_lbl)
	hp_bar = UI.bar(100, 100); legacy.add_child(hp_bar)
	ar_bar = UI.bar(100, 100); legacy.add_child(ar_bar)
	wname_lbl = UI.lbl(""); legacy.add_child(wname_lbl)
	ammo_lbl = UI.lbl(""); legacy.add_child(ammo_lbl)
	reserve_lbl = UI.lbl(""); legacy.add_child(reserve_lbl)
	nade_lbl = UI.lbl(""); legacy.add_child(nade_lbl)
	# bottom-left: health / armour
	var hpw := HealthPanel.new()
	hp_panel = hpw
	hpw.hud = self
	hpw.anchor_top = 1; hpw.anchor_bottom = 1
	hpw.offset_left = 26; hpw.offset_top = -138; hpw.offset_right = 446; hpw.offset_bottom = -22
	hpw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hpw)
	# bottom-right: weapon + ammo
	var amw := AmmoPanel.new()
	amw.hud = self
	amw.anchor_left = 1; amw.anchor_right = 1; amw.anchor_top = 1; amw.anchor_bottom = 1
	amw.offset_left = -486; amw.offset_top = -150; amw.offset_right = -26; amw.offset_bottom = -22
	amw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(amw)
	ammo_panel = amw
	reload_bar = UI.bar(0, 1, UI.ACCENT, 4, 200)
	reload_bar.set_anchors_preset(Control.PRESET_CENTER)
	reload_bar.position = Vector2(-100, 70)
	reload_bar.visible = false
	root.add_child(reload_bar)
	# top center: timer + score
	var tc := UI.vbox(4)
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-280, 12)
	tc.custom_minimum_size = Vector2(560, 0)
	root.add_child(tc)
	score_box = UI.hbox(0)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tc.add_child(score_box)
	# minimap
	if GS.settings.get("minimap", true):
		minimap = Minimap.new()
		minimap.hud = self
		minimap.tex = ImageTexture.create_from_image(match_node.minimap_img)
		minimap.position = Vector2(22, 22)
		minimap.size = Vector2(250, 270)
		minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(minimap)
	# kill feed
	feed = UI.vbox(3)
	feed.anchor_left = 1; feed.anchor_right = 1
	feed.offset_left = -560; feed.offset_right = -24; feed.offset_top = 24
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(feed)
	for i in 6:
		_kf_rows.append(_kf_new_row())     # built during loading, recycled on every kill
	# center messages
	center = UI.lbl("", 40, UI.ACCENT, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-500, -230)
	center.size = Vector2(1000, 60)
	center.add_theme_constant_override("outline_size", 8)
	center.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	root.add_child(center)
	center2 = UI.lbl("", 26, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	center2.set_anchors_preset(Control.PRESET_CENTER)
	center2.position = Vector2(-400, 370)
	center2.size = Vector2(800, 40)
	center2.add_theme_constant_override("outline_size", 6)
	center2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	root.add_child(center2)
	_build_medals()
	count_lbl = UI.lbl("", 140, Color.WHITE, "Teko", HORIZONTAL_ALIGNMENT_CENTER)
	count_lbl.set_anchors_preset(Control.PRESET_CENTER)
	count_lbl.position = Vector2(-200, -160)
	count_lbl.size = Vector2(400, 200)
	root.add_child(count_lbl)
	# death panel
	death_panel = ColorRect.new()
	(death_panel as ColorRect).color = Color(0.25, 0, 0, 0.35)
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_panel.visible = false
	root.add_child(death_panel)
	var dv := UI.vbox(6)
	dv.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dv.position = Vector2(-400, -130)
	dv.custom_minimum_size = Vector2(800, 0)
	death_panel.add_child(dv)
	death_lbl = UI.lbl("", 34, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	dv.add_child(death_lbl)
	death_timer_lbl = UI.lbl("", 17, Color(1, 1, 1, 0.75), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	dv.add_child(death_timer_lbl)
	on_weapon_changed()
	call_deferred("chat_help")

func show_countdown() -> void:
	pass

# ---------------------------------------------------------------- spectate panel
var spec_panel: SpecPanel
var hp_panel: Control
func show_spectate(on: bool) -> void:
	if on:
		if spec_panel == null or not is_instance_valid(spec_panel):
			spec_panel = SpecPanel.new()
			spec_panel.hud = self
			spec_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
			spec_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(spec_panel)
		spec_panel.visible = true
		if death_panel: death_panel.visible = false
	elif spec_panel and is_instance_valid(spec_panel):
		spec_panel.visible = false
	# your own health / ammo / red overlays make no sense while watching someone else
	for n in [hp_panel, ammo_panel, vignette, blood_ov]:
		if n and is_instance_valid(n):
			(n as CanvasItem).visible = not on

class SpecPanel extends Control:
	## bottom-centre card while watching a teammate: name, health, weapon, how to switch
	var hud
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var m = hud.match_node
		if m == null or not m.spectating or m.spec_target == null or not is_instance_valid(m.spec_target):
			return
		var n = m.spec_target
		var f: Font = UI.font("Rajdhani-Bold")
		var fr: Font = UI.font("RussoOne-Regular")
		var tc: Color = GS.TEAM_COLORS.get(m.player.team, UI.ACCENT)
		var c := size / 2.0
		var r := Rect2(c.x - 230, size.y - 150, 460, 86)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.025, 0.035, 0.88)
		sb.set_corner_radius_all(12)
		sb.border_color = Color(tc.r, tc.g, tc.b, 0.6)
		sb.set_border_width_all(1)
		draw_style_box(sb, r)
		draw_rect(Rect2(r.position.x, r.position.y + 10, 4, r.size.y - 20), tc)
		draw_string(f, r.position + Vector2(18, 22), "◉ İZLENİYOR", HORIZONTAL_ALIGNMENT_LEFT, 200, 14, Color(1, 1, 1, 0.55))
		draw_string(fr, r.position + Vector2(18, 50), str(n.display_name) if "display_name" in n else "?", HORIZONTAL_ALIGNMENT_LEFT, 260, 24, Color.WHITE)
		var wn: String = str(GS.WEAPONS.get(n.wid, {}).get("name", "")) if "wid" in n else ""
		draw_string(f, r.position + Vector2(18, 74), wn, HORIZONTAL_ALIGNMENT_LEFT, 200, 15, UI.ACCENT2)
		if "health" in n and not ("puppet" in n and n.puppet):
			var hp := clampf(float(n.health) / 100.0, 0.0, 1.0)
			var br := Rect2(r.end.x - 190, r.position.y + 40, 170, 10)
			draw_rect(br, Color(1, 1, 1, 0.1))
			draw_rect(Rect2(br.position, Vector2(br.size.x * hp, br.size.y)), Color("2fd67a").lerp(Color("ff3d3d"), 1.0 - hp))
			draw_string(f, Vector2(br.position.x, br.position.y - 6), "CAN %d" % int(n.health), HORIZONTAL_ALIGNMENT_LEFT, 170, 14, Color(1, 1, 1, 0.7))
		draw_string(f, Vector2(r.position.x, r.end.y + 22), "◀ SAĞ TIK      SOL TIK / BOŞLUK ▶      takım arkadaşı değiştir", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color(1, 1, 1, 0.5))


# ---------------------------------------------------------------- chat / voice help
var _vnote: Label
var _chat_hint: Label
func voice_notice(t: String) -> void:
	if root == null:
		return
	if _vnote == null or not is_instance_valid(_vnote):
		_vnote = UI.lbl("", 19, Color("ffd27a"), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
		_vnote.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_vnote.offset_left = -500; _vnote.offset_right = 500; _vnote.offset_top = -250; _vnote.offset_bottom = -220
		_vnote.add_theme_constant_override("outline_size", 6)
		_vnote.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_vnote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_vnote)
	_vnote.text = "◉ " + t
	_vnote.modulate.a = 1.0
	var tw := _vnote.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_vnote, "modulate:a", 0.0, 0.8)

## small permanent key hint above the chat input + a "how it works" card for the first seconds of a match
func chat_help() -> void:
	if root == null:
		return
	var online: bool = match_node != null and match_node.net
	_chat_hint = UI.lbl("[Enter] Sohbet   [Y] Takım" + ("   [V] Konuş (basılı tut)" if online else ""), 15, Color(1, 1, 1, 0.55), "Rajdhani-Bold")
	_chat_hint.anchor_left = 0; _chat_hint.anchor_top = 1; _chat_hint.anchor_bottom = 1
	_chat_hint.offset_left = 26; _chat_hint.offset_top = -162; _chat_hint.offset_bottom = -144
	_chat_hint.add_theme_constant_override("outline_size", 4)
	_chat_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_chat_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_hint)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.sb(Color(0.02, 0.025, 0.035, 0.86), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.6), 1, 8, 14))
	card.anchor_left = 1; card.anchor_right = 1; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -380; card.offset_right = -24; card.offset_top = -40
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(UI.lbl("◆ SOHBET NASIL KULLANILIR", 18, UI.ACCENT, "Rajdhani-Bold"))
	var rows := [["ENTER / T", "Herkese yazılı mesaj"], ["Y", "Sadece takımına yaz"], ["ESC", "Yazmayı iptal et"]]
	if online:
		rows.append(["V (basılı tut)", "Sesli konuş — bırakınca susar"])
	for r in rows:
		var h := UI.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var k := PanelContainer.new()
		k.add_theme_stylebox_override("panel", UI.sb(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.3), 1, 4, 4))
		k.custom_minimum_size = Vector2(130, 0)
		k.add_child(UI.lbl(r[0], 15, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		h.add_child(k)
		h.add_child(UI.lbl(r[1], 16, UI.TEXT, "Rajdhani-SemiBold"))
	if online:
		var mic_ok := AudioServer.get_input_device_list().size() > 0
		v.add_child(UI.lbl("Mikrofon: " + ("hazır ✔" if mic_ok else "bulunamadı ✖"), 14, UI.GREEN if mic_ok else UI.RED, "Rajdhani-Bold"))
	else:
		v.add_child(UI.lbl("Sesli sohbet çevrimiçi odalarda açılır.", 14, UI.DIM, "Rajdhani-SemiBold"))
	var tw := card.create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(card, "modulate:a", 0.0, 1.0)
	tw.tween_callback(card.queue_free)

# ---------------------------------------------------------------- per frame
var voice_lbl: Label
func _voice_ui() -> void:
	if voice_lbl == null:
		voice_lbl = UI.lbl("", 18, Color(0.6, 1.0, 0.7), "Rajdhani-Bold")
		voice_lbl.anchor_left = 0; voice_lbl.anchor_top = 1; voice_lbl.anchor_bottom = 1
		voice_lbl.offset_left = 24; voice_lbl.offset_top = -480; voice_lbl.offset_bottom = -455
		voice_lbl.add_theme_constant_override("outline_size", 5)
		voice_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		voice_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(voice_lbl)
	var names: Array = []
	if Voice.is_sending():
		names.append("SEN")
	for id in Voice.speaking.keys():
		names.append(str(Net.members.get(id, {}).get("name", "?")))
	voice_lbl.text = ("◉ KONUŞUYOR: " + ", ".join(names)) if names.size() > 0 else ""
	if Voice.is_sending():
		voice_lbl.text += "   " + "▮".repeat(int(clampf(Voice.level * 40.0, 0, 10))) + "▯".repeat(10 - int(clampf(Voice.level * 40.0, 0, 10)))

func _process(delta: float) -> void:
	if match_node and match_node.net and root:
		_voice_ui()
	if player == null or match_node == null:
		return
	var m = match_node
	# countdown
	count_lbl.text = str(int(ceil(m.countdown))) if m.countdown > 0 else ""
	# health
	hp_lbl.text = str(int(ceil(player.health)))
	hp_bar.value = player.health
	ar_bar.value = player.armor
	hp_lbl.add_theme_color_override("font_color", UI.RED if player.health < 30 else Color.WHITE)
	var low: float = clamp((45.0 - player.health) / 45.0, 0.0, 1.0) if player.alive else 0.6
	vignette.modulate.a = lerp(vignette.modulate.a, low, min(delta * 4.0, 1.0))
	if blood_ov:
		var floor_a: float = clamp((60.0 - player.health) / 60.0, 0.0, 1.0) * 0.55 if player.alive else 0.8
		blood_a = max(blood_a - delta * 0.45, floor_a)
		blood_ov.modulate.a = blood_a
	if player.alive and player.health < 30:
		hb_t -= delta
		if hb_t <= 0:
			hb_t = 1.1
			SFX.play("heartbeat", -6)
	# ammo
	if player.cur != "" and player.ammo.has(player.cur) and not player.wdata.get("throwable", false) and not player.wdata.get("melee", false):
		var a: Array = player.ammo[player.cur]
		ammo_lbl.text = "%02d" % a[0]
		reserve_lbl.text = "/ %03d" % a[1]
		ammo_lbl.add_theme_color_override("font_color", UI.RED if a[0] <= int(player.wdata.get("mag_max", 30)) * 0.25 else Color.WHITE)
		ammo_lbl.visible = true; reserve_lbl.visible = true
	else:
		ammo_lbl.visible = player.wdata.get("throwable", false)
		ammo_lbl.add_theme_color_override("font_color", Color.WHITE)
		ammo_lbl.text = ("x%d" % (player.smokes if player.cur == "smoke" else player.grenades)) if player.wdata.get("throwable", false) else ""
		reserve_lbl.visible = false
	nade_lbl.text = ("💣 x%d   ☁ x%d" % [player.grenades, player.smokes]) if player.slots.has("bomba") else ""
	reload_bar.visible = player.reload_t > 0 and not player.wdata.get("shell_reload", false)
	if reload_bar.visible:
		reload_bar.value = 1.0 - player.reload_t / max(player.reload_total, 0.01)
	# scope
	scope_ov.visible = player.wdata.get("scope", false) and player.ads_k > 0.92 and player.alive
	if scope_ov.visible and scope_rect:
		var sz := scope_rect.size
		(scope_rect.material as ShaderMaterial).set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	xhair.visible = player.alive and not scope_ov.visible and not (player.ads_k > 0.6 and not player.wdata.get("melee", false))
	xhair.queue_redraw()
	hit_t = max(hit_t - delta, 0.0)
	hit_ctl.queue_redraw()
	for d in dmg_list.duplicate():
		d["t"] -= delta
		if d["t"] <= 0:
			dmg_list.erase(d)
	dmg_ctl.queue_redraw()
	if minimap:
		minimap.queue_redraw()
	# timer + scores
	_update_scores()
	# target name
	target_t -= delta
	if target_t <= 0 and player.alive:
		target_t = 0.1
		var q := PhysicsRayQueryParameters3D.create(player.cam.global_position, player.cam.global_position - player.cam.global_transform.basis.z * 120.0, 1 | 2)
		q.exclude = [player.get_rid()]
		var r: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty() and r["collider"].has_method("take_damage") and r["collider"].alive:
			var c = r["collider"]
			target_lbl.text = c.display_name
			target_lbl.add_theme_color_override("font_color", GS.TEAM_COLORS[c.team] if m.teams and c.team == player.team else UI.RED)
		else:
			target_lbl.text = ""
	# death
	if death_panel.visible:
		death_t -= delta
		death_timer_lbl.text = ("TUR SONUNU BEKLE  •  BİRAZDAN TAKIM ARKADAŞINI İZLEYECEKSİN" if match_node.sab else "YENİDEN DOĞUYORSUN  %.1f" % max(death_t, 0.0))
		if _death_bar and is_instance_valid(_death_bar):
			_death_bar.value = 3.5 - max(death_t, 0.0)
	# weapon menu (B)
	if Input.is_action_just_pressed("buy_menu") and not m.ended and not m.paused:
		toggle_buy(not buy_open)
	# scoreboard (Tab)
	var show_board: bool = (Input.is_action_pressed("scoreboard") or force_board) and not m.ended
	if show_board:
		board_t -= delta
		if board == null or board_t <= 0:
			board_t = 0.6
			_build_board()
	elif board:
		board.queue_free()
		board = null

func _update_scores() -> void:
	if score_bar == null:
		score_bar = ScoreBar.new()
		score_bar.hud = self
		score_bar.custom_minimum_size = Vector2(560, 74)
		score_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_box.add_child(score_bar)
	score_bar.queue_redraw()

# ---------------------------------------------------------------- events
func on_weapon_changed() -> void:
	if player == null or wname_lbl == null:
		return
	var id: String = player.cur
	if id == "":
		return
	var lvl := GS.wlvl(id)
	wname_lbl.text = GS.WEAPONS[id]["name"] + (" [+%d]" % lvl if lvl > 0 else "")

func on_fire() -> void:
	pass

func on_respawn() -> void:
	death_panel.visible = false
	center2.text = ""

func hitmarker(head: bool, kill: bool, amount: float, _pos: Vector3) -> void:
	hit_t = 0.25 if not kill else 0.45
	hit_head = head
	hit_kill = kill

func on_damaged(from_pos: Vector3, amount: float) -> void:
	if GS.settings.get("blood", true):
		blood_a = clamp(blood_a + amount / 55.0, 0.0, 0.95)
	var to = from_pos - player.global_position
	var ang := atan2(to.x, to.z)
	dmg_list.append({"a": ang, "t": 1.2, "amt": amount})

func ping_minimap(n) -> void:
	pings[n] = 2.0

func kill_feed(killer: String, victim: String, wid: String, head: bool, kt: String, vt: String, by_player: bool, player_died: bool, lvl: int = 0) -> void:
	var __t := Time.get_ticks_usec()
	_sp_kill_feed(killer, victim, wid, head, kt, vt, by_player, player_died, lvl)
	var __d := Time.get_ticks_usec() - __t
	if __d > 3000: print("SPIKE hud.gd.kill_feed ", __d / 1000.0, "ms")

func lvl_badge(lvl: int, fs: int = 15) -> Control:
	return UI.lvl_badge(lvl, fs)

## kill feed rows are built once and recycled (creating panels/labels per kill cost 6-11 ms = a hitch on every kill)
var _kf_rows: Array = []
var _kf_sb := {}
func _kf_style(kind: String) -> StyleBoxFlat:
	if not _kf_sb.has(kind):
		match kind:
			# CS2: dark translucent strips; your own kills get a red outline, your death a red fill
			"me": _kf_sb[kind] = UI.sb(Color(0.0, 0.0, 0.0, 0.62), Color(0.88, 0.1, 0.12), 2, 3, 0)
			"died": _kf_sb[kind] = UI.sb(Color(0.55, 0.04, 0.05, 0.72), Color(0, 0, 0, 0), 0, 3, 0)
			_: _kf_sb[kind] = UI.sb(Color(0.0, 0.0, 0.0, 0.5), Color(0, 0, 0, 0), 0, 3, 0)
		_kf_sb[kind].content_margin_left = 12; _kf_sb[kind].content_margin_right = 12
		_kf_sb[kind].content_margin_top = 3; _kf_sb[kind].content_margin_bottom = 3
	return _kf_sb[kind]

func _kf_new_row() -> Dictionary:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var kl := UI.lbl("", 19, Color.WHITE, "Rajdhani-Bold")
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var wl := UI.lbl("", 17, UI.DIM, "Rajdhani-SemiBold")
	var bh := HBoxContainer.new()
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hr := TextureRect.new()
	hr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hr.custom_minimum_size = Vector2(24, 24)
	hr.modulate = Color(1, 1, 1, 0.95)
	var vl := UI.lbl("", 19, Color.WHITE, "Rajdhani-Bold")
	for c in [kl, tr, wl, bh, hr, vl]:
		h.add_child(c)
	p.visible = false
	feed.add_child(p)
	return {"p": p, "kl": kl, "tr": tr, "wl": wl, "bh": bh, "hr": hr, "vl": vl, "badge": null, "blvl": -1, "tw": null}

func _sp_kill_feed(killer: String, victim: String, wid: String, head: bool, kt: String, vt: String, by_player: bool, player_died: bool, lvl: int = 0) -> void:
	if not GS.settings.get("kill_feed", true):
		return
	if _kf_rows.is_empty():
		for i in 6:
			_kf_rows.append(_kf_new_row())
	# reuse the oldest row and move it to the bottom
	var r: Dictionary = _kf_rows.pop_front()
	_kf_rows.append(r)
	var p: PanelContainer = r["p"]
	feed.move_child(p, feed.get_child_count() - 1)
	if r["tw"] and (r["tw"] as Tween).is_valid():
		(r["tw"] as Tween).kill()
	p.add_theme_stylebox_override("panel", _kf_style("me" if by_player else ("died" if player_died else "n")))
	# soft CS2 side colours (pale blue / pale gold) instead of saturated team colours
	var kc: Color = GS.TEAM_COLORS.get(kt, Color("eed58f")).lerp(Color.WHITE, 0.45) if kt != "" else Color("eed58f")
	var vc: Color = GS.TEAM_COLORS.get(vt, Color("eed58f")).lerp(Color.WHITE, 0.45) if vt != "" else Color("eed58f")
	(r["kl"] as Label).text = killer
	(r["kl"] as Label).add_theme_color_override("font_color", kc)
	(r["vl"] as Label).text = victim
	(r["vl"] as Label).add_theme_color_override("font_color", vc)
	var icon := _kf_icon(wid)
	var tr: TextureRect = r["tr"]
	var wl: Label = r["wl"]
	if icon:
		tr.texture = icon
		var ih := 24.0
		tr.custom_minimum_size = Vector2(min(ih * icon.get_width() / max(icon.get_height(), 1), 104.0), ih)
		tr.modulate = Color(1, 1, 1, 0.95) if lvl <= 0 else Color(1, 1, 1).lerp(GS.lvl_color(lvl), 0.35)
		tr.visible = true
		wl.visible = false
	else:
		tr.visible = false
		wl.visible = true
		wl.text = "[" + (str(GS.WEAPONS[wid]["name"]) if GS.WEAPONS.has(wid) else "☠") + "]"
	# upgrade badge: only rebuilt when the level shown in this row changes
	var bh: HBoxContainer = r["bh"]
	if lvl != int(r["blvl"]):
		if r["badge"] and is_instance_valid(r["badge"]):
			(r["badge"] as Node).queue_free()
		r["badge"] = lvl_badge(lvl, 15) if lvl > 0 else null
		if r["badge"]:
			bh.add_child(r["badge"])
		r["blvl"] = lvl
	bh.visible = lvl > 0
	var hr: TextureRect = r["hr"]
	if head:
		hr.texture = _kf_icon("_head")
	hr.visible = head and hr.texture != null
	p.modulate.a = 1.0
	p.visible = true
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): p.visible = false)
	r["tw"] = tw

var insp_card: PanelContainer
## F-inspect card: weapon, skin, level (slides in bottom-right)
func inspect_card(wid: String) -> void:
	if not GS.WEAPONS.has(wid) or root == null:
		return
	if insp_card and is_instance_valid(insp_card):
		insp_card.queue_free()
	var sk: String = GS.wskin(wid)
	var rar: int = int(GS.SKINS.get(sk, {}).get("rarity", 0))
	var rc: Color = [Color(0.75, 0.8, 0.88), Color(0.35, 0.65, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.78, 0.25)][clamp(rar, 0, 3)]
	insp_card = UI.panel(Color(0.03, 0.04, 0.06, 0.78), rc, 10, 2)
	var v := UI.vbox(2)
	insp_card.add_child(v)
	var top := UI.hbox(10)
	v.add_child(top)
	var ic := _kf_icon(wid)
	if ic:
		var tr := TextureRect.new()
		tr.texture = ic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(110, 36)
		tr.modulate = rc
		top.add_child(tr)
	var tv := UI.vbox(0)
	top.add_child(tv)
	tv.add_child(UI.lbl(str(GS.WEAPONS[wid]["name"]).to_upper(), 26, Color.WHITE, "Rajdhani-Bold"))
	tv.add_child(UI.lbl(str(GS.SKINS.get(sk, {}).get("name", sk)).to_upper(), 16, rc, "Rajdhani-SemiBold"))
	var lv: int = GS.wlvl(wid)
	if lv > 0:
		v.add_child(UI.lbl("★".repeat(min(lv, 10)) + "  SEVİYE %d" % lv, 15, UI.GOLD, "Rajdhani-Bold"))
	var stw: Dictionary = GS.stats_for(wid)
	v.add_child(UI.lbl("HASAR %d   ·   ŞARJÖR %d   ·   %s" % [int(stw.get("dmg", 0)), int(stw.get("mag", 0)), str(GS.WEAPONS[wid].get("cls", ""))], 14, UI.DIM, "Rajdhani-SemiBold"))
	root.add_child(insp_card)
	insp_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	insp_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	insp_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	insp_card.offset_top -= 120; insp_card.offset_bottom -= 120     # above the ammo panel
	_ignore_mouse(insp_card)
	insp_card.modulate.a = 0.0
	var tw := insp_card.create_tween()
	tw.tween_property(insp_card, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.4)
	tw.tween_property(insp_card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(insp_card.queue_free)

var _kf_cache := {}
func _kf_icon(wid: String) -> Texture2D:
	if _kf_cache.has(wid):
		return _kf_cache[wid]
	var base: String = wid if wid.begins_with("_") else GS.weapon_base(wid)
	var p := "res://assets/ui/kf/%s.png" % base
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_kf_cache[wid] = t
	return t

# ---------------------------------------------------------------- in-match chat
var typing := false
var chat_box: VBoxContainer
var chat_in: LineEdit
var chat_team := false

func _ensure_chat() -> void:
	if chat_box and is_instance_valid(chat_box):
		return
	chat_box = UI.vbox(2)
	chat_box.anchor_left = 0; chat_box.anchor_top = 1; chat_box.anchor_bottom = 1
	chat_box.offset_left = 24; chat_box.offset_top = -450; chat_box.offset_bottom = -206; chat_box.offset_right = 560
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_box)
	chat_in = LineEdit.new()
	chat_in.anchor_left = 0; chat_in.anchor_top = 1; chat_in.anchor_bottom = 1
	chat_in.offset_left = 24; chat_in.offset_right = 560; chat_in.offset_top = -200; chat_in.offset_bottom = -166
	chat_in.max_length = 120
	chat_in.visible = false
	chat_in.add_theme_stylebox_override("normal", UI.sb(Color(0, 0, 0, 0.75), UI.ACCENT, 1, 4, 8))
	chat_in.text_submitted.connect(_chat_send)
	chat_in.gui_input.connect(func(ev): if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE: _chat_close())
	root.add_child(chat_in)

func open_chat(team: bool) -> void:
	_ensure_chat()
	chat_team = team
	typing = true
	chat_in.placeholder_text = "TAKIM'a yaz... (Enter gönder, Esc iptal)" if team else "HERKESE yaz... (Enter gönder, Esc iptal)"
	chat_in.visible = true
	chat_in.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat_in.grab_focus()
	for c in chat_box.get_children():
		(c as CanvasItem).modulate.a = 1.0

func _chat_close() -> void:
	typing = false
	if chat_in:
		chat_in.visible = false
		chat_in.release_focus()
	if match_node and not match_node.paused and not match_node.ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _chat_send(t: String) -> void:
	t = t.strip_edges()
	_chat_close()
	if t == "":
		return
	var me: String = Online.username if Online.is_logged_in() else str(GS.profile.get("name", "Oyuncu"))
	var myteam: String = player.team if player and "team" in player else ""
	if match_node and match_node.net:
		Net.send({"t": "chat", "n": me, "m": t, "team": myteam if chat_team else ""})
	chat_line(me, t, chat_team, GS.TEAM_COLORS.get(myteam, UI.ACCENT2))
	if match_node and not match_node.net and "combatants" in match_node and randf() < 0.7:
		_bot_reply(t, myteam)

const BOT_LINES := ["eyvallah", "tamamdır kanka", "gg", "B'ye geçiyorum", "ön tarafta 2 kişi var", "dikkat sağdan geliyorlar",
	"iyi oyun", "haha", "yardım lazım!", "bomba bende", "toplanalım", "nice"]
func _bot_reply(t: String, myteam: String) -> void:
	var pool: Array = []
	for c in match_node.combatants:
		if c["node"] != player and c.get("team", "") == myteam:
			pool.append(c)
	if pool.is_empty():
		return
	var c: Dictionary = pool[randi() % pool.size()]
	await get_tree().create_timer(randf_range(1.0, 2.6)).timeout
	if not is_instance_valid(self):
		return
	var line: String = BOT_LINES[randi() % BOT_LINES.size()]
	if t.to_lower().contains("gg") or t.to_lower().contains("iyi oyun"): line = "gg wp"
	elif t.to_lower().begins_with("selam") or t.to_lower().strip_edges() == "sa" or t.to_lower().begins_with("sa "): line = "as kardeşim"
	chat_line(str(c["name"]), line, true, GS.TEAM_COLORS.get(myteam, UI.ACCENT2))

func chat_line(who: String, t: String, team: bool, col: Color) -> void:
	_ensure_chat()
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(530, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.text = "%s[color=#%s][b]%s:[/b][/color] %s" % ["[color=#7fd1ff][TAKIM][/color] " if team else "", col.to_html(false), who, t.replace("[", "(")]
	chat_box.add_child(l)
	while chat_box.get_child_count() > 7:
		chat_box.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	SFX.play("ui_click", -10)

var kb: Control
## modern kill banner under the crosshair: slanted plate, weapon silhouette, points, streak pips
func _kill_banner(head: bool, wid: String, streak: int) -> void:
	## CS2-style kill feedback: a row of skull cards (kills this life) above the bottom HUD, the newest one
	## slams in with a flash; a slim plate above it names the kill type, weapon and score
	if kb and is_instance_valid(kb):
		kb.queue_free()
	var col: Color = Color(1.0, 0.82, 0.35) if head else Color(1.0, 0.32, 0.26)
	var n := clampi(streak, 1, 8)
	var cw := 46.0
	var gap := 8.0
	var w := n * cw + (n - 1) * gap
	kb = Control.new()
	kb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	kb.size = Vector2(maxf(w, 420.0), 128)
	kb.position = Vector2(-kb.size.x * 0.5, -186)
	kb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kb)
	# plate: "KAFADAN VURUŞ  •  AK-47  •  +150"
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 2; sb.content_margin_bottom = 2
	sb.border_width_bottom = 2; sb.border_color = col
	sb.corner_radius_top_left = 3; sb.corner_radius_top_right = 3
	plate.add_theme_stylebox_override("panel", sb)
	var ph := UI.hbox(10)
	plate.add_child(ph)
	var hs := _kf_icon("_head")
	if head and hs:
		var hi := TextureRect.new()
		hi.texture = hs; hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hi.custom_minimum_size = Vector2(24, 24); hi.modulate = col
		ph.add_child(hi)
	ph.add_child(UI.lbl("KAFADAN VURUŞ" if head else "ETKİSİZ HALE GETİRİLDİ", 19, col, "Rajdhani-Bold"))
	var wi := _kf_icon(wid)
	if wi:
		var wt := TextureRect.new()
		wt.texture = wi; wt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; wt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wt.custom_minimum_size = Vector2(64, 22); wt.modulate = Color(1, 1, 1, 0.85)
		ph.add_child(wt)
	ph.add_child(UI.lbl("+150" if head else "+100", 19, Color(1, 1, 1, 0.9), "Rajdhani-Bold"))
	kb.add_child(plate)
	plate.position = Vector2(0, 0)
	plate.resized.connect(func(): plate.position.x = (kb.size.x - plate.size.x) * 0.5)
	# skull cards
	var x0 := (kb.size.x - w) * 0.5
	var sk := _skull_tex()
	for i in n:
		var c := Panel.new()
		var cs := StyleBoxFlat.new()
		var last := i == n - 1
		cs.bg_color = Color(col.r * 0.25, col.g * 0.12, col.b * 0.1, 0.85) if last else Color(0, 0, 0, 0.55)
		cs.border_width_bottom = 3; cs.border_color = col if last else Color(1, 1, 1, 0.35)
		cs.set_corner_radius_all(3)
		c.add_theme_stylebox_override("panel", cs)
		c.position = Vector2(x0 + i * (cw + gap), 44); c.size = Vector2(cw, 58)
		c.pivot_offset = c.size * 0.5
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kb.add_child(c)
		if sk:
			var t := TextureRect.new()
			t.texture = sk; t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.set_anchors_preset(Control.PRESET_FULL_RECT); t.offset_left = 6; t.offset_right = -6; t.offset_top = 8; t.offset_bottom = -8
			t.modulate = col if last else Color(1, 1, 1, 0.75)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(t)
		if last:
			c.scale = Vector2(1.9, 1.9)
			c.modulate = Color(3, 3, 3, 0)
			var t2 := c.create_tween().set_parallel(true)
			t2.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t2.tween_property(c, "modulate", Color.WHITE, 0.25)
			var fl := ColorRect.new()
			fl.color = Color(col.r, col.g, col.b, 0.55)
			fl.size = c.size; fl.position = c.position; fl.pivot_offset = c.size * 0.5
			fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			kb.add_child(fl)
			var t3 := fl.create_tween().set_parallel(true)
			t3.tween_property(fl, "scale", Vector2(2.6, 2.0), 0.35).set_ease(Tween.EASE_OUT)
			t3.tween_property(fl, "color:a", 0.0, 0.35)
			t3.chain().tween_callback(fl.queue_free)
	_ignore_mouse(kb)
	plate.modulate.a = 0.0
	var tw := kb.create_tween()
	tw.tween_property(plate, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(kb, "modulate:a", 0.0, 0.4)
	tw.tween_callback(kb.queue_free)

var _skull: Texture2D
func _skull_tex() -> Texture2D:
	if _skull == null:
		for pth in ["res://assets/ui/icons/skull.png", "res://assets/ui/kf/_head.png"]:
			if ResourceLoader.exists(pth):
				_skull = load(pth)
				break
	return _skull

func kill_confirm(head: bool, big: String, multi: int = 1, wid: String = "", streak: int = 1) -> void:
	center2.text = ""
	_kill_banner(head, wid, streak)
	# pick medal
	var w: Dictionary = GS.WEAPONS.get(wid, {})
	var key := "kill"
	var title := "ÖLDÜRME"
	var col := Color(0.92, 0.94, 1.0)
	if w.get("melee", false):
		key = "knife"; title = "BIÇAKLADIN!"; col = Color(1, 0.75, 0.7)
	elif w.get("throwable", false) or wid == "frag":
		key = "grenade"; title = "BOMBA!"; col = Color(1, 0.85, 0.4)
	if head:
		key = "head"; title = "KAFADAN!"; col = Color(1, 0.84, 0.35)
	match multi:
		2: key = "double"; title = "ÇİFTE ÖLDÜRME!"; col = Color(1, 0.45, 0.35)
		3: key = "triple"; title = "ÜÇLÜ ÖLDÜRME!"; col = Color(1, 0.82, 0.3)
		4: key = "quad"; title = "DÖRTLÜ ÖLDÜRME!"; col = Color(0.8, 0.6, 1.0)
	if multi >= 5:
		key = "penta"; title = "KATLİAM!"; col = Color(0.5, 0.95, 1.0)
	if multi < 2 and big != "" and not head:
		key = "streak"; col = Color(1, 0.6, 0.35)
	var sub := ""
	if big != "" and multi < 2:
		sub = big
	elif head and multi >= 2:
		sub = "KAFADAN!"
	_show_medal(key, title, sub, col, multi)
	if multi >= 2:
		SFX.play("multikill", -3, 1.0 + (multi - 2) * 0.06)
	# AI announcer (not for ordinary single kills)
	if key != "kill" and bool(GS.settings.get("announcer", true)):
		_announce("ann_" + key)

var ann_player: AudioStreamPlayer
func _announce(n: String) -> void:
	if ann_player == null:
		ann_player = AudioStreamPlayer.new()
		ann_player.bus = "SFX"
		add_child(ann_player)
	var st := SFX.get_stream(n)
	if st == null:
		return
	ann_player.stream = st     # a newer line interrupts the previous one (double -> triple)
	ann_player.volume_db = -1.0
	ann_player.play()

func _build_medals() -> void:
	for k in ["kill", "head", "double", "triple", "quad", "penta", "knife", "grenade", "streak"]:
		var pth := "res://assets/ui/medals/%s.png" % k
		if ResourceLoader.exists(pth):
			medals[k] = load(pth)
	# full screen blood overlay
	blood_ov = TextureRect.new()
	if ResourceLoader.exists("res://assets/fx/blood_screen.png"):
		blood_ov.texture = load("res://assets/fx/blood_screen.png")
	blood_ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blood_ov.stretch_mode = TextureRect.STRETCH_SCALE
	blood_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	blood_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blood_ov.modulate.a = 0.0
	root.add_child(blood_ov)
	root.move_child(blood_ov, vignette.get_index() + 1)
	medal_box = Control.new()
	medal_box.set_anchors_preset(Control.PRESET_CENTER)
	medal_box.position = Vector2(-200, 70)
	medal_box.size = Vector2(400, 300)
	medal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.pivot_offset = Vector2(200, 80)
	medal_box.modulate.a = 0.0
	root.add_child(medal_box)
	medal_ring = MedalRing.new()
	medal_ring.position = Vector2(200, 80)
	medal_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.add_child(medal_ring)
	medal_tex = TextureRect.new()
	medal_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medal_tex.size = Vector2(170, 170)
	medal_tex.position = Vector2(115, -5)
	medal_tex.pivot_offset = Vector2(85, 85)
	medal_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.add_child(medal_tex)
	medal_title = UI.lbl("", 38, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	medal_title.position = Vector2(0, 168); medal_title.size = Vector2(400, 46)
	medal_title.add_theme_constant_override("outline_size", 10)
	medal_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	medal_title.pivot_offset = Vector2(200, 23)
	medal_box.add_child(medal_title)
	medal_sub = UI.lbl("", 22, UI.GOLD, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	medal_sub.position = Vector2(0, 212); medal_sub.size = Vector2(400, 28)
	medal_sub.add_theme_constant_override("outline_size", 6)
	medal_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	medal_box.add_child(medal_sub)
	medal_skulls = HBoxContainer.new()
	medal_skulls.alignment = BoxContainer.ALIGNMENT_CENTER
	medal_skulls.add_theme_constant_override("separation", 4)
	medal_skulls.position = Vector2(0, 244); medal_skulls.size = Vector2(400, 40)
	medal_skulls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.add_child(medal_skulls)

func _show_medal(key: String, title: String, sub: String, col: Color, multi: int) -> void:
	if medal_box == null:
		return
	if medal_tw and medal_tw.is_valid():
		medal_tw.kill()
	medal_tex.texture = medals.get(key, medals.get("kill"))
	medal_title.text = title
	medal_title.add_theme_color_override("font_color", col)
	medal_sub.text = sub
	UI.clear(medal_skulls)
	for i in clamp(multi, 1, 6):
		var t := TextureRect.new()
		t.texture = _skull_tex()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.custom_minimum_size = Vector2(34, 34)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.modulate = col if i == multi - 1 else Color(1, 1, 1, 0.75)
		medal_skulls.add_child(t)
	medal_skulls.visible = multi >= 2
	medal_ring.col = col
	medal_ring.t = 0.0
	medal_box.modulate.a = 1.0
	medal_tex.scale = Vector2(2.6, 2.6)
	medal_tex.modulate = Color(3, 3, 3, 0)
	medal_tex.rotation = deg_to_rad(-14)
	medal_title.scale = Vector2(1.8, 1.8)
	medal_title.modulate.a = 0.0
	medal_tw = medal_box.create_tween()
	medal_tw.set_parallel(true)
	medal_tw.tween_property(medal_tex, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	medal_tw.tween_property(medal_tex, "rotation", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	medal_tw.tween_property(medal_tex, "modulate", Color(1, 1, 1, 1), 0.32)
	medal_tw.tween_property(medal_ring, "t", 1.0, 0.55).set_delay(0.12)
	medal_tw.tween_property(medal_title, "scale", Vector2.ONE, 0.22).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	medal_tw.tween_property(medal_title, "modulate:a", 1.0, 0.15).set_delay(0.1)
	medal_tw.chain().tween_interval(1.5)
	medal_tw.chain().tween_property(medal_box, "modulate:a", 0.0, 0.45)

## e-sports round banner (v3.4): full-width stripe that slides in, team-coloured wedge, big title + sub line
var _rb: Control
func round_banner(title: String, sub: String, col: Color, score_a: int = -1, score_b: int = -1) -> void:
	if _rb and is_instance_valid(_rb):
		_rb.queue_free()
	var rb := Control.new()
	rb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rb.offset_top = 236; rb.offset_bottom = 348
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb.pivot_offset = Vector2(640, 56)
	root.add_child(rb)
	_rb = rb
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; uniform vec4 col : source_color; void fragment(){ float e = 1.0 - abs(UV.x - 0.5) * 2.0; float a = smoothstep(0.0, 0.55, e); float band = step(0.06, UV.y) * step(UV.y, 0.94); vec3 c = mix(vec3(0.02,0.024,0.034), col.rgb * 0.45, smoothstep(0.2, 1.0, e) * 0.6); float edge = (step(UV.y, 0.035) + step(0.965, UV.y)) * a; COLOR = vec4(mix(c, col.rgb, edge), max(a * 0.9 * band, edge)); }"
	gm.shader = sh
	gm.set_shader_parameter("col", col)
	bg.material = gm
	rb.add_child(bg)
	var v := UI.vbox(0)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb.add_child(v)
	var h := UI.hbox(22)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	if score_a >= 0:
		h.add_child(UI.lbl(str(score_a), 46, GS.TEAM_COLORS.get("a", Color.WHITE), "Teko"))
	var tl := UI.lbl(title, 40, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	tl.add_theme_constant_override("outline_size", 6)
	tl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	h.add_child(tl)
	if score_b >= 0:
		h.add_child(UI.lbl(str(score_b), 46, GS.TEAM_COLORS.get("b", Color.WHITE), "Teko"))
	if sub != "":
		v.add_child(UI.lbl(sub, 17, col.lightened(0.45), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	rb.modulate.a = 0.0
	rb.scale = Vector2(1.0, 0.2)
	var tw := rb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rb, "modulate:a", 1.0, 0.18)
	tw.tween_property(rb, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.4)
	tw.chain().tween_property(rb, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(rb.queue_free)

func center_msg(t: String, c: Color) -> void:
	center.text = t
	center.add_theme_color_override("font_color", c)
	center.modulate.a = 1.0
	center.scale = Vector2(1.3, 1.3)
	center.pivot_offset = center.size / 2
	var tw := center.create_tween()
	tw.tween_property(center, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(center, "modulate:a", 0.0, 0.5)

var _death_card: Control
var _death_bar: ProgressBar
## death card: one clean, centred card — who killed you, with what (+level), how hard, and what they have left
func show_death(killer: String, wid: String, head: bool, info: Dictionary = {}) -> void:
	death_panel.visible = true
	death_t = 3.5
	death_lbl.text = ""
	if _death_card and is_instance_valid(_death_card):
		_death_card.queue_free()
	var accent: Color = UI.GOLD if head else Color(1, 0.33, 0.28)
	var tc: Color = GS.TEAM_COLORS.get(str(info.get("team", "")), Color(1, 0.42, 0.35))
	var card := PanelContainer.new()
	var csb := UI.sb(Color(0.02, 0.022, 0.032, 0.92), Color(1, 1, 1, 0.08), 1, 14, 0)
	csb.shadow_color = Color(0, 0, 0, 0.5); csb.shadow_size = 24
	card.add_theme_stylebox_override("panel", csb)
	card.custom_minimum_size = Vector2(660, 0)
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_bottom = -150
	death_panel.add_child(card)
	_death_card = card
	var v := UI.vbox(0)
	card.add_child(v)
	# header strip
	var hs := PanelContainer.new()
	var hsb := UI.sb(Color(accent.r, accent.g, accent.b, 0.16), Color(0, 0, 0, 0), 0, 0, 0)
	hsb.corner_radius_top_left = 14; hsb.corner_radius_top_right = 14
	hsb.content_margin_left = 20; hsb.content_margin_right = 20; hsb.content_margin_top = 8; hsb.content_margin_bottom = 8
	hsb.border_width_bottom = 2; hsb.border_color = accent
	hs.add_theme_stylebox_override("panel", hsb)
	v.add_child(hs)
	var hh := UI.hbox(10)
	hs.add_child(hh)
	var skt := _skull_tex()
	if skt:
		var sk := TextureRect.new()
		sk.texture = skt; sk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; sk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sk.custom_minimum_size = Vector2(24, 24); sk.modulate = accent; sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(sk)
	hh.add_child(UI.lbl("ÖLDÜRÜLDÜN", 22, accent.lightened(0.15), "RussoOne-Regular"))
	hh.add_child(UI.spacer())
	if head:
		hh.add_child(_death_chip("KAFADAN", UI.GOLD))
	if info.get("self", false):
		hh.add_child(_death_chip("KENDİNİ", UI.DIM))
	# body
	var bm := MarginContainer.new()
	for k in ["left", "right"]:
		bm.add_theme_constant_override("margin_" + k, 20)
	bm.add_theme_constant_override("margin_top", 14); bm.add_theme_constant_override("margin_bottom", 14)
	v.add_child(bm)
	var bv := UI.vbox(14)
	bm.add_child(bv)
	var top := UI.hbox(14)
	bv.add_child(top)
	# avatar: the killer's agent portrait (v3.4) framed in team colour, rank emblem beside it
	var av := PanelContainer.new()
	var asb := UI.sb(Color(tc.r * 0.3, tc.g * 0.3, tc.b * 0.3, 1), tc, 2, 4, 0)
	av.add_theme_stylebox_override("panel", asb)
	av.custom_minimum_size = Vector2(84, 84)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tm := str(info.get("team", ""))
	var pool: Array = GS.team_chars(tm) if tm != "" else GS.CHARACTERS.keys()
	var cid: String = str(pool[abs(hash(killer)) % pool.size()]) if pool.size() > 0 else ""
	var ap := "res://assets/ui/agents/%s.jpg" % cid
	if cid != "" and ResourceLoader.exists(ap):
		var at := AtlasTexture.new()
		at.atlas = load(ap)
		var aw: float = at.atlas.get_width()
		at.region = Rect2(aw * 0.2, aw * 0.02, aw * 0.6, aw * 0.6)
		var pr := TextureRect.new()
		pr.texture = at; pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av.add_child(pr)
	else:
		var al := UI.lbl(killer.substr(0, 1).to_upper(), 28, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
		al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av.add_child(al)
	top.add_child(av)
	var rk := TextureRect.new()
	rk.texture = GS.rank_info((int(info.get("lvl", 1)) * 37) % 3000)["icon"]
	rk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; rk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rk.custom_minimum_size = Vector2(56, 56); rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(rk)
	var nv := UI.vbox(-2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	nv.add_child(UI.lbl("SENİ VURAN", 13, UI.DIM, "Rajdhani-Bold"))
	nv.add_child(UI.lbl(killer, 30, Color.WHITE, "RussoOne-Regular"))
	var tags := UI.hbox(6)
	nv.add_child(tags)
	tags.add_child(_death_chip("SEVİYE %d" % int(info.get("lvl", 1)), Color(0.6, 0.75, 1.0)))
	var tn: String = str(GS.TEAMS.get(str(info.get("team", "")), ""))
	if tn != "":
		tags.add_child(_death_chip(tn, tc))
	# weapon block (right)
	var wv := UI.vbox(2)
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(wv)
	var ic := TextureRect.new()
	ic.texture = _kf_icon(wid)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(170, 48)
	var wl: int = int(info.get("wlvl", 0))
	ic.modulate = Color.WHITE if wl <= 0 else Color(1, 1, 1).lerp(GS.lvl_color(wl), 0.4)
	wv.add_child(ic)
	var wh := UI.hbox(6)
	wh.alignment = BoxContainer.ALIGNMENT_END
	wv.add_child(wh)
	if wl > 0:
		wh.add_child(lvl_badge(wl, 14))
	wh.add_child(UI.lbl(str(GS.WEAPONS.get(wid, {}).get("name", "")).to_upper(), 17, Color.WHITE, "Rajdhani-Bold"))
	# v3.4: the killer's skin (rarity colour) and attachments
	var skn := str(info.get("skin", ""))
	if skn != "" and GS.SKINS.has(skn):
		var rr: int = clampi(int(GS.SKINS[skn].get("rarity", 0)), 0, GS.RARITY_COLORS.size() - 1)
		var sh2 := UI.hbox(6)
		sh2.alignment = BoxContainer.ALIGNMENT_END
		sh2.add_child(_death_chip(("KAPLAMA  •  " + str(GS.SKINS[skn]["name"])).to_upper(), GS.RARITY_COLORS[rr]))
		wv.add_child(sh2)
	var pts: Array = info.get("parts", []) if info.get("parts", []) is Array else []
	if not pts.is_empty():
		var ph := UI.hbox(4)
		ph.alignment = BoxContainer.ALIGNMENT_END
		for pid in pts:
			var pid_s := str(pid)
			if not GS.PARTS.has(pid_s):
				continue
			var pb := PanelContainer.new()
			pb.add_theme_stylebox_override("panel", UI.sb(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1, 5, 2))
			pb.tooltip_text = str(GS.PARTS[pid_s]["name"])
			var pth := "res://assets/ui/parts/%s.png" % pid_s
			if ResourceLoader.exists(pth):
				var pi := TextureRect.new()
				pi.texture = load(pth)
				pi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; pi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pi.custom_minimum_size = Vector2(30, 30)
				pb.add_child(pi)
			else:
				pb.add_child(UI.lbl(str(GS.PARTS[pid_s]["name"]).substr(0, 3).to_upper(), 11, UI.DIM, "Rajdhani-Bold"))
			ph.add_child(pb)
		var pl2 := UI.lbl("EKLENTİ", 11, UI.DIM, "Rajdhani-Bold")
		pl2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(pl2)
		ph.move_child(pl2, 0)
		wv.add_child(ph)
	# stat tiles
	var tiles := UI.hbox(10)
	bv.add_child(tiles)
	if info.has("hp"):
		var hp: float = float(info["hp"])
		var t1 := _death_tile("KALAN CANI")
		var hl := UI.lbl("%d" % int(ceil(hp)), 30, UI.GREEN if hp > 60 else (UI.GOLD if hp > 25 else UI.RED), "Teko")
		t1.add_child(hl)
		var hb := UI.bar(hp, 100, UI.GREEN if hp > 60 else (UI.GOLD if hp > 25 else UI.RED), 6)
		hb.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 3, 0))
		t1.add_child(hb)
		tiles.add_child(t1.get_parent())
	if info.has("dmg"):
		var t2 := _death_tile("SANA VERDİĞİ HASAR")
		t2.add_child(UI.lbl("%d" % int(info["dmg"]), 30, Color(1, 0.45, 0.4), "Teko"))
		t2.add_child(UI.lbl("%d isabet%s" % [int(info.get("hits", 0)), ("  •  %d kafa" % int(info["heads"])) if int(info.get("heads", 0)) > 0 else ""], 13, UI.DIM, "Rajdhani-Bold"))
		tiles.add_child(t2.get_parent())
	if info.has("my_dmg"):
		var t3 := _death_tile("SENİN VERDİĞİN")
		t3.add_child(UI.lbl("%d" % int(info["my_dmg"]), 30, Color(0.55, 0.85, 1.0), "Teko"))
		t3.add_child(UI.lbl("hasar", 13, UI.DIM, "Rajdhani-Bold"))
		tiles.add_child(t3.get_parent())
	if info.has("dist"):
		var t4 := _death_tile("MESAFE")
		t4.add_child(UI.lbl("%d m" % int(round(float(info["dist"]))), 30, Color.WHITE, "Teko"))
		t4.add_child(UI.lbl("uzak" if float(info["dist"]) > 30 else ("orta" if float(info["dist"]) > 10 else "yakın"), 13, UI.DIM, "Rajdhani-Bold"))
		tiles.add_child(t4.get_parent())
	# respawn bar
	var rv := UI.vbox(4)
	bv.add_child(rv)
	_death_bar = UI.bar(0, 3.5, accent, 5)
	_death_bar.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 3, 0))
	rv.add_child(_death_bar)
	_ignore_mouse(card)
	# entrance
	card.modulate.a = 0.0
	card.pivot_offset = Vector2(300, 100)
	card.scale = Vector2(0.94, 0.94)
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _death_chip(t: String, c: Color) -> Control:
	var p := PanelContainer.new()
	var sbx := UI.sb(Color(c.r, c.g, c.b, 0.15), Color(c.r, c.g, c.b, 0.55), 1, 5, 0)
	sbx.content_margin_left = 8; sbx.content_margin_right = 8; sbx.content_margin_top = 1; sbx.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sbx)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(UI.lbl(t, 13, c.lightened(0.25), "Rajdhani-Bold"))
	return p

func _death_tile(title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	var sbx := UI.sb(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.07), 1, 10, 10)
	p.add_theme_stylebox_override("panel", sbx)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(-2)
	p.add_child(v)
	v.add_child(UI.lbl(title, 12, UI.DIM, "Rajdhani-Bold"))
	return v

# ---------------------------------------------------------------- scoreboard
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

func _sbx(bg: Color, border: Color = Color(0, 0, 0, 0), rad: int = 8, pad: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(rad)
	if border.a > 0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = pad; sb.content_margin_right = pad; sb.content_margin_top = pad; sb.content_margin_bottom = pad
	return sb

func _build_board() -> void:
	## CS2 scoreboard: a wide dark sheet, header with map / mode / clock and the big "12 : 7" score,
	## teams stacked (each with its colour bar), rows: avatar, rank emblem, name, K / A / Ö / KAFA% / K/Ö / SKOR / PING
	if board:
		board.queue_free()
	var m = match_node
	board = PanelContainer.new()
	var bsb := _sbx(Color(0.02, 0.022, 0.028, 0.94), Color(1, 1, 1, 0.06), 4, 0)
	bsb.shadow_color = Color(0, 0, 0, 0.5); bsb.shadow_size = 24
	board.add_theme_stylebox_override("panel", bsb)
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.custom_minimum_size = Vector2(1180, 0)
	root.add_child(board)
	var v := UI.vbox(0)
	board.add_child(v)
	# ---- header
	var hdr := PanelContainer.new()
	var hsb := _sbx(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 4, 0)
	hsb.content_margin_left = 24; hsb.content_margin_right = 24; hsb.content_margin_top = 12; hsb.content_margin_bottom = 12
	hsb.corner_radius_bottom_left = 0; hsb.corner_radius_bottom_right = 0
	hdr.add_theme_stylebox_override("panel", hsb)
	v.add_child(hdr)
	var top := UI.hbox(16)
	hdr.add_child(top)
	var tv := UI.vbox(-4)
	tv.custom_minimum_size = Vector2(360, 0)
	top.add_child(tv)
	tv.add_child(UI.lbl(GS.MAPS[m.map_id]["name"].to_upper(), 30, Color.WHITE, "Teko"))
	tv.add_child(UI.lbl(GS.MODES[m.mode]["name"].to_upper() + ("   •   HEDEF %d" % int(m.target_score) if m.mode != "gungame" else ""), 14, Color(1, 1, 1, 0.5), "Rajdhani-Bold"))
	var mid := UI.hbox(18)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(mid)
	if m.teams:
		var ca: Color = GS.TEAM_COLORS["a"]; var cb: Color = GS.TEAM_COLORS["b"]
		mid.add_child(UI.lbl(GS.TEAMS["a"], 20, ca.lightened(0.3), "Rajdhani-Bold"))
		mid.add_child(UI.lbl(str(m.team_score["a"]), 52, ca.lightened(0.2), "Teko"))
		mid.add_child(UI.lbl(":", 40, Color(1, 1, 1, 0.4), "Teko"))
		mid.add_child(UI.lbl(str(m.team_score["b"]), 52, cb.lightened(0.2), "Teko"))
		mid.add_child(UI.lbl(GS.TEAMS["b"], 20, cb.lightened(0.3), "Rajdhani-Bold"))
	var tl := int(m.time_left)
	var tr := UI.lbl("%d:%02d" % [tl / 60, tl % 60], 34, Color.WHITE, "Teko", HORIZONTAL_ALIGNMENT_RIGHT)
	tr.custom_minimum_size = Vector2(360, 0)
	top.add_child(tr)
	# MVP = highest score overall
	var mvp = null
	var best := -1
	for e in m.combatants:
		var sc: int = int(e["score"]) if m.mode != "gungame" else int(e["gg"])
		if sc > best:
			best = sc; mvp = e
	var cols := [["", 46], ["OYUNCU", 384], ["SV", 52], ["L", 60], ["Ö", 60], ["KAFA %", 76], ["K/Ö", 72], ["SKOR" if m.mode != "gungame" else "SİLAH", 110], ["PİNG", 64]]
	var groups: Array = [["a", GS.TEAMS["a"]], ["b", GS.TEAMS["b"]]] if m.teams else [["", "OYUNCULAR"]]
	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 16)
	body.add_theme_constant_override("margin_top", 8); body.add_theme_constant_override("margin_bottom", 10)
	v.add_child(body)
	var bv := UI.vbox(10)
	body.add_child(bv)
	for gtuple in groups:
		var t: String = gtuple[0]
		var tc: Color = GS.TEAM_COLORS.get(t, UI.ACCENT)
		var list = m.combatants.filter(func(e): return t == "" or e["team"] == t)
		list.sort_custom(func(a, b): return (a["score"] > b["score"]) if m.mode != "gungame" else (a["gg"] > b["gg"]))
		var alive_n := 0
		for e in list:
			if e["node"].alive: alive_n += 1
		# team bar + column header in one line
		var th := UI.hbox(0)
		bv.add_child(th)
		var tb := ColorRect.new(); tb.color = tc; tb.custom_minimum_size = Vector2(4, 24)
		th.add_child(tb)
		var tn := UI.lbl("  " + str(gtuple[1]) + ("   %d/%d" % [alive_n, list.size()] if t != "" else ""), 16, tc.lightened(0.35), "Rajdhani-Bold")
		tn.custom_minimum_size = Vector2(cols[0][1] + cols[1][1] - 4, 0)
		th.add_child(tn)
		for c in cols.slice(2):
			var l := UI.lbl(c[0], 13, Color(1, 1, 1, 0.42), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
			l.custom_minimum_size = Vector2(c[1], 0)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			th.add_child(l)
		var rv := UI.vbox(2)
		bv.add_child(rv)
		for i in list.size():
			var e: Dictionary = list[i]
			var alive: bool = e["node"].alive
			var me: bool = e["is_player"]
			var rp := PanelContainer.new()
			var rbg := Color(tc.r * 0.3, tc.g * 0.3, tc.b * 0.3, 0.55) if me else (Color(1, 1, 1, 0.05) if i % 2 == 0 else Color(1, 1, 1, 0.025))
			var rsb := _sbx(rbg, Color(0, 0, 0, 0), 2, 0)
			rsb.border_width_left = 3; rsb.border_color = tc if alive else Color(tc.r, tc.g, tc.b, 0.3)
			if me:
				rsb.border_width_top = 1; rsb.border_width_bottom = 1; rsb.border_color = tc.lightened(0.2)
			rp.add_theme_stylebox_override("panel", rsb)
			rp.custom_minimum_size = Vector2(0, 40)
			rp.modulate.a = 1.0 if alive else 0.55
			rv.add_child(rp)
			var row := UI.hbox(0)
			rp.add_child(row)
			var fc := Color.WHITE
			if me: fc = Color("ffe2a8")
			# avatar: the agent portrait for you, a coloured initial for others
			var avc := Control.new()
			avc.custom_minimum_size = Vector2(cols[0][1], 40)
			row.add_child(avc)
			var art_p := "res://assets/ui/agents/%s.jpg" % GS.cur_char()
			if me and ResourceLoader.exists(art_p):
				var at := AtlasTexture.new()
				at.atlas = load(art_p)
				var aw: float = at.atlas.get_width()
				at.region = Rect2(aw * 0.25, aw * 0.05, aw * 0.5, aw * 0.5)
				var ar := TextureRect.new()
				ar.texture = at; ar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				ar.position = Vector2(7, 3); ar.size = Vector2(34, 34)
				avc.add_child(ar)
			else:
				var av := PanelContainer.new()
				var hue := float(abs(hash(str(e["name"]))) % 360) / 360.0
				av.add_theme_stylebox_override("panel", _sbx(Color.from_hsv(hue, 0.45, 0.42), Color(0, 0, 0, 0), 2, 0))
				av.position = Vector2(7, 3); av.size = Vector2(34, 34)
				var al := UI.lbl(str(e["name"]).substr(0, 1).to_upper(), 17, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
				al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				av.add_child(al)
				avc.add_child(av)
			var pc := UI.hbox(8)
			pc.custom_minimum_size = Vector2(cols[1][1], 0)
			row.add_child(pc)
			var ri: Dictionary = GS.rank_info(int(GS.profile.get("rp", 0)) if me else (int(e["lvl"]) * 37) % 3000)
			var rk := TextureRect.new()
			rk.texture = ri["icon"]
			rk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rk.custom_minimum_size = Vector2(32, 32)
			rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rk.tooltip_text = str(ri["name"])
			pc.add_child(rk)
			var nl := UI.lbl(str(e["name"]), 20, fc, "Rajdhani-Bold")
			nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nl.clip_text = true
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pc.add_child(nl)
			if mvp != null and e == mvp and best > 0:
				var mv := UI.lbl("★ MVP", 14, UI.GOLD, "Rajdhani-Bold")
				mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				pc.add_child(mv)
			if not alive:
				var sk := _skull_tex()
				if sk:
					var si := TextureRect.new()
					si.texture = sk; si.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; si.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					si.custom_minimum_size = Vector2(20, 20); si.modulate = Color(1, 0.4, 0.35)
					si.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					pc.add_child(si)
			var kills := int(e["kills"])
			var kd: float = float(kills) / max(1.0, float(e["deaths"]))
			var hsp := int(round(100.0 * float(e["head"]) / max(1.0, float(kills))))
			var assists := int(e.get("assists", 0))
			var vals := [str(e["lvl"]), str(kills), str(assists), str(e["deaths"]), ("%d%%" % hsp) if kills > 0 else "-", "%.2f" % kd,
				str(e["score"]) if m.mode != "gungame" else GS.WEAPONS[GS.GUNGAME_ORDER[min(e["gg"], GS.GUNGAME_ORDER.size() - 1)]]["name"],
				str(12 if me else 18 + (abs(hash(str(e["name"]))) % 30))]
			# columns: SV L Ö KAFA K/Ö SKOR PİNG (assists shown only when tracked)
			vals = [vals[0], vals[1], vals[3], vals[4], vals[5], vals[6], vals[7]]
			for k in vals.size():
				var vc := fc
				if k == 4: vc = Color("8dffb5") if kd >= 1.0 else Color("ff8f80")
				var big := k in [1, 2, 5]
				var l := UI.lbl(vals[k], 24 if big else 18, vc, "Teko" if big else "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER)
				l.custom_minimum_size = Vector2(cols[k + 2][1], 0)
				l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(l)
	var foot := UI.lbl("TAB bırakınca kapanır   •   Enter: sohbet   •   Y: takım sohbeti   •   V: sesli konuş", 13, Color(1, 1, 1, 0.32), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(foot)
	v.add_child(UI.spacer(false, 0, 8))
	board.position = (root.size - board.get_combined_minimum_size()) / 2
	_ignore_mouse(board)

# ---------------------------------------------------------------- pause & settings
func show_pause(p: bool) -> void:
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
	if not p:
		return
	pause_panel = ColorRect.new()
	(pause_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_panel)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(cc)
	var pp := UI.panel(Color(0.03, 0.035, 0.05, 0.94), Color(1, 1, 1, 0.08), 26, 12)
	cc.add_child(pp)
	var v := UI.vbox(12)
	v.custom_minimum_size = Vector2(360, 0)
	pp.add_child(v)
	v.add_child(UI.lbl("DURAKLATILDI", 40, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.btn("DEVAM ET", func(): match_node.set_paused(false), 24, true, 360, 56))
	v.add_child(UI.btn("AYARLAR", _open_settings, 22, false, 360, 52))
	v.add_child(UI.btn("MAÇTAN AYRIL", func(): match_node.leave(), 22, false, 360, 52))
	v.add_child(UI.btn("OYUNDAN ÇIK", func(): get_tree().quit(), 20, false, 360, 48))

func _open_settings() -> void:
	var holder := ColorRect.new()
	holder.color = Color(0.02, 0.025, 0.035, 0.97)
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(holder)
	var su := preload("res://scripts/settings_ui.gd").new()
	su.in_match = true
	su.on_close = func(): holder.queue_free()
	su.set_anchors_preset(Control.PRESET_FULL_RECT)
	su.offset_left = 120; su.offset_right = -120; su.offset_top = 60; su.offset_bottom = -60
	holder.add_child(su)

# ---------------------------------------------------------------- end screen
func show_end(r: Dictionary) -> void:
	if board: board.queue_free(); board = null
	if pause_panel: pause_panel.queue_free(); pause_panel = null
	death_panel.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var tw := bg.create_tween()
	tw.tween_property(bg, "color:a", 0.88, 0.8)
	var v := UI.vbox(16)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(1100, 0)
	v.position = Vector2(-550, -400)
	bg.add_child(v)
	var title := UI.lbl("ZAFER!" if r["won"] else "MAĞLUBİYET", 96, UI.GOLD if r["won"] else UI.RED, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	var m = match_node
	var sub := "%d. sıra" % r["place"] if not m.teams else "%s %d  -  %d %s" % [GS.TEAMS["a"], m.team_score["a"], m.team_score["b"], GS.TEAMS["b"]]
	v.add_child(UI.lbl(sub + "   •   " + GS.MODES[m.mode]["name"] + "   •   " + GS.MAPS[m.map_id]["name"], 26, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	var pe: Dictionary = r["pe"]
	var stats := UI.hbox(14)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(stats)
	for pair in [["ÖLDÜRME", str(pe["kills"])], ["ÖLÜM", str(pe["deaths"])], ["KAFADAN", str(pe["head"])], ["K/D", "%.2f" % (float(pe["kills"]) / max(1.0, float(pe["deaths"])))], ["SKOR", str(pe["score"])]]:
		var p := UI.panel(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), 14)
		var pv := UI.vbox(0)
		p.add_child(pv)
		pv.add_child(UI.lbl(pair[1], 52, Color.WHITE, "Teko", HORIZONTAL_ALIGNMENT_CENTER))
		pv.add_child(UI.lbl(pair[0], 18, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		p.custom_minimum_size = Vector2(170, 0)
		stats.add_child(p)
	v.add_child(UI.header("ÖDÜLLER", 24))
	var rw := UI.hbox(14)
	rw.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(rw)
	var rewards := [["TECRÜBE", "+%d XP" % r["xp"], Color("7fd1ff")], ["ALTIN", "+%s" % UI.money(r["gold"]), UI.GOLD]]
	for k in r["mats"].keys():
		if r["mats"][k] > 0:
			rewards.append([GS.MATS[k].to_upper(), "+%d" % r["mats"][k], Color("c8d2dc")])
	var i := 0
	for rr in rewards:
		var p := UI.panel(Color(1, 1, 1, 0.05), rr[2].darkened(0.3), 12)
		var pv := UI.vbox(0)
		p.add_child(pv)
		pv.add_child(UI.lbl(rr[1], 34, rr[2], "Teko", HORIZONTAL_ALIGNMENT_CENTER))
		pv.add_child(UI.lbl(rr[0], 16, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		p.custom_minimum_size = Vector2(150, 0)
		p.modulate.a = 0
		rw.add_child(p)
		var t2 := p.create_tween()
		t2.tween_interval(0.6 + i * 0.18)
		t2.tween_callback(func(): SFX.play("tick", -6))
		t2.tween_property(p, "modulate:a", 1.0, 0.25)
		i += 1
	# competitive rank change
	var ri: Dictionary = GS.rank_info(int(r.get("rp", 0)))
	var ro: Dictionary = GS.rank_info(int(r.get("rp_old", 0)))
	var rpd: int = int(r.get("rp", 0)) - int(r.get("rp_old", 0))
	var rk := UI.panel(Color(ri["color"].r * 0.12, ri["color"].g * 0.12, ri["color"].b * 0.12, 0.9), ri["color"], 12, 2)
	rk.custom_minimum_size = Vector2(620, 0)
	rk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rk)
	var rkh := UI.hbox(16)
	rk.add_child(rkh)
	var em := TextureRect.new()
	em.texture = ri["icon"]; em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; em.custom_minimum_size = Vector2(96, 96)
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rkh.add_child(em)
	var rkv := UI.vbox(2)
	rkv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rkh.add_child(rkv)
	var up_txt := ""
	if ri["i"] > ro["i"]: up_txt = "   ▲ TERFİ!"
	elif ri["i"] < ro["i"]: up_txt = "   ▼ RÜTBE DÜŞTÜ"
	rkv.add_child(UI.lbl(str(ri["name"]).to_upper() + up_txt, 30, ri["color"], "RussoOne-Regular"))
	rkv.add_child(UI.lbl(("%+d RP" % rpd) + ("   •   DERECELİ MAÇ" if r.get("ranked", false) else "   •   bot/normal maç (yarım puan)"), 20, UI.GREEN if rpd >= 0 else UI.RED, "Rajdhani-Bold"))
	var rbar := UI.bar(float(ro["prog"]) * 100.0, 100.0, ri["color"], 10)
	rkv.add_child(rbar)
	rkv.add_child(UI.lbl("%d RP%s" % [int(r.get("rp", 0)), ("  —  sonraki rütbe %d RP" % int(ri["hi"])) if ri["hi"] > ri["lo"] else "  —  EN YÜKSEK RÜTBE"], 16, UI.DIM, "Rajdhani-SemiBold"))
	var t3 := rbar.create_tween()
	t3.tween_interval(1.2)
	t3.tween_property(rbar, "value", float(ri["prog"]) * 100.0, 0.8)
	if ri["i"] > ro["i"]:
		t3.tween_callback(func(): SFX.play("success", -2))
	if r["ups"] > 0:
		v.add_child(UI.lbl("SEVİYE ATLADIN!  Yeni seviye: %d  (+500 Altın, +1 Kasa)" % int(GS.profile["level"]), 30, UI.GOLD, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	var xpb := UI.bar(float(GS.profile["xp"]), float(GS.xp_for_level(int(GS.profile["level"]))), Color("7fd1ff"), 10)
	v.add_child(xpb)
	v.add_child(UI.lbl("Seviye %d  —  %s / %s XP" % [int(GS.profile["level"]), UI.money(int(GS.profile["xp"])), UI.money(GS.xp_for_level(int(GS.profile["level"])))], 18, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
	var bb := UI.hbox(14)
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bb)
	bb.add_child(UI.btn("LOBİYE DÖN", func(): match_node.leave(), 24, true, 300, 58))
	bb.add_child(UI.btn("TEKRAR OYNA", func(): SFX.stop_amb(); SFX.clear_world(); match_node.main.start_match(GS.room), 22, false, 260, 58))

# ================================================================ inner controls
class Crosshair extends Control:
	var hud
	func _draw() -> void:
		var s: Dictionary = GS.settings
		var p = hud.player
		var c := size / 2
		var col := Color(str(s["xh_color"]))
		col.a = float(s["xh_alpha"])
		var gap: float = float(s["xh_gap"])
		if s["xh_dynamic"] and p.cur != "":
			gap += p.current_spread() * 260.0
		var ln: float = float(s["xh_size"])
		var th: float = float(s["xh_thick"])
		var style := int(s["xh_style"])
		if p.wdata.get("melee", false):
			style = 1
		var outline: bool = s["xh_outline"]
		var oc := Color(0, 0, 0, col.a * 0.8)
		var rects: Array = []
		if style == 0 or style == 3 or style == 4:
			rects.append(Rect2(c.x - gap - ln, c.y - th / 2, ln, th))
			rects.append(Rect2(c.x + gap, c.y - th / 2, ln, th))
			rects.append(Rect2(c.x - th / 2, c.y + gap, th, ln))
			if style != 3:
				rects.append(Rect2(c.x - th / 2, c.y - gap - ln, th, ln))
		if outline:
			for r in rects:
				draw_rect(r.grow(1.0), oc)
		for r in rects:
			draw_rect(r, col)
		if style == 2:
			if outline: draw_arc(c, gap + 4, 0, TAU, 48, oc, th + 2, true)
			draw_arc(c, gap + 4, 0, TAU, 48, col, th, true)
		if s["xh_dot"] or style == 1 or style == 4:
			if outline: draw_circle(c, th + 1.2, oc)
			draw_circle(c, th, col)

class HitMarker extends Control:
	var hud
	func _draw() -> void:
		if hud.hit_t <= 0 or not GS.settings.get("hit_marker", true):
			return
		var c := size / 2
		var a: float = clamp(hud.hit_t / 0.25, 0.0, 1.0)
		var col := Color(1, 0.15, 0.1, a) if hud.hit_kill else (Color(1, 0.8, 0.2, a) if hud.hit_head else Color(1, 1, 1, a))
		var r1 := 8.0 + (1.0 - a) * 3.0
		var r2 := r1 + (11.0 if hud.hit_kill else 8.0)
		for k in 4:
			var ang := PI / 4 + k * PI / 2
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * r1, c + d * r2, Color(0, 0, 0, a * 0.6), 4.0, true)
			draw_line(c + d * r1, c + d * r2, col, 2.2, true)

class DmgDir extends Control:
	var hud
	func _draw() -> void:
		var c := size / 2
		var yaw: float = hud.player.yaw
		for d in hud.dmg_list:
			var rel: float = d["a"] - yaw + PI
			var a: float = clamp(d["t"] / 1.2, 0.0, 1.0)
			var ang := -rel - PI / 2
			draw_arc(c, 150, ang - 0.25, ang + 0.25, 16, Color(1, 0.1, 0.05, a * 0.85), 10, true)

class Minimap extends Control:
	## circular rotating radar: real top-down map photo, compass ring, teammates and pinged enemies
	var hud
	var tex: Texture2D
	var zoom := 2.6
	const R := 112.0

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var m = hud.match_node
		var p = hud.player
		if p == null:
			return
		var c := Vector2(size.x / 2, R + 13)
		var pp: Vector2 = m.world_to_minimap(p.global_position)
		var k: float = zoom * 0.5
		# CS2 radar: rounded dark square with the rotating map clipped inside
		var box := Rect2(c - Vector2(R, R), Vector2(R * 2, R * 2))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.025, 0.03, 0.78)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 8
		draw_style_box(sb, box.grow(4))
		var pts := PackedVector2Array(); var uvs := PackedVector2Array(); var cols := PackedColorArray()
		var ts: Vector2 = tex.get_size() if tex else Vector2(512, 512)
		var cr := 6.0
		for ci in 4:
			var cc: Vector2 = [Vector2(R - cr, -R + cr), Vector2(R - cr, R - cr), Vector2(-R + cr, R - cr), Vector2(-R + cr, -R + cr)][ci]
			for si in 5:
				var a := -PI / 2 + ci * PI / 2 + si * (PI / 2) / 4.0
				var d: Vector2 = cc + Vector2(cos(a), sin(a)) * cr
				pts.append(c + d)
				uvs.append(((d / k).rotated(-p.yaw) + pp) / ts)
				cols.append(Color(0.92, 0.92, 0.92))
		if tex:
			draw_polygon(pts, cols, uvs, tex)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.14), 1.0, true)
		# field of view cone
		var fov := PackedVector2Array([c, c + Vector2(-0.62, -1).normalized() * R * 0.95, c + Vector2(0, -1) * R, c + Vector2(0.62, -1).normalized() * R * 0.95])
		draw_colored_polygon(fov, Color(1, 0.85, 0.5, 0.09))
		# combatants
		for e in m.combatants:
			var n = e["node"]
			if n == p or not n.alive:
				continue
			var friendly: bool = m.teams and e["team"] == p.team
			var pinged: bool = hud.pings.get(n, 0.0) > 0
			if not friendly and not pinged:
				continue
			var q: Vector2 = ((m.world_to_minimap(n.global_position) - pp) * k).rotated(p.yaw)
			var col: Color = GS.TEAM_COLORS.get(e["team"], Color(0.3, 0.6, 1)) if friendly else Color(1, 0.2, 0.15)
			if absf(q.x) > R - 6 or absf(q.y) > R - 6:
				q = q.clamp(Vector2(6 - R, 6 - R), Vector2(R - 6, R - 6))
				col.a = 0.6
			draw_circle(c + q, 6.0, Color(0, 0, 0, 0.6))
			draw_circle(c + q, 4.5, col)
			if not friendly:
				draw_arc(c + q, 9.0 + sin(Time.get_ticks_msec() * 0.012) * 2.0, 0, TAU, 20, Color(1, 0.25, 0.2, 0.7), 1.5, true)
		# sabotage: A / B sites and the bomb
		if m.sab and m.sab.sites.size() == 2:
			var fb2: Font = UI.font("RussoOne-Regular")
			for st in m.sab.sites:
				var q2: Vector2 = ((m.world_to_minimap(st["pos"]) - pp) * k).rotated(p.yaw)
				q2 = q2.clamp(Vector2(12 - R, 12 - R), Vector2(R - 12, R - 12))
				var hot: bool = m.sab.planted and st["pos"].distance_to(m.sab.bomb_pos) < m.sab.SITE_R
				var sc2: Color = Color(1, 0.3, 0.25) if hot else Color(1, 0.78, 0.35)
				var hp := PackedVector2Array()
				for hi in 6:
					hp.append(c + q2 + Vector2.from_angle(PI / 6.0 + hi * PI / 3.0) * 11.0)
				draw_colored_polygon(hp, Color(0.03, 0.035, 0.05, 0.9))
				hp.append(hp[0])
				draw_polyline(hp, sc2, 2.0, true)
				draw_string(fb2, c + q2 + Vector2(-6, 6), str(st["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			var bpos := Vector3.INF
			if m.sab.planted: bpos = m.sab.bomb_pos
			elif m.sab.bomb_drop != Vector3.INF and p.team == "a": bpos = m.sab.bomb_drop
			if bpos != Vector3.INF:
				var q3: Vector2 = ((m.world_to_minimap(bpos) - pp) * k).rotated(p.yaw)
				q3 = q3.clamp(Vector2(8 - R, 8 - R), Vector2(R - 8, R - 8))
				var bl: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
				draw_rect(Rect2(c + q3 - Vector2(6, 4), Vector2(12, 8)), Color(1, 0.25, 0.2, 0.6 + 0.4 * bl))
		for kk in hud.pings.keys():
			hud.pings[kk] -= get_process_delta_time()
			if hud.pings[kk] <= 0:
				hud.pings.erase(kk)
		# player arrow
		var tri := PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 8), c + Vector2(0, 4), c + Vector2(-8, 8)])
		draw_colored_polygon(tri, Color(1, 0.78, 0.25))
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.7), 1.5, true)
		# north marker on the edge (rotates with the view)
		var f: Font = UI.font("Rajdhani-Bold")
		var nd := Vector2(0, -1).rotated(p.yaw)
		var tmax: float = R / maxf(absf(nd.x), absf(nd.y))
		var npos := c + nd * (tmax - 10)
		draw_circle(npos, 8, Color(0, 0, 0, 0.6))
		draw_string(f, npos + Vector2(-5, 6), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.78, 0.3))
		# map name plate
		var nm: String = GS.MAPS[m.map_id]["name"].to_upper()
		draw_string(f, Vector2(c.x - R, c.y + R + 24), nm, HORIZONTAL_ALIGNMENT_LEFT, R * 2, 16, Color(1, 1, 1, 0.75))


class ScoreBar extends Control:
	## top-centre: two score cards with alive-player pips, timer pill in the middle, thin progress lines
	var hud

	static func grad_rect(ci: CanvasItem, r: Rect2, c0: Color, c1: Color, horizontal: bool = true) -> void:
		if r.size.x < 0.5 or r.size.y < 0.5:
			return
		var pts := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
		var cols := PackedColorArray([c0, c1, c1, c0]) if horizontal else PackedColorArray([c0, c0, c1, c1])
		ci.draw_polygon(pts, cols)

	func _box(r: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), rad: int = 6) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(rad)
		if border.a > 0:
			sb.border_color = border
			sb.set_border_width_all(1)
		draw_style_box(sb, r)

	func _draw() -> void:
		var m = hud.match_node
		var p = hud.player
		if m == null or p == null:
			return
		var W := size.x
		var f: Font = UI.font("Teko")
		var fb: Font = UI.font("Rajdhani-Bold")
		var cx := W / 2
		var cw := 112.0
		var sides: Array = []
		if m.teams:
			var my: String = p.team if p.team != "" else "a"
			var ot := "b" if my == "a" else "a"
			sides = [[GS.TEAMS[my], int(m.team_score[my]), GS.TEAM_COLORS[my], my], [GS.TEAMS[ot], int(m.team_score[ot]), GS.TEAM_COLORS[ot], ot]]
		else:
			var pe: Dictionary = m.entry(p)
			var best := 0
			for c in m.combatants:
				if c["node"] != p:
					best = max(best, int(c["kills"]) if m.mode != "gungame" else int(c["gg"]))
			var mine: int = int(pe.get("kills", 0)) if m.mode != "gungame" else int(pe.get("gg", 0))
			sides = [["SEN", mine, Color("3d9bff"), ""], ["LİDER", best, Color("ff7a2f"), ""]]
		var target: float = max(float(m.target_score), 1.0) if m.mode != "gungame" else float(GS.GUNGAME_ORDER.size())
		var sw := 150.0
		for i in 2:
			var sd: Array = sides[i]
			var left := i == 0
			var col: Color = sd[2]
			var r := Rect2(cx - cw / 2 - 6 - sw, 6, sw, 52) if left else Rect2(cx + cw / 2 + 6, 6, sw, 52)
			ScoreBar.grad_rect(self, r, Color(0.04, 0.045, 0.05, 0.0 if left else 0.7), Color(0.04, 0.045, 0.05, 0.7 if left else 0.0))
			# coloured inner edge toward the timer
			var edge := Rect2(r.end.x - 4, r.position.y + 6, 4, r.size.y - 12) if left else Rect2(r.position.x, r.position.y + 6, 4, r.size.y - 12)
			draw_rect(edge, col)
			var sc_s := str(sd[1])
			var name_s: String = str(sd[0])
			if left:
				draw_string(f, Vector2(r.end.x - 70, r.position.y + 45), sc_s, HORIZONTAL_ALIGNMENT_RIGHT, 58, 48, Color.WHITE)
				draw_string(fb, Vector2(r.position.x + 12, r.position.y + 22), name_s, HORIZONTAL_ALIGNMENT_LEFT, 90, 15, col.lightened(0.35))
			else:
				draw_string(f, Vector2(r.position.x + 12, r.position.y + 45), sc_s, HORIZONTAL_ALIGNMENT_LEFT, 58, 48, Color.WHITE)
				draw_string(fb, Vector2(r.end.x - 102, r.position.y + 22), name_s, HORIZONTAL_ALIGNMENT_RIGHT, 90, 15, col.lightened(0.35))
			# progress to target
			var k: float = clamp(float(sd[1]) / target, 0.0, 1.0)
			var pr := Rect2(r.position.x + 10, r.end.y - 7, (r.size.x - 20), 3)
			draw_rect(pr, Color(1, 1, 1, 0.1))
			if left:
				draw_rect(Rect2(pr.end.x - pr.size.x * k, pr.position.y, pr.size.x * k, 3), col.lightened(0.15))
			else:
				draw_rect(Rect2(pr.position.x, pr.position.y, pr.size.x * k, 3), col.lightened(0.15))
			# alive pips (team modes)
			if sd[3] != "":
				var mem: Array = m.combatants.filter(func(e): return e["team"] == sd[3])
				var n: int = mini(mem.size(), 10)
				var px0: float = (r.end.x - 12 - n * 11) if left else (r.position.x + 12)
				for j in n:
					var al: bool = mem[j]["node"].alive
					var pc := Vector2(px0 + j * 11 + 4, r.end.y + 9)
					draw_rect(Rect2(pc - Vector2(4, 4), Vector2(8, 8)), col if al else Color(1, 1, 1, 0.15))
		# timer pill
		var tl := int(m.time_left)
		var tr := Rect2(cx - cw / 2, 2, cw, 60)
		_box(tr, Color(0.04, 0.045, 0.05, 0.82), Color(1, 1, 1, 0.08), 3)
		var tc := Color.WHITE if tl > 30 else Color(1, 0.32, 0.28).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01))
		draw_string(f, Vector2(cx - cw / 2, 42), "%d:%02d" % [tl / 60, tl % 60], HORIZONTAL_ALIGNMENT_CENTER, cw, 42, tc)
		var goal: String = ("İLK %d" % int(m.target_score)) if m.mode != "gungame" else "SİLAH %d/%d" % [int(m.entry(p).get("gg", 0)) + 1, GS.GUNGAME_ORDER.size()]
		draw_string(fb, Vector2(cx - cw / 2, 56), goal, HORIZONTAL_ALIGNMENT_CENTER, cw, 12, Color(1, 1, 1, 0.5))
		draw_rect(Rect2(tr.position.x, tr.end.y - 2, tr.size.x, 2), Color(1, 1, 1, 0.18))


class HealthPanel extends Control:
	## modern health / armour: fading glass plate, big number, slim gradient bar with damage trail and 25-ticks
	var hud

	func _process(delta: float) -> void:
		var p = hud.player
		if p == null:
			return
		hud.hp_shown = lerp(hud.hp_shown, float(p.health), min(delta * 14.0, 1.0))
		if hud.hp_trail > hud.hp_shown:
			hud.hp_trail = move_toward(hud.hp_trail, hud.hp_shown, delta * 35.0)
		else:
			hud.hp_trail = hud.hp_shown
		queue_redraw()

	func _draw() -> void:
		## CS2-style: no plate, just a soft shadow strip, white "+ 100" and "shield 100" with slim bars
		var p = hud.player
		if p == null:
			return
		var W := size.x; var H := size.y
		var f: Font = UI.font("Rajdhani-Bold")
		var fn: Font = UI.font("Teko")
		ScoreBar.grad_rect(self, Rect2(0, H - 62, W, 62), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.0))
		var hp := int(ceil(p.health))
		var low: bool = hp <= 25
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		var hc := Color(1, 0.32, 0.28).lerp(Color(1, 0.85, 0.8), pulse * 0.35) if low else Color(1, 1, 1, 0.96)
		var y := H - 14.0
		# health: plus icon
		var ic := Vector2(20, y - 18)
		draw_rect(Rect2(ic + Vector2(-3, -10), Vector2(6, 20)), hc)
		draw_rect(Rect2(ic + Vector2(-10, -3), Vector2(20, 6)), hc)
		draw_string(fn, Vector2(38, y), str(hp), HORIZONTAL_ALIGNMENT_LEFT, 90, 50, hc)
		var bx := 38.0; var bw := 92.0
		draw_rect(Rect2(bx, y + 3, bw, 3), Color(1, 1, 1, 0.14))
		var tr: float = clampf(hud.hp_trail / 100.0, 0, 1)
		var fl: float = clampf(hud.hp_shown / 100.0, 0, 1)
		if tr > fl:
			draw_rect(Rect2(bx + bw * fl, y + 3, bw * (tr - fl), 3), Color(1, 0.75, 0.6, 0.8))
		draw_rect(Rect2(bx, y + 3, bw * fl, 3), hc if not low else Color(1, 0.35, 0.3))
		# armour: shield icon
		var ax := 168.0
		var sc := Vector2(ax, y - 18)
		var arm := int(p.armor)
		var acol := Color(1, 1, 1, 0.96) if arm > 0 else Color(1, 1, 1, 0.35)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(-9, -10), sc + Vector2(9, -10), sc + Vector2(9, 2), sc + Vector2(0, 11), sc + Vector2(-9, 2)]), acol)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(-5, -6), sc + Vector2(5, -6), sc + Vector2(5, 1), sc + Vector2(0, 6), sc + Vector2(-5, 1)]), Color(0.1, 0.12, 0.15, 0.85))
		draw_string(fn, Vector2(ax + 18, y), str(arm), HORIZONTAL_ALIGNMENT_LEFT, 90, 50, acol)
		draw_rect(Rect2(ax + 18, y + 3, 76, 3), Color(1, 1, 1, 0.14))
		draw_rect(Rect2(ax + 18, y + 3, 76 * clampf(arm / 100.0, 0, 1), 3), acol)
		# name + team (small, above)
		var team_c: Color = GS.TEAM_COLORS.get(p.team, Color(1, 0.55, 0.12))
		var nm: String = str(GS.profile["name"])
		draw_rect(Rect2(10, y - 62, 3, 13), team_c)
		draw_string(f, Vector2(18, y - 51), nm, HORIZONTAL_ALIGNMENT_LEFT, 220, 15, Color(1, 1, 1, 0.8))


class AmmoPanel extends Control:
	## weapon silhouette, magazine pips, big ammo count, reserve, fire mode and grenades
	var hud
	var icon: TextureRect
	var icon_id := ""

	func _ready() -> void:
		icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(190, 82)
		icon.position = Vector2(26, 8)
		icon.size = Vector2(190, 82)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item; void fragment(){ vec4 t = texture(TEXTURE, UV); float l = dot(t.rgb, vec3(0.3,0.5,0.2)); COLOR = vec4(vec3(0.75 + l * 0.35), t.a * 0.95); }"
		var m := ShaderMaterial.new(); m.shader = sh
		icon.material = m
		add_child(icon)

	func _sk(r: Rect2, sk: float) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(sk, 0), r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x - sk, r.size.y), r.position + Vector2(0, r.size.y)])

	func _process(_d: float) -> void:
		var p = hud.player
		if p and p.cur != icon_id and p.cur != "":
			icon_id = p.cur
			Thumbs.request(icon_id, GS.wskin(icon_id), icon)
		icon.visible = false      # CS2-style ammo block: numbers only
		queue_redraw()

	func _draw() -> void:
		## CS2-style: "30 | 90" in white with a bullet icon, weapon name small above, grenades as a row of icons
		var p = hud.player
		if p == null or p.cur == "":
			return
		var W := size.x; var H := size.y
		ScoreBar.grad_rect(self, Rect2(0, H - 62, W, 62), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.42))
		var fn: Font = UI.font("Teko")
		var fb: Font = UI.font("Rajdhani-Bold")
		var w: Dictionary = p.wdata
		var right := W - 12.0
		var y := H - 14.0
		var nm: String = GS.WEAPONS[p.cur]["name"]
		var lvl: int = GS.wlvl(p.cur)
		var nm_s := nm + ("  +%d" % lvl if lvl > 0 else "")
		draw_string(fb, Vector2(right - 300, y - 51), nm_s, HORIZONTAL_ALIGNMENT_RIGHT, 300, 15, Color(1, 1, 1, 0.75))
		if w.get("melee", false):
			draw_string(fb, Vector2(right - 300, y - 4), "SOL TIK: KES   ·   SAĞ TIK: SAPLA", HORIZONTAL_ALIGNMENT_RIGHT, 300, 15, Color(1, 1, 1, 0.6))
		elif w.get("throwable", false):
			var cnt: int = p.smokes if p.cur == "smoke" else p.grenades
			draw_string(fn, Vector2(right - 90, y), "x%d" % cnt, HORIZONTAL_ALIGNMENT_RIGHT, 90, 50, Color.WHITE)
			draw_string(fb, Vector2(right - 400, y - 6), "BASILI TUT: NİŞAN  ·  BIRAK: AT   ", HORIZONTAL_ALIGNMENT_RIGHT, 300, 14, Color(1, 1, 1, 0.55))
		elif p.ammo.has(p.cur):
			var a: Array = p.ammo[p.cur]
			var mx: int = int(w.get("mag_max", 30))
			var lowa: bool = a[0] <= maxi(1, int(mx * 0.2))
			var col := Color(1, 0.33, 0.28) if lowa else Color(1, 1, 1, 0.96)
			var rs := str(a[1])
			var rw := fn.get_string_size(rs, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			draw_string(fn, Vector2(right - rw, y), rs, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.6))
			draw_rect(Rect2(right - rw - 12, y - 30, 2, 24), Color(1, 1, 1, 0.35))
			var ms := str(a[0])
			var mw := fn.get_string_size(ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 50).x
			var mxp := right - rw - 22 - mw
			draw_string(fn, Vector2(mxp, y), ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, col)
			# bullet icon
			var bxp := mxp - 22
			draw_rect(Rect2(bxp, y - 30, 8, 22), col)
			draw_colored_polygon(PackedVector2Array([Vector2(bxp, y - 30), Vector2(bxp + 8, y - 30), Vector2(bxp + 4, y - 38)]), col)
			draw_rect(Rect2(bxp, y - 12, 8, 2), Color(0, 0, 0, 0.4))
			if p.reload_t > 0:
				var rf: float = 1.0 - p.reload_t / max(p.reload_total, 0.01)
				draw_rect(Rect2(right - 160, y + 4, 160, 3), Color(1, 1, 1, 0.14))
				draw_rect(Rect2(right - 160, y + 4, 160 * rf, 3), Color(1, 1, 1, 0.9))
			var mode := "OTO" if w.get("auto", false) else ("SÜRGÜ" if w.get("bolt", false) else ("POMPA" if w.get("shell_reload", false) else "TEK"))
			draw_string(fb, Vector2(bxp - 120, y - 6), mode, HORIZONTAL_ALIGNMENT_RIGHT, 110, 13, Color(1, 1, 1, 0.45))
		# grenades: small icons above the ammo (frag / smoke), dimmed when empty
		if p.slots.has("bomba"):
			var gx := right - 8.0
			var gy := y - 78.0
			for k in [["smoke", p.smokes], ["frag", p.grenades]]:
				for j in int(k[1]):
					var c0 := Color(1, 1, 1, 0.85 if p.cur == k[0] else 0.55)
					if k[0] == "frag":
						draw_circle(Vector2(gx - 6, gy + 8), 6, c0)
						draw_rect(Rect2(gx - 9, gy - 1, 6, 4), c0)
					else:
						draw_rect(Rect2(gx - 11, gy, 10, 15), c0)
						draw_rect(Rect2(gx - 11, gy, 10, 3), Color(0, 0, 0, 0.35))
					gx -= 18.0


class MedalRing extends Control:
	## Expanding glow ring + light rays behind the kill medal.
	var t := 1.0:
		set(v):
			t = v
			queue_redraw()
	var col := Color.WHITE

	func _draw() -> void:
		if t >= 1.0:
			return
		var a := 1.0 - t
		var r := 60.0 + t * 130.0
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(col.r, col.g, col.b, a * 0.9), 6.0 * a + 1.0, true)
		draw_arc(Vector2.ZERO, r * 0.8, 0, TAU, 64, Color(1, 1, 1, a * 0.5), 2.0, true)
		for i in 12:
			var ang := i * TAU / 12.0 + t * 0.6
			var d := Vector2(cos(ang), sin(ang))
			draw_line(d * (50.0 + t * 40.0), d * (90.0 + t * 150.0), Color(col.r, col.g, col.b, a * 0.55), 3.0, true)


# ---------------------------------------------------------------- weapon menu (B)
const BUY_GROUPS := [["TÜFEKLER", ["ak47", "akm", "m4a1", "m4k", "scar", "aug", "m249", "rpk16", "kuzgun"]], ["HAFİF MAKİNALI", ["mp5", "p90", "ump45", "vector", "vityaz", "uzi"]], ["POMPALI", ["spas"]],
	["KESKİN NİŞANCI", ["awp", "awm", "kar98"]], ["TABANCALAR", ["glock", "usp", "deagle", "revolver", "kartal", "fn502", "m1911"]], ["BIÇAKLAR", ["knife", "karambit", "hancer", "kasap", "balta"]]]

## Valorant-style loadout panel: one compact window over the (still visible) game, weapon classes as columns
## of white silhouette cards, and a detail pane for the hovered weapon on the right.
const BUY_COLS := [
	[["TABANCALAR", ["glock", "usp", "m1911", "fn502", "deagle", "revolver", "kartal"]]],
	[["HAFİF MAKİNALI", ["mp5", "p90", "ump45", "vector", "vityaz", "uzi"]], ["POMPALI", ["spas"]]],
	[["TÜFEKLER", ["ak47", "akm", "m4a1", "m4k", "scar", "aug", "kuzgun"]]],
	[["NİŞANCI", ["awp", "awm", "kar98"]], ["AĞIR", ["m249", "rpk16"]]],
	[["BIÇAKLAR", ["knife", "karambit", "hancer", "kasap", "balta"]]],
]
var _buy_detail: VBoxContainer

func toggle_buy(open: bool) -> void:
	if buy_panel:
		buy_panel.queue_free()
		buy_panel = null
	buy_open = open
	if not open:
		if not match_node.paused and not match_node.ended:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SFX.play("equip", -8)
	var mode: String = match_node.mode
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	buy_panel = dim
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := PanelContainer.new()
	var psb := UI.sb(Color(0.02, 0.025, 0.035, 0.86), Color(1, 1, 1, 0.07), 1, 12, 18)
	psb.shadow_color = Color(0, 0, 0, 0.45); psb.shadow_size = 30
	p.add_theme_stylebox_override("panel", psb)
	cc.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	# header
	var top := UI.hbox(12)
	v.add_child(top)
	var acc := ColorRect.new(); acc.color = UI.ACCENT; acc.custom_minimum_size = Vector2(4, 30)
	top.add_child(acc)
	top.add_child(UI.lbl("SİLAH SEÇİMİ", 28, Color.WHITE, "RussoOne-Regular"))
	top.add_child(UI.spacer())
	for cat in [["ana", "ANA"], ["tabanca", "TABANCA"], ["bicak", "BIÇAK"]]:
		var cur_id: String = player.slots.get(cat[0], "")
		if cur_id == "" or not GS.WEAPONS.has(cur_id):
			continue
		var chip := PanelContainer.new()
		var csb := UI.sb(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 1, 6, 0)
		csb.content_margin_left = 8; csb.content_margin_right = 10; csb.content_margin_top = 2; csb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", csb)
		var ch := UI.hbox(6)
		chip.add_child(ch)
		var ci := TextureRect.new()
		ci.texture = _kf_icon(cur_id); ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ci.custom_minimum_size = Vector2(54, 22)
		ch.add_child(ci)
		var cv := UI.vbox(-4)
		ch.add_child(cv)
		cv.add_child(UI.lbl(cat[1], 11, UI.DIM, "Rajdhani-Bold"))
		cv.add_child(UI.lbl(str(GS.WEAPONS[cur_id]["name"]), 15, Color.WHITE, "Rajdhani-Bold"))
		top.add_child(chip)
	var kb := UI.lbl("[B] KAPAT", 15, UI.DIM, "Rajdhani-Bold")
	top.add_child(kb)
	if mode == "gungame" or mode == "knife":
		v.add_child(UI.lbl("Bu modda silah değiştirilemez.", 24, UI.RED, "Rajdhani-Bold"))
		_ignore_unless_button(p)
		return
	var body := UI.hbox(14)
	v.add_child(body)
	var cols: Array = BUY_COLS.duplicate(true)
	var extra: Array = []
	for wid in GS.mod_weapon_model.keys():
		extra.append(wid)
	if extra.size() > 0:
		cols[4].append(["EKLENTİ", extra])
	var first := ""
	for col in cols:
		var cv2 := UI.vbox(6)
		cv2.custom_minimum_size = Vector2(196, 0)
		body.add_child(cv2)
		for g in col:
			var hh := UI.hbox(6)
			cv2.add_child(hh)
			var dot := ColorRect.new(); dot.color = UI.ACCENT; dot.custom_minimum_size = Vector2(3, 14)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hh.add_child(dot)
			hh.add_child(UI.lbl(g[0], 14, UI.ACCENT2, "Rajdhani-Bold"))
			for id in g[1]:
				if not GS.WEAPONS.has(id):
					continue
				if first == "" or player.slots.get(GS.WEAPONS[id]["cat"], "") == id and GS.WEAPONS[id]["cat"] == "ana":
					first = id
				cv2.add_child(_buy_card(id, mode))
	# detail pane
	var dp := PanelContainer.new()
	var dsb := UI.sb(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07), 1, 10, 14)
	dp.add_theme_stylebox_override("panel", dsb)
	dp.custom_minimum_size = Vector2(320, 0)
	body.add_child(dp)
	_buy_detail = UI.vbox(8)
	dp.add_child(_buy_detail)
	if first != "":
		_buy_show(first, mode)

func _ignore_unless_button(n: Node) -> void:
	pass

func _buy_card(id: String, mode: String) -> Control:
	var w: Dictionary = GS.WEAPONS[id]
	var cat: String = w["cat"]
	var owned: bool = GS.owned(id)
	var allowed: bool = owned and (mode != "sniper" or cat != "ana" or w.get("scope", false))
	var equipped: bool = player.slots.get(cat, "") == id
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(196, 76)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := Color(UI.ACCENT.r * 0.22, UI.ACCENT.g * 0.18, UI.ACCENT.b * 0.12, 0.95) if equipped else (Color(0.06, 0.07, 0.09, 0.92) if allowed else Color(0.04, 0.04, 0.05, 0.85))
	b.add_theme_stylebox_override("normal", UI.sb(bg, UI.ACCENT if equipped else Color(1, 1, 1, 0.06), 2 if equipped else 1, 4, 0))
	b.add_theme_stylebox_override("hover", UI.sb(Color(0.11, 0.12, 0.15, 0.98), UI.ACCENT2, 1, 4, 0))
	b.add_theme_stylebox_override("pressed", UI.sb(Color(0.2, 0.12, 0.04, 1), Color.WHITE, 2, 4, 0))
	var ic := TextureRect.new()
	ic.texture = _kf_icon(id)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 14; ic.offset_right = -14; ic.offset_top = 8; ic.offset_bottom = -24
	ic.modulate = Color(1, 1, 1, 0.95) if allowed else Color(0.55, 0.57, 0.62, 0.45)
	b.add_child(ic)
	var nm := UI.lbl(str(w["name"]).to_upper(), 13, Color.WHITE if allowed else UI.DIM, "Rajdhani-Bold")
	nm.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	nm.offset_left = 8; nm.offset_top = -21; nm.offset_bottom = -3
	b.add_child(nm)
	var tag := ""
	var tc := UI.DIM
	if equipped:
		tag = "✓"; tc = UI.GREEN
	elif not owned:
		tag = "◆ %s" % UI.money(int(w.get("price", 0))); tc = UI.GOLD
	elif not allowed:
		tag = "MODDA YOK"; tc = UI.RED
	if tag != "":
		var tl := UI.lbl(tag, 13, tc, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_RIGHT)
		tl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		tl.offset_left = -110; tl.offset_right = -8; tl.offset_top = -21; tl.offset_bottom = -3
		b.add_child(tl)
	var wl := GS.wlvl(id)
	if owned and wl > 0:
		var bd := lvl_badge(wl, 11)
		bd.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bd.position = Vector2(-44, 5)
		b.add_child(bd)
	for c in b.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.mouse_entered.connect(func(): SFX.play("ui_hover", -16); _buy_show(id, mode))
	if allowed:
		b.pressed.connect(func():
			player.equip_from_menu(cat, id)
			SFX.play("buy", -6)
			toggle_buy(false))
	else:
		b.pressed.connect(func(): SFX.play("fail", -6))
	return b

func _buy_show(id: String, mode: String) -> void:
	if _buy_detail == null or not is_instance_valid(_buy_detail):
		return
	UI.clear(_buy_detail)
	var w: Dictionary = GS.WEAPONS[id]
	var st := GS.stats_for(id)
	var owned: bool = GS.owned(id)
	var th := Thumbs.make_rect(id, GS.wskin(id), Vector2(290, 130))
	_buy_detail.add_child(th)
	var nh := UI.hbox(8)
	_buy_detail.add_child(nh)
	nh.add_child(UI.lbl(str(w["name"]).to_upper(), 26, Color.WHITE, "RussoOne-Regular"))
	var wl := GS.wlvl(id)
	if owned and wl > 0:
		var bd := lvl_badge(wl, 13)
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nh.add_child(bd)
	var sk: String = GS.wskin(id)
	var skn: String = str(GS.SKINS.get(sk, {}).get("name", "Standart")) if sk != "std" else "Standart"
	_buy_detail.add_child(UI.lbl("%s  •  %s" % [str(w.get("cls", w["cat"])).to_upper(), skn], 14, UI.ACCENT2, "Rajdhani-Bold"))
	var rows: Array = []
	if w.get("melee", false):
		rows = [["HASAR", float(st["dmg"]), 120.0, "%d" % int(st["dmg"])]]
	else:
		var dmg := float(st["dmg"]) * float(w.get("pellets", 1))
		rows = [
			["HASAR", dmg, 140.0, "%d" % int(dmg)],
			["ATIŞ HIZI", float(w["rpm"]), 1200.0, "%d/dk" % int(w["rpm"])],
			["İSABET", clampf(1.0 - float(st["spread"]) / 0.09, 0.0, 1.0) * 100.0, 100.0, ""],
			["MENZİL", float(w.get("range", 100.0)), 450.0, "%d m" % int(w.get("range", 100.0))],
			["HAREKET", float(w.get("speed", 1.0)) * 100.0, 115.0, "%d%%" % int(float(w.get("speed", 1.0)) * 100.0)],
		]
	for r in rows:
		var rh := UI.hbox(8)
		_buy_detail.add_child(rh)
		var rl := UI.lbl(r[0], 13, UI.DIM, "Rajdhani-Bold")
		rl.custom_minimum_size = Vector2(74, 0)
		rh.add_child(rl)
		var bar := UI.bar(r[1], r[2], UI.ACCENT, 6, 150)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UI.sb(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 3, 0))
		rh.add_child(bar)
		rh.add_child(UI.lbl(r[3], 14, Color.WHITE, "Rajdhani-Bold"))
	if not w.get("melee", false):
		_buy_detail.add_child(UI.lbl("ŞARJÖR  %d / %d" % [int(st["mag"]), int(w.get("reserve", 0))], 15, Color.WHITE, "Rajdhani-Bold"))
	var ab: String = str(GS.BALLISTICS.get(id, {}).get("ability", ""))
	if ab != "":
		var al := UI.lbl(ab, 14, Color(0.8, 0.85, 0.9), "Rajdhani-SemiBold")
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size = Vector2(290, 0)
		_buy_detail.add_child(al)
	var note := "Tıkla: kuşan (sonraki doğuşta da kalır)" if owned else "Marketten açılır: %s altın" % UI.money(int(w.get("price", 0)))
	_buy_detail.add_child(UI.lbl(note, 13, UI.GREEN if owned else UI.GOLD, "Rajdhani-Bold"))
