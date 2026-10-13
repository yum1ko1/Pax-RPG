// Степь за частоколом (landscape.gd → _terrain): текстура земли в двух масштабах (второй повёрнут — без видимого
// повтора), общий цвет — вершинный (трава / охра / сухое по шуму), уклоны — в камень. По траве бегут светлые волны
// ветра (pax_rpg_wind), по земле ползут тени облаков — даль живая, а не нарисованная.
shader_type spatial;

global uniform vec4 pax_rpg_wind;
global uniform float pax_rpg_time;

uniform sampler2D g_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock : source_color = vec3(0.45, 0.4, 0.38);
uniform float tile = 8.0;            // м на повтор текстуры
uniform float clouds = 0.32;

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
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wp.xz;
	vec2 u1 = p / tile;
	vec2 u2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (tile * 4.3) + vec2(0.31, 0.77);
	float mixk = smoothstep(0.3, 0.7, noise(p * 0.02));
	vec3 tex = mix(texture(g_col, u1).rgb, texture(g_col, u2).rgb, 0.35 + 0.3 * mixk);
	float lum = dot(tex, vec3(0.333));
	vec3 c = COLOR.rgb * (0.55 + 0.9 * lum);                       // цвет местности + рисунок земли
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	c = mix(c, rock * (0.7 + 0.6 * lum), smoothstep(0.35, 0.6, slope + (fbm(p * 0.03) - 0.5) * 0.3));
	c *= 0.85 + 0.3 * fbm(p * 0.008);                              // крупные пятна
	vec2 wd = normalize(pax_rpg_wind.xy + vec2(1e-4));
	float gust = sin(pax_rpg_time * 0.9 - dot(p, wd) * 0.035 + fbm(p * 0.01) * 5.0) * 0.5 + 0.5;
	c *= 1.0 + 0.07 * gust * (1.0 - slope);                        // волны ветра по траве
	float cl = smoothstep(0.48, 0.62, fbm(p * 0.0016 - wd * pax_rpg_time * 0.012));
	c *= 1.0 - cl * clouds;
	ALBEDO = c;
	NORMAL_MAP = mix(texture(g_nrm, u1).rgb, vec3(0.5, 0.5, 1.0), 0.35);
	ROUGHNESS = 0.93;
	SPECULAR = 0.25;
}
