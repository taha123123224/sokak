extends Node
## Room connection through the Cloudflare relay (WebSocket). The first player in a room is the host.
## Messages are small JSON dictionaries: {"t": type, ...}; the relay adds "from" (sender id).

signal connected_room(code: String)
signal disconnected_room(reason: String)
signal member_joined(id: String, name: String)
signal member_left(id: String)
signal host_changed(id: String)
signal message(m: Dictionary)

var ws: WebSocketPeer
var code := ""
var my_id := ""
var my_name := ""
var host_id := ""
var members := {}          # id -> {"name":..., "team":..., "ready":...}
var _open := false
var _was_open := false
var ping_ms := 0
var _ping_t := 0.0

func active() -> bool:
	return ws != null and _open

func is_host() -> bool:
	return host_id != "" and host_id == my_id

func join(room_code: String, pid: String, pname: String) -> bool:
	leave()
	var base: String = Online.relay_url
	if base == "":
		return false
	code = room_code.to_upper()
	my_id = pid
	my_name = pname
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var u := base.replace("https://", "wss://").replace("http://", "ws://") + "/room/%s?id=%s&name=%s" % [code, pid.uri_encode(), pname.uri_encode()]
	var e := ws.connect_to_url(u)
	if e != OK:
		ws = null
		return false
	_open = false
	_was_open = false
	members.clear()
	return true

func leave() -> void:
	if ws:
		ws.close(1000, "bye")
	ws = null
	_open = false
	members.clear()
	host_id = ""
	code = ""

func send(m: Dictionary) -> void:
	if ws and _open:
		ws.send_text(JSON.stringify(m))

func send_to(id: String, m: Dictionary) -> void:
	m["to"] = id
	send(m)

func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			_was_open = true
		_ping_t -= delta
		if _ping_t <= 0:
			_ping_t = 3.0
			send({"t": "ping", "ts": Time.get_ticks_msec()})
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary:
				_handle(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		var why := "Bağlantı kapandı" if _was_open else "Odaya bağlanılamadı (oda dolu olabilir)"
		ws = null
		_open = false
		disconnected_room.emit(why)

func _handle(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"welcome":
			host_id = str(d.get("host", ""))
			members.clear()
			for m in d.get("members", []):
				members[str(m["id"])] = {"name": str(m["name"])}
			connected_room.emit(code)
			host_changed.emit(host_id)
		"joined":
			members[str(d["id"])] = {"name": str(d.get("name", "Oyuncu"))}
			host_id = str(d.get("host", host_id))
			member_joined.emit(str(d["id"]), str(d.get("name", "Oyuncu")))
		"left":
			members.erase(str(d["id"]))
			member_left.emit(str(d["id"]))
			var nh := str(d.get("host", host_id))
			if nh != host_id:
				host_id = nh
				host_changed.emit(host_id)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(d.get("ts", 0))
		_:
			message.emit(d)
