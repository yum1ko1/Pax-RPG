// Дрожание горячего воздуха над огнём (vfx.gd → sim_flame): то, что за огнём, «плывёт» — свет преломляется
// в струе горячего газа. Вертикальный billboard над пламенем; два слоя шума бегут вверх и сдвигают картинку экрана;
// сила — у основания струи, к верху и к краям тает. Вблизи и днём это главный признак живого жара.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float strength = 0.012;
uniform float speed = 1.6;
varying float ph;

void vertex() {
	ph = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 10.0;
	vec3 at = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), vec4(at, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float y = 1.0 - UV.y;
	float t = TIME * speed + ph;
	vec2 u1 = UV * vec2(1.5, 1.0) + vec2(0.0, t * 0.6);
	vec2 u2 = UV * vec2(3.1, 2.2) + vec2(0.3, t * 1.3);
	vec2 n1 = vec2(texture(noise_tex, u1).r, texture(noise_tex, u1 + vec2(0.37, 0.61)).r) - 0.5;
	vec2 n2 = vec2(texture(noise_tex, u2).r, texture(noise_tex, u2 + vec2(0.71, 0.13)).r) - 0.5;
	float mask = smoothstep(0.0, 0.15, y) * smoothstep(1.0, 0.35, y) * smoothstep(0.5, 0.15, abs(UV.x - 0.5));
	float far = clamp(-VERTEX.z / 25.0, 0.0, 1.0);                     // вдали дрожь не видна — и не нужна
	vec2 off = (n1 + n2 * 0.6) * strength * mask * (1.0 - far) / max(-VERTEX.z * 0.25, 1.0);
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = smoothstep(0.0, 0.35, mask) * (1.0 - far);              // плавно: прозрачное позади (стекло, порталы) не вырезается
}
