// Тело павшего врага (src/location/body_fx.gd): материал модели (альбедо, шероховатость) + два эффекта.
//   dissolve 0..1 — растворение в ману: тело выгорает пятнами шума, по краю выгорания — розово-сиреневое свечение;
//   clip_on, clip — разрез иаем: остаётся часть по одну сторону плоскости clip (xyz — нормаль, w — сдвиг, в осях
//     сетки); внутренность через срез светится маной (задние грани — свечение вместо тела).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float roughness = 0.85;
uniform bool clip_on = false;
uniform vec4 clip = vec4(0.0, 1.0, 0.0, 0.0);
uniform float dissolve = 0.0;
uniform vec3 mana : source_color = vec3(0.85, 0.42, 1.0);

varying vec3 lp;
varying vec3 wp;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_on && dot(lp, clip.xyz) - clip.w < 0.0) {
		discard;
	}
	float n = noise(wp * 6.0) * 0.6 + noise(wp * 17.0) * 0.4;
	if (n < dissolve * 1.05) {
		discard;
	}
	vec4 a = texture(albedo_tex, UV) * albedo_col;
	float edge = 1.0 - smoothstep(0.0, 0.09, n - dissolve * 1.05);
	ALBEDO = a.rgb;
	ROUGHNESS = roughness;
	EMISSION = mana * edge * 3.0 * step(0.001, dissolve);
	if (!FRONT_FACING) {                                  // сквозь срез — не изнанка тела, а мана
		ALBEDO = mana * 0.25;
		EMISSION = mana * 2.2;
	}
}
