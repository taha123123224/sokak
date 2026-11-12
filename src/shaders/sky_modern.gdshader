// v3.7 modern sky (day / golden / sunset / overcast): saturated zenith blue fading to a bright hazy horizon,
// a crisp sun with a soft Mie halo, and two layers of lit, drifting clouds (bright sun-side tops, blue-grey
// undersides). In the reflection cubemap pass soft "studio" light panels are added so metal on the weapons
// and on the map catches clean, modern highlights.
shader_type sky;

uniform vec3 zen : source_color = vec3(0.12, 0.38, 0.86);
uniform vec3 hor : source_color = vec3(0.66, 0.82, 0.96);
uniform vec3 gnd : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.8);
uniform float sun_size = 0.9994;
uniform float cover = 0.45;          // 0 = clear, 1 = overcast
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.62, 0.74);
uniform float studio = 0.6;          // strength of the reflection-only light panels
uniform float energy = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { s += a * noise(p); p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + 3.1; a *= 0.5; }
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 L = normalize(LIGHT0_DIRECTION);
	float y = d.y;
	float mu = dot(d, L);
	vec3 col;
	// --- atmosphere
	float h = max(y, 0.0);
	float t = pow(1.0 - h, 5.0);
	col = mix(zen, hor, t);
	// warm forward scattering around the sun, stronger near the horizon when the sun is low
	float low = 1.0 - smoothstep(0.0, 0.45, L.y);
	col += sun_col * (pow(max(mu, 0.0), 8.0) * 0.18 + pow(max(mu, 0.0), 64.0) * 0.35) * (0.5 + low);
	col = mix(col, col * vec3(1.05, 0.9, 0.78) + sun_col * 0.08, low * t * 0.6 * (0.6 + 0.4 * max(mu, 0.0)));
	// --- clouds (above the horizon only)
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.1);
		vec2 wind = vec2(TIME * 0.006, TIME * 0.0025);
		float base = fbm(uv * 0.55 + wind);
		float det = fbm(uv * 2.2 + wind * 2.5);
		float c = smoothstep(1.0 - cover - 0.1, 1.0 - cover + 0.35, base * 0.75 + det * 0.35);
		// lighting: sample toward the sun for self-shadowing
		float base2 = fbm((uv + L.xz * 0.35) * 0.55 + wind);
		float shade = clamp((base - base2) * 3.0 + 0.55, 0.0, 1.0);
		vec3 cc = mix(cloud_dark, cloud_lit, shade);
		cc += sun_col * pow(max(mu, 0.0), 6.0) * 0.6 * (1.0 - c * 0.5);      // silver lining toward the sun
		cc = mix(cc, cc * vec3(1.08, 0.86, 0.72), low * 0.7);                 // golden-hour tint
		float fade = smoothstep(0.0, 0.12, y);
		col = mix(col, cc, c * fade * 0.92);
		// high thin cirrus streaks
		float ci = smoothstep(0.55, 0.9, fbm(vec2(uv.x * 0.25, uv.y * 1.4) + wind * 0.5)) * (1.0 - c);
		col = mix(col, cloud_lit * 0.95 + sun_col * 0.05, ci * 0.35 * fade);
	}
	// --- below the horizon: soft ground bounce
	if (y < 0.0) {
		col = mix(hor * 0.85, gnd, smoothstep(0.0, -0.3, y));
	}
	// --- sun disc
	col += sun_col * smoothstep(sun_size, sun_size + 0.0003, mu) * 12.0;
	// --- studio panels: only in the reflection cubemap, gives clean metal highlights
	if (AT_CUBEMAP_PASS && studio > 0.0) {
		float az = atan(d.x, d.z);
		float p1 = smoothstep(0.3, 0.26, abs(az - 0.9)) * smoothstep(0.12, 0.2, y) * smoothstep(0.62, 0.52, y);
		float p2 = smoothstep(0.22, 0.18, abs(az + 2.2)) * smoothstep(0.05, 0.12, y) * smoothstep(0.42, 0.34, y);
		float strip = smoothstep(0.03, 0.0, abs(y - 0.02)) * 0.6;
		col += vec3(1.0, 0.98, 0.95) * (p1 * 2.2 + p2 * 1.4 + strip) * studio;
	}
	COLOR = col * energy;
}
