extends Node3D
## v4.8 map surroundings: everything OUTSIDE the playable area, so the helicopter insertion (and long sight
## lines over the walls) show a believable place instead of a flat plane in the void:
##  - a large relief terrain (flat near the map, rising into hills / mountains, sea on coastal maps)
##  - theme filler built with MultiMesh (one draw call each): apartment blocks, old-town houses with tiled
##    roofs, industrial sheds, chimneys, tanks, port cranes and container stacks, conifer / broadleaf / olive trees
## All procedural and seeded per map, so every client sees the same thing. No collision (out of bounds anyway).

var c := Vector2.ZERO        # rect centre (x, z)
var hs := Vector2.ONE        # rect half size
var gy := 0.0                # ground level of the map
var th: Dictionary = {}
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var occ := {}                # coarse occupancy grid (8 m cells) so trees avoid buildings
var q := 1.0                 # density factor from the graphics preset
var sea_dir := Vector2.ZERO
var sea_y := -2.5

const THEMES := {
	# relief: mountain height far away; flat: flat ring width before hills; tex: near/far/rock textures
	"mahalle":    {"relief": 70.0, "flat": 160.0, "near": "asphalt", "far": "grass", "tn": [0.75, 0.75, 0.75], "tf": [0.75, 0.8, 0.6],
				   "city": "apt", "n_bld": 1500, "b0": 4.0, "b1": 650.0, "trees": "broad", "n_tree": 1200, "night": 0.0},
	"safranbolu": {"relief": 120.0, "flat": 110.0, "near": "cobble", "far": "grass", "tn": [0.85, 0.82, 0.78], "tf": [0.72, 0.82, 0.55],
				   "city": "oldtown", "n_bld": 900, "b0": 4.0, "b1": 420.0, "trees": "broad", "n_tree": 3200},
	"gemi":       {"relief": 90.0, "flat": 0.0, "near": "grass", "far": "grass", "tn": [0.7, 0.8, 0.55], "tf": [0.6, 0.72, 0.5],
				   "sea": "all", "sea_y": -6.05, "coast": 1500.0, "city": "apt", "n_bld": 900, "b0": 1500.0, "b1": 2300.0, "trees": "broad", "n_tree": 600, "ships": 9},
	"liman":      {"relief": 60.0, "flat": 220.0, "near": "asphalt", "far": "grass", "tn": [0.62, 0.62, 0.62], "tf": [0.72, 0.78, 0.6],
				   "sea": "east", "sea_y": -2.55, "city": "port", "n_bld": 900, "b0": 4.0, "b1": 520.0, "trees": "broad", "n_tree": 900, "ships": 6},
	"insaat":     {"relief": 80.0, "flat": 170.0, "near": "dirt", "far": "grass", "tn": [0.8, 0.75, 0.68], "tf": [0.75, 0.8, 0.6],
				   "city": "apt", "n_bld": 1300, "b0": 6.0, "b1": 600.0, "trees": "broad", "n_tree": 1400, "cranes": 7},
	"canakkale":  {"relief": 110.0, "flat": 90.0, "near": "grass", "far": "grass", "tn": [0.78, 0.74, 0.5], "tf": [0.7, 0.72, 0.48],
				   "sea": "east", "sea_y": -2.25, "city": "village", "n_bld": 260, "b0": 140.0, "b1": 900.0, "trees": "olive", "n_tree": 4200, "ships": 7},
	"hurda":      {"relief": 90.0, "flat": 140.0, "near": "dryground", "far": "dryground", "tn": [0.85, 0.78, 0.68], "tf": [0.8, 0.75, 0.6],
				   "city": "industrial", "n_bld": 600, "b0": 10.0, "b1": 520.0, "trees": "broad", "n_tree": 900, "cranes": 3,
				   "outer": [-80, -148, 73, 89]},
	"fabrika":    {"relief": 80.0, "flat": 150.0, "near": "asphalt", "far": "grass", "tn": [0.72, 0.72, 0.7], "tf": [0.72, 0.76, 0.56],
				   "city": "industrial", "n_bld": 800, "b0": 4.0, "b1": 560.0, "trees": "broad", "n_tree": 1500},
	"cekirdek":   {"relief": 190.0, "flat": 70.0, "near": "rawconc", "far": "grass", "tn": [0.7, 0.7, 0.7], "tf": [0.42, 0.52, 0.32], "roads": [[1.2, 0.5]],
				   "city": "facility", "n_bld": 120, "b0": 4.0, "b1": 160.0, "trees": "conifer", "n_tree": 5200, "snow": 150.0},
	"kereste":    {"relief": 210.0, "flat": 70.0, "near": "grass", "far": "grass", "tn": [0.46, 0.56, 0.34], "tf": [0.36, 0.5, 0.28],
				   "city": "sheds", "n_bld": 26, "b0": 8.0, "b1": 90.0, "trees": "conifer", "n_tree": 7000, "snow": 165.0, "logs": 40,
				   "roads": [[0.35, 1.0], [3.4, 2.0]], "road_tex": "dirt"},
}

static func has_theme(id: String) -> bool:
	return THEMES.has(id)

func build(map_id: String, bounds: Array, ground_y: float, quality: String) -> void:
	th = THEMES.get(map_id, THEMES["fabrika"])
	rng.seed = hash(map_id) & 0x7fffffff
	noise.seed = rng.seed
	noise.frequency = 0.0035
	noise.fractal_octaves = 4
	noise2.seed = rng.seed + 7
	noise2.frequency = 0.02
	gy = ground_y
	if th.has("outer"):
		bounds = th["outer"]     # the model's own terrain reaches further than the playable bounds
	c = Vector2((float(bounds[0]) + float(bounds[2])) * 0.5, -(float(bounds[1]) + float(bounds[3])) * 0.5)
	hs = Vector2((float(bounds[2]) - float(bounds[0])) * 0.5, (float(bounds[3]) - float(bounds[1])) * 0.5)
	q = {"low": 0.45, "medium": 0.7, "high": 1.0, "ultra": 1.0, "epic": 1.15}.get(quality, 0.8)
	var sea: String = th.get("sea", "")
	sea_dir = Vector2(1, 0) if sea == "east" else Vector2.ZERO
	sea_y = float(th.get("sea_y", -2.5))
	_terrain()
	if sea != "":
		_sea()
	_buildings()
	if th.has("cranes"):
		_cranes(int(th["cranes"]))
	if th.has("ships"):
		_ships(int(th["ships"]))
	if th.has("logs"):
		_logs(int(th["logs"]))
	_trees()

# ------------------------------------------------------------------ helpers
func rdist(x: float, z: float) -> float:
	var dx := maxf(absf(x - c.x) - hs.x, 0.0)
	var dz := maxf(absf(z - c.y) - hs.y, 0.0)
	return sqrt(dx * dx + dz * dz)

func sea_k(x: float, z: float) -> float:
	## 0 = land, 1 = open sea
	var sea: String = th.get("sea", "")
	if sea == "all":
		var dd := Vector2(x - c.x, z - c.y).length()
		return 1.0 - smoothstep(float(th["coast"]) - 60.0, float(th["coast"]) + 40.0, dd + noise.get_noise_2d(x, z) * 160.0)
	if sea == "east":
		var e := x - (c.x + hs.x)
		return smoothstep(10.0, 40.0, e + noise.get_noise_2d(x * 0.5, z * 0.5) * 30.0) * (1.0 - smoothstep(1400.0, 1500.0, e))
	return 0.0

func height(x: float, z: float) -> float:
	var d := rdist(x, z) - 3.0
	if d <= 0.0:
		return gy - 0.35
	var flat: float = th["flat"]
	var n1 := noise.get_noise_2d(x, z)
	var ridged := 1.0 - absf(noise.get_noise_2d(x * 0.6 + 100.0, z * 0.6))
	var amp: float = float(th["relief"]) * smoothstep(flat, flat + 420.0, d + n1 * 60.0)
	var h := gy - 0.06 + lerpf(-0.29, 0.0, smoothstep(0.0, 4.0, d))
	h += noise2.get_noise_2d(x, z) * 1.2 * smoothstep(4.0, 40.0, d)
	h += amp * (0.6 * ridged * ridged + 0.4 * (n1 * 0.5 + 0.5))
	var s := sea_k(x, z)
	if s > 0.0:
		h = lerpf(h, sea_y - 9.0, s)
	return h

func road_d(x: float, z: float) -> float:
	## distance to the nearest access road (winding lines leaving the map), 1e9 if the map has none
	var best := 1e9
	for r in th.get("roads", []):
		var a: float = r[0]
		var dv := Vector2(cos(a), sin(a))
		var pv := Vector2(-dv.y, dv.x)
		var rel := Vector2(x - c.x, z - c.y)
		var t := rel.dot(dv)
		if t < 0.0:
			continue
		var lat := rel.dot(pv) - 28.0 * sin(t * 0.007 + float(r[1])) * smoothstep(0.0, 120.0, t)
		best = minf(best, absf(lat))
	return best

func _occ_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / 8.0)), int(floor(z / 8.0)))

func _tex(n: String) -> Texture2D:
	return MatLib.tex(n + "_albedo.png")

# ------------------------------------------------------------------ terrain
const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ta : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mac : filter_linear_mipmap, repeat_enable;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 tint_r = vec3(0.55, 0.52, 0.5);
uniform vec2 ctr;
uniform vec2 half_size;
uniform float flat_d = 100.0;
uniform float snow_h = 9999.0;
uniform float sea_y = -100.0;
uniform sampler2D troad : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tcan : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float canopy_k = 0.0;
uniform vec4 road0 = vec4(0.0);
uniform vec4 road1 = vec4(0.0);
uniform vec4 road2 = vec4(0.0);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0)); w /= (w.x + w.y + w.z);
	return texture(t, p.zy / s).rgb * w.x + texture(t, p.xz / s).rgb * w.y + texture(t, p.xy / s).rgb * w.z;
}
void fragment() {
	vec2 qd = max(abs(wp.xz - ctr) - half_size, vec2(0.0));
	float d = length(qd);
	float m1 = texture(mac, wp.xz * 0.0013).r;
	float m2 = texture(mac, wp.xz * 0.011 + 0.37).r;
	vec3 ca = mix(texture(ta, wp.xz / 5.0).rgb, texture(ta, wp.xz / 27.0).rgb, 0.45) * tint_a;
	vec3 cb = mix(texture(tb, wp.xz / 6.0).rgb, texture(tb, wp.xz / 37.0).rgb, 0.5) * tint_b;
	vec3 cr = tri(tr, wp, wn, 14.0) * tint_r;
	float kb = smoothstep(flat_d * 0.35, flat_d * 1.1 + 30.0, d + (m1 - 0.5) * 90.0);
	vec3 col = mix(ca, cb, kb);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	// distant forests: canopy texture on the far hills (the 3D trees thin out there)
	float fm = smoothstep(0.42, 0.58, texture(mac, wp.xz * 0.0011 + 0.5).r) * smoothstep(180.0, 420.0, d) * canopy_k * (1.0 - smoothstep(0.3, 0.5, slope));
	vec3 cc = mix(texture(tcan, wp.xz / 38.0).rgb, texture(tcan, wp.xz / 97.0).rgb, 0.4) * 1.15;
	col = mix(col, cc, fm);
	col = mix(col, cr, smoothstep(0.22, 0.42, slope + (m2 - 0.5) * 0.18));
	// shoreline sand and wet rock under the water
	float hs = wp.y - sea_y;
	float beach = (1.0 - smoothstep(0.4, 3.0, hs)) * smoothstep(-2.5, -0.4, hs);
	col = mix(col, vec3(0.62, 0.55, 0.42) * (0.8 + 0.3 * m2), beach * step(-99.0, sea_y));
	col = mix(col, vec3(0.04, 0.1, 0.11), smoothstep(-0.6, -3.5, hs) * step(-99.0, sea_y));
	float snow = smoothstep(snow_h - 20.0, snow_h + 15.0, wp.y + (m2 - 0.5) * 30.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	col = mix(col, vec3(0.9, 0.92, 0.95), snow);
	col *= 0.78 + 0.44 * m1;
	// access roads (same formula as road_d() on the CPU side)
	float rd = 1e9;
	vec4 rr[3] = vec4[3](road0, road1, road2);
	for (int i = 0; i < 3; i++) {
		if (rr[i].w < 0.5) continue;
		vec2 dv = rr[i].xy; vec2 pv = vec2(-dv.y, dv.x);
		vec2 rel = wp.xz - ctr;
		float tt = dot(rel, dv);
		if (tt < 0.0) continue;
		float lat = dot(rel, pv) - 28.0 * sin(tt * 0.007 + rr[i].z) * smoothstep(0.0, 120.0, tt);
		rd = min(rd, abs(lat));
	}
	float road = (1.0 - smoothstep(3.2, 4.6, rd + (m2 - 0.5) * 1.5)) * step(0.5, d);
	vec3 rc = mix(texture(troad, wp.xz / 4.0).rgb, texture(troad, wp.xz / 19.0).rgb, 0.4) * vec3(0.78, 0.72, 0.66);
	rc *= 0.8 + 0.25 * smoothstep(0.5, 2.5, rd);   // wheel ruts darker in the middle
	col = mix(col, rc, road);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, snow);
}
"""

func _terrain() -> void:
	var N := 200
	var E := 2600.0
	var xs := PackedFloat32Array()
	for i in N + 1:
		var u := float(i) / N * 2.0 - 1.0
		var a := absf(u)
		xs.append(signf(u) * E * (0.07 * a + 0.93 * pow(a, 2.4)))
	var verts := PackedVector3Array()
	verts.resize((N + 1) * (N + 1))
	for j in N + 1:
		for i in N + 1:
			var x := c.x + xs[i]
			var z := c.y + xs[j]
			verts[j * (N + 1) + i] = Vector3(x, height(x, z), z)
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for j in N + 1:
		for i in N + 1:
			var l := verts[j * (N + 1) + maxi(i - 1, 0)]; var r := verts[j * (N + 1) + mini(i + 1, N)]
			var d := verts[maxi(j - 1, 0) * (N + 1) + i]; var u2 := verts[mini(j + 1, N) * (N + 1) + i]
			norms[j * (N + 1) + i] = (u2 - d).cross(r - l).normalized()
	var idx := PackedInt32Array()
	idx.resize(N * N * 6)
	var k := 0
	for j in N:
		for i in N:
			var a0 := j * (N + 1) + i
			var b0 := a0 + N + 1
			idx[k] = a0; idx[k + 1] = a0 + 1; idx[k + 2] = b0
			idx[k + 3] = a0 + 1; idx[k + 4] = b0 + 1; idx[k + 5] = b0
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "far_terrain"
	mi.mesh = am
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	sm.shader = sh
	sm.set_shader_parameter("ta", _tex(th["near"]))
	sm.set_shader_parameter("tb", _tex(th["far"]))
	sm.set_shader_parameter("tr", _tex("dryground"))
	sm.set_shader_parameter("tint_r", Vector3(0.52, 0.5, 0.48))
	sm.set_shader_parameter("mac", MatLib.tex("macro_noise.png"))
	var tn: Array = th["tn"]; var tf: Array = th["tf"]
	sm.set_shader_parameter("tint_a", Vector3(tn[0], tn[1], tn[2]))
	sm.set_shader_parameter("tint_b", Vector3(tf[0], tf[1], tf[2]))
	sm.set_shader_parameter("ctr", c)
	sm.set_shader_parameter("half_size", hs)
	sm.set_shader_parameter("flat_d", float(th["flat"]))
	sm.set_shader_parameter("snow_h", float(th.get("snow", 9999.0)) + gy)
	sm.set_shader_parameter("sea_y", sea_y if th.has("sea") else -100.0)
	sm.set_shader_parameter("troad", _tex(th.get("road_tex", "asphalt")))
	sm.set_shader_parameter("tcan", MatLib.tex("forest_canopy.png"))
	sm.set_shader_parameter("canopy_k", float(th.get("canopy", 1.0 if th.get("trees", "") == "conifer" else 0.55)))
	var rl: Array = th.get("roads", [])
	for i in mini(rl.size(), 3):
		sm.set_shader_parameter("road%d" % i, Vector4(cos(float(rl[i][0])), sin(float(rl[i][0])), float(rl[i][1]), 1.0))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _sea() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "far_sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	pm.subdivide_width = 8; pm.subdivide_depth = 8
	mi.mesh = pm
	mi.material_override = MatLib.get_mat("water")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, sea_y - 0.3, c.y)
	add_child(mi)

# ------------------------------------------------------------------ buildings
const BLD_SHADER := """
shader_type spatial;
uniform float night = 0.0;
uniform sampler2D mac : filter_linear_mipmap, repeat_enable;
uniform vec3 pal[8];
uniform sampler2D facade : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 lp;
varying vec3 ln;
varying vec4 cd;
varying vec3 bc;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	cd = INSTANCE_CUSTOM;
	lp = VERTEX * cd.xyz;
	ln = NORMAL;
	float fr = fract(INSTANCE_CUSTOM.w) * 8.0;
	bc = pal[int(floor(fr)) % 8] * (0.88 + 0.2 * fract(fr * 7.31));
}
void fragment() {
	float kind = floor(cd.w);
	float seed = fract(fract(cd.w) * 8.0);
	vec3 size = cd.xyz;
	float v = lp.y + size.y * 0.5 - 1.5;          // metres above the street (1.5 m is buried)
	float n = texture(mac, (lp.xz + lp.yy) * 0.05 + seed * 7.0).r;
	if (ln.y > 0.5) {
		vec3 roof = mix(vec3(0.1, 0.098, 0.095), vec3(0.17, 0.16, 0.15), h21(vec2(seed, 3.0)));
		if (kind == 1.0) roof = vec3(0.13, 0.135, 0.14);
		vec2 rp = lp.xz;
		float edge = step(min(size.x * 0.5 - abs(rp.x), size.z * 0.5 - abs(rp.y)), 0.45);
		ALBEDO = mix(roof * (0.8 + 0.35 * n), bc * 0.6, edge);
		ROUGHNESS = 0.9;
	} else if (ln.y < -0.5) {
		ALBEDO = vec3(0.1);
	} else {
		float u = abs(ln.x) > 0.5 ? lp.z + size.z * 0.5 : lp.x + size.x * 0.5;
		float fh = kind == 2.0 ? 2.8 : 3.0;
		float fw = kind == 1.0 ? 6.0 : 3.1;
		vec2 cell = vec2(u / fw, v / fh);
		vec2 f = fract(cell);
		float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.28, f.y) * step(f.y, 0.82);
		win *= step(1.0, cell.y) * step(v, size.y - 2.3);
		if (kind == 1.0) {
			// shed: ribbed cladding, a high strip of skylights only
			win = step(0.1, f.x) * step(f.x, 0.9) * step(size.y - 3.6, v) * step(v, size.y - 2.6);
		}
		float hh = h21(floor(cell) + seed * 31.0);
		vec3 glass = mix(vec3(0.05, 0.07, 0.09), vec3(0.22, 0.27, 0.32), hh);
		vec3 wall = bc * 0.66 * (0.82 + 0.3 * n);
		if (kind == 1.0) wall *= 0.85 + 0.15 * step(0.5, fract(u * 1.6));
		if (kind == 2.0) {
			// old-town: dark timber bands at every floor line
			wall = mix(wall, vec3(0.28, 0.18, 0.1), step(fract(v / fh), 0.07) * step(1.0, v));
		}
		// ground floor: darker shop band
		wall = mix(wall, wall * 0.55, step(v, 3.0) * step(0.0, v) * step(kind, 0.5));
		// grime towards the street
		wall *= mix(0.72, 1.0, smoothstep(0.0, 6.0, v));
		vec3 alb = mix(wall, glass, win);
		if (kind == 0.0 && v > 3.0 && v < size.y - 2.3) {
			// textured facade bays (2 windows x 1 storey) on the upper floors
			vec3 ft = texture(facade, vec2(u / 6.2, -(v - 3.0) / fh)).rgb;
			float lum = dot(ft, vec3(0.33));
			vec3 tinted = ft * 0.72 * bc / vec3(0.86, 0.82, 0.73);
			alb = mix(ft * 0.8, tinted, smoothstep(0.42, 0.6, lum)) * (0.85 + 0.25 * n);
			win = 1.0 - smoothstep(0.3, 0.45, lum);
		}
		ALBEDO = alb;
		ROUGHNESS = mix(0.92, 0.2, win);
		EMISSION = win * step(0.62, hh) * vec3(1.0, 0.78, 0.48) * night * 2.5;
	}
}
"""

var _pal := PackedVector3Array()
var _bld_mm: MultiMesh
var _roof_mm: MultiMesh
var _bld_list: Array = []      # [Transform3D, Color, Vector4]
var _roof_list: Array = []     # [Transform3D, Color]

func _add_bld(pos: Vector3, size: Vector3, rot: float, pi: int, kind: int, roof: bool = false, roof_col: Color = Color(0.62, 0.26, 0.16)) -> void:
	var tot := Vector3(size.x, size.y + 1.5, size.z)
	var b := Basis(Vector3.UP, rot).scaled(tot)
	# custom.w = kind + (palette index + random) / 8
	_bld_list.append([Transform3D(b, pos + Vector3.UP * (tot.y * 0.5 - 1.5)), Color.WHITE, Color(tot.x, tot.y, tot.z, float(kind) + (float(pi % 8) + rng.randf() * 0.95) / 8.0)])
	if roof:
		var rh := minf(size.x, size.z) * rng.randf_range(0.28, 0.42)
		var rb := Basis(Vector3.UP, rot).scaled(Vector3(size.x + 0.8, rh, size.z + 0.8))
		_roof_list.append([Transform3D(rb, pos + Vector3.UP * size.y), roof_col])
	# mark occupancy
	var r := maxf(size.x, size.z) * 0.6
	var x := pos.x - r
	while x <= pos.x + r:
		var z := pos.z - r
		while z <= pos.z + r:
			occ[_occ_key(x, z)] = true
			z += 4.0
		x += 4.0

func _free(x: float, z: float, r: float) -> bool:
	for k in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, -r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, r) * 0.7]:
		if occ.has(_occ_key(x + k.x, z + k.y)):
			return false
	return true

func _ground_ok(x: float, z: float, r: float) -> float:
	## returns the lowest ground height under the footprint, or NAN if too steep / sea
	var h0 := height(x, z)
	var lo := h0; var hi := h0
	for k in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		var hh := height(x + k.x, z + k.y)
		lo = minf(lo, hh); hi = maxf(hi, hh)
		if sea_k(x + k.x, z + k.y) > 0.05:
			return NAN
	if hi - lo > r * 0.9:
		return NAN
	return lo

func _pick_pos(b0: float, b1: float, power: float) -> Vector3:
	## random point whose rect-distance is about [b0, b1] (denser close to the map): a random spot along one
	## side of the rect pushed outwards
	var dd := lerpf(b0, b1, pow(rng.randf(), power))
	var side := rng.randi() % 4
	var p := Vector2.ZERO
	if side == 0: p = Vector2(c.x + rng.randf_range(-hs.x - dd, hs.x + dd), c.y - hs.y - dd)
	elif side == 1: p = Vector2(c.x + rng.randf_range(-hs.x - dd, hs.x + dd), c.y + hs.y + dd)
	elif side == 2: p = Vector2(c.x - hs.x - dd, c.y + rng.randf_range(-hs.y - dd, hs.y + dd))
	else: p = Vector2(c.x + hs.x + dd, c.y + rng.randf_range(-hs.y - dd, hs.y + dd))
	# jitter inwards a bit so the bands do not look like perfect rings
	return Vector3(p.x + rng.randf_range(-6, 6), 0, p.y + rng.randf_range(-6, 6))

func _buildings() -> void:
	var style: String = th.get("city", "")
	var n := int(float(th.get("n_bld", 0)) * q)
	var b0: float = th.get("b0", 6.0)
	var b1: float = th.get("b1", 400.0)
	var PAL := {
		"apt": [Color(0.88, 0.8, 0.62), Color(0.9, 0.66, 0.5), Color(0.92, 0.9, 0.86), Color(0.82, 0.55, 0.48), Color(0.66, 0.72, 0.78), Color(0.9, 0.78, 0.5), Color(0.75, 0.62, 0.55), Color(0.72, 0.8, 0.7)],
		"oldtown": [Color(0.93, 0.9, 0.84), Color(0.92, 0.86, 0.74), Color(0.88, 0.82, 0.74), Color(0.95, 0.93, 0.9)],
		"industrial": [Color(0.55, 0.32, 0.25), Color(0.6, 0.6, 0.58), Color(0.5, 0.52, 0.55), Color(0.62, 0.42, 0.3), Color(0.45, 0.5, 0.48)],
		"port": [Color(0.6, 0.62, 0.64), Color(0.45, 0.55, 0.62), Color(0.7, 0.68, 0.62), Color(0.55, 0.35, 0.28)],
		"village": [Color(0.92, 0.88, 0.8), Color(0.86, 0.8, 0.7), Color(0.9, 0.9, 0.88)],
		"facility": [Color(0.62, 0.63, 0.64), Color(0.5, 0.53, 0.56), Color(0.7, 0.7, 0.68)],
		"sheds": [Color(0.48, 0.34, 0.24), Color(0.55, 0.4, 0.28), Color(0.42, 0.3, 0.22), Color(0.6, 0.58, 0.55)],
	}
	var pal: Array = PAL.get(style, PAL["apt"])
	var placed := 0
	var tries := 0
	var grid := 46.0 if style == "apt" else 38.0
	var chim := []
	var tanks := []
	var conts := []
	while placed < n and tries < n * 12:
		tries += 1
		var p := _pick_pos(b0, b1, 1.6 if style in ["apt", "port", "industrial"] else 1.3)
		var x := p.x; var z := p.z
		var w := 0.0; var dpt := 0.0; var h := 0.0; var kind := 0; var roof := false
		var rot := 0.0
		match style:
			"apt":
				w = rng.randf_range(10, 20); dpt = rng.randf_range(10, 16)
				var dd := rdist(x, z)
				h = rng.randf_range(9, 18) + (rng.randf_range(0, 12) if dd > 120 else 0.0)
				if rng.randf() < 0.06: h = rng.randf_range(30, 55)
				roof = rng.randf() < 0.22
			"oldtown", "village":
				w = rng.randf_range(7, 12); dpt = rng.randf_range(7, 11); h = rng.randf_range(5.5, 9.0)
				kind = 2; roof = true
				rot = rng.randf_range(-0.25, 0.25)
			"industrial", "port":
				if rng.randf() < 0.55:
					w = rng.randf_range(24, 50); dpt = rng.randf_range(16, 30); h = rng.randf_range(8, 14); kind = 1
				else:
					w = rng.randf_range(10, 18); dpt = rng.randf_range(10, 14); h = rng.randf_range(9, 20)
			"facility":
				w = rng.randf_range(12, 30); dpt = rng.randf_range(10, 22); h = rng.randf_range(5, 10); kind = rng.randi() % 2
			"sheds":
				w = rng.randf_range(9, 20); dpt = rng.randf_range(7, 12); h = rng.randf_range(4.5, 7.5); kind = 1
				roof = rng.randf() < 0.6
				rot = rng.randf_range(-0.4, 0.4)
		# street grid for the dense styles
		if style in ["apt", "industrial", "port"]:
			var gx := fposmod(x, grid); var gz := fposmod(z, grid)
			if gx < 9.0 or gz < 9.0:
				continue
			# snap the footprint inside its block
			x = floor(x / grid) * grid + clampf(gx, 9.0 + w * 0.5, grid - w * 0.5 - 0.5)
			z = floor(z / grid) * grid + clampf(gz, 9.0 + dpt * 0.5, grid - dpt * 0.5 - 0.5)
		var r := maxf(w, dpt) * 0.55
		if rdist(x, z) < b0 + r or road_d(x, z) < r + 6.0:
			continue
		if not _free(x, z, r):
			continue
		var gyy := _ground_ok(x, z, r)
		if is_nan(gyy):
			continue
		var pidx := rng.randi() % pal.size()
		var rc := Color(0.5, 0.21, 0.13) * rng.randf_range(0.85, 1.1) if style != "sheds" else Color(0.2, 0.19, 0.18) * rng.randf_range(0.8, 1.2)
		_add_bld(Vector3(x, gyy, z), Vector3(w, h, dpt), rot, pidx, kind, roof, rc)
		placed += 1
		if style in ["industrial", "port", "facility"] and rng.randf() < 0.07:
			chim.append(Vector3(x + w * 0.3, gyy, z))
		if style in ["industrial", "facility"] and rng.randf() < 0.08:
			tanks.append(Vector3(x - w * 0.5 - 7, gyy, z))
		if style == "port" and rng.randf() < 0.35:
			conts.append(Vector3(x, gyy, z + dpt * 0.5 + 7))
	_pal = PackedVector3Array()
	for i in 8:
		var pc: Color = pal[i % pal.size()]
		_pal.append(Vector3(pc.r, pc.g, pc.b))
	_flush_buildings()
	if not chim.is_empty():
		_chimneys(chim)
	if not tanks.is_empty():
		_tanks(tanks)
	if style == "port":
		_container_yard(conts)

func _flush_buildings() -> void:
	if _bld_list.is_empty():
		return
	if OS.has_environment("OSKDBG"):
		print("OSK first building ", _bld_list[0][0].origin, " size ", _bld_list[0][2])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var bm := BoxMesh.new()
	mm.mesh = bm
	mm.instance_count = _bld_list.size()
	for i in _bld_list.size():
		mm.set_instance_transform(i, _bld_list[i][0])
		mm.set_instance_custom_data(i, _bld_list[i][2])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "far_buildings"
	mmi.multimesh = mm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLD_SHADER
	sm.shader = sh
	sm.set_shader_parameter("mac", MatLib.tex("macro_noise.png"))
	sm.set_shader_parameter("night", float(th.get("night", 0.0)))
	sm.set_shader_parameter("pal", _pal)
	sm.set_shader_parameter("facade", MatLib.tex("facade_apt.png"))
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	if not _roof_list.is_empty():
		var rx := []; var rc := []
		for r in _roof_list:
			rx.append(r[0]); rc.append(r[1])
		var rt := MatLib.tex(("corrugated" if th.get("city", "") in ["sheds", "industrial", "port", "facility"] else "rooftiles") + "_albedo.png")
		_mm_simple("far_roofs", _pyramid_mesh(), rx, rc, _vc_mat(0.85, 0.0, rt, Vector2(3, 3), true))

func _pyramid_mesh() -> Mesh:
	## hip roof: unit footprint (-0.5..0.5), height 1, ridge along X
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0, -0.5); var b := Vector3(0.5, 0, -0.5); var cc := Vector3(0.5, 0, 0.5); var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(-0.22, 1, 0); var r1 := Vector3(0.22, 1, 0)
	var tris := [[a, r0, r1], [a, r1, b], [cc, r1, r0], [cc, r0, d], [d, r0, a], [b, r1, cc]]
	for t in tris:
		var n: Vector3 = ((t[1] - t[0]).cross(t[2] - t[0])).normalized()
		if n.y < 0: n = -n
		for v in t:
			st.set_normal(n)
			st.set_uv(Vector2(v.x + 0.5, v.y + v.z))
			st.add_vertex(v)
	return st.commit()

func _mm_simple(name_: String, mesh: Mesh, xf: Array, cols: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cols[i] if not cols.is_empty() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

const VC_SHADER := """
shader_type spatial;
uniform float rough = 0.9;
uniform float metal = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec2 uvs = vec2(1.0);
varying vec3 ic;
void vertex() { ic = COLOR.rgb * INSTANCE_CUSTOM.rgb; }
void fragment() {
	ALBEDO = ic * texture(tex, UV * uvs).rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

func _vc_mat(rough: float = 0.9, metal: float = 0.0, tex: Texture2D = null, uvs: Vector2 = Vector2.ONE, cull_off: bool = false) -> ShaderMaterial:
	## per-instance colour comes in INSTANCE_CUSTOM (multiplied with the mesh's vertex colours)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VC_SHADER.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;") if cull_off else VC_SHADER
	m.shader = sh
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	if tex:
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("uvs", uvs)
	return m

func _chimneys(pts: Array) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75; cm.bottom_radius = 1.0; cm.height = 1.0; cm.radial_segments = 12; cm.rings = 1
	var xf := []; var cols := []
	for p in pts:
		var h := rng.randf_range(22, 42)
		xf.append(Transform3D(Basis().scaled(Vector3(1.6, h, 1.6)), p + Vector3.UP * h * 0.5))
		cols.append(Color(0.52, 0.3, 0.24) if rng.randf() < 0.6 else Color(0.62, 0.62, 0.6))
	_mm_simple("far_chimneys", cm, xf, cols, _vc_mat())

func _tanks(pts: Array) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5; cm.bottom_radius = 0.5; cm.height = 1.0; cm.radial_segments = 20; cm.rings = 1
	var xf := []; var cols := []
	for p in pts:
		var r := rng.randf_range(5, 9); var h := rng.randf_range(7, 14)
		var pp: Vector3 = p
		pp.y = height(pp.x, pp.z) - 0.5
		xf.append(Transform3D(Basis().scaled(Vector3(r * 2, h, r * 2)), pp + Vector3.UP * h * 0.5))
		cols.append(Color(0.78, 0.78, 0.76) if rng.randf() < 0.6 else Color(0.55, 0.6, 0.62))
	_mm_simple("far_tanks", cm, xf, cols, _vc_mat(0.5, 0.4))

func _container_yard(pts: Array) -> void:
	var bm := BoxMesh.new()
	var xf := []; var cols := []
	var CC := [Color(0.75, 0.2, 0.15), Color(0.15, 0.35, 0.65), Color(0.2, 0.5, 0.3), Color(0.85, 0.55, 0.15), Color(0.6, 0.6, 0.62), Color(0.95, 0.95, 0.92)]
	for p in pts:
		var rows := rng.randi_range(2, 5)
		for rI in rows:
			var stack := rng.randi_range(1, 4)
			for s in stack:
				var pos: Vector3 = p + Vector3(rng.randf_range(-1, 1), 0, rI * 2.8)
				if not _free(pos.x, pos.z, 4.0) or sea_k(pos.x, pos.z) > 0.0:
					continue
				pos.y = height(pos.x, pos.z) + 1.3 + s * 2.6
				xf.append(Transform3D(Basis().scaled(Vector3(12.2, 2.6, 2.45)), pos))
				cols.append(CC[rng.randi() % CC.size()] * rng.randf_range(0.8, 1.05))
	if not xf.is_empty():
		_mm_simple("far_containers", bm, xf, cols, _vc_mat(0.6, 0.3))

func _crane_mesh(port: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := []
	if port:
		# ship-to-shore gantry crane: 4 legs, a beam and a long boom out over the water
		for lx in [-8.0, 8.0]:
			for lz in [-6.0, 6.0]:
				parts.append([Vector3(lx, 15, lz), Vector3(1.2, 30, 1.2)])
		parts.append([Vector3(0, 31, -6), Vector3(18, 2.5, 2)])
		parts.append([Vector3(0, 31, 6), Vector3(18, 2.5, 2)])
		parts.append([Vector3(30, 34, 0), Vector3(80, 2.2, 3)])
		parts.append([Vector3(-4, 40, 0), Vector3(3, 14, 3)])
		parts.append([Vector3(2, 33, 0), Vector3(6, 4, 8)])
	else:
		# tower crane: mast, jib, counter-jib, counterweight, cab
		parts.append([Vector3(0, 22, 0), Vector3(1.8, 44, 1.8)])
		parts.append([Vector3(14, 44.5, 0), Vector3(36, 1.4, 1.4)])
		parts.append([Vector3(-9, 44.5, 0), Vector3(14, 1.4, 1.6)])
		parts.append([Vector3(-14, 43.0, 0), Vector3(4, 3, 2.4)])
		parts.append([Vector3(0, 47.5, 0), Vector3(1.2, 5, 1.2)])
		parts.append([Vector3(1.4, 42.5, 0), Vector3(2.2, 2.2, 2.2)])
	for p in parts:
		var bm := BoxMesh.new()
		bm.size = p[1]
		st.append_from(bm, 0, Transform3D(Basis(), p[0]))
	return st.commit()

func _cranes(n: int) -> void:
	var xf := []; var cols := []
	var port: bool = th.get("city", "") == "port"
	for i in n * 4:
		if xf.size() >= n:
			break
		var p := _pick_pos(30.0, 260.0, 1.2)
		var g := _ground_ok(p.x, p.z, 4.0)
		if is_nan(g):
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, g, p.z)))
		cols.append(Color(0.95, 0.72, 0.1))
	if port:
		# along the quay, booms over the water
		var qx := c.x + hs.x + 14.0
		for i in 5:
			var z := c.y + (i - 2) * 70.0 + 160.0
			xf.append(Transform3D(Basis(), Vector3(qx, gy, z)))
			cols.append(Color(0.9, 0.3, 0.12) if i % 2 == 0 else Color(0.2, 0.45, 0.75))
	if not xf.is_empty():
		_mm_simple("far_cranes", _crane_mesh(port), xf, cols, _vc_mat(0.6, 0.3))

func _ships(n: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := BoxMesh.new(); hull.size = Vector3(90, 10, 16)
	st.append_from(hull, 0, Transform3D(Basis(), Vector3(0, 2, 0)))
	var bridge := BoxMesh.new(); bridge.size = Vector3(10, 12, 14)
	st.append_from(bridge, 0, Transform3D(Basis(), Vector3(-36, 13, 0)))
	var cargo := BoxMesh.new(); cargo.size = Vector3(60, 5, 13)
	st.append_from(cargo, 0, Transform3D(Basis(), Vector3(6, 9.5, 0)))
	var mesh := st.commit()
	var xf := []; var cols := []
	for i in n * 10:
		if xf.size() >= n:
			break
		var ang := rng.randf() * TAU
		var dd := rng.randf_range(350.0, 1300.0)
		var p := Vector2(c.x, c.y) + Vector2(cos(ang), sin(ang)) * dd
		if sea_k(p.x, p.y) < 0.99 or sea_k(p.x + 60, p.y) < 0.99 or sea_k(p.x - 60, p.y) < 0.99:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), Vector3(p.x, sea_y - 1.5, p.y)))
		cols.append([Color(0.25, 0.27, 0.3), Color(0.55, 0.15, 0.12), Color(0.15, 0.25, 0.4), Color(0.85, 0.85, 0.82)][rng.randi() % 4])
	if not xf.is_empty():
		_mm_simple("far_ships", mesh, xf, cols, _vc_mat(0.6, 0.2))

func _logs(n: int) -> void:
	## lumber yards around the mill: stacked logs
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5; cm.bottom_radius = 0.5; cm.height = 1.0; cm.radial_segments = 8; cm.rings = 1
	var xf := []; var cols := []
	for i in n:
		var p := _pick_pos(8.0, 120.0, 1.4)
		var g := _ground_ok(p.x, p.z, 5.0)
		if is_nan(g) or not _free(p.x, p.z, 5.0):
			continue
		var yaw := rng.randf() * TAU
		var L := rng.randf_range(8, 12)
		var rows := rng.randi_range(2, 4)
		for r in rows:
			for k in rows - r + 2:
				var off: Vector3 = Vector3(0, 0.45 + r * 0.8, (k - (rows - r + 1) * 0.5) * 0.9 + r * 0.45)
				var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI / 2)
				xf.append(Transform3D(b.scaled(Vector3(0.9, L, 0.9)), Vector3(p.x, g, p.z) + Basis(Vector3.UP, yaw) * off))
				cols.append(Color(0.55, 0.4, 0.26) * rng.randf_range(0.8, 1.1))
		occ[_occ_key(p.x, p.z)] = true
	if not xf.is_empty():
		_mm_simple("far_logs", cm, xf, cols, _vc_mat(0.95, 0.0, MatLib.tex("woodbeam_albedo.png")))

# ------------------------------------------------------------------ trees
func _prim_into(st: SurfaceTool, pm: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
	var arr := pm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in ix:
		st.set_color(col)
		st.set_normal((xf.basis * nn[i]).normalized())
		st.add_vertex(xf * v[i])

func _tree_mesh(kind: String, far: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12; trunk.bottom_radius = 0.2; trunk.height = 1.0; trunk.radial_segments = 5; trunk.rings = 0
	trunk.cap_top = false; trunk.cap_bottom = false
	var bark := Color(0.32, 0.22, 0.15)
	var seg := 6 if far else 7
	match kind:
		"conifer":
			if not far:
				_prim_into(st, trunk, Transform3D(Basis().scaled(Vector3(1, 0.3, 1)), Vector3(0, 0.15, 0)), bark)
			var layers := 1 if far else 3
			for k in layers:
				var cn := CylinderMesh.new()
				cn.top_radius = 0.0; cn.rings = 0; cn.radial_segments = seg
				cn.cap_top = false; cn.cap_bottom = far
				if far:
					cn.bottom_radius = 0.27; cn.height = 0.92
					_prim_into(st, cn, Transform3D(Basis(), Vector3(0, 0.08 + 0.46, 0)), Color(0.15, 0.25, 0.08))
				else:
					cn.bottom_radius = 0.3 - k * 0.07; cn.height = 0.5 - k * 0.06
					_prim_into(st, cn, Transform3D(Basis(), Vector3(0, 0.28 + k * 0.22 + cn.height * 0.5, 0)), Color(0.15, 0.26, 0.08).lightened(k * 0.04))
		"olive", "broad":
			var olive := kind == "olive"
			if not far:
				_prim_into(st, trunk, Transform3D(Basis().scaled(Vector3(1.4, 0.45, 1.4)), Vector3(0, 0.22, 0)), bark)
			var blobs := 1 if far else 2
			for k in blobs:
				var sp := SphereMesh.new()
				sp.radial_segments = seg + 1; sp.rings = 3 if far else 4
				sp.radius = 0.34 - k * 0.05; sp.height = 0.6 - k * 0.1
				var pos := Vector3(0, 0.62, 0) if far else Vector3(sin(k * 2.1) * 0.12, 0.6 + k * 0.2, cos(k * 2.1) * 0.12)
				if olive:
					pos.y -= 0.08
				_prim_into(st, sp, Transform3D(Basis(), pos), Color(0.38, 0.42, 0.22) if olive else Color(0.24, 0.36, 0.1))
	return st.commit()

const TREE_SHADER := """
shader_type spatial;
render_mode specular_disabled;
varying float hy;
varying vec3 vc;
void vertex() { hy = VERTEX.y; vc = COLOR.rgb * INSTANCE_CUSTOM.rgb; }
void fragment() {
	// darker towards the trunk / inside the crown, lit tips on top
	ALBEDO = vc * 0.75 * mix(0.4, 1.05, smoothstep(0.05, 1.0, hy));
	ROUGHNESS = 1.0;
}
"""

func _trees() -> void:
	var kind: String = th.get("trees", "broad")
	var n := int(float(th.get("n_tree", 1000)) * q)
	var xf := []; var cols := []
	var xf2 := []; var cols2 := []
	var tries := 0
	var tree_from := 4.0 if th.get("city", "") in ["sheds", "facility"] else 6.0
	while xf.size() + xf2.size() < n and tries < n * 5:
		tries += 1
		var p := _pick_pos(tree_from, 1100.0, 1.9)
		var x := p.x; var z := p.z
		# clump them into forests with the noise, keep clearings
		var fn := noise.get_noise_2d(x * 2.0, z * 2.0)
		if kind != "olive" and fn < -0.15:
			continue
		if kind == "olive" and fmod(absf(x), 9.0) > 2.2:
			continue     # olive groves are planted in rows
		if not _free(x, z, 3.0) or sea_k(x, z) > 0.0 or road_d(x, z) < 7.5:
			continue
		var h := height(x, z)
		if h > gy + float(th.get("snow", 9999.0)) - 10.0:
			continue
		if h < gy - 0.5 and th.has("sea"):
			continue
		var s := rng.randf_range(8.0, 16.0) if kind == "conifer" else (rng.randf_range(4.0, 6.0) if kind == "olive" else rng.randf_range(6.0, 12.0))
		var tf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.85, 1.15), s, s * rng.randf_range(0.85, 1.15))), Vector3(x, h - 0.2, z))
		var near := rdist(x, z) < 260.0
		(xf if near else xf2).append(tf)
		var tint := Color(rng.randf_range(0.85, 1.2), rng.randf_range(0.88, 1.1), rng.randf_range(0.7, 0.95)) * rng.randf_range(0.8, 1.1)
		(cols if near else cols2).append(tint)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TREE_SHADER
	m.shader = sh
	if not xf.is_empty():
		_mm_simple("far_trees", _tree_mesh(kind, false), xf, cols, m)
	if not xf2.is_empty():
		_mm_simple("far_trees2", _tree_mesh(kind, true), xf2, cols2, m)
