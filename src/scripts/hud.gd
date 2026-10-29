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

func _ready() -> void:
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
	var sc := TextureRect.new()
	sc.texture = load("res://assets/fx/scope.png")
	sc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_ov.add_child(sc)
	for side in [0, 1]:
		var cr := ColorRect.new()
		cr.color = Color.BLACK
		cr.anchor_top = 0; cr.anchor_bottom = 1
		if side == 0:
			cr.anchor_left = 0; cr.anchor_right = 0.5; cr.offset_right = -540
		else:
			cr.anchor_left = 0.5; cr.anchor_right = 1; cr.offset_left = 540
		scope_ov.add_child(cr)
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
	feed = UI.vbox(4)
	feed.anchor_left = 1; feed.anchor_right = 1
	feed.offset_left = -560; feed.offset_right = -24; feed.offset_top = 24
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(feed)
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
	dv.set_anchors_preset(Control.PRESET_CENTER)
	dv.position = Vector2(-400, 140)
	dv.custom_minimum_size = Vector2(800, 0)
	death_panel.add_child(dv)
	death_lbl = UI.lbl("", 34, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	dv.add_child(death_lbl)
	death_timer_lbl = UI.lbl("", 22, UI.DIM, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER)
	dv.add_child(death_timer_lbl)
	on_weapon_changed()

func show_countdown() -> void:
	pass

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
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
		ammo_lbl.text = ("x%d" % player.grenades) if player.wdata.get("throwable", false) else ""
		reserve_lbl.visible = false
	nade_lbl.text = ("💣 x%d" % player.grenades) if player.slots.has("bomba") else ""
	reload_bar.visible = player.reload_t > 0 and not player.wdata.get("shell_reload", false)
	if reload_bar.visible:
		reload_bar.value = 1.0 - player.reload_t / max(player.reload_total, 0.01)
	# scope
	scope_ov.visible = player.wdata.get("scope", false) and player.ads_k > 0.92 and player.alive
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
		death_timer_lbl.text = "Yeniden doğuluyor: %.1f" % max(death_t, 0.0)
	# weapon menu (B)
	if Input.is_action_just_pressed("buy_menu") and not m.ended and not m.paused:
		toggle_buy(not buy_open)
	# scoreboard (Tab)
	var show_board: bool = Input.is_action_pressed("scoreboard") and not m.ended
	if show_board:
		board_t -= delta
		if board == null or board_t <= 0:
			board_t = 0.25
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

func kill_feed(killer: String, victim: String, wid: String, head: bool, kt: String, vt: String, by_player: bool, player_died: bool) -> void:
	if not GS.settings.get("kill_feed", true):
		return
	var p := UI.panel(Color(0.02, 0.03, 0.05, 0.65) if not by_player else Color(0.35, 0.2, 0.05, 0.75), Color(1, 1, 1, 0.08) if not (by_player or player_died) else (UI.ACCENT if by_player else UI.RED), 8, 2)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := UI.hbox(10)
	p.add_child(h)
	var kc: Color = GS.TEAM_COLORS.get(kt, Color("ffcf5a")) if kt != "" else Color("ffcf5a")
	var vc: Color = GS.TEAM_COLORS.get(vt, Color("ff6a5a")) if vt != "" else Color("ff6a5a")
	h.add_child(UI.lbl(killer, 20, kc, "Rajdhani-Bold"))
	var wname: String = GS.WEAPONS[wid]["name"] if GS.WEAPONS.has(wid) else "☠"
	h.add_child(UI.lbl("[" + wname + "]", 17, UI.DIM, "Rajdhani-SemiBold"))
	if head:
		h.add_child(UI.lbl("✖ KAFA", 17, UI.GOLD, "Rajdhani-Bold"))
	h.add_child(UI.lbl(victim, 20, vc, "Rajdhani-Bold"))
	feed.add_child(p)
	_ignore_mouse(p)
	if feed.get_child_count() > 6:
		feed.get_child(0).queue_free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func kill_confirm(head: bool, big: String, multi: int = 1, wid: String = "", streak: int = 1) -> void:
	center2.text = ("+150  KAFADAN VURUŞ" if head else "+100  ETKİSİZ HALE GETİRİLDİ")
	center2.add_theme_color_override("font_color", UI.GOLD if head else Color(1, 1, 1, 0.9))
	center2.modulate.a = 1.0
	var tw := center2.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(center2, "modulate:a", 0.0, 0.5)
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
		t.texture = medals.get("head" if (i == multi - 1 and key == "head") else "kill")
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

func show_death(killer: String, wid: String, head: bool) -> void:
	death_panel.visible = true
	death_t = 3.5
	var wn: String = GS.WEAPONS[wid]["name"] if GS.WEAPONS.has(wid) else ""
	death_lbl.text = "%s seni etkisiz hale getirdi%s" % [killer, ("  [" + wn + "]" if wn != "" else "")] + ("  — KAFADAN!" if head else "")

# ---------------------------------------------------------------- scoreboard
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

func _build_board() -> void:
	if board:
		board.queue_free()
	var m = match_node
	board = UI.panel(Color(0.03, 0.04, 0.06, 0.92), Color(1, 1, 1, 0.12), 20, 6)
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.custom_minimum_size = Vector2(1240 if m.teams else 900, 0)
	root.add_child(board)
	var v := UI.vbox(10)
	board.add_child(v)
	var top := UI.hbox(12)
	v.add_child(top)
	top.add_child(UI.header(GS.MODES[m.mode]["name"].to_upper() + "  •  " + GS.MAPS[m.map_id]["name"].to_upper(), 26))
	top.add_child(UI.spacer())
	var tl := int(m.time_left)
	top.add_child(UI.lbl("Kalan Süre  %d:%02d" % [tl / 60, tl % 60], 22, UI.DIM, "Rajdhani-Bold"))
	var groups: Array = []
	if m.teams:
		groups = [["a", GS.TEAMS["a"]], ["b", GS.TEAMS["b"]]]
	else:
		groups = [["", "OYUNCULAR"]]
	var hb := UI.hbox(20)
	v.add_child(hb)
	for gtuple in groups:
		var t: String = gtuple[0]
		var gv := UI.vbox(3)
		gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(gv)
		var head := UI.hbox(0)
		var hp := UI.panel(GS.TEAM_COLORS.get(t, UI.ACCENT).darkened(0.4), Color(0, 0, 0, 0), 8, 2)
		hp.add_child(head)
		gv.add_child(hp)
		var title = gtuple[1] + ("   " + str(m.team_score[t]) if t != "" else "")
		var cols := [[title, 260], ["Svy", 50], ["Ö", 60], ["Ö/L", 60], ["KAFA", 60], ["K/D", 60], ["SKOR", 80], ["Ping", 60]]
		if m.mode == "gungame":
			cols[6] = ["SİLAH", 80]
		for c in cols:
			var l := UI.lbl(c[0], 18 if c[0] != title else 22, Color.WHITE, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_LEFT if c[0] == title else HORIZONTAL_ALIGNMENT_CENTER)
			l.custom_minimum_size = Vector2(c[1], 30)
			head.add_child(l)
		var list = m.combatants.filter(func(e): return t == "" or e["team"] == t)
		list.sort_custom(func(a, b): return (a["score"] > b["score"]) if m.mode != "gungame" else (a["gg"] > b["gg"]))
		for i in list.size():
			var e: Dictionary = list[i]
			var row := UI.hbox(0)
			var rp := UI.panel(Color(1, 1, 1, 0.04) if not e["is_player"] else Color(1, 0.55, 0.1, 0.22), Color(0, 0, 0, 0), 6, 2)
			rp.add_child(row)
			gv.add_child(rp)
			var alive: bool = e["node"].alive
			var kd: float = float(e["kills"]) / max(1.0, float(e["deaths"]))
			var vals := ["%d. %s%s" % [i + 1, e["name"], "" if alive else "  ☠"], str(e["lvl"]), str(e["kills"]), str(e["deaths"]), str(e["head"]), "%.2f" % kd,
				str(e["score"]) if m.mode != "gungame" else GS.WEAPONS[GS.GUNGAME_ORDER[min(e["gg"], GS.GUNGAME_ORDER.size() - 1)]]["name"], str(randi_range(18, 45) if not e["is_player"] else 12)]
			for k in vals.size():
				var l := UI.lbl(vals[k], 20, (Color.WHITE if alive else UI.DIM) if not e["is_player"] else UI.ACCENT2, "Rajdhani-Bold" if k == 0 else "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_LEFT if k == 0 else HORIZONTAL_ALIGNMENT_CENTER)
				l.custom_minimum_size = Vector2(cols[k][1], 28)
				row.add_child(l)
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
	var v := UI.vbox(14)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-180, -200)
	v.custom_minimum_size = Vector2(360, 0)
	pause_panel.add_child(v)
	v.add_child(UI.lbl("DURAKLATILDI", 44, Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.btn("DEVAM ET", func(): match_node.set_paused(false), 24, true, 360, 56))
	v.add_child(UI.btn("AYARLAR", _open_settings, 22, false, 360, 52))
	v.add_child(UI.btn("MAÇTAN AYRIL", func(): match_node.leave(), 22, false, 360, 52))

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
		# drop shadow + glass backing
		draw_circle(c + Vector2(0, 4), R + 12, Color(0, 0, 0, 0.35))
		draw_circle(c, R + 9, Color(0.03, 0.05, 0.08, 0.88))
		# map disc: polygon with UVs into the map texture (rotated so 'forward' is up)
		var pts := PackedVector2Array(); var uvs := PackedVector2Array(); var cols := PackedColorArray()
		var ts: Vector2 = tex.get_size() if tex else Vector2(512, 512)
		for i in 64:
			var a := i * TAU / 64.0
			var d := Vector2(cos(a), sin(a)) * R
			pts.append(c + d)
			var w := (d / k).rotated(-p.yaw) + pp
			uvs.append(w / ts)
			cols.append(Color.WHITE)
		if tex:
			draw_polygon(pts, cols, uvs, tex)
		# range rings + grid
		for rr in [R * 0.33, R * 0.66]:
			draw_arc(c, rr, 0, TAU, 48, Color(1, 1, 1, 0.06), 1.0, true)
		draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(1, 1, 1, 0.05), 1.0)
		draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(1, 1, 1, 0.05), 1.0)
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
			if q.length() > R - 6:
				q = q.normalized() * (R - 6)
				col.a = 0.6
			draw_circle(c + q, 6.0, Color(0, 0, 0, 0.6))
			draw_circle(c + q, 4.5, col)
			if not friendly:
				draw_arc(c + q, 9.0 + sin(Time.get_ticks_msec() * 0.012) * 2.0, 0, TAU, 20, Color(1, 0.25, 0.2, 0.7), 1.5, true)
		for kk in hud.pings.keys():
			hud.pings[kk] -= get_process_delta_time()
			if hud.pings[kk] <= 0:
				hud.pings.erase(kk)
		# player arrow
		var tri := PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 8), c + Vector2(0, 4), c + Vector2(-8, 8)])
		draw_colored_polygon(tri, Color(1, 0.78, 0.25))
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.7), 1.5, true)
		# outer ring + compass (rotates with the view)
		draw_arc(c, R + 1, 0, TAU, 96, Color(1, 1, 1, 0.22), 2.0, true)
		draw_arc(c, R + 8, 0, TAU, 96, Color(1, 0.55, 0.12, 0.85), 3.0, true)
		var f: Font = UI.font("Rajdhani-Bold")
		var dirs := [["K", 0.0], ["D", PI / 2], ["G", PI], ["B", -PI / 2]]
		for i in 36:
			var a2: float = i * TAU / 36.0 + p.yaw - PI / 2
			var r0 := R + (3.0 if i % 9 == 0 else 5.0)
			draw_line(c + Vector2(cos(a2), sin(a2)) * r0, c + Vector2(cos(a2), sin(a2)) * (R + 8), Color(1, 1, 1, 0.35 if i % 9 else 0.8), 1.0)
		for dd in dirs:
			var a3: float = float(dd[1]) + p.yaw - PI / 2
			var at := c + Vector2(cos(a3), sin(a3)) * (R - 12)
			var txt: String = dd[0]
			draw_circle(at, 9, Color(0.02, 0.03, 0.05, 0.8))
			draw_string(f, at + Vector2(-5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.75, 0.3) if txt == "K" else Color(1, 1, 1, 0.85))
		# map name plate
		var nm: String = GS.MAPS[m.map_id]["name"].to_upper()
		var pw := 170.0
		var pr := Rect2(c.x - pw / 2, c.y + R + 4, pw, 22)
		draw_rect(pr, Color(0.02, 0.03, 0.05, 0.85))
		draw_rect(Rect2(pr.position, Vector2(3, pr.size.y)), Color(1, 0.55, 0.12))
		draw_string(f, pr.position + Vector2(10, 17), nm, HORIZONTAL_ALIGNMENT_LEFT, pw - 14, 16, Color(1, 1, 1, 0.9))


class ScoreBar extends Control:
	## top-centre: angled team plates with score + progress to target, timer in the middle
	var hud

	func _plate(r: Rect2, left: bool) -> PackedVector2Array:
		var sk := 16.0
		if left:
			return PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.position + r.size, r.position + Vector2(sk, r.size.y)])
		return PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x - sk, r.size.y), r.position + Vector2(0, r.size.y)])

	func _draw() -> void:
		var m = hud.match_node
		var p = hud.player
		if m == null or p == null:
			return
		var W := size.x
		var f: Font = UI.font("Teko")
		var fb: Font = UI.font("Rajdhani-Bold")
		var cw := 120.0
		var cx := W / 2
		var sides: Array = []
		if m.teams:
			sides = [[GS.TEAMS["a"], int(m.team_score["a"]), GS.TEAM_COLORS["a"], p.team == "a"], [GS.TEAMS["b"], int(m.team_score["b"]), GS.TEAM_COLORS["b"], p.team == "b"]]
		else:
			var pe: Dictionary = m.entry(p)
			var best := 0
			for c in m.combatants:
				if c["node"] != p:
					best = max(best, int(c["kills"]) if m.mode != "gungame" else int(c["gg"]))
			var mine: int = int(pe.get("kills", 0)) if m.mode != "gungame" else int(pe.get("gg", 0))
			sides = [["SEN", mine, Color("3d8bff"), true], ["RAKİP LİDER", best, Color("ff8a1f"), false]]
		var target: float = max(float(m.target_score), 1.0) if m.mode != "gungame" else float(GS.GUNGAME_ORDER.size())
		var pw := (W - cw) / 2 - 6
		for i in 2:
			var sd: Array = sides[i]
			var left := i == 0
			var r := Rect2(0 if left else cx + cw / 2 + 6, 4, pw, 46)
			draw_colored_polygon(_plate(Rect2(r.position + Vector2(0, 3), r.size), left), Color(0, 0, 0, 0.3))
			var col: Color = sd[2]
			draw_colored_polygon(_plate(r, left), col.darkened(0.45 if sd[3] else 0.62))
			# progress toward target
			var k: float = clamp(float(sd[1]) / target, 0.0, 1.0)
			var pr := Rect2(r.position.x, r.position.y + r.size.y - 5, r.size.x * k, 5)
			if not left:
				pr.position.x = r.position.x + r.size.x * (1.0 - k)
			draw_rect(pr, col.lightened(0.2))
			var name_s: String = sd[0]
			var sc_s: String = str(sd[1])
			if left:
				draw_string(fb, r.position + Vector2(22, 31), name_s, HORIZONTAL_ALIGNMENT_LEFT, 150, 20, Color(1, 1, 1, 0.92))
				draw_string(f, r.position + Vector2(r.size.x - 74, 42), sc_s, HORIZONTAL_ALIGNMENT_RIGHT, 64, 50, Color.WHITE)
			else:
				draw_string(f, r.position + Vector2(10, 42), sc_s, HORIZONTAL_ALIGNMENT_LEFT, 64, 50, Color.WHITE)
				draw_string(fb, r.position + Vector2(r.size.x - 172, 31), name_s, HORIZONTAL_ALIGNMENT_RIGHT, 150, 20, Color(1, 1, 1, 0.92))
		# timer
		var tl := int(m.time_left)
		var hexr := Rect2(cx - cw / 2, 0, cw, 56)
		var hp := PackedVector2Array([hexr.position + Vector2(12, 0), hexr.position + Vector2(cw - 12, 0), hexr.position + Vector2(cw, 28), hexr.position + Vector2(cw - 12, 56), hexr.position + Vector2(12, 56), hexr.position + Vector2(0, 28)])
		draw_colored_polygon(hp, Color(0.02, 0.03, 0.05, 0.92))
		draw_polyline(hp + PackedVector2Array([hp[0]]), Color(1, 0.55, 0.12, 0.9), 2.0, true)
		var tc := Color.WHITE if tl > 30 else Color(1, 0.3, 0.25)
		draw_string(f, Vector2(cx - 60, 44), "%d:%02d" % [tl / 60, tl % 60], HORIZONTAL_ALIGNMENT_CENTER, 120, 44, tc)
		var goal: String = ("HEDEF %d" % int(m.target_score)) if m.mode != "gungame" else "SİLAH %d / %d" % [int(m.entry(p).get("gg", 0)) + 1, GS.GUNGAME_ORDER.size()]
		draw_string(fb, Vector2(cx - 60, 70), goal, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 1, 1, 0.55))


class HealthPanel extends Control:
	## skewed health / armour block with segmented bar and delayed damage trail
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

	func _sk(r: Rect2, sk: float) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(sk, 0), r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x - sk, r.size.y), r.position + Vector2(0, r.size.y)])

	func _draw() -> void:
		var p = hud.player
		if p == null:
			return
		var W := size.x; var H := size.y
		var team_c: Color = GS.TEAM_COLORS.get(p.team, Color(1, 0.55, 0.12))
		draw_colored_polygon(_sk(Rect2(4, 6, W - 4, H - 6), 18), Color(0, 0, 0, 0.3))
		draw_colored_polygon(_sk(Rect2(0, 0, W - 4, H - 6), 18), Color(0.025, 0.035, 0.055, 0.82))
		draw_colored_polygon(_sk(Rect2(0, 0, 6, H - 6), 0), team_c)
		var f: Font = UI.font("Teko")
		var fb: Font = UI.font("Rajdhani-Bold")
		var hp := int(ceil(p.health))
		var low: bool = hp < 30
		var hpc := Color(1, 0.28, 0.22) if low else Color.WHITE
		if low:
			hpc = hpc.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		# cross icon
		var ic := Vector2(36, 50)
		draw_rect(Rect2(ic + Vector2(-5, -15), Vector2(10, 30)), hpc)
		draw_rect(Rect2(ic + Vector2(-15, -5), Vector2(30, 10)), hpc)
		draw_string(f, Vector2(58, 76), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 74, hpc)
		# segmented health bar
		var bx := 160.0; var by := 26.0; var bw := W - bx - 34.0; var bh := 18.0
		var segs := 10
		var gap := 4.0
		var sw := (bw - gap * (segs - 1)) / segs
		for i in segs:
			var x := bx + i * (sw + gap)
			var r := Rect2(x, by, sw, bh)
			draw_colored_polygon(_sk(r, 5), Color(1, 1, 1, 0.08))
			var seg_lo := i * 10.0
			var tr: float = clamp((hud.hp_trail - seg_lo) / 10.0, 0.0, 1.0)
			var fl: float = clamp((hud.hp_shown - seg_lo) / 10.0, 0.0, 1.0)
			if tr > 0:
				draw_colored_polygon(_sk(Rect2(x, by, sw * tr, bh), 5 * tr), Color(1, 0.85, 0.6, 0.7))
			if fl > 0:
				var col := Color("38e07b").lerp(Color("ffcf3d"), clamp((70.0 - hud.hp_shown) / 40.0, 0.0, 1.0)).lerp(Color("ff3b3b"), clamp((35.0 - hud.hp_shown) / 25.0, 0.0, 1.0))
				draw_colored_polygon(_sk(Rect2(x, by, sw * fl, bh), 5 * fl), col)
				draw_rect(Rect2(x + 3, by + 2, sw * fl - 6, 3), Color(1, 1, 1, 0.25))
		# armour
		var ay := by + bh + 12
		var ar: float = clamp(float(p.armor) / 100.0, 0.0, 1.0)
		draw_colored_polygon(_sk(Rect2(bx, ay, bw, 9), 4), Color(1, 1, 1, 0.07))
		draw_colored_polygon(_sk(Rect2(bx, ay, bw * ar, 9), 4), Color("4aa3ff"))
		# shield icon + value
		var sc := Vector2(bx + bw + 16, ay + 4)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(-7, -7), sc + Vector2(7, -7), sc + Vector2(7, 1), sc + Vector2(0, 9), sc + Vector2(-7, 1)]), Color("4aa3ff"))
		draw_string(fb, Vector2(bx, ay + 34), "ZIRH %d" % int(p.armor), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.75, 1, 0.9))
		var nm: String = str(GS.profile["name"])
		var tn: String = GS.TEAMS.get(p.team, "") if p.team != "" else ""
		draw_string(fb, Vector2(bx + 90, ay + 34), nm + ("   " + tn if tn != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, bw - 80, 17, team_c.lightened(0.2))


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
		if icon.size != Vector2(190, 82):
			icon.position = Vector2(26, 8); icon.size = Vector2(190, 82)
		queue_redraw()

	func _draw() -> void:
		var p = hud.player
		if p == null or p.cur == "":
			return
		var W := size.x; var H := size.y
		draw_colored_polygon(_sk(Rect2(4, 6, W - 4, H - 6), 18), Color(0, 0, 0, 0.3))
		draw_colored_polygon(_sk(Rect2(0, 0, W - 4, H - 6), 18), Color(0.025, 0.035, 0.055, 0.82))
		draw_rect(Rect2(W - 10, 0, 6, H - 6), Color(1, 0.55, 0.12))
		var f: Font = UI.font("Teko")
		var fb: Font = UI.font("Rajdhani-Bold")
		var w: Dictionary = p.wdata
		var nm: String = GS.WEAPONS[p.cur]["name"]
		var lvl: int = GS.wlvl(p.cur)
		draw_string(fb, Vector2(30, H - 18), nm.to_upper() + ("  +%d" % lvl if lvl > 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, 200, 19, Color(1, 0.72, 0.35))
		var right := W - 26.0
		if w.get("melee", false):
			draw_string(f, Vector2(right - 150, 80), "YAKIN", HORIZONTAL_ALIGNMENT_RIGHT, 150, 46, Color.WHITE)
			draw_string(fb, Vector2(right - 200, 104), "SOL TIK: KES  •  SAĞ TIK: SAPLA", HORIZONTAL_ALIGNMENT_RIGHT, 200, 14, UI.DIM)
		elif w.get("throwable", false):
			draw_string(f, Vector2(right - 150, 84), "x%d" % p.grenades, HORIZONTAL_ALIGNMENT_RIGHT, 150, 64, Color.WHITE)
			draw_string(fb, Vector2(right - 220, 104), "BASILI TUT: NİŞAN  •  BIRAK: AT", HORIZONTAL_ALIGNMENT_RIGHT, 220, 14, UI.DIM)
		elif p.ammo.has(p.cur):
			var a: Array = p.ammo[p.cur]
			var mx: int = int(w.get("mag_max", 30))
			var lowa: bool = a[0] <= mx * 0.25
			var col := Color(1, 0.3, 0.25) if lowa else Color.WHITE
			draw_string(f, Vector2(right - 210, 86), "%d" % a[0], HORIZONTAL_ALIGNMENT_RIGHT, 140, 82, col)
			draw_string(f, Vector2(right - 66, 86), "/%d" % a[1], HORIZONTAL_ALIGNMENT_LEFT, 80, 36, Color(1, 1, 1, 0.55))
			# magazine pips
			var n: int = min(mx, 50)
			var per_row: int = 25 if n > 25 else n
			var pw := 5.0; var ph := 12.0; var gap := 2.0
			for i in n:
				var row: int = i / per_row
				var col_i: int = i % per_row
				var x := right - (col_i + 1) * (pw + gap)
				var y := 104.0 + row * (ph * 0.55 + 3)
				var filled: bool = i < int(round(float(a[0]) * n / max(mx, 1)))
				draw_rect(Rect2(x, y, pw, ph * (0.55 if n > 25 else 1.0)), (Color(1, 0.75, 0.3) if filled else Color(1, 1, 1, 0.12)))
			var mode := "OTO" if w.get("auto", false) else ("SÜRGÜ" if w.get("bolt", false) else ("POMPA" if w.get("shell_reload", false) else "TEK"))
			draw_string(fb, Vector2(right - 300, 40), mode, HORIZONTAL_ALIGNMENT_RIGHT, 80, 15, UI.DIM)
			if p.reload_t > 0:
				var rf: float = 1.0 - p.reload_t / max(p.reload_total, 0.01)
				draw_string(fb, Vector2(right - 300, 60), "DOLDURULUYOR", HORIZONTAL_ALIGNMENT_RIGHT, 120, 15, Color(1, 0.72, 0.35))
				draw_rect(Rect2(right - 300 + 0, 66, 120 * rf, 3), Color(1, 0.55, 0.12))
		# grenade counter chip
		if p.slots.has("bomba") and not w.get("throwable", false):
			var gx := 228.0
			draw_circle(Vector2(gx, 30), 9, Color(0.35, 0.42, 0.25))
			draw_rect(Rect2(gx - 3, 17, 6, 5), Color(0.5, 0.5, 0.5))
			draw_string(fb, Vector2(gx + 14, 36), "x%d" % p.grenades, HORIZONTAL_ALIGNMENT_LEFT, 40, 18, Color(1, 1, 1, 0.85))


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
const BUY_GROUPS := [["TÜFEKLER", ["ak47", "m4a1", "scar", "aug", "m249"]], ["HAFİF MAKİNALI", ["mp5", "p90", "ump45", "vector"]], ["POMPALI", ["spas"]],
	["KESKİN NİŞANCI", ["awp", "kar98"]], ["TABANCALAR", ["glock", "deagle", "revolver"]], ["BIÇAKLAR", ["knife", "karambit"]]]

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
	dim.color = Color(0, 0.01, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	buy_panel = dim
	var center_c := CenterContainer.new()
	center_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center_c)
	var p := UI.panel(Color(0.03, 0.04, 0.06, 0.94), Color(1, 0.55, 0.12, 0.6), 22, 6)
	p.custom_minimum_size = Vector2(1180, 0)
	center_c.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	var top := UI.hbox(12)
	v.add_child(top)
	var acc := ColorRect.new(); acc.color = UI.ACCENT; acc.custom_minimum_size = Vector2(6, 38)
	top.add_child(acc)
	top.add_child(UI.lbl("SİLAH SEÇİMİ", 36, Color.WHITE, "RussoOne-Regular"))
	top.add_child(UI.spacer())
	top.add_child(UI.lbl("[B] Kapat  •  Seçim anında kuşanılır ve sonraki doğuşta da kalır", 18, UI.DIM, "Rajdhani-SemiBold"))
	if mode == "gungame" or mode == "knife":
		v.add_child(UI.lbl("Bu modda silah değiştirilemez.", 26, UI.RED, "Rajdhani-Bold"))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var groups: Array = BUY_GROUPS.duplicate(true)
	var extra: Array = []
	for wid in GS.mod_weapon_model.keys():
		extra.append(wid)
	if extra.size() > 0:
		groups.append(["EKLENTİ SİLAHLARI", extra])
	for g in groups:
		var col := UI.vbox(8)
		col.custom_minimum_size = Vector2(370, 0)
		grid.add_child(col)
		col.add_child(UI.lbl(g[0], 20, UI.ACCENT2, "Rajdhani-Bold"))
		for id in g[1]:
			col.add_child(_buy_card(id, mode))

func _buy_card(id: String, mode: String) -> Control:
	var w: Dictionary = GS.WEAPONS[id]
	var cat: String = w["cat"]
	var owned: bool = GS.owned(id)
	var allowed: bool = owned and (mode != "sniper" or cat != "ana" or w.get("scope", false))
	var equipped: bool = player.slots.get(cat, "") == id
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(370, 104)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var border := UI.ACCENT if equipped else Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("normal", UI.sb(Color(0.07, 0.085, 0.12, 0.95) if allowed else Color(0.05, 0.05, 0.06, 0.9), border, 2 if equipped else 1, 5, 8))
	b.add_theme_stylebox_override("hover", UI.sb(Color(0.12, 0.1, 0.07, 0.98), UI.ACCENT2, 2, 5, 8))
	b.add_theme_stylebox_override("pressed", UI.sb(Color(0.2, 0.12, 0.04, 1), Color.WHITE, 2, 5, 8))
	var h := UI.hbox(10)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10; h.offset_right = -10; h.offset_top = 6; h.offset_bottom = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var th := Thumbs.make_rect(id, GS.wskin(id), Vector2(150, 76))
	if not allowed:
		th.modulate = Color(0.4, 0.4, 0.45, 0.8)
	h.add_child(th)
	var info := UI.vbox(2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var nm := UI.lbl(w["name"], 22, Color.WHITE if allowed else UI.DIM, "Rajdhani-Bold")
	info.add_child(nm)
	var st := GS.stats_for(id)
	if w.get("melee", false):
		info.add_child(UI.lbl("Hasar %d" % int(st["dmg"]), 16, UI.DIM))
	else:
		var r1 := UI.hbox(6); r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r1.add_child(UI.lbl("HSR", 14, UI.DIM, "Rajdhani-Bold"))
		r1.add_child(UI.bar(float(st["dmg"]) * float(w.get("pellets", 1)), 140.0, UI.ACCENT, 6, 140))
		info.add_child(r1)
		var r2 := UI.hbox(6); r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r2.add_child(UI.lbl("HIZ", 14, UI.DIM, "Rajdhani-Bold"))
		r2.add_child(UI.bar(float(w["rpm"]), 950.0, Color("4fb3ff"), 6, 140))
		info.add_child(r2)
	var tag := ""
	var tc := UI.DIM
	if equipped:
		tag = "KUŞANILDI"; tc = UI.GREEN
	elif not owned:
		tag = "🔒 MARKET  %s" % UI.money(int(w.get("price", 0))); tc = UI.GOLD
	elif not allowed:
		tag = "BU MODDA YOK"; tc = UI.RED
	else:
		tag = "SEÇ"; tc = UI.ACCENT2
	info.add_child(UI.lbl(tag, 16, tc, "Rajdhani-Bold"))
	for c in b.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.mouse_entered.connect(func(): SFX.play("ui_hover", -14))
	if allowed:
		b.pressed.connect(func():
			player.equip_from_menu(cat, id)
			SFX.play("buy", -6)
			toggle_buy(false))
	else:
		b.pressed.connect(func(): SFX.play("fail", -6))
	return b
