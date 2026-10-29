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
	_c(Net.disconnected_room, func(why): if m.page == "netroom": m._toast(why, UI.RED); m.show_page("rooms"))
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
	m.soldier.visible = true
	var p := UI.panel(UI.BG, UI.LINE, 18)
	m._margin(p, 28, 18, 560, 24)
	m.content.add_child(p)
	room_box = UI.vbox(10)
	p.add_child(room_box)
	_refresh_room()

func _refresh_room() -> void:
	if m.page != "netroom" or room_box == null or not is_instance_valid(room_box):
		return
	for c in room_box.get_children():
		c.queue_free()
	var v := room_box
	var th := UI.hbox(10)
	v.add_child(th)
	th.add_child(UI.header(str(room_cfg["name"]) if Net.is_host() else "ONLINE ODA", 28))
	th.add_child(UI.spacer())
	th.add_child(UI.lbl("KOD: %s" % Net.code, 22, UI.GOLD, "RussoOne-Regular"))
	th.add_child(UI.btn("KODU KOPYALA", func(): DisplayServer.clipboard_set(Net.code); m._toast("Oda kodu kopyalandı", UI.GREEN), 15, false, 140, 38))
	th.add_child(UI.btn("ODADAN ÇIK", leave_room, 16, false, 140, 38))
	if not Net.active():
		v.add_child(UI.lbl("Odaya bağlanılıyor...", 20, UI.ACCENT2, "Rajdhani-Bold"))
		return
	Online.set_status("room", Net.code)
	var body := UI.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# members
	var mv := UI.vbox(6)
	mv.custom_minimum_size = Vector2(430, 0)
	body.add_child(mv)
	mv.add_child(UI.lbl("OYUNCULAR (%d/10)" % Net.members.size(), 20, UI.ACCENT2, "Rajdhani-Bold"))
	var ids: Array = Net.members.keys()
	for i in ids.size():
		var id: String = ids[i]
		var row := UI.panel(Color(1, 1, 1, 0.04), UI.ACCENT if id == Net.host_id else UI.LINE, 8)
		mv.add_child(row)
		var h := UI.hbox(8)
		row.add_child(h)
		var team := "a" if i % 2 == 0 else "b"
		h.add_child(UI.lbl("●", 20, GS.TEAM_COLORS.get(team, Color.WHITE), "Rajdhani-Bold"))
		h.add_child(UI.lbl(str(Net.members[id]["name"]) + ("  (sen)" if id == Net.my_id else ""), 19, Color.WHITE, "Rajdhani-Bold"))
		h.add_child(UI.spacer())
		if id == Net.host_id:
			h.add_child(UI.lbl("👑 KURUCU", 15, UI.GOLD, "Rajdhani-Bold"))
	# settings + invite + chat
	var rv := UI.vbox(8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rv)
	rv.add_child(UI.lbl("HARİTA: %s   •   MOD: %s   •   SÜRE: %d dk   •   HEDEF: %d" % [GS.MAPS[room_cfg["map"]]["name"], GS.MODES[room_cfg["mode"]]["name"], int(room_cfg["time"]), int(room_cfg["target"])], 18, Color.WHITE, "Rajdhani-Bold"))
	if Net.is_host():
		var mh := UI.hbox(6)
		rv.add_child(mh)
		for mp in GS.MAPS.keys():
			mh.add_child(UI.btn(GS.MAPS[mp]["name"], func(): room_cfg["map"] = mp; _send_cfg(), 15, room_cfg["map"] == mp, 0, 34))
		var md := UI.hbox(6)
		rv.add_child(md)
		for mo in ["tdm", "ffa", "gungame", "knife", "sniper"]:
			if GS.MODES.has(mo):
				md.add_child(UI.btn(GS.MODES[mo]["name"], func(): room_cfg["mode"] = mo; _send_cfg(), 15, room_cfg["mode"] == mo, 0, 34))
	var inv := UI.hbox(6)
	rv.add_child(inv)
	inv.add_child(UI.lbl("Arkadaş davet et:", 16, UI.DIM, "Rajdhani-Bold"))
	var nf := 0
	for f in Online.friends:
		if bool(f["pending"]) or not bool(f["online"]):
			continue
		nf += 1
		inv.add_child(UI.btn("+ " + str(f["username"]), func():
			var e: String = await Online.invite(str(f["user_id"]), Net.code, str(room_cfg["name"]))
			m._toast("Davet gönderildi" if e == "" else e, UI.GREEN if e == "" else UI.RED), 15, false, 0, 34))
	if nf == 0:
		inv.add_child(UI.lbl("çevrimiçi arkadaş yok (ARKADAŞLAR sekmesinden ekle)", 15, UI.DIM, "Rajdhani-SemiBold"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 260)
	rv.add_child(sc)
	room_chat = UI.vbox(2)
	sc.add_child(room_chat)
	for line in chat_log:
		_chat_line(line[0], line[1], line[2])
	var ch := UI.hbox(6)
	rv.add_child(ch)
	var ce := LineEdit.new()
	ce.placeholder_text = "Mesaj yaz..."
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.custom_minimum_size = Vector2(0, 40)
	ch.add_child(ce)
	var send := func():
		var t := ce.text.strip_edges()
		if t == "": return
		Net.send({"t": "chat", "n": Online.username, "m": t})
		_add_chat(Online.username, t, UI.ACCENT2)
		ce.text = ""
	ce.text_submitted.connect(func(_x): send.call())
	ch.add_child(UI.btn("GÖNDER", send, 15, false, 100, 40))
	if Net.is_host():
		var go := UI.btn("▶  MAÇI BAŞLAT", start_match, 24, true, 0, 60)
		rv.add_child(go)
		_publish()
	else:
		rv.add_child(UI.lbl("Kurucunun maçı başlatması bekleniyor...", 18, UI.ACCENT2, "Rajdhani-Bold"))

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
	l.custom_minimum_size = Vector2(600, 0)
	l.text = "[color=#%s][b]%s:[/b][/color] %s" % [c.to_html(false), who, t]
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
	if _pub_t <= 0 and Net.active() and Net.is_host() and m.page == "netroom":
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
			if m.page == "netroom" and d.get("cfg") is Dictionary:
				_launch(d["cfg"])
		"hello_room":
			if Net.is_host():
				Net.send_to(str(d["from"]), {"t": "cfg", "cfg": room_cfg})
