// Объёмные формы удара (src/location/hit_vfx.gd → _cone / _helix / _sphere): не плоская картинка, а сетка вокруг оси
// удара — конус луча, ленты спирали, ударный конус, сфера вспышки. UV.x — вдоль удара (0 — хвост, 1 — остриё),
// UV.y — вокруг оси. Объём даёт угол обзора: оболочка (fres > 0) светится по краю силуэта и прозрачна в лоб — как
// светящийся газ; ядро (fres_inv = 1) — наоборот, плотное в лоб. По объёму бежит шум (3D, по кругу без шва) — рвёт
// и «течёт» вдоль удара; progress 0..1 съедает форму от хвоста к острию, по кромке выгорания — золотистый ободок.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(1.0, 0.95, 0.92);
uniform vec3 mid : source_color = vec3(1.0, 0.08, 0.16);
uniform vec3 edge : source_color = vec3(0.32, 0.0, 0.03);
uniform vec3 rim : source_color = vec3(1.0, 0.7, 0.32);
uniform float energy = 2.0;
uniform float fres = 2.0;
uniform float fres_inv = 0.0;
uniform float flow = 3.0;            // скорость шума вдоль удара (от хвоста к острию)
uniform float noise_scale = 3.0;
uniform float soft = 0.12;
uniform float density = 1.0;
uniform float heat_k = 1.0;          // сколько белого ядра в цвете
instance uniform float progress = 0.0;
instance uniform float reveal = 2.0;
instance uniform float glow = 1.0;
instance uniform float seed = 0.0;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm(vec3 p) {
	float r = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		r += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return r / 0.9375;
}

void fragment() {
	float nv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float f = mix(pow(1.0 - nv, fres), pow(nv, 1.5), fres_inv);
	float ang = UV.y * 6.2831853;
	vec3 p = vec3(UV.x * noise_scale * 2.5 - TIME * flow + seed * 7.0, cos(ang) * noise_scale * 0.6, sin(ang) * noise_scale * 0.6);
	float n = fbm(p);
	float er = 0.55 * UV.x + 0.45 * n;
	float thr = progress * (1.0 + soft);
	float keep = smoothstep(thr, thr + soft, er);
	float burn = (1.0 - smoothstep(0.0, soft * 1.2, abs(er - thr - soft * 0.5))) * step(0.001, progress);
	float vis = smoothstep(reveal, reveal - 0.08, UV.x);
	float ends = smoothstep(0.0, 0.12, UV.x);
	float body = f * (0.35 + 0.9 * n) * ends * vis * density;
	float a = clamp(body * keep, 0.0, 1.0);
	float heat = clamp(a * a * heat_k * (1.0 - 0.5 * progress), 0.0, 1.0);
	vec3 col = mix(edge, mid, smoothstep(0.05, 0.6, a));
	col = mix(col, core, smoothstep(0.55, 1.0, heat));
	ALBEDO = (col * a + rim * burn * body * 0.9) * energy * glow;
	ALPHA = clamp(a * (1.0 - heat) * 0.95, 0.0, 1.0);
}
