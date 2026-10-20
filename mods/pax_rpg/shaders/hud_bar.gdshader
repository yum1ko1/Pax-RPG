// Полоса HUD (hud.gd → живой слой): здоровье и концентрация под кованой рамкой (канал рамки прозрачный).
//   fill / ghost — доля заполнения и светлый «след» недавней потери; centered — от центра в обе стороны
//   (концентрация), иначе от начала; vertical — вдоль высоты (здоровье — снизу вверх);
//   цвет — по толщине от col_hi через col_mid к col_lo (глянец), вдоль — течёт энергия (шум), край заливки
//   светится (glow), сверху — блик стекла; low — пульс к красному (концентрация на исходе), broken — красное
//   мерцание в центре (слом).
shader_type canvas_item;

uniform float fill = 1.0;
uniform float ghost = 1.0;
uniform bool centered = false;
uniform bool vertical = false;
uniform vec4 col_hi : source_color = vec4(1.0, 0.93, 0.55, 1.0);
uniform vec4 col_mid : source_color = vec4(1.0, 0.7, 0.16, 1.0);
uniform vec4 col_lo : source_color = vec4(0.55, 0.24, 0.02, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.97, 0.8, 1.0);
uniform vec4 ghost_col : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform float low = 0.0;
uniform float broken = 0.0;
uniform float alpha = 1.0;
uniform float flow = 1.0;
uniform float aspect = 8.0;          // длина / толщина канала — шум не вытягивается

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = vertical ? vec2(1.0 - UV.y, UV.x) : UV;      // x — вдоль полосы, y — поперёк
	float x = uv.x;
	float y = uv.y;
	float d = centered ? abs(x - 0.5) * 2.0 : x;
	float aa = fwidth(d) * 1.5 + 0.002;
	float inside = 1.0 - smoothstep(fill - aa, fill + aa, d);
	float gin = 1.0 - smoothstep(ghost - aa, ghost + aa, d);
	// подложка канала: тёмный багрянец, к краям — тень
	float mid = 1.0 - abs(y - 0.5) * 2.0;
	vec3 bg = mix(vec3(0.03, 0.004, 0.008), vec3(0.11, 0.018, 0.028), smoothstep(0.0, 1.0, mid));
	// заливка: глянцевый градиент по толщине
	vec3 base = y < 0.45 ? mix(col_hi.rgb, col_mid.rgb, y / 0.45) : mix(col_mid.rgb, col_lo.rgb, (y - 0.45) / 0.55);
	float dir = centered ? sign(x - 0.5) : 1.0;
	vec2 np = vec2(x * aspect * 1.2 - dir * TIME * 0.9 * flow, y * 1.6 + TIME * 0.15);
	float n = fbm(np);
	float streak = smoothstep(0.55, 0.85, fbm(vec2(x * aspect * 0.6 - dir * TIME * 1.6 * flow, y * 0.8)));
	base *= 0.8 + 0.45 * n;
	base += glow.rgb * streak * 0.22;
	base += vec3(1.0) * smoothstep(0.3, 0.06, y) * 0.28;                     // блик стекла сверху
	float e = exp(-max(fill - d, 0.0) * aspect * 2.2) * inside;              // край заливки светится
	base = mix(base, glow.rgb, e * 0.75);
	float sp = step(0.985, hash(floor(vec2(x * aspect * 6.0 - dir * TIME * 4.0, y * 6.0)))) * inside;   // искры
	base += glow.rgb * sp * 0.6;
	float p = low * (0.5 + 0.5 * sin(TIME * 9.0));
	base = mix(base, vec3(1.0, 0.22, 0.16), p * 0.5);
	vec3 c = bg;
	c = mix(c, ghost_col.rgb * (0.82 + 0.18 * mid), gin * (1.0 - inside) * 0.72);
	c = mix(c, base, inside);
	c += vec3(0.95, 0.06, 0.05) * broken * (0.35 + 0.35 * sin(TIME * 10.0)) * (1.0 - smoothstep(0.0, 0.3, d));
	COLOR = vec4(c, alpha);
}
