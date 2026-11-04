extends RefCounted
## YÖNETİM paneli (sadece sunucuda yönetici olarak kayıtlı hesap görür; her işlem sunucuda tekrar kontrol edilir).
## Sekmeler: GENEL (canlı istatistik) • OYUNCULAR (ara, yasakla, sil, hediye) • DUYURU • TOPLU HEDİYE

var m
var tab := "genel"
var _stats_box: Control
var _list_box: VBoxContainer
var _query := ""
var _sel := {}            # selected user row

func _init(menu) -> void:
	m = menu

func page() -> void:
	if not Online.is_admin:
		m.content.add_child(UI.lbl("Bu sayfa yalnızca yöneticiler içindir.", 24, UI.RED, "Rajdhani-Bold"))
		return
	m.soldier.visible = false
	var p := UI.panel(Color(0.025, 0.03, 0.045, 0.96), Color("ff3d5a"), 18, 2)
	m._margin(p, 28, 18, 28, 24)
	m.content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var th := UI.hbox(10)
	v.add_child(th)
	th.add_child(UI.lbl("◆ YÖNETİM PANELİ", 32, Color("ff5d72"), "RussoOne-Regular"))
	th.add_child(UI.lbl("kurucu: " + Online.username, 16, UI.DIM, "Rajdhani-Bold"))
	th.add_child(UI.spacer())
	for it in [["genel", "GENEL"], ["oyuncu", "OYUNCULAR"], ["duyuru", "DUYURU"], ["toplu", "TOPLU HEDİYE"]]:
		var key: String = it[0]
		th.add_child(UI.btn(it[1], func(): tab = key; m.show_page("admin"), 17, tab == key, 150, 42))
	match tab:
		"genel": _genel(v)
		"oyuncu": _oyuncu(v)
		"duyuru": _duyuru(v)
		"toplu": _toplu(v)

# ---------------------------------------------------------------- GENEL
func _genel(v: VBoxContainer) -> void:
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 12)
	v.add_child(g)
	_stats_box = g
	var hint := UI.lbl("Her 5 saniyede canlı yenilenir.", 15, UI.DIM, "Rajdhani-SemiBold")
	v.add_child(hint)
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
	UI.clear(_stats_box)
	if not r["ok"]:
		_stats_box.add_child(UI.lbl(str(r["err"]), 18, UI.RED))
		return
	var d: Dictionary = r["res"]
	for it in [["ŞU AN ÇEVRİMİÇİ", "online", UI.GREEN], ["MAÇTA", "in_match", UI.ACCENT], ["AKTİF ODA", "rooms", UI.ACCENT2],
			["TOPLAM HESAP", "total", Color.WHITE], ["BUGÜN KAYIT", "today", Color("7fd1ff")], ["YASAKLI", "banned", UI.RED]]:
		var c := UI.panel(Color(1, 1, 1, 0.04), (it[2] as Color).darkened(0.3), 14)
		c.custom_minimum_size = Vector2(250, 0)
		var cv := UI.vbox(0)
		c.add_child(cv)
		cv.add_child(UI.lbl(str(int(d.get(it[1], 0))), 56, it[2], "Teko"))
		cv.add_child(UI.lbl(it[0], 16, UI.DIM, "Rajdhani-Bold"))
		_stats_box.add_child(c)

# ---------------------------------------------------------------- OYUNCULAR
func _oyuncu(v: VBoxContainer) -> void:
	var sh := UI.hbox(8)
	v.add_child(sh)
	var le := LineEdit.new()
	le.placeholder_text = "Kullanıcı adı ara (boş = son görülenler)"
	le.text = _query
	le.custom_minimum_size = Vector2(420, 42)
	sh.add_child(le)
	var go := func(): _query = le.text.strip_edges(); _list_refresh()
	le.text_submitted.connect(func(_t): go.call())
	sh.add_child(UI.btn("ARA", go, 18, true, 110, 42))
	sh.add_child(UI.btn("YENİLE", func(): _list_refresh(), 18, false, 110, 42))
	var body := UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(900, 560)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	_list_box = UI.vbox(4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list_box)
	body.add_child(_actions_panel())
	_list_refresh()

func _list_refresh() -> void:
	if _list_box == null or not is_instance_valid(_list_box):
		return
	var r: Dictionary = await Online.admin("users", {"q": _query})
	if not is_instance_valid(_list_box):
		return
	UI.clear(_list_box)
	if not r["ok"]:
		_list_box.add_child(UI.lbl(str(r["err"]), 18, UI.RED))
		return
	var rows = r["res"]
	if not (rows is Array):
		return
	var now := Time.get_unix_time_from_system()
	for row in rows:
		var ls := str(row.get("last_seen", ""))
		var online: bool = ls != "" and now - Time.get_unix_time_from_datetime_string(ls.substr(0, 19)) < 90
		var banned: bool = row.get("banned_until") != null and str(row.get("banned_until")) != ""
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		var on: bool = str(_sel.get("id", "")) == str(row["id"])
		b.add_theme_stylebox_override("normal", UI.sb(Color(0.3, 0.05, 0.08, 0.6) if banned else Color(0.07, 0.085, 0.11, 0.92), UI.ACCENT if on else Color(0.16, 0.19, 0.25), 1, 4, 6))
		b.add_theme_stylebox_override("hover", UI.sb(Color(0.1, 0.12, 0.16), UI.ACCENT2, 1, 4, 6))
		var h := UI.hbox(0)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ri: Dictionary = GS.rank_info(int(row.get("rp", 0)) if row.get("rp") != null else 0)
		for c in [[("● " if online else "○ ") + str(row["username"]) + ("  ◆YÖNETİCİ" if row.get("admin", false) else ""), 320, UI.GREEN if online else Color.WHITE],
				["Sv %d" % int(row.get("level", 1)), 90, UI.ACCENT2], [str(ri["name"]), 150, ri["color"]],
				["◉ " + UI.money(int(row.get("gold", 0)) if row.get("gold") != null else 0), 150, UI.GOLD],
				[("YASAKLI" if banned else str(row.get("status", ""))), 120, UI.RED if banned else UI.DIM]]:
			var l := UI.lbl(c[0], 18, c[2], "Rajdhani-Bold")
			l.custom_minimum_size = Vector2(c[1], 0)
			l.clip_text = true
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(l)
		var rr: Dictionary = row
		b.pressed.connect(func(): _sel = rr; m.show_page("admin"))
		_list_box.add_child(b)

func _actions_panel() -> Control:
	var p := UI.panel(Color(0.05, 0.06, 0.08, 0.95), UI.LINE, 14)
	p.custom_minimum_size = Vector2(430, 0)
	var v := UI.vbox(8)
	p.add_child(v)
	if _sel.is_empty():
		v.add_child(UI.lbl("Listeden bir oyuncu seç.", 18, UI.DIM, "Rajdhani-Bold"))
		return p
	var uid: String = str(_sel["id"])
	v.add_child(UI.lbl(str(_sel["username"]), 28, Color.WHITE, "RussoOne-Regular"))
	v.add_child(UI.lbl("Kayıt: %s   •   Öldürme: %d" % [str(_sel.get("created_at", "")).substr(0, 10), int(_sel.get("kills", 0)) if _sel.get("kills") != null else 0], 15, UI.DIM, "Rajdhani-SemiBold"))
	if _sel.get("banned_until") != null:
		v.add_child(UI.lbl("YASAKLI: %s  (%s)" % [str(_sel["banned_until"]).substr(0, 16), str(_sel.get("ban_reason", ""))], 16, UI.RED, "Rajdhani-Bold"))
	v.add_child(UI.header("YASAKLA", 18))
	var reason := LineEdit.new(); reason.placeholder_text = "Sebep (ör. hile, küfür)"; reason.custom_minimum_size = Vector2(0, 38)
	v.add_child(reason)
	var bh := UI.hbox(6)
	v.add_child(bh)
	for it in [["1 SAAT", 1], ["1 GÜN", 24], ["7 GÜN", 168], ["SÜRESİZ", 0]]:
		var hrs: int = it[1]
		bh.add_child(UI.btn(it[0], func(): _do("ban", {"id": uid, "hours": hrs, "reason": reason.text}, "Oyuncu yasaklandı"), 15, false, 0, 36))
	var bh2 := UI.hbox(6)
	v.add_child(bh2)
	bh2.add_child(UI.btn("YASAĞI KALDIR", func(): _do("unban", {"id": uid}, "Yasak kaldırıldı"), 15, false, 0, 36))
	var del := UI.btn("HESABI SİL", func(): _confirm_delete(uid, str(_sel["username"])), 15, false, 0, 36)
	del.add_theme_color_override("font_color", UI.RED)
	bh2.add_child(del)
	v.add_child(UI.header("HEDİYE GÖNDER", 18))
	v.add_child(_gift_form(uid))
	return p

func _confirm_delete(uid: String, name: String) -> void:
	var mv: VBoxContainer = m._modal(560, 240)
	mv.add_child(UI.lbl("%s hesabı KALICI olarak silinsin mi?" % name, 24, UI.RED, "Rajdhani-Bold"))
	mv.add_child(UI.lbl("Bu işlem geri alınamaz: profil, silahlar ve istatistikler silinir.", 17, UI.DIM))
	var h := UI.hbox(10)
	mv.add_child(h)
	h.add_child(UI.btn("EVET, SİL", func(): m._close_modal(); _sel = {}; _do("delete", {"id": uid}, "Hesap silindi"), 18, true, 200, 46))
	h.add_child(UI.btn("VAZGEÇ", m._close_modal, 18, false, 160, 46))

func _gift_form(target: String) -> Control:
	var v := UI.vbox(6)
	var g := GridContainer.new(); g.columns = 2
	g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var fields := {}
	for it in [["gold", "Altın"], ["demir", "Demir"], ["krom", "Krom"], ["titanyum", "Titanyum"], ["kobalt", "Kobalt"], ["crates", "Sokak Kasası"]]:
		g.add_child(UI.lbl(it[1], 16, UI.TEXT, "Rajdhani-Bold"))
		var sb := SpinBox.new(); sb.max_value = 1000000 if it[0] == "gold" else 10000; sb.step = 1; sb.custom_minimum_size = Vector2(160, 34)
		g.add_child(sb)
		fields[it[0]] = sb
	# weapon / skin pickers
	g.add_child(UI.lbl("Silah", 16, UI.TEXT, "Rajdhani-Bold"))
	var wopt := OptionButton.new(); wopt.add_item("— yok —")
	for id in GS.WEAPONS.keys():
		if not GS.WEAPONS[id].get("throwable", false):
			wopt.add_item(str(GS.WEAPONS[id]["name"])); wopt.set_item_metadata(wopt.item_count - 1, id)
	g.add_child(wopt)
	g.add_child(UI.lbl("Süre", 16, UI.TEXT, "Rajdhani-Bold"))
	var dopt := OptionButton.new()
	for it in [["Süresiz", 0], ["3 gün", 3], ["7 gün", 7], ["30 gün", 30]]:
		dopt.add_item(it[0]); dopt.set_item_metadata(dopt.item_count - 1, it[1])
	g.add_child(dopt)
	g.add_child(UI.lbl("Stil", 16, UI.TEXT, "Rajdhani-Bold"))
	var sopt := OptionButton.new(); sopt.add_item("— yok —")
	for sk in GS.SKINS.keys():
		if sk != "std":
			sopt.add_item(str(GS.SKINS[sk]["name"])); sopt.set_item_metadata(sopt.item_count - 1, sk)
	g.add_child(sopt)
	var msg := LineEdit.new(); msg.placeholder_text = "Mesaj (ör. Bayramın kutlu olsun!)"; msg.custom_minimum_size = Vector2(0, 36)
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
		_do("gift", {"id": target, "gift": gift}, "Hediye gönderildi" if target != "all" else "Herkese hediye gönderildi")
	v.add_child(UI.btn("★ HEDİYEYİ GÖNDER" + ("  (TÜM OYUNCULAR)" if target == "all" else ""), send, 18, true, 0, 46))
	return v

# ---------------------------------------------------------------- DUYURU / TOPLU
func _duyuru(v: VBoxContainer) -> void:
	v.add_child(UI.lbl("Duyuru, oyundaki herkesin ekranında (lobide ve maçta) anlık olarak görünür.", 18, UI.TEXT, "Rajdhani-Bold"))
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 140)
	te.placeholder_text = "Örn: Bu akşam 21:00'de 2x altın etkinliği!"
	v.add_child(te)
	v.add_child(UI.btn("◆ DUYURU YAP", func():
		var t := te.text.strip_edges()
		if t.length() < 2: return
		_do("announce", {"text": t}, "Duyuru yayınlandı"); te.text = "", 20, true, 260, 50))

func _toplu(v: VBoxContainer) -> void:
	v.add_child(UI.lbl("TÜM oyunculara (yasaklılar hariç) aynı anda hediye gönder.", 20, UI.GOLD, "Rajdhani-Bold"))
	var p := UI.panel(Color(0.05, 0.06, 0.08, 0.95), UI.LINE, 14)
	p.custom_minimum_size = Vector2(480, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(p)
	p.add_child(_gift_form("all"))

func _do(a: String, args: Dictionary, okmsg: String) -> void:
	var r: Dictionary = await Online.admin(a, args)
	if r["ok"]:
		m._toast(okmsg + (" (%d oyuncu)" % int(r["res"].get("count", 0)) if r["res"] is Dictionary and r["res"].has("count") else ""), UI.GREEN)
		if tab == "oyuncu":
			_list_refresh()
	else:
		m._toast(str(r["err"]), UI.RED)
