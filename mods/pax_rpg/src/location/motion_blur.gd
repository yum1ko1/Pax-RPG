extends CompositorEffect
## Размытие в движении (в движке его нет): после прозрачных — каждый пиксель размывается вдоль своего вектора
## движения (буфер скоростей, тот же, что у TAA). Камера стоит — резко; разворот, бег, взмах меча — смазано.
## shutter — доля кадра, пока «открыт затвор» (0.5 — как у кино, 180°). Ошибка Vulkan — эффект выключается сам.

var shutter := 0.5
var samples := 10

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _copy: RID                     # копия кадра: читаем из неё, пишем в кадр
var _copy_size := Vector2i.ZERO
var _failed := false

const GLSL := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D src;
layout(set = 0, binding = 1) uniform sampler2D vel;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform Params {
	vec2 size;
	float shutter;
	float samples;
} p;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / p.size;
	vec2 v = texture(vel, uv).xy * p.shutter;           // смещение за кадр в долях экрана
	float len = length(v * p.size);
	if (len < 0.75) {                                   // меньше пикселя — не трогаем (резкость на месте)
		imageStore(dst, px, texture(src, uv));
		return;
	}
	v *= min(1.0, 48.0 / len);                          // не длиннее 48 px
	int n = int(p.samples);
	vec4 acc = vec4(0.0);
	for (int i = 0; i < n; i++) {
		float t = (float(i) + 0.5) / float(n) - 0.5;
		acc += texture(src, uv - v * t);
	}
	imageStore(dst, px, acc / float(n));
}
"""


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(_init_rd)


func _init_rd() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_failed = true
		return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_warning("Pax RPG motion blur: " + spirv.compile_error_compute)
		_failed = true
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_failed = true
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for r: RID in [_copy, _pipeline, _shader, _sampler]:
			if r.is_valid():
				_rd.free_rid(r)


func _ensure_copy(size: Vector2i) -> void:
	if _copy.is_valid() and _copy_size == size:
		return
	if _copy.is_valid():
		_rd.free_rid(_copy)
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.width = size.x
	tf.height = size.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	_copy = _rd.texture_create(tf, RDTextureView.new())
	_copy_size = size


func _render_callback(type: int, render_data: RenderData) -> void:
	if _failed or _rd == null or not _pipeline.is_valid() or type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	_ensure_copy(size)
	var push := PackedFloat32Array([float(size.x), float(size.y), shutter, float(samples)]).to_byte_array()
	var groups := Vector3i(ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	for view: int in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var vel := buffers.get_velocity_layer(view)
		if not color.is_valid() or not vel.is_valid():
			return
		var err := _rd.texture_copy(color, _copy, Vector3.ZERO, Vector3.ZERO, Vector3(size.x, size.y, 1), 0, 0, 0, 0)
		if err != OK:
			push_warning("Pax RPG motion blur: no copy of the frame (%d) — off" % err)
			_failed = true
			return
		var u_src := RDUniform.new()
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_src.binding = 0
		u_src.add_id(_sampler)
		u_src.add_id(_copy)
		var u_vel := RDUniform.new()
		u_vel.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_vel.binding = 1
		u_vel.add_id(_sampler)
		u_vel.add_id(vel)
		var u_dst := RDUniform.new()
		u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_dst.binding = 2
		u_dst.add_id(color)
		var uset := UniformSetCacheRD.get_cache(_shader, 0, [u_src, u_vel, u_dst])
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
		_rd.compute_list_bind_uniform_set(cl, uset, 0)
		_rd.compute_list_set_push_constant(cl, push, push.size())
		_rd.compute_list_dispatch(cl, groups.x, groups.y, groups.z)
		_rd.compute_list_end()
