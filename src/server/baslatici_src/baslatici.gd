extends Control
## SOKAK: Operasyon - Başlatıcı
## SOKAK.exe --main-pack baslatici.pck ile açılır. Oyun dosyalarını (SOKAK.pck) GitHub'dan
## parça parça indirir (yarıda kalırsa kaldığı yerden devam eder), sonra BAŞLAT ile oyunu açar.

const MANIFEST := "https://raw.githubusercontent.com/taha123123224/sokak/main/version.json"
const W := 1120.0
const H := 630.0

const OR := Color("ff8a1f")
const OR2 := Color("ffb45c")
const ORD := Color("c75a0c")
const TX := Color("e9ecef")
const MUT := Color("9aa3ad")
const DIM := Color("6b747e")
const GREEN := Color("4ade80")
const RED := Color("ff5a46")

enum St { CHECKING, DOWNLOADING, MERGING, READY, ERROR }

const TIPS := [
	"Kafadan vuruşlar gövdeye göre 2,5 kat daha fazla hasar verir.",
	"SCAR-H ve AK-47 ince duvarların arkasındaki rakibi delip vurabilir.",
	"Susturucu takılı silahla ateş edince haritada görünmezsin.",
	"Eklenti Paketi kasasından susturucu, nişangah ve lazer çıkabilir.",
	"Arkadaşlarını ARKADAŞLAR sekmesinden ekleyip odana davet edebilirsin.",
	"Hesabın bulutta saklanır; güncelleme sonrası her şey yerinde kalır.",
	"UMP-45 ile vurduğun rakip kısa süre yavaşlar.",
	"Çömelerek ateş etmek sekmeyi azaltır.",
]

var dir := ""
var bg: Texture2D
var f_title: Font
var f_body: Font
var f_lbl: FontVariation
var f_btn: FontVariation

# iş parçacığıyla paylaşılan durum
var state: int = St.CHECKING
var title := "SÜRÜM KONTROL EDİLİYOR"
var sub := "Sunucuya bağlanılıyor…"
var version := ""
var notes: PackedStringArray = []
var logo: Texture2D
var live: ColorRect
var embers: Array = []
var total: int = 1
var done: int = 0
var part_idx := 0
var part_count := 0
var quitting := false
var updating := false

var thread: Thread
var t := 0.0
var shown := 0.0
var speed := 0.0
var samples: Array = []
var tip := 0
var tip_t := 0.0
var hover := ""

var r_btn := Rect2(W - 44 - 260, H - 38 - 64, 260, 64)
var r_close := Rect2(W - 44, 8, 36, 30)
var r_min := Rect2(W - 82, 8, 36, 30)

var proxy_host := ""
var proxy_port := 0
var tls: TLSOptions


func _ready() -> void:
	dir = OS.get_executable_path().get_base_dir()
	if OS.has_environment("SOKAK_DIR"):
		dir = OS.get_environment("SOKAK_DIR")
	get_window().title = "SOKAK: Operasyon"
	# yüksek DPI ekranlarda pencereyi büyüt (içerik canvas_items ile ölçeklenir)
	var scr := DisplayServer.window_get_current_screen()
	var sc: float = clampf(DisplayServer.screen_get_dpi(scr) / 96.0, 1.0, 3.0)
	var usable := DisplayServer.screen_get_usable_rect(scr)
	sc = minf(sc, minf(usable.size.x * 0.9 / W, usable.size.y * 0.9 / H))
	sc = maxf(sc, 1.0)
	var sz := Vector2i(int(W * sc), int(H * sc))
	get_window().size = sz
	get_window().position = usable.position + (usable.size - sz) / 2

	bg = load("res://bg.jpg")
	logo = load("res://logo.png")
	# living background layer: drawn behind this control
	live = ColorRect.new()
	live.set_anchors_preset(Control.PRESET_FULL_RECT)
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.show_behind_parent = true
	var sm := ShaderMaterial.new()
	sm.shader = load("res://bg_live.gdshader")
	sm.set_shader_parameter("art", bg)
	live.material = sm
	add_child(live)
	for i in 46:
		embers.append([randf(), randf(), randf_range(0.01, 0.05), randf_range(0.6, 2.4), randf() * TAU])
	f_title = load("res://fonts/BarlowCondensed-ExtraBoldItalic.ttf")
	f_body = load("res://fonts/Barlow-Medium.ttf")
	f_lbl = FontVariation.new()
	f_lbl.base_font = load("res://fonts/BarlowCondensed-Bold.ttf")
	f_lbl.spacing_glyph = 3
	f_btn = FontVariation.new()
	f_btn.base_font = f_title
	f_btn.spacing_glyph = 2
	tip = randi() % TIPS.size()

	tls = TLSOptions.client()
	if OS.has_environment("SOKAK_PROXY"):   # yalnızca test ortamı
		var p := OS.get_environment("SOKAK_PROXY").trim_prefix("http://").split(":")
		proxy_host = p[0]
		proxy_port = int(p[1])
		if OS.has_environment("SOKAK_CA"):
			var ca := X509Certificate.new()
			if ca.load(OS.get_environment("SOKAK_CA")) == OK:
				tls = TLSOptions.client(ca)

	mouse_filter = Control.MOUSE_FILTER_STOP
	_start_work()


func _start_work() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
	thread = Thread.new()
	thread.start(_work)


func _exit_tree() -> void:
	quitting = true
	if thread and thread.is_started():
		thread.wait_to_finish()


# ------------------------------------------------------------------ iş
func _st(s: int, ti: String, sb: String) -> void:
	state = s
	title = ti
	sub = sb


func _fail(msg: String) -> void:
	_st(St.ERROR, "İNDİRME BAŞARISIZ", msg)


func _pck_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	return f.get_length()


func _work() -> void:
	var pck := dir.path_join("SOKAK.pck")
	var js := ""
	for i in 3:
		var mu := OS.get_environment("SOKAK_MANIFEST") if OS.has_environment("SOKAK_MANIFEST") else MANIFEST
		var r: Dictionary = _fetch(mu + "?t=" + str(Time.get_unix_time_from_system()), "", 0)
		if r.ok:
			js = (r.body as PackedByteArray).get_string_from_utf8()
			break
		if quitting:
			return
		OS.delay_msec(1200)
	var m = JSON.parse_string(js) if js != "" else null
	if not (m is Dictionary) or not (m.has("parts") or m.has("packs")):
		if _pck_size(pck) > 1000000:
			_st(St.READY, "OYUN HAZIR", "Sunucuya ulaşılamadı; mevcut sürümle oynayabilirsin.")
		else:
			_fail("Sürüm bilgisi alınamadı. İnternet bağlantını kontrol edip TEKRAR DENE'ye bas.")
		return
	version = str(m.get("version", ""))
	var nt := str(m.get("notes", ""))
	if ":" in nt.substr(0, 14):
		nt = nt.substr(nt.find(":") + 1)
	var lst := PackedStringArray()
	for part in nt.split("•"):
		if part.strip_edges() != "":
			lst.append(part.strip_edges())
	notes = lst.slice(0, 5)
	var build := str(int(m.get("build", 0)))
	if m.has("packs"):
		_work_packs(m, build)
		return
	var parts: Array = m["parts"]
	var want: int = int(m.get("pck_size", 0))
	if want == 0:
		for p in parts:
			want += int(p["size"])

	var have_pck := _pck_size(pck)
	if have_pck == want:
		_st(St.READY, "OYUN HAZIR", "Oyun güncel. İyi oyunlar!")
		return
	updating = have_pck > 0
	_st(St.DOWNLOADING, "GÜNCELLEME İNDİRİLİYOR" if updating else "OYUN DOSYALARI İNDİRİLİYOR",
		"Lütfen bekleyin. Pencereyi kapatırsan indirme bir dahaki açılışta kaldığı yerden devam eder.")

	var tmp := dir.path_join("indirilenler")
	DirAccess.make_dir_recursive_absolute(tmp)
	var da := DirAccess.open(tmp)
	if da == null:
		_fail("Oyun klasörüne yazılamadı.")
		return
	for fn in da.get_files():
		if not fn.begins_with("b" + build + "_"):
			DirAccess.remove_absolute(tmp.path_join(fn))

	total = want
	part_count = parts.size()
	var files: Array[String] = []
	var before := 0
	for i in parts.size():
		var fp := tmp.path_join("b%s_parca%d" % [build, i])
		files.append(fp)
		before += mini(maxi(_pck_size(fp), 0), int(parts[i]["size"]))
	done = before

	for i in parts.size():
		part_idx = i + 1
		if not _download_part(str(parts[i]["url"]), int(parts[i]["size"]), files[i]):
			if not quitting:
				_fail("İndirme tamamlanamadı (parça %d). Bağlantını kontrol edip TEKRAR DENE'ye bas." % (i + 1))
			return

	_st(St.MERGING, "DOSYALAR HAZIRLANIYOR", "İndirilen parçalar birleştiriliyor, az kaldı…")
	done = 0
	var outp := pck + ".new"
	var o := FileAccess.open(outp, FileAccess.WRITE)
	if o == null:
		_fail("Oyun dosyası yazılamadı (disk dolu ya da izin yok).")
		return
	for fp in files:
		var s := FileAccess.open(fp, FileAccess.READ)
		if s == null:
			o.close()
			_fail("Parça okunamadı. TEKRAR DENE'ye bas.")
			return
		while s.get_position() < s.get_length():
			var chunk := s.get_buffer(1 << 20)
			o.store_buffer(chunk)
			done += chunk.size()
			if quitting:
				o.close()
				return
		s.close()
	o.close()
	if _pck_size(outp) != want:
		DirAccess.remove_absolute(outp)
		_fail("Dosya boyutu tutmadı. TEKRAR DENE'ye bas.")
		return
	var moved := false
	for k in 10:
		if FileAccess.file_exists(pck):
			DirAccess.remove_absolute(pck)
		if DirAccess.rename_absolute(outp, pck) == OK:
			moved = true
			break
		OS.delay_msec(500)
	if not moved:
		_fail("Oyun dosyası değiştirilemedi. Oyun açıksa kapatıp TEKRAR DENE'ye bas.")
		return
	for fp in files:
		DirAccess.remove_absolute(fp)
	DirAccess.remove_absolute(tmp)
	var sv := FileAccess.open(dir.path_join("surum.txt"), FileAccess.WRITE)
	if sv:
		sv.store_string("%s (%s)" % [version, build])
		sv.close()
	_st(St.READY, "OYUN HAZIR", "Güncelleme tamamlandı. İyi oyunlar!" if updating else "İndirme tamamlandı. İyi oyunlar!")


## v2.5 delta: the game is a small SOKAK.pck + content-addressed shards in veri/. Only packs that are
## missing or changed are downloaded (each one resumable and MD5-checked), then veri/yuklu.json is written.
func _work_packs(m: Dictionary, build: String) -> void:
	var packs: Array = m["packs"]
	var vd := dir.path_join("veri")
	DirAccess.make_dir_recursive_absolute(vd)
	_st(St.CHECKING, "DOSYALAR KONTROL EDİLİYOR", "Hangi dosyaların değiştiği kontrol ediliyor…")
	var need: Array = []
	var want := 0
	for p in packs:
		var f := str(p["f"])
		var local := dir.path_join(f)
		var ok := false
		if f == "SOKAK.pck":
			ok = _pck_size(local) == int(p["size"]) and FileAccess.get_md5(local) == str(p["md5"])
		else:
			ok = _pck_size(local) == int(p["size"])
		if not ok:
			need.append(p)
			want += int(p["size"])
		if quitting:
			return
	var names: Array = []
	for p in packs:
		names.append(str(p["f"]))
	var cur = JSON.parse_string(FileAccess.get_file_as_string(vd.path_join("yuklu.json"))) if FileAccess.file_exists(vd.path_join("yuklu.json")) else null
	var listed: bool = cur is Dictionary and int(cur.get("build", 0)) == int(build) and cur.get("packs", []) == names
	if need.is_empty() and listed:
		_st(St.READY, "OYUN HAZIR", "Oyun güncel. İyi oyunlar!")
		return
	updating = _pck_size(dir.path_join("SOKAK.pck")) > 0
	if not need.is_empty():
		_st(St.DOWNLOADING, "GÜNCELLEME İNDİRİLİYOR" if updating else "OYUN DOSYALARI İNDİRİLİYOR",
			("Sadece değişen dosyalar iniyor: %.0f MB. " % (want / 1048576.0)) + "Pencereyi kapatırsan kaldığı yerden devam eder.")
	total = maxi(want, 1)
	part_count = need.size()
	done = 0
	for p in need:
		done += mini(maxi(_pck_size(dir.path_join(str(p["f"])) + ".indir"), 0), int(p["size"]))
	for i in need.size():
		part_idx = i + 1
		var p: Dictionary = need[i]
		var f := str(p["f"])
		var final := dir.path_join(f)
		var tmpf := final + ".indir"
		var good := false
		for attempt in 2:
			if not _download_part(str(p["url"]), int(p["size"]), tmpf):
				break
			if FileAccess.get_md5(tmpf) == str(p["md5"]):
				good = true
				break
			done -= _pck_size(tmpf)
			DirAccess.remove_absolute(tmpf)
		if not good:
			if not quitting:
				_fail("İndirme tamamlanamadı (dosya %d/%d). Bağlantını kontrol edip TEKRAR DENE'ye bas." % [i + 1, need.size()])
			return
		var moved := false
		for k in 10:
			if FileAccess.file_exists(final):
				DirAccess.remove_absolute(final)
			if DirAccess.rename_absolute(tmpf, final) == OK:
				moved = true
				break
			OS.delay_msec(500)
		if not moved:
			_fail("Oyun dosyası değiştirilemedi. Oyun açıksa kapatıp TEKRAR DENE'ye bas.")
			return
	var jf := FileAccess.open(vd.path_join("yuklu.json"), FileAccess.WRITE)
	if jf == null:
		_fail("Oyun klasörüne yazılamadı.")
		return
	jf.store_string(JSON.stringify({"build": int(build), "version": version, "packs": names}))
	jf.close()
	# remove left-overs: old shards, the old single-file download folder
	var da := DirAccess.open(vd)
	if da:
		for fn in da.get_files():
			if (fn.ends_with(".pck") and not names.has("veri/" + fn)) or fn.ends_with(".indir"):
				DirAccess.remove_absolute(vd.path_join(fn))
	var old := dir.path_join("indirilenler")
	if DirAccess.dir_exists_absolute(old):
		var od := DirAccess.open(old)
		for fn in od.get_files():
			DirAccess.remove_absolute(old.path_join(fn))
		DirAccess.remove_absolute(old)
	var sv := FileAccess.open(dir.path_join("surum.txt"), FileAccess.WRITE)
	if sv:
		sv.store_string("%s (%s)" % [version, build])
		sv.close()
	_st(St.READY, "OYUN HAZIR", "Güncelleme tamamlandı. İyi oyunlar!" if updating else "İndirme tamamlandı. İyi oyunlar!")


func _download_part(url: String, size: int, fp: String) -> bool:
	for attempt in 8:
		if quitting:
			return false
		var have := maxi(_pck_size(fp), 0)
		if have == size:
			return true
		if have > size:
			DirAccess.remove_absolute(fp)
			done -= have
			have = 0
		var r: Dictionary = _fetch(url, fp, have)
		if r.ok and _pck_size(fp) == size:
			return true
		if not quitting:
			OS.delay_msec(mini(8000, 1000 * (attempt + 1)))
	return false


## GET isteği. out_path boşsa gövde belleğe alınır; doluysa dosyaya yazılır (offset > 0 ise devam).
func _fetch(url: String, out_path: String, offset: int) -> Dictionary:
	var res := {"ok": false, "body": PackedByteArray()}
	var u := url.trim_prefix("https://")
	var slash := u.find("/")
	var host := u.substr(0, slash)
	var path := u.substr(slash)
	var c := HTTPClient.new()
	c.read_chunk_size = 262144
	if proxy_host != "":
		c.set_https_proxy(proxy_host, proxy_port)
	if c.connect_to_host(host, 443, tls) != OK:
		return res
	var t0 := Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_CONNECTING or c.get_status() == HTTPClient.STATUS_RESOLVING:
		c.poll()
		OS.delay_msec(10)
		if quitting or Time.get_ticks_msec() - t0 > 20000:
			return res
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return res
	var hdr := PackedStringArray(["User-Agent: SOKAK-Baslatici/2.5", "Accept-Encoding: identity"])
	if offset > 0:
		hdr.append("Range: bytes=%d-" % offset)
	if c.request(HTTPClient.METHOD_GET, path, hdr) != OK:
		return res
	t0 = Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		OS.delay_msec(10)
		if quitting or Time.get_ticks_msec() - t0 > 20000:
			return res
	if not c.has_response():
		return res
	var code := c.get_response_code()
	if code != 200 and code != 206:
		return res
	var f: FileAccess = null
	if out_path != "":
		if offset > 0 and code == 206:
			f = FileAccess.open(out_path, FileAccess.READ_WRITE)
			if f:
				f.seek_end()
		else:
			if offset > 0:
				done -= offset   # sunucu baştan gönderiyor
			f = FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			return res
	var last := Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.size() == 0:
			if Time.get_ticks_msec() - last > 30000:
				break
			OS.delay_usec(1000)
		else:
			last = Time.get_ticks_msec()
			if f:
				f.store_buffer(chunk)
				done += chunk.size()
			else:
				res.body.append_array(chunk)
		if quitting:
			break
	if f:
		f.close()
	res.ok = not quitting and c.get_status() != HTTPClient.STATUS_BODY and (c.get_status() == HTTPClient.STATUS_CONNECTED or c.get_status() == HTTPClient.STATUS_DISCONNECTED)
	c.close()
	return res


func _retry() -> void:
	if state != St.ERROR:
		return
	_st(St.CHECKING, "SÜRÜM KONTROL EDİLİYOR", "Sunucuya bağlanılıyor…")
	_start_work()


func _play() -> void:
	if OS.has_environment("SOKAK_NOLAUNCH"):
		print("LAUNCH ", dir.path_join("SOKAK.exe"))
		get_tree().quit()
		return
	var exe := OS.get_executable_path()
	var pid := OS.create_process(exe, PackedStringArray(), false)
	if pid <= 0:
		_fail("Oyun başlatılamadı. Klasördeki SOKAK.exe'yi doğrudan açmayı dene.")
		return
	get_tree().quit()


# ------------------------------------------------------------------ animasyon
func _process(delta: float) -> void:
	t += delta
	var now := t
	samples.append([now, done])
	while samples.size() > 2 and now - samples[0][0] > 4.0:
		samples.pop_front()
	var dt: float = now - samples[0][0]
	if dt > 0.5:
		speed = speed * 0.85 + 0.15 * maxf(0.0, float(done - int(samples[0][1])) / dt)
	var target: float = 1.0 if state == St.READY else clampf(float(done) / maxf(1.0, float(total)), 0.0, 1.0)
	if target < shown - 0.05:
		shown = target
	else:
		shown += (target - shown) * minf(1.0, delta * 5.0)
	if live:
		(live.material as ShaderMaterial).set_shader_parameter("t", t)
	tip_t += delta
	if tip_t > 6.0:
		tip_t = 0.0
		tip = (tip + 1) % TIPS.size()
	queue_redraw()


# ------------------------------------------------------------------ çizim
func _skew(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y)])


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, width := -1.0) -> void:
	if width > 0:
		draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, col)
	else:
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	var sx := size.x / W
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, size.y / H))
	var intro := clampf(t / 0.9, 0.0, 1.0)
	intro = 1.0 - pow(1.0 - intro, 3.0)
	# the key art itself is drawn by the live shader layer behind this control (smoke, lanterns, sun)
	if live == null:
		draw_rect(Rect2(0, 0, W, H), Color("0c0e11"))
	# left shade for the text, bottom shade for the bar, thin top fade
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W * 0.62, 0), Vector2(W * 0.62, H), Vector2(0, H)]),
		PackedColorArray([Color(0.02, 0.022, 0.028, 0.94), Color(0.02, 0.022, 0.028, 0.0), Color(0.02, 0.022, 0.028, 0.0), Color(0.02, 0.022, 0.028, 0.94)]))
	draw_polygon(PackedVector2Array([Vector2(0, H - 200), Vector2(W, H - 200), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([Color(0.015, 0.016, 0.02, 0.0), Color(0.015, 0.016, 0.02, 0.0), Color(0.015, 0.016, 0.02, 0.96), Color(0.015, 0.016, 0.02, 0.96)]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, 70), Vector2(0, 70)]),
		PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	# embers
	for e in embers:
		var ex: float = fmod(e[0] + t * 0.01 * e[3], 1.0) * W
		var ey: float = fmod(e[1] - t * e[2] + 1.0, 1.0) * H
		draw_circle(Vector2(ex, ey), 1.0 + e[2] * 30.0, Color(1.0, 0.6, 0.25, (0.25 + 0.25 * sin(t * e[3] + e[4])) * intro))
	_win_btn(r_min, "min")
	_win_btn(r_close, "close")
	var a := intro
	var dx := (1.0 - intro) * -30.0
	# logo
	if logo:
		var lw := 250.0
		draw_texture_rect(logo, Rect2(40 + dx, 30, lw, lw * logo.get_height() / logo.get_width()), false, Color(1, 1, 1, a))
	# state tag
	var tag := "HAZIR" if state == St.READY else ("HATA" if state == St.ERROR else ("HAZIRLANIYOR" if state == St.MERGING else ("İNDİRİLİYOR" if state == St.DOWNLOADING else "BAĞLANIYOR")))
	var tag_c := GREEN if state == St.READY else (RED if state == St.ERROR else OR)
	var ty := 168.0
	if version != "":
		var vs := "YENİ GÜNCELLEME  •  v" + version
		var vw := f_lbl.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_rect(Rect2(44 + dx, ty, vw + 22, 26), Color(1, 0.54, 0.12, 0.16 * a))
		draw_rect(Rect2(44 + dx, ty, 3, 26), Color(OR, a))
		_txt(f_lbl, Vector2(56 + dx, ty + 18), vs, 14, Color(OR2, a))
	_txt(f_title, Vector2(42 + dx, ty + 78), title, 46, Color(TX, a))
	_txt(f_body, Vector2(44 + dx, ty + 108), sub, 15, Color(MUT, a), 470.0)
	# patch notes from the manifest
	var ny := ty + 160.0
	if notes.size() > 0:
		_txt(f_lbl, Vector2(44 + dx, ny), "YENİLİKLER", 14, Color(DIM, a))
		ny += 14
		for i in notes.size():
			var ia := clampf((t - 0.5 - i * 0.12) / 0.4, 0.0, 1.0)
			draw_rect(Rect2(46 + dx, ny + 12 + i * 30, 7, 7), Color(OR, ia))
			_txt(f_body, Vector2(64 + dx, ny + 21 + i * 30), notes[i], 15, Color(TX, 0.9 * ia), 520.0)
	# bottom: status + progress
	var bx := 44.0
	var by := H - 66.0
	var bw2 := W - 44.0 - 330.0
	var pulse := 1.0 if state == St.READY or state == St.ERROR else 0.55 + 0.45 * sin(t * 4.0)
	draw_circle(Vector2(bx + 5, by - 34), 4.0, Color(tag_c, pulse))
	_txt(f_lbl, Vector2(bx + 16, by - 29), tag, 14, tag_c)
	if state == St.CHECKING:
		_bar_indeterminate(bx, by, bw2, 6)
	else:
		_bar(bx, by, bw2, 6, shown, state == St.ERROR)
	if state == St.DOWNLOADING or state == St.MERGING:
		var pc := str(int(floor(shown * 100.0))) + "%"
		var pw := f_title.get_string_size(pc, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_txt(f_title, Vector2(bx + bw2 - pw, by - 14), pc, 34, OR2)
	var info := ""
	if state == St.DOWNLOADING:
		info = "%d / %d MB" % [int(done / 1048576.0), int(total / 1048576.0)]
		if speed > 1000.0:
			info += "   ·   %.1f MB/sn" % (speed / 1048576.0)
			var rem: float = (total - done) / speed
			if rem >= 60.0:
				info += "   ·   ~%d dk %d sn kaldı" % [int(rem / 60.0), int(fmod(rem, 60.0))]
			else:
				info += "   ·   ~%d sn kaldı" % (int(rem) + 1)
		info += "   ·   Dosya %d/%d" % [part_idx, part_count]
	elif state == St.MERGING:
		info = "%d / %d MB birleştirildi" % [int(done / 1048576.0), int(total / 1048576.0)]
	elif state == St.READY:
		var ta := clampf(minf(tip_t / 0.5, (6.0 - tip_t) / 0.5), 0.0, 1.0)
		info = "İPUCU  ·  " + TIPS[tip]
		_txt(f_body, Vector2(bx, by + 30), info, 13, Color(MUT, ta))
		info = ""
	if info != "":
		_txt(f_body, Vector2(bx, by + 30), info, 13, MUT)
	_main_button()


func _win_btn(r: Rect2, id: String) -> void:
	var h := hover == id
	if h:
		draw_rect(r, Color(0.82, 0.2, 0.16, 0.8) if id == "close" else Color(1, 1, 1, 0.16))
	var c := r.get_center()
	var col := Color(TX, 1.0 if h else 0.67)
	if id == "close":
		draw_line(c - Vector2(6, 6), c + Vector2(6, 6), col, 1.6, true)
		draw_line(c + Vector2(6, -6), c + Vector2(-6, 6), col, 1.6, true)
	else:
		draw_line(c + Vector2(-7, 1), c + Vector2(7, 1), col, 1.6, true)


func _grad_poly(pts: PackedVector2Array, c_left: Color, c_right: Color) -> void:
	var x0 := pts[3].x
	var x1 := pts[1].x
	var cols := PackedColorArray()
	for p in pts:
		cols.append(c_left.lerp(c_right, clampf((p.x - x0) / maxf(1.0, x1 - x0), 0.0, 1.0)))
	draw_polygon(pts, cols)


func _bar(x: float, y: float, w: float, h: float, f: float, bad: bool) -> void:
	draw_colored_polygon(_skew(Rect2(x, y, w, h), 6), Color(0.145, 0.169, 0.2, 0.8))
	var fw := clampf(f, 0.0, 1.0) * w
	if fw < 2.0:
		return
	var a := Color("962819") if bad else ORD
	var b := RED if bad else OR2
	_grad_poly(_skew(Rect2(x, y, fw, h), minf(6.0, fw * 0.5)), a, b)
	if bad:
		return
	# hareketli parıltı
	var sw := 120.0
	var s0 := x + fmod(t * 260.0, w + 2 * sw) - sw
	var l := maxf(s0, x + 6)
	var r := minf(s0 + sw, x + fw - 6)
	if r > l:
		var mid := s0 + sw * 0.5
		var pts := PackedVector2Array([Vector2(l + 6, y), Vector2(r + 6, y), Vector2(r, y + h), Vector2(l, y + h)])
		var cols := PackedColorArray()
		for p in pts:
			cols.append(Color(1, 0.94, 0.86, 0.55 * clampf(1.0 - absf(p.x - mid) / (sw * 0.5), 0.0, 1.0)))
		draw_polygon(pts, cols)
	# uçta parlama
	var ex := x + fw
	for i in 4:
		draw_circle(Vector2(ex - 3, y + h * 0.5), 6.0 + i * 5.0, Color(1, 0.67, 0.31, 0.16 - i * 0.035))


func _bar_indeterminate(x: float, y: float, w: float, h: float) -> void:
	draw_colored_polygon(_skew(Rect2(x, y, w, h), 6), Color(0.145, 0.169, 0.2, 0.8))
	var seg := w * 0.22
	var s0 := x + (sin(t * 2.2) + 1.0) * 0.5 * (w - seg)
	_grad_poly(_skew(Rect2(s0, y, seg, h), 6), ORD, OR2)


func _main_button() -> void:
	var rd := state == St.READY
	var error := state == St.ERROR
	var active := rd or error
	var h := hover == "btn" and active
	var r := r_btn
	if h:
		r.position.y -= 2
	var label := "BAŞLAT" if rd else ("TEKRAR DENE" if error else ("HAZIRLANIYOR" if state == St.MERGING else ("BEKLEYİN" if state == St.CHECKING else "İNDİRİLİYOR")))
	if rd:
		var p := 0.5 + 0.5 * sin(t * 3.0)
		for i in range(3, 0, -1):
			var gr := r.grow_individual(i * 5 + p * 4, i * 4 + p * 3, i * 5 + p * 4, i * 4 + p * 3)
			draw_colored_polygon(_skew(gr, 18), Color(OR, (22.0 + p * 18.0) / 255.0))
	var pts := _skew(r, 16)
	if rd:
		var top := Color("ffcd8c") if h else OR2
		draw_polygon(pts, PackedColorArray([top, top, ORD, ORD]))
	elif error:
		var top2 := Color("6e7682") if h else Color("5a626e")
		draw_polygon(pts, PackedColorArray([top2, top2, Color("373e48"), Color("373e48")]))
	else:
		draw_colored_polygon(pts, Color(0.118, 0.137, 0.165, 0.86))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(1, 1, 1, 0.27), 1.0, true)
	var tc := Color("1a0f04") if rd else (TX if error else DIM)
	var fs := 26
	var tw := f_btn.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lx := r.position.x + (r.size.x - tw) * 0.5
	var base_y := r.position.y + r.size.y * 0.5 + fs * 0.36
	if rd:
		var ix := lx - 12
		var iy := r.position.y + r.size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(ix - 7, iy - 9), Vector2(ix + 7, iy), Vector2(ix - 7, iy + 9)]), tc)
		lx += 10
	draw_string(f_btn, Vector2(lx, base_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)


# ------------------------------------------------------------------ fare / klavye
func _hit(p: Vector2) -> String:
	var q := Vector2(p.x * W / size.x, p.y * H / size.y)
	if r_close.has_point(q):
		return "close"
	if r_min.has_point(q):
		return "min"
	if r_btn.has_point(q):
		return "btn"
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = _hit(e.position)
		var hand := hover == "close" or hover == "min" or (hover == "btn" and (state == St.READY or state == St.ERROR))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hand else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(e.position)
		if e.pressed:
			if h == "":
				DisplayServer.window_start_drag()
		else:
			if h == "close":
				get_tree().quit()
			elif h == "min":
				get_window().mode = Window.MODE_MINIMIZED
			elif h == "btn":
				if state == St.READY:
					_play()
				elif state == St.ERROR:
					_retry()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_ENTER and state == St.READY:
			_play()
		elif e.keycode == KEY_ESCAPE:
			get_tree().quit()
