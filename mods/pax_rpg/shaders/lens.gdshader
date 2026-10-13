// Слой камеры (gfx.gd → материал контейнера 3D-вида локации, SubViewportContainer): то, что делает картинку «снятой»,
// а не нарисованной (приём Bodycam — кадр несёт недостатки настоящей оптики и сенсора):
//   distortion — лёгкая бочка объектива (центр чуть крупнее, углы на месте);
//   ca — хроматическая аберрация к краям; sharpen — цифровая резкость (как у камеры, не мыло);
//   grain — зерно сенсора, сильнее в тенях, своё в каждом кадре; vignette — затемнение краёв (0 — есть отдельное).
//   flare — блики объектива от солнца (sun_uv — солнце на экране, sun_vis 0..1 — видно ли, gfx.gd проверяет лучом):
//     ореол вокруг солнца, горизонтальная полоса, «призраки» вдоль линии солнце → центр кадра;
//   mblur — размытие при повороте камеры (смещение кадра за выдержку, доли экрана; gfx.gd), центр с героем резкий.
// Всё здесь, а не в эффектах потока рендера: с отдельным потоком рендера те вешали игру.
// Тут же «Остановка времени» иая (iai.gd ставит k / wave / flash / center на этот же материал):
//   k 0..1 — рыбий глаз сильнее, расслоение цвета, мир уходит в сиреневый монохром; wave — кольцо волны от героя;
//   flash — белая вспышка. Без иая k = 0 — только слой камеры.
shader_type canvas_item;

uniform float distortion = 0.0;
uniform float ca = 0.0;
uniform float sharpen = 0.22;
uniform float grain = 0.0;
uniform float grain_size = 1.3;       // пикселей на зерно
uniform float vignette = 0.0;
uniform vec2 sun_uv = vec2(-1.0);
uniform float sun_vis = 0.0;
uniform vec3 sun_col = vec3(1.0, 0.82, 0.62);
uniform float flare = 1.0;
uniform float ghosts = 0.0;          // «призраки», полоса и кольцо объектива (0 — только сияние солнца, как в RPG)
uniform vec2 mblur = vec2(0.0);

uniform float k = 0.0;
uniform float wave = -1.0;
uniform float flash = 0.0;
uniform vec2 center = vec2(0.5, 0.55);
uniform vec3 tint = vec3(0.78, 0.66, 1.0);
uniform float strength = 0.38;        // рыбий глаз иая: центр крупнее в 1 / (1 − strength) раз

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 asp = vec2(px.y / px.x, 1.0);
	vec2 d = (UV - vec2(0.5)) * asp;
	float r2 = dot(d, d);
	float rr = r2 / dot(vec2(0.5) * asp, vec2(0.5) * asp);          // 0 — центр, 1 — угол кадра
	vec2 fe = d * (1.0 - (distortion + k * strength) * (1.0 - rr));
	vec2 dc = (UV - center) * asp;
	float rc = length(dc);
	float front = wave > 0.0 ? exp(-pow((rc - wave) / 0.012, 2.0)) : 0.0;
	fe += normalize(dc + 1e-5) * front * 0.025;
	vec2 base = fe / asp + vec2(0.5);
	// аберрация: R/B разъезжаются к краям (у иая — сильнее)
	float shift = (ca + k * 0.006) * (0.3 + rr * 1.7) + front * 0.012;
	vec2 dir = normalize(d + 1e-5) / asp;
	vec3 col;
	col.r = textureLod(TEXTURE, base + dir * shift, 0.0).r;
	col.g = textureLod(TEXTURE, base, 0.0).g;
	col.b = textureLod(TEXTURE, base - dir * shift, 0.0).b;
	// размытие поворота: вдоль смещения кадра, по краям сильнее, центр (герой) резкий
	float mb_len = length(mblur);
	if (mb_len > 0.0005) {
		float edge = smoothstep(0.04, 0.3, r2);
		vec3 acc = col;
		for (int i = 1; i <= 7; i++) {
			float t = float(i) / 7.0 - 0.5;
			acc += textureLod(TEXTURE, base + mblur * t * edge, 0.0).rgb;
		}
		col = acc / 8.0;
	}
	// цифровая резкость: нерезкая маска по крестику соседей
	if (sharpen > 0.0) {
		vec3 nb = textureLod(TEXTURE, base + vec2(px.x, 0.0), 0.0).rgb + textureLod(TEXTURE, base - vec2(px.x, 0.0), 0.0).rgb
			+ textureLod(TEXTURE, base + vec2(0.0, px.y), 0.0).rgb + textureLod(TEXTURE, base - vec2(0.0, px.y), 0.0).rgb;
		col += (col - nb * 0.25) * sharpen;
	}
	// остановленный мир иая: сиреневый монохром с сохранённым контрастом
	if (k > 0.001) {
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float lc = pow(smoothstep(0.08, 0.9, l), 1.35);
		col = mix(col, mix(vec3(0.03, 0.015, 0.07), tint, lc), k * 0.75);
		col += vec3(0.9, 0.75, 1.0) * clamp(front, 0.0, 1.0) * 0.55;
		col *= 1.0 - k * 0.45 * smoothstep(0.15, 0.6, r2);
	}
	col *= 1.0 - vignette * smoothstep(0.2, 0.75, r2);
	// блики объектива от солнца
	if (sun_vis > 0.001 && flare > 0.0) {
		vec2 sv = (UV - sun_uv) * asp;
		float sd = length(sv);
		vec3 f = sun_col * (exp(-sd * 9.0) * 0.55 + exp(-sd * 40.0) * 0.6);          // ореол у солнца
		f += sun_col * exp(-abs(sv.y) * 260.0) * exp(-abs(sv.x) * 2.2) * 0.35 * ghosts;   // горизонтальная полоса
		vec2 axis = vec2(0.5) - sun_uv;
		for (int i = 0; i < 4; i++) {                                              // «призраки» линз
			float tpos = 0.55 + float(i) * 0.42;
			vec2 gp = (UV - (sun_uv + axis * tpos * 2.0)) * asp;
			float gr = 0.03 + 0.025 * float(i);
			float ghost = smoothstep(gr, gr * 0.55, length(gp));
			vec3 gc = mix(vec3(0.5, 0.75, 1.0), vec3(1.0, 0.55, 0.8), float(i) / 3.0);
			f += gc * ghost * 0.07 * ghosts;
		}
		float ring = exp(-pow((length((UV - vec2(0.5)) * asp + (sun_uv - vec2(0.5)) * asp * 0.4) - 0.32) / 0.02, 2.0));
		f += vec3(0.85, 0.7, 1.0) * ring * 0.035 * ghosts;                          // кольцо-гало
		col += f * sun_vis * flare;
	}
	// зерно сенсора: в каждом кадре своё, в тенях заметнее, в светах почти нет
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec2 gp = floor(FRAGCOORD.xy / grain_size);
	float g = hash(gp + fract(TIME * 17.0) * 113.0) - 0.5;
	col += g * grain * (1.25 - smoothstep(0.0, 0.8, lum));
	col = mix(col, vec3(1.0, 0.95, 1.0), flash);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
