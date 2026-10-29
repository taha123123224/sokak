extends Node
## Sound manager: 2D/3D one-shots with pooling, music & ambience.

const DIR := "res://assets/sfx/"
var streams := {}
var pool2d: Array[AudioStreamPlayer] = []
var pool3d: Array[AudioStreamPlayer3D] = []
var music: AudioStreamPlayer
var amb: AudioStreamPlayer
var world: Node = null
var silent := false   # parent for 3D players (current match)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool2d.append(p)
	music = AudioStreamPlayer.new(); music.bus = "Music"; add_child(music)
	amb = AudioStreamPlayer.new(); amb.bus = "Amb"; add_child(amb)

var variants := {}

func _pick(n: String) -> AudioStream:
	## random take among name, name_v1, name_v2 ... (real recordings have several takes)
	if not variants.has(n):
		var arr: Array = []
		var s0 := get_stream(n)
		if s0:
			arr.append(s0)
		for i in range(1, 6):
			var p := DIR + "%s_v%d.wav" % [n, i]
			if ResourceLoader.exists(p):
				arr.append(load(p))
		variants[n] = arr
	var a: Array = variants[n]
	return a[randi() % a.size()] if a.size() > 0 else null

func get_stream(n: String) -> AudioStream:
	if streams.has(n):
		return streams[n]
	var path := DIR + n + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	streams[n] = s
	return s

func play(n: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if silent:
		return
	var s := _pick(n)
	if s == null:
		return
	var best: AudioStreamPlayer = pool2d[0]
	for p in pool2d:
		if not p.playing:
			best = p
			break
	best.stream = s
	best.volume_db = vol_db
	best.pitch_scale = pitch
	best.play()

func play_var(base: String, count: int, vol_db: float = 0.0, pitch_var: float = 0.08) -> void:
	play("%s%d" % [base, randi() % count], vol_db, 1.0 + randf_range(-pitch_var, pitch_var))

func play3d(n: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0, max_dist: float = 120.0, unit_size: float = 10.0) -> void:
	if silent:
		return
	var s := _pick(n)
	if s == null or world == null or not is_instance_valid(world):
		return
	var best: AudioStreamPlayer3D = null
	for p in pool3d:
		if is_instance_valid(p) and not p.playing:
			best = p
			break
	if best == null:
		if pool3d.size() >= 48:
			best = pool3d[randi() % pool3d.size()]
		else:
			best = AudioStreamPlayer3D.new()
			best.bus = "SFX"
			best.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			best.attenuation_filter_cutoff_hz = 6000
			best.attenuation_filter_db = -12
			world.add_child(best)
			pool3d.append(best)
	best.global_position = pos
	best.stream = s
	best.volume_db = vol_db
	best.unit_size = unit_size
	best.max_distance = max_dist
	best.pitch_scale = pitch
	best.play()

func clear_world() -> void:
	pool3d.clear()
	world = null

func _frames(w: AudioStreamWAV) -> int:
	var bps := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
	return w.data.size() / (bps * (2 if w.stereo else 1))

func play_music(n: String, vol_db: float = -4.0, loop: bool = true) -> void:
	if _mfade and _mfade.is_valid():
		_mfade.kill()
	var s := get_stream(n)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		w.loop_end = _frames(w)
	if music.stream == s and music.playing:
		music.volume_db = vol_db
		return
	music.stream = s
	music.volume_db = vol_db - 30.0 if loop else vol_db
	music.play()
	if loop:  # the loop itself has no fade; fade in only when a track starts
		_mfade = create_tween()
		_mfade.tween_property(music, "volume_db", vol_db, 1.4).set_trans(Tween.TRANS_SINE)

var _mfade: Tween

func stop_music() -> void:
	if _mfade and _mfade.is_valid():
		_mfade.kill()
	var tw := create_tween()
	_mfade = tw
	tw.tween_property(music, "volume_db", -40.0, 1.0)
	tw.tween_callback(music.stop)

func play_amb(n: String) -> void:
	var s := get_stream(n)
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = _frames(s as AudioStreamWAV)
	amb.stream = s
	amb.volume_db = -6
	amb.play()

func stop_amb() -> void:
	amb.stop()
