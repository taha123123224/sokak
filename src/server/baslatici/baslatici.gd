extends Control
## SOKAK: Operasyon - Başlatıcı
## SOKAK.exe --main-pack baslatici.pck ile açılır. Oyun dosyalarını (SOKAK.pck) GitHub'dan
## parça parça indirir (yarıda kalırsa kaldığı yerden devam eder), sonra BAŞLAT ile oyunu açar.

const MANIFEST := "https://raw.githubusercontent.com/taha123123224/sokak/main/version.json"
const W := 820.0
const H := 480.0

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

var r_btn := Rect2(W - 40 - 230, H - 40 - 58, 230, 58)
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
		var r: Dictionary = _fetch(MANIFEST + "?t=" + str(Time.get_unix_time_from_system()), "", 0)
		if r.ok:
			js = (r.body as PackedByteArray).get_string_from_utf8()
			break
		if quitting:
			return
		OS.delay_msec(1200)
	var m = JSON.parse_string(js) if js != "" else null
	if not (m is Dictionary) or not m.has("parts"):
		if _pck_size(pck) > 1000000:
			_st(St.READY, "OYUN HAZIR", "Sunucuya ulaşılamadı; mevcut sürümle oynayabilirsin.")
		else:
			_fail("Sürüm bilgisi alınamadı. İnternet bağlantını kontrol edip TEKRAR DENE'ye bas.")
		return
	version = str(m.get("version", ""))
	var build := str(int(m.get("build", 0)))
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
	var hdr := PackedStringArray(["User-Agent: SOKAK-Baslatici/2.3", "Accept-Encoding: identity"])
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
	if bg:
		draw_texture_rect(bg, Rect2(0, 0, W, H), false)
	else:
		draw_rect(Rect2(0, 0, W, H), Color("0c0e11"))

	_win_btn(r_min, "min")
	_win_btn(r_close, "close")

	var tag := "HAZIR" if state == St.READY else ("HATA" if state == St.ERROR else ("HAZIRLANIYOR" if state == St.MERGING else ("İNDİRİLİYOR" if state == St.DOWNLOADING else "BAĞLANIYOR")))
	var tag_c := GREEN if state == St.READY else (RED if state == St.ERROR else OR)
	var ty := 222.0
	var pulse := 1.0 if state == St.READY or state == St.ERROR else 0.55 + 0.45 * sin(t * 4.0)
	draw_circle(Vector2(46, ty + 8), 4.0, Color(tag_c, pulse))
	_txt(f_lbl, Vector2(58, ty + 13), tag, 13, tag_c)
	if version != "":
		var tw := f_lbl.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_txt(f_lbl, Vector2(58 + tw + 18, ty + 13), "SÜRÜM " + version, 13, DIM)

	_txt(f_title, Vector2(38, ty + 56), title, 36, TX)
	_txt(f_body, Vector2(42, ty + 84), sub, 14, MUT, 600.0)

	var bx := 42.0
	var by := 352.0
	var bw := W - 84.0
	var bh := 10.0
	if state == St.CHECKING:
		_bar_indeterminate(bx, by, bw, bh)
	else:
		_bar(bx, by, bw, bh, shown, state == St.ERROR)

	if state == St.DOWNLOADING or state == St.MERGING:
		var pc := str(int(floor(shown * 100.0)))
		var w1 := f_title.get_string_size(pc, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
		var w2 := f_title.get_string_size("%", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var px := bx + bw - w1 - w2 + 4
		_txt(f_title, Vector2(px, by - 14), "%", 26, OR)
		_txt(f_title, Vector2(px + w2 - 2, by - 12), pc, 46, OR)

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
		info += "   ·   Parça %d/%d" % [part_idx, part_count]
	elif state == St.MERGING:
		info = "%d / %d MB birleştirildi" % [int(done / 1048576.0), int(total / 1048576.0)]
	elif state == St.READY:
		info = "Tüm dosyalar hazır"
	_txt(f_body, Vector2(bx - 1, by + 32), info, 12, MUT)

	var ta := clampf(minf(tip_t / 0.5, (6.0 - tip_t) / 0.5), 0.0, 1.0)
	_txt(f_lbl, Vector2(42, H - 68), "İPUCU", 13, Color(OR, ta))
	_txt(f_body, Vector2(42, H - 48), TIPS[tip], 12, Color(TX, 0.86 * ta), W - 380.0)

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
