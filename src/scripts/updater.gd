extends Node
## In-game updater. Reads a small version.json from GitHub; when a newer build exists the login screen shows
## "GÜNCELLE". The new SOKAK.pck is downloaded next to the exe, then a tiny helper swaps it in after the
## game closes and starts the game again. Player data lives in AppData + the cloud, so nothing is lost.

signal update_available(info: Dictionary)
signal progress(frac: float, text: String)
signal failed(msg: String)

const VERSION := "2.2.0"
const BUILD := 22
var latest := {}
var _dl: HTTPRequest
var _total := 0

func has_update() -> bool:
	return int(latest.get("build", 0)) > BUILD

func check() -> void:
	var url: String = Online.update_manifest
	if url == "":
		return
	var h := HTTPRequest.new()
	h.timeout = 10.0
	add_child(h)
	# cache-buster so GitHub's CDN never serves an old manifest
	if h.request(url + ("&" if "?" in url else "?") + "t=%d" % Time.get_unix_time_from_system()) != OK:
		h.queue_free(); return
	var r: Array = await h.request_completed
	h.queue_free()
	if int(r[1]) != 200:
		return
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if d is Dictionary:
		latest = d
		if has_update():
			update_available.emit(latest)

func download_and_install() -> void:
	if not has_update():
		return
	if OS.get_name() != "Windows":
		failed.emit("Otomatik güncelleme yalnızca Windows sürümünde çalışır.")
		return
	var dir := OS.get_executable_path().get_base_dir()
	var tmp := dir.path_join("SOKAK.pck.new")
	# the pack is published in parts (GitHub serves files up to ~100 MB); download and join them
	var parts: Array = latest.get("parts", [])
	if parts.is_empty() and latest.has("pck_url"):
		parts = [{"url": latest["pck_url"], "size": int(latest.get("pck_size", 0))}]
	_total = 0
	for pt in parts:
		_total += int(pt.get("size", 0))
	var out := FileAccess.open(tmp, FileAccess.WRITE)
	if out == null:
		failed.emit("Oyun klasörüne yazılamıyor. Oyunu yönetici olarak ya da başka bir klasörde çalıştır.")
		return
	_done_bytes = 0
	for i in parts.size():
		var pt: Dictionary = parts[i]
		var part_file := dir.path_join("SOKAK.pck.part")
		_dl = HTTPRequest.new()
		_dl.download_file = part_file
		_dl.use_threads = true
		_dl.max_redirects = 10
		_dl.download_chunk_size = 1 << 20
		add_child(_dl)
		var ok := false
		for attempt in 3:
			if _dl.request(str(pt["url"]) + "?t=%d" % Time.get_unix_time_from_system()) != OK:
				continue
			set_process(true)
			var r: Array = await _dl.request_completed
			set_process(false)
			if int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200 and (int(pt.get("size", 0)) <= 0 or _file_size(part_file) == int(pt["size"])):
				ok = true
				break
		_dl.queue_free(); _dl = null
		if not ok:
			out.close()
			DirAccess.remove_absolute(tmp); DirAccess.remove_absolute(part_file)
			failed.emit("İndirme başarısız (parça %d/%d). İnternetini kontrol edip tekrar dene." % [i + 1, parts.size()])
			return
		out.store_buffer(FileAccess.get_file_as_bytes(part_file))
		_done_bytes += int(pt.get("size", _file_size(part_file)))
		DirAccess.remove_absolute(part_file)
	out.close()
	progress.emit(1.0, "Kuruluyor... oyun birazdan yeniden açılacak.")
	# save everything before closing
	GS.save_profile(true)
	if Online.is_logged_in():
		await Online.save_now()
	var bat := dir.path_join("sokak_guncelle.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	var exe := OS.get_executable_path().get_file()
	f.store_string("@echo off\r\ncd /d \"%~dp0\"\r\nset n=0\r\n:wait\r\ntimeout /t 1 /nobreak >nul\r\nset /a n+=1\r\nmove /y \"SOKAK.pck.new\" \"SOKAK.pck\" >nul 2>&1\r\nif errorlevel 1 if %n% lss 30 goto wait\r\nstart \"\" \"" + exe + "\"\r\ndel \"%~f0\"\r\n")
	f.close()
	OS.create_process("cmd.exe", PackedStringArray(["/c", bat]))
	get_tree().quit()

var _done_bytes := 0

func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else 0

func _process(_d: float) -> void:
	if _dl and is_instance_valid(_dl):
		var got := _done_bytes + _dl.get_downloaded_bytes()
		var tot: int = _total if _total > 0 else max(_dl.get_body_size(), 1)
		progress.emit(clamp(float(got) / tot, 0.0, 1.0), "İndiriliyor... %.1f / %.1f MB" % [got / 1048576.0, tot / 1048576.0])
