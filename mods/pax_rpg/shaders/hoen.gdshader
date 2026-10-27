// Хоэн — солнце Юрумы (тело игры «Солнце», шейдер ставит data/bodies.patch.json). Один шейдер рисует и диск, и
// корону: сфера тела раздута в hull раз, а каждый пиксель пускает луч из камеры — попал в настоящую сферу — это
// поверхность, иначе — корона по тому, как близко луч прошёл от центра, и по углу вокруг луча зрения. Лишних узлов в
// сцене нет. Так же нарисовано превью «Солнце Хоэн» (variant: 0 — золотой, 1 — в венце маны, 2 — лучистый).
// Считаем в пространстве камеры: до солнца ~150 000 единиц, расстояние луча от центра — через cross (без вычитания
// больших квадратов, иначе float теряет край диска).
shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform float variant = 1.0;
uniform float hull = 4.0;                                        // до скольких радиусов тянется корона
uniform vec3 hoen_core = vec3(1.0, 0.88, 0.6);
uniform vec3 hoen_edge = vec3(1.0, 0.52, 0.26);
uniform vec3 hoen_mana = vec3(1.0, 0.36, 0.72);
uniform float brightness = 1.0;
// Игра ставит звезде свои core, edge и world_seed — объявлены, чтобы не было предупреждений; цвета Хоэна — свои.
uniform vec3 core = vec3(1.0, 0.92, 0.72);
uniform vec3 edge = vec3(1.0, 0.55, 0.18);
uniform float world_seed = 0.0;

varying vec3 v_center;                                           // центр солнца в пространстве камеры
varying float v_r;                                               // его радиус

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm4(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.13 + vec3(1.7, -2.3, 0.9);
		a *= 0.5;
	}
	return s;
}

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += vnoise(p) * a;
		p = p * 2.13 + vec3(1.7, -2.3, 0.9);
		a *= 0.5;
	}
	return s / 0.875;
}

// n — точка на сфере в осях солнца, mu — косинус угла к лучу зрения (1 — центр диска, 0 — край).
vec3 surface(vec3 n, float mu, float t) {
	float a = t * 0.012;                                          // медленно вращается вокруг оси
	float ca = cos(a);
	float sa = sin(a);
	vec3 q = vec3(ca * n.x + sa * n.z, n.y, -sa * n.x + ca * n.z);
	vec3 w = vec3(fbm3(q * 3.0 + vec3(1.7, t * 0.02, 4.1)), fbm3(q * 3.0 + vec3(8.3, 2.8, -t * 0.02)),
		fbm3(q * 3.0 + vec3(-3.1, t * 0.015, 6.6)));
	float big = fbm4(q * 2.2 + w * 0.9);                          // медленная конвекция: светлые и тусклые поля
	float mid = fbm3(q * 9.0 + w * 2.0 + vec3(0.0, t * 0.03, 0.0));
	float cells = 0.5 * (vnoise(q * 70.0 + w * 5.0 + vec3(t * 0.05)) + vnoise(q.zxy * 61.0 - w * 4.0 - vec3(t * 0.04)));
	float soft = variant > 1.5 ? 0.4 : 1.0;                       // лучистый — спокойнее
	float heat = 0.58 * big + 0.27 * mid + 0.15 * mix(0.5, cells, soft) + 0.08;
	vec3 deep = hoen_edge * vec3(0.92, 0.62, 0.45);
	vec3 col = mix(deep, hoen_edge, smoothstep(0.22, 0.42, heat));
	col = mix(col, hoen_core, smoothstep(0.38, 0.62, heat));
	col = mix(col, vec3(1.0, 0.98, 0.9), smoothstep(0.6, 0.82, heat) * 0.7);
	if (variant > 0.5 && variant < 1.5) {                         // по золоту текут розовые жилы маны
		float v = fbm3(q * 1.8 + w * 1.2 + vec3(0.0, -t * 0.03, t * 0.02));
		float vein = pow(1.0 - abs(v * 2.0 - 1.0), 26.0);
		float vein2 = pow(1.0 - abs(fbm3(q * 4.5 + w * 1.5 - vec3(t * 0.05)) * 2.0 - 1.0), 40.0);
		col = mix(col, hoen_mana * 1.25, clamp(vein * 0.9 + vein2 * 0.5, 0.0, 1.0) * (0.35 + 0.65 * mu));
	}
	col *= 0.42 + 0.58 * pow(mu, 0.55);                           // потемнение к краю
	col = mix(hoen_edge * vec3(1.0, 0.62, 0.42), col, smoothstep(0.0, 0.3, mu));   // янтарно-красный край
	if (variant > 1.5) {
		col = mix(col, vec3(1.0, 0.95, 0.8), pow(1.0 - mu, 6.0) * 0.8);          // у лучистого — светлый ободок
	}
	return col * 1.18;
}

// b — ближайшее расстояние луча до центра в радиусах (≥ 1), cs — направление на это место вокруг луча зрения.
vec3 corona(float b, vec2 cs, float t) {
	float x = max(b - 1.0, 0.0);
	float fade = 1.0 - smoothstep(hull * 0.62, hull * 0.97, b);
	vec3 col;
	if (variant < 0.5) {                                          // золотой: мягкая корона с неровными лучами
		float halo = exp(-x * 7.0) * 0.85 + exp(-x * 1.8) * 0.32 + exp(-x * 0.55) * 0.07;
		float s1 = fbm4(vec3(cs * 2.6, x * 0.5 - t * 0.03));
		float s2 = fbm3(vec3(cs * 8.0, x * 1.2 - t * 0.05));
		float streak = clamp(0.45 + 1.4 * (s1 - 0.45) + 0.8 * (s2 - 0.5), 0.0, 2.0);
		float near = smoothstep(0.0, 0.25, x);
		col = mix(hoen_core, hoen_edge * vec3(1.0, 0.8, 0.6), smoothstep(0.0, 1.0, x)) * halo
			* (0.55 + 0.75 * streak * near + (1.0 - near) * 0.45);
	} else if (variant < 1.5) {                                   // венец маны: золото у края, дальше розовые потоки
		float halo = exp(-x * 7.5) * 0.8 + exp(-x * 1.9) * 0.26;
		vec3 gold = mix(hoen_core, hoen_edge, smoothstep(0.0, 0.5, x)) * halo;
		float s1 = fbm4(vec3(cs * 3.2, x * 0.7 - t * 0.05));
		float s2 = fbm3(vec3(cs * 10.0, x * 1.6 - t * 0.08));
		float streak = clamp(1.6 * (s1 - 0.42) + 0.9 * (s2 - 0.5), 0.0, 2.0);
		vec3 pink = hoen_mana * streak * (exp(-x * 0.9) * 0.55 + exp(-x * 3.0) * 0.35) * smoothstep(0.02, 0.3, x);
		float arcs = vnoise(vec3(cs * 13.0, t * 0.12));          // протуберанцы у самого края
		float loops = smoothstep(0.58, 0.8, arcs) * exp(-x * 9.0) * smoothstep(0.0, 0.03, x);
		float lace = pow(1.0 - abs(fbm3(vec3(cs * 18.0, x * 9.0 - t * 0.2)) * 2.0 - 1.0), 8.0) * exp(-x * 5.0)
			* smoothstep(0.0, 0.03, x);
		col = gold + pink + hoen_mana * vec3(1.15, 0.9, 1.0) * (loops * 1.6 + lace * 0.9);
	} else {                                                      // лучистый: два слоя лучей вращаются навстречу
		float th = atan(cs.y, cs.x);
		float halo = exp(-x * 6.0) * 0.8 + exp(-x * 1.6) * 0.3;
		float r1 = pow(abs(cos(th * 6.0 + t * 0.035)), 26.0) * exp(-x * 0.85);
		float r2 = pow(abs(cos(th * 9.0 - t * 0.022 + 0.6)), 60.0) * exp(-x * 1.5) * 0.7;
		float r3 = pow(abs(cos(th * 24.0 + t * 0.06)), 8.0) * exp(-x * 4.0) * 0.25;
		float shimmer = 0.8 + 0.4 * vnoise(vec3(cs * 5.0, x * 2.0 - t * 0.3));
		float rays = (r1 + r2 + r3) * shimmer * smoothstep(0.0, 0.08, x);
		vec3 ray_col = mix(vec3(1.0, 0.93, 0.72), mix(hoen_edge, hoen_mana, 0.55), smoothstep(0.3, 2.0, x));
		col = mix(hoen_core, hoen_edge, smoothstep(0.0, 0.6, x)) * halo + ray_col * rays * 0.95;
	}
	return col * fade;
}

void vertex() {
	v_center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_r = length((MODELVIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);     // вершина сферы лежит на её поверхности
	VERTEX *= hull;
}

void fragment() {
	vec3 rd = normalize(VERTEX);                                  // луч из камеры (она в начале координат)
	vec3 oc = -v_center;
	float tca = dot(v_center, rd);                                // вдоль луча до ближайшей к центру точки
	float d = length(cross(rd, v_center)) / v_r;                  // как близко луч прошёл от центра, в радиусах
	vec3 col;
	if (d < 1.0 && tca > 0.0) {
		float th = tca - v_r * sqrt(1.0 - d * d);
		vec3 nv = (oc + rd * th) / v_r;                           // нормаль в осях камеры
		vec3 nw = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
		vec3 nl = normalize(transpose(mat3(MODEL_MATRIX)) * nw);  // в осях солнца — узор крутится вместе с ним
		col = surface(nl, clamp(dot(nv, -rd), 0.0, 1.0), TIME);
	} else {
		vec3 pc = rd * max(tca, 0.0) - v_center;                  // от центра к ближайшей точке луча
		vec3 wv = normalize(v_center);
		vec3 axis = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;   // ось солнца — корона не крутится с камерой
		vec3 u = cross(wv, axis);
		u = length(u) > 0.0001 ? normalize(u) : normalize(cross(wv, vec3(1.0, 0.0, 0.0)));
		vec3 v = cross(u, wv);
		vec2 cs = normalize(vec2(dot(pc, u), dot(pc, v)) + vec2(0.000001));
		col = corona(d, cs, TIME);
	}
	ALBEDO = pow(max(col, vec3(0.0)), vec3(2.2)) * brightness;    // превью писало цвет в sRGB, Godot ждёт линейный
}
