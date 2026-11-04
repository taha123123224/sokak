extends RefCounted
## YÖNETİM paneli (sadece sunucuda yönetici olarak kayıtlı hesap görür; her işlem sunucuda tekrar kontrol edilir
## ve sunucudaki yönetici kayıt defterine yazılır).
## Bölümler: GENEL BAKIŞ • OYUNCULAR • DUYURULAR • TOPLU HEDİYE • İŞLEM KAYDI

const RED := Color("ff3d5a")
const CARD := Color(0.06, 0.07, 0.095, 0.97)
const CARD2 := Color(0.085, 0.1, 0.13, 0.97)

var m
var tab := "genel"
var _stats_box: Control
var _side_box: Control
var _live_lbl: Label
var _list_box: VBoxContainer
var _count_lbl: Label
var _query := ""
var _filter := ""
var _sel := {}            # selected user row
var _anns_box: VBoxContainer
var _log_box: VBoxContainer

func _init(menu) -> void:
	m = menu

# ---------------------------------------------------------------- helpers
func _card(bg: Color = CARD, border: Color = Color(1, 1, 1, 0.06), pad: int = 16, radius: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(bg, border, 1, radius, pad))
	return p

func _pill(text: String, c: Color, size: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	var s := UI.sb(Color(c.r, c.g, c.b, 0.16), Color(c.r, c.g, c.b, 0.55), 1, 20, 0)
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 1; s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.add_child(UI.lbl(text, size, c.lightened(0.15), "Rajdhani-Bold"))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _avatar(name: String, d: int, online: bool) -> Control:
	var p := PanelContainer.new()
	var hue := float(abs(hash(name)) % 360) / 360.0
	p.add_theme_stylebox_override("panel", UI.sb(Color.from_hsv(hue, 0.55, 0.42), UI.GREEN if online else Color(1, 1, 1, 0.12), 2, d / 2, 0))
	p.custom_minimum_size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(name.substr(0, 1).to_upper(), int(d * 0.5), Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

func _rank_icon(rp: int, d: int) -> Control:
	var ri: Dictionary = GS.rank_info(rp)
	var t := TextureRect.new()
	t.texture = ri["icon"]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(d, d)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _n(row: Dictionary, k: String) -> int:
	var v = row.get(k)
	return 0 if v == null else int(float(str(v)))

func _ago(ts: String) -> String:
	if ts == "" or ts == "<null>":
		return "hiç"
	var s := Time.get_unix_time_from_system() - Time.get_unix_time_from_datetime_string(ts.substr(0, 19))
	if s < 90: return "şimdi"
	if s < 3600: return "%d dk önce" % int(s / 60)
	if s < 86400: return "%d sa önce" % int(s / 3600)
	return "%d gün önce" % int(s / 86400)

func _is_online(row: Dictionary) -> bool:
	var ls := str(row.get("last_seen", ""))
	return ls != "" and ls != "<null>" and Time.get_unix_time_from_system() - Time.get_unix_time_from_datetime_string(ls.substr(0, 19)) < 90

func _is_banned(row: Dictionary) -> bool:
	var b = row.get("banned_until")
	if b == null or str(b) == "":
		return false
	if str(b) == "infinity":
		return true
	return Time.get_unix_time_from_datetime_string(str(b).substr(0, 19)) > Time.get_unix_time_from_system()

# ---------------------------------------------------------------- page shell
func page() -> void:
	if not Online.is_admin:
		m.content.add_child(UI.lbl("Bu sayfa yalnızca yöneticiler içindir.", 24, UI.RED, "Rajdhani-Bold"))
		return
	m.soldier.visible = false
	var root := UI.hbox(16)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m._margin(root, 24, 14, 24, 20)
	m.content.add_child(root)
	root.add_child(_sidebar())
	var main := _card(Color(0.03, 0.035, 0.05, 0.94), Color(1, 1, 1, 0.05), 22, 12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	var v := UI.vbox(14)
	main.add_child(v)
	var titles := {"genel": ["GENEL BAKIŞ", "Sunucunun anlık durumu — her 5 saniyede yenilenir"],
		"oyuncu": ["OYUNCULAR", "Ara, incele, yasakla, hediye gönder"],
		"duyuru": ["DUYURULAR", "Herkesin ekranında anında görünen mesajlar"],
		"toplu": ["TOPLU HEDİYE", "Tüm oyunculara aynı anda hediye"],
		"log": ["İŞLEM KAYDI", "Yönetici hesaplarıyla yapılan her işlem burada saklanır"]}
	var th := UI.hbox(12)
	v.add_child(th)
	var tv := UI.vbox(0)
	th.add_child(tv)
	tv.add_child(UI.lbl(titles[tab][0], 34, Color.WHITE, "RussoOne-Regular"))
	tv.add_child(UI.lbl(titles[tab][1], 16, UI.DIM, "Rajdhani-SemiBold"))
	th.add_child(UI.spacer())
	_live_lbl = UI.lbl("● CANLI", 16, UI.GREEN, "Rajdhani-Bold")
	_live_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(_live_lbl)
	var ln := ColorRect.new(); ln.color = Color(1, 1, 1, 0.07); ln.custom_minimum_size = Vector2(0, 1)
	v.add_child(ln)
	match tab:
		"genel": _genel(v)
		"oyuncu": _oyuncu(v)
		"duyuru": _duyuru(v)
		"toplu": _toplu(v)
		"log": _log(v)

func _sidebar() -> Control:
	var p := _card(Color(0.04, 0.045, 0.065, 0.96), Color(RED.r, RED.g, RED.b, 0.35), 16, 12)
	p.custom_minimum_size = Vector2(260, 0)
	var v := UI.vbox(6)
	p.add_child(v)
	var hh := UI.hbox(10)
	v.add_child(hh)
	var badge := _card(Color(RED.r, RED.g, RED.b, 0.18), RED, 0, 8)
	badge.custom_minimum_size = Vector2(46, 46)
	var bl := UI.lbl("◆", 26, RED, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	hh.add_child(badge)
	var nv := UI.vbox(-4)
	hh.add_child(nv)
	nv.add_child(UI.lbl("YÖNETİM", 24, Color.WHITE, "RussoOne-Regular"))
	nv.add_child(UI.lbl("SOKAK: Operasyon", 14, UI.DIM, "Rajdhani-Bold"))
	v.add_child(UI.spacer(false, 0, 8))
	var me := _card(CARD2, Color(1, 1, 1, 0.06), 10, 8)
	v.add_child(me)
	var mh := UI.hbox(10)
	me.add_child(mh)
	mh.add_child(_avatar(Online.username, 38, true))
	var mv := UI.vbox(-4)
	mh.add_child(mv)
	mv.add_child(UI.lbl(Online.username, 18, Color.WHITE, "Rajdhani-Bold"))
	mv.add_child(UI.lbl("KURUCU YÖNETİCİ", 13, RED, "Rajdhani-Bold"))
	v.add_child(UI.spacer(false, 0, 10))
	for it in [["genel", "▣  GENEL BAKIŞ"], ["oyuncu", "☰  OYUNCULAR"], ["duyuru", "✉  DUYURULAR"], ["toplu", "★  TOPLU HEDİYE"], ["log", "≡  İŞLEM KAYDI"]]:
		var key: String = it[0]
		var b := Button.new()
		b.text = "  " + it[1]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_override("font", UI.font("Rajdhani-Bold"))
		b.add_theme_font_size_override("font_size", 18)
		var on := tab == key
		b.add_theme_stylebox_override("normal", UI.sb(Color(RED.r, RED.g, RED.b, 0.2) if on else Color(0, 0, 0, 0), RED if on else Color(0, 0, 0, 0), 1, 8, 8))
		b.add_theme_stylebox_override("hover", UI.sb(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), 1, 8, 8))
		b.add_theme_stylebox_override("pressed", UI.sb(Color(RED.r, RED.g, RED.b, 0.3), RED, 1, 8, 8))
		b.add_theme_color_override("font_color", Color.WHITE if on else UI.TEXT)
		b.pressed.connect(func(): tab = key; m.show_page("admin"))
		v.add_child(b)
	v.add_child(UI.spacer())
	var sec := _card(Color(0.05, 0.12, 0.08, 0.6), Color(UI.GREEN.r, UI.GREEN.g, UI.GREEN.b, 0.35), 10, 8)
	v.add_child(sec)
	var sv := UI.vbox(2)
	sec.add_child(sv)
	sv.add_child(UI.lbl("✔ GÜVENLİ BAĞLANTI", 15, UI.GREEN, "Rajdhani-Bold"))
	var sl := UI.lbl("Yetki her işlemde sunucuda kontrol edilir. Şifre oyunda saklanmaz.", 13, UI.DIM, "Rajdhani-SemiBold")
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(220, 0)
	sv.add_child(sl)
	return p

# ---------------------------------------------------------------- GENEL
func _genel(v: VBoxContainer) -> void:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	v.add_child(g)
	_stats_box = g
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	_side_box = row
	var tm := Timer.new(); tm.wait_time = 5.0; tm.autostart = true
	tm.timeout.connect(_stats_refresh)
	v.add_child(tm)
	_stats_refresh()

func _stats_refresh() -> void:
	if _stats_box == null or not is_instance_valid(_stats_box):
		return
	var r: Dictionary = await Online.admin("stats")
	if not is_instance_valid(_stats_box):
		return
	if is_instance_valid(_live_lbl):
		_live_lbl.modulate.a = 0.35
		_live_lbl.create_tween().tween_property(_live_lbl, "modulate:a", 1.0, 0.6)
	UI.clear(_stats_box)
	if not r["ok"]:
		_stats_box.add_child(UI.lbl(str(r["err"]), 18, UI.RED))
		return
	var d: Dictionary = r["res"]
	for it in [["ŞU AN ÇEVRİMİÇİ", "online", UI.GREEN, "●"], ["MAÇTA OYNAYAN", "in_match", UI.ACCENT, "▶"],
			["AKTİF ODA", "rooms", UI.ACCENT2, "▣"], ["SON 24 SAAT AKTİF", "active_day", Color("7fd1ff"), "◷"],
			["TOPLAM HESAP", "total", Color.WHITE, "☰"], ["BUGÜN KAYIT", "today", Color("b48cff"), "+"],
			["BU HAFTA KAYIT", "week", Color("ff9edb"), "+"], ["YASAKLI", "banned", UI.RED, "⊘"]]:
		var c: Color = it[2]
		var card := _card(CARD, Color(c.r, c.g, c.b, 0.28), 0, 10)
		card.custom_minimum_size = Vector2(260, 118)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := UI.hbox(0)
		card.add_child(hb)
		var acc := ColorRect.new(); acc.color = c; acc.custom_minimum_size = Vector2(5, 0)
		hb.add_child(acc)
		var cv := UI.vbox(-6)
		m._margin(cv, 18, 12, 14, 10)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(cv)
		var top := UI.hbox(6)
		cv.add_child(top)
		top.add_child(UI.lbl(it[0], 15, UI.DIM, "Rajdhani-Bold"))
		top.add_child(UI.spacer())
		top.add_child(UI.lbl(it[3], 20, c, "Rajdhani-Bold"))
		cv.add_child(UI.lbl(UI.money(int(d.get(it[1], 0))), 60, c if it[1] != "total" else Color.WHITE, "Teko"))
		_stats_box.add_child(card)
	# lower row: top players + economy
	if _side_box == null or not is_instance_valid(_side_box):
		return
	UI.clear(_side_box)
	var tp := _card(CARD, Color(1, 1, 1, 0.06), 16, 10)
	tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_box.add_child(tp)
	var tv := UI.vbox(8)
	tp.add_child(tv)
	tv.add_child(UI.lbl("EN YÜKSEK RÜTBELİ OYUNCULAR", 18, UI.GOLD, "Rajdhani-Bold"))
	var i := 1
	for t in d.get("top", []):
		var h := UI.hbox(12)
		tv.add_child(h)
		h.add_child(UI.lbl("#%d" % i, 22, UI.GOLD if i == 1 else UI.DIM, "Teko"))
		h.add_child(_rank_icon(_n(t, "rp"), 34))
		var nm := UI.lbl(str(t.get("username", "")), 19, Color.WHITE, "Rajdhani-Bold")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var ri: Dictionary = GS.rank_info(_n(t, "rp"))
		h.add_child(UI.lbl(str(ri["name"]), 16, ri["color"], "Rajdhani-Bold"))
		h.add_child(UI.lbl("%d RP" % _n(t, "rp"), 17, UI.ACCENT2, "Rajdhani-Bold"))
		i += 1
	var ec := _card(CARD, Color(1, 1, 1, 0.06), 16, 10)
	ec.custom_minimum_size = Vector2(380, 0)
	_side_box.add_child(ec)
	var ev := UI.vbox(6)
	ec.add_child(ev)
	ev.add_child(UI.lbl("EKONOMİ", 18, UI.GOLD, "Rajdhani-Bold"))
	ev.add_child(UI.lbl("◉ " + UI.money(int(d.get("gold_total", 0))), 46, UI.GOLD, "Teko"))
	ev.add_child(UI.lbl("Oyunculardaki toplam altın", 15, UI.DIM, "Rajdhani-SemiBold"))
	var tot := maxi(1, int(d.get("total", 1)))
	ev.add_child(UI.spacer(false, 0, 6))
	ev.add_child(UI.lbl("Son 24 saatte giren oyuncu oranı: %%%d" % int(100.0 * int(d.get("active_day", 0)) / tot), 16, UI.TEXT, "Rajdhani-Bold"))
	ev.add_child(UI.bar(float(d.get("active_day", 0)), float(tot), UI.GREEN, 10))

# ---------------------------------------------------------------- OYUNCULAR
func _oyuncu(v: VBoxContainer) -> void:
	var sh := UI.hbox(10)
	v.add_child(sh)
	var le := LineEdit.new()
	le.placeholder_text = "⌕  Kullanıcı adı ara…"
	le.text = _query
	le.custom_minimum_size = Vector2(380, 44)
	le.max_length = 32
	sh.add_child(le)
	var go := func(): _query = le.text.strip_edges(); _list_refresh()
	le.text_submitted.connect(func(_t): go.call())
	sh.add_child(UI.btn("ARA", go, 18, true, 100, 44))
	for it in [["", "HEPSİ"], ["online", "● ÇEVRİMİÇİ"], ["banned", "⊘ YASAKLI"]]:
		var f: String = it[0]
		sh.add_child(UI.btn(it[1], func(): _filter = f; m.show_page("admin"), 16, _filter == f, 0, 44))
	sh.add_child(UI.spacer())
	_count_lbl = UI.lbl("", 16, UI.DIM, "Rajdhani-Bold")
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_count_lbl)
	sh.add_child(UI.btn("⟳", func(): _list_refresh(), 20, false, 48, 44))
	var body := UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var lc := _card(CARD, Color(1, 1, 1, 0.05), 8, 10)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(lc)
	var lv := UI.vbox(4)
	lc.add_child(lv)
	var hdr := UI.hbox(0)
	m._margin(hdr, 12, 4, 12, 4)
	lv.add_child(hdr)
	for c in [["OYUNCU", 330], ["RÜTBE", 190], ["SEVİYE", 90], ["ALTIN", 150], ["SON GÖRÜLME", 140], ["DURUM", 120]]:
		var l := UI.lbl(c[0], 14, UI.DIM, "Rajdhani-Bold")
		l.custom_minimum_size = Vector2(c[1], 0)
		hdr.add_child(l)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 520)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	_list_box = UI.vbox(4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list_box)
	var ac := ScrollContainer.new()
	ac.custom_minimum_size = Vector2(450, 0)
	ac.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(ac)
	ac.add_child(_actions_panel())
	_list_refresh()

func _list_refresh() -> void:
	if _list_box == null or not is_instance_valid(_list_box):
		return
	var r: Dictionary = await Online.admin("users", {"q": _query, "f": _filter})
	if not is_instance_valid(_list_box):
		return
	UI.clear(_list_box)
	if not r["ok"]:
		_list_box.add_child(UI.lbl(str(r["err"]), 18, UI.RED))
		return
	var rows = r["res"]
	if not (rows is Array):
		return
	if is_instance_valid(_count_lbl):
		_count_lbl.text = "%d oyuncu" % rows.size()
	if rows.is_empty():
		_list_box.add_child(UI.lbl("Sonuç yok.", 18, UI.DIM, "Rajdhani-Bold"))
	for row in rows:
		var online := _is_online(row)
		var banned := _is_banned(row)
		var on: bool = str(_sel.get("id", "")) == str(row["id"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 54)
		var bg := Color(0.22, 0.05, 0.08, 0.7) if banned else CARD2
		b.add_theme_stylebox_override("normal", UI.sb(bg, UI.ACCENT if on else Color(1, 1, 1, 0.04), 2 if on else 1, 8, 6))
		b.add_theme_stylebox_override("hover", UI.sb(bg.lightened(0.06), UI.ACCENT2, 1, 8, 6))
		b.add_theme_stylebox_override("pressed", UI.sb(bg, UI.ACCENT, 2, 8, 6))
		var h := UI.hbox(0)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var name := str(row["username"])
		var c1 := UI.hbox(10)
		c1.custom_minimum_size = Vector2(330, 0)
		c1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c1)
		var av := _avatar(name, 36, online)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c1.add_child(av)
		var nl := UI.lbl(name, 19, Color.WHITE, "Rajdhani-Bold")
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c1.add_child(nl)
		if row.get("admin", false):
			c1.add_child(_pill("YÖNETİCİ", RED, 12))
		var rp := _n(row, "rp")
		var ri: Dictionary = GS.rank_info(rp)
		var c2 := UI.hbox(6)
		c2.custom_minimum_size = Vector2(190, 0)
		c2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c2)
		var ic := _rank_icon(rp, 30)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c2.add_child(ic)
		var rl := UI.lbl(str(ri["name"]), 16, ri["color"], "Rajdhani-Bold")
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rl.clip_text = true
		rl.custom_minimum_size = Vector2(150, 0)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c2.add_child(rl)
		for c in [["Sv %d" % maxi(1, _n(row, "level")), 90, UI.ACCENT2], ["◉ " + UI.money(_n(row, "gold")), 150, UI.GOLD],
				[_ago(str(row.get("last_seen", ""))), 140, UI.TEXT]]:
			var l := UI.lbl(c[0], 17, c[2], "Rajdhani-Bold")
			l.custom_minimum_size = Vector2(c[1], 0)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			l.clip_text = true
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(l)
		var st := "YASAKLI" if banned else ("MAÇTA" if online and str(row.get("status", "")) == "match" else ("ÇEVRİMİÇİ" if online else "ÇEVRİMDIŞI"))
		h.add_child(_pill(st, UI.RED if banned else (UI.ACCENT if st == "MAÇTA" else (UI.GREEN if online else UI.DIM)), 13))
		var rr: Dictionary = row
		b.pressed.connect(func(): _sel = rr; m.show_page("admin"))
		_list_box.add_child(b)

func _stat_cell(g: GridContainer, label: String, value: String, c: Color) -> void:
	var p := _card(CARD2, Color(1, 1, 1, 0.04), 8, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(-6)
	p.add_child(v)
	v.add_child(UI.lbl(value, 30, c, "Teko"))
	v.add_child(UI.lbl(label, 13, UI.DIM, "Rajdhani-Bold"))
	g.add_child(p)

func _actions_panel() -> Control:
	var p := _card(CARD, Color(1, 1, 1, 0.06), 18, 10)
	p.custom_minimum_size = Vector2(440, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10)
	p.add_child(v)
	if _sel.is_empty():
		v.add_child(UI.spacer(false, 0, 40))
		v.add_child(UI.lbl("☰", 64, Color(1, 1, 1, 0.15), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UI.lbl("Bir oyuncu seç", 22, UI.TEXT, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UI.lbl("Bilgileri, yasaklama ve hediye seçenekleri burada görünür.", 15, UI.DIM, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER))
		return p
	var uid: String = str(_sel["id"])
	var name := str(_sel["username"])
	var online := _is_online(_sel)
	var banned := _is_banned(_sel)
	var hh := UI.hbox(14)
	v.add_child(hh)
	hh.add_child(_avatar(name, 64, online))
	var nv := UI.vbox(2)
	hh.add_child(nv)
	nv.add_child(UI.lbl(name, 28, Color.WHITE, "RussoOne-Regular"))
	var pills := UI.hbox(6)
	nv.add_child(pills)
	pills.add_child(_pill("YASAKLI" if banned else ("ÇEVRİMİÇİ" if online else "ÇEVRİMDIŞI"), UI.RED if banned else (UI.GREEN if online else UI.DIM), 13))
	var ri: Dictionary = GS.rank_info(_n(_sel, "rp"))
	pills.add_child(_pill(str(ri["name"]), ri["color"], 13))
	hh.add_child(UI.spacer())
	hh.add_child(_rank_icon(_n(_sel, "rp"), 58))
	v.add_child(UI.lbl("Kayıt: %s   •   Son görülme: %s" % [str(_sel.get("created_at", "")).substr(0, 10), _ago(str(_sel.get("last_seen", "")))], 14, UI.DIM, "Rajdhani-SemiBold"))
	var g := GridContainer.new(); g.columns = 4
	g.add_theme_constant_override("h_separation", 6); g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var k := _n(_sel, "kills"); var d := _n(_sel, "deaths")
	_stat_cell(g, "ÖLDÜRME", str(k), Color.WHITE)
	_stat_cell(g, "ÖLÜM", str(d), Color.WHITE)
	_stat_cell(g, "K/Ö", "%.2f" % (float(k) / maxf(1.0, float(d))), UI.ACCENT2)
	_stat_cell(g, "GALİBİYET", str(_n(_sel, "wins")), UI.GREEN)
	_stat_cell(g, "SEVİYE", str(maxi(1, _n(_sel, "level"))), UI.ACCENT2)
	_stat_cell(g, "RP", str(_n(_sel, "rp")), ri["color"])
	_stat_cell(g, "SİLAH", str(_n(_sel, "weapons")), Color.WHITE)
	_stat_cell(g, "ALTIN", UI.money(_n(_sel, "gold")), UI.GOLD)
	if banned:
		var bp := _card(Color(0.3, 0.04, 0.07, 0.6), UI.RED, 10, 8)
		v.add_child(bp)
		var bt := str(_sel["banned_until"])
		bp.add_child(UI.lbl("⊘ YASAKLI — %s\nSebep: %s" % ["süresiz" if bt == "infinity" else bt.substr(0, 16).replace("T", " "), str(_sel.get("ban_reason", ""))], 16, Color("ffb3bf"), "Rajdhani-Bold"))
	if not _sel.get("admin", false):
		v.add_child(_section("⊘  YASAKLA", UI.RED))
		var reason := LineEdit.new(); reason.placeholder_text = "Sebep (ör. hile, küfür)"; reason.custom_minimum_size = Vector2(0, 40); reason.max_length = 120
		v.add_child(reason)
		var bh := UI.hbox(6)
		v.add_child(bh)
		for it in [["1 SAAT", 1], ["1 GÜN", 24], ["7 GÜN", 168], ["SÜRESİZ", 0]]:
			var hrs: int = it[1]
			var bb := UI.btn(it[0], func(): _do("ban", {"id": uid, "hours": hrs, "reason": reason.text if reason.text.strip_edges() != "" else "Kurallara aykırı davranış"}, "%s yasaklandı" % name), 15, false, 0, 38)
			bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bh.add_child(bb)
		var bh2 := UI.hbox(6)
		v.add_child(bh2)
		if banned:
			var ub := UI.btn("✔ YASAĞI KALDIR", func(): _do("unban", {"id": uid}, "Yasak kaldırıldı"), 15, true, 0, 38)
			ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bh2.add_child(ub)
		var del := UI.btn("✖ HESABI SİL", func(): _confirm_delete(uid, name), 15, false, 0, 38)
		del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		del.add_theme_color_override("font_color", UI.RED)
		bh2.add_child(del)
	v.add_child(_section("★  HEDİYE GÖNDER", UI.GOLD))
	v.add_child(_gift_form(uid))
	return p

func _apply_preset(fields: Dictionary, vals: Dictionary) -> void:
	for kk in vals:
		fields[kk].value = vals[kk]

func _section(t: String, c: Color) -> Control:
	var h := UI.hbox(8)
	var l := UI.lbl(t, 17, c, "Rajdhani-Bold")
	h.add_child(l)
	var ln := ColorRect.new(); ln.color = Color(c.r, c.g, c.b, 0.25); ln.custom_minimum_size = Vector2(0, 1)
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ln)
	return h

func _confirm_delete(uid: String, name: String) -> void:
	var mv: VBoxContainer = m._modal(600, 280)
	mv.add_child(UI.lbl("✖ %s hesabı KALICI olarak silinsin mi?" % name, 24, UI.RED, "Rajdhani-Bold"))
	mv.add_child(UI.lbl("Bu işlem geri alınamaz: profil, silahlar ve istatistikler silinir.", 17, UI.DIM))
	var le := LineEdit.new()
	le.placeholder_text = "Onay için kullanıcı adını yaz: " + name
	le.custom_minimum_size = Vector2(0, 42)
	mv.add_child(le)
	var h := UI.hbox(10)
	mv.add_child(h)
	h.add_child(UI.btn("EVET, SİL", func():
		if le.text.strip_edges() != name:
			m._toast("Kullanıcı adı eşleşmedi", UI.RED); return
		m._close_modal(); _sel = {}; _do("delete", {"id": uid}, "Hesap silindi"), 18, true, 200, 46))
	h.add_child(UI.btn("VAZGEÇ", m._close_modal, 18, false, 160, 46))

func _gift_form(target: String) -> Control:
	var v := UI.vbox(8)
	var fields := {}
	var presets := UI.hbox(6)
	v.add_child(presets)
	var g := GridContainer.new(); g.columns = 4
	g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	for it in [["gold", "◉ Altın", UI.GOLD], ["crates", "▣ Kasa", UI.ACCENT], ["demir", "Demir", Color("b8c0cc")], ["krom", "Krom", Color("d9e6f2")],
			["titanyum", "Titanyum", Color("9fd3ff")], ["kobalt", "Kobalt", Color("6f8cff")]]:
		g.add_child(UI.lbl(it[1], 16, it[2], "Rajdhani-Bold"))
		var sb := SpinBox.new(); sb.max_value = 1000000 if it[0] == "gold" else 10000; sb.step = 1; sb.custom_minimum_size = Vector2(130, 36)
		g.add_child(sb)
		fields[it[0]] = sb
	for pr in [["+1.000 ◉", {"gold": 1000}], ["+10.000 ◉", {"gold": 10000}], ["MALZEME PAKETİ", {"demir": 50, "krom": 25, "titanyum": 10, "kobalt": 3}], ["5 KASA", {"crates": 5}]]:
		var vals: Dictionary = pr[1]
		var pb := UI.btn(pr[0], func(): _apply_preset(fields, vals), 14, false, 0, 32)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(pb)
	var g2 := GridContainer.new(); g2.columns = 2
	g2.add_theme_constant_override("h_separation", 8); g2.add_theme_constant_override("v_separation", 6)
	v.add_child(g2)
	g2.add_child(UI.lbl("Silah", 16, UI.TEXT, "Rajdhani-Bold"))
	var wopt := OptionButton.new(); wopt.add_item("— yok —"); wopt.custom_minimum_size = Vector2(240, 36)
	for id in GS.WEAPONS.keys():
		if not GS.WEAPONS[id].get("throwable", false):
			wopt.add_item(str(GS.WEAPONS[id]["name"])); wopt.set_item_metadata(wopt.item_count - 1, id)
	g2.add_child(wopt)
	g2.add_child(UI.lbl("Süre", 16, UI.TEXT, "Rajdhani-Bold"))
	var dopt := OptionButton.new()
	for it in [["Süresiz", 0], ["3 gün", 3], ["7 gün", 7], ["30 gün", 30]]:
		dopt.add_item(it[0]); dopt.set_item_metadata(dopt.item_count - 1, it[1])
	g2.add_child(dopt)
	g2.add_child(UI.lbl("Stil", 16, UI.TEXT, "Rajdhani-Bold"))
	var sopt := OptionButton.new(); sopt.add_item("— yok —")
	for sk in GS.SKINS.keys():
		if sk != "std":
			sopt.add_item(str(GS.SKINS[sk]["name"])); sopt.set_item_metadata(sopt.item_count - 1, sk)
	g2.add_child(sopt)
	var msg := LineEdit.new(); msg.placeholder_text = "Mesaj (ör. Bayramın kutlu olsun!)"; msg.custom_minimum_size = Vector2(0, 38); msg.max_length = 120
	v.add_child(msg)
	v.add_child(UI.lbl("Stil, seçilen silaha verilir (oyuncuda yoksa silahla birlikte gelir).", 13, UI.DIM, "Rajdhani-SemiBold"))
	var send := func():
		var gift := {"gold": int(fields["gold"].value), "crates": int(fields["crates"].value),
			"mats": {"demir": int(fields["demir"].value), "krom": int(fields["krom"].value), "titanyum": int(fields["titanyum"].value), "kobalt": int(fields["kobalt"].value)},
			"msg": msg.text if msg.text.strip_edges() != "" else "Yöneticiden hediye!"}
		if wopt.selected > 0:
			gift["weapon"] = wopt.get_item_metadata(wopt.selected)
			gift["days"] = dopt.get_item_metadata(dopt.selected)
		if sopt.selected > 0:
			gift["skin"] = sopt.get_item_metadata(sopt.selected)
			if wopt.selected > 0:
				gift["skin_wid"] = gift["weapon"]
		var empty: bool = gift["gold"] == 0 and gift["crates"] == 0 and not gift.has("weapon") and not gift.has("skin") \
			and gift["mats"].values().all(func(x): return x == 0)
		if empty:
			m._toast("Hediye boş — bir şey seç", UI.RED); return
		if target == "all":
			var mv: VBoxContainer = m._modal(560, 220)
			mv.add_child(UI.lbl("Bu hediye TÜM oyunculara gönderilsin mi?", 22, UI.GOLD, "Rajdhani-Bold"))
			var h := UI.hbox(10)
			mv.add_child(h)
			h.add_child(UI.btn("EVET, GÖNDER", func(): m._close_modal(); _do("gift", {"id": "all", "gift": gift}, "Herkese hediye gönderildi"), 18, true, 220, 46))
			h.add_child(UI.btn("VAZGEÇ", m._close_modal, 18, false, 160, 46))
		else:
			_do("gift", {"id": target, "gift": gift}, "Hediye gönderildi")
	v.add_child(UI.btn("★ HEDİYEYİ GÖNDER" + ("  (TÜM OYUNCULAR)" if target == "all" else ""), send, 18, true, 0, 48))
	return v

# ---------------------------------------------------------------- DUYURU
func _duyuru(v: VBoxContainer) -> void:
	var body := UI.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var cp := _card(CARD, Color(1, 1, 1, 0.06), 18, 10)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cp)
	var cv := UI.vbox(10)
	cp.add_child(cv)
	cv.add_child(UI.lbl("YENİ DUYURU", 18, UI.ACCENT, "Rajdhani-Bold"))
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 150)
	te.placeholder_text = "Örn: Bu akşam 21:00'de 2x altın etkinliği!"
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	cv.add_child(te)
	var cnt := UI.lbl("0 / 300", 14, UI.DIM, "Rajdhani-Bold")
	cv.add_child(cnt)
	cv.add_child(UI.lbl("ÖNİZLEME", 15, UI.DIM, "Rajdhani-Bold"))
	var pv := _card(Color(0.08, 0.06, 0.02, 0.95), UI.ACCENT, 14, 8)
	cv.add_child(pv)
	var pvv := UI.vbox(2)
	pv.add_child(pvv)
	pvv.add_child(UI.lbl("◆ DUYURU", 16, UI.ACCENT, "Rajdhani-Bold"))
	var pl := UI.lbl("…", 20, Color.WHITE, "Rajdhani-Bold")
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pvv.add_child(pl)
	te.text_changed.connect(func():
		if te.text.length() > 300: te.text = te.text.substr(0, 300)
		cnt.text = "%d / 300" % te.text.length()
		pl.text = te.text if te.text.strip_edges() != "" else "…")
	cv.add_child(UI.btn("◆ DUYURU YAYINLA", func():
		var t := te.text.strip_edges()
		if t.length() < 2: return
		await _do("announce", {"text": t}, "Duyuru yayınlandı"); te.text = ""; pl.text = "…"; _anns_refresh(), 20, true, 0, 52))
	var hp := _card(CARD, Color(1, 1, 1, 0.06), 16, 10)
	hp.custom_minimum_size = Vector2(520, 0)
	body.add_child(hp)
	var hv := UI.vbox(8)
	hp.add_child(hv)
	hv.add_child(UI.lbl("SON DUYURULAR", 18, UI.TEXT, "Rajdhani-Bold"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hv.add_child(sc)
	_anns_box = UI.vbox(6)
	_anns_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_anns_box)
	_anns_refresh()

func _anns_refresh() -> void:
	if _anns_box == null or not is_instance_valid(_anns_box):
		return
	var r: Dictionary = await Online.admin("anns")
	if not is_instance_valid(_anns_box):
		return
	UI.clear(_anns_box)
	if not r["ok"] or not (r["res"] is Array):
		_anns_box.add_child(UI.lbl(str(r.get("err", "")), 16, UI.RED))
		return
	if r["res"].is_empty():
		_anns_box.add_child(UI.lbl("Henüz duyuru yok.", 16, UI.DIM, "Rajdhani-Bold"))
	for a in r["res"]:
		var c := _card(CARD2, Color(1, 1, 1, 0.05), 10, 8)
		_anns_box.add_child(c)
		var h := UI.hbox(8)
		c.add_child(h)
		var tv := UI.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		var tl := UI.lbl(str(a.get("text", "")), 17, Color.WHITE, "Rajdhani-Bold")
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(tl)
		tv.add_child(UI.lbl(_ago(str(a.get("created_at", ""))), 13, UI.DIM, "Rajdhani-SemiBold"))
		var aid := int(a.get("id", 0))
		var db := UI.btn("✖", func(): await _do("ann_del", {"ann": aid}, "Duyuru silindi"); _anns_refresh(), 16, false, 40, 36)
		db.add_theme_color_override("font_color", UI.RED)
		db.tooltip_text = "Duyuruyu sil (yeni girenler görmez)"
		h.add_child(db)

# ---------------------------------------------------------------- TOPLU
func _toplu(v: VBoxContainer) -> void:
	var w := _card(Color(0.1, 0.08, 0.02, 0.8), UI.GOLD, 12, 8)
	v.add_child(w)
	w.add_child(UI.lbl("★ Bu bölümden gönderilen hediye TÜM oyunculara (yasaklılar hariç) aynı anda gider ve gelen kutularına düşer.", 17, UI.GOLD, "Rajdhani-Bold"))
	var p := _card(CARD, Color(1, 1, 1, 0.06), 18, 10)
	p.custom_minimum_size = Vector2(560, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(p)
	p.add_child(_gift_form("all"))

# ---------------------------------------------------------------- LOG
const ACT_NAMES := {"ban": "YASAKLADI", "unban": "YASAK KALDIRDI", "delete": "HESAP SİLDİ", "announce": "DUYURU", "ann_del": "DUYURU SİLDİ", "gift": "HEDİYE"}

func _log(v: VBoxContainer) -> void:
	var lc := _card(CARD, Color(1, 1, 1, 0.05), 10, 10)
	lc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lc)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 600)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lc.add_child(sc)
	_log_box = UI.vbox(4)
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_log_box)
	var r: Dictionary = await Online.admin("log")
	if not is_instance_valid(_log_box):
		return
	if not r["ok"] or not (r["res"] is Array):
		_log_box.add_child(UI.lbl(str(r.get("err", "")), 16, UI.RED))
		return
	if r["res"].is_empty():
		_log_box.add_child(UI.lbl("Henüz kayıt yok.", 16, UI.DIM, "Rajdhani-Bold"))
	for e in r["res"]:
		var c := _card(CARD2, Color(1, 1, 1, 0.04), 10, 6)
		_log_box.add_child(c)
		var h := UI.hbox(14)
		c.add_child(h)
		var act := str(e.get("action", ""))
		var col: Color = UI.RED if act in ["ban", "delete"] else (UI.GOLD if act == "gift" else (UI.GREEN if act == "unban" else UI.ACCENT2))
		var pl := _pill(ACT_NAMES.get(act, act.to_upper()), col, 13)
		pl.custom_minimum_size = Vector2(150, 0)
		h.add_child(pl)
		var who := UI.lbl(str(e.get("admin", "")), 16, UI.DIM, "Rajdhani-Bold")
		who.custom_minimum_size = Vector2(160, 0)
		h.add_child(who)
		var tgt := str(e.get("target", ""))
		var info = e.get("info", {})
		var detail := ""
		if info is Dictionary:
			if info.has("text"): detail = str(info["text"])
			elif info.has("reason"): detail = "%s  (%s)" % [str(info["reason"]), "süresiz" if _n(info, "hours") == 0 else "%d saat" % _n(info, "hours")]
			elif info.has("gift") and info["gift"] is Dictionary: detail = _gift_text(info["gift"])
		var tl := UI.lbl(("%s  •  " % tgt if tgt != "" and tgt.length() < 40 else ("TÜM OYUNCULAR  •  " if tgt == "all" else "")) + detail, 16, Color.WHITE, "Rajdhani-Bold")
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.clip_text = true
		h.add_child(tl)
		h.add_child(UI.lbl(_ago(str(e.get("at", ""))), 14, UI.DIM, "Rajdhani-SemiBold"))

func _gift_text(g: Dictionary) -> String:
	var parts := []
	if _n(g, "gold") > 0: parts.append("◉ %s" % UI.money(_n(g, "gold")))
	if _n(g, "crates") > 0: parts.append("%d kasa" % _n(g, "crates"))
	if g.get("mats") is Dictionary:
		for k in g["mats"]:
			if _n(g["mats"], k) > 0: parts.append("%d %s" % [_n(g["mats"], k), k])
	if g.has("weapon"): parts.append(str(GS.WEAPONS.get(g["weapon"], {}).get("name", g["weapon"])))
	if g.has("skin"): parts.append("stil: " + str(GS.SKINS.get(g["skin"], {}).get("name", g["skin"])))
	return ", ".join(parts)

func _do(a: String, args: Dictionary, okmsg: String) -> void:
	var r: Dictionary = await Online.admin(a, args)
	if r["ok"]:
		m._toast(okmsg + (" (%d oyuncu)" % int(r["res"].get("count", 0)) if r["res"] is Dictionary and r["res"].has("count") else ""), UI.GREEN)
		if tab == "oyuncu":
			if a == "ban" or a == "unban":
				# refresh selected row from the list
				var rr: Dictionary = await Online.admin("users", {"q": str(_sel.get("username", "")), "f": ""})
				if rr["ok"] and rr["res"] is Array:
					for row in rr["res"]:
						if str(row["id"]) == str(_sel.get("id", "")):
							_sel = row
				m.show_page("admin")
			else:
				_list_refresh()
	else:
		m._toast(str(r["err"]), UI.RED)
