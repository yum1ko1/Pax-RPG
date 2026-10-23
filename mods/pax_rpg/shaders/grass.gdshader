// Трава города (src/location/grass.gd): кустики-пучки травинок, MultiMesh по ячейкам.
// Ветер — глобальный pax_rpg_wind (xy — направление, z — сила, w — порыв; ведёт wind.gd): по полю бегут волны
// вдоль ветра, кончики дрожат, в порыв трава ложится. Герой (pax_rpg_player) раздвигает траву вокруг себя.
// Вдали травинки плавно уходят в землю (а не исчезают разом). UV.y — высота по травинке (0 — корень, 1 — кончик).
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

global uniform vec4 pax_rpg_wind;
global uniform vec4 pax_rpg_player;
global uniform float pax_rpg_time;
global uniform vec4 pax_rpg_weather;      // время ветра (gfx.gd): в остановке времени (иай) стоит и трава

uniform vec3 root_col : source_color = vec3(0.16, 0.15, 0.07);
uniform vec3 green_col : source_color = vec3(0.47, 0.5, 0.24);
uniform vec3 dry_col : source_color = vec3(0.74, 0.58, 0.34);
uniform float fade_start = 28.0;
uniform float fade_end = 40.0;
uniform float bend = 0.35;           // м, наклон кончика при сильном ветре

varying float h;
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	h = UV.y;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(wp.xz, cam.xz);
	VERTEX.y *= 1.0 - smoothstep(fade_start, fade_end, d);        // вдали — ниже и ниже, до земли
	vec2 wd = normalize(pax_rpg_wind.xy + vec2(1e-4));
	float s = pax_rpg_wind.z;
	float g = pax_rpg_wind.w;
	float wave = sin(pax_rpg_time * 1.6 - dot(wp.xz, wd) * 0.32 + noise(wp.xz * 0.05) * 4.0) * 0.5 + 0.5;
	float flutter = sin(pax_rpg_time * 7.0 + wp.x * 3.1 + wp.z * 2.3) * 0.12;
	float b = (0.12 + 0.55 * wave * s + 0.8 * g + flutter * (0.4 + s)) * h * h * bend;
	vec3 off = vec3(wd.x, 0.0, wd.y) * b;
	// герой раздвигает траву: от него, сильнее у ног
	vec2 away = wp.xz - pax_rpg_player.xz;
	float pd = length(away);
	float push = (1.0 - smoothstep(0.25, 0.9, pd)) * step(abs(wp.y - pax_rpg_player.y), 1.5);
	off.xz += normalize(away + vec2(1e-4)) * push * 0.22 * h;   // только расступается — высота травы не меняется
	off.y -= b * b * 0.5 * h;
	// в оси сетки: у пучков оси взаимно перпендикулярны (поворот вокруг вертикали и масштаб — grass.gd), обратная
	// матрица — оси, делённые на квадрат длины; то же, что inverse(mat3(MODEL_MATRIX)) * off, без обращения в вершине
	vec3 a0 = MODEL_MATRIX[0].xyz;
	vec3 a1 = MODEL_MATRIX[1].xyz;
	vec3 a2 = MODEL_MATRIX[2].xyz;
	VERTEX += vec3(dot(a0, off) / dot(a0, a0), dot(a1, off) / dot(a1, a1), dot(a2, off) / dot(a2, a2));
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));     // мягкий свет по пучку, без «полосатости»
}

void fragment() {
	float n06 = noise(wp.xz * 0.06);                                // пятна: один шум на оттенок и яркость
	float patch = smoothstep(0.35, 0.75, n06 * 0.7 + noise(wp.xz * 0.4) * 0.3);
	vec3 tip = mix(green_col, dry_col, patch) * COLOR.rgb;
	vec3 c = mix(root_col, tip, smoothstep(0.0, 0.7, h));
	c += vec3(0.08, 0.07, 0.03) * smoothstep(0.75, 1.0, h);         // выгоревшие кончики
	ALBEDO = (c) * mix(vec3(0.85, 0.95, 0.75), vec3(1.15, 1.05, 0.8), n06) * mix(1.0, 0.72, pax_rpg_weather.x);   // пятнами, как земля; мокрая — темнее
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.55;                                          // на просвет против солнца — светится
	AO = mix(0.35, 1.0, h);
	AO_LIGHT_AFFECT = 0.5;
}
