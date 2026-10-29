extends Node
## Online services (Supabase free tier): accounts with username + password, cloud save of the whole
## profile, friends, room invites, public room list and presence (online / in lobby / in match).
## Everything is plain HTTPS REST, so it works behind any home router.

signal logged_in
signal logged_out
signal friends_updated(list: Array)
signal invite_received(inv: Dictionary)
signal error(msg: String)

var url := ""
var anon := ""
var relay_url := ""
var update_manifest := ""
var token := ""
var refresh := ""
var expires_at := 0.0
var uid := ""
var username := ""
var friends: Array = []
var status := "online"
var room := ""
var _hb_t := 0.0
var _inv_t := 0.0
var _fr_t := 0.0
var _save_t := -1.0
var _seen_invites := {}
const SESSION := "user://session.json"
const EMAIL_DOMAIN := "@sokak-oyun.app"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open("res://online_config.json", FileAccess.READ)
	if f:
		var c = JSON.parse_string(f.get_as_text())
		if c is Dictionary:
			url = str(c.get("supabase_url", "")).trim_suffix("/").replace("/rest/v1", "")
			anon = str(c.get("supabase_anon_key", ""))
			relay_url = str(c.get("relay_url", "")).trim_suffix("/")
			update_manifest = str(c.get("update_manifest", ""))
	# a config next to the exe (or in user://) overrides the built-in one, so keys can change without a rebuild
	for p in [OS.get_executable_path().get_base_dir().path_join("online_config.json"), "user://online_config.json"]:
		if FileAccess.file_exists(p):
			var c2 = JSON.parse_string(FileAccess.get_file_as_string(p))
			if c2 is Dictionary:
				if str(c2.get("supabase_url", "")) != "": url = str(c2["supabase_url"]).trim_suffix("/").replace("/rest/v1", "")
				if str(c2.get("supabase_anon_key", "")) != "": anon = str(c2["supabase_anon_key"])
				if str(c2.get("relay_url", "")) != "": relay_url = str(c2["relay_url"]).trim_suffix("/")
				if str(c2.get("update_manifest", "")) != "": update_manifest = str(c2["update_manifest"])

func configured() -> bool:
	return url != "" and anon != ""

func is_logged_in() -> bool:
	return token != "" and uid != ""

# ---------------------------------------------------------------- HTTP
func _req(method: int, path: String, body = null, extra: PackedStringArray = PackedStringArray(), auth := true) -> Dictionary:
	if not configured():
		return {"ok": false, "code": 0, "data": null, "err": "Online servis yapılandırılmamış"}
	var h := HTTPRequest.new()
	h.timeout = 12.0
	add_child(h)
	var headers := PackedStringArray(["apikey: " + anon, "Content-Type: application/json"])
	# new-style publishable keys (sb_publishable_...) are not JWTs: only send a Bearer token for a logged-in user
	if auth and token != "":
		headers.append("Authorization: Bearer " + token)
	elif not anon.begins_with("sb_"):
		headers.append("Authorization: Bearer " + anon)
	headers.append_array(extra)
	var e := h.request(url + path, headers, method, "" if body == null else JSON.stringify(body))
	if e != OK:
		h.queue_free()
		return {"ok": false, "code": 0, "data": null, "err": "Bağlantı kurulamadı"}
	var r: Array = await h.request_completed
	h.queue_free()
	var code: int = r[1]
	var txt: String = (r[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(txt) if txt != "" else null
	var ok := code >= 200 and code < 300
	var err := ""
	if not ok:
		err = "Sunucuya ulaşılamadı" if code == 0 else _err_text(data, code)
	return {"ok": ok, "code": code, "data": data, "err": err}

func _err_text(d, code: int) -> String:
	var m := ""
	if d is Dictionary:
		m = str(d.get("msg", d.get("message", d.get("error_description", d.get("error", "")))))
	if "Invalid login" in m or "invalid_grant" in m or "invalid_credentials" in m:
		return "Kullanıcı adı veya şifre yanlış"
	if "already registered" in m or "already been registered" in m or "duplicate" in m or code == 409:
		return "Bu kullanıcı adı alınmış"
	if "Password should be" in m:
		return "Şifre en az 6 karakter olmalı"
	if "Signups not allowed" in m or "signup_disabled" in m:
		return "Yeni kayıtlar şu an kapalı (Supabase > Authentication > Sign In / Providers > 'Allow new users to sign up' açılmalı)"
	if "rate limit" in m.to_lower() or code == 429:
		return "Çok fazla deneme yapıldı, birkaç dakika sonra tekrar dene"
	if "User not found" in m:
		return "Böyle bir kullanıcı yok"
	if "JWT" in m or "jwt" in m:
		return "Oturum süresi doldu, tekrar giriş yap"
	if "Email not confirmed" in m:
		return "Supabase'de e-posta onayı kapalı olmalı (Authentication > Providers > Email > Confirm email: KAPALI)"
	return m if m != "" else "Hata (%d)" % code

# ---------------------------------------------------------------- auth
static func valid_username(n: String) -> String:
	if n.length() < 3 or n.length() > 16:
		return "Kullanıcı adı 3-16 karakter olmalı"
	var re := RegEx.create_from_string("^[A-Za-z0-9_ÇĞİÖŞÜçğıöşü]+$")
	if re.search(n) == null:
		return "Sadece harf, rakam ve _ kullanılabilir"
	return ""

func _email(n: String) -> String:
	# Supabase auth needs an e-mail; usernames are mapped to a private pseudo address
	return n.to_lower().uri_encode().replace("%", "x") + EMAIL_DOMAIN

func register(n: String, pw: String) -> String:
	var bad := valid_username(n)
	if bad != "":
		return bad
	if pw.length() < 6:
		return "Şifre en az 6 karakter olmalı"
	var free := await _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/username_free", {"name": n}, PackedStringArray(), false)
	if free["ok"] and free["data"] == false:
		return "Bu kullanıcı adı alınmış"
	var r := await _req(HTTPClient.METHOD_POST, "/auth/v1/signup", {"email": _email(n), "password": pw, "data": {"username": n}}, PackedStringArray(), false)
	if not r["ok"]:
		return r["err"]
	if not (r["data"] is Dictionary) or not r["data"].has("access_token"):
		return "Supabase'de e-posta onayı kapalı olmalı (Authentication > Providers > Email > Confirm email: KAPALI)"
	_take_session(r["data"])
	username = n
	var p := await _req(HTTPClient.METHOD_POST, "/rest/v1/profiles", {"id": uid, "username": n, "data": GS.profile, "level": int(GS.profile.get("level", 1))}, PackedStringArray(["Prefer: return=minimal"]))
	if not p["ok"]:
		return p["err"]
	GS.profile["name"] = n
	GS.save_profile()
	_after_login()
	return ""

func login(n: String, pw: String) -> String:
	var r := await _req(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": _email(n), "password": pw}, PackedStringArray(), false)
	if not r["ok"]:
		return r["err"]
	_take_session(r["data"])
	var ok := await _load_profile()
	if not ok:
		return "Profil yüklenemedi"
	_after_login()
	return ""

func try_resume() -> bool:
	## silent login with the saved refresh token
	if not configured() or not FileAccess.file_exists(SESSION):
		return false
	var s = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
	if not (s is Dictionary) or str(s.get("refresh", "")) == "":
		return false
	refresh = s["refresh"]
	var r := await _req(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh}, PackedStringArray(), false)
	if not r["ok"]:
		return false
	_take_session(r["data"])
	if not await _load_profile():
		return false
	_after_login()
	return true

func logout() -> void:
	if is_logged_in():
		await set_status("offline")
	token = ""; uid = ""; refresh = ""; username = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION))
	logged_out.emit()

func _take_session(d: Dictionary) -> void:
	token = str(d.get("access_token", ""))
	refresh = str(d.get("refresh_token", refresh))
	expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))
	var u: Dictionary = d.get("user", {})
	uid = str(u.get("id", uid))
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	f.store_string(JSON.stringify({"refresh": refresh}))

func _load_profile() -> bool:
	var r := await _req(HTTPClient.METHOD_GET, "/rest/v1/profiles?id=eq.%s&select=username,data" % uid)
	if not r["ok"] or not (r["data"] is Array) or (r["data"] as Array).is_empty():
		return false
	var row: Dictionary = r["data"][0]
	username = str(row["username"])
	var d = row.get("data", {})
	if d is Dictionary and d.size() > 3:
		GS.profile = d          # continue exactly where the account left off
		GS.sanitize_profile()
	GS.profile["name"] = username
	GS.save_profile(true)
	return true

func _after_login() -> void:
	set_status("lobby")
	refresh_friends()
	logged_in.emit()

# ---------------------------------------------------------------- cloud save
func queue_save() -> void:
	if is_logged_in():
		_save_t = 3.0

func save_now() -> void:
	if not is_logged_in():
		return
	_save_t = -1.0
	await _req(HTTPClient.METHOD_PATCH, "/rest/v1/profiles?id=eq." + uid, {"data": GS.profile, "level": int(GS.profile.get("level", 1))}, PackedStringArray(["Prefer: return=minimal"]))

# ---------------------------------------------------------------- presence
func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

func set_status(st: String, rm: String = "") -> void:
	status = st
	room = rm
	if is_logged_in():
		await _req(HTTPClient.METHOD_PATCH, "/rest/v1/profiles?id=eq." + uid, {"status": st, "room": rm if rm != "" else null, "last_seen": _now_iso()}, PackedStringArray(["Prefer: return=minimal"]))

func _process(delta: float) -> void:
	if not is_logged_in():
		return
	if Time.get_unix_time_from_system() > expires_at - 120 and refresh != "":
		expires_at = Time.get_unix_time_from_system() + 60
		_refresh_token()
	_hb_t -= delta
	if _hb_t <= 0:
		_hb_t = 30.0
		set_status(status, room)
	_inv_t -= delta
	if _inv_t <= 0:
		_inv_t = 4.0
		_poll_invites()
	_fr_t -= delta
	if _fr_t <= 0:
		_fr_t = 20.0
		refresh_friends()
	if _save_t > 0:
		_save_t -= delta
		if _save_t <= 0:
			save_now()

func _refresh_token() -> void:
	var r := await _req(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh}, PackedStringArray(), false)
	if r["ok"]:
		_take_session(r["data"])

# ---------------------------------------------------------------- friends
func refresh_friends() -> void:
	var r := await _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_friends", {})
	if r["ok"] and r["data"] is Array:
		friends = r["data"]
		friends_updated.emit(friends)

func search_users(q: String) -> Array:
	q = q.strip_edges()
	if q.length() < 2:
		return []
	var r := await _req(HTTPClient.METHOD_GET, "/rest/v1/profiles?select=id,username,level,last_seen&username=ilike.%s*&id=neq.%s&limit=12" % [q.uri_encode(), uid])
	return r["data"] if r["ok"] and r["data"] is Array else []

func add_friend(target_id: String) -> String:
	var r := await _req(HTTPClient.METHOD_POST, "/rest/v1/friendships", {"requester": uid, "addressee": target_id}, PackedStringArray(["Prefer: return=minimal"]))
	refresh_friends()
	return "" if r["ok"] else ("İstek zaten gönderilmiş" if r["code"] == 409 else r["err"])

func accept_friend(fid: int) -> void:
	await _req(HTTPClient.METHOD_PATCH, "/rest/v1/friendships?id=eq.%d" % fid, {"status": "accepted"}, PackedStringArray(["Prefer: return=minimal"]))
	refresh_friends()

func remove_friend(fid: int) -> void:
	await _req(HTTPClient.METHOD_DELETE, "/rest/v1/friendships?id=eq.%d" % fid, null, PackedStringArray(["Prefer: return=minimal"]))
	refresh_friends()

# ---------------------------------------------------------------- invites
func invite(target_id: String, room_code: String, room_name: String) -> String:
	var r := await _req(HTTPClient.METHOD_POST, "/rest/v1/invites", {"sender": uid, "receiver": target_id, "room": room_code, "room_name": room_name}, PackedStringArray(["Prefer: return=minimal"]))
	return "" if r["ok"] else r["err"]

func _poll_invites() -> void:
	var since := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 600) + "Z"
	var r := await _req(HTTPClient.METHOD_GET, "/rest/v1/invites?select=id,room,room_name,created_at,sender,profiles!invites_sender_fkey(username)&receiver=eq.%s&created_at=gt.%s&order=created_at.desc" % [uid, since])
	if not r["ok"] or not (r["data"] is Array):
		return
	for inv in r["data"]:
		var id := int(inv["id"])
		if _seen_invites.has(id):
			continue
		_seen_invites[id] = true
		var who := "Bir arkadaşın"
		if inv.get("profiles") is Dictionary:
			who = str(inv["profiles"].get("username", who))
		invite_received.emit({"id": id, "room": inv["room"], "room_name": inv.get("room_name", ""), "from": who})

func drop_invite(id: int) -> void:
	await _req(HTTPClient.METHOD_DELETE, "/rest/v1/invites?id=eq.%d" % id, null, PackedStringArray(["Prefer: return=minimal"]))

# ---------------------------------------------------------------- public rooms
func publish_room(code: String, cfg: Dictionary, players: int, state: String = "lobby") -> void:
	if not is_logged_in():
		return
	var body := {"code": code, "host": uid, "name": str(cfg.get("name", "Oda")), "map": str(cfg.get("map", "mahalle")), "mode": str(cfg.get("mode", "tdm")),
		"players": players, "max_players": int(cfg.get("max", 10)), "private": bool(cfg.get("private", false)), "state": state, "updated_at": _now_iso()}
	await _req(HTTPClient.METHOD_POST, "/rest/v1/rooms", body, PackedStringArray(["Prefer: resolution=merge-duplicates,return=minimal"]))

func close_room(code: String) -> void:
	if is_logged_in():
		await _req(HTTPClient.METHOD_DELETE, "/rest/v1/rooms?code=eq." + code, null, PackedStringArray(["Prefer: return=minimal"]))

func list_rooms() -> Array:
	var since := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 120) + "Z"
	var r := await _req(HTTPClient.METHOD_GET, "/rest/v1/rooms?select=*,profiles(username)&private=eq.false&updated_at=gt.%s&order=updated_at.desc&limit=40" % since)
	return r["data"] if r["ok"] and r["data"] is Array else []
