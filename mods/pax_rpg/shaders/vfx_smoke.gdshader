// Дым из настоящей симуляции (pax_rpg/dev/vfx/sim: smoke_sim.py → make_smoke_atlas.py → textures/vfx/sim/smoke_puff_*):
// частица — клуб дыма, за жизнь частицы проходит 64 кадра (клубится, растёт, тает), кадр «дотягивается» к следующему
// по карте движения. Свет — «с 6 сторон» (6-way lighting, как в больших играх): клуб отрендерен с солнцем справа,
// слева, сверху, снизу, спереди и сзади, и в light() каждый настоящий свет сцены — солнце, луна, огонь жаровни —
// смешивает эти 6 картинок по своему направлению. Поэтому дым днём светлый сверху и тёмный снизу, на закате
// розовеет с одной стороны, а над огнём рыжий снизу; против солнца светится по краю. Тень зданий на него ложится.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform sampler2D atlas_a : hint_default_black, filter_linear_mipmap, repeat_disable;   // свет справа, сверху, спереди; плотность
uniform sampler2D atlas_b : hint_default_black, filter_linear_mipmap, repeat_disable;   // слева, снизу, сзади
uniform sampler2D flow_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 flow_uv = vec2(0.1, 0.1);         // make_smoke_atlas.py: FLOW_UV
uniform float density = 1.0;
uniform float light_k = 1.0;
uniform float soft = 0.6;                      // мягкий срез о крыши и землю, м
varying vec3 v_right;
varying vec3 v_up;
varying vec3 m_pos;                            // свет справа, сверху, спереди
varying vec3 m_neg;                            // слева, снизу, сзади
varying float v_frame;

const float G = 8.0;

void vertex() {
	// billboard частицы с поворотом (INSTANCE_CUSTOM.x), как у StandardMaterial BILLBOARD_PARTICLES
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float c = cos(INSTANCE_CUSTOM.x), s = sin(INSTANCE_CUSTOM.x);
	w = w * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * w;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_right = normalize(MODELVIEW_MATRIX[0].xyz);
	v_up = normalize(MODELVIEW_MATRIX[1].xyz);
	v_frame = clamp(INSTANCE_CUSTOM.z, 0.0, 1.0) * 63.0;            // кадр флипбука частицы (anim_speed 1 — весь атлас за жизнь)
}

vec2 cell(float i, vec2 uv) {
	return (vec2(mod(i, G), floor(i / G)) + clamp(uv, vec2(0.003), vec2(0.997))) / G;
}

void fragment() {
	float f = v_frame;
	float i0 = floor(f);
	float i1 = min(i0 + 1.0, 63.0);
	float k = f - i0;
	vec2 fl = (texture(flow_tex, cell(i0, UV)).rg - 0.5) * flow_uv;
	vec2 ua = cell(i0, UV - fl * k), ub = cell(i1, UV + fl * (1.0 - k));
	vec4 a = mix(texture(atlas_a, ua), texture(atlas_a, ub), k);
	vec3 b = mix(texture(atlas_b, ua).rgb, texture(atlas_b, ub).rgb, k);
	m_pos = a.rgb;
	m_neg = b;
	float amb = (a.r + a.g + a.b + b.r + b.g + b.b) / 6.0;          // рассеянный свет неба — по средней освещённости
	ALBEDO = COLOR.rgb * (0.25 + 0.75 * amb);
	NORMAL = vec3(0.0, 0.0, 1.0);
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 wp = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, d) * 2.0 - 1.0, 1.0);
#else
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
#endif
	wp.xyz /= wp.w;
	float fade = clamp((VERTEX.z - wp.z) / soft, 0.0, 1.0) * clamp(-VERTEX.z / 1.5, 0.0, 1.0);   // и у самой камеры
	ALPHA = clamp(a.a * density * COLOR.a, 0.0, 1.0) * fade;
}

void light() {
	vec3 l = vec3(dot(LIGHT, v_right), dot(LIGHT, v_up), LIGHT.z);  // свет в осях клуба (z — к камере)
	vec3 w = l * l;
	vec3 m = mix(m_neg, m_pos, step(0.0, l));
	float sixway = dot(w, m);
	float amb = (m_pos.r + m_pos.g + m_pos.b + m_neg.r + m_neg.g + m_neg.b) / 6.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * sixway / max(0.25 + 0.75 * amb, 0.05) * light_k / PI;
}
