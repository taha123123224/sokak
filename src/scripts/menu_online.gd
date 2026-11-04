extends RefCounted
## Online pages for the lobby menu: ARKADAŞLAR (friends, requests, search), online room list, online room
## lobby (members, chat, invite friends, host settings, start) and the incoming-invite popup.

var m   # menu.gd instance

var _conns: Array = []

func _init(menu) -> void:
	m = menu
	_c(Online.invite_received, _on_invite)
	_c(Online.friend_request, _on_friend_request)
	_c(Online.friend_accepted, func(f): _notify("ARKADAŞ OLDUNUZ", "%s isteğini kabul etti." % str(f.get("username", "?")), str(f.get("username", "?")), UI.GREEN, []))
	_c(Online.friends_updated, func(_l): m._update_friend_badge())
	_c(Net.message, _on_net)
	_c(Net.member_joined, func(_i, n): _sys("%s odaya katıldı." % n); _refresh_room())
	_c(Net.member_left, func(_i): _refresh_room())
	_c(Net.host_changed, func(_h): _refresh_room())
	_c(Net.disconnected_room, func(why):
		m._toast(why, UI.RED)
		if m.page == "netroom" or m.page == "rooms": m.show_page("rooms"))
	_c(Net.connected_room, func(_c2): Net.send({"t": "hello_room"}); _refresh_room())

func _c(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_conns.append([sig, cb])

func cleanup() -> void:
	for p in _conns:
		if (p[0] as Signal).is_connected(p[1]):
			(p[0] as Signal).disconnect(p[1])
	_conns.clear()

func need_login() -> bool:
	if Online.is_logged_in():
		return false
	var p := UI.panel(UI.BG, UI.LINE, 24)
	m._margin(p, 28, 18, 560, 400)
	m.content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.header("ÇEVRİMİÇİ", 28))
	v.add_child(m._wrap("Arkadaş eklemek, odaya davet etmek ve arkadaşlarınla oynamak için hesabınla giriş yapmalısın.", 20))
	v.add_child(UI.btn("GİRİŞ / KAYIT EKRANINA DÖN", func(): m.main.go_login(), 20, true, 380, 56))
	return true

# ================================================================ FRIENDS
var search_box: LineEdit
var search_res: VBoxContainer

func _avatar(name: String, d: int, ring: Color) -> Control:
	var p := PanelContainer.new()
	var hue := float(abs(hash(name)) % 360) / 360.0
	p.add_theme_stylebox_override("panel", UI.sb(Color.from_hsv(hue, 0.5, 0.42), ring, 2, d / 2, 0))
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(name.substr(0, 1).to_upper(), int(d * 0.48), Color.WHITE, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

func _card(bg: Color, border: Color, pad: int = 14, rad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(bg, border, 1, rad, pad))
	return p

func _pill(t: String, c: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UI.sb(Color(c.r, c.g, c.b, 0.15), Color(c.r, c.g, c.b, 0.5), 1, 14, 0)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 1; sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UI.lbl(t, 13, c.lightened(0.2), "Rajdhani-Bold"))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

var fr_filter := "all"

func _status_of(f: Dictionary) -> Array:
	## [text, colour, online]
	var on: bool = bool(f.get("online", false)) and str(f.get("status", "")) != "offline"
	if not on:
		return ["Çevrimdışı", Color(0.45, 0.47, 0.52), false]
	match str(f.get("status", "")):
		"match": return ["Maçta", UI.ACCENT, true]
		"room": return ["Odada", Color("7fd1ff"), true]
	return ["Lobide", UI.GREEN, true]

func page_friends() -> void:
	if need_login():
		return
	m.soldier.visible = false
	var root := UI.hbox(16)
	m._margin(root, 24, 14, 24, 20)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.content.add_child(root)
	# ---------------- left: friend list
	var lp := _card(Color(0.025, 0.03, 0.045, 0.95), Color(1, 1, 1, 0.07), 20, 12)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(lp)
	var v := UI.vbox(12)
	lp.add_child(v)
	var mates: Array = Online.friends.filter(func(f): return not bool(f["pending"]))
	var online_n := mates.filter(func(f): return _status_of(f)[2]).size()
	var th := UI.hbox(12)
	v.add_child(th)
	var tv := UI.vbox(-4)
	th.add_child(tv)
	tv.add_child(UI.lbl("ARKADAŞLAR", 32, Color.WHITE, "RussoOne-Regular"))
	tv.add_child(UI.lbl("%d çevrimiçi  •  %d arkadaş" % [online_n, mates.size()], 15, UI.GREEN if online_n > 0 else UI.DIM, "Rajdhani-Bold"))
	th.add_child(UI.spacer())
	for it in [["all", "TÜMÜ"], ["on", "● ÇEVRİMİÇİ"], ["game", "▶ OYUNDA"]]:
		var key: String = it[0]
		th.add_child(m._chip(it[1], fr_filter == key, func(): fr_filter = key; m.show_page("friends"), 0))
	th.add_child(UI.btn("⟳", func(): await Online.refresh_friends(); m.show_page("friends"), 20, false, 48, 40))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	mates.sort_custom(func(a, b):
		var sa: bool = _status_of(a)[2]; var sb: bool = _status_of(b)[2]
		return sa and not sb if sa != sb else str(a["username"]).to_lower() < str(b["username"]).to_lower())
	var shown := 0
	for f in mates:
		var st: Array = _status_of(f)
		if fr_filter == "on" and not st[2]: continue
		if fr_filter == "game" and str(f.get("status", "")) not in ["room", "match"]: continue
		shown += 1
		var row := _card(Color(0.06, 0.07, 0.095, 0.96), Color(st[1].r, st[1].g, st[1].b, 0.25 if st[2] else 0.06), 12, 10)
		list.add_child(row)
		var h := UI.hbox(14)
		row.add_child(h)
		h.add_child(_avatar(str(f["username"]), 48, st[1] if st[2] else Color(1, 1, 1, 0.1)))
		var nv := UI.vbox(-2)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nv)
		var nh := UI.hbox(8)
		nv.add_child(nh)
		nh.add_child(UI.lbl(str(f["username"]), 21, Color.WHITE if st[2] else Color(1, 1, 1, 0.6), "Rajdhani-Bold"))
		nh.add_child(_pill("Sv %d" % int(f.get("level", 1)), UI.ACCENT2))
		nv.add_child(UI.lbl("● " + str(st[0]), 15, st[1], "Rajdhani-Bold"))
		if st[2] and Net.active() and Net.code != "" and str(f.get("room", "")) != Net.code:
			h.add_child(UI.btn("✉ DAVET ET", func():
				var e: String = await Online.invite(str(f["user_id"]), Net.code, str(room_cfg.get("name", "Oda")))
				m._toast("Davet gönderildi: " + str(f["username"]) if e == "" else e, UI.GREEN if e == "" else UI.RED), 15, true, 130, 40))
		if st[2] and f.get("room") != null and str(f["room"]) != "" and str(f["room"]) != Net.code:
			h.add_child(UI.btn("▶ ODASINA KATIL", func(): join_room(str(f["room"])), 15, false, 160, 40))
		var rm := UI.btn("✕", func(): _confirm_remove(f), 16, false, 42, 40)
		rm.tooltip_text = "Arkadaşlıktan çıkar"
		h.add_child(rm)
	if shown == 0:
		var ev := UI.vbox(6)
		list.add_child(ev)
		ev.add_child(UI.spacer(false, 0, 40))
		ev.add_child(UI.lbl("☺", 64, Color(1, 1, 1, 0.12), "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		ev.add_child(UI.lbl("Henüz arkadaşın yok" if mates.is_empty() else "Bu filtrede kimse yok", 22, UI.TEXT, "Rajdhani-Bold", HORIZONTAL_ALIGNMENT_CENTER))
		ev.add_child(UI.lbl("Sağdaki kutudan kullanıcı adıyla arayıp istek gönder.", 16, UI.DIM, "Rajdhani-SemiBold", HORIZONTAL_ALIGNMENT_CENTER))
	# ---------------- right: add + requests
	var right := UI.vbox(14)
	right.custom_minimum_size = Vector2(470, 0)
	root.add_child(right)
	var me := _card(Color(0.05, 0.06, 0.085, 0.96), Color(1, 1, 1, 0.07), 14, 12)
	right.add_child(me)
	var meh := UI.hbox(12)
	me.add_child(meh)
	meh.add_child(_avatar(Online.username, 44, UI.GREEN))
	var mev := UI.vbox(-4)
	meh.add_child(mev)
	mev.add_child(UI.lbl(Online.username, 20, Color.WHITE, "Rajdhani-Bold"))
	mev.add_child(UI.lbl("Arkadaşların seni bu adla bulur", 14, UI.DIM, "Rajdhani-SemiBold"))
	var ap := _card(Color(0.05, 0.06, 0.085, 0.96), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.35), 16, 12)
	right.add_child(ap)
	var av := UI.vbox(8)
	ap.add_child(av)
	av.add_child(UI.lbl("＋ ARKADAŞ EKLE", 18, UI.ACCENT, "Rajdhani-Bold"))
	var ah := UI.hbox(8)
	av.add_child(ah)
	search_box = LineEdit.new()
	search_box.placeholder_text = "⌕  Kullanıcı adı (en az 2 harf)"
	search_box.custom_minimum_size = Vector2(0, 44)
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(search_box)
	ah.add_child(UI.btn("ARA", _search, 17, true, 90, 44))
	search_box.text_submitted.connect(func(_t): _search())
	search_res = UI.vbox(6)
	av.add_child(search_res)
	var incoming: Array = Online.friends.filter(func(f): return bool(f["pending"]) and bool(f["incoming"]))
	var outgoing: Array = Online.friends.filter(func(f): return bool(f["pending"]) and not bool(f["incoming"]))
	var rq := _card(Color(0.05, 0.06, 0.085, 0.96), Color(1, 0.3, 0.35, 0.45) if incoming.size() > 0 else Color(1, 1, 1, 0.07), 16, 12)
	right.add_child(rq)
	var rv := UI.vbox(8)
	rq.add_child(rv)
	var rh := UI.hbox(8)
	rv.add_child(rh)
	rh.add_child(UI.lbl("GELEN İSTEKLER", 18, Color("ff8a96") if incoming.size() > 0 else UI.TEXT, "Rajdhani-Bold"))
	if incoming.size() > 0:
		rh.add_child(_pill(str(incoming.size()), UI.RED))
	if incoming.is_empty():
		rv.add_child(UI.lbl("Bekleyen istek yok.", 15, UI.DIM, "Rajdhani-SemiBold"))
	for f in incoming:
		var ih := UI.hbox(10)
		rv.add_child(ih)
		ih.add_child(_avatar(str(f["username"]), 36, Color(1, 1, 1, 0.1)))
		var il := UI.lbl(str(f["username"]), 18, Color.WHITE, "Rajdhani-Bold")
		il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ih.add_child(il)
		ih.add_child(UI.btn("✔ KABUL", func(): await Online.accept_friend(int(f["friendship_id"])); SFX.play("success", -6); m.show_page("friends"), 15, true, 100, 36))
		ih.add_child(UI.btn("✕", func(): await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 15, false, 40, 36))
	if outgoing.size() > 0:
		var oq := _card(Color(0.05, 0.06, 0.085, 0.96), Color(1, 1, 1, 0.07), 16, 12)
		right.add_child(oq)
		var ov := UI.vbox(6)
		oq.add_child(ov)
		ov.add_child(UI.lbl("GÖNDERDİĞİN İSTEKLER", 16, UI.DIM, "Rajdhani-Bold"))
		for f in outgoing:
			var oh := UI.hbox(8)
			ov.add_child(oh)
			var ol := UI.lbl(str(f["username"]) + "   •   bekliyor", 16, UI.TEXT, "Rajdhani-SemiBold")
			ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			oh.add_child(ol)
			oh.add_child(UI.btn("İPTAL", func(): await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 14, false, 80, 32))

func _confirm_remove(f: Dictionary) -> void:
	var mv: VBoxContainer = m._modal(520, 200)
	mv.add_child(UI.lbl("%s arkadaş listenden çıkarılsın mı?" % str(f["username"]), 22, Color.WHITE, "Rajdhani-Bold"))
	var h := UI.hbox(10)
	mv.add_child(h)
	h.add_child(UI.btn("ÇIKAR", func(): m._close_modal(); await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 18, true, 160, 46))
	h.add_child(UI.btn("VAZGEÇ", m._close_modal, 18, false, 160, 46))

func _search() -> void:
	for c in search_res.get_children():
		c.queue_free()
	var res: Array = await Online.search_users(search_box.text)
	if not is_instance_valid(search_res):
		return
	if res.is_empty():
		search_res.add_child(UI.lbl("Kullanıcı bulunamadı.", 15, UI.DIM, "Rajdhani-SemiBold"))
		return
	var known := {}
	for f in Online.friends:
		known[str(f.get("user_id", ""))] = bool(f["pending"])
	for u in res:
		var h := UI.hbox(10)
		search_res.add_child(h)
		h.add_child(_avatar(str(u["username"]), 34, Color(1, 1, 1, 0.1)))
		var l := UI.lbl("%s   Sv %d" % [u["username"], int(u.get("level", 1))], 17, Color.WHITE, "Rajdhani-Bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var uid_s := str(u["id"])
		if known.has(uid_s):
			h.add_child(_pill("İSTEK GÖNDERİLDİ" if known[uid_s] else "ARKADAŞIN", UI.DIM if known[uid_s] else UI.GREEN))
		else:
			h.add_child(UI.btn("＋ EKLE", func():
				var e: String = await Online.add_friend(uid_s)
				m._toast("İstek gönderildi: " + str(u["username"]) if e == "" else e, UI.GREEN if e == "" else UI.RED)
				m.show_page("friends"), 15, true, 100, 34))

# ================================================================ notifications
var _notif_stack: Array = []
func _notify(title: String, text: String, who: String, col: Color, buttons: Array, life: float = 14.0) -> Control:
	## modern slide-in card (top right): avatar, title, text, optional buttons [[label, callable, primary]]
	SFX.play("medal", -6)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(0.03, 0.035, 0.05, 0.97), Color(col.r, col.g, col.b, 0.7), 1, 12, 14))
	p.custom_minimum_size = Vector2(440, 0)
	p.anchor_left = 1; p.anchor_right = 1
	p.offset_left = -460; p.offset_right = -20
	p.offset_top = 80 + _notif_stack.size() * 128
	m.ui.add_child(p)
	_notif_stack.append(p)
	p.tree_exiting.connect(func(): _notif_stack.erase(p))
	var h := UI.hbox(12)
	p.add_child(h)
	var acc := ColorRect.new(); acc.color = col; acc.custom_minimum_size = Vector2(4, 0)
	h.add_child(acc)
	h.add_child(_avatar(who, 46, col))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UI.lbl(title, 15, col.lightened(0.2), "Rajdhani-Bold"))
	var tl := UI.lbl(text, 18, Color.WHITE, "Rajdhani-Bold")
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	if buttons.size() > 0:
		var bh := UI.hbox(8)
		v.add_child(bh)
		for b in buttons:
			var cb: Callable = b[1]
			bh.add_child(UI.btn(b[0], func(): if is_instance_valid(p): p.queue_free(); cb.call(), 15, bool(b[2]), 0, 36))
	var x := UI.btn("✕", func(): if is_instance_valid(p): p.queue_free(), 14, false, 30, 30)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(x)
	# slide in from the right
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(p, "offset_left", -460.0, 0.3).from(-200.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "offset_right", -20.0, 0.3).from(240.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	m.get_tree().create_timer(life).timeout.connect(func():
		if is_instance_valid(p):
			var t2 := p.create_tween()
			t2.tween_property(p, "modulate:a", 0.0, 0.3)
			t2.tween_callback(p.queue_free))
	return p

func _on_friend_request(f: Dictionary) -> void:
	var fid := int(f.get("friendship_id", 0))
	var nm := str(f.get("username", "?"))
	_notify("ARKADAŞLIK İSTEĞİ", "%s seni arkadaş olarak eklemek istiyor." % nm, nm, Color("ff6b8a"),
		[["✔ KABUL ET", func(): await Online.accept_friend(fid); SFX.play("success", -6); m._toast("%s ile artık arkadaşsınız" % nm, UI.GREEN); if m.page == "friends": m.show_page("friends"), true],
		 ["REDDET", func(): await Online.remove_friend(fid); if m.page == "friends": m.show_page("friends"), false]], 25.0)
	m._update_friend_badge()

# ================================================================ invites
func _on_invite(inv: Dictionary) -> void:
	var nm := str(inv.get("from", "?"))
	_notify("ODA DAVETİ", "%s seni \"%s\" odasına çağırıyor." % [nm, str(inv.get("room_name", "Oda"))], nm, UI.ACCENT,
		[["▶ KATIL", func(): Online.drop_invite(int(inv["id"])); join_room(str(inv["room"])), true],
		 ["REDDET", func(): Online.drop_invite(int(inv["id"])), false]], 25.0)

# ================================================================ online rooms
var room_cfg := {"name": "Arkadaş Odası", "map": "mahalle", "mode": "tdm", "time": 10, "target": 50, "max": 10, "private": false}
var room_chat: VBoxContainer
var room_box: VBoxContainer
var _pub_t := 0.0

func rooms_panel(v: VBoxContainer) -> void:
	## online section on top of the room list page
	if not Online.is_logged_in():
		return
	var op := UI.panel(Color(0.05, 0.09, 0.06, 0.9), UI.GREEN.darkened(0.3), 12)
	v.add_child(op)
	var ov := UI.vbox(8)
	op.add_child(ov)
	var h := UI.hbox(10)
	ov.add_child(h)
	h.add_child(UI.lbl("● ÇEVRİMİÇİ ODALAR", 20, UI.GREEN, "Rajdhani-Bold"))
	h.add_child(UI.spacer())
	var code_e := LineEdit.new()
	code_e.placeholder_text = "Oda kodu"
	code_e.custom_minimum_size = Vector2(150, 40)
	h.add_child(code_e)
	h.add_child(UI.btn("KODLA KATIL", func(): if code_e.text.strip_edges().length() >= 4: join_room(code_e.text.strip_edges()), 16, false, 140, 40))
	h.add_child(UI.btn("ONLINE ODA KUR", create_room, 18, true, 190, 40))
	var lst := UI.vbox(4)
	ov.add_child(lst)
	lst.add_child(UI.lbl("Yükleniyor...", 16, UI.DIM, "Rajdhani-SemiBold"))
	var rooms: Array = await Online.list_rooms()
	if not is_instance_valid(lst):
		return
	for c in lst.get_children():
		c.queue_free()
	if rooms.is_empty():
		lst.add_child(UI.lbl("Şu an açık online oda yok. İlk odayı sen kur ve arkadaşlarını davet et!", 16, UI.DIM, "Rajdhani-SemiBold"))
	for r in rooms:
		var rh := UI.hbox(10)
		lst.add_child(rh)
		var host_n := str(r["profiles"]["username"]) if r.get("profiles") is Dictionary else "?"
		rh.add_child(UI.lbl("%s   •   %s   •   %s   •   %d/%d   •   kurucu: %s" % [r["name"], GS.MAPS.get(r["map"], {}).get("name", r["map"]), GS.MODES.get(r["mode"], {}).get("name", r["mode"]), int(r["players"]), int(r["max_players"]), host_n], 17, Color.WHITE, "Rajdhani-SemiBold"))
		rh.add_child(UI.spacer())
		rh.add_child(UI.btn("KATIL" if str(r["state"]) == "lobby" else "MAÇTA", func(): join_room(str(r["code"])), 15, str(r["state"]) == "lobby", 100, 34))

# ================================================================ ONLINE HUB (rooms page in online mode)
var _hub_list: VBoxContainer
var _hub_count: Label
var _hub_friends: VBoxContainer

func page_online_rooms() -> void:
	if need_login():
		return
	m.set_showcase(GS.active_set().get("ana", "ak47"))
	var p := UI.panel(UI.BG, UI.GREEN.darkened(0.45), 18)
	m._margin(p, 28, 18, 560, 24)
	m.content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var th := UI.hbox(10)
	v.add_child(th)
	th.add_child(UI.lbl("● ÇEVRİMİÇİ ODALAR", 30, UI.GREEN, "RussoOne-Regular"))
	th.add_child(UI.spacer())
	_hub_count = UI.lbl("", 20, Color.WHITE, "Rajdhani-Bold")
	th.add_child(_hub_count)
	var bar := UI.hbox(10)
	v.add_child(bar)
	bar.add_child(UI.btn("▶  HIZLI KATIL", quick_join, 20, true, 200, 48))
	bar.add_child(UI.btn("ODA KUR", create_room, 20, false, 150, 48))
	var code_e := LineEdit.new()
	code_e.placeholder_text = "Oda kodu"
	code_e.custom_minimum_size = Vector2(160, 48)
	bar.add_child(code_e)
	bar.add_child(UI.btn("KODLA KATIL", func(): if code_e.text.strip_edges().length() >= 4: join_room(code_e.text.strip_edges().to_upper()), 18, false, 150, 48))
	bar.add_child(UI.spacer())
	bar.add_child(UI.btn("YENİLE", _hub_refresh, 16, false, 110, 48))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_hub_list = UI.vbox(6)
	_hub_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_hub_list)
	# online friends strip
	var fp := UI.panel(Color(0.04, 0.07, 0.05, 0.9), UI.LINE, 10)
	v.add_child(fp)
	var fv := UI.vbox(6)
	fp.add_child(fv)
	fv.add_child(UI.lbl("ÇEVRİMİÇİ ARKADAŞLAR", 17, UI.GREEN, "Rajdhani-Bold"))
	_hub_friends = UI.vbox(4)
	fv.add_child(_hub_friends)
	var tm := Timer.new()
	tm.wait_time = 6.0
	tm.autostart = true
	tm.timeout.connect(_hub_refresh)
	p.add_child(tm)
	_hub_refresh()

func _hub_refresh() -> void:
	if m.page != "rooms" or _hub_list == null or not is_instance_valid(_hub_list):
		return
	var n: int = await Online.count_online()
	var rooms: Array = await Online.list_rooms()
	if not is_instance_valid(_hub_list):
		return
	_hub_count.text = "%d oyuncu çevrimiçi   •   %d açık oda" % [maxi(n, 1), rooms.size()]
	for c in _hub_list.get_children():
		c.queue_free()
	if rooms.is_empty():
		var e := UI.vbox(6)
		e.add_child(UI.lbl("Şu an açık oda yok.", 24, Color.WHITE, "Rajdhani-Bold"))
		e.add_child(UI.lbl("ODA KUR'a bas, arkadaşlarını davet et ya da HIZLI KATIL ile ilk odayı aç.", 18, UI.DIM, "Rajdhani-SemiBold"))
		_hub_list.add_child(e)
	for r in rooms:
		var full := int(r["players"]) >= int(r["max_players"])
		var lobby := str(r["state"]) == "lobby"
		var code := str(r["code"])
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.sb(Color(0.05, 0.065, 0.09, 0.96), UI.GREEN.darkened(0.35) if lobby and not full else Color(0.2, 0.22, 0.26), 1, 6, 0))
		_hub_list.add_child(row)
		var rh := UI.hbox(14)
		row.add_child(rh)
		var img: Control = m._map_image(str(r["map"]))
		img.custom_minimum_size = Vector2(150, 84)
		rh.add_child(img)
		var host_n := str(r["profiles"]["username"]) if r.get("profiles") is Dictionary else "?"
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(tv)
		var nl := UI.lbl(str(r["name"]), 22, Color.WHITE, "RussoOne-Regular")
		nl.clip_text = true
		tv.add_child(nl)
		tv.add_child(UI.lbl("%s   •   %s   •   kurucu: %s" % [GS.MAPS.get(r["map"], {}).get("name", r["map"]), GS.MODES.get(r["mode"], {}).get("name", r["mode"]), host_n], 16, UI.TEXT, "Rajdhani-SemiBold"))
		var pb := UI.bar(float(r["players"]), float(r["max_players"]), UI.RED if full else UI.GREEN, 6, 260)
		tv.add_child(pb)
		var cv := UI.vbox(2)
		cv.custom_minimum_size = Vector2(150, 0)
		rh.add_child(cv)
		cv.add_child(UI.lbl("%d / %d" % [int(r["players"]), int(r["max_players"])], 26, UI.RED if full else UI.GREEN, "Teko", HORIZONTAL_ALIGNMENT_CENTER))
		var jb := UI.btn("KATIL ›" if lobby and not full else ("DOLU" if full else "MAÇTA"), func(): join_room(code), 16, lobby and not full, 140, 36)
		jb.disabled = not lobby or full
		cv.add_child(jb)
	for c in _hub_friends.get_children():
		c.queue_free()
	var any := false
	for f in Online.friends:
		if not (f is Dictionary) or not bool(f.get("online", false)) or bool(f.get("pending", false)):
			continue
		any = true
		var fh := UI.hbox(10)
		fh.add_child(UI.lbl("●  " + str(f["username"]), 18, UI.GREEN, "Rajdhani-Bold"))
		fh.add_child(UI.lbl("Sv. %d  •  %s" % [int(f.get("level", 1)), "odada" if str(f.get("room", "")) not in ["", "<null>"] else "lobide"], 16, UI.DIM, "Rajdhani-SemiBold"))
		fh.add_child(UI.spacer())
		var rm := str(f.get("room", ""))
		if rm not in ["", "<null>"]:
			fh.add_child(UI.btn("YANINA GİT", func(): join_room(rm), 14, false, 120, 30))
		_hub_friends.add_child(fh)
	if not any:
		_hub_friends.add_child(UI.lbl("Şu an çevrimiçi arkadaşın yok. ARKADAŞLAR sekmesinden arkadaş ekleyebilirsin.", 16, UI.DIM, "Rajdhani-SemiBold"))

func quick_join() -> void:
	if not Online.is_logged_in():
		m.show_page("mode"); return
	m._toast("Uygun oda aranıyor…", UI.GREEN)
	var rooms: Array = await Online.list_rooms()
	for r in rooms:
		if str(r["state"]) == "lobby" and int(r["players"]) < int(r["max_players"]):
			join_room(str(r["code"]))
			return
	create_room()

# ================================================================ LEADERBOARD (SIRALAMA)
var _lb_sort := "rp"
var _lb_box: VBoxContainer
var _lb_podium: HBoxContainer
var _lb_info: Label
var _lb_sig := ""

func page_leaderboard() -> void:
	m.soldier.visible = true
	var p := UI.panel(UI.BG, UI.LINE, 18)
	m._margin(p, 28, 18, 560, 24)
	m.content.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var th := UI.hbox(10)
	v.add_child(th)
	th.add_child(UI.lbl("SIRALAMA", 34, Color.WHITE, "RussoOne-Regular"))
	th.add_child(UI.spacer(false, 14))
	var live := UI.lbl("● CANLI", 18, UI.GREEN, "Rajdhani-Bold")
	th.add_child(live)
	var tw := live.create_tween().set_loops()
	tw.tween_property(live, "modulate:a", 0.35, 0.7)
	tw.tween_property(live, "modulate:a", 1.0, 0.7)
	th.add_child(UI.spacer())
	for it in [["rp", "RÜTBE"], ["level", "SEVİYE"], ["wins", "GALİBİYET"], ["kills", "ÖLDÜRME"]]:
		var key: String = it[0]
		th.add_child(UI.btn(it[1], func(): _lb_sort = key; _lb_sig = ""; m.show_page("leader"), 18, _lb_sort == key, 140, 44))
	if not Online.is_logged_in():
		v.add_child(UI.lbl("Sıralamayı görmek ve listeye girmek için hesabınla giriş yapmalısın.", 20, UI.ACCENT2, "Rajdhani-Bold"))
		v.add_child(UI.btn("GİRİŞ / KAYIT EKRANINA DÖN", func(): m.main.go_login(), 20, true, 380, 56))
		return
	_lb_podium = UI.hbox(14)
	_lb_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_lb_podium)
	var head := UI.hbox(0)
	v.add_child(head)
	for c in [["#", 70], ["Rütbe", 210], ["Oyuncu", 300], ["Seviye", 100], ["Galibiyet", 120], ["Öldürme", 120], ["K/D", 90], ["Maç", 80]]:
		var l := UI.lbl(c[0], 17, UI.DIM, "Rajdhani-Bold")
		l.custom_minimum_size = Vector2(c[1], 26)
		head.add_child(l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_lb_box = UI.vbox(4)
	_lb_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_lb_box)
	_lb_info = UI.lbl("Yükleniyor…", 16, UI.DIM, "Rajdhani-SemiBold")
	v.add_child(_lb_info)
	var tm := Timer.new()
	tm.wait_time = 5.0
	tm.autostart = true
	tm.timeout.connect(_lb_refresh)
	p.add_child(tm)
	_lb_sig = ""
	Online.save_now()
	_lb_refresh()

func _lb_val(r: Dictionary, k: String) -> int:
	var x = r.get(k)
	return int(x) if x != null else 0

func _lb_refresh() -> void:
	if m.page != "leader" or _lb_box == null or not is_instance_valid(_lb_box):
		return
	var rows: Array = await Online.leaderboard(_lb_sort, 50)
	if not is_instance_valid(_lb_box):
		return
	var t := Time.get_time_string_from_system()
	_lb_info.text = "%d oyuncu  •  son güncelleme %s  •  her 5 saniyede yenilenir" % [rows.size(), t]
	var sig := JSON.stringify(rows.map(func(r): return [r.get("username"), r.get("level"), r.get("rp"), r.get("wins"), r.get("kills"), r.get("last_seen", "").substr(0, 16)]))
	if sig == _lb_sig:
		return
	_lb_sig = sig
	for c in _lb_box.get_children():
		c.queue_free()
	for c in _lb_podium.get_children():
		c.queue_free()
	var now := Time.get_unix_time_from_system()
	var medal := [Color("ffc23d"), Color("cfd8e3"), Color("d9894a")]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var me := str(r.get("id", "")) == Online.uid
		var online := false
		var ls := str(r.get("last_seen", ""))
		if ls != "":
			online = now - Time.get_unix_time_from_datetime_string(ls.substr(0, 19)) < 75
		var k := _lb_val(r, "kills")
		var d := _lb_val(r, "deaths")
		if i < 3:
			_lb_podium.add_child(_lb_card(i, r, medal[i], online))
		var row := PanelContainer.new()
		var bg := Color(0.16, 0.1, 0.03, 0.95) if me else Color(0.07, 0.085, 0.11, 0.92)
		row.add_theme_stylebox_override("panel", UI.sb(bg, UI.ACCENT if me else (medal[i] if i < 3 else Color(0.16, 0.19, 0.25)), 1, 4, 6))
		_lb_box.add_child(row)
		var rh := UI.hbox(0)
		row.add_child(rh)
		var cells := [["%d" % (i + 1), 70, medal[i] if i < 3 else UI.DIM, "Teko", 26]]
		var cells2 := [[("● " if online else "   ") + str(r.get("username", "?")) + ("  (sen)" if me else ""), 300, UI.GREEN if online else Color.WHITE, "Rajdhani-Bold", 20],
			[str(_lb_val(r, "level")), 100, UI.ACCENT2, "Rajdhani-Bold", 20],
			[str(_lb_val(r, "wins")), 120, Color.WHITE, "Rajdhani-Bold", 20],
			[str(k), 120, Color.WHITE, "Rajdhani-Bold", 20],
			["%.2f" % (float(k) / maxf(1.0, float(d))), 90, UI.DIM, "Rajdhani-SemiBold", 19],
			[str(_lb_val(r, "matches")), 80, UI.DIM, "Rajdhani-SemiBold", 19]]
		for c in cells:
			var l0 := UI.lbl(c[0], c[4], c[2], c[3])
			l0.custom_minimum_size = Vector2(c[1], 0)
			rh.add_child(l0)
		var rinf: Dictionary = GS.rank_info(_lb_val(r, "rp"))
		var rcell := UI.hbox(6)
		rcell.custom_minimum_size = Vector2(210, 0)
		rh.add_child(rcell)
		var ric := TextureRect.new()
		ric.texture = rinf["icon"]; ric.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ric.custom_minimum_size = Vector2(34, 34)
		ric.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rcell.add_child(ric)
		var rl := UI.lbl("%s  %d" % [rinf["name"], _lb_val(r, "rp")], 17, rinf["color"], "Rajdhani-Bold")
		rl.clip_text = true
		rcell.add_child(rl)
		for c in cells2:
			var l := UI.lbl(c[0], c[4], c[2], c[3])
			l.custom_minimum_size = Vector2(c[1], 0)
			l.clip_text = true
			rh.add_child(l)
		row.modulate.a = 0.0
		var tw := row.create_tween()
		tw.tween_interval(0.02 * i)
		tw.tween_property(row, "modulate:a", 1.0, 0.25)

func _lb_card(i: int, r: Dictionary, c: Color, online: bool) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(300, 150 if i == 0 else 130)
	pc.size_flags_vertical = Control.SIZE_SHRINK_END
	var sbx := UI.sb(Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.95), c, 2, 6, 14)
	pc.add_theme_stylebox_override("panel", sbx)
	var vv := UI.vbox(2)
	pc.add_child(vv)
	var h := UI.hbox(8)
	vv.add_child(h)
	h.add_child(UI.lbl(["1.", "2.", "3."][i], 40, c, "Teko"))
	var nm := UI.lbl(str(r.get("username", "?")), 26, Color.WHITE, "RussoOne-Regular")
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(200, 0)
	h.add_child(nm)
	var stat := ""
	match _lb_sort:
		"wins": stat = "%d galibiyet" % _lb_val(r, "wins")
		"kills": stat = "%d öldürme" % _lb_val(r, "kills")
		"rp": stat = "%s  •  %d RP" % [GS.rank_info(_lb_val(r, "rp"))["name"], _lb_val(r, "rp")]
		_: stat = "Seviye %d" % _lb_val(r, "level")
	var srow := UI.hbox(8)
	vv.add_child(srow)
	var semb := TextureRect.new()
	semb.texture = GS.rank_info(_lb_val(r, "rp"))["icon"]; semb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	semb.custom_minimum_size = Vector2(44, 44); semb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	srow.add_child(semb)
	srow.add_child(UI.lbl(stat, 22, c.lightened(0.2), "Rajdhani-Bold"))
	vv.add_child(UI.lbl("● çevrimiçi" if online else "çevrimdışı", 16, UI.GREEN if online else UI.DIM, "Rajdhani-SemiBold"))
	pc.pivot_offset = pc.custom_minimum_size / 2
	pc.scale = Vector2(0.9, 0.9)
	pc.create_tween().tween_property(pc, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return pc

func _code() -> String:
	var abc := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var c := ""
	for i in 6:
		c += abc[randi() % abc.length()]
	return c

func create_room() -> void:
	if Online.relay_url == "":
		m._toast("Maç sunucusu (relay) henüz kurulmadı.", UI.RED); return
	if str(room_cfg.get("name", "")).strip_edges() == "" or room_cfg["name"] == "Arkadaş Odası":
		room_cfg["name"] = "%s'in Odası" % Online.username
	if Net.join(_code(), Online.uid, Online.username):
		m.show_page("netroom")

func join_room(code: String) -> void:
	if Online.relay_url == "":
		m._toast("Maç sunucusu (relay) henüz kurulmadı.", UI.RED); return
	if Net.join(code, Online.uid, Online.username):
		m.show_page("netroom")

func leave_room() -> void:
	if Net.is_host():
		Online.close_room(Net.code)
	Net.leave()
	Online.set_status("lobby")
	m.show_page("rooms")

func page_room() -> void:
	room_box = Control.new()
	room_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.content.add_child(room_box)
	_refresh_room()

func _refresh_room() -> void:
	if m.page != "netroom" or room_box == null or not is_instance_valid(room_box):
		return
	if not Net.active():
		UI.clear(m.content)
		room_box = Control.new(); room_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.content.add_child(room_box)
		var w := UI.lbl("Odaya bağlanılıyor...", 26, UI.ACCENT2, "RussoOne-Regular", HORIZONTAL_ALIGNMENT_CENTER)
		w.set_anchors_preset(Control.PRESET_CENTER); w.position = Vector2(-300, -20); w.custom_minimum_size = Vector2(600, 0)
		room_box.add_child(w)
		return
	Online.set_status("room", Net.code)
	UI.clear(m.content)
	room_box = Control.new(); room_box.set_anchors_preset(Control.PRESET_FULL_RECT); room_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.content.add_child(room_box)
	var players: Array = []
	var ids: Array = Net.members.keys()
	for i in ids.size():
		var id: String = ids[i]
		var mem: Dictionary = Net.members[id]
		players.append({"name": str(mem.get("name", "?")), "lvl": int(mem.get("lvl", 1)), "team": "a" if i % 2 == 0 else "b",
			"you": id == Net.my_id, "host": id == Net.host_id, "ready": true, "rp": int(mem.get("rp", 0))})
	var host := Net.is_host()
	var o := {"title": str(room_cfg["name"]), "no": Net.code, "map": room_cfg["map"], "mode": room_cfg["mode"], "time": room_cfg["time"], "target": room_cfg["target"],
		"teams": GS.MODES[room_cfg["mode"]]["teams"], "players": players,
		"info_extra": [["Kod", Net.code], ["Oyuncu", "%d / 10" % players.size()], ["Dereceli", "EVET" if room_cfg.get("ranked", false) else "hayır"], ["Sesli sohbet", "V basılı tut"]],
		"on_leave": leave_room,
		"on_invite": _invite_dialog,
		"on_chat": func(t):
			Net.send({"t": "chat", "n": Online.username, "m": t})
			_add_chat(Online.username, t, UI.ACCENT2),
		"host_box": func(box):
			if host:
				box.add_child(UI.lbl("ODA AYARLARI", 16, UI.DIM, "Rajdhani-Bold"))
				box.add_child(UI.lbl("%s  •  %s" % [GS.MAPS[room_cfg["map"]]["name"], GS.MODES[room_cfg["mode"]]["name"]], 18, Color.WHITE, "Rajdhani-Bold"))
				box.add_child(UI.lbl(("İlk %d tur" % int(room_cfg.get("target", 6))) if room_cfg["mode"] == "sabotaj" else ("%d dk  •  hedef %d" % [int(room_cfg.get("time", 10)), int(room_cfg.get("target", 50))]), 15, UI.DIM, "Rajdhani-SemiBold"))
				box.add_child(UI.btn("⚙ HARİTA / MOD / KURALLAR", func():
					var c: Dictionary = room_cfg.duplicate()
					c["_edit"] = true
					m._room_dialog(c, true, func(nc): room_cfg = nc; _send_cfg()), 15, true, 0, 42))
			else:
				box.add_child(UI.lbl("KULLANICI LİSTESİ", 16, UI.DIM, "Rajdhani-Bold"))
				for pl in players:
					box.add_child(UI.lbl(("★ " if pl["host"] else "• ") + str(pl["name"]), 16, UI.GOLD if pl["host"] else UI.TEXT, "Rajdhani-SemiBold")),
		"wait_text": "Kurucunun maçı başlatması bekleniyor..."}
	if host:
		o["on_start"] = func(_b): start_match()
		o["start_text"] = "MAÇI BAŞLAT"
	var lay: Dictionary = m.room_layout(o)
	room_chat = lay["chat"]
	voice_lbl = UI.lbl("", 18, UI.GREEN, "Rajdhani-Bold")
	voice_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	voice_lbl.offset_left = -300; voice_lbl.offset_right = 300; voice_lbl.offset_top = 6
	voice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_lbl.add_theme_constant_override("outline_size", 5)
	voice_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	voice_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_box.add_child(voice_lbl)
	for line in chat_log:
		_chat_line(line[0], line[1], line[2])
	if host:
		_publish()

func _invite_dialog() -> void:
	var v: VBoxContainer = m._modal(560, 0)
	var th := UI.hbox(8)
	v.add_child(th)
	th.add_child(UI.header("ARKADAŞ DAVET ET", 24))
	th.add_child(UI.spacer())
	th.add_child(UI.btn("✕", m._close_modal, 18, false, 40, 36))
	v.add_child(UI.lbl("Oda kodu: %s" % Net.code, 20, UI.GOLD, "RussoOne-Regular"))
	v.add_child(UI.btn("KODU KOPYALA", func(): DisplayServer.clipboard_set(Net.code); m._toast("Oda kodu kopyalandı", UI.GREEN), 15, false, 160, 36))
	var nf := 0
	for f in Online.friends:
		if bool(f["pending"]) or not bool(f["online"]):
			continue
		nf += 1
		v.add_child(UI.btn("+  " + str(f["username"]), func():
			var e: String = await Online.invite(str(f["user_id"]), Net.code, str(room_cfg["name"]))
			m._toast("Davet gönderildi" if e == "" else e, UI.GREEN if e == "" else UI.RED), 16, false, 0, 40))
	if nf == 0:
		v.add_child(UI.lbl("Çevrimiçi arkadaşın yok (ARKADAŞLAR sekmesinden ekleyebilirsin).", 16, UI.DIM, "Rajdhani-SemiBold"))

var chat_log: Array = []

func _add_chat(who: String, t: String, c: Color) -> void:
	chat_log.append([who, t, c])
	if chat_log.size() > 60:
		chat_log.pop_front()
	if room_chat and is_instance_valid(room_chat):
		_chat_line(who, t, c)

func _chat_line(who: String, t: String, c: Color) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.custom_minimum_size = Vector2(400, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = "[color=#%s][b]%s:[/b][/color] %s" % [c.to_html(false), who.replace("[", "("), t.replace("[", "(")]
	room_chat.add_child(l)

func _sys(t: String) -> void:
	_add_chat("SİSTEM", t, Color("ffd24a"))

func _send_cfg() -> void:
	Net.send({"t": "cfg", "cfg": room_cfg})
	_publish()
	_refresh_room()

func _publish() -> void:
	if Net.is_host():
		Online.publish_room(Net.code, room_cfg, Net.members.size(), "lobby")

var voice_lbl: Label
func tick(delta: float) -> void:
	if voice_lbl and is_instance_valid(voice_lbl):
		var names: Array = []
		if Voice.is_sending():
			names.append("SEN")
		for id in Voice.speaking.keys():
			names.append(str(Net.members.get(id, {}).get("name", "?")))
		var open: bool = str(GS.settings.get("voice_mode", "ptt")) == "open"
		var lv := int(clampf(Voice.level * 40.0, 0, 10))
		var meter := "   MİK " + "▮".repeat(lv) + "▯".repeat(10 - lv)
		var hint := ("◎ Açık mikrofon: konuşman yeterli" if open else "◎ V tuşuna basılı tutarak konuş") + "   (gönderilen %d • alınan %d)" % [Voice.sent, Voice.received]
		if Voice.last_error != "":
			hint = "✖ " + Voice.last_error + " — Ayarlar > Ses > Mikrofonu test et"
		voice_lbl.text = (("◉ KONUŞUYOR: " + ", ".join(names)) if names.size() > 0 else hint) + (meter if Voice.talking else "")
		voice_lbl.modulate = Color(1, 1, 1, 1.0 if names.size() > 0 else 0.6)
	_pub_t -= delta
	if _pub_t <= 0 and Net.active() and Net.is_host():
		_pub_t = 30.0
		_publish()

func start_match() -> void:
	if not Net.is_host():
		return
	var ids: Array = Net.members.keys()
	var teams := {}
	for i in ids.size():
		teams[ids[i]] = "a" if i % 2 == 0 else "b"
	var cfg: Dictionary = room_cfg.duplicate()
	cfg["net"] = true
	cfg["teams_map"] = teams
	cfg["seed"] = randi()
	cfg["start_at"] = Time.get_unix_time_from_system() + 2.0
	Net.send({"t": "start", "cfg": cfg})
	Online.publish_room(Net.code, room_cfg, ids.size(), "match")
	_launch(cfg)

func _launch(cfg: Dictionary) -> void:
	Online.set_status("match", Net.code)
	var c := cfg.duplicate()
	c["bots"] = 0
	c["diff"] = 1
	c["team"] = str(cfg["teams_map"].get(Net.my_id, "a"))
	c["no"] = 0
	m.main.start_match(c)

func _on_net(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"chat":
			_add_chat(str(d.get("n", "?")), str(d.get("m", "")), Color.WHITE)
		"cfg":
			if d.get("cfg") is Dictionary:
				room_cfg = d["cfg"]
				_refresh_room()
		"start":
			# the host started: join even if you were looking at the bag / market
			if d.get("cfg") is Dictionary and str(d.get("from", "")) == Net.host_id:
				if m.modal:
					m._close_modal()
				_launch(d["cfg"])
		"hello_room":
			if Net.is_host():
				Net.send_to(str(d["from"]), {"t": "cfg", "cfg": room_cfg})
