// Порыв ветра (аниме): тонкая белая изогнутая линия. Квад — вдоль ветра (UV.x), линия бежит по нему: голова
// впереди, хвост тает; по ходу «жизни» (life 0..1) появляется и гаснет. Вертикаль квада — место для изгиба.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float life = 0.0;
uniform float phase = 0.0;
uniform float curl = 0.3;

void fragment() {
	float x = UV.x;
	// центр линии гнётся волной и завитком к концу
	float cy = 0.5 + sin(x * 6.0 + phase) * 0.18 * curl * 2.0 + pow(x, 6.0) * curl * 0.8 * sin(phase);
	float d = abs(UV.y - cy);
	float w = mix(0.02, 0.07, sin(x * 3.14159));               // тоньше к концам
	float line = smoothstep(w, w * 0.3, d) + 0.35 * smoothstep(w * 3.5, w, d);   // линия и мягкое свечение
	// бегущий отрезок: голова движется по квадy за жизнь
	float head = mix(-0.2, 1.3, life);
	float seg = smoothstep(head - 0.7, head - 0.1, x) * (1.0 - smoothstep(head - 0.02, head + 0.02, x));
	float fade = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.7, 1.0, life));
	ALBEDO = vec3(1.0, 0.97, 1.0);
	ALPHA = line * seg * fade * 0.85;
}
