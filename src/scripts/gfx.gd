extends RefCounted
## Graphics driver selection + automatic "is 3D really drawing?" check.
## Some PCs (mostly older AMD drivers, or Windows' Vulkan-on-DirectX layer) start Vulkan fine but draw no 3D at
## all: only the sky and the 2D interface show. At start-up we render a tiny red cube off-screen and read the pixel
## back. If it is missing we switch to DirectX 12, then to the compatibility (OpenGL) renderer, and restart.
## The choice is written to user://grafik.cfg, which project.godot loads as a settings override.

const CFG := "user://grafik.cfg"
const MODES := ["auto", "vulkan", "d3d12", "mobile", "gl"]
const NAMES := {"auto": "Otomatik (önerilen)", "vulkan": "Vulkan", "d3d12": "DirectX 12", "gl": "Uyumluluk (OpenGL) — eski kartlar", "mobile": "Performans modu (zayıf PC)"}

static func load_cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(CFG)
	return c

static func mode() -> String:
	return str(load_cfg().get_value("sokak", "mode", "auto"))

## active driver right now: "vulkan", "d3d12", "opengl3", ...
static func driver() -> String:
	var m := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	if m == "gl_compatibility":
		return "opengl3"
	return RenderingServer.get_current_rendering_driver_name()

## write the override file. mode: auto (= vulkan unless auto-switched), vulkan, d3d12, gl
static func write(mode_: String, auto_pick: String = "") -> void:
	var c := ConfigFile.new()
	var eff := auto_pick if mode_ == "auto" and auto_pick != "" else mode_
	c.set_value("sokak", "mode", mode_)
	c.set_value("sokak", "auto_pick", auto_pick)
	if eff == "d3d12":
		c.set_value("rendering", "rendering_device/driver.windows", "d3d12")
	elif eff == "vulkan":
		c.set_value("rendering", "rendering_device/driver.windows", "vulkan")
	if eff == "gl":
		c.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	elif eff == "mobile":
		c.set_value("rendering", "renderer/rendering_method", "mobile")
	c.save(CFG)

static func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	Engine.get_main_loop().quit()

## renders a lit red cube into a small SubViewport and checks the centre pixel
static func check_3d(host: Node) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	host.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3)
	vp.add_child(cam)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-30, 20, 0)
	vp.add_child(l)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0)
	mat.roughness = 0.8
	bm.material = mat
	mi.mesh = bm
	vp.add_child(mi)
	cam.make_current()
	var ok := false
	for i in 12:
		await RenderingServer.frame_post_draw
		if i < 3:
			continue
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			continue
		var px := img.get_pixel(32, 32)
		if px.r > 0.25 and px.r > px.b * 1.5 and px.g < 0.4:
			ok = true
			break
	vp.queue_free()
	return ok

## called once at start-up (not in test runs). Returns true when the game is restarting.
static func startup(host: Node) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var c := load_cfg()
	var m := str(c.get_value("sokak", "mode", "auto"))
	var tries := int(c.get_value("sokak", "tries", 0))
	var ok := await check_3d(host)
	print("GFX driver=%s adapter=%s 3d_ok=%s mode=%s tries=%d" % [driver(), RenderingServer.get_video_adapter_name(), ok, m, tries])
	if ok:
		if tries != 0:
			c.set_value("sokak", "tries", 0)
			c.save(CFG)
		return false
	if m != "auto" or tries >= 2:
		return false             # player picked a driver himself, or both fallbacks were tried: stop switching
	var cur := driver()
	var pick := ""
	if OS.get_name() == "Windows" and cur == "vulkan":
		pick = "d3d12"
	elif cur != "opengl3":
		pick = "gl"
	if pick == "":
		return false
	write("auto", pick)
	var c2 := load_cfg()
	c2.set_value("sokak", "tries", tries + 1)
	c2.save(CFG)
	restart()
	return true
