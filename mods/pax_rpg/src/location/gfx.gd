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
##  • объёмные облака и блики с лучами солнца — эффекты игры (Pax.graphics.clouds / lens) на камере локации;
##  • слой камеры (shaders/lens.gdshader на контейнере вида, без потока рендера): цифровая резкость, сияние солнца,
##    размытие при повороте камеры (как в Sekiro / The Witcher 3); «съёмочные» приёмы (бочка, аберрация, зерно, грязь
##    на линзе, «призраки», ручная камера — camera_sway) есть, но в RPG выключены (config gfx.lens_*).
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
	# погода (weather.gd): x — мокрость, y — дождь, z — пасмурность, w — туман низин
	RenderingServer.global_shader_parameter_add(&"pax_rpg_weather", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)


## Значение настройки: своё у игрока (меню «Графика», настройки мода gfx_<ключ>) главнее config/location.json.
func _v(key: String, fallback: Variant) -> Variant:
	return _ovr[key] if _ovr.has(key) else cfg.get(key, fallback)


func _b(key: String, fallback: bool) -> bool:
	return bool(_v(key, fallback))


func _f(key: String, fallback: float) -> float:
	return float(_v(key, fallback))


## Ключи меню «Графика» (pause_menu.gd) — их значения берутся из настроек мода.
const MENU_KEYS := ["upscale", "resolution", "fps_limit", "vsync", "gi", "ssil", "ssao", "ssr", "aa", "fsr_scale", "lamp_shadows", "glow", "lens_sharpen", "cam_blur",
	"flare", "auto_exposure", "grass_density"]
var _ovr := {}
var _env: Environment
var _we: WorldEnvironment


## Свои настройки игрока (зовёт location.gd, когда mod уже есть).
func load_overrides() -> void:
	if mod == null:
		return
	for k: String in MENU_KEYS:
		var v: Variant = mod.get_setting("gfx_" + k, null)
		if v != null:
			_ovr[k] = v


## Меню «Графика»: значение сменилось — применить сразу (трава — со следующего входа в город).
func set_option(key: String, value: Variant) -> void:
	_ovr[key] = value
	match key:
		"aa", "fsr_scale", "resolution", "upscale":
			if is_instance_valid(view):
				_apply_aa(view)
		"fps_limit", "vsync":
			apply_frame_limits()
		"lens_sharpen":
			if lens_mat != null:
				lens_mat.set_shader_parameter("sharpen", float(value))
		"gi", "ssil", "ssao", "ssr", "glow", "auto_exposure":
			if _env != null and is_instance_valid(_we):
				apply_env(_env, _we)


func _gi_on() -> bool:
	var g: Variant = _v("gi", "sdfgi")
	return (g is bool and bool(g)) or str(g) == "sdfgi"


## Сглаживание и чёткость — до первого кадра локации.
func apply_viewport(v: SubViewport) -> void:
	view = v
	if not v.get_tree().node_added.is_connected(_on_node_added):
		v.get_tree().node_added.connect(_on_node_added)
	_apply_aa(v)
	v.use_debanding = _b("debanding", true)
	_lens_layer(v)
	v.use_occlusion_culling = _b("occlusion", false)     # выкл.: на краях стен модели пропадали и появлялись
	v.mesh_lod_threshold = _f("mesh_lod_px", 1.0)        # пикселей ошибки LOD: больше — проще сетки вдали
	v.set("anisotropic_filtering_level", 4)              # 16× анизотропия: земля и дороги чёткие под углом
	v.positional_shadow_atlas_size = int(_f("lamp_shadow_atlas", 4096))
	# все ячейки атласа теней огней одного размера (16 × 1024² в 4096²): Godot не перекладывает тени между ячейками
	# разного размера по мере того, как огни растут и уменьшаются на экране, — тени не скачут по чёткости
	for q: int in 4:
		v.set_positional_shadow_atlas_quadrant_subdiv(q, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)


## Апскейл FSR 2 режимами, как у DLSS (DLSS в Godot недоступен — закрытая библиотека NVIDIA, нужен C++-модуль движка):
## «Качество» 67 %, «Баланс» 58 %, «Производительность» 50 % разрешения, резкость под каждый режим.
func _apply_upscale(v: SubViewport) -> void:
	var mode := str(_v("upscale", "native"))
	var k: float = {"quality": 0.67, "balanced": 0.58, "performance": 0.5}.get(mode, 0.0)
	if k <= 0.0:
		return
	v.use_taa = false
	v.msaa_3d = Viewport.MSAA_DISABLED
	v.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	v.scaling_3d_scale = k
	v.fsr_sharpness = {"quality": 0.2, "balanced": 0.1, "performance": 0.0}.get(mode, 0.2)


## Разрешение 3D-картинки (меню «Графика» → resolution: native | 1080 | 1440 | 2160): масштаб рендера к высоте окна.
## Выше окна (4K на мониторе 1440p) — суперсэмплинг: рендер больше и сжимается до окна (резче, дороже);
## ниже — рендер меньше и растягивается (FSR 2, если выбран, иначе билинейно).
func _apply_resolution(v: SubViewport) -> void:
	var res := str(_v("resolution", "native")).to_int()
	if res <= 0:
		return
	var win_h := float(maxi(DisplayServer.window_get_size().y, 1))
	var k := clampf(float(res) / win_h, 0.25, 2.0)
	if v.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and k <= 1.0:
		v.scaling_3d_scale = k * v.scaling_3d_scale
	else:
		v.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		v.scaling_3d_scale = k


## Частота кадров (меню «Графика»): fps_limit 0 — без ограничения, vsync — вертикальная синхронизация. На время
## локации; leave_frame_limits() возвращает то, что стояло в игре.
var _frame_saved: Array = []


func apply_frame_limits() -> void:
	if _frame_saved.is_empty():
		_frame_saved = [Engine.max_fps, DisplayServer.window_get_vsync_mode()]
	Engine.max_fps = int(float(_v("fps_limit", 0.0)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _b("vsync", false) else DisplayServer.VSYNC_DISABLED)


func leave_frame_limits() -> void:
	if _frame_saved.is_empty():
		return
	Engine.max_fps = int(_frame_saved[0])
	DisplayServer.window_set_vsync_mode(int(_frame_saved[1]) as DisplayServer.VSyncMode)
	_frame_saved = []


## Частицы (огонь, искры, дым, брызги) не отбрасывают тень: они двигаются каждый кадр, и тень огня рядом
## перерисовывалась постоянно — плясала по стенам и стоила проход сцены на каждую тень.
func _on_node_added(n: Node) -> void:
	if (n is GPUParticles3D or n is CPUParticles3D) and is_instance_valid(view) and view.is_ancestor_of(n):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _exit_tree_signals() -> void:
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Сглаживание (меню может менять его на ходу).
func _apply_aa(v: SubViewport) -> void:
	v.use_taa = false
	v.msaa_3d = Viewport.MSAA_DISABLED
	v.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	v.scaling_3d_scale = 1.0
	match str(_v("aa", "taa")):
		"taa":                                           # стабильнее FSR 2: свечение мелких огней не мигает
			v.use_taa = true
		"fsr2":                                          # FSR 2: fsr_scale 1.0 — в родном разрешении, меньше — быстрее
			v.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			v.scaling_3d_scale = clampf(_f("fsr_scale", 1.0), 0.5, 1.0)
			v.fsr_sharpness = _f("fsr_sharpness", 0.15)    # 0 — резче всего, 2 — без повышения резкости
		"msaa":
			v.msaa_3d = Viewport.MSAA_2X
	_apply_upscale(v)
	_apply_resolution(v)


func apply_env(env: Environment, we: WorldEnvironment) -> void:
	_env = env
	_we = we
	env.sdfgi_enabled = _fplus and _gi_on()
	env.ssil_enabled = _fplus and _b("ssil", true)
	env.ssao_enabled = _fplus and _b("ssao", true)
	env.ssr_enabled = _fplus and _b("ssr", true)
	if env.ssr_enabled:                                   # отражения: стёкла, вода, мокрый камень, металл доспеха
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.2
	if env.ssao_enabled:                                  # затенение углов, стыков, под навесами
		env.ssao_radius = 1.1
		env.ssao_intensity = 2.0
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06
		env.ssao_sharpness = 0.98
		env.ssao_light_affect = 0.15                     # чуть и на прямом свете — предметы «садятся» на землю
		env.ssao_ao_channel_affect = 0.5                 # и AO из материалов моделей
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true                   # меньше протеканий света сквозь стены
		env.sdfgi_read_sky_light = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = _f("gi_cell", 0.2)       # мельче — точнее у героя, ближний каскад меньше
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_bounce_feedback = _f("gi_bounce", 0.5)
		env.sdfgi_energy = _f("gi_energy", 1.0)
	if env.sdfgi_enabled:
		env.sdfgi_probe_bias = 1.1
		env.sdfgi_normal_bias = 1.1
	if env.ssil_enabled:
		env.ssil_radius = 5.0
		env.ssil_intensity = _f("ssil_intensity", 1.0)
		env.ssil_sharpness = 0.98
		env.ssil_normal_rejection = 1.0
	# Туман как в The Witcher 3 / Sekiro / Arc Raiders: вблизи (до fog_begin) чисто, дальше дымка растёт,
	# горы уходят в цвет неба, но силуэт читается. Глубинный туман (начало и конец в метрах), а не экспонента от
	# камеры; слоя «у земли» нет (город целиком ниже его — была муть у самого героя); объёмный — тонкий, для лучей.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = _f("fog_begin", 35.0)
	env.fog_depth_end = _f("fog_end", 1500.0)
	env.fog_depth_curve = _f("fog_curve", 1.8)           # >1 — средние планы чище, дымка набирает к дали
	env.fog_density = _f("fog_max", 0.85)                # сколько дымки на самом конце (горы — ~0.6–0.8)
	env.fog_aerial_perspective = _f("fog_aerial", 0.75)  # даль берёт цвет неба — синеет/розовеет, а не сереет
	env.fog_sky_affect = _f("fog_sky", 0.15)
	env.fog_height = _f("fog_height", -2.0)              # лёгкая дымка только в низинах степи
	env.fog_height_density = _f("fog_height_density", 0.0)
	env.volumetric_fog_anisotropy = _f("fog_anisotropy", 0.6)   # против солнца — видимые лучи
	# ореол: яркое (огонь, фонари, мана, блик солнца на металле) светится мягким ореолом, плюс лёгкий общий bloom
	env.glow_enabled = true
	env.glow_intensity = _f("glow", 0.4)
	env.glow_strength = 1.0
	env.glow_bloom = _f("bloom", 0.0)
	env.glow_hdr_threshold = 1.15                   # светится только огонь, мана и блики, не освещённые стены
	env.glow_hdr_scale = _f("glow_scale", 0.9)
	var levels := [0.0, 1.0, 0.7, 0.35, 0.12, 0.0, 0.0]   # ореол близко к источнику, без широкой засветки
	for i: int in 7:
		env.set_glow_level(i, float(levels[i]))
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = _b("auto_exposure", true)
	ca.auto_exposure_scale = _f("exposure_scale", 0.3)
	ca.auto_exposure_speed = _f("exposure_speed", 1.2)    # глаз привыкает за секунду: на входе нет долгой засветки
	ca.auto_exposure_min_sensitivity = _f("exposure_min_iso", 80.0)     # узкий диапазон: не больше ±1 ступени
	ca.auto_exposure_max_sensitivity = _f("exposure_max_iso", 130.0)
	var far := _f("dof_far", 0.0)                        # по умолчанию без размытия дали — дымка сама отделяет планы
	if far > 0.0:
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = far
		ca.dof_blur_far_transition = _f("dof_far_transition", 70.0)
		ca.dof_blur_amount = _f("dof_amount", 0.04)
	we.camera_attributes = ca
	var dirt := _f("lens_dirt", 0.0)                     # грязь на линзе — приём «съёмки»; в RPG по умолчанию нет
	if dirt > 0.0:                                        # грязь на линзе: пятна и пылинки видны только в ореолах света
		env.glow_map = _dirt_texture()
		env.glow_map_strength = dirt


## Облака, блики и размытие в движении — эффекты в потоке рендера. Ставятся ПОСЛЕ загрузки (location.gd →
## _check_ready, через полсекунды), а не посреди стройки: в 0.3.5 игра зависла ровно в миг, когда их вешали на камеру
## во время загрузки. Каждый шаг пишет в журнал — если повиснет снова, последняя строка покажет виновника.
## У камеры свой Compositor (главнее окружения): размытие в движении — в конец его списка.
func apply_camera(c: Camera3D, s: DirectionalLight3D) -> void:
	cam = c
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	# И-51: с отдельным потоком рендера облака вешали игру; при безопасном потоке (thread_model 1) — включены сами
	var safe := int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)) == 1
	if _b("clouds", safe) and safe and Pax.graphics.available("clouds"):
		print("[pax_rpg] fx: clouds…")
		_clouds = Pax.graphics.clouds(c, {"clouds_coverage": _f("clouds_coverage", 0.42)})
	if _b("lens", safe) and safe and Pax.graphics.available("lens"):
		print("[pax_rpg] fx: lens…")
		_lens = Pax.graphics.lens(c, {"sun_color": Color(1.0, 0.82, 0.64, 0.22)}, s)
	var mb := _f("motion_blur", 0.0)                     # свои блики и размытие — в lens.gdshader (flare, cam_blur)
	if _fplus and mb > 0.0:
		print("[pax_rpg] fx: motion blur…")
		_mb = MotionBlur.new()
		_mb.shutter = mb
		if c.compositor == null:
			c.compositor = Compositor.new()
		var list: Array[CompositorEffect] = c.compositor.compositor_effects
		list.append(_mb)
		c.compositor.compositor_effects = list
	print("[pax_rpg] fx: camera effects on")


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
## Настройки проекта игры, которые локация меняет через RenderingServer (ключ → значение Godot по умолчанию).
const PS_KEYS := {
	"rendering/environment/ssao/quality": 2, "rendering/environment/ssao/half_size": true,
	"rendering/environment/ssao/adaptive_target": 0.5, "rendering/environment/ssao/blur_passes": 2,
	"rendering/environment/ssao/fadeout_from": 50.0, "rendering/environment/ssao/fadeout_to": 300.0,
	"rendering/environment/ssil/quality": 2, "rendering/environment/ssil/half_size": true,
	"rendering/environment/ssil/adaptive_target": 0.5, "rendering/environment/ssil/blur_passes": 4,
	"rendering/environment/ssil/fadeout_from": 50.0, "rendering/environment/ssil/fadeout_to": 300.0,
	"rendering/environment/screen_space_reflection/roughness_quality": 1,
	"rendering/global_illumination/sdfgi/probe_ray_count": 1,
	"rendering/environment/glow/upscale_mode": 1,
	"rendering/environment/volumetric_fog/use_filter": 1, "rendering/environment/volumetric_fog/volume_size": 64,
	"rendering/environment/volumetric_fog/volume_depth": 64,
	"rendering/environment/subsurface_scattering/subsurface_scattering_quality": 1,
	"rendering/textures/decals/filter": 3, "rendering/textures/light_projectors/filter": 3,
}


func push_globals() -> void:
	if not _saved.is_empty():
		return
	_saved = {
		"conv": int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/frames_to_converge", 4)),
		"upd": int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/frames_to_update_lights", 2)),
		"atlas": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)),
		"dq": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)),
		"pq": int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)),
	}
	for k: String in PS_KEYS:                                # И-50: всё, что меняем ниже, — запомнить как было в игре
		_saved[k] = ProjectSettings.get_setting(k, PS_KEYS[k])
	RenderingServer.directional_shadow_atlas_set_size(int(_f("sun_shadow_atlas", 8192)), true)
	# качество эффектов движка (рендер Godot): полное разрешение SSAO/SSIL, гладкие шероховатые отражения, больше лучей
	# SDFGI, бикубический ореол, сглаженный объёмный туман, SSS кожи, анизотропные декали
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, false, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH, false, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64)   # свет статичный, сходится за 30 кадров — 64 луча не видно
	RenderingServer.environment_glow_set_use_bicubic_upscale(true)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)   # туман тонкий — грубая сетка незаметна
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	RenderingServer.decals_set_filter(RenderingServer.DECAL_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)
	RenderingServer.light_projectors_set_filter(RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)
	# отражённый свет сходится за 30 кадров и обновляет свет за 16: без ступенек и мерцания при движении камеры
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_16_FRAMES)
	var q := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if _b("soft_shadows", true) else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)


func _ps(k: String) -> Variant:
	return _saved.get(k, PS_KEYS[k])


func restore_globals() -> void:
	if _saved.is_empty():
		return
	RenderingServer.directional_shadow_atlas_set_size(int(_saved["atlas"]), true)
	RenderingServer.environment_set_sdfgi_frames_to_converge(int(_saved["conv"]) as RenderingServer.EnvironmentSDFGIFramesToConverge)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(int(_saved["upd"]) as RenderingServer.EnvironmentSDFGIFramesToUpdateLight)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(_saved["dq"]) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(_saved["pq"]) as RenderingServer.ShadowQuality)
	var e := "rendering/environment/"
	RenderingServer.environment_set_ssao_quality(int(_ps(e + "ssao/quality")) as RenderingServer.EnvironmentSSAOQuality,
		bool(_ps(e + "ssao/half_size")), float(_ps(e + "ssao/adaptive_target")), int(_ps(e + "ssao/blur_passes")),
		float(_ps(e + "ssao/fadeout_from")), float(_ps(e + "ssao/fadeout_to")))
	RenderingServer.environment_set_ssil_quality(int(_ps(e + "ssil/quality")) as RenderingServer.EnvironmentSSILQuality,
		bool(_ps(e + "ssil/half_size")), float(_ps(e + "ssil/adaptive_target")), int(_ps(e + "ssil/blur_passes")),
		float(_ps(e + "ssil/fadeout_from")), float(_ps(e + "ssil/fadeout_to")))
	RenderingServer.environment_set_ssr_roughness_quality(int(_ps(e + "screen_space_reflection/roughness_quality")) as RenderingServer.EnvironmentSSRRoughnessQuality)
	RenderingServer.environment_set_sdfgi_ray_count(int(_ps("rendering/global_illumination/sdfgi/probe_ray_count")) as RenderingServer.EnvironmentSDFGIRayCount)
	RenderingServer.environment_glow_set_use_bicubic_upscale(int(_ps(e + "glow/upscale_mode")) == 1)
	RenderingServer.environment_set_volumetric_fog_filter_active(bool(_ps(e + "volumetric_fog/use_filter")))
	RenderingServer.environment_set_volumetric_fog_volume_size(int(_ps(e + "volumetric_fog/volume_size")), int(_ps(e + "volumetric_fog/volume_depth")))
	RenderingServer.sub_surface_scattering_set_quality(int(_ps(e + "subsurface_scattering/subsurface_scattering_quality")) as RenderingServer.SubSurfaceScatteringQuality)
	RenderingServer.decals_set_filter(int(_ps("rendering/textures/decals/filter")) as RenderingServer.DecalFilter)
	RenderingServer.light_projectors_set_filter(int(_ps("rendering/textures/light_projectors/filter")) as RenderingServer.LightProjectorFilter)
	_saved = {}


func _exit_tree() -> void:
	_exit_tree_signals()
	restore_globals()
	leave_frame_limits()
	_drop_camera_effects()


func _process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("gfx._process")
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
	_part_t -= delta
	if _part_t <= 0.0:
		_part_t = 0.5
		_cull_particles()
	_refresh_probe()
	_rim_follow()
	_camera_lens(delta)
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
	var hp := player.global_position if is_instance_valid(player) else cam.global_position
	var near: Array = []
	for l: Array in lights:
		var ol := l[0] as OmniLight3D
		if not is_instance_valid(ol):
			continue
		if not ol.has_meta("pax_rpg_lamp"):              # параметры — один раз: каждое присваивание пересчитывает свет
			ol.set_meta("pax_rpg_lamp", true)
			ol.light_size = 0.12                         # мягкий край тени фонаря
			ol.light_volumetric_fog_energy = _f("lamp_fog", 0.35)   # подсвечивает воздух рядом, а не туманный шар
		# по расстоянию до героя, а не по кадру: тень огня за краем кадра всё равно лежит в кадре, а проверка «в кадре»
		# от покачивания камеры включала и выключала тени — они прыгали. Яркость — базовая (без мерцания огня)
		var d := ol.global_position.distance_to(hp)
		if ol.shadow_enabled:
			d -= 6.0                                     # запас: огонь с тенью держит её, пока не станет заметно дальше
		var base_e: Variant = ol.get("base")
		var e := float(base_e) if base_e != null else ol.light_energy
		if ol.visible and e > (0.05 if ol.shadow_enabled else 0.12) and d < 35.0:
			near.append([d, ol])
		elif ol.shadow_enabled:
			ol.shadow_enabled = false
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in near.size():
		var lo := near[i][1] as OmniLight3D
		var want := i < n
		if lo.shadow_enabled != want:                    # переключаем только то, что правда сменилось
			lo.shadow_enabled = want


## Двигающиеся тела (герой, враги, жители) — динамические для отражённого света; новые (волны арены) — тоже.
## Частицы (дым, искры, листья, лепестки — 160+ систем, CPUParticles3D считаются процессором каждый кадр):
## дальше PART_FAR м от камеры прячутся (спрятанные не считаются), ближе — возвращаются. Прячем только свои
## (метка pax_rpg_culled), чужие скрытые не трогаем. Список узлов обновляется раз в 5 с.
const PART_FAR := 45.0
var _part_t := 0.0
var _parts: Array = []
var _parts_age := 99.0


func _cull_particles() -> void:
	if not is_instance_valid(view):
		return
	var cam := view.get_camera_3d()
	if cam == null:
		return
	_parts_age += 0.5
	if _parts_age > 5.0:
		_parts_age = 0.0
		_parts = view.find_children("*", "CPUParticles3D", true, false) + view.find_children("*", "GPUParticles3D", true, false)
	var cp := cam.global_position
	for n: Variant in _parts:
		if not is_instance_valid(n):
			continue
		var p := n as Node3D
		var far := p.global_position.distance_squared_to(cp) > PART_FAR * PART_FAR
		if far and p.visible:
			p.visible = false
			p.set_meta("pax_rpg_culled", true)
		elif not far and not p.visible and p.has_meta("pax_rpg_culled"):
			p.visible = true
			p.remove_meta("pax_rpg_culled")


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
					var gi := n as GeometryInstance3D
					if gi.gi_mode != GeometryInstance3D.GI_MODE_DYNAMIC:   # только новое (вещи героя) — без пересчёта
						gi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
					if c == player and (gi.layers & RIM_LAYER) == 0:
						gi.layers |= RIM_LAYER


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
		night = 1.0 - clampf(sun.light_energy / 1.1, 0.0, 1.0) * 0.6
	_rim.light_energy = energy * night
	if is_instance_valid(sun):                       # цвет — от солнца мира (розовый закат), не свой голубой
		_rim.light_color = sun.light_color.lerp(Color(0.85, 0.75, 0.9), 0.4)


var _fogs_made := false


## Дымка у живого огня: эллипсоид тумана вокруг каждого костра и жаровни (виден при объёмном тумане).
func _fire_fog() -> void:
	_fogs_made = true
	if not _fplus or _f("fire_fog", 0.06) <= 0.0:
		return
	var fm := FogMaterial.new()
	fm.density = _f("fire_fog", 0.06)                    # лёгкий ореол в воздухе, а не светящийся шар
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
		fv.size = Vector3(2.2, 2.0, 2.2)
		fv.material = fm
		ol.get_parent().add_child(fv)
		fv.global_position = ol.global_position + Vector3(0, 0.4, 0)
		made += 1


var lens_mat: ShaderMaterial
var mod: PaxMod                    # ставит location.gd до apply_viewport (шейдер слоя камеры — файл мода)
static var _dirt: ImageTexture


## Слой камеры на контейнере 3D-вида (иай рисует в нём же остановку времени — iai.gd).
func _lens_layer(v: SubViewport) -> void:
	var box := v.get_parent() as SubViewportContainer
	if box == null or mod == null or not _b("camera_fx", true):
		return
	var sh: Shader = mod.shader("shaders/lens.gdshader")
	if sh == null:
		return
	lens_mat = ShaderMaterial.new()
	lens_mat.shader = sh
	lens_mat.set_meta("pax_rpg_lens", true)
	for kv: Array in [["distortion", 0.0], ["ca", 0.0006], ["sharpen", 0.3], ["grain", 0.0], ["vignette", 0.0], ["ghosts", 0.0]]:
		lens_mat.set_shader_parameter(str(kv[0]), _f("lens_" + str(kv[0]), float(kv[1])))
	box.material = lens_mat


## Грязь на линзе (glow_map): разводы и пылинки — свой рисунок, без файла (один раз за сессию).
static func _dirt_texture() -> ImageTexture:
	if _dirt != null:
		return _dirt
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.012
	for y: int in n:
		for x: int in n:
			var v := 0.18 + 0.55 * smoothstep(0.1, 0.7, noise.get_noise_2d(x, y) * 0.5 + 0.5)   # разводы
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.94))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 70:                                     # пылинки — каждая только в своём квадрате
		var c := Vector2(rng.randf(), rng.randf()) * n
		var rad := rng.randf_range(1.0, 5.0)
		var peak := rng.randf_range(0.4, 1.0)
		for y: int in range(maxi(0, int(c.y - rad)), mini(n, int(c.y + rad) + 1)):
			for x: int in range(maxi(0, int(c.x - rad)), mini(n, int(c.x + rad) + 1)):
				var a := peak * (1.0 - smoothstep(rad * 0.4, rad, Vector2(x, y).distance_to(c)))
				if a > img.get_pixel(x, y).r:
					img.set_pixel(x, y, Color(a, a * 0.97, a * 0.94))
	_dirt = ImageTexture.create_from_image(img)
	return _dirt


var _prev_fwd := Vector3.ZERO
var _sun_vis := 0.0


## Слой камеры по кадру: размытие поворота (насколько повернулась камера за кадр) и блики солнца (где солнце
## на экране и не заслонено ли — луч по коллизиям города).
func _camera_lens(delta: float) -> void:
	if lens_mat == null or not is_instance_valid(cam) or not is_instance_valid(view):
		return
	var b := cam.global_transform.basis
	var fwd := -b.z
	var vs := Vector2(view.size)
	var aspect := vs.x / maxf(vs.y, 1.0)
	var th := tan(deg_to_rad(cam.fov) * 0.5)
	var shutter := 0.0                                   # размытие поворота выкл.: по сдвигу за кадр оно дёргалось с частотой кадров
	var mb := Vector2.ZERO
	if _prev_fwd != Vector3.ZERO and shutter > 0.0 and delta > 0.0:
		var d := fwd - _prev_fwd
		mb = Vector2(d.dot(b.x) / (2.0 * th * aspect), -d.dot(b.y) / (2.0 * th)) * shutter
		if mb.length() > 0.035:
			mb = mb.normalized() * 0.035
	_prev_fwd = fwd
	lens_mat.set_shader_parameter("mblur", mb)
	var fl := _f("flare", 0.6)
	if fl <= 0.0 or not is_instance_valid(sun):
		lens_mat.set_shader_parameter("sun_vis", 0.0)
		return
	var to_sun := sun.global_transform.basis.z.normalized()        # свет летит по −Z — солнце в стороне +Z
	var want := 0.0
	var p := cam.global_position + to_sun * 1000.0
	if to_sun.y > -0.02 and not cam.is_position_behind(p) and sun.light_energy > 0.3:
		var uv := cam.unproject_position(p) / vs
		if uv.x > -0.2 and uv.x < 1.2 and uv.y > -0.2 and uv.y < 1.2:
			lens_mat.set_shader_parameter("sun_uv", uv)
			want = 0.0 if _sun_blocked else clampf(sun.light_energy / 1.1, 0.0, 1.0)   # за домом — нет
	_sun_vis = move_toward(_sun_vis, want, delta * 4.0)
	lens_mat.set_shader_parameter("sun_vis", _sun_vis * fl)
	lens_mat.set_shader_parameter("sun_col", Vector3(sun.light_color.r, sun.light_color.g, sun.light_color.b))


var _sun_blocked := false


## Заслонено ли солнце (луч по коллизиям города) — в такте физики: вне его пространство физики может быть занято.
func _physics_process(_delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("gfx._physics_process")
	if not is_instance_valid(cam) or not is_instance_valid(sun) or not is_instance_valid(view) or view.world_3d == null:
		return
	var to_sun := sun.global_transform.basis.z.normalized()
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + to_sun * 300.0)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]   # сам герой солнце не заслоняет
	_sun_blocked = not view.world_3d.direct_space_state.intersect_ray(q).is_empty()
