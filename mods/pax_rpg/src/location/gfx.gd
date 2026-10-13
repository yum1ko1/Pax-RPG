extends Node
## Качество картинки локации (концепт — pax_rpg/docs/Графика_концепт.md, этап 1). Всё из config/location.json → gfx,
## любой пункт выключается там же:
##  • отражённый свет: SDFGI (каскады вокруг камеры) + SSIL — стены подсвечивают землю, под навесами не плоско;
##  • TAA вместо MSAA (листва, черепица, блики без ряби; SSAO/SSR/SSIL чище) или FSR2; debanding — небо без полос;
##  • солнце: мягкие тени с размытием по угловому размеру диска (PCSS), атлас крупнее — на время локации;
##  • тени фонарей и костров: тени — у ближайших к камере lamp_shadows огней, набор меняется на ходу;
##  • туман: анизотропия к солнцу (лучи видны против света), гуще у земли;
##  • камера: автоэкспозиция (из тени на солнце глаз привыкает), лёгкая размытость дальнего плана;
##  • проба отражений переснимается со сменой часа — ночью стёкла не отражают день;
##  • контровой свет героя: холодный свет из-за спины (относительно камеры) только на героя — силуэт не тонет в фоне.
##  • ветер и топтание: глобальные параметры шейдеров pax_rpg_wind (xy — направление, z — сила, w — порыв; ведёт
##    wind.gd) и pax_rpg_player (где герой — трава расступается) — их читают grass/foliage/steppe/mountain.gdshader;
##  • дымка у костров и жаровен (FogVolume) — огонь светится в воздухе;
##  • размытие в движении (motion_blur.gd) — по векторам движения TAA;
##  • объёмные облака и блики с лучами солнца — эффекты игры (Pax.graphics.clouds / lens) на камере локации.
## Оптимизация: окклюзия (Hi-Z движка: окклюдеры стен и домов — city.gd) — заслонённое не рисуется; каскады теней
## распределены к герою (ближний — несколько метров, чёткий); LOD-порог сеток — mesh_lod_px.
## Герой и враги в SDFGI — динамические (иначе оставляют «тень-призрак» в отражённом свете).

const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")
const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
const MotionBlur := preload("res://mods/pax_rpg/src/location/motion_blur.gd")

var cfg: Dictionary = {}
var view: SubViewport
var cam: Camera3D
var player: Node3D
var sun: DirectionalLight3D
var lights: Array = []             # [OmniLight3D, энергия ночью] — как у daynight.gd
var probe: ReflectionProbe
var daynight: DayNight
var _fplus := false
var _shadow_t := 0.0
var _dyn_t := 0.0
var _probe_step := -1
var _rim: DirectionalLight3D
const RIM_LAYER := 1 << 19          # слой видимости 20 — только герой, на него светит контровой свет
var _time := 0.0                   # время ветра для шейдеров; иай замораживает этот узел — и трава замирает
var _saved := {}
var _mb: MotionBlur
var _clouds: CompositorEffect
var _lens: CompositorEffect                   # глобальные настройки теней игры — вернуть, когда локация уходит


func setup(c: Dictionary) -> void:
	name = "PaxRpgGfx"
	cfg = c
	_fplus = RenderingServer.get_current_rendering_method() == "forward_plus"
	ensure_globals()


## Глобальные параметры шейдеров мода — до того, как скомпилируется первый шейдер, который их читает. Один раз
## за сессию (global_shader_parameter_get_list нельзя: вне редактора она ждёт поток рендера и тормозит игру).
static var _globals_added := false


static func ensure_globals() -> void:
	if _globals_added:
		return
	_globals_added = true
	RenderingServer.global_shader_parameter_add(&"pax_rpg_wind", RenderingServer.GLOBAL_VAR_TYPE_VEC4,
		Vector4(0.95, 0.3, 0.5, 0.0))
	RenderingServer.global_shader_parameter_add(&"pax_rpg_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add(&"pax_rpg_player", RenderingServer.GLOBAL_VAR_TYPE_VEC4,
		Vector4(0.0, -1000.0, 0.0, 0.0))


func _b(key: String, fallback: bool) -> bool:
	return bool(cfg.get(key, fallback))


func _f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


## Сглаживание и чёткость — до первого кадра локации.
func apply_viewport(v: SubViewport) -> void:
	view = v
	match str(cfg.get("aa", "taa")):
		"taa":
			v.msaa_3d = Viewport.MSAA_DISABLED
			v.use_taa = true
		"fsr2":                                          # своё временное сглаживание + рендер в меньшем размере
			v.msaa_3d = Viewport.MSAA_DISABLED
			v.use_taa = false
			v.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			v.scaling_3d_scale = clampf(_f("fsr_scale", 0.77), 0.5, 1.0)
		_:
			v.msaa_3d = Viewport.MSAA_2X
	v.use_debanding = _b("debanding", true)
	v.use_occlusion_culling = _b("occlusion", true)      # дома и стены (OccluderInstance3D) заслоняют то, что за ними
	v.mesh_lod_threshold = _f("mesh_lod_px", 1.0)        # пикселей ошибки LOD: больше — проще сетки вдали
	v.positional_shadow_atlas_size = int(_f("lamp_shadow_atlas", 4096))


func apply_env(env: Environment, we: WorldEnvironment) -> void:
	if _fplus and str(cfg.get("gi", "sdfgi")) == "sdfgi":
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true                   # меньше протеканий света сквозь стены
		env.sdfgi_read_sky_light = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = _f("gi_cell", 0.2)       # мельче — точнее у героя, ближний каскад меньше
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_bounce_feedback = _f("gi_bounce", 0.5)
		env.sdfgi_energy = _f("gi_energy", 1.0)
	if _fplus and _b("ssil", true):
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.ssil_intensity = _f("ssil_intensity", 1.0)
		env.ssil_normal_rejection = 1.0
	env.fog_height = _f("fog_height", 6.0)               # у земли дымка гуще: улицы вдали тонут мягче
	env.fog_height_density = _f("fog_height_density", 0.008)
	env.volumetric_fog_anisotropy = _f("fog_anisotropy", 0.6)   # против солнца — видимые лучи
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = _b("auto_exposure", true)
	ca.auto_exposure_scale = _f("exposure_scale", 0.4)
	ca.auto_exposure_speed = _f("exposure_speed", 0.6)
	ca.auto_exposure_min_sensitivity = _f("exposure_min_iso", 60.0)     # узкий диапазон: не больше ±1 ступени
	ca.auto_exposure_max_sensitivity = _f("exposure_max_iso", 180.0)
	var far := _f("dof_far", 80.0)
	if far > 0.0:
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = far
		ca.dof_blur_far_transition = _f("dof_far_transition", 70.0)
		ca.dof_blur_amount = _f("dof_amount", 0.04)
	we.camera_attributes = ca
	var mb := _f("motion_blur", 0.5)
	if _fplus and mb > 0.0:
		_mb = MotionBlur.new()
		_mb.shutter = mb
		var comp := Compositor.new()
		comp.compositor_effects = [_mb]
		we.compositor = comp


## Облака и блики — эффекты игры на камеру (их у камеры свой Compositor — он главнее окружения, поэтому размытие
## в движении переезжает в конец его списка). Игрок выключил эффект в настройках — его просто нет.
func apply_camera(c: Camera3D, s: DirectionalLight3D) -> void:
	cam = c
	var t0 := Time.get_ticks_msec()
	if _b("clouds", true) and Pax.graphics.available("clouds"):
		_clouds = Pax.graphics.clouds(c, {"clouds_coverage": _f("clouds_coverage", 0.42)})
	print("[pax_rpg] load: clouds %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	if _b("lens", true) and Pax.graphics.available("lens"):
		_lens = Pax.graphics.lens(c, {"sun_color": Color(1.0, 0.82, 0.64, 0.22)}, s)
	print("[pax_rpg] load: lens %d ms" % (Time.get_ticks_msec() - t0))
	if _mb != null and c.compositor != null:
		var list: Array[CompositorEffect] = c.compositor.compositor_effects
		if not list.has(_mb):
			list.append(_mb)
			c.compositor.compositor_effects = list


func _drop_camera_effects() -> void:
	if is_instance_valid(cam):
		for e: CompositorEffect in [_clouds, _lens]:
			if e != null:
				Pax.graphics.remove_effect(cam, e)
	_clouds = null
	_lens = null


func apply_sun(s: DirectionalLight3D) -> void:
	s.light_angular_distance = _f("sun_angle", 0.6)      # мягкий край тени растёт с расстоянием до заслона
	s.shadow_blur = 1.0
	s.directional_shadow_blend_splits = true              # без ступеньки на границе каскадов
	s.directional_shadow_max_distance = _f("sun_shadow_distance", 110.0)
	# каскады: доли дальности теней — 1-й до ~6 м (герой и враги резко), 2-й ~20 м, 3-й ~50 м, 4-й до конца
	var sp: Array = cfg.get("shadow_splits", [0.06, 0.18, 0.45])
	if sp.size() >= 3:
		s.directional_shadow_split_1 = float(sp[0])
		s.directional_shadow_split_2 = float(sp[1])
		s.directional_shadow_split_3 = float(sp[2])
	s.directional_shadow_fade_start = 0.85


## Глобальные настройки теней — на время локации (атлас солнца, мягкий фильтр); restore_globals() возвращает.
func push_globals() -> void:
	if not _saved.is_empty():
		return
	_saved = {
		"atlas": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)),
		"dq": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)),
		"pq": int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)),
	}
	RenderingServer.directional_shadow_atlas_set_size(int(_f("sun_shadow_atlas", 8192)), true)
	var q := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if _b("soft_shadows", true) else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)


func restore_globals() -> void:
	if _saved.is_empty():
		return
	RenderingServer.directional_shadow_atlas_set_size(int(_saved["atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(_saved["dq"]) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(_saved["pq"]) as RenderingServer.ShadowQuality)
	_saved = {}


func _exit_tree() -> void:
	restore_globals()
	_drop_camera_effects()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_time += delta
	RenderingServer.global_shader_parameter_set(&"pax_rpg_time", _time)
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_t = 0.5
		_lamp_shadows()
	_dyn_t -= delta
	if _dyn_t <= 0.0:
		_dyn_t = 1.0
		_mark_dynamic()
	_refresh_probe()
	_rim_follow()
	if is_instance_valid(player):
		var pp := player.global_position
		RenderingServer.global_shader_parameter_set(&"pax_rpg_player", Vector4(pp.x, pp.y, pp.z, 0.0))
	Prof.add("графика", t0)


## Тени — у ближайших к камере горящих огней; дальние без теней (каждая тень огня — 6 проходов сцены).
func _lamp_shadows() -> void:
	var n := int(_f("lamp_shadows", 6))
	if lights.is_empty() or not is_instance_valid(cam):
		return
	if not _fogs_made:
		_fire_fog()
	var cp := cam.global_position
	var near: Array = []
	for l: Array in lights:
		var ol := l[0] as OmniLight3D
		if not is_instance_valid(ol):
			continue
		ol.light_size = 0.12                             # мягкий край тени фонаря
		var d := ol.global_position.distance_to(cp)
		if ol.visible and ol.light_energy > 0.1 and d < 35.0:
			near.append([d, ol])
		else:
			ol.shadow_enabled = false
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in near.size():
		(near[i][1] as OmniLight3D).shadow_enabled = i < n


## Двигающиеся тела (герой, враги, жители) — динамические для отражённого света; новые (волны арены) — тоже.
func _mark_dynamic() -> void:
	if not is_instance_valid(view):
		return
	for c: Node in view.get_children():
		if c is CharacterBody3D and (c == player or not c.has_meta("pax_rpg_gi")):   # герою надевают вещи — каждый раз
			c.set_meta("pax_rpg_gi", true)
			var stack: Array = [c]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				stack.append_array(n.get_children())
				if n is GeometryInstance3D:
					(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
					if c == player and n is VisualInstance3D:
						(n as VisualInstance3D).layers |= RIM_LAYER


## Каждые полчаса мира проба отражений переснимается (сдвиг на миллиметр — Godot снимает её заново).
func _refresh_probe() -> void:
	if not is_instance_valid(probe) or daynight == null or not is_instance_valid(daynight):
		return
	var step := int(daynight.hour * 2.0)
	if step == _probe_step:
		return
	var first := _probe_step < 0
	_probe_step = step
	if not first:
		probe.position.y += 0.001 if step % 2 == 0 else -0.001


## Контровой свет: позади героя от камеры, чуть сверху, к камере; ночью сильнее (днём силуэт и так читается).
func _rim_follow() -> void:
	if not is_instance_valid(cam) or not is_instance_valid(player):
		return
	var energy := _f("rim", 0.7)
	if energy <= 0.0:
		return
	if _rim == null:
		_rim = DirectionalLight3D.new()
		_rim.name = "PaxRpgRim"
		_rim.light_color = Color(0.62, 0.8, 1.0)
		_rim.light_specular = 1.6
		_rim.shadow_enabled = false
		_rim.light_cull_mask = RIM_LAYER
		_rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY      # не рисует второе солнце на небе
		view.add_child(_rim)
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		return
	var dir := (-f.normalized() + Vector3(0, -0.55, 0)).normalized()    # свет летит из-за героя на камеру
	_rim.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	var night := 1.0
	if is_instance_valid(sun):
		night = 1.0 - clampf(sun.light_energy / 1.35, 0.0, 1.0) * 0.6
	_rim.light_energy = energy * night


var _fogs_made := false


## Дымка у живого огня: эллипсоид тумана вокруг каждого костра и жаровни (виден при объёмном тумане).
func _fire_fog() -> void:
	_fogs_made = true
	if not _fplus or _f("fire_fog", 0.35) <= 0.0:
		return
	var fm := FogMaterial.new()
	fm.density = _f("fire_fog", 0.35)
	fm.albedo = Color(1.0, 0.86, 0.76)
	fm.height_falloff = 0.6
	fm.edge_fade = 0.6
	var made := 0
	for l: Array in lights:
		var ol := l[0] as OmniLight3D
		if not is_instance_valid(ol) or not (ol is Vfx.Flicker) or made >= 48:
			continue
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fv.size = Vector3(3.6, 3.0, 3.6)
		fv.material = fm
		ol.get_parent().add_child(fv)
		fv.global_position = ol.global_position + Vector3(0, 0.4, 0)
		made += 1
