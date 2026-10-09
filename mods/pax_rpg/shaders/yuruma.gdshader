shader_type spatial;
render_mode unshaded, cull_back;

// Юрума вместо Земли: карта поверхности (с мановыми облаками) по развёртке игры, свет от солнца игры,
// розовая мановая дымка и ореол атмосферы. sun_dir игра сама ставит на материал планеты каждый кадр
// (в пространстве планеты) — имя то же, что в её planet.gdshader.

uniform sampler2D surface_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 haze_color : source_color = vec3(1.0, 0.56, 0.84);
uniform float haze : hint_range(0.0, 1.0) = 0.12;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.9;
uniform float night_light : hint_range(0.0, 1.0) = 0.07;

varying vec3 local_n;

void vertex() {
	local_n = normalize(VERTEX);
}

// Та же развёртка, что sph_uv игры: u — долгота от atan(x, z), v — от северного полюса (y).
vec2 sph_uv(vec3 n) {
	return vec2(atan(n.x, n.z) / TAU + 0.5, acos(clamp(n.y, -1.0, 1.0)) / PI);
}

void fragment() {
	vec3 n = normalize(local_n);
	vec2 uv = sph_uv(n);
	// шов развёртки: производная по u скачет на единицу — без поправки по меридиану идёт мыльная полоса
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	vec3 col = textureGrad(surface_map, uv, dx, dy).rgb;

	float ndl = dot(n, normalize(sun_dir));
	float day = smoothstep(-0.12, 0.25, ndl);
	vec3 lit = col * mix(night_light, 1.0, clamp(ndl * 1.1 + 0.05, 0.0, 1.0));

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	lit = mix(lit, haze_color * (0.3 + 0.7 * day), haze * (0.35 + 0.65 * day));
	lit += haze_color * fres * rim_strength * (0.2 + 0.8 * day);
	ALBEDO = lit;
}
