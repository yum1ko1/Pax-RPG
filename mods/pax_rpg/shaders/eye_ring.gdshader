// Око Раскола у глобуса (planet/heavens3d.gd): квадрат в плоскости кольца, UV — от -extent до extent радиусов.
// Тонкий раскалённый добела обод в трещинах, розовый ореол, неустойчивые вихри маны; кольцо легко пульсирует.
// То же, что Око в небе локаций (sky.gdshader: eye_rim, mana_swirl).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float extent = 2.2;
uniform float breath = 1.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
float sq(float x) {
	return x * x;
}

// Обод Ока: x — расстояние от центра в радиусах кольца, a — угол. Тонкий раскалённый добела обод в трещинах,
// в розовом ореоле, легко пульсирует.
vec3 eye_rim(float x, float a, float time) {
	float b = 1.0 + breath * (0.1 * sin(time * 1.4) + 0.05 * sin(time * 3.3 + 1.0));
	float crack = 0.75 + 0.25 * noise(vec2(a * 38.2, 1.0)) + 0.15 * noise(vec2(a * 162.3, 7.0));
	float core = exp(-sq((x - 1.0) / 0.03)) * crack;
	float glow = exp(-sq((x - 1.0) / 0.14)) * 0.35 + exp(-sq((x - 1.0) / 0.5)) * 0.08;
	return (vec3(1.0, 0.97, 0.93) * core * 1.6 + vec3(1.0, 0.55, 0.78) * glow) * b;
}

// Неустойчивые вихри розовой маны вокруг Ока: спиральные рукава крутятся, рвутся, вспыхивают и гаснут.
// q — точка в плоскости Ока, в его радиусах.
vec3 mana_swirl(vec2 q, float time) {
	float r = length(q), a = atan(q.y, q.x);
	float mask = exp(-sq((r - 1.0) / 0.42)) + 0.35 * exp(-r * r / 0.2);
	if (mask < 0.01) {
		return vec3(0.0);
	}
	vec2 ca = vec2(cos(a), sin(a));
	float s = a + r * 2.4 - time * 0.22;
	float w = fbm(ca * 1.7 * r + vec2(time * 0.11, -time * 0.07));
	float f = fbm(q * 2.6 + w * 2.2 + vec2(time * 0.17, -time * 0.12));
	float arms = pow(0.5 + 0.5 * sin(3.0 * s + f * 7.0), 2.5);
	float burst = smoothstep(0.45, 0.95, noise(ca * 1.3 + vec2(time * 0.45, 3.0)));
	float flick = 0.7 + 0.3 * noise(vec2(time * 2.3, r * 3.0));
	float v = mask * smoothstep(0.35, 0.8, f) * arms * (0.35 + 1.1 * burst) * flick;
	return mix(vec3(0.95, 0.25, 0.65), vec3(1.0, 0.72, 0.92), smoothstep(0.6, 1.0, f)) * v * 0.9;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0 * extent;
	float x = length(q);
	ALBEDO = eye_rim(x, atan(q.y, q.x), TIME) + mana_swirl(q, TIME);
}
