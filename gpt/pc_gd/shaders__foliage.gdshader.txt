// Деревья, кусты, пучки травы из моделей (city.gd → _place, список FOLIAGE): материал модели (альбедо, шероховатость)
// + ветер. Модель качается тем сильнее, чем выше точка над её низом (h² — ствол у земли стоит), по ветру
// (pax_rpg_wind, ведёт wind.gd) с порывами; листва дрожит мелко; на просвет против солнца — светится (BACKLIGHT).
// y_min / y_max — низ и верх сетки в её осях (по ним высота точки 0..1); amp — наклон верха в метрах.
shader_type spatial;
render_mode cull_disabled;           // листья-карточки (дубы, трава из наборов) видны с обеих сторон

global uniform vec4 pax_rpg_wind;
global uniform float pax_rpg_time;
global uniform vec4 pax_rpg_player;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D rough_tex : filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform bool use_rough_tex = false;
uniform float y_min = 0.0;
uniform float y_max = 1.0;
uniform float amp = 0.15;
uniform float backlight = 0.45;
uniform float canopy = 0.0;
uniform bool use_alpha = false;
uniform float push = 0.0;
global uniform vec4 pax_rpg_weather;
varying vec3 tint;                   // у каждой копии свой оттенок кроны/травы (по её месту), мокрое — темнее            // трава и цветы: герой раздвигает их вокруг себя (м)      // карточки листьев и травы: прозрачное — вырезается по альфе текстуры          // 1 — дерево: ствол стоит, качаются только крона и листва (верх сетки)

void vertex() {
	float h0 = clamp((VERTEX.y - y_min) / max(y_max - y_min, 0.001), 0.0, 1.0);
	float h = mix(h0, smoothstep(0.42, 1.0, h0), canopy);    // у дерева гнётся только верх
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 org = MODEL_MATRIX[3].xyz;                               // у всех точек одной копии — общая фаза качания
	float hv = fract(sin(dot(org.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float hv2 = fract(sin(dot(org.xz, vec2(39.346, 11.135))) * 24634.6345);
	tint = mix(vec3(0.82, 0.9, 0.7), vec3(1.12, 1.05, 0.82), hv) * mix(0.88, 1.1, hv2);   // от свежей зелени к желтизне
	tint *= mix(1.0, 0.75, pax_rpg_weather.x);
	vec2 wd = normalize(pax_rpg_wind.xy + vec2(1e-4));
	float s = pax_rpg_wind.z;
	float g = pax_rpg_wind.w;
	float t = pax_rpg_time;
	float sway = sin(t * 1.1 + org.x * 0.21 + org.z * 0.17) * 0.6 + sin(t * 2.3 + org.x * 0.5) * 0.25;
	float lean = (0.25 + 0.45 * s + 1.1 * g) + sway * (0.35 + 0.5 * s);
	float leaf = sin(t * 8.0 + wp.x * 4.1 + wp.y * 3.3 + wp.z * 2.7) * (0.025 + 0.02 * canopy) * (0.4 + s + g) * h;   // дрожь листвы
	vec3 off = vec3(wd.x, 0.0, wd.y) * lean * amp * h * h + vec3(leaf, leaf * 0.5, -leaf);
	off.y -= dot(off.xz, off.xz) * 0.25 * h;                      // клонится — чуть ниже, не тянется
	if (push > 0.0) {                                             // раздвигается вокруг героя, как сплошная трава
		vec2 away = wp.xz - pax_rpg_player.xz;
		float pd = length(away);
		float k = (1.0 - smoothstep(0.3, 1.1, pd)) * step(abs(wp.y - pax_rpg_player.y), 1.6);
		off.xz += normalize(away + vec2(1e-4)) * k * push * h;
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = a.rgb * tint;
#ifndef FOLIAGE_OPAQUE
	// FOLIAGE_OPAQUE (city.gd → непрозрачные поверхности: кора, кусты без карточек) — без альфа-среза: там ALPHA = 1
	// и так ничего не срезала, а с ALPHA_SCISSOR_THRESHOLD глубина и тени шли через фрагментный шейдер с discard
	ALPHA = use_alpha ? a.a : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ROUGHNESS = use_rough_tex ? texture(rough_tex, UV).g * roughness : roughness;
	SPECULAR = 0.35;
	BACKLIGHT = a.rgb * backlight;
}
