// Рамка подсказки инвентаря цветом редкости / маны: яркость золотой рамки × цвет (src/location/inv/item_tip.gd).
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amount = 0.85;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 t = tint.rgb * l * 1.75;
	COLOR = vec4(mix(c.rgb, t, amount), c.a);
}
