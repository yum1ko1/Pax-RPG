// Радужная сфера лута: цвета переливаются по кругу (поворот оттенка во времени), серое и чёрное (тушь) не меняется.
shader_type canvas_item;

uniform float speed = 0.22;

vec3 hue(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb = clamp(hue(c.rgb, TIME * speed * 6.2832 + UV.x * 1.5), 0.0, 1.0);
	COLOR = c;
}
