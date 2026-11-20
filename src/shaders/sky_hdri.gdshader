shader_type sky;
// v4.18.5 photographic sky: Poly Haven "pure sky" HDRI (CC0), rotated so its real sun lines up with the map's sun light.
uniform sampler2D pano : filter_linear_mipmap, repeat_enable;
uniform float yaw = 0.0;
uniform float energy = 1.0;
uniform vec3 ground_col : source_color = vec3(0.32, 0.31, 0.29);
uniform float sun_boost = 1.0;

void sky() {
	vec3 d = EYEDIR;
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 r = vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
	float u = atan(r.x, -r.z) / (2.0 * PI) + 0.5;
	float v = acos(clamp(r.y, -1.0, 1.0)) / PI;
	vec3 col = textureLod(pano, vec2(u, v), 0.0).rgb * energy;
	// below the horizon the pure-sky photo has no ground: fade to a neutral ground tone (reflections, low views)
	float g = smoothstep(0.02, -0.12, d.y);
	col = mix(col, ground_col * energy * 0.6, g);
	// keep the photographed sun disc bright enough to bloom, without blowing out the reflection pass
	if (AT_CUBEMAP_PASS) {
		col = min(col, vec3(40.0));
	} else {
		col *= mix(1.0, sun_boost, smoothstep(30.0, 200.0, dot(col, vec3(0.333))));
	}
	COLOR = col;
}
