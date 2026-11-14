extends Node
## In-game updater. Reads a small version.json from GitHub; when a newer build exists the login screen shows
## "GÜNCELLE". The new SOKAK.pck is downloaded next to the exe, then a tiny helper swaps it in after the
## game closes and starts the game again. Player data lives in AppData + the cloud, so nothing is lost.

signal update_available(info: Dictionary)
signal progress(frac: float, text: String)
signal failed(msg: String)

const VERSION := "4.8.0"
const BUILD := 63
var latest := {}
var _dl: HTTPRequest
var _total := 0

func has_update() -> bool:
	return int(latest.get("build", 0)) > BUILD

# ---------------------------------------------------------------- v4.4 live update notice
const CHECK_EVERY := 150.0
var _timer: Timer
var _banner: CanvasLayer
var _snooze_until := 0.0
var _notified_build := 0

func _ready() -> void:
	set_process(false)
	_timer = Timer.new()
	_timer.wait_time = CHECK_EVERY
	_timer.autostart = true
	_timer.timeout.connect(check)
	add_child(_timer)
	update_available.connect(_on_update_found)
	_cleanup_packs.call_deferred()

func _on_update_found(info: Dictionary) -> void:
	if int(info.get("build", 0)) == _notified_build and Time.get_ticks_msec() / 1000.0 < _snooze_until:
		return
	_notified_build = int(info.get("build", 0))
	_show_banner(info)

func _show_banner(info: Dictionary) -> void:
	if _banner and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = CanvasLayer.new()
	_banner.layer = 128
	add_child(_banner)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.96)
	sb.border_color = Color("ff8a1f"); sb.border_width_left = 4; sb.border_width_bottom = 2
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22; sb.content_margin_right = 18; sb.content_margin_top = 14; sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-330, -140)
	panel.custom_minimum_size = Vector2(660, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var t1 := UI.lbl("OYUNUMUZ GÜNCELLENDİ!  v%s" % str(info.get("version", "")), 22, Color("ffb45c"), "RussoOne-Regular")
	v.add_child(t1)
	var in_match := get_tree().current_scene != null and get_tree().current_scene.has_method("ensure_comms")
	var t2 := UI.lbl("Güncel sürümü indirip oyuna öyle devam edin. Sadece değişen dosyalar inecek." + ("\nMaçın bitince menüden güncelleyebilirsin." if in_match else ""), 15, Color(1, 1, 1, 0.8), "Rajdhani-SemiBold")
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t2)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	h.add_child(bv)
	var b1 := UI.btn("ŞİMDİ GÜNCELLE", func():
		_banner_progress(panel, t2)
		download_and_install(), 16, true, 180, 40)
	bv.add_child(b1)
	var b2 := UI.btn("SONRA", func():
		_snooze_until = Time.get_ticks_msec() / 1000.0 + 600.0
		_hide_banner(), 14, false, 180, 30)
	bv.add_child(b2)
	var tw := panel.create_tween()
	tw.tween_property(panel, "position:y", 74.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	SFX.play("success", -4)

func _banner_progress(panel: Control, lbl: Label) -> void:
	for b in panel.find_children("*", "Button", true, false):
		(b as Button).disabled = true
	progress.connect(func(f: float, txt: String): if is_instance_valid(lbl): lbl.text = "%s  (%d%%)" % [txt, int(f * 100)])
	failed.connect(func(msg: String):
		if is_instance_valid(lbl): lbl.text = msg
		for b in panel.find_children("*", "Button", true, false):
			if is_instance_valid(b): (b as Button).disabled = false)

func _hide_banner() -> void:
	if _banner and is_instance_valid(_banner):
		var bp := _banner.get_child(0) as Control
		var tw := bp.create_tween()
		tw.tween_property(bp, "position:y", -160.0, 0.3)
		tw.tween_callback(_banner.queue_free)

## shards that are no longer listed in veri/yuklu.json are left-overs from an older build
func _cleanup_packs() -> void:
	if OS.get_name() != "Windows" or Packs.state.is_empty():
		return
	var vd := Packs.dir.path_join("veri")
	var keep: Array = Packs.state.get("packs", [])
	var da := DirAccess.open(vd)
	if da == null:
		return
	for fn in da.get_files():
		if fn.ends_with(".pck") and not keep.has("veri/" + fn):
			DirAccess.remove_absolute(vd.path_join(fn))

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
		_update_launcher()

## the launcher (SOKAK.exe --main-pack baslatici.pck) cannot update itself on older installs, so the game
## refreshes baslatici.pck in the background whenever the manifest lists a different one
func _update_launcher() -> void:
	var li = latest.get("launcher", {})
	if not (li is Dictionary) or not li.has("url") or OS.get_name() != "Windows":
		return
	var dir := OS.get_executable_path().get_base_dir()
	var path := dir.path_join("baslatici.pck")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var have := f.get_length() if f else -1
	f = null
	if have == int(li.get("size", 0)):
		return
	var h := HTTPRequest.new()
	h.timeout = 60.0
	h.download_file = path + ".new"
	add_child(h)
	if h.request(str(li["url"])) != OK:
		h.queue_free(); return
	var r: Array = await h.request_completed
	h.queue_free()
	var nf := FileAccess.open(path + ".new", FileAccess.READ)
	var got := nf.get_length() if nf else -1
	nf = null
	if int(r[1]) == 200 and got == int(li.get("size", 0)):
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(path + ".new", path)
		print("launcher updated")
	else:
		DirAccess.remove_absolute(path + ".new")

func download_and_install() -> void:
	if not has_update():
		return
	if OS.get_name() != "Windows":
		failed.emit("Otomatik güncelleme yalnızca Windows sürümünde çalışır.")
		return
	var dir := OS.get_executable_path().get_base_dir()
	if latest.has("packs"):
		await _install_packs(dir)
		return
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
var _busy := false

## v4.4 delta update: only the packs whose content changed are downloaded (main pack + changed shards)
func _install_packs(dir: String) -> void:
	if _busy:
		return
	_busy = true
	var packs: Array = latest["packs"]
	var need: Array = []
	_total = 0
	for p in packs:
		var f := str(p["f"])
		var local := dir.path_join(f)
		var ok := false
		if f == "SOKAK.pck":
			ok = FileAccess.file_exists(local) and FileAccess.get_md5(local) == str(p["md5"])
		else:
			ok = _file_size(local) == int(p["size"])
		if not ok:
			need.append(p)
			_total += int(p["size"])
	DirAccess.make_dir_recursive_absolute(dir.path_join("veri"))
	_done_bytes = 0
	for i in need.size():
		var p: Dictionary = need[i]
		var f := str(p["f"])
		var dest := dir.path_join("SOKAK.pck.new" if f == "SOKAK.pck" else f)
		var part_file := dest + ".indir"
		var ok := false
		for attempt in 3:
			_dl = HTTPRequest.new()
			_dl.download_file = part_file
			_dl.use_threads = true
			_dl.max_redirects = 10
			_dl.download_chunk_size = 1 << 20
			add_child(_dl)
			if _dl.request(str(p["url"])) == OK:
				set_process(true)
				var r: Array = await _dl.request_completed
				set_process(false)
				ok = int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200 and _file_size(part_file) == int(p["size"]) and FileAccess.get_md5(part_file) == str(p["md5"])
			_dl.queue_free(); _dl = null
			if ok:
				break
		if not ok:
			DirAccess.remove_absolute(part_file)
			_busy = false
			failed.emit("İndirme başarısız (%d/%d). İnternetini kontrol edip tekrar dene." % [i + 1, need.size()])
			return
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		DirAccess.rename_absolute(part_file, dest)
		_done_bytes += int(p["size"])
	# the new shard list becomes active together with the new main pack (swapped by the helper after exit)
	var names: Array = []
	for p in packs:
		names.append(str(p["f"]))
	var jf := FileAccess.open(dir.path_join("veri/yuklu.json.new"), FileAccess.WRITE)
	jf.store_string(JSON.stringify({"build": int(latest.get("build", 0)), "version": str(latest.get("version", "")), "packs": names}))
	jf.close()
	progress.emit(1.0, "Kuruluyor... oyun birazdan yeniden açılacak.")
	GS.save_profile(true)
	if Online.is_logged_in():
		await Online.save_now()
	var bat := dir.path_join("sokak_guncelle.bat")
	var bf := FileAccess.open(bat, FileAccess.WRITE)
	var exe := OS.get_executable_path().get_file()
	bf.store_string("@echo off\r\ncd /d \"%~dp0\"\r\nset n=0\r\n:wait\r\ntimeout /t 1 /nobreak >nul\r\nset /a n+=1\r\nif exist \"SOKAK.pck.new\" (\r\n  move /y \"SOKAK.pck.new\" \"SOKAK.pck\" >nul 2>&1\r\n  if errorlevel 1 if %n% lss 30 goto wait\r\n)\r\nmove /y \"veri\\yuklu.json.new\" \"veri\\yuklu.json\" >nul 2>&1\r\nstart \"\" \"" + exe + "\"\r\ndel \"%~f0\"\r\n")
	bf.close()
	OS.create_process("cmd.exe", PackedStringArray(["/c", bat]))
	get_tree().quit()

func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else 0

func _process(_d: float) -> void:
	if _dl and is_instance_valid(_dl):
		var got := _done_bytes + _dl.get_downloaded_bytes()
		var tot: int = _total if _total > 0 else max(_dl.get_body_size(), 1)
		progress.emit(clamp(float(got) / tot, 0.0, 1.0), "İndiriliyor... %.1f / %.1f MB" % [got / 1048576.0, tot / 1048576.0])
