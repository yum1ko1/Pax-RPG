extends CanvasLayer
## Локация города — прототип механики. Свой 3D-мир в SubViewport поверх игры (own_world_3d: своя физика и свет,
## мир игры его не видит): платформа, несколько блоков, ворота выхода и герой (config/hero.json: модель, скорости,
## комбо; логика анимаций — hero.gd; нет модели — овал). WASD — ходьба относительно камеры, Shift — бег, Пробел —
## прыжок, F — достать / убрать меч, ЛКМ — удар (три подряд — комбо), правая кнопка мыши + движение — поворот
## камеры, E у ворот — назад на карту мира (сигнал exit_requested, дальше travel.gd).

signal exit_requested

const GATE_RADIUS := 2.6           # м, насколько близко к воротам E работает
const FALL_Y := -20.0              # упал с платформы — обратно на старт
const ARENA_START := Vector3(0.0, 1.2, 8.0)
var START := ARENA_START           # точка появления (у города — из его планировки)
var _gate_radius := GATE_RADIUS
const Hero := preload("res://mods/pax_rpg/src/location/hero.gd")
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const City := preload("res://mods/pax_rpg/src/location/city.gd")
const Npc := preload("res://mods/pax_rpg/src/location/npc.gd")
const HelpPanel := preload("res://mods/pax_rpg/src/location/help_panel.gd")
const PauseMenu := preload("res://mods/pax_rpg/src/location/pause_menu.gd")
const Sfx := preload("res://mods/pax_rpg/src/location/sfx.gd")
const CityTitle := preload("res://mods/pax_rpg/src/location/city_title.gd")
const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const Wind := preload("res://mods/pax_rpg/src/location/wind.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const HERO_HP := 100.0
const HERO_POSTURE := 100.0

var mod: PaxMod
var cfg: Dictionary = {}
var active := false

var _box: SubViewportContainer
var _view: SubViewport
var _player: CharacterBody3D
var _body_mesh: Node3D
var _cam: Camera3D
var _hud: Hud                      # HUD «Сакура и сталь» (hud.gd)
var _gate_pos := Vector3.ZERO
var _city_name := ""
var _yaw := 0.0
var _turning := false
var _near_gate := false
var hero_cfg: Dictionary = {}      # config/hero.json
var _hero: Hero                    # модель и её анимации; null — герой-овал
var _f_down := false               # F была нажата в прошлом кадре — достаём меч по нажатию, не по удержанию
var _f_queued := false             # нажатие F пришло событием (короткое — опрос мог его не застать)
var _lmb_queued := false           # удар (ЛКМ) — до следующего кадра физики
var _space_down := false
var _alt_down := false             # уворот — по нажатию Alt, не по удержанию
var game: PaxGame                  # задаёт travel.gd: пока мы на локации, время мира стоит
var test_mode := false             # тестовая арена из главного меню (герой + гоблин), выход — обратно в меню
var _goblins: Array = []
var _hp := HERO_HP
var _posture := 0.0                # концентрация героя (Sekiro): блоки копят, переполнилась — стойка сломана
var _since_hit := 99.0
var _stagger := 0.0                # с, сломанная стойка — управление на миг отнято
var _lock: Node3D                  # захваченный враг (Q): камера держит его, герой стоит к нему лицом
var _lock_mark: MeshInstance3D
var _rmb := false
var _cam_lock := 0.0               # 0 — свободная камера, 1 — за плечом при захвате (плавно между)
var _lock_point := Vector3.ZERO
var _kills := 0
var _prog: Progress                # уровень, опыт, очки умений (сохраняются)
var _orbs: Array = []              # мана повергнутых врагов летит в шкалу опыта: {p0: Vector2, t, delay, v}
var _lvl_flash := 0.0              # с, вспышка нового уровня в HUD
var _flask := 3                    # заряды эликсира (R)
var _hp_ghost := 1.0               # розовый «след» недавней потери здоровья на полосе
var _numbers: Array = []           # цифры урона: {pos: Vector3, v, crit, t}
var _toast: Dictionary = {}        # уведомление слева: {text, t}
var _hint_t := 25.0                # с, сколько ещё видна подсказка управления (H — показать снова)
var _dead_seen: Dictionary = {}    # id гоблина → уже засчитан повергнутым
var _map_rects: Array = []         # [центр XZ, размер XZ, цвет] — платформы для миникарты
var _help: HelpPanel               # кнопка и окно «Управление» (H)
var _pause: PauseMenu              # меню паузы (Esc)
var _sfx: Sfx                      # шаги, снаряжение, гул города
var _zoom_want := 0.0              # куда крутят колесом; _zoom догоняет плавно, с лёгкой задержкой
var _zoom := 0.0                   # приближение камеры колесом: 0 — обычная даль, 1 — как в бою (за плечом)
var _was_floor := true
var _body_turn := false
var _city_leaves: Array = []
var _city_lights: Array = []
var _city_smoke: Array = []
var _city_glass: Array = []
var _city_paper: Array = []
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _daynight: DayNight            # тело доворачивается к цели (голова уже не достаёт)
var _hold_pause := 0.0             # с; пробел — прыжок, а игра ловит его как «пуск времени» — снова ставим паузу


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgLocation"
	layer = 100
	visible = false
	var parsed: Variant = JSON.parse_string(m.read_text("config/location.json"))
	cfg = parsed if parsed is Dictionary else {}
	var hp: Variant = JSON.parse_string(m.read_text("config/hero.json"))
	hero_cfg = hp if hp is Dictionary else {}


func _f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ---------- построить и убрать ----------

## Кнопка «Тест» главного меню: арена — та же площадка, герой и гоблин; ворота возвращают в меню.
func build_test() -> void:
	build({"id": "test"})
	test_mode = true
	_pause.set_leave_text(mod.tr_key("pax_rpg_pause_menu"))
	_city_name = mod.tr_key("pax_rpg_menu_test")
	_update_hud()


## Гоблины локации (config/location.json → goblins): полукругом перед героем, между ним и воротами.
func _spawn_goblins(n: int) -> void:
	for i: int in n:
		var g := Goblin.new()
		var a := (float(i) - (n - 1) * 0.5) * 0.6
		g.setup(mod, _player, _on_hero_hit, START + Vector3(sin(a) * 9.0, -1.0, -cos(a) * 9.0), _hero_attacking,
			_hero_blocking)
		_view.add_child(g)
		_goblins.append(g)


func _hp_max() -> float:
	return HERO_HP * (_prog.hp_mult() if _prog != null else 1.0)


func _pos_max() -> float:
	return HERO_POSTURE * (_prog.posture_mult() if _prog != null else 1.0)


func build(city: Dictionary) -> void:
	clear()
	if _prog == null:
		_prog = Progress.new()
		_prog.setup(mod, hero_cfg.get("progress", {}))
	_orbs.clear()
	test_mode = false
	_hp = _hp_max()
	_city_name = mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP   # щелчки по локации не доходят до окон игры под ней
	add_child(_box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_box.add_child(_view)
	_map_rects.clear()
	_make_sky()
	_city_lights = []
	_city_glass = []
	_city_paper = []
	var layout := _city_layout(str(city.get("id", "")))
	START = ARENA_START
	_gate_radius = GATE_RADIUS
	var goblins := int(cfg.get("goblins", 1))
	if layout.is_empty():
		_make_ground()
		_make_gate()
	else:                                            # настоящий город: планировка config/<id>.json
		var c := City.new()
		c.build(mod, _view, layout)
		_map_rects.append_array(c.rects)
		_city_leaves = c.leaves
		_city_smoke = c.smoke
		_city_lights = c.lights
		_city_glass = c.glass
		_city_paper = c.paper_mats
		var st: Array = layout.get("start", [0, 1.2, 0])
		START = Vector3(float(st[0]), float(st[1]), float(st[2]))
		var ex: Array = layout.get("exit", [0, 0])
		_gate_pos = Vector3(float(ex[0]), 0.0, float(ex[1]))
		_gate_radius = float(layout.get("exit_radius", GATE_RADIUS))
		goblins = int(layout.get("goblins", 0))
		_spawn_npcs(layout)
		_shots = layout.get("shots", [])
		_make_portal()
		var probe := ReflectionProbe.new()             # отражения неба и улиц в стёклах (снимок — один раз)
		probe.size = Vector3(200.0, 50.0, 200.0)
		probe.position = Vector3(0.0, 12.0, 0.0)
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.box_projection = false
		probe.intensity = 1.0
		_view.add_child(probe)
	_daynight = DayNight.new()
	_daynight.lights = _city_lights
	_daynight.glass = _city_glass
	_daynight.paper = _city_paper
	_daynight.setup(_env, _sun, _sky_mat, cfg)
	_view.add_child(_daynight)
	_make_player()
	if not layout.is_empty():                          # ветер с порывами и листопад — в городе
		var wind := Wind.new()
		wind.setup(mod, _player)
		wind.leaves = _city_leaves
		wind.smoke = _city_smoke
		_view.add_child(wind)
	_spawn_goblins(goblins)
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_view.add_child(_cam)
	_cam.current = true
	_hud = Hud.new()
	_hud.setup(mod, mod.texture(str(hero_cfg.get("enemy_portrait", "models/goblin/portrait.png"))))
	add_child(_hud)
	_help = HelpPanel.new()
	_help.setup(mod)
	_help.toggled.connect(func(on: bool) -> void:
		if not paused():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED)
	add_child(_help)
	_sfx = Sfx.new()
	_sfx.setup(mod, not layout.is_empty())
	add_child(_sfx)
	_pause = PauseMenu.new()
	_pause.setup(mod, mod.tr_key("pax_rpg_pause_leave"))
	_pause.visible = false
	_pause.resume.connect(_set_paused.bind(false))
	_pause.show_help.connect(func() -> void:
		_set_paused(false)
		_help.set_open(true))
	_pause.leave_city.connect(func() -> void:
		_set_paused(false)
		exit_requested.emit())
	add_child(_pause)
	if not layout.is_empty():                          # заставка: катана с названием места
		var ct := CityTitle.new()
		ct.setup(mod, _city_name)
		add_child(ct)
		ct.play(float(cfg.get("loading_seconds", 4.0)) + 2.6)   # после экрана загрузки
	_zoom = 0.0
	_zoom_want = 0.0
	_yaw = 0.0
	_near_gate = false
	_flask = int(_hf("flask_charges", 3.0))
	_hp_ghost = 1.0
	_numbers.clear()
	_toast = {}
	_hint_t = 0.0                                    # подсказка — не на экране, а в окне «Управление» (H)
	_dead_seen.clear()
	_lock_mark = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 1.0, 1.0)
	lmat.no_depth_test = true
	lm.material = lmat
	_lock_mark.mesh = lm
	_lock_mark.visible = false
	_view.add_child(_lock_mark)
	_lock = null
	_posture = 0.0
	_stagger = 0.0
	_update_hud()
	visible = true
	active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # камера — мышью, без зажатой кнопки (ПКМ — блок)


func clear() -> void:
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = false
	visible = false
	_turning = false
	for n: Node in [_box, _hud, _pause, _sfx, _help]:
		if is_instance_valid(n):
			n.queue_free()
	_goblins.clear()
	test_mode = false
	_lock = null
	_box = null
	_view = null
	_player = null
	_cam = null
	_hud = null
	_pause = null
	_sfx = null


func _make_sky() -> void:
	var sky := Sky.new()
	var ssh: Shader = mod.shader("shaders/sky.gdshader")
	_sky_mat = null
	if ssh != null:                                  # небо со сменой суток и облаками (daynight.gd)
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = ssh
		sky.sky_material = _sky_mat
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.radiance_size = Sky.RADIANCE_SIZE_64
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.22, 0.42, 0.85)
		sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.86)     # розовая мановая атмосфера Юрумы
		sky_mat.ground_horizon_color = Color(0.85, 0.55, 0.8)
		sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.3)
		sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	var fplus := RenderingServer.get_current_rendering_method() == "forward_plus"   # SSAO и SSR — только в Forward+
	env.ssao_enabled = fplus                         # тени в углах и под крышами
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.glow_enabled = true                          # фонари, мана, вода фонтана светятся
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.fog_enabled = true                           # розовая дымка маны вдали
	env.fog_light_color = Color(0.95, 0.62, 0.8)
	env.fog_density = 0.0016                         # реже: за стеной видны холмы и горы в дымке
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.3
	env.ssr_enabled = fplus                          # стёкла окон и лужи отражают город
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 145.0, 0.0)   # низкое тёплое солнце — длинные тени по улицам
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0       # дальше тени не видны за дымкой, а каждый метр — лишняя отрисовка
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_view.add_child(sun)
	_sun = sun


## Консоль F8: rpg_time <час> — поставить время суток (для скриншотов).
func set_hour(h: float) -> String:
	if _daynight == null or not is_instance_valid(_daynight):
		return "no location"
	_daynight.hour = fmod(h, 24.0)
	_daynight.apply()
	return "time: %.1f" % _daynight.hour


func _solid(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	_view.add_child(body)
	var big := size.x >= 20.0
	_map_rects.append([Vector2(pos.x, pos.z), Vector2(size.x, size.z),
		Color(0.11, 0.16, 0.35) if big else Color(0.2, 0.27, 0.55)])
	return body


## Мирные жители по маршрутам планировки: «npcs» штук, по кругу маршрутов, в разных точках.
func _spawn_npcs(layout: Dictionary) -> void:
	var paths: Array = layout.get("paths", [])
	if paths.is_empty():
		return
	for n: int in int(layout.get("npcs", 0)):
		var src: Array = paths[n % paths.size()]
		var pts := PackedVector3Array()
		for pt: Variant in src:
			var a: Array = pt
			pts.append(Vector3(float(a[0]) + randf_range(-1.2, 1.2), 0.1, float(a[1]) + randf_range(-1.2, 1.2)))
		var npc := Npc.new()
		npc.setup(mod, pts, randi() % pts.size(), n * 7919 + 13)
		_view.add_child(npc)


## Планировка города (config/<id>.json); нет файла — {} (локация-прототип).
func _city_layout(id: String) -> Dictionary:
	if id == "" or id == "test":
		return {}
	var txt := mod.read_text("config/%s.json" % id)
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


func _make_ground() -> void:
	var s := _f("platform_size", 40.0)
	_solid(Vector3(s, 1.0, s), Vector3(0.0, -0.5, 0.0), Color(0.16, 0.45, 0.58))
	# блоки и ступени — проверить ходьбу, прыжок и упор в стену
	_solid(Vector3(3.0, 1.0, 3.0), Vector3(-8.0, 0.5, 2.0), Color(0.36, 0.38, 0.62))
	_solid(Vector3(3.0, 2.0, 3.0), Vector3(-8.0, 1.0, -1.0), Color(0.42, 0.42, 0.7))
	_solid(Vector3(3.0, 3.0, 3.0), Vector3(-8.0, 1.5, -4.0), Color(0.5, 0.46, 0.78))
	_solid(Vector3(6.0, 2.5, 1.0), Vector3(7.0, 1.25, 0.0), Color(0.3, 0.55, 0.75))
	_solid(Vector3(1.5, 4.0, 1.5), Vector3(9.0, 2.0, 8.0), Color(0.85, 0.85, 0.95))


func _make_gate() -> void:
	var s := _f("platform_size", 40.0)
	_gate_pos = Vector3(0.0, 0.0, -s * 0.5 + 4.0)
	var pillar := Color(0.55, 0.5, 0.8)
	_solid(Vector3(1.0, 4.5, 1.0), _gate_pos + Vector3(-2.2, 2.25, 0.0), pillar)
	_solid(Vector3(1.0, 4.5, 1.0), _gate_pos + Vector3(2.2, 2.25, 0.0), pillar)
	_solid(Vector3(5.4, 0.8, 1.0), _gate_pos + Vector3(0.0, 4.9, 0.0), pillar)
	var glow := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(3.4, 4.4)
	glow.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.45, 0.85, 0.55)
	glow.material_override = mat
	glow.position = _gate_pos + Vector3(0.0, 2.2, 0.0)
	_view.add_child(glow)
	var gate_label := Label3D.new()
	gate_label.text = mod.tr_key("pax_rpg_gate")
	gate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate_label.font_size = 64
	gate_label.outline_size = 12
	gate_label.position = _gate_pos + Vector3(0.0, 6.0, 0.0)
	_view.add_child(gate_label)


## Выход из города: мерцающая завеса, тёплый свет, искры маны и надпись над ним (вход — E, см. подсказку HUD).
func _make_portal() -> void:
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(7.0, 6.0)
	glow.mesh = q
	var sh: Shader = mod.shader("shaders/portal.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		glow.material_override = m
	glow.position = _gate_pos + Vector3(0.0, 3.0, 0.0)
	_view.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.85)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.position = _gate_pos + Vector3(0.0, 2.0, -1.5)
	_view.add_child(l)
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.2, 0.2, 0.6)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.0, 0.25, 0.0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.7, 0.95)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.5, 0.9)
	dm.emission_energy_multiplier = 3.0
	dot.material = dm
	p.mesh = dot
	p.position = _gate_pos + Vector3(0.0, 0.2, 0.0)
	_view.add_child(p)
	var label := Label3D.new()
	label.text = mod.tr_key("pax_rpg_gate")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.outline_size = 14
	label.modulate = Color(1.0, 0.85, 0.95)
	label.position = _gate_pos + Vector3(0.0, 6.6, 0.0)
	_view.add_child(label)


func _make_player() -> void:
	_player = CharacterBody3D.new()
	_player.position = START
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(hero_cfg.get("capsule_radius", 0.4))
	cap.height = float(hero_cfg.get("capsule_height", 1.8))
	shape.shape = cap
	_player.add_child(shape)
	_body_mesh = Node3D.new()
	_player.add_child(_body_mesh)
	_hero = Hero.new()
	var model := _hero.load_model(mod, hero_cfg)
	if model != null:
		model.position = Vector3(0.0, -cap.height / 2.0, 0.0)   # ступни — на низ капсулы
		model.rotation.y = PI                                    # glb смотрит на +Z, вперёд у героя — -Z
		_body_mesh.add_child(model)
		_view.add_child(_player)            # сначала в дерево: вне дерева AnimationPlayer не играет
		_hero.start(_player)
		return
	_hero = null
	mod.log_warning("Pax RPG: %s did not load — the hero is an oval" % str(hero_cfg.get("model", "?")))
	# Запасной герой — овал (вытянутая сфера) и «нос» спереди, чтобы видеть, куда он смотрит.
	var oval := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	oval.mesh = sphere
	oval.scale = Vector3(0.8, 1.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	oval.material_override = mat
	_body_mesh.add_child(oval)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.18, 0.18, 0.3)
	nose.mesh = nb
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(1.0, 0.4, 0.8)
	nose.material_override = nmat
	nose.position = Vector3(0.0, 0.45, -0.42)
	_body_mesh.add_child(nose)
	_view.add_child(_player)


func _hf(key: String, fallback: float) -> float:
	return float(hero_cfg.get(key, cfg.get(key, fallback)))


# ---------- управление ----------

## Пауза (Esc): мир локации замирает, мышь свободна, поверх — меню.
func _set_paused(on: bool) -> void:
	if not is_instance_valid(_pause):
		return
	_pause.visible = on
	if is_instance_valid(_box):
		_box.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_rmb = false
	_lmb_queued = false


func paused() -> bool:
	return is_instance_valid(_pause) and _pause.visible


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(_player) or paused():
		return
	var on_floor := _player.is_on_floor()
	# F и пробел опрашиваем здесь, а не в _input: игра может забрать нажатие раньше нас
	var f := (Input.is_physical_key_pressed(KEY_F) or Input.is_key_pressed(KEY_F)) and not _typing()
	if (_f_queued or (f and not _f_down)) and _hero != null:
		var wasd := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)
		_hero.toggle_sword(on_floor, wasd)
	_f_queued = false
	_f_down = f
	_stagger = maxf(0.0, _stagger - delta)
	_since_hit += delta
	_regen_posture(delta)
	if _hero != null:
		_hero.combat = _hud_enemy() != null
	if _lock != null and (not is_instance_valid(_lock) or not (_lock as Goblin).is_alive()
			or _lock.global_position.distance_to(_player.global_position) > 22.0):
		_set_lock(null)
	if _lmb_queued and _hero != null and _stagger <= 0.0:
		if not _try_deathblow():
			if _hero.action == "":
				var tg := _attack_target()
				_face_now(_yaw_to(tg) if tg != null else _aim_yaw())   # удар — во врага рядом, иначе куда камера
			_hero.attack(on_floor)
	_lmb_queued = false
	if _hero != null:
		_hero.set_block(_rmb and _stagger <= 0.0)
	var locked := _hero != null and (_hero.locks_move() or _stagger > 0.0)
	var input := Vector2.ZERO
	if not _typing() and not locked:
		input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _yaw)
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, _yaw)
	var move := right * input.x - forward * input.y
	if move.length() > 1.0:
		move = move.normalized()
	# уворот (Alt): развернуть героя по вводу (без ввода — куда смотрит) и кувырок; дальше его ведёт root motion
	var alt := Input.is_physical_key_pressed(KEY_ALT) and not _typing()
	if alt and not _alt_down and not locked and _hero != null:
		var wish := right * input.x - forward * input.y
		if _hero.dodge(on_floor):
			if wish.length() > 0.01:
				_body_mesh.rotation.y = atan2(-wish.x, -wish.z)
			locked = true
	_alt_down = alt
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and not (_hero != null and (_hero.walk_only()
		or _hero.blocking))
	var speed := _hf("run_speed", 5.0) if running else _hf("walk_speed", 2.4)
	if _hero != null and (_hero.armed or _hero.walk_only()):
		speed *= _hf("armed_run_factor", 0.8) if running else _hf("armed_speed_factor", 1.0)
	if _hero != null and _hero.blocking:
		speed *= _hf("block_speed_factor", 0.55)
	elif _lock != null and not running:
		speed *= _hf("lock_speed_factor", 0.75)          # в поединке — осторожный шаг
	var vel := _player.velocity
	var acc := _hf("accel", 9.0) * delta                  # разгон и торможение плавно, не рывком
	vel.x = move_toward(vel.x, move.x * speed, acc)
	vel.z = move_toward(vel.z, move.z * speed, acc)
	var space := Input.is_physical_key_pressed(KEY_SPACE) and not _typing()
	if on_floor:
		if space and not _space_down and not locked:
			if _hero == null or _hero.jump(on_floor):
				vel.y = _hf("jump_speed", 7.0)   # отрыв сразу; анимация прыжка — с момента отрыва
	else:
		vel.y -= _f("gravity", 20.0) * delta
	_space_down = space
	# игра слушает пробел раньше нас и запускает время — пока пробел нажат и чуть после, держим паузу
	if space:
		_hold_pause = 0.3
	if _hold_pause > 0.0:
		_hold_pause -= delta
		if game != null and bool(cfg.get("pause_world", true)):
			game.set_speed(0)
	var moving := move.length() > 0.01 and on_floor
	# куда стоит лицом: в захваченного врага; на бегу — по ходу; шагом — туда же, куда камера
	# без оружия и без захвата — идёт лицом по ходу (как Sekiro вне захвата); боком и спиной — только с мечом, в блоке, в захвате
	var free_walk := moving and _hero != null and not _hero.armed and not _hero.blocking and _lock == null \
		and not bool(cfg.get("strafe_unarmed", false))
	if not locked:
		var face := INF
		if _lock != null and not running:
			# в захвате на месте: к врагу поворачивается голова; тело — только когда угол для головы велик
			var want := _aim_yaw()
			if moving or (_hero != null and (_hero.blocking or _hero_attacking())):
				face = want
			else:
				var diff := absf(angle_difference(_body_mesh.rotation.y, want))
				if diff > deg_to_rad(_hf("head_limit", 70.0) * 0.9):
					_body_turn = true
				elif diff < deg_to_rad(15.0):
					_body_turn = false
				if _body_turn:
					face = want
		elif moving and (running or free_walk):
			face = atan2(-move.x, -move.z)
		elif moving or (_hero != null and _hero.blocking):
			face = _yaw
		if face != INF:
			_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, face, minf(1.0, delta * 12.0))
	if _hero != null:
		var look: Variant = null
		if _lock != null and is_instance_valid(_lock):
			look = _lock.global_position + Vector3(0.0, _hf("look_height", 0.95), 0.0)
		_hero.look_at_point(look, delta)
	# магнит ударов: каждый удар комбо доворачивает к врагу, шаг удара не проносит сквозь него
	var mag: Goblin = _attack_target() if _hero_attacking() else null
	if mag != null:
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, _yaw_to(mag), minf(1.0, delta * _hf("magnet_turn", 14.0)))
	if _hero != null:
		var by := _body_mesh.rotation.y
		var bf := Vector3(-sin(by), 0.0, -cos(by))
		var br := Vector3(cos(by), 0.0, -sin(by))
		_hero.move_dir = Vector2(0.0, 1.0) if free_walk else Vector2(move.dot(br), move.dot(bf))
	if _hero != null:
		var r: Dictionary = _hero.tick(delta, moving, Vector2(_player.velocity.x, _player.velocity.z).length(), running, on_floor)
		var step: Vector3 = r.root
		if r.has("hit"):
			_strike(r.hit)
		if step != Vector3.ZERO and delta > 0.0:
			# смещение клипа — в осях модели; модель повёрнута вместе с _body_mesh (и на PI внутри него)
			var w := _body_mesh.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI) * step
			vel.x = w.x / delta
			vel.z = w.z / delta
		if mag != null:
			vel = _magnet_pull(vel, mag, delta)
	_player.velocity = vel
	var was := _player.global_position
	_player.move_and_slide()
	if is_instance_valid(_sfx):
		var d := _player.global_position - was
		d.y = 0.0
		var fl := _player.is_on_floor()
		if fl and not _was_floor:
			_sfx.land()
		_was_floor = fl
		_sfx.walk(d.length(), running, _hero != null and _hero.armed, fl)
	if _hero != null:
		_hero.cape_wind(_player.velocity)
	if _lock != null:
		var d := _lock.global_position - _player.global_position
		_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), minf(1.0, delta * 6.0))
	if is_instance_valid(_lock_mark):
		_lock_mark.visible = false                   # прицел захвата рисует HUD
	if _player.position.y < FALL_Y:
		_player.position = START
		_player.velocity = Vector3.ZERO
	_follow_camera(delta)
	var near := Vector2(_player.position.x - _gate_pos.x, _player.position.z - _gate_pos.z).length() < _gate_radius
	if near != _near_gate:
		_near_gate = near
		_update_hud()


## Камера: свободная — сзади и сверху; при захвате врага плавно подлетает к герою и встаёт за правым плечом,
## глядя на середину между героем и врагом — обоих видно, удобно читать замахи.
## Кинокамера для превью (консоль F8: rpg_cam N, 0 — обычная): ракурсы «shots» из планировки города.
var _cine: Array = []
var _shots: Array = []


func cine(n: int) -> String:
	if n <= 0 or n > _shots.size():
		_cine = []
		if is_instance_valid(_hud):
			_hud.visible = true
		return "camera: player"
	_cine = _shots[n - 1]
	if is_instance_valid(_hud):
		_hud.visible = false
	return "camera: shot %d/%d" % [n, _shots.size()]


func _follow_camera(delta := 0.0) -> void:
	if not _cine.is_empty() and is_instance_valid(_cam):
		var a: Array = _cine[0]
		var b: Array = _cine[1]
		_cam.global_position = Vector3(float(a[0]), float(a[1]), float(a[2]))
		_cam.look_at(Vector3(float(b[0]), float(b[1]), float(b[2])))
		return
	if not is_instance_valid(_cam):
		return
	var want := 1.0 if (_lock != null and is_instance_valid(_lock)) else 0.0
	_cam_lock = move_toward(_cam_lock, want, delta * _f("lock_camera_speed", 2.5)) if delta > 0.0 else want
	var k := smoothstep(0.0, 1.0, _cam_lock)
	var target := _player.position + Vector3(0.0, 0.9, 0.0)
	# колесо: от обычной дали до «боевой» — как за плечом в захвате (высота и даль lock_camera_*)
	if delta > 0.0:
		_zoom = lerpf(_zoom, _zoom_want, 1.0 - exp(-delta * _f("zoom_smooth", 3.0)))
	var z := smoothstep(0.0, 1.0, _zoom)
	var ch := lerpf(_f("camera_height", 3.5), _f("lock_camera_height", 1.75) - 0.9, z)
	var cd := lerpf(_f("camera_distance", 7.0), _f("lock_camera_distance", 3.2), z)
	var free_pos := target + Vector3(0.0, ch, cd).rotated(Vector3.UP, _yaw)
	var look := target
	var pos := free_pos
	if k > 0.0:
		var back := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, _yaw)
		var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, _yaw)
		var shoulder := _player.position + Vector3(0.0, _f("lock_camera_height", 1.75), 0.0) \
			+ right * _f("lock_camera_side", 0.9) + back * _f("lock_camera_distance", 3.2)
		var enemy := _lock_point if want == 0.0 else _lock.global_position + Vector3(0.0, 0.9, 0.0)
		if want > 0.0:
			_lock_point = enemy
		var lock_look := (_player.position + Vector3(0.0, 1.4, 0.0)).lerp(enemy, 0.55)
		pos = free_pos.lerp(shoulder, k)
		look = target.lerp(lock_look, k)
	_cam.position = pos
	_cam.look_at(look, Vector3.UP)


## Удар героя по врагам рядом: в пределах range и перед ним (arc — косинус полуугла; -1 — по кругу, удар о землю).
func _strike(hit: Dictionary) -> void:
	var fwd := -_body_mesh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		var d := to.length()
		if d > float(hit.range) + 0.35:
			continue
		if d > 0.3 and fwd.dot(to / d) < float(hit.arc):
			continue
		gob.take_damage(float(hit.damage) * _prog.damage_mult(), _player.global_position, bool(hit.get("knock", false)))
		_numbers.append({"pos": gob.global_position + Vector3(randf_range(-0.3, 0.3), 1.3, 0.0),
			"v": int(hit.damage), "crit": bool(hit.get("knock", false)), "t": 0.0})


# ---------- бой как в Sekiro ----------

## Куда целиться: в захваченного врага, иначе — туда, куда смотрит камера.
func _aim_yaw() -> float:
	if _lock != null:
		var d := _lock.global_position - _player.global_position
		return atan2(-d.x, -d.z)
	return _yaw


## Подтяг удара к врагу: до мига удара герой доходит (у финального — долетает) до дистанции reach, чтобы клинок
## попал по врагу, а не по воздуху; ближе reach шаг клипа не несёт — не влезает во врага.
func _magnet_pull(vel: Vector3, mag: Goblin, delta: float) -> Vector3:
	var to := mag.global_position - _player.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.01 or delta <= 0.0:
		return vel
	var dir := to / dist
	var reach := _hero.attack_reach()
	var gap := dist - reach
	var along := vel.x * dir.x + vel.z * dir.z
	var tl := _hero.hit_time_left()
	if tl >= 0.0 and _hero.pull_on() and gap > 0.0:
		var need := minf(gap / maxf(tl, 0.06), _hf("magnet_pull_max", 8.0))
		if need > along:
			vel.x += dir.x * (need - along)
			vel.z += dir.z * (need - along)
			along = need
	if along > 0.0 and along * delta > gap:                  # за кадр не проскочить ближе reach
		var cut := along - maxf(gap, 0.0) / delta
		vel.x -= dir.x * cut
		vel.z -= dir.z * cut
	return vel


## Цель удара: захваченный враг, иначе ближайший живой в magnet_range перед камерой (в пределах magnet_angle),
## а вплотную (magnet_close) — с любой стороны.
func _attack_target() -> Goblin:
	if _lock != null and is_instance_valid(_lock) and (_lock as Goblin).is_alive():
		return _lock as Goblin
	var best: Goblin = null
	var bd := _hf("magnet_range", 5.0)
	var cone := deg_to_rad(_hf("magnet_angle", 75.0))
	var ref := _body_mesh.rotation.y if _hero != null and _hero.action in Hero.ATTACKS else _yaw
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.is_alive():
			continue
		var d := gob.global_position.distance_to(_player.global_position)
		if d < bd and (d < _hf("magnet_close", 3.0) or absf(angle_difference(ref, _yaw_to(gob))) < cone):
			bd = d
			best = gob
	return best


func _yaw_to(n: Node3D) -> float:
	var d := n.global_position - _player.global_position
	return atan2(-d.x, -d.z)


func _face_now(yaw: float) -> void:
	_body_mesh.rotation.y = yaw


func _hero_attacking() -> bool:
	return _hero != null and _hero.action in Hero.ATTACKS


func _hero_blocking() -> bool:
	return _hero != null and _hero.blocking


## Q: захватить ближнего врага перед камерой (до 16 м) / отпустить.
func _toggle_lock() -> void:
	if _lock != null:
		_set_lock(null)
		return
	var cam_f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var best: Node3D = null
	var best_s := INF
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		var d := to.length()
		if d > 16.0:
			continue
		var score := d * (2.0 - cam_f.dot(to / maxf(d, 0.01)))   # ближе и прямее перед камерой — лучше
		if score < best_s:
			best_s = score
			best = gob
	_set_lock(best)


func _set_lock(t: Node3D) -> void:
	_lock = t
	if is_instance_valid(_lock_mark):
		_lock_mark.visible = false


## ЛКМ рядом с врагом без равновесия (красная метка) — добивание вместо удара.
func _try_deathblow() -> bool:
	if _hero == null:
		return false
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.can_deathblow():
			continue
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		if to.length() > _hf("deathblow_range", 2.8):
			continue
		_face_now(atan2(-to.x, -to.z))
		if _hero.deathblow():
			get_tree().create_timer(_hf("deathblow_hit", 1.1)).timeout.connect(gob.deathblow)
			return true
	return false


## Удар гоблина по герою: кувырок — мимо; парирование в первые доли секунды блока — отбит, у врага сбита
## концентрация; блок — урона нет, но копится своя концентрация (переполнилась — стойка сломана); иначе — урон.
func _on_hero_hit(damage: float, attacker: Node3D = null) -> void:
	if _hero != null and _hero.invulnerable():
		return
	var fwd := Vector3(-sin(_body_mesh.rotation.y), 0.0, -cos(_body_mesh.rotation.y))
	var facing := true
	if attacker != null:
		var to := attacker.global_position - _player.global_position
		to.y = 0.0
		facing = to.length() < 0.01 or fwd.dot(to.normalized()) > 0.2
	var spark_at := _player.global_position + fwd * 0.7 + Vector3(0.0, 1.2, 0.0)
	if _hero != null and facing and _hero.parry_window():
		_hero.deflect()
		_posture = minf(_pos_max(), _posture + 4.0)
		_sparks(spark_at, Color(1.0, 0.8, 0.35), 40, 5.0)
		if attacker is Goblin:
			(attacker as Goblin).deflected(_player.global_position)
		return
	if _hero != null and facing and _hero.blocking:
		_posture = minf(_pos_max(), _posture + damage * 2.2)
		_since_hit = 0.0
		_sparks(spark_at, Color(1.0, 0.6, 0.25), 14, 3.0)
		_player.velocity -= fwd * 3.0
		if attacker is Goblin:
			(attacker as Goblin).blocked()
		if _posture >= _pos_max():
			_posture = _pos_max() * 0.35
			_stagger = _hf("guard_break_time", 1.2)
			_hero.set_block(false)
			_hero.hurt()
		return
	_hp = maxf(0.0, _hp - damage)
	_posture = minf(_pos_max(), _posture + damage * 0.8)
	_since_hit = 0.0
	if _hero != null:
		_hero.hurt()
	if _hp <= 0.0 and is_instance_valid(_player):
		_hp = _hp_max()
		_hp_ghost = 1.0
		_posture = 0.0
		_flask = int(_hf("flask_charges", 3.0))
		_player.position = START
		_player.velocity = Vector3.ZERO
	_update_hud()


func _regen_posture(delta: float) -> void:
	if _since_hit < 1.0 or _posture <= 0.0:
		return
	var rate := _hf("posture_regen_block", 10.0) if (_hero != null and _hero.blocking) else _hf("posture_regen", 22.0)
	_posture = maxf(0.0, _posture - rate * delta)


## Искры: блок и парирование.
func _sparks(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.35
	p.spread = 70.0
	p.direction = Vector3.UP
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -9.0, 0.0)
	var q := SphereMesh.new()
	q.radius = 0.018
	q.height = 0.036
	q.radial_segments = 4
	q.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	q.material = m
	p.mesh = q
	_view.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func _hud_enemy() -> Goblin:
	if _lock != null and is_instance_valid(_lock) and (_lock as Goblin).is_alive():
		return _lock as Goblin
	var best: Goblin = null
	var bd := 15.0
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.in_combat():
			continue
		var d := gob.global_position.distance_to(_player.global_position)
		if d < bd:
			bd = d
			best = gob
	return best


func _update_hud() -> void:
	if is_instance_valid(_hud):
		_hud_tick(0.0)


## Эликсир (R): лечит, зарядов мало — пополняются, когда герой пал и вернулся на старт.
func _drink() -> void:
	if _flask <= 0 or _hp >= _hp_max() or _stagger > 0.0 or not is_instance_valid(_player):
		return
	_flask -= 1
	_hp = minf(_hp_max(), _hp + _hf("flask_heal", 45.0))
	_sparks(_player.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.55, 0.78), 30, 2.5)


func _process(delta: float) -> void:
	if active and is_instance_valid(_hud):
		_hud_tick(delta)


## Состояние HUD на кадр: герой, компас, миникарта, враг, цифры урона, мана и опыт за повергнутых.
## Шарики маны: по кривой от павшего врага к концу полоски опыта; долетел — +опыт (полоска растёт на глазах).
func _tick_orbs(delta: float) -> void:
	_lvl_flash = maxf(0.0, _lvl_flash - delta)
	if _orbs.is_empty() or not is_instance_valid(_hud):
		return
	var keep: Array = []
	for o: Dictionary in _orbs:
		o.t = float(o.t) + delta
		if float(o.t) - float(o.delay) >= ORB_TIME:
			var ups := _prog.add_xp(float(o.v))
			if ups > 0:
				_lvl_flash = 1.6
				_hp = _hp_max()                              # новый уровень — силы вернулись
				_toast = {"text": mod.tr_key("pax_rpg_hud_level_up") % _prog.level, "t": 0.0}
				if _prog.level % int((hero_cfg.get("progress", {}) as Dictionary).get("skill_every", 10)) == 0:
					_toast = {"text": mod.tr_key("pax_rpg_hud_skill_point") % _prog.level, "t": 0.0}
		else:
			keep.append(o)
	_orbs = keep


const ORB_TIME := 0.95


func _orb_points() -> Array:
	var out: Array = []
	if not is_instance_valid(_hud):
		return out
	var target := _hud.xp_target(_prog.frac())
	for o: Dictionary in _orbs:
		var k := clampf((float(o.t) - float(o.delay)) / ORB_TIME, 0.0, 1.0)
		if k <= 0.0:
			continue
		var p0: Vector2 = o.p0
		var ctrl := p0.lerp(target, 0.4) + Vector2(-160.0, -220.0) * (0.6 + 0.4 * float(o.bend))
		var trail: Array = []
		for j: int in range(5, 0, -1):                     # шлейф: где шарик был чуть раньше
			trail.append(_bez(p0, ctrl, target, maxf(0.0, k - j * 0.035)))
		out.append([_bez(p0, ctrl, target, k), k, trail])
	return out


static func _bez(p0: Vector2, c: Vector2, p1: Vector2, k: float) -> Vector2:
	var e := k * k * (3.0 - 2.0 * k)
	return p0.lerp(c, e).lerp(c.lerp(p1, e), e)


func _hud_tick(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(_player) or not is_instance_valid(_cam) \
			or not _player.is_inside_tree():
		return                                       # build() ещё до входа в дерево — позиций нет
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		var id := gob.get_instance_id()
		if not gob.is_alive() and not bool(_dead_seen.get(id, false)):
			_dead_seen[id] = true
			_kills += 1
			# мана не растворяется: шарики перелетают в шкалу опыта (левый верхний угол), опыт — по прилёту
			var gain := float((hero_cfg.get("progress", {}) as Dictionary).get("xp_per_kill", 35.0))
			var from := _cam.unproject_position(gob.global_position + Vector3(0.0, 0.8, 0.0))
			var n := 10
			for k: int in n:
				_orbs.append({"p0": from + Vector2(randf_range(-30, 30), randf_range(-30, 30)), "t": 0.0,
					"delay": k * 0.06, "v": gain / n, "bend": randf_range(-1.0, 1.0)})
			_toast = {"text": mod.tr_key("pax_rpg_hud_got") % [mod.tr_key("pax_rpg_hud_mana_item"), int(gain)], "t": 0.0}
		elif gob.is_alive():
			_dead_seen[id] = false
	_tick_orbs(delta)
	var hp := _hp / _hp_max()
	if hp >= _hp_ghost:
		_hp_ghost = hp
	elif _since_hit > 0.6:
		_hp_ghost = move_toward(_hp_ghost, hp, delta * 0.6)
	_hint_t = maxf(0.0, _hint_t - delta)
	var st := {"hp": hp, "hp_ghost": _hp_ghost, "hp_abs": _hp, "hp_max": _hp_max(), "posture": _posture / _pos_max(),
		"level": _prog.level, "xp": _prog.frac(), "xp_abs": _prog.xp, "xp_need": _prog.need(),
		"skill_points": _prog.skill_points, "orbs": _orb_points(), "lvl_flash": _lvl_flash, "flask": _flask, "flask_max": int(_hf("flask_charges", 3.0)),
		"yaw": _yaw, "body_yaw": _body_mesh.rotation.y if _body_mesh != null else _yaw, "kills": _kills,
		"me": Vector2(_player.global_position.x, _player.global_position.z), "map_rects": _map_rects,
		"gate": Vector2(_gate_pos.x, _gate_pos.z), "near_gate": _near_gate, "place": _city_name,
		"hint": mod.tr_key("pax_rpg_controls"), "hint_a": clampf(_hint_t, 0.0, 1.0),
		"gate_hint": mod.tr_key("pax_rpg_gate_hint") if _near_gate else ""}
	var targets: Array = []
	var enemies: Array = []
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var d := gob.global_position.distance_to(_player.global_position)
		var locked := gob == _lock
		enemies.append({"pos": Vector2(gob.global_position.x, gob.global_position.z), "locked": locked})
		if d < 45.0:
			targets.append({"yaw": _yaw_to(gob), "dist": d, "color": Color(1.0, 0.36, 0.56) if locked
				else Color(1.0, 0.55, 0.78)})
	targets.append({"yaw": atan2(-(_gate_pos.x - _player.global_position.x), -(_gate_pos.z - _player.global_position.z)),
		"dist": Vector2(_gate_pos.x - _player.global_position.x, _gate_pos.z - _player.global_position.z).length(),
		"color": Color(0.47, 0.84, 1.0), "ring": true})
	st["targets"] = targets
	st["enemies"] = enemies
	var e := _hud_enemy()
	if e != null:
		st["enemy"] = {"name": mod.tr_key("pax_rpg_goblin"), "hp": e.hp / Goblin.MAX_HP,
			"posture": e.posture / Goblin.MAX_POSTURE, "broken": e.can_deathblow()}
		st["ult"] = e.posture / Goblin.MAX_POSTURE if not e.can_deathblow() else 1.0
		st["ult_ready"] = e.can_deathblow()
	if _lock != null and is_instance_valid(_lock):
		var lp := _lock.global_position + Vector3(0.0, 0.85, 0.0)
		if not _cam.is_position_behind(lp):
			st["lock_screen"] = _cam.unproject_position(lp)
			st["lock_broken"] = (_lock as Goblin).can_deathblow()
	var nums: Array = []
	for i: int in range(_numbers.size() - 1, -1, -1):
		var n: Dictionary = _numbers[i]
		n.t = float(n.t) + delta
		if float(n.t) > 1.1:
			_numbers.remove_at(i)
			continue
		var wp: Vector3 = n.pos + Vector3(0.0, float(n.t) * 0.7, 0.0)
		if _cam.is_position_behind(wp):
			continue
		nums.append({"p": _cam.unproject_position(wp), "v": n.v, "crit": n.crit,
			"a": 1.0 - smoothstep(0.65, 1.1, float(n.t))})
	st["numbers"] = nums
	if not _toast.is_empty():
		_toast.t = float(_toast.t) + delta
		if float(_toast.t) > 3.5:
			_toast = {}
		else:
			st["toast"] = {"text": _toast.text, "a": 1.0 - smoothstep(2.8, 3.5, float(_toast.t))}
	var act := _hero.action if _hero != null else ""
	st["skills"] = [
		{"k": "斬", "key": mod.tr_key("pax_rpg_key_lmb"), "label": mod.tr_key("pax_rpg_hud_attack"),
			"on": act in Hero.ATTACKS, "color": Color(1.0, 0.55, 0.78)},
		{"k": "盾", "key": mod.tr_key("pax_rpg_key_rmb"), "label": mod.tr_key("pax_rpg_hud_block"),
			"on": _hero != null and _hero.blocking, "color": Color(0.47, 0.84, 1.0)},
		{"k": "風", "key": "Alt", "label": mod.tr_key("pax_rpg_hud_dodge"), "on": act in ["Dodge", "DodgeArmed"],
			"color": Color(0.47, 0.84, 1.0)},
		{"k": "鎖", "key": "Q", "label": mod.tr_key("pax_rpg_hud_lock"), "on": _lock != null,
			"color": Color(1.0, 0.55, 0.78)}]
	_hud.st = st
	_hud.refresh()


const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_Q, KEY_SPACE, KEY_SHIFT, KEY_ALT, KEY_C, KEY_R, KEY_H]


func _input(event: InputEvent) -> void:
	if not active:
		return
	if paused():
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
				and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_set_paused(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_want = clampf(_zoom_want + (0.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1), 0.0, 1.0)
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if is_instance_valid(_help) and (_help.is_open() or _help.over(mb.position)):
				return                                   # клик — по кнопке / окну «Управление»
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # вернуть мышь камере (Esc её отпускал)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = mb.pressed                       # блок; первые доли секунды — парирование
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_toggle_lock()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_lmb_queued = true                   # удар; повтор во время удара — следующий удар комбо
		get_viewport().set_input_as_handled()   # колесо и щелчки — не камере игры под локацией
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _lock == null:
			_yaw -= (event as InputEventMouseMotion).relative.x * _f("turn_speed", 0.004)
		return
	if event is InputEventKey and not _typing():
		var key: InputEventKey = event
		if key.physical_keycode in KEYS or key.keycode in KEYS:
			get_viewport().set_input_as_handled()   # горячие клавиши игры молчат, пока герой ходит
		if key.pressed and not key.echo and key.physical_keycode == KEY_E and _near_gate:
			exit_requested.emit()
		if key.pressed and not key.echo and key.physical_keycode == KEY_Q:
			_toggle_lock()                           # захват цели (как в Sekiro)
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			_set_paused(true)
			get_viewport().set_input_as_handled()
		if key.pressed and not key.echo and key.physical_keycode == KEY_R:
			_drink()                                 # эликсир
		if key.pressed and not key.echo and key.physical_keycode == KEY_H:
			if is_instance_valid(_help):
				_help.set_open(not _help.is_open())   # окно «Управление»
		if key.pressed and not key.echo and key.physical_keycode == KEY_C and _hero != null:
			_hero.toggle_slot("back")                # снять / надеть плащ
		if key.pressed and not key.echo and (key.physical_keycode == KEY_F or key.keycode == KEY_F):
			_f_queued = true
