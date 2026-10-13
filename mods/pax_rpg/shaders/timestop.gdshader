// «Остановка времени» (приём Иай, src/location/iai.gd): экранный проход поверх 3D.
// k — сила эффекта 0..1: рыбий глаз (бочка) + расслоение цвета к краям + мир уходит в сиреневый монохром;
// wave — радиус волны от героя (доли экрана): на фронте — инверсия цвета и сильное искажение;
// flash — белая вспышка (финал); center — герой на экране (UV).
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
uniform float wave = -1.0;
uniform float flash = 0.0;
uniform vec2 center = vec2(0.5, 0.55);
uniform vec3 tint = vec3(0.78, 0.66, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 asp = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 d = (uv - vec2(0.5)) * asp;
	float r2 = dot(d, d);
	// рыбий глаз: центр «выпячивается», края стягиваются
	vec2 fe = d * (1.0 - k * 0.32 * r2) / (1.0 - k * 0.08);
	// волна от героя: кольцо искажения
	vec2 dc = (uv - center) * asp;
	float rc = length(dc);
	float front = wave > 0.0 ? exp(-pow((rc - wave) / 0.035, 2.0)) : 0.0;
	fe += normalize(dc + 1e-5) * front * 0.025;
	vec2 base = fe / asp + vec2(0.5);
	// расслоение цвета: R/B разъезжаются к краям
	float ca = k * 0.006 * (0.5 + r2 * 4.0) + front * 0.012;
	vec2 dir = normalize(d + 1e-5) / asp;
	vec3 col;
	col.r = textureLod(screen, base + dir * ca, 0.0).r;
	col.g = textureLod(screen, base, 0.0).g;
	col.b = textureLod(screen, base - dir * ca, 0.0).b;
	// остановленный мир: сиреневый монохром с сохранённым контрастом
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 mono = mix(vec3(0.05, 0.03, 0.1), tint * 1.15, smoothstep(0.02, 0.85, l));
	col = mix(col, mono, k * 0.85);
	// фронт волны — негатив
	col = mix(col, vec3(1.0) - col, clamp(front * 1.3, 0.0, 1.0) * step(0.01, k));
	// края темнее, вспышка
	col *= 1.0 - k * 0.45 * smoothstep(0.15, 0.6, r2);
	col = mix(col, vec3(1.0, 0.95, 1.0), flash);
	COLOR = vec4(col, 1.0);
}
