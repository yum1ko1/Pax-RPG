## Материал «как в больших играх» для домов у входа (Аллея Сакур): цвет и рисунок — атлас Meshy (2048 на весь дом),
## поверх — повторяющиеся текстуры в мировых метрах (трипланарно): дерево (Poly Haven weathered_planks, CC0) там,
## где атлас тёплый и насыщенный, камень (japanese_stone_wall) — где серый. Детали меняют только яркость (±) и
## рельеф (нормали смешиваются с нормалями атласа), цвет остаётся атласа — вблизи стена из волокон и швов, а не мыла.
## Вдали детали гаснут (detail_far м) — рябь мипов не мерцает.
## Цена пикселя: выборки деталей — только там, где их видно (ближе detail_far), только нужный материал (камень или
## дерево; оба — лишь на их стыке) и только оси трипланара с заметным весом — вместо 12 выборок на каждый пиксель.
extends RefCounted

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")

const SH := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D atlas_n : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_n = true;
uniform sampler2D stone_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stone_avg = 0.4;
uniform float wood_avg = 0.4;
uniform float tile_stone = 0.35;   // повторов на метр
uniform float tile_wood = 0.55;
uniform float strength = 0.75;     // сила рисунка в яркости
uniform float n_strength = 0.8;    // сила рельефа деталей
uniform float detail_far = 45.0;
uniform float sky_far_ao = 0.35;  // сколько неба остаётся на дальних домах
uniform float sky_far_from = 40.0;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack(vec2 rg) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Есть ли в квадрате 2×2 пикселя (по нему видеокарта считает мип выборки) хоть один v > 0 — ответ один на все
// четыре: выборки внутри такой ветки получают верный мип, на границе ветки нет шва и ряби.
// В Compatibility (GLES3) точных производных нет — там ветки не пропускаются (всё считается, как раньше).
vec4 quad_any(vec4 v) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return vec4(1.0);
#else
	v = max(v, vec4(0.0));
	v += abs(dFdxFine(v));
	return v + abs(dFdyFine(v));
#endif
}

void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	float mx = max(base.r, max(base.g, base.b));
	float mn = min(base.r, min(base.g, base.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float wood = smoothstep(0.16, 0.34, sat) * smoothstep(-0.02, 0.06, base.r - base.b);
	float dist = length(VERTEX);
	float k = 1.0 - smoothstep(detail_far * 0.6, detail_far, dist);
	vec3 an = has_n ? unpack(texture(atlas_n, UV).rg) : vec3(0.0, 0.0, 1.0);
	// трипланар: ось с весом < 0.001 (стена ±10° от оси, вертикаль у стен) не выбирается, остальные — к сумме 1:
	// сверено рендером — разница ≤ 1/255 (0.005 уже давало 3/255 и мерцание бликов)
	vec3 w = wn * wn;
	w *= w;
	w /= (w.x + w.y + w.z);
	w *= step(vec3(0.001), w);
	w /= (w.x + w.y + w.z);
	vec4 need = quad_any(vec4(k, 1.0 - wood, wood, 0.0));   // детали видны · нужен камень · нужно дерево
	vec3 axes = quad_any(vec4(w, 0.0)).xyz;
	float l = 1.0;                                          // без деталей — яркость и рельеф атласа как есть
	vec3 dn = vec3(0.0, 0.0, 1.0);
	if (need.x > 0.0) {
		vec2 px = wp.zy, py = wp.xz, pz = wp.xy;
		float ts = tile_stone;
		float tw = tile_wood;
		vec3 sa = vec3(0.0), wa = vec3(0.0);
		vec2 sn = vec2(0.0), wnn = vec2(0.0);
		if (need.y > 0.0) {
			if (axes.x > 0.0) { sa += texture(stone_a, px * ts).rgb * w.x; sn += texture(stone_n, px * ts).rg * w.x; }
			if (axes.y > 0.0) { sa += texture(stone_a, py * ts).rgb * w.y; sn += texture(stone_n, py * ts).rg * w.y; }
			if (axes.z > 0.0) { sa += texture(stone_a, pz * ts).rgb * w.z; sn += texture(stone_n, pz * ts).rg * w.z; }
		}
		if (need.z > 0.0) {
			if (axes.x > 0.0) { wa += texture(wood_a, px * tw).rgb * w.x; wnn += texture(wood_n, px * tw).rg * w.x; }
			if (axes.y > 0.0) { wa += texture(wood_a, py * tw).rgb * w.y; wnn += texture(wood_n, py * tw).rg * w.y; }
			if (axes.z > 0.0) { wa += texture(wood_a, pz * tw).rgb * w.z; wnn += texture(wood_n, pz * tw).rg * w.z; }
		}
		float ls = dot(sa, vec3(0.299, 0.587, 0.114)) / stone_avg;
		float lw = dot(wa, vec3(0.299, 0.587, 0.114)) / wood_avg;
		l = mix(ls, lw, wood);
		dn = unpack(mix(sn, wnn, wood));
		dn.xy *= n_strength * k;
	}
	ALBEDO = base * mix(1.0, clamp(l, 0.35, 1.8), strength * k);
	vec3 n = normalize(vec3(an.xy + dn.xy, an.z * dn.z));   // whiteout: швы атласа + волокна и сколы деталей
	NORMAL_MAP = n * 0.5 + 0.5;
	ROUGHNESS = mix(0.92, 0.8, wood) - (l - 1.0) * 0.08 * k;
	SPECULAR = mix(0.12, 0.3, k);
	// вдали дом вне каскадов GI: его светит голое ночное небо без затенения — синеет и белеет. Гасим долю
	// неба (AO действует на рассеянный свет и отражения неба, на фонари и луну — нет)
	AO = mix(1.0, sky_far_ao, smoothstep(sky_far_from, sky_far_from * 2.5, dist));
	AO_LIGHT_AFFECT = 0.0;              // вдали без бликов — дома не белеют
}
"""

static var _shader: Shader
static var _tex := {}
static var _mats := {}


static func _dds(mod: PaxMod, rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var t: Texture2D = Assets.dds_tex(mod, rel)       # общая с city/arena: камень арены в видеопамяти один раз
	_tex[rel] = t
	return t


static func _avg(t: Texture2D) -> float:
	if t == null:
		return 0.4
	var img := t.get_image()
	if img == null:
		return 0.4
	if img.is_compressed():
		img = img.duplicate() as Image
		img.decompress()
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c := img.get_pixel(0, 0)
	return maxf(0.05, c.r * 0.299 + c.g * 0.587 + c.b * 0.114)


## Материал для поверхности с атласом src (один на атлас — дома одной модели делят его).
static func material(mod: PaxMod, src: BaseMaterial3D) -> Material:
	if src == null or src.albedo_texture == null:
		return null
	if _mats.has(src):
		return _mats[src]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SH
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("atlas", src.albedo_texture)
	m.set_shader_parameter("has_n", src.normal_enabled and src.normal_texture != null)
	if src.normal_texture != null:
		m.set_shader_parameter("atlas_n", src.normal_texture)
	var sa := _dds(mod, "textures/arena/japanese_stone_wall_diff.dds")
	var wa := _dds(mod, "textures/detail/wood_planks_diff.dds")
	m.set_shader_parameter("stone_a", sa)
	m.set_shader_parameter("stone_n", _dds(mod, "textures/arena/japanese_stone_wall_nor.dds"))
	m.set_shader_parameter("wood_a", wa)
	m.set_shader_parameter("wood_n", _dds(mod, "textures/detail/wood_planks_nor.dds"))
	if not _tex.has("avg_s"):
		_tex["avg_s"] = _avg(sa)
		_tex["avg_w"] = _avg(wa)
	m.set_shader_parameter("stone_avg", _tex["avg_s"])
	m.set_shader_parameter("wood_avg", _tex["avg_w"])
	_mats[src] = m
	return m
