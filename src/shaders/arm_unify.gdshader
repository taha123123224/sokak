// v3.4.1: first-person rig arms (CC-BY animation packs) recoloured to the main character's arms:
// sleeves get the soldier's camo cloth, bare skin becomes the dark tactical glove, gloves stay
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float sleeve_v = -1.0;     // >= 0: texture rows below this V are the sleeve (packs with a dark sleeve)
uniform float camo_scale = 5.0;
uniform vec3 glove : source_color = vec3(0.07, 0.07, 0.075);
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * base_color.rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float skin = smoothstep(0.06, 0.16, c.r - c.b) * smoothstep(0.18, 0.35, c.r);
	float sleeve;
	if (sleeve_v >= 0.0) {
		sleeve = smoothstep(sleeve_v - 0.01, sleeve_v + 0.01, UV.y);
	} else {
		sleeve = (1.0 - skin) * smoothstep(0.1, 0.18, lum);
	}
	vec3 camo = texture(camo_tex, UV * camo_scale).rgb * 0.9;
	float shade = clamp(lum / max(dot(texture(albedo_tex, UV, 4.0).rgb, vec3(0.3, 0.59, 0.11)), 0.02), 0.5, 1.4);
	vec3 col = mix(c, glove * (0.6 + lum * 2.0), skin * (1.0 - sleeve));
	col = mix(col, camo * shade, sleeve);
	ALBEDO = col;
	ROUGHNESS = mix(0.7, 0.9, sleeve);
	SPECULAR = 0.35;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
