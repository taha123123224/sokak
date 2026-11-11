shader_type canvas_item;
// living key art: slow push-in, drifting volumetric smoke, flickering lanterns, pulsing sun, heat shimmer
uniform sampler2D art : filter_linear_mipmap;
uniform float t = 0.0;
uniform vec2 lantern0 = vec2(0.6, 0.38);
uniform vec2 lantern1 = vec2(0.543, 0.565);
uniform vec2 lantern2 = vec2(0.588, 0.608);
uniform vec2 sun = vec2(0.689, 0.29);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	float z = 1.06 - 0.04 * smoothstep(0.0, 40.0, t);
	uv = (uv - vec2(0.62, 0.5)) / z + vec2(0.62, 0.5);
	uv.x += sin(t * 0.07) * 0.004;
	// heat shimmer near the glowing street
	float sh = (noise(vec2(uv.x * 40.0, uv.y * 30.0 - t * 1.5)) - 0.5) * 0.0018 * smoothstep(0.55, 0.95, uv.y);
	vec3 col = texture(art, uv + vec2(sh, 0.0)).rgb;
	// smoke: two layers drifting right, thicker low and left
	float s1 = fbm(uv * vec2(3.0, 5.0) + vec2(-t * 0.035, t * 0.01));
	float s2 = fbm(uv * vec2(6.0, 9.0) + vec2(-t * 0.06, -t * 0.015) + 7.3);
	float smoke = smoothstep(0.42, 0.95, s1 * 0.65 + s2 * 0.45) * (0.35 + 0.65 * smoothstep(0.35, 1.0, uv.y)) * (1.0 - 0.6 * smoothstep(0.55, 0.95, uv.x));
	col = mix(col, vec3(0.55, 0.42, 0.33) * (0.6 + 0.6 * col.r), smoke * 0.42);
	// lanterns flicker
	float fl = 0.85 + 0.15 * noise(vec2(t * 6.0, 1.0)) + 0.08 * sin(t * 23.0);
	vec2 asp = vec2(1.78, 1.0);
	col += vec3(1.0, 0.55, 0.18) * 0.22 * fl * exp(-length((uv - lantern0) * asp) * 26.0);
	col += vec3(1.0, 0.55, 0.18) * 0.14 * fl * exp(-length((uv - lantern1) * asp) * 34.0);
	col += vec3(1.0, 0.55, 0.18) * 0.12 * fl * exp(-length((uv - lantern2) * asp) * 34.0);
	// sun bloom + god rays
	float sd = length((uv - sun) * asp);
	col += vec3(1.0, 0.62, 0.3) * (0.10 + 0.03 * sin(t * 0.8)) * exp(-sd * 7.0);
	vec2 dir = uv - sun;
	float ang = atan(dir.y, dir.x);
	float rays = pow(max(0.0, noise(vec2(ang * 9.0, t * 0.15))), 3.0) * exp(-sd * 3.0) * 0.18;
	col += vec3(1.0, 0.7, 0.4) * rays;
	COLOR = vec4(col, 1.0);
}
