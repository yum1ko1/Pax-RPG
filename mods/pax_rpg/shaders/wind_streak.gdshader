// Порыв ветра: одна-две тонкие пряди воздуха — едва заметные, рваные шумом, чуть розоватые под небо Юрумы
// (не клубы и не дымка: без ореола вокруг пряди). Квад — вдоль ветра (UV.x); пряди бегут по нему: голова впереди, хвост тает; по ходу «жизни»
// (life 0..1) пучок появляется и гаснет.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// жизнь и полёт считает шейдер по общим часам (gfx.gd → pax_rpg_time): скрипт ничего не пишет в кадр
global uniform float pax_rpg_time;
instance uniform float t0 = 0.0;
instance uniform float dur = 1.2;
instance uniform vec3 vel = vec3(0.0);
instance uniform float phase = 0.0;
instance uniform float curl = 0.3;
varying float life;

void vertex() {
	float el = max(pax_rpg_time - t0, 0.0);
	life = clamp(el / dur, 0.0, 1.0);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(vel * el, 0.0)).xyz;   // прядь летит с ветром
}
uniform vec3 tint = vec3(1.0, 0.9, 0.97);

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) { float i = floor(x); float f = fract(x); return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f)); }

void fragment() {
	float x = UV.x;
	float head = mix(-0.2, 1.3, life);
	float seg = smoothstep(head - 0.8, head - 0.15, x) * (1.0 - smoothstep(head - 0.03, head + 0.03, x));
	float fade = smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.65, 1.0, life));
	float a = 0.0;
	int strands = 1 + int(hash(phase * 3.1) > 0.45);       // одна или две пряди
	if (seg * fade <= 0.0) {
		strands = 0;                                       // вне головы и хвоста прядь прозрачна — пряди не считаем
	}
	for (int k = 0; k < strands; k++) {
		float fk = float(k);
		float ph = phase + fk * 1.7;
		float cy = 0.5 + (fk - 0.5) * 0.18 + sin(x * (5.0 + fk) + ph) * 0.12 * curl * 2.0 + pow(x, 5.0) * curl * 0.6 * sin(ph);
		float w = mix(0.004, 0.012, sin(x * 3.14159)) * (1.0 - fk * 0.25);   // тоньше к концам
		float d = abs(UV.y - cy);
		float strand = smoothstep(w, 0.0, d);
		float broken = smoothstep(0.35, 0.7, noise(x * 18.0 + fk * 7.0 + phase * 3.0));   // рвётся на клочья
		a += strand * broken * (0.55 + 0.45 * hash(fk + floor(phase * 10.0)));
	}
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0) * seg * fade * 0.2;
}
