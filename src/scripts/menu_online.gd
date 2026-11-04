extends RefCounted
## Online pages for the lobby menu: ARKADAŞLAR (friends, requests, search), online room list, online room
## lobby (members, chat, invite friends, host settings, start) and the incoming-invite popup.

var m   # menu.gd instance

var _conns: Array = []

func _init(menu) -> void:
	m = menu
	_c(Online.invite_received, _on_invite)
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

func page_friends() -> void:
	if need_login():
		return
	m.set_showcase(GS.active_set().get("ana", "ak47"))
	var p := UI.panel(UI.BG, UI.LINE, 18)
	m._margin(p, 28, 18, 560, 24)
	m.content.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	var th := UI.hbox(10)
	v.add_child(th)
	th.add_child(UI.header("ARKADAŞLAR", 28))
	th.add_child(UI.spacer())
	th.add_child(UI.lbl("Sen: %s" % Online.username, 18, UI.ACCENT2, "Rajdhani-Bold"))
	th.add_child(UI.btn("YENİLE", func(): await Online.refresh_friends(); m.show_page("friends"), 16, false, 110, 40))
	# add friend
	var ah := UI.hbox(8)
	v.add_child(ah)
	search_box = LineEdit.new()
	search_box.placeholder_text = "Kullanıcı adı ara..."
	search_box.custom_minimum_size = Vector2(420, 46)
	search_box.add_theme_font_size_override("font_size", 20)
	ah.add_child(search_box)
	ah.add_child(UI.btn("ARA", _search, 18, true, 120, 46))
	search_box.text_submitted.connect(func(_t): _search())
	search_res = UI.vbox(4)
	v.add_child(search_res)
	var cols := UI.hbox(20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# incoming / outgoing requests
	var req := UI.vbox(6)
	req.custom_minimum_size = Vector2(420, 0)
	cols.add_child(req)
	req.add_child(UI.lbl("İSTEKLER", 20, UI.ACCENT2, "Rajdhani-Bold"))
	var any_req := false
	for f in Online.friends:
		if not bool(f["pending"]):
			continue
		any_req = true
		var row := UI.panel(Color(1, 1, 1, 0.04), UI.LINE, 8)
		req.add_child(row)
		var h := UI.hbox(8)
		row.add_child(h)
		h.add_child(UI.lbl(str(f["username"]), 20, Color.WHITE, "Rajdhani-Bold"))
		h.add_child(UI.spacer())
		if bool(f["incoming"]):
			h.add_child(UI.btn("KABUL ET", func(): await Online.accept_friend(int(f["friendship_id"])); SFX.play("success", -6); m.show_page("friends"), 15, true, 110, 36))
			h.add_child(UI.btn("REDDET", func(): await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 15, false, 90, 36))
		else:
			h.add_child(UI.lbl("bekliyor...", 16, UI.DIM, "Rajdhani-SemiBold"))
			h.add_child(UI.btn("İPTAL", func(): await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 15, false, 80, 36))
	if not any_req:
		req.add_child(UI.lbl("Bekleyen istek yok.", 17, UI.DIM, "Rajdhani-SemiBold"))
	# friend list
	var fl := UI.vbox(6)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(fl)
	var cnt := 0
	for f in Online.friends:
		if not bool(f["pending"]):
			cnt += 1
	fl.add_child(UI.lbl("ARKADAŞ LİSTESİ (%d)" % cnt, 20, UI.ACCENT2, "Rajdhani-Bold"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fl.add_child(sc)
	var list := UI.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if cnt == 0:
		list.add_child(UI.lbl("Henüz arkadaşın yok. Yukarıdan kullanıcı adıyla arayıp ekle!", 17, UI.DIM, "Rajdhani-SemiBold"))
	for f in Online.friends:
		if bool(f["pending"]):
			continue
		var row := UI.panel(Color(1, 1, 1, 0.04), UI.LINE, 8)
		list.add_child(row)
		var h := UI.hbox(10)
		row.add_child(h)
		var on: bool = bool(f["online"]) and str(f["status"]) != "offline"
		var dot := UI.lbl("●", 22, UI.GREEN if on else Color(0.4, 0.42, 0.46), "Rajdhani-Bold")
		h.add_child(dot)
		var nv := UI.vbox(0)
		h.add_child(nv)
		nv.add_child(UI.lbl(str(f["username"]), 20, Color.WHITE, "Rajdhani-Bold"))
		var st_txt := "Çevrimdışı"
		if on:
			st_txt = {"lobby": "Lobide", "room": "Odada", "match": "Maçta"}.get(str(f["status"]), "Çevrimiçi")
		nv.add_child(UI.lbl("Seviye %d  •  %s" % [int(f["level"]), st_txt], 15, UI.GREEN if on else UI.DIM, "Rajdhani-SemiBold"))
		h.add_child(UI.spacer())
		if on and Net.active() and Net.code != "":
			h.add_child(UI.btn("DAVET ET", func():
				var e: String = await Online.invite(str(f["user_id"]), Net.code, str(room_cfg.get("name", "Oda")))
				m._toast("Davet gönderildi: " + str(f["username"]) if e == "" else e, UI.GREEN if e == "" else UI.RED), 15, true, 110, 36))
		if on and f.get("room") != null and str(f["room"]) != "" and str(f["room"]) != Net.code:
			h.add_child(UI.btn("KATIL", func(): join_room(str(f["room"])), 15, false, 90, 36))
		h.add_child(UI.btn("✕", func(): await Online.remove_friend(int(f["friendship_id"])); m.show_page("friends"), 15, false, 40, 36))

func _search() -> void:
	for c in search_res.get_children():
		c.queue_free()
	var res: Array = await Online.search_users(search_box.text)
	if res.is_empty():
		search_res.add_child(UI.lbl("Kullanıcı bulunamadı.", 16, UI.DIM, "Rajdhani-SemiBold"))
		return
	for u in res:
		var h := UI.hbox(8)
		search_res.add_child(h)
		h.add_child(UI.lbl("%s  (Svy %d)" % [u["username"], int(u.get("level", 1))], 18, Color.WHITE, "Rajdhani-Bold"))
		h.add_child(UI.btn("ARKADAŞ EKLE", func():
			var e: String = await Online.add_friend(str(u["id"]))
			m._toast("İstek gönderildi: " + str(u["username"]) if e == "" else e, UI.GREEN if e == "" else UI.RED)
			m.show_page("friends"), 15, true, 150, 34))

# ================================================================ invites
func _on_invite(inv: Dictionary) -> void:
	SFX.play("medal", -4)
	var p := UI.panel(Color(0.04, 0.06, 0.09, 0.96), UI.ACCENT, 14)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-500, 100)
	p.custom_minimum_size = Vector2(460, 0)
	m.ui.add_child(p)
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.lbl("ODA DAVETİ", 18, UI.ACCENT2, "Rajdhani-Bold"))
	v.add_child(UI.lbl("%s seni \"%s\" odasına davet ediyor." % [inv["from"], inv.get("room_name", "Oda")], 18, Color.WHITE, "Rajdhani-SemiBold"))
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.btn("KATIL", func(): p.queue_free(); Online.drop_invite(int(inv["id"])); join_room(str(inv["room"])), 18, true, 140, 44))
	h.add_child(UI.btn("REDDET", func(): p.queue_free(); Online.drop_invite(int(inv["id"])), 18, false, 120, 44))
	m.get_tree().create_timer(25.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

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
		"info_extra": [["Kod", Net.code], ["Oyuncu", "%d / 10" % players.size()], ["Dereceli", "EVET" if room_cfg.get("ranked", false) else "hayır"]],
		"on_leave": leave_room,
		"on_invite": _invite_dialog,
		"on_chat": func(t):
			Net.send({"t": "chat", "n": Online.username, "m": t})
			_add_chat(Online.username, t, UI.ACCENT2),
		"host_box": func(box):
			if host:
				box.add_child(UI.lbl("HARİTA", 14, UI.DIM, "Rajdhani-Bold"))
				var mg := GridContainer.new(); mg.columns = 3
				mg.add_theme_constant_override("h_separation", 4); mg.add_theme_constant_override("v_separation", 4)
				box.add_child(mg)
				for mp in GS.MAPS.keys():
					mg.add_child(UI.btn(GS.MAPS[mp]["name"], func(): room_cfg["map"] = mp; _send_cfg(), 13, room_cfg["map"] == mp, 100, 30))
				box.add_child(UI.lbl("MOD", 14, UI.DIM, "Rajdhani-Bold"))
				var dg := GridContainer.new(); dg.columns = 3
				dg.add_theme_constant_override("h_separation", 4); dg.add_theme_constant_override("v_separation", 4)
				box.add_child(dg)
				for mo in ["tdm", "ffa", "gungame", "knife", "sniper"]:
					if GS.MODES.has(mo):
						dg.add_child(UI.btn(GS.MODES[mo]["name"], func(): room_cfg["mode"] = mo; _send_cfg(), 13, room_cfg["mode"] == mo, 100, 30))
				box.add_child(UI.btn("★ DERECELİ: " + ("AÇIK" if room_cfg.get("ranked", false) else "KAPALI"), func(): room_cfg["ranked"] = not room_cfg.get("ranked", false); _send_cfg(), 14, room_cfg.get("ranked", false), 0, 32))
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

func tick(delta: float) -> void:
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
