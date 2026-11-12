// v3.6.1 Kurt Adam sky: cinematic blue hour over Ay Vadisi. Deep blue zenith, a narrow amber band on the
// horizon, sunset-lit high clouds, a large rising moon with a soft halo, faint stars and a subtle aurora.
shader_type sky;
uniform vec3 moon_dir = vec3(-0.35, 0.3, -0.88);
uniform vec3 sun_dir = vec3(0.55, 0.05, 0.83);
uniform vec3 zen : source_color = vec3(0.04, 0.07, 0.17);
uniform vec3 mid : source_color = vec3(0.16, 0.24, 0.42);
uniform vec3 hor : source_color = vec3(0.92, 0.56, 0.33);
uniform vec3 grnd : source_color = vec3(0.07, 0.08, 0.1);
float h3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1, 0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0, 1), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1, 1), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + 11.7; a *= 0.5; } return s; }
void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = normalize(sun_dir);
	float sunside = pow(max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z))), 0.0), 2.0);
	vec3 col;
	if (y < 0.0) {
		col = mix(hor * 0.35, grnd, smoothstep(0.0, -0.2, y));
	} else {
		// horizon glow strongest toward the set sun, cool blue elsewhere
		vec3 h = mix(vec3(0.42, 0.42, 0.52), hor, 0.35 + 0.65 * sunside);
		col = mix(h, mid, smoothstep(0.0, 0.16 + 0.1 * sunside, y));
		col = mix(col, zen, smoothstep(0.2, 0.8, y));
		// high clouds, lit warm from below on the sun side
		vec2 cp = d.xz / (y + 0.12) * 1.4 + vec2(TIME * 0.004, 0.0);
		float cl = smoothstep(0.52, 0.85, fbm(cp * 0.9));
		vec3 ccol = mix(vec3(0.2, 0.24, 0.36), vec3(1.0, 0.62, 0.42), sunside * smoothstep(0.45, 0.05, y));
		col = mix(col, ccol, cl * 0.75 * smoothstep(0.0, 0.08, y));
		// stars, only higher up and between clouds
		vec3 sp = d * 260.0;
		float st = step(0.9975, h3(floor(sp)));
		float tw = 0.65 + 0.35 * sin(TIME * 2.5 + h3(floor(sp) + 7.0) * 30.0);
		col += vec3(0.9, 0.95, 1.0) * st * tw * smoothstep(0.3, 0.65, y) * (1.0 - cl) * 0.9;
		// faint aurora
		vec2 ap = d.xz / max(y, 0.1);
		float w = sin(ap.x * 0.8 + TIME * 0.08 + vn(ap * 0.5) * 3.0) * 0.5 + ap.y * 0.15 - 0.3;
		float band = exp(-w * w * 20.0) * (0.5 + 0.5 * vn(ap * vec2(3.0, 0.4) + TIME * 0.15));
		col += vec3(0.2, 0.85, 0.6) * band * smoothstep(0.25, 0.5, y) * smoothstep(0.95, 0.6, y) * 0.16 * (1.0 - cl);
	}
	// moon
	float md = dot(d, normalize(moon_dir));
	float disc = smoothstep(0.99955, 0.99975, md);
	vec2 mp = (d - normalize(moon_dir)).xy * 90.0;
	col = mix(col, vec3(0.96, 0.94, 0.88) * (0.82 + 0.18 * fbm(mp * 3.0)), disc);
	col += vec3(0.6, 0.68, 0.85) * pow(max(md, 0.0), 300.0) * 0.5 + vec3(0.4, 0.48, 0.65) * pow(max(md, 0.0), 18.0) * 0.08;
	COLOR = col;
}
