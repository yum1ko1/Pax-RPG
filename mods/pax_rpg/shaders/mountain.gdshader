// Горы за степью (landscape.gd → _mountains): хребты из шума, цвет — по высоте и уклону: травянистые подножия,
// скалы слоями (страты), снег на вершинах и пологих полках, на крутом снег не держится. Деталь скалы — нормали
// трипланарно (без UV-растяжки на склонах). Тени облаков ползут по ветру. Даль синеет — это туман сцены.
shader_type spatial;

global uniform vec4 pax_rpg_wind;
global uniform float pax_rpg_time;

uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_a : source_color = vec3(0.36, 0.32, 0.34);
uniform vec3 rock_b : source_color = vec3(0.56, 0.47, 0.42);
uniform vec3 grass_col : source_color = vec3(0.46, 0.47, 0.27);
uniform vec3 snow_col : source_color = vec3(0.93, 0.94, 1.0);
uniform float snow_line = 210.0;     // м — выше снег
uniform float detail_scale = 0.03;   // повторов детали на метр
uniform float clouds = 0.35;         // сила теней облаков

varying vec3 wp;
varying vec3 wn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += noise(p) * a; p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);                     // 0 — ровно, 1 — стена
	float n = fbm(wp.xz * 0.004);
	float strata = sin(wp.y * 0.09 + n * 7.0 + fbm(wp.xz * 0.02) * 3.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_a, rock_b, strata * 0.65 + n * 0.35);
	rock *= 0.8 + 0.4 * fbm(wp.xz * 0.05 + wp.y * 0.03);
	float grassy = (1.0 - smoothstep(0.18, 0.42, slope)) * (1.0 - smoothstep(snow_line * 0.3, snow_line * 0.6, wp.y + n * 50.0));
	float snow = smoothstep(snow_line - 25.0, snow_line + 25.0, wp.y + (n - 0.5) * 90.0) * (1.0 - smoothstep(0.5, 0.78, slope));
	snow = max(snow, smoothstep(snow_line + 60.0, snow_line + 120.0, wp.y) * (1.0 - smoothstep(0.7, 0.92, slope)));
	vec3 c = mix(rock, grass_col * (0.8 + 0.4 * n), grassy);
	c = mix(c, snow_col * (0.9 + 0.1 * n), snow);
	// тени облаков: пятна шума, плывут по ветру
	vec2 wd = normalize(pax_rpg_wind.xy + vec2(1e-4));
	float cl = smoothstep(0.48, 0.62, fbm(wp.xz * 0.0016 - wd * pax_rpg_time * 0.012));
	c *= 1.0 - cl * clouds;
	// трипланарная деталь нормалей (whiteout)
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec3 tx = texture(detail_n, wp.zy * detail_scale).xyz * 2.0 - 1.0;
	vec3 ty = texture(detail_n, wp.xz * detail_scale).xyz * 2.0 - 1.0;
	vec3 tz = texture(detail_n, wp.xy * detail_scale).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy + wn.zy, abs(tx.z) * wn.x);
	ty = vec3(ty.xy + wn.xz, abs(ty.z) * wn.y);
	tz = vec3(tz.xy + wn.xy, abs(tz.z) * wn.z);
	vec3 nw = normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
	nw = normalize(mix(wn, nw, 0.7 * (1.0 - snow * 0.6)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.55, snow);
	SPECULAR = mix(0.25, 0.5, snow);
}
