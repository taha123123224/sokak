extends Node
## Push-to-talk voice chat over the room relay (autoload "Voice").
## Mic -> AudioEffectCapture -> 11 kHz mono -> 8-bit mu-law -> binary WebSocket packet.
## Packet: 'V' (0x56), id length, id bytes, samples.  The relay forwards binary packets unchanged.
## Receiving: one AudioStreamGenerator per speaker (decoded + upsampled).

const RATE := 11025
const SEND_EVERY := 0.06            # seconds of audio per packet (~660 bytes)

var talking := false
var enabled := true
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _bus := -1
var _acc := PackedFloat32Array()
var _t := 0.0
var _players := {}                  # sender id -> {"p": AudioStreamPlayer, "pb": playback, "t": last packet time}
var speaking := {}                  # sender id -> seconds left of "speaking" indicator

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ensure_mic() -> bool:
	if _capture:
		return true
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return false
	_bus = AudioServer.get_bus_index("Mic")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Mic")
		AudioServer.set_bus_mute(_bus, true)          # never play your own mic locally
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(_bus, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	return true

func set_talking(on: bool) -> void:
	if on == talking:
		return
	if on and (not enabled or not Net.active() or not _ensure_mic()):
		return
	talking = on
	if on:
		_capture.clear_buffer()
		_acc.clear()
		_mic.play()
	elif _mic:
		_mic.stop()

func _process(delta: float) -> void:
	for k in speaking.keys():
		speaking[k] = float(speaking[k]) - delta
		if speaking[k] <= 0:
			speaking.erase(k)
	if not talking or _capture == null:
		return
	var mix := AudioServer.get_mix_rate()
	var step := mix / RATE
	var n := _capture.get_frames_available()
	if n > 0:
		var fr := _capture.get_buffer(n)
		var i := 0.0
		while i < fr.size():
			var v := fr[int(i)]
			_acc.append((v.x + v.y) * 0.5)
			i += step
	_t += delta
	if _t >= SEND_EVERY and _acc.size() > 0:
		_t = 0.0
		_send(_acc)
		_acc.clear()

static func _mulaw_enc(x: float) -> int:
	var s := 0x80 if x < 0.0 else 0
	var m := clampf(absf(x), 0.0, 1.0)
	var y := log(1.0 + 255.0 * m) / log(256.0)
	return s | int(y * 127.0)

static func _mulaw_dec(b: int) -> float:
	var s := -1.0 if (b & 0x80) else 1.0
	var y := float(b & 0x7f) / 127.0
	return s * (pow(256.0, y) - 1.0) / 255.0

func _send(samples: PackedFloat32Array) -> void:
	var idb := Net.my_id.to_utf8_buffer()
	var pkt := PackedByteArray()
	pkt.append(0x56)
	pkt.append(idb.size())
	pkt.append_array(idb)
	var peak := 0.0
	for x in samples:
		peak = maxf(peak, absf(x))
	if peak < 0.012:                     # silence gate: don't send room noise
		return
	for x in samples:
		pkt.append(_mulaw_enc(x * 1.6))
	Net.send_binary(pkt)

## called by Net for incoming binary packets
func on_packet(pkt: PackedByteArray) -> void:
	if pkt.size() < 3 or pkt[0] != 0x56:
		return
	var l: int = pkt[1]
	if pkt.size() < 2 + l:
		return
	var from := pkt.slice(2, 2 + l).get_string_from_utf8()
	if from == Net.my_id:
		return
	var e: Dictionary = _players.get(from, {})
	if e.is_empty():
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = AudioServer.get_mix_rate()
		gen.buffer_length = 0.5
		p.stream = gen
		p.bus = "Master"
		p.volume_db = linear_to_db(maxf(float(GS.settings.get("vol_voice", 1.0)), 0.001))
		add_child(p)
		p.play()
		e = {"p": p, "pb": p.get_stream_playback()}
		_players[from] = e
	speaking[from] = 0.35
	var pb: AudioStreamGeneratorPlayback = e["pb"]
	var up := int(round(AudioServer.get_mix_rate() / RATE))
	var last := 0.0
	for i in range(2 + l, pkt.size()):
		var v := _mulaw_dec(pkt[i])
		for k in up:                       # linear upsample
			var s := lerpf(last, v, float(k + 1) / up)
			if pb.can_push_buffer(1):
				pb.push_frame(Vector2(s, s))
		last = v

func clear() -> void:
	for k in _players.keys():
		(_players[k]["p"] as Node).queue_free()
	_players.clear()
	speaking.clear()
	set_talking(false)
