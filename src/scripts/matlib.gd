extends Node
## Material library: maps Blender material names -> high quality PBR StandardMaterial3D.

const TEX := "res://assets/tex/"
var cache := {}
var tex_cache := {}
var water_shader: Shader

# name: [texture_set, uv_scale (tiles per meter), tint, roughness, metallic, extra]
var DEFS := {
	"cobble": ["cobble", 0.42, Color(1, 1, 1), -1, 0, {}],
	"paver": ["paver", 0.5, Color(0.86, 0.85, 0.84), -1, 0, {}],
	"asphalt": ["asphalt", 0.22, Color(1.3, 1.3, 1.32), 0.95, 0, {}],
	"curb": ["concrete", 0.8, Color(1.1, 1.1, 1.08), -1, 0, {}],
	"concrete": ["rawconc", 0.3, Color(1.0, 0.99, 0.97), -1, 0, {}],
	"plaster_white": ["plaster", 0.35, Color(0.86, 0.84, 0.79), -1, 0, {}],
	"plaster_cream": ["plaster", 0.35, Color(0.86, 0.80, 0.67), -1, 0, {}],
	"plaster_ochre": ["plaster", 0.35, Color(0.78, 0.63, 0.45), -1, 0, {}],
	"plaster_rose": ["plaster", 0.35, Color(0.80, 0.66, 0.61), -1, 0, {}],
	"plaster_blue": ["plaster", 0.35, Color(0.62, 0.70, 0.76), -1, 0, {}],
	"plaster_green": ["plaster", 0.35, Color(0.66, 0.73, 0.63), -1, 0, {}],
	"plaster_grey": ["plaster", 0.35, Color(0.63, 0.63, 0.61), -1, 0, {}],
	"plaster_yellow": ["plaster", 0.35, Color(0.86, 0.78, 0.56), -1, 0, {}],
	"plaster_terracotta": ["plaster", 0.35, Color(0.74, 0.53, 0.43), -1, 0, {}],
	"plaster_mint": ["plaster", 0.35, Color(0.67, 0.77, 0.71), -1, 0, {}],
	"plaster_lilac": ["plaster", 0.35, Color(0.74, 0.70, 0.77), -1, 0, {}],
	"flower_pot": ["concrete", 2.0, Color(0.85, 0.42, 0.25), 0.8, 0, {}],
	"flower_red": ["", 1.0, Color(0.95, 0.08, 0.12), 0.6, 0, {"sss": true}],
	"flower_pink": ["", 1.0, Color(1.0, 0.45, 0.72), 0.6, 0, {"sss": true}],
	"flower_white": ["", 1.0, Color(1.0, 1.0, 0.95), 0.6, 0, {"sss": true}],
	"flower_purple": ["", 1.0, Color(0.65, 0.3, 0.95), 0.6, 0, {"sss": true}],
	"plant_green": ["grass", 3.0, Color(0.45, 0.85, 0.35), 0.7, 0, {"sss": true}],
	"shutter_green": ["planks", 1.5, Color(0.25, 0.65, 0.42), -1, 0, {}],
	"shutter_blue": ["planks", 1.5, Color(0.3, 0.52, 0.9), -1, 0, {}],
	"shutter_brown": ["planks", 1.5, Color(0.7, 0.45, 0.28), -1, 0, {}],
	"laundry_0": ["", 1.0, Color(0.95, 0.2, 0.2), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_1": ["", 1.0, Color(0.2, 0.55, 1.0), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_2": ["", 1.0, Color(1.0, 0.88, 0.3), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_3": ["", 1.0, Color(1.0, 1.0, 1.0), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_4": ["", 1.0, Color(0.3, 0.85, 0.45), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_5": ["", 1.0, Color(1.0, 0.5, 0.75), 0.9, 0, {"cull": false, "sss": true}],
	"laundry_6": ["", 1.0, Color(1.0, 0.58, 0.15), 0.9, 0, {"cull": false, "sss": true}],
	"aw_stripe_red": ["", 0.6, Color(1, 1, 1), 0.85, 0, {"tex": "aw_stripe_red.png", "cull": false}],
	"aw_stripe_green": ["", 0.6, Color(1, 1, 1), 0.85, 0, {"tex": "aw_stripe_green.png", "cull": false}],
	"aw_stripe_blue": ["", 0.6, Color(1, 1, 1), 0.85, 0, {"tex": "aw_stripe_blue.png", "cull": false}],
	"aw_stripe_orange": ["", 0.6, Color(1, 1, 1), 0.85, 0, {"tex": "aw_stripe_orange.png", "cull": false}],
	"brick": ["brick2", 0.5, Color(1, 1, 1), -1, 0, {}],
	"woodbeam": ["woodbeam", 0.7, Color(0.85, 0.8, 0.75), -1, 0, {}],
	"planks": ["planks", 0.5, Color(1, 1, 1), -1, 0, {}],
	"planks_crate": ["planks", 0.8, Color(1.05, 0.95, 0.8), -1, 0, {}],
	"pallet": ["planks", 0.8, Color(1.1, 1.05, 0.9), -1, 0, {}],
	"bench_wood": ["planks", 1.0, Color(0.9, 0.75, 0.6), -1, 0, {}],
	"rooftiles": ["rooftiles", 0.9, Color(1, 1, 1), -1, 0, {}],
	"stonewall": ["stonewall", 0.62, Color(1.05, 1.02, 0.97), -1, 0, {}],
	"grass": ["grass", 0.25, Color(1, 1, 1), -1, 0, {}],
	# Ay Vadisi (Kurt Adam)
	"moss_ground": ["grass", 0.22, Color(0.78, 0.95, 0.62), 0.96, 0, {}],
	"river_bed": ["dirt", 0.25, Color(0.7, 0.62, 0.55), 0.95, 0, {}],
	"log_wood": ["woodbeam", 0.9, Color(0.75, 0.62, 0.5), -1, 0, {}],
	"pine_needles": ["grass", 1.4, Color(0.42, 0.62, 0.44), 0.92, 0, {"sss": true}],
	"snow": ["dirt", 0.08, Color(1.6, 1.62, 1.7), 0.75, 0, {}],
	"mountain_rock": ["dirt", 0.06, Color(0.5, 0.52, 0.58), 0.95, 0, {}],
	"ruin_stone": ["stonewall", 0.55, Color(0.95, 0.93, 0.88), -1, 0, {}],
	"ruin_stone_dark": ["ashlar", 0.6, Color(0.62, 0.62, 0.66), 0.92, 0, {}],
	"path_stone": ["cobble", 0.5, Color(0.9, 0.88, 0.85), -1, 0, {}],
	# İnşaat / Çanakkale
	"site_dirt": ["dryground", 0.22, Color(0.92, 0.9, 0.9), 0.97, 0, {}],
	"gravel": ["gravel2", 0.45, Color(0.92, 0.9, 0.87), 0.95, 0, {}],
	"sand": ["dirt", 0.35, Color(1.22, 1.08, 0.86), 0.98, 0, {}],
	"rebar_rust": ["paintmetal", 2.0, Color(0.5, 0.28, 0.16), 0.75, 0.6, {}],
	"crane_yellow": ["paintmetal", 0.8, Color(0.82, 0.6, 0.12), 0.55, 0.3, {}],
	"scaffold_net": ["", 1.0, Color(0.08, 0.26, 0.16, 0.8), 0.9, 0, {"cull": false}],
	"fence_mesh": ["corrugated", 2.0, Color(0.7, 0.72, 0.74), 0.4, 0.8, {}],
	"fence_banner": ["", 1.0, Color(0.08, 0.3, 0.55), 0.75, 0, {"cull": false}],
	"mixer_white": ["paintmetal", 0.6, Color(0.92, 0.92, 0.9), 0.35, 0.3, {}],
	"mixer_drum": ["paintmetal", 0.6, Color(0.95, 0.45, 0.06), 0.4, 0.3, {}],
	"site_sign": ["", 1.0, Color(0.98, 0.76, 0.08), 0.5, 0, {}],
	"cone_orange": ["", 1.0, Color(1.0, 0.36, 0.04), 0.5, 0, {}],
	"cone_white": ["", 1.0, Color(0.95, 0.95, 0.95), 0.4, 0, {}],
	"stripe_red": ["", 1.0, Color(0.8, 0.08, 0.06), 0.5, 0, {}],
	"cable_black": ["", 1.0, Color(0.04, 0.04, 0.04), 0.6, 0, {}],
	"dry_grass": ["grass", 0.26, Color(0.95, 0.9, 0.72), 0.95, 0, {}],
	"path_dirt": ["dirt", 0.3, Color(1.0, 0.95, 0.88), 0.97, 0, {}],
	"cliff_rock": ["stonewall", 0.3, Color(0.78, 0.72, 0.64), 0.9, 0, {}],
	"far_hills": ["grass", 0.02, Color(0.6, 0.65, 0.48), 0.95, 0, {}],
	"fort_stone": ["stonewall", 1.1, Color(0.88, 0.83, 0.74), -1, 0, {}],
	"earth": ["dirt", 0.4, Color(0.82, 0.76, 0.7), 0.98, 0, {}],
	"cannon_iron": ["paintmetal", 1.5, Color(0.16, 0.16, 0.17), 0.45, 0.85, {}],
	"canvas": ["cloth_cotton", 0.8, Color(0.75, 0.7, 0.55), 0.9, 0, {"cull": false}],
	"rock": ["stonewall", 0.8, Color(0.8, 0.76, 0.7), 0.9, 0, {}],
	"dirt": ["dirt", 0.3, Color(0.95, 0.92, 0.88), 0.95, 0, {}],
	"marble": ["concrete", 0.3, Color(1.0, 0.98, 0.95), 0.35, 0, {}],
	"glass_window": ["", 1.0, Color(0.1, 0.13, 0.16), 0.04, 0.3, {"spec": 0.9}],
	"window_lit": ["", 1.0, Color(0.9, 0.75, 0.45), 0.3, 0, {"emit": Color(1.0, 0.78, 0.5), "emit_e": 1.2}],
	"window_frame": ["", 1.0, Color(0.86, 0.86, 0.84), 0.55, 0, {}],
	"frame_wood": ["woodbeam", 1.0, Color(0.75, 0.6, 0.5), -1, 0, {}],
	"metal_dark": ["paintmetal", 0.6, Color(0.16, 0.16, 0.17), -1, 0.6, {}],
	"metal_steel": ["paintmetal", 0.6, Color(0.6, 0.62, 0.64), 0.4, 0.85, {}],
	"metal_rail": ["paintmetal", 1.0, Color(0.14, 0.14, 0.15), 0.45, 0.7, {}],
	"shutter": ["corrugated", 1.2, Color(0.62, 0.63, 0.65), -1, 0.6, {}],
	"awning_red": ["", 1.0, Color(0.68, 0.1, 0.08), 0.85, 0, {"cull": false}],
	"awning_green": ["", 1.0, Color(0.1, 0.42, 0.18), 0.85, 0, {"cull": false}],
	"awning_blue": ["", 1.0, Color(0.1, 0.22, 0.58), 0.85, 0, {"cull": false}],
	"ac_unit": ["paintmetal", 1.0, Color(0.9, 0.9, 0.88), 0.5, 0.1, {}],
	"dish": ["paintmetal", 1.0, Color(0.9, 0.9, 0.9), 0.4, 0.2, {}],
	"flag_red": ["", 1.0, Color(0.85, 0.04, 0.07), 0.8, 0, {"cull": false}],
	"flag_white": ["", 1.0, Color(0.95, 0.95, 0.95), 0.8, 0, {"cull": false}],
	"lamp_glow": ["", 1.0, Color(1, 0.9, 0.7), 0.3, 0, {"emit": Color(1, 0.85, 0.6), "emit_e": 4.0}],
	"foliage": ["grass", 1.2, Color(0.55, 0.8, 0.45), 0.9, 0, {"sss": true}],
	"bark": ["woodbeam", 1.5, Color(0.9, 0.85, 0.8), -1, 0, {}],
	"tire": ["polymer", 2.0, Color(1, 1, 1), 0.9, 0, {}],
	"chrome": ["", 1.0, Color(0.85, 0.85, 0.85), 0.12, 1.0, {}],
	"car_glass": ["", 1.0, Color(0.04, 0.05, 0.06), 0.03, 0.4, {"spec": 1.0}],
	"taillight": ["", 1.0, Color(0.7, 0.03, 0.03), 0.2, 0, {"emit": Color(1, 0.05, 0.02), "emit_e": 0.6}],
	"headlight": ["", 1.0, Color(0.95, 0.95, 0.9), 0.1, 0.2, {"emit": Color(1, 1, 0.9), "emit_e": 0.3}],
	"dumpster": ["paintmetal", 0.6, Color(0.14, 0.36, 0.2), -1, 0.3, {}],
	"sandbag": ["sandbag", 1.5, Color(1, 1, 1), -1, 0, {}],
	"deck": ["deck", 0.4, Color(1, 1, 1), -1, 0, {}],
	"hull_red": ["paintmetal", 0.15, Color(0.5, 0.08, 0.06), -1, 0.2, {}],
	"hull_dark": ["paintmetal", 0.15, Color(0.1, 0.12, 0.15), -1, 0.2, {}],
	"ship_white": ["paintmetal", 0.25, Color(0.9, 0.9, 0.88), -1, 0.15, {}],
	"ship_deck_green": ["paintmetal", 0.2, Color(0.26, 0.42, 0.32), 0.7, 0.1, {}],
	"paint_yellow": ["paintmetal", 0.3, Color(0.9, 0.68, 0.06), -1, 0.2, {}],
	"paint_orange": ["paintmetal", 0.3, Color(0.88, 0.36, 0.06), -1, 0.2, {}],
	"container_red": ["corrugated", 0.45, Color(0.62, 0.13, 0.09), -1, -1, {}],
	"container_blue": ["corrugated", 0.45, Color(0.1, 0.27, 0.58), -1, -1, {}],
	"container_orange": ["corrugated", 0.45, Color(0.88, 0.44, 0.09), -1, -1, {}],
	"container_green": ["corrugated", 0.45, Color(0.13, 0.4, 0.22), -1, -1, {}],
	"container_grey": ["corrugated", 0.45, Color(0.52, 0.54, 0.55), -1, -1, {}],
	"container_yellow": ["corrugated", 0.45, Color(0.88, 0.72, 0.12), -1, -1, {}],
	"container_white": ["corrugated", 0.45, Color(0.88, 0.89, 0.89), -1, -1, {}],
	"warehouse_wall": ["corrugated", 0.35, Color(0.6, 0.62, 0.66), -1, -1, {}],
	"warehouse_roof": ["corrugated", 0.35, Color(0.42, 0.44, 0.47), -1, -1, {}],
	"dome_lead": ["paintmetal", 0.3, Color(0.48, 0.52, 0.55), 0.45, 0.6, {}],
	"rope": ["sandbag", 2.0, Color(0.8, 0.7, 0.5), 0.9, 0, {}],
	"black_paint": ["paintmetal", 1.0, Color(0.05, 0.05, 0.05), 0.5, 0.2, {}],
	"cable": ["", 1.0, Color(0.02, 0.02, 0.02), 0.6, 0, {}],
	"fruit_red": ["", 1.0, Color(0.75, 0.08, 0.05), 0.4, 0, {}],
	"fruit_orange": ["", 1.0, Color(0.95, 0.5, 0.05), 0.45, 0, {}],
	"fruit_green": ["", 1.0, Color(0.4, 0.65, 0.1), 0.45, 0, {}],
	"tea_glass": ["", 1.0, Color(0.6, 0.15, 0.05), 0.05, 0, {}],
	"bus_blue": ["paintmetal", 0.5, Color(0.12, 0.32, 0.72), 0.35, 0.5, {}],
	"barrel_blue": ["paintmetal", 1.0, Color(0.12, 0.27, 0.62), -1, 0.4, {}],
	"barrel_red": ["paintmetal", 1.0, Color(0.62, 0.12, 0.09), -1, 0.4, {}],
	"barrel_yellow": ["paintmetal", 1.0, Color(0.82, 0.62, 0.06), -1, 0.4, {}],
	"paint_line": ["", 1.0, Color(0.85, 0.75, 0.1), 0.7, 0, {}],
	# weapons (uv already scaled x4 in blender)
	"arm_glove": ["polymer", 3.0, Color(0.12, 0.12, 0.12), 0.75, 0, {}],
	"arm_glove_pad": ["polymer", 3.0, Color(0.35, 0.3, 0.22), 0.8, 0, {"no_albedo": true}],
	"arm_sleeve": ["cloth_camo", 3.0, Color(0.9, 0.9, 0.85), 0.9, 0, {}],
	"arm_watch": ["", 1.0, Color(0.03, 0.03, 0.03), 0.3, 0.5, {}],
	"gun_metal": ["gunmetal", 1.0, Color(1, 1, 1), -1, -1, {}],
	"gun_metal_dark": ["gunmetal", 1.0, Color(0.55, 0.55, 0.58), -1, -1, {}],
	"gun_paint": ["polymer", 2.0, Color(1, 1, 1), -1, 0, {}],
	"gun_paint_wood": ["gunwood", 1.0, Color(1, 1, 1), -1, 0, {}],
	"gun_paint_olive": ["polymer", 2.0, Color(0.2, 0.24, 0.15), -1, 0, {"no_albedo": true}],
	"gun_paint_tan": ["polymer", 2.0, Color(0.5, 0.41, 0.29), -1, 0, {"no_albedo": true}],
	"gun_paint_green": ["polymer", 2.0, Color(0.17, 0.23, 0.11), -1, 0, {"no_albedo": true}],
	"gun_paint_steel": ["gunmetal", 1.0, Color(0.62, 0.63, 0.65), -1, -1, {"no_albedo": true}],
	"gun_polymer": ["polymer", 2.0, Color(1, 1, 1), -1, 0, {}],
	"gun_rubber": ["polymer", 3.0, Color(0.7, 0.7, 0.7), 0.95, 0, {}],
	"gun_glass": ["", 1.0, Color(0.15, 0.3, 0.38, 0.35), 0.02, 0.5, {"alpha": true}],
	"gun_holo_glass": ["", 1.0, Color(0.75, 0.92, 1.0, 0.035), 0.02, 0.0, {"alpha": true, "unshaded": true}],
	"gun_magclear": ["", 1.0, Color(0.45, 0.35, 0.18, 0.55), 0.1, 0, {"alpha": true}],
	"gun_paint_eotech": ["gunmetal", 1.0, Color(0.16, 0.16, 0.17), 0.55, 0.6, {"no_albedo": true}],
	"gun_reticle": ["", 1.0, Color(0.02, 0.02, 0.02), 0.6, 0, {"unshaded": true}],
	"gun_dot": ["", 1.0, Color(1, 0.1, 0.05), 0.3, 0, {"emit": Color(1, 0.05, 0.02), "emit_e": 12.0, "unshaded": true}],
	"gun_brass": ["", 1.0, Color(0.85, 0.62, 0.26), 0.28, 1.0, {}],
	"gun_shell": ["", 1.0, Color(0.7, 0.06, 0.05), 0.4, 0, {}],
	"gun_blade": ["gunmetal", 1.0, Color(0.8, 0.81, 0.83), 0.14, 1.0, {"no_albedo": true}],
}

var shaders := {}
func _shader(key: String, code: String) -> Shader:
	if not shaders.has(key):
		var sh := Shader.new()
		sh.code = code
		shaders[key] = sh
	return shaders[key]

func _ready() -> void:
	water_shader = Shader.new()
	water_shader.code = WATER_SHADER

func tex(name: String) -> Texture2D:
	if tex_cache.has(name):
		return tex_cache[name]
	var t: Texture2D = null
	if ResourceLoader.exists(TEX + name):
		t = load(TEX + name)
	tex_cache[name] = t
	return t

func get_mat(name: String) -> Material:
	if cache.has(name):
		return cache[name]
	var m: Material = null
	if name.begins_with("ext_") or name.begins_with("gun_paint_ext"):
		cache[name] = null      # imported, fully textured model: keep its own material
		return null
	if name == "leaves" or name == "foliage":
		var lm := ShaderMaterial.new()
		lm.shader = _shader("leaves", LEAF_SHADER)
		lm.set_shader_parameter("tex", tex("leaves.png"))
		m = lm
	elif name == "flag_tr" or name == "flag_red":
		var fm := ShaderMaterial.new()
		fm.shader = _shader("flag", FLAG_SHADER)
		fm.set_shader_parameter("tex", tex("flag_tr.png") if name == "flag_tr" else null)
		fm.set_shader_parameter("tint", Color(1, 1, 1) if name == "flag_tr" else Color(0.9, 0.05, 0.08))
		m = fm
	elif name == "water":
		var sm := ShaderMaterial.new()
		sm.shader = water_shader
		sm.set_shader_parameter("normal_tex", tex("water_normal.png"))
		m = sm
	elif name.begins_with("sign_"):
		var s := StandardMaterial3D.new()
		s.albedo_texture = tex("signs/" + name.substr(5) + ".png")
		s.roughness = 0.45
		s.emission_enabled = true
		s.emission_texture = s.albedo_texture
		s.emission_energy_multiplier = 0.25
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = s
	elif name.begins_with("cont_") and name != "cont_":
		var s := StandardMaterial3D.new()
		s.albedo_texture = tex(name + ".png")
		s.normal_enabled = true
		s.normal_texture = tex("cont_normal.png")
		s.normal_scale = 1.2
		s.roughness = 0.55; s.metallic = 0.35
		m = s
	elif name == "puddle_dec" or name == "oilstain_dec":
		var s := StandardMaterial3D.new()
		s.albedo_texture = tex(("puddle" if name == "puddle_dec" else "oilstain") + ".png")
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		s.roughness = 0.1 if name == "puddle_dec" else 0.25
		s.metallic = 0.0
		s.metallic_specular = 1.0
		s.render_priority = 1
		m = s
	elif name.begins_with("winint"):
		# glass with a room / curtain behind it + sharp sky reflections
		var s := StandardMaterial3D.new()
		var k := name.substr(6)
		s.albedo_texture = tex("win_int%s.png" % k)
		s.roughness = 0.05
		s.metallic = 0.15
		s.metallic_specular = 0.9
		s.clearcoat_enabled = true; s.clearcoat = 1.0; s.clearcoat_roughness = 0.02
		if k == "2" or k == "6":
			s.emission_enabled = true
			s.emission_texture = s.albedo_texture
			s.emission_energy_multiplier = 0.6
		m = s
	elif name.begins_with("grime_"):
		var s := StandardMaterial3D.new()
		s.albedo_texture = tex("grime_%s.png" % name.substr(6))
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		s.roughness = 1.0
		s.cull_mode = BaseMaterial3D.CULL_BACK
		s.render_priority = 1
		m = s
	elif name.begins_with("poster"):
		var s := StandardMaterial3D.new()
		s.albedo_texture = tex("signs/" + name + ".png")
		s.roughness = 0.75
		m = s
	elif name == "drain_pipe" or name == "antenna":
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(0.45, 0.46, 0.48) if name == "drain_pipe" else Color(0.7, 0.7, 0.72)
		s.metallic = 0.7; s.roughness = 0.4
		m = s
	elif name == "solar_panel":
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(0.06, 0.1, 0.22)
		s.metallic = 0.4; s.roughness = 0.12
		s.clearcoat_enabled = true; s.clearcoat = 1.0
		m = s
	elif name.contains("|"):
		m = char_mat(name)
	elif name.begins_with("car_paint_"):
		var s := StandardMaterial3D.new()
		var cols := {"red": Color(0.55, 0.03, 0.03), "white": Color(0.85, 0.85, 0.82), "blue": Color(0.06, 0.15, 0.4), "black": Color(0.02, 0.02, 0.025), "grey": Color(0.38, 0.4, 0.42), "yellow": Color(0.8, 0.58, 0.04)}
		s.albedo_color = cols.get(name.substr(10), Color(0.5, 0.5, 0.5))
		s.metallic = 0.55; s.roughness = 0.28
		s.clearcoat_enabled = true; s.clearcoat = 1.0; s.clearcoat_roughness = 0.05
		m = s
	elif DEFS.has(name):
		m = build(DEFS[name])
		_tone(name, m)
	else:
		m = null      # unknown name: keep the model's own (coloured) material instead of flat grey
	cache[name] = m
	return m

const TONE_DOWN := ["awning", "cont_", "car_", "flag_", "dumpster", "hull_", "ship_", "c_", "planks", "crate", "deck"]

func _tone(name: String, m: Material) -> void:
	## realistic, easy-on-the-eye palette: pull saturated paint colours toward a weathered, natural tone
	if not (m is StandardMaterial3D):
		return
	for p in TONE_DOWN:
		if name.begins_with(p):
			var c: Color = (m as StandardMaterial3D).albedo_color
			var l := c.get_luminance()
			(m as StandardMaterial3D).albedo_color = Color(lerp(c.r, l, 0.3), lerp(c.g, l, 0.3), lerp(c.b, l, 0.3), c.a) * 0.94
			return

const MACRO_SETS := ["concrete", "rawconc", "dryground", "dirt", "grass", "gravel2", "asphalt", "cobble", "paver", "plaster", "stonewall", "brick", "ashlar", "rooftiles"]

func build(d: Array) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	var tset: String = d[0]
	var uv: float = d[1]
	var tint: Color = d[2]
	var extra: Dictionary = d[5]
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if tset != "":
		if extra.get("jpg", false):
			s.albedo_texture = tex(tset + "_diffuse.jpg")
		else:
			s.albedo_texture = tex(tset + "_albedo.png")
			var n := tex(tset + "_normal.png")
			if n:
				s.normal_enabled = true
				s.normal_texture = n
				s.normal_scale = 1.0
			# parallax occlusion on rough masonry/cobbles (high+ quality)
			if tset in ["cobble", "stonewall", "paver"] and int(GS.settings.get("shadows", 2)) >= 2:
				var hm := tex(tset + "_height.png")
				if hm:
					s.heightmap_enabled = true
					s.heightmap_texture = hm
					s.heightmap_scale = {"cobble": 1.6, "stonewall": 1.0, "paver": 0.8}[tset]
					s.heightmap_deep_parallax = true
					s.heightmap_min_layers = 6
					s.heightmap_max_layers = 16
					s.heightmap_flip_texture = false
			var orm := tex(tset + "_orm.png")
			if orm:
				s.roughness_texture = orm
				s.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				s.metallic_texture = orm
				s.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		s.uv1_scale = Vector3(uv, uv, uv)
		# large-scale colour variation (world space) so big surfaces don't look tiled and flat
		if tset in MACRO_SETS and str(GS.settings.get("quality", "high")) != "low":
			var mt := tex("macro_noise.png")
			if mt:
				s.detail_enabled = true
				s.detail_albedo = mt
				s.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
				s.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
				s.uv2_triplanar = true
				s.uv2_world_triplanar = true
				s.uv2_scale = Vector3(0.045, 0.045, 0.045)
				tint = Color(tint.r * 1.1, tint.g * 1.1, tint.b * 1.1, tint.a)
	s.albedo_color = tint
	if extra.has("tex"):
		s.albedo_texture = tex(extra["tex"])
		s.uv1_scale = Vector3(uv, uv, uv)
	if extra.get("no_albedo", false):
		s.albedo_texture = null
	var r: float = d[3]
	var mtl: float = d[4]
	if r >= 0:
		s.roughness = r
		if s.roughness_texture and r < 0.5:
			s.roughness_texture = null
	else:
		s.roughness = 1.0
	if mtl >= 0:
		s.metallic = mtl
		if s.metallic_texture and mtl < 0.95 and mtl > 0.0:
			s.metallic_texture = null
		elif mtl == 0:
			s.metallic_texture = null
	else:
		s.metallic = 1.0
	if extra.has("spec"):
		s.metallic_specular = extra["spec"]
	if extra.has("emit"):
		s.emission_enabled = true
		s.emission = extra["emit"]
		s.emission_energy_multiplier = extra["emit_e"]
	if extra.get("unshaded", false):
		s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if extra.get("alpha", false) or tint.a < 1.0:
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not extra.get("cull", true):
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
	if extra.get("sss", false):
		s.backlight_enabled = true
		s.backlight = Color(0.25, 0.35, 0.1)
	return s

## Character materials encoded in the material name, e.g. "cloth|wool|3a2226|0.7"
func char_mat(name: String) -> Material:
	var p := name.split("|")
	var kind := p[0]
	var s := StandardMaterial3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"skin", "lips":
			var c := Color(p[1])
			if kind == "lips":
				c = c.darkened(0.25).lerp(Color(0.55, 0.25, 0.22), 0.45)
			s.albedo_color = c
			s.albedo_texture = tex("skin_detail_albedo.png")
			s.normal_enabled = true
			s.normal_texture = tex("skin_detail_normal.png")
			s.normal_scale = 0.6
			s.roughness_texture = tex("skin_detail_orm.png")
			s.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			s.roughness = 0.9 if kind == "skin" else 0.6
			s.uv1_scale = Vector3(14, 14, 14)
			s.subsurf_scatter_enabled = not GS.has_meta("lowfx")
			s.subsurf_scatter_strength = 0.35
			s.subsurf_scatter_skin_mode = true
			s.metallic_specular = 0.45
			s.rim_enabled = true
			s.rim = 0.15
			s.rim_tint = 0.6
		"cloth":
			var t := p[1]
			s.albedo_color = Color(p[2])
			s.albedo_texture = tex("cloth_" + t + "_albedo.png")
			s.normal_enabled = true
			s.normal_texture = tex("cloth_" + t + "_normal.png")
			s.normal_scale = 1.0
			s.roughness_texture = tex("cloth_" + t + "_orm.png")
			s.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			s.roughness = clamp(float(p[3]) + 0.25, 0.0, 1.0) if p.size() > 3 else 1.0
			var sc: float = {"wool": 10.0, "cotton": 12.0, "denim": 7.0, "leather": 5.0, "nylon": 8.0, "camo": 4.0, "bootleather": 6.0}.get(t, 8.0)
			s.uv1_scale = Vector3(sc, sc, sc)
			if t == "leather" or t == "bootleather":
				s.clearcoat_enabled = true
				s.clearcoat = 0.35
				s.clearcoat_roughness = 0.35
			if t == "wool" or t == "cotton":
				s.rim_enabled = true
				s.rim = 0.3
				s.rim_tint = 0.8
		"hair":
			s.albedo_color = Color(p[1]).lightened(0.05)
			s.albedo_texture = tex("hair_strands_albedo.png")
			s.normal_enabled = true
			s.normal_texture = tex("hair_strands_normal.png")
			s.roughness = 0.55
			s.uv1_scale = Vector3(6, 22, 6)
			s.anisotropy_enabled = true
			s.anisotropy = 0.6
			if p.size() > 2:
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				s.albedo_color.a = 0.85 if p[2] == "brow" else 0.8
		"eye":
			s.albedo_texture = tex("eye_brown.png")
			s.roughness = 0.05
			s.metallic_specular = 0.8
			s.clearcoat_enabled = true
			s.clearcoat = 1.0
			s.clearcoat_roughness = 0.0
		"gear":
			s.albedo_color = Color(p[1])
			s.roughness = float(p[2]) if p.size() > 2 else 0.5
			s.metallic = 0.6
		_:
			s.albedo_color = Color(0.6, 0.6, 0.6)
	return s

## Skin material for weapons ("gun_paint*" surfaces)
func skin_mat(skin: String) -> Material:
	var key := "skin:" + skin
	if cache.has(key):
		return cache[key]
	var s := StandardMaterial3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if GS.mod_skin_tex.has(skin):
		var tp: String = GS.mod_skin_tex[skin]
		if tp != "" and FileAccess.file_exists(tp):
			var im := Image.load_from_file(tp)
			if im:
				im.generate_mipmaps()
				s.albedo_texture = ImageTexture.create_from_image(im)
				s.uv1_scale = Vector3(0.6, 0.6, 0.6)
		s.albedo_color = GS.mod_skin_col.get(skin, Color.WHITE)
		s.roughness = 0.35; s.metallic = 0.25
		s.clearcoat_enabled = true; s.clearcoat = 0.6
	elif skin == "altin":
		s.albedo_color = Color(0.95, 0.72, 0.32)
		s.metallic = 1.0; s.roughness = 0.22
		s.normal_enabled = true; s.normal_texture = tex("gunmetal_normal.png")
	else:
		s.albedo_texture = tex("skin_" + skin + "_albedo.png")
		var orm := tex("skin_" + skin + "_orm.png")
		if orm:
			s.roughness_texture = orm
			s.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		s.roughness = 1.0
		s.metallic = 0.15
		s.uv1_scale = Vector3(0.6, 0.6, 0.6)
		s.clearcoat_enabled = true; s.clearcoat = 0.5; s.clearcoat_roughness = 0.2
		if skin in ["gece", "galaksi", "lav", "aurora", "siber"]:
			s.emission_enabled = true
			s.emission_texture = s.albedo_texture
			s.emission_energy_multiplier = {"galaksi": 0.35, "gece": 0.2, "lav": 1.2, "aurora": 0.6, "siber": 1.4}[skin]
		if skin in ["zumrut", "nazar", "kehribar", "mermer", "okyanus", "ayyildiz", "kan", "ejder"]:
			s.clearcoat = 1.0; s.clearcoat_roughness = 0.04
			s.metallic = 0.35 if skin in ["zumrut", "ejder", "kehribar"] else 0.1
		if skin == "karbon" or skin == "buz" or skin == "cini" or skin == "turkuaz":
			s.clearcoat = 1.0; s.clearcoat_roughness = 0.05
			s.metallic = 0.3 if skin != "turkuaz" else 0.5
	cache[key] = s
	return s

const EXT_SKIN_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_col : source_color = vec4(1.0);
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 ao_ch = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform bool has_ao = false;
uniform float normal_depth = 1.0;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_skin_tex = false;
uniform vec4 skin_tint : source_color = vec4(1.0);
uniform float tri_scale = 2.6;
uniform float detail_mix = 0.6;
uniform float skin_metal = 0.2;
uniform float skin_rough = 0.35;
uniform float coat = 0.6;
uniform float emission = 0.0;
uniform float sheen = 0.0;
uniform int anim = 0;       // 1 dragon lava pulse, 2 phoenix flames, 3 quantum data pulse, 4 lightning flicker
varying vec3 opos;
varying vec3 onrm;
void vertex() { opos = VERTEX; onrm = NORMAL; }
vec3 hue_rot(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}
float hsh(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
vec3 tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	return texture(skin_tex, p.zy).rgb * w.x + texture(skin_tex, p.xz).rgb * w.y + texture(skin_tex, p.xy).rgb * w.z;
}
void fragment() {
	vec3 base = has_albedo ? texture(base_albedo, UV).rgb * base_col.rgb : base_col.rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 pp = opos * tri_scale;
	if (anim == 2) { pp += vec3(0.0, TIME * 0.09, TIME * 0.03); }
	if (anim == 6) { pp += 0.05 * vec3(sin(TIME * 1.3 + pp.y * 9.0), cos(TIME * 1.1 + pp.z * 9.0), sin(TIME * 0.9 + pp.x * 9.0)); }
	if (anim == 7) { pp += vec3(TIME * 0.012, TIME * 0.006, 0.0); }
	if (anim == 8) { pp += vec3(0.0, TIME * 0.02, 0.0) + 0.012 * sin(TIME * 0.7 + pp.zxy * 6.0); }
	vec3 sk = (has_skin_tex ? tri(pp, normalize(onrm)) : vec3(1.0)) * skin_tint.rgb;
	if (anim == 5) { sk = hue_rot(sk, TIME * 0.8 + dot(opos, vec3(4.0, 7.0, 2.0))); }
	if (anim == 7) { sk = hue_rot(sk, sin(TIME * 0.35) * 0.9); }
	// keep the model's painted detail (edge wear, grime, engravings) under the skin
	float det = clamp(lum / 0.32, 0.3, 1.7);
	ALBEDO = sk * mix(1.0, det, detail_mix);
	if (has_normal) { NORMAL_MAP = texture(base_normal, UV).rgb; NORMAL_MAP_DEPTH = normal_depth; }
	float br = has_rough ? dot(texture(base_rough, UV), rough_ch) : skin_rough;
	ROUGHNESS = clamp(mix(skin_rough, br, 0.45), 0.04, 1.0);
	METALLIC = skin_metal;
	if (has_ao) { AO = dot(texture(base_ao, UV), ao_ch); AO_LIGHT_AFFECT = 0.4; }
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.12;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = sk * emission + sk * fres * sheen;
	if (anim > 0) {
		// animated skins: only the bright parts of the pattern (veins, feathers, traces, bolts) light up
		float l = max(sk.r, max(sk.g, sk.b));
		float mask = smoothstep(0.5, 0.92, l);
		float k = 0.0;
		if (anim == 1) { k = 1.1 + 0.9 * sin(TIME * 2.2 - dot(opos, vec3(3.0, 18.0, 7.0))); }
		else if (anim == 2) { k = 1.0 + 0.5 * sin(TIME * 7.0 + opos.y * 40.0) * sin(TIME * 3.1 + opos.z * 25.0); }
		else if (anim == 3) { float band = sin(dot(opos, vec3(9.0, 4.0, 16.0)) - TIME * 4.5) * 0.5 + 0.5; k = 0.45 + 3.2 * pow(band, 14.0); }
		else if (anim == 4) { float f = step(0.82, fract(sin(floor(TIME * 13.0) * 12.9898) * 43758.5453)); k = 0.5 + 3.5 * f + 0.25 * sin(TIME * 40.0); }
		else if (anim == 5) {
			// hologram: bright scanline sweeping along the gun + digital glitch flashes
			float sl = pow(sin(opos.z * 30.0 - TIME * 5.0) * 0.5 + 0.5, 10.0);
			float gl = step(0.9, hsh(vec3(floor(TIME * 9.0), floor(opos.z * 20.0), 0.0)));
			k = 0.8 + 2.6 * sl + 1.5 * gl + 0.15 * sin(opos.y * 400.0 + TIME * 20.0);
		}
		else if (anim == 6) { k = 1.2 + 1.4 * pow(sin(TIME * 5.0 + dot(opos, vec3(30.0, 12.0, 20.0))) * 0.5 + 0.5, 3.0); }
		else if (anim == 7) {
			// nebula: stars twinkle one by one
			float tw = sin(TIME * 3.0 + hsh(floor(opos * 90.0)) * 6.283) * 0.5 + 0.5;
			k = 0.7 + 2.4 * pow(tw, 6.0) * smoothstep(0.75, 0.95, l);
		}
		else if (anim == 8) { k = 1.4 + 1.1 * sin(TIME * 1.8 - opos.z * 22.0) + 0.3 * sin(TIME * 7.0 + opos.y * 50.0); mask = smoothstep(0.42, 0.85, sk.r); }
		EMISSION += sk * mask * k * 1.6;
		ROUGHNESS = min(ROUGHNESS, 0.3);
	}
}
"""

## v3.2 animated legendary skins -> shader animation mode
const ANIM_SKINS := {"ejderha": 1, "anka": 2, "kuantum": 3, "yildirim": 4, "hologram": 5, "plazma": 6, "nebula": 7, "magma": 8}

const _CH := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333, 0.333, 0.333, 0)]

## Skin for an imported (3DExport) weapon: the skin pattern is projected
## tri-planar in model space, the model's own normal/roughness/AO maps stay.
func ext_skin_mat(orig: BaseMaterial3D, skin: String) -> Material:
	var key := "extskin:%d:%s" % [orig.get_instance_id(), skin]
	if cache.has(key):
		return cache[key]
	var src := skin_mat(skin) as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = _shader("ext_skin", EXT_SKIN_SHADER)
	m.set_shader_parameter("base_col", orig.albedo_color)
	if orig.albedo_texture:
		m.set_shader_parameter("base_albedo", orig.albedo_texture); m.set_shader_parameter("has_albedo", true)
	if orig.normal_enabled and orig.normal_texture:
		m.set_shader_parameter("base_normal", orig.normal_texture); m.set_shader_parameter("has_normal", true)
		m.set_shader_parameter("normal_depth", orig.normal_scale)
	if orig.roughness_texture:
		m.set_shader_parameter("base_rough", orig.roughness_texture); m.set_shader_parameter("has_rough", true)
		m.set_shader_parameter("rough_ch", _CH[int(orig.roughness_texture_channel)])
	if orig.ao_enabled and orig.ao_texture:
		m.set_shader_parameter("base_ao", orig.ao_texture); m.set_shader_parameter("has_ao", true)
		m.set_shader_parameter("ao_ch", _CH[int(orig.ao_texture_channel)])
	if src:
		if src.albedo_texture:
			m.set_shader_parameter("skin_tex", src.albedo_texture); m.set_shader_parameter("has_skin_tex", true)
		m.set_shader_parameter("skin_tint", src.albedo_color)
		m.set_shader_parameter("skin_metal", src.metallic)
		m.set_shader_parameter("skin_rough", 0.4 if src.roughness_texture else src.roughness)
		m.set_shader_parameter("coat", src.clearcoat if src.clearcoat_enabled else 0.0)
		m.set_shader_parameter("emission", src.emission_energy_multiplier * 0.6 if src.emission_enabled else 0.0)
		# a solid metal finish (gold) should not darken the model's detail as much
		m.set_shader_parameter("detail_mix", 0.35 if src.albedo_texture == null else 0.6)
		m.set_shader_parameter("anim", ANIM_SKINS.get(skin, 0))
		m.set_shader_parameter("sheen", 0.25 if skin in ["galaksi", "buz", "turkuaz", "altin", "zumrut", "aurora", "nazar", "kehribar"] else 0.0)
	cache[key] = m
	return m

## Replace materials in an imported scene by name. skin: weapon skin id or ""
func _tune_rb(_m: Material) -> void:
	# Rocketbox materials are used exactly as imported (alpha/culling come from the glTF).
	# NOTE: mutating these imported materials at runtime deadlocked the renderer on some drivers.
	pass

func apply(node: Node, skin: String = "") -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var sm := mesh.surface_get_material(i)
				var n := sm.resource_name if sm else ""
				if n == "":
					continue
				n = n.split(".")[0]
				if n.begins_with("rb_"):
					_tune_rb(sm)
					continue
				if ANIM_SKINS.has(skin) and n.begins_with("gun_paint") and sm is BaseMaterial3D:
					mi.set_surface_override_material(i, ext_skin_mat(sm as BaseMaterial3D, skin))
				elif skin != "" and skin != "std" and n.begins_with("gun_paint_ext") and sm is BaseMaterial3D:
					mi.set_surface_override_material(i, ext_skin_mat(sm as BaseMaterial3D, skin))
				elif skin != "" and skin != "std" and n.begins_with("gun_paint"):
					mi.set_surface_override_material(i, skin_mat(skin))
				elif _is_flat_gun(n) and sm is BaseMaterial3D:
					mi.set_surface_override_material(i, _flat_pbr(n, sm as BaseMaterial3D))
				elif EXT_FALLBACK.has(n):
					mi.set_surface_override_material(i, _ext_fallback(n, sm))
				else:
					mi.set_surface_override_material(i, get_mat(n))
	for c in node.get_children():
		apply(c, skin)

## flat-colour CC0 guns (fps-asset-kit): keep their colour layout, add real gunmetal/polymer surface detail
const FLAT_GUNS: Array[String] = ["ump45"]   # v3.8: scar / mp5 now use real textured models
func _is_flat_gun(n: String) -> bool:
	for g in FLAT_GUNS:
		if n.begins_with("gun_paint_ext_%s_" % g) or n.begins_with("ext_%s_" % g):
			return true
	return false

func _flat_pbr(n: String, orig: BaseMaterial3D) -> Material:
	var key := "flat:" + n
	if cache.has(key):
		return cache[key]
	var c := orig.albedo_color
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	var lum := (c.r + c.g + c.b) / 3.0
	if sat > 0.08 and lum < 0.5:
		# tan / brown furniture: textured polymer
		m.albedo_texture = tex("polymer_albedo.png")
		m.albedo_color = Color(c.r * 1.9, c.g * 1.9, c.b * 1.9)
		m.normal_enabled = true; m.normal_texture = tex("polymer_normal.png"); m.normal_scale = 0.8
		m.metallic = 0.0; m.roughness = 0.62
		m.uv1_scale = Vector3(5, 5, 5)
	elif lum > 0.5:
		m.albedo_color = c
		m.metallic = 0.7 if sat > 0.2 else 0.2; m.roughness = 0.35
	else:
		# black/grey receiver parts: worn gunmetal with micro detail and edge sheen
		m.albedo_texture = tex("gunmetal_albedo.png")
		var k := 0.35 + lum * 5.0
		m.albedo_color = Color(0.45 * k, 0.46 * k, 0.49 * k)
		m.normal_enabled = true; m.normal_texture = tex("gunmetal_normal.png"); m.normal_scale = 0.55
		m.roughness_texture = tex("gunmetal_orm.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 0.75 if lum < 0.02 else 0.35
		m.roughness = 1.0
		m.uv1_scale = Vector3(6, 6, 6)
	m.rim_enabled = true; m.rim = 0.15; m.rim_tint = 0.6
	cache[key] = m
	return m

## imported models whose archive came without textures: give them real wood / steel detail
const EXT_FALLBACK := {"gun_paint_ext_r870_2": "wood", "gun_paint_ext_r870_1": "metal", "gun_paint_ext_m4a1_UltimateLowPolyGuns": "metal",
	"gun_paint_ext_akm_wpn_akm": "metal", "ext_akm_wood": "wood", "gun_paint_ext_kartal_Material": "metal", "ext_kartal_wood": "wood",
	"gun_paint_ext_m4k_base_low": "metal", "gun_paint_ext_m4k_front_low": "metal", "ext_balta_1": "wood", "ext_balta_0": "metal"}
func _ext_fallback(n: String, orig: Material) -> Material:
	var key := "extfb:" + n
	if cache.has(key):
		return cache[key]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	if EXT_FALLBACK[n] == "wood":
		m.albedo_texture = tex("gunwood_albedo.png")
		m.albedo_color = Color(0.62, 0.42, 0.3)
		m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		m.roughness = 0.42
		m.clearcoat_enabled = true; m.clearcoat = 0.35; m.clearcoat_roughness = 0.3
	else:
		m.albedo_texture = tex("gunmetal_albedo.png")
		m.albedo_color = Color(0.55, 0.56, 0.6)
		m.normal_enabled = true; m.normal_texture = tex("gunmetal_normal.png"); m.normal_scale = 0.6
		m.roughness_texture = tex("gunmetal_orm.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 0.85; m.roughness = 1.0
		m.uv1_scale = Vector3(6.0, 6.0, 6.0)
	cache[key] = m
	return m

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep : source_color = vec3(0.03, 0.2, 0.32);
uniform vec3 shallow : source_color = vec3(0.08, 0.42, 0.5);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz * 0.03;
	vec3 n1 = texture(normal_tex, uv + vec2(TIME * 0.012, TIME * 0.008)).xyz;
	vec3 n2 = texture(normal_tex, uv * 2.3 - vec2(TIME * 0.01, -TIME * 0.015)).xyz;
	vec3 n = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, fres * 0.6);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
varying float h;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.7 + w.x * 0.6 + w.z * 0.4) * 0.06 + sin(TIME * 3.1 + w.y * 2.0) * 0.025;
	VERTEX += vec3(s, s * 0.4, s * 0.7);
	h = w.y;
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.45) discard;
	ALBEDO = c.rgb * tint * (0.85 + 0.25 * fract(sin(dot(floor(UV * 3.0), vec2(12.9, 78.2))) * 43758.5));
	ROUGHNESS = 0.75;
	SSS_STRENGTH = 0.4;
	BACKLIGHT = vec3(0.35, 0.5, 0.15);
}
"""

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_tex = true;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amt = clamp(UV.x, 0.0, 1.0);
	VERTEX.y += sin(TIME * 4.0 - UV.x * 8.0 + w.x) * 0.08 * amt;
	VERTEX.z += sin(TIME * 2.6 - UV.x * 5.0) * 0.03 * amt;
}
void fragment() {
	vec4 c = textureLod(tex, UV, 0.0);
	vec3 col = c.a > 0.0 ? c.rgb : tint.rgb;
	ALBEDO = col * tint.rgb;
	ROUGHNESS = 0.8;
	BACKLIGHT = col * 0.4;
}
"""
