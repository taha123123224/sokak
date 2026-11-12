extends Node3D
## v3.8 ground items: dropped weapons (G drops yours, E picks one up — it swaps with the weapon in that slot)
## and the ammo bag every fallen soldier leaves behind (walk over it: mermi for your guns).
## Weapons keep their magazine / reserve. Items fade out after a while so the map stays clean.

const WEAPON_LIFE := 10.0
const BAG_LIFE := 10.0
const PICK_R := 1.9
const BAG_R := 1.35

var m                         # match node
var items: Array = []         # {kind, node, wid, mag, res, t, vel, rest}
var focus = null              # weapon item under the crosshair (E prompt)

func setup(match_node) -> void:
	m = match_node

func drop_weapon(wid: String, mag: int, res: int, pos: Vector3, vel: Vector3) -> void:
	if not GS.WEAPONS.has(wid):
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var ps: PackedScene = GS.weapon_scene(wid)
	if ps:
		var w: Node3D = ps.instantiate()
		root.add_child(w)
		# weapon space: muzzle +Y, up +Z -> lie flat on its side, muzzle along +X
		w.rotation = Vector3(0, 0, -PI * 0.5)
		w.rotate_object_local(Vector3.UP, PI * 0.5)
		MatLib.apply(w, GS.wskin(wid) if GS.owned(wid) else "std")
		w.scale = Vector3.ONE * 0.85
	_glow_ring(root, Color(1.0, 0.75, 0.3))
	items.append({"kind": "w", "node": root, "wid": wid, "mag": mag, "res": res, "t": 0.0, "vel": vel, "rest": false,
		"spin": randf_range(-6.0, 6.0)})
	_cap()

func _box(root: Node3D, sz: Vector3, pos: Vector3, mt: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = sz
	mi.mesh = bm
	mi.material_override = mt
	mi.position = pos
	root.add_child(mi)
	return mi

static var _nylon: StandardMaterial3D
static var _strap: StandardMaterial3D
static var _metal: StandardMaterial3D
func drop_bag(pos: Vector3) -> void:
	## v4.1: small coyote-tan ammo pouch (flap, straps, buckle) with a floating ammo icon
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos + Vector3(0, 0.3, 0)
	if _nylon == null:
		_nylon = StandardMaterial3D.new(); _nylon.albedo_color = Color(0.46, 0.39, 0.28); _nylon.roughness = 0.95
		_strap = StandardMaterial3D.new(); _strap.albedo_color = Color(0.16, 0.15, 0.12); _strap.roughness = 0.8
		_metal = StandardMaterial3D.new(); _metal.albedo_color = Color(0.25, 0.25, 0.27); _metal.metallic = 0.8; _metal.roughness = 0.35
	var body := Node3D.new()
	root.add_child(body)
	_box(body, Vector3(0.22, 0.12, 0.15), Vector3(0, 0.06, 0), _nylon)
	_box(body, Vector3(0.23, 0.025, 0.155), Vector3(0, 0.127, -0.005), _nylon)          # flap
	_box(body, Vector3(0.225, 0.07, 0.012), Vector3(0, 0.1, 0.078), _nylon)             # flap front
	for x in [-0.06, 0.06]:
		_box(body, Vector3(0.025, 0.13, 0.16), Vector3(x, 0.065, 0.002), _strap)
		_box(body, Vector3(0.03, 0.02, 0.01), Vector3(x, 0.09, 0.083), _metal)
	_box(body, Vector3(0.2, 0.012, 0.012), Vector3(0, 0.03, 0.078), _strap)            # molle row
	# floating ammo marker (always faces the camera, constant size)
	var ic := Label3D.new()
	ic.text = "▮▮▮"
	ic.font = UI.font("BarlowSemiCondensed-Bold")
	ic.font_size = 40
	ic.outline_size = 10
	ic.modulate = Color(1.0, 0.82, 0.35)
	ic.outline_modulate = Color(0, 0, 0, 0.6)
	ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ic.fixed_size = true
	ic.pixel_size = 0.0007
	ic.no_depth_test = false
	ic.position.y = 0.42
	ic.name = "icon"
	root.add_child(ic)
	_glow_ring(root, Color(1.0, 0.8, 0.35))
	items.append({"kind": "b", "node": root, "t": 0.0, "vel": Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), "rest": false, "spin": 2.0})
	_cap()

func _glow_ring(root: Node3D, c: Color) -> void:
	## a thin soft disc under the item (not a big torus)
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(0.62, 0.62); qm.orientation = PlaneMesh.FACE_Y
	ring.mesh = qm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial; render_mode unshaded, blend_add, cull_disabled, depth_draw_never; uniform vec4 c : source_color; void fragment(){ float r = length(UV - 0.5) * 2.0; float a = smoothstep(1.0, 0.85, r) * smoothstep(0.62, 0.86, r) * 0.9 + (1.0 - smoothstep(0.0, 0.9, r)) * 0.12; ALBEDO = c.rgb; ALPHA = a * c.a; }"
	sm.shader = sh
	sm.set_shader_parameter("c", Color(c.r, c.g, c.b, 0.8))
	ring.material_override = sm
	ring.name = "ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

func _cap() -> void:
	while items.size() > 28:
		var it: Dictionary = items.pop_front()
		if is_instance_valid(it["node"]):
			it["node"].queue_free()

func _process(delta: float) -> void:
	if m == null:
		return
	var space := get_world_3d().direct_space_state
	var keep: Array = []
	for it in items:
		var n: Node3D = it["node"]
		if not is_instance_valid(n):
			continue
		it["t"] += delta
		var life: float = WEAPON_LIFE if it["kind"] == "w" else BAG_LIFE
		if it["t"] > life:
			n.queue_free()
			continue
		if not it["rest"]:
			# simple ballistic fall until it hits the ground
			var v: Vector3 = it["vel"]
			v.y -= 14.0 * delta
			var from := n.global_position
			var to := from + v * delta
			var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.05, 0), to - Vector3(0, 0.08, 0), 1)
			var r := space.intersect_ray(q)
			if not r.is_empty() and v.y < 0.0:
				n.global_position = r["position"] + Vector3(0, 0.06, 0)
				it["rest"] = true
			else:
				n.global_position = to
				n.rotate_y(it["spin"] * delta)
			it["vel"] = v
		var ring := n.get_node_or_null("ring") as MeshInstance3D
		if ring:
			ring.position.y = 0.01
			var pulse := 0.9 + 0.1 * sin(it["t"] * 4.0)
			ring.scale = Vector3.ONE * pulse
			ring.visible = it["rest"]
		var ic := n.get_node_or_null("icon") as Label3D
		if ic:
			ic.position.y = 0.42 + 0.04 * sin(it["t"] * 3.0)
		if it["t"] > life - 2.0:
			# shrink away in the last two seconds
			var k := clampf((life - it["t"]) / 2.0, 0.0, 1.0)
			n.scale = Vector3.ONE * maxf(k, 0.05)
		keep.append(it)
	items = keep
	_player_logic()

func _player_logic() -> void:
	focus = null
	var p = m.player
	if p == null or not p.alive or ("wolf" in p and p.wolf):
		return
	var eye: Vector3 = p.cam.global_position
	var fwd: Vector3 = -p.cam.global_transform.basis.z
	var best := 0.0
	for it in items:
		var n: Node3D = it["node"]
		if not it["rest"]:
			continue
		var d := n.global_position.distance_to(p.global_position)
		if it["kind"] == "b":
			if d < BAG_R and _take_bag(p):
				n.queue_free()
				it["t"] = 999.0
			continue
		if d < PICK_R:
			var to := (n.global_position - eye).normalized()
			var dot := to.dot(fwd)
			if dot > 0.75 and dot > best:
				best = dot
				focus = it
	if m.hud and m.hud.has_method("pickup_prompt"):
		m.hud.pickup_prompt(focus["wid"] if focus else "")

func _take_bag(p) -> bool:
	## refill: one magazine's worth of reserve for every gun you carry (no more than the starting reserve x1.5)
	var got := false
	for c in ["ana", "tabanca"]:
		var id: String = p.slots.get(c, "")
		if id == "" or not p.ammo.has(id):
			continue
		var st := GS.stats_for(id)
		var cap := int(float(GS.WEAPONS[id].get("reserve", 0)) * 1.5)
		var a: Array = p.ammo[id]
		if a[1] < cap:
			a[1] = mini(a[1] + int(st["mag"]), cap)
			got = true
	if got:
		SFX.play("equip", -6, 1.4)
		if m.hud and m.hud.has_method("center_msg"):
			m.hud.center_msg("+ MERMİ", Color(0.6, 0.9, 1.0))
	return got

## E: take the weapon under the crosshair (your weapon of that slot drops in its place)
func try_pickup() -> bool:
	if focus == null or not is_instance_valid(focus["node"]):
		return false
	var p = m.player
	var wid: String = focus["wid"]
	var cat := str(GS.WEAPONS[wid]["cat"])
	var pos: Vector3 = focus["node"].global_position
	var old: String = p.slots.get(cat, "")
	if old != "" and old != wid and p.ammo.has(old):
		var oa: Array = p.ammo[old]
		drop_weapon(old, oa[0], oa[1], pos + Vector3(0, 0.4, 0), Vector3(0, 1.5, 0))
	p.take_ground_weapon(cat, wid, int(focus["mag"]), int(focus["res"]))
	focus["node"].queue_free()
	focus["t"] = 999.0
	focus = null
	SFX.play("equip", -4, 1.0)
	return true
