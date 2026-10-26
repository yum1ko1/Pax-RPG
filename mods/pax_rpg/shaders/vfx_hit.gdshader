// Эффект удара (src/location/hit_vfx.gd): одна статичная маска (textures/vfx/hit/*.png, GPT-референс → make_hit_masks.py)
// оживает шейдером — так делают удары в Genshin и DMC. R — форма, G — порядок эрозии: progress 0..1 съедает маску по
// порогу (сначала тает то, где G ниже), по кромке выгорания — золотистый ободок. reveal — сколько мазка вдоль U уже
// прорисовано (укол «выстреливает» от хвоста к острию). Цвет — по яркости формы: белое ядро → цвет маны → тёмная кромка.
//   mode 0 — billboard (звезда вспышки), 1 — вдоль оси X узла, повёрнут к камере (луч укола, мазок),
//   2 — как стоит узел (кольцо волны поперёк удара).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.92);
uniform vec3 mid : source_color = vec3(1.0, 0.08, 0.16);
uniform vec3 edge : source_color = vec3(0.32, 0.0, 0.03);
uniform vec3 rim : source_color = vec3(1.0, 0.7, 0.32);
uniform float energy = 3.0;
uniform float soft = 0.08;
uniform float rim_k = 0.8;
uniform int mode = 0;
instance uniform float progress = 0.0;
instance uniform float reveal = 2.0;
instance uniform float glow = 1.0;
instance uniform float roll = 0.0;

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	if (mode == 0) {
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * sx, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * sy, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz, 0.0), vec4(at, 1.0));
	} else if (mode == 1) {
		vec3 ax = MODEL_MATRIX[0].xyz;
		vec3 to_cam = normalize(cam - at);
		vec3 side = cross(normalize(ax), to_cam);
		side = length(side) > 0.001 ? normalize(side) : vec3(0.0, 1.0, 0.0);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(ax, 0.0), vec4(side * length(MODEL_MATRIX[1].xyz), 0.0),
			vec4(to_cam, 0.0), vec4(at, 1.0));
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	if (roll != 0.0) {
		vec2 d = uv - 0.5;
		float c = cos(roll), s = sin(roll);
		uv = vec2(c * d.x - s * d.y, s * d.x + c * d.y) + 0.5;
	}
	vec4 m = texture(mask_tex, uv);
	float shape = m.r;
	float vis = smoothstep(reveal, reveal - 0.06, uv.x);
	float thr = progress * (1.0 + soft);
	float keep = smoothstep(thr, thr + soft, m.g);
	float burn = (1.0 - smoothstep(0.0, soft * 1.4, abs(m.g - thr - soft * 0.5))) * step(0.001, progress);
	float a = shape * keep * vis;
	float heat = clamp(shape * (1.0 - 0.45 * progress), 0.0, 1.0);
	vec3 col = mix(edge, mid, smoothstep(0.0, 0.5, heat));
	col = mix(col, core, smoothstep(0.62, 0.97, heat));
	ALBEDO = (col * a + rim * burn * shape * vis * rim_k) * energy * glow;
	ALPHA = clamp(a + burn * shape * vis * 0.5, 0.0, 1.0);
}
