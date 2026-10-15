// Земля города: глина с травой, по маске дорог (R) — булыжник в грязи, по маске троп (G) — утоптанная земля.
// UV — мировые XZ (плоскость не повёрнута), край дороги рвётся шумом и камнями, у кладки — параллакс по высоте.
// Повтор плитки глины ломается вторым, повёрнутым слоем и крупными пятнами цвета.
shader_type spatial;

uniform sampler2D g_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_hgt : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask : hint_default_black, filter_linear;
uniform vec4 mask_rect = vec4(-95.0, -99.0, 190.0, 186.0);   // x0, z0, ширина, глубина (м)
uniform float g_tile = 4.0;          // м на повтор глины
uniform float c_tile = 3.2;          // м на повтор кладки
uniform float c_depth = 0.05;        // м, глубина рельефа кладки для параллакса
uniform float normal_strength = 1.0;

varying vec3 wpos;
global uniform vec4 pax_rpg_weather;   // x — мокрость, y — дождь (weather.gd)
global uniform float pax_rpg_time;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// шум луж — без sin (точен в float на любой видеокарте): тот же счёт в weather.gd → puddle_at, чтобы шаг знал,
// что он в луже (хлюпает только в ней)
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float pnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 m = texture(mask, (p - mask_rect.xy) / mask_rect.zw).rg;
	float n = noise(p * 0.45) * 0.55 + noise(p * 1.7) * 0.3 + noise(p * 5.0) * 0.15;

	// глина: два слоя (второй — повёрнут и крупнее), пятна цвета
	vec2 g1 = p / g_tile;
	vec2 g2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (g_tile * 2.3) + vec2(0.37, 0.71);
	float gb = smoothstep(0.3, 0.7, noise(p * 0.07));
	vec3 gc = mix(texture(g_col, g1).rgb, texture(g_col, g2).rgb, gb * 0.6);
	vec3 gn = mix(texture(g_nrm, g1).rgb, texture(g_nrm, g2).rgb, gb * 0.6);
	float gr = texture(g_rgh, g1).r;
	gc *= mix(vec3(0.82, 0.8, 0.78), vec3(1.1, 1.06, 1.0), noise(p * 0.035));
	// тропы: темнее, глаже, без травы — утоптано
	float path = smoothstep(0.2, 0.7, m.g + (n - 0.5) * 0.5);
	gc = mix(gc, gc * vec3(0.78, 0.72, 0.66), path * 0.8);
	gn = mix(gn, vec3(0.5, 0.5, 1.0), path * 0.45);
	gr = mix(gr, 0.78, path * 0.6);

	// кладка: параллакс по высоте (смещение UV к глазу)
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec2 cuv = p / c_tile;
	float h = texture(c_hgt, cuv).r;
	cuv += vw.xz / max(vw.y, 0.3) * (h - 0.5) * c_depth / c_tile;
	h = texture(c_hgt, cuv).r;
	vec3 cc = texture(c_col, cuv).rgb;
	vec3 cn = texture(c_nrm, cuv).rgb;
	float cr = texture(c_rgh, cuv).r;
	// край дороги: камни выступают в глину, между ними — грязь
	float w = smoothstep(0.42, 0.62, m.r + (n - 0.5) * 0.55 + (h - 0.45) * 0.5);
	float edge = w * (1.0 - smoothstep(0.75, 1.0, m.r + n * 0.2));
	cc = mix(cc, cc * vec3(0.62, 0.56, 0.5), edge * (1.0 - h) * 0.9);     // грязь у края забивает щели
	cr = mix(cr, 0.5, edge * (1.0 - h) * 0.5);

	vec3 alb = mix(gc, cc, w);
	vec3 nm = mix(gn, cn, w);
	float rgh = mix(gr, cr, w);
	// мокро: темнее и глаже; в низинах шума и в швах кладки — лужи (зеркальные, рельеф сглажен)
	float wet = pax_rpg_weather.x;
	if (wet > 0.001) {
		// мокро — пятнами: где-то просто влажный камень, где-то потемнее; лужи — отдельные круглые пятна
		// с ровным краем (крупный шум + чуть мелкого), только на ровном и в низких местах кладки
		float damp = wet * mix(0.45, 1.0, smoothstep(0.25, 0.75, noise(p * 0.06 + 3.1)));
		float pn = pnoise(p * 0.11 + 7.3) * 0.8 + pnoise(p * 0.45) * 0.2 - (h - 0.5) * 0.04 * w;
		float pud = smoothstep(0.69, 0.715, pn) * wet;
		float rim = smoothstep(0.6, 0.69, pn) * (1.0 - pud) * wet;          // мокрый ободок вокруг лужи
		alb *= mix(1.0, 0.6, damp + rim * 0.3);
		rgh = mix(rgh, rgh * 0.4, damp);
		rgh = mix(rgh, rgh * 0.25, rim);
		// рябь от капель: кольца по ячейкам, каждое со своим временем
		vec2 cell = floor(p * 2.2);
		vec2 cp = fract(p * 2.2) - 0.5 - (vec2(hash(cell), hash(cell + 17.0)) - 0.5) * 0.6;
		float ph = fract(pax_rpg_time * 1.3 + hash(cell + 5.0));
		float d = length(cp);
		float ring = sin((d - ph * 0.5) * 60.0) * (1.0 - smoothstep(0.5 * ph, 0.5 * ph + 0.06, d)) * smoothstep(0.0, 0.5 * ph + 0.001, d) * (1.0 - ph);
		vec2 rn = (d > 0.001 ? cp / d : vec2(0.0)) * ring * 0.35 * pax_rpg_weather.y;
		alb = mix(alb, alb * vec3(0.45, 0.5, 0.58), pud * 0.7);
		rgh = mix(rgh, 0.02, pud);
		nm = mix(nm, vec3(0.5 + rn.x, 0.5 + rn.y, 1.0), pud);             // зеркало воды, рельеф камня скрыт
	}
	ALBEDO = alb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = rgh;
	SPECULAR = 0.35;
	AO = mix(1.0, 0.55 + 0.45 * h, w);
	AO_LIGHT_AFFECT = 0.3;
}
