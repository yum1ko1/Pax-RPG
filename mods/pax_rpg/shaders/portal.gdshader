// Лёгкое свечение выхода из города: мерцающая завеса сакура → лазурь, гаснет к краям и вверх.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 pink : source_color = vec4(1.0, 0.45, 0.8, 1.0);
uniform vec4 blue : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float strength = 0.9;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x);
	float h = 1.0 - uv.y;                                  // 0 — низ, 1 — верх
	float fade = smoothstep(1.0, 0.15, h) * smoothstep(0.0, 0.08, h);
	float t = TIME * 0.35;
	float n = noise(vec2(uv.x * 5.0, h * 3.0 - t * 2.0)) * 0.6 + noise(vec2(uv.x * 11.0 + 3.0, h * 7.0 - t * 3.5)) * 0.4;
	float streak = pow(n, 2.2);
	vec3 col = mix(pink.rgb, blue.rgb, clamp(h * 1.2 + n * 0.3 - 0.2, 0.0, 1.0));
	ALBEDO = col * (0.35 + 1.4 * streak) * edge * fade * strength;
}
