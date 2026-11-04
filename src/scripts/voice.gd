extends Node
## Push-to-talk voice chat over the room relay (autoload "Voice").
## Mic -> AudioEffectCapture -> 11 kHz mono -> 8-bit mu-law -> binary WebSocket packet.
## Packet: 'V' (0x56), id length, id bytes, samples.  The relay forwards it to the other players in the room.
## Receiving: one AudioStreamGenerator per speaker with a small jitter buffer (decoded + resampled).
## Works in the online room screen and in online matches: hold V.

const RATE := 11025
const SEND_EVERY := 0.06            # seconds of audio per packet (~660 bytes)
const GAIN := 1.8

var talking := false
var enabled := true
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _bus := -1
var _acc := PackedFloat32Array()
var _src_pos := 0.0                 # fractional read position for resampling the mic to RATE
var _t := 0.0
var _players := {}                  # sender id -> {"p": AudioStreamPlayer, "pb": playback, "last": float, "pos": float}
var speaking := {}                  # sender id -> seconds left of "speaking" indicator
var level := 0.0                    # current mic peak (HUD meter / settings test)
var testing := false                # settings: mic meter only
var loopback := false               # settings: hear yourself through the voice codec (no server needed)
var sent := 0                       # packets sent / received (shown in the room screen to debug)
var received := 0
var last_error := ""
var _agc := 2.0                      # automatic gain: quiet Windows mics (peak ~0.01) get boosted up to 10x
var _open_talk := 0.0               # open-mic mode: seconds left of "talking" after the voice stops
const OPEN_THRESHOLD := 0.02

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ensure_mic() -> bool:
	if _capture:
		return true
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		last_error = "Mikrofon girişi kapalı"
		return false
	if AudioServer.get_input_device_list().is_empty():
		last_error = "Mikrofon bulunamadı"
		return false
	_bus = AudioServer.get_bus_index("Mic")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Mic")
	# silent but NOT muted: some drivers / Godot versions skip effects on a muted bus, so the capture got nothing
	AudioServer.set_bus_mute(_bus, false)
	AudioServer.set_bus_volume_db(_bus, -80.0)
	AudioServer.set_bus_send(_bus, "Master")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(_bus, _capture, 0)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	return true

func _mic_on() -> void:
	if _mic and not _mic.playing:
		_capture.clear_buffer()
		_mic.play()

func _mic_off_if_idle() -> void:
	if _mic and not talking and not testing and not loopback:
		_mic.stop()

func set_talking(on: bool) -> void:
	if on == talking or _open_mode():
		return
	if on and (not enabled or not Net.active() or not _ensure_mic()):
		return
	talking = on
	if on:
		_acc.clear()
		_src_pos = 0.0
		_mic_on()
	else:
		_mic_off_if_idle()

## settings page: level meter only
func mic_test(on: bool) -> bool:
	if on:
		if not _ensure_mic():
			return false
		testing = true
		_mic_on()
	else:
		testing = false
		_mic_off_if_idle()
	return true

## settings page: hear your own voice after the voice codec (proves mic + encoding + playback all work)
func loop_test(on: bool) -> bool:
	if on:
		if not _ensure_mic():
			return false
		loopback = true
		_acc.clear()
		_mic_on()
	else:
		loopback = false
		_drop_player("__self")
		_mic_off_if_idle()
	return true

## push-to-talk in the online ROOM screen too (matches handle V themselves)
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or e.echo or not e.is_action("voice"):
		return
	if not Net.active():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	enabled = bool(GS.settings.get("voice_on", true))
	if _open_mode():
		return
	set_talking(e.is_pressed())

## true while your voice is actually going out (for the "KONUŞUYOR" indicators)
func is_sending() -> bool:
	return talking and (not _open_mode() or _open_talk > 0.0)

func _open_mode() -> bool:
	return str(GS.settings.get("voice_mode", "ptt")) == "open"

func _process(delta: float) -> void:
	# open-mic mode: the mic listens while you are in an online room / match and talks when you speak
	if _open_mode() and Net.active() and bool(GS.settings.get("voice_on", true)):
		if not talking and _ensure_mic():
			talking = true
			_acc.clear()
			_mic_on()
	elif talking and _open_mode():
		talking = false
		_mic_off_if_idle()
	for k in speaking.keys():
		speaking[k] = float(speaking[k]) - delta
		if speaking[k] <= 0:
			speaking.erase(k)
	if _capture == null or not (talking or testing or loopback):
		level = lerpf(level, 0.0, minf(1.0, delta * 8.0))
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var fr := _capture.get_buffer(n)
	var pk := 0.0
	for f in fr:
		pk = maxf(pk, absf(f.x))
	level = lerpf(level, pk, 0.5)
	if not (talking or loopback):
		return
	# resample mic (44.1 / 48 kHz) to 11025 Hz
	var step := AudioServer.get_mix_rate() / RATE
	while _src_pos < fr.size():
		var v := fr[int(_src_pos)]
		_acc.append((v.x + v.y) * 0.5)
		_src_pos += step
	_src_pos -= fr.size()
	_t += delta
	if _t >= SEND_EVERY and _acc.size() > 0:
		_t = 0.0
		var pkt := _encode(_acc, talking and not _open_mode())
		_acc.clear()
		if pkt.is_empty():
			return
		if loopback:
			_play_samples("__self", pkt, 2)
		if talking:
			if _open_mode():
				_open_talk = 0.6 if level > OPEN_THRESHOLD else _open_talk - SEND_EVERY
				if _open_talk <= 0:
					return
			Net.send_binary(pkt)
			sent += 1

static func _mulaw_enc(x: float) -> int:
	var s := 0x80 if x < 0.0 else 0
	var m := clampf(absf(x), 0.0, 1.0)
	var y := log(1.0 + 255.0 * m) / log(256.0)
	return s | int(y * 127.0)

static func _mulaw_dec(b: int) -> float:
	var s := -1.0 if (b & 0x80) else 1.0
	var y := float(b & 0x7f) / 127.0
	return s * (pow(256.0, y) - 1.0) / 255.0

func _encode(samples: PackedFloat32Array, force: bool = false) -> PackedByteArray:
	var peak := 0.0
	for x in samples:
		peak = maxf(peak, absf(x))
	# push-to-talk sends everything while V is held (a gate here silenced quiet microphones completely);
	# only true digital silence is skipped
	if peak < (0.0005 if force else 0.004):
		return PackedByteArray()
	# automatic gain control toward a peak of ~0.7
	var want := clampf(0.7 / maxf(peak, 0.0001), 1.0, 10.0)
	_agc = lerpf(_agc, want, 0.25 if want < _agc else 0.05)
	var idb := Net.my_id.to_utf8_buffer() if Net.my_id != "" else "self".to_utf8_buffer()
	var pkt := PackedByteArray()
	pkt.append(0x56)
	pkt.append(idb.size())
	pkt.append_array(idb)
	for x in samples:
		pkt.append(_mulaw_enc(clampf(x * _agc, -1.0, 1.0)))
	return pkt

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
	received += 1
	speaking[from] = 0.35
	_play_samples(from, pkt, 2 + l)

func _play_samples(from: String, pkt: PackedByteArray, off: int) -> void:
	if from == "__self":
		off = 2 + pkt[1]
	var e: Dictionary = _players.get(from, {})
	if e.is_empty():
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = AudioServer.get_mix_rate()
		gen.buffer_length = 0.6
		p.stream = gen
		p.bus = "Master"
		add_child(p)
		p.play()
		e = {"p": p, "pb": p.get_stream_playback(), "last": 0.0, "pos": 0.0}
		_players[from] = e
		# jitter buffer: start with ~0.12 s of silence so network hiccups don't crackle
		var pre := PackedVector2Array()
		pre.resize(int(gen.mix_rate * 0.12))
		(e["pb"] as AudioStreamGeneratorPlayback).push_buffer(pre)
	(e["p"] as AudioStreamPlayer).volume_db = linear_to_db(maxf(float(GS.settings.get("vol_voice", 1.0)), 0.001))
	var pb: AudioStreamGeneratorPlayback = e["pb"]
	# decode + linear resample 11025 Hz -> mix rate, pushed as one buffer (was one call per sample)
	var ratio := AudioServer.get_mix_rate() / RATE
	var dec := PackedFloat32Array()
	for i in range(off, pkt.size()):
		dec.append(_mulaw_dec(pkt[i]))
	var out := PackedVector2Array()
	var nout := int(dec.size() * ratio)
	out.resize(nout)
	var last: float = e["last"]
	for j in nout:
		var sp := float(j) / ratio
		var i0 := int(sp)
		var fr := sp - i0
		var a := last if i0 == 0 else dec[i0 - 1]
		var b := dec[mini(i0, dec.size() - 1)]
		var v := lerpf(a, b, fr)
		out[j] = Vector2(v, v)
	e["last"] = dec[dec.size() - 1] if dec.size() > 0 else 0.0
	var room := pb.get_frames_available()
	if room < out.size():
		out = out.slice(0, room)     # too far behind: drop the overflow instead of growing the delay
	if out.size() > 0:
		pb.push_buffer(out)

func _drop_player(id: String) -> void:
	if _players.has(id):
		(_players[id]["p"] as Node).queue_free()
		_players.erase(id)

func clear() -> void:
	for k in _players.keys():
		(_players[k]["p"] as Node).queue_free()
	_players.clear()
	speaking.clear()
	set_talking(false)
