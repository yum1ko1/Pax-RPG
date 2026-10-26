// Огонь из настоящей симуляции газа (pax_rpg/dev/vfx/sim: Blender Mantaflow → make_fire_atlas.py → textures/vfx/sim).
// Атлас 8×8 кадров петли: R — свечение пламени (√), G — освещённость дыма, B — плотность дыма; flow_tex — куда
// сдвигается каждая точка к следующему кадру: кадр «дотягивается» к следующему по потоку (а не мигает сменой
// картинок), так 64 кадра идут плавно и медленно. Цвет пламени — по жару, как у раскалённого газа: тёмно-красный
// край → оранжевый → жёлто-белое ядро (HDR — ловит bloom). Дым — свой свет сверху (небо, луна) + рыжий снизу от огня.
// Цилиндрический billboard держит вертикаль; у каждого огня своя фаза (по месту) — соседние не горят в такт.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 flow_uv = vec2(0.2, 0.1);        // 1.0 в карте потока — столько долей кадра (make_fire_atlas.py: FLOW_UV, кадр 1:2)
uniform float fps = 30.0;
uniform float energy = 3.0;
uniform vec3 hot : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 mid : source_color = vec3(1.0, 0.38, 0.06);
uniform vec3 cool : source_color = vec3(0.55, 0.05, 0.01);
uniform vec3 smoke_col : source_color = vec3(0.16, 0.15, 0.15);
uniform vec3 sky_light : source_color = vec3(0.55, 0.6, 0.75);
uniform float smoke_k = 1.0;
uniform float soft = 0.25;                    // мягкий срез о чашу и землю, м
instance uniform float push = 0.0;
instance uniform float speed = 1.0;
varying float ph;

const float G = 8.0;

void vertex() {
	ph = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec3 at = MODEL_MATRIX[3].xyz;
	vec3 to_cam = (INV_VIEW_MATRIX[3].xyz - at) * vec3(1.0, 0.0, 1.0);
	at += to_cam * (push / max(length(to_cam), 0.001));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), vec4(at, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec2 cell(float i, vec2 uv) {
	float x = mod(i, G);
	float y = floor(i / G);
	return (vec2(x, y) + clamp(uv, vec2(0.002), vec2(0.998))) / G;
}

void fragment() {
	float t = TIME * fps * speed / 64.0 + ph;
	float f = fract(t) * 64.0;
	float i0 = floor(f);
	float i1 = mod(i0 + 1.0, 64.0);
	float k = f - i0;
	vec2 uv = UV;
	vec2 fl = (texture(flow_tex, cell(i0, uv)).rg - 0.5) * flow_uv;
	vec3 a = texture(atlas, cell(i0, uv - fl * k)).rgb;
	vec3 b = texture(atlas, cell(i1, uv + fl * (1.0 - k))).rgb;
	vec3 s = mix(a, b, k);
	float e = pow(s.r, 1.2);                                        // свечение (в атласе — √; середину языков чуть приподнять)
	float dens = clamp(s.b * smoke_k, 0.0, 1.0);
	// жар → цвет: чем ярче газ, тем горячее
	vec3 c = mix(cool, mid, smoothstep(0.03, 0.3, e));
	c = mix(c, hot, smoothstep(0.45, 0.95, e));
	vec3 fire = c * pow(e, 1.25) * energy;
	// дым: свет неба/луны по запечённому освещению + отсвет огня снизу (сильнее у основания)
	float low = 1.0 - UV.y;
	vec3 sm = smoke_col * (0.35 + 0.9 * s.g) * sky_light + mid * 0.5 * smoothstep(0.9, 0.35, low) * dens;
	// мягкие частицы: тает, где под ним близко чаша или земля
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 wp = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, d) * 2.0 - 1.0, 1.0);
#else
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
#endif
	wp.xyz /= wp.w;
	float fade = clamp((VERTEX.z - wp.z) / soft, 0.0, 1.0);          // обе глубины отрицательны: сцена дальше — wp.z меньше
	float cov = dens * 0.9;
	ALBEDO = (sm * cov + fire) * fade;
	ALPHA = cov * fade;
}
