extends Node
## v4.18 in-game performance benchmark (real GPU numbers are only meaningful on the player's own PC).
## Runs a fixed, repeatable camera route through the map's spawn points while bots fight, after a warm-up.
## Writes one JSON per run + appends a row to benchmarks.csv in user://benchmarks/ and Documents/SOKAK_Benchmark/.
## VRAM: Godot only reports its OWN allocations (textures + buffers + other), not the whole GPU's usage: the JSON says so;
## for full-GPU numbers use Task Manager / nvidia-smi alongside (see docs/BENCHMARK.md).

var match_node: Node
var warmup := 6.0
var duration := 60.0
var t := 0.0
var frames: PackedFloat32Array = []
var last_us := 0
var route: Array = []
var leg := 0.0
var done := false
var vram_peak := 0
var next_cb: Callable

const LEG := 7.5          # seconds per route point (turn 270 degrees while there)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GS.settings["dyn_res"] = false         # no automatic resolution / effect drops while measuring
	match_node.set_meta("bench", true)
	last_us = Time.get_ticks_usec()

func _make_route() -> void:
	for sp in match_node.spawn_points:
		route.append(sp["pos"])
	# deterministic order: sorted by angle around the map centre, at most 8 stops
	var c := Vector3.ZERO
	for p in route: c += p
	if route.size() > 0: c /= route.size()
	route.sort_custom(func(a, b): return atan2(a.x - c.x, a.z - c.z) < atan2(b.x - c.x, b.z - c.z))
	while route.size() > 8: route.remove_at(route.size() - 1)

func _process(_d: float) -> void:
	if done:
		return
	var now := Time.get_ticks_usec()
	var dt := (now - last_us) / 1000000.0
	last_us = now
	var pl = match_node.player
	if route.is_empty() and not match_node.spawn_points.is_empty():
		_make_route()
	if OS.has_environment("BENCHDBG") and Engine.get_process_frames() % 60 == 0:
		print("BENCHDBG t=%.1f pl=%s loading=%s cd=%s route=%d frames=%d" % [t, pl != null, match_node.loading != null and is_instance_valid(match_node.loading), str(match_node.countdown), route.size(), frames.size()])
	if pl == null or not is_instance_valid(pl) or route.is_empty() or match_node.loading != null and is_instance_valid(match_node.loading) \
			or float(match_node.countdown) > 0.0:
		return
	t += dt
	# camera route: stand at a spawn, sweep the view, move on
	leg += dt
	var i := int(t / LEG) % route.size()
	if leg >= LEG or t < dt * 2:
		leg = 0.0 if leg >= LEG else leg
		pl.global_position = route[i] + Vector3(0, 0.1, 0)
		if "velocity" in pl: pl.velocity = Vector3.ZERO
	pl.yaw = (t / LEG) * TAU * 0.75
	pl.pitch = sin(t * 0.7) * 0.12
	pl.health = 100.0
	if t < warmup:
		return
	frames.append(dt)
	var vm := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	vram_peak = max(vram_peak, vm)
	if t >= warmup + duration:
		done = true
		_finish()

func _finish() -> void:
	var n := frames.size()
	if n < 10:
		return
	var sorted := frames.duplicate(); sorted.sort()
	var tot := 0.0
	for f in frames: tot += f
	var avg_ft := tot / n
	var worst := maxi(1, n / 100)
	var w1 := 0.0
	for k in worst: w1 += sorted[n - 1 - k]
	w1 /= worst
	var w01 := 0.0
	var worst01 := maxi(1, n / 1000)
	for k in worst01: w01 += sorted[n - 1 - k]
	w01 /= worst01
	var vp := get_viewport()
	var win := DisplayServer.window_get_size()
	var rs := float(vp.scaling_3d_scale)
	var st: Dictionary = GS.settings
	var r := {
		"game_version": Updater.VERSION, "build": Updater.BUILD,
		"date": Time.get_datetime_string_from_system(false, true),
		"gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(), "gpu_driver": str(OS.get_video_adapter_driver_info()),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		"ram_mb": int(OS.get_memory_info().get("physical", 0) / 1048576),
		"os": OS.get_name() + " " + OS.get_version(),
		"map": str(GS.room.get("map", "")), "profile": str(st.get("quality", "")),
		"window": "%dx%d" % [win.x, win.y], "render_scale": rs,
		"render_resolution": "%dx%d" % [int(win.x * rs), int(win.y * rs)],
		"upscaler": str(st.get("upscaler", "")), "vsync": bool(st.get("vsync", false)), "fps_cap": int(st.get("fps_cap", -1)),
		"settings": {"msaa": st.get("msaa"), "taa": st.get("taa"), "fxaa": st.get("fxaa"), "shadows": st.get("shadows"),
			"ssao": st.get("ssao"), "ssil": st.get("ssil"), "ssr": st.get("ssr"), "sdfgi": st.get("sdfgi"),
			"volumetric": st.get("volumetric"), "glow": st.get("glow"), "draw_distance": st.get("draw_distance")},
		"warmup_s": warmup, "duration_s": duration, "frames": n,
		"avg_fps": snappedf(1.0 / avg_ft, 0.1), "avg_frametime_ms": snappedf(avg_ft * 1000.0, 0.01),
		"low1_fps": snappedf(1.0 / w1, 0.1), "low01_fps": snappedf(1.0 / w01, 0.1),
		"median_frametime_ms": snappedf(sorted[n / 2] * 1000.0, 0.01),
		"p99_frametime_ms": snappedf(sorted[mini(n - 1, int(n * 0.99))] * 1000.0, 0.01),
		"max_frametime_ms": snappedf(sorted[n - 1] * 1000.0, 0.01),
		"godot_vram_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
		"godot_vram_peak_mb": int(vram_peak / 1048576),
		"godot_texture_mem_mb": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576),
		"godot_buffer_mem_mb": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576),
		"vram_note": "Godot'un kendi ayırdığı bellek (doku+tampon+diğer). Tüm GPU kullanımı değildir; sürücü/işletim sistemi/ekran tamponları dahil değil. Tam değer için Görev Yöneticisi > Performans > GPU > Ayrılmış GPU belleği veya nvidia-smi.",
		"draw_calls_avg_last": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects_last": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives_last": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var fname := "bench_%s_%s_%s.json" % [r["map"], r["profile"], stamp]
	var dirs := ["user://benchmarks"]
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs != "":
		dirs.append(docs.path_join("SOKAK_Benchmark"))
	var cols := ["date", "game_version", "gpu", "cpu", "map", "profile", "window", "render_resolution", "upscaler", "avg_fps", "low1_fps", "low01_fps", "avg_frametime_ms", "p99_frametime_ms", "max_frametime_ms", "godot_vram_peak_mb", "duration_s", "frames"]
	var saved := ""
	for d: String in dirs:
		DirAccess.make_dir_recursive_absolute(d)
		var f := FileAccess.open(str(d).path_join(fname), FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(JSON.stringify(r, "  "))
		f.close()
		var cp: String = d.path_join("benchmarks.csv")
		var newf := not FileAccess.file_exists(cp)
		var c := FileAccess.open(cp, FileAccess.READ_WRITE if not newf else FileAccess.WRITE)
		if c:
			c.seek_end()
			if newf:
				c.store_line(",".join(cols))
			var row: PackedStringArray = []
			for k in cols: row.append('"%s"' % str(r[k]).replace('"', "'"))
			c.store_line(",".join(row))
			c.close()
		if saved == "":
			saved = ProjectSettings.globalize_path(d.path_join(fname))
	print("BENCH ", JSON.stringify({"map": r["map"], "profile": r["profile"], "avg_fps": r["avg_fps"], "low1_fps": r["low1_fps"], "frametime": r["avg_frametime_ms"], "vram_peak_mb": r["godot_vram_peak_mb"], "file": saved}))
	r["file"] = saved
	match_node.set_meta("bench_result", r)
	if next_cb.is_valid():
		next_cb.call(r)
