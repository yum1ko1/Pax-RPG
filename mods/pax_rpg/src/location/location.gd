extends CanvasLayer
## Локация города — прототип механики. Свой 3D-мир в SubViewport поверх игры (own_world_3d: своя физика и свет,
## мир игры его не видит): платформа, несколько блоков, ворота выхода и герой (config/hero.json: модель, скорости,
## комбо; логика анимаций — hero.gd; нет модели — овал). WASD — ходьба относительно камеры, Shift — бег, Пробел —
## прыжок, F — достать / убрать меч, ЛКМ — удар (три подряд — комбо), правая кнопка мыши + движение — поворот
## камеры, E у ворот — назад на карту мира (сигнал exit_requested, дальше travel.gd).
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")

signal exit_requested

const GATE_RADIUS := 2.6           # м, насколько близко к воротам E работает
const FALL_Y := -20.0              # упал с платформы — обратно на старт
const ARENA_START := Vector3(0.0, 1.2, 8.0)
var START := ARENA_START           # точка появления (у города — из его планировки)
var _gate_radius := GATE_RADIUS
const Hero := preload("res://mods/pax_rpg/src/location/hero.gd")
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const Orc := preload("res://mods/pax_rpg/src/location/orc.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const CityMap := preload("res://mods/pax_rpg/src/location/city_map.gd")
const Arena := preload("res://mods/pax_rpg/src/location/arena.gd")
const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
const Iai := preload("res://mods/pax_rpg/src/location/iai.gd")
const City := preload("res://mods/pax_rpg/src/location/city.gd")
const Landscape := preload("res://mods/pax_rpg/src/location/landscape.gd")
const Npc := preload("res://mods/pax_rpg/src/location/npc.gd")
const HelpPanel := preload("res://mods/pax_rpg/src/location/help_panel.gd")
const PauseMenu := preload("res://mods/pax_rpg/src/location/pause_menu.gd")
const Sfx := preload("res://mods/pax_rpg/src/location/sfx.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Music := preload("res://mods/pax_rpg/src/location/music.gd")
const AudioBus := preload("res://mods/pax_rpg/src/location/audio_bus.gd")
const CityTitle := preload("res://mods/pax_rpg/src/location/city_title.gd")
const Wrist := preload("res://mods/pax_rpg/src/ui/wrist.gd")
const Talk := preload("res://mods/pax_rpg/src/location/talk.gd")
const Forest := preload("res://mods/pax_rpg/src/location/forest.gd")
const Quest := preload("res://mods/pax_rpg/src/location/quest.gd")
const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const Wind := preload("res://mods/pax_rpg/src/location/wind.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const Gfx := preload("res://mods/pax_rpg/src/location/gfx.gd")
const Grass := preload("res://mods/pax_rpg/src/location/grass.gd")
const Rift := preload("res://mods/pax_rpg/src/location/rift.gd")
const Inventory := preload("res://mods/pax_rpg/src/location/inventory.gd")
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
var _prev_action := ""
var _quake_cd := 0.0                 # с до готовности «Земного разлома»
var _quake_waves_done := 0
var _vfx: Vfx
var _vignette: ColorRect
var _iai: Iai                         # «Иай: остановка времени» (V)
var _iai_cd := 0.0
var _quake_icon: Texture2D
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
var _arena_cfg: Array = []          # арена города из планировки: [x, z, радиус ямы, вход]
var _arena: Arena                    # бои на арене (arena.gd)
var _city_map: CityMap               # карта города (M)
var _help: HelpPanel               # кнопка и окно «Управление» (H)
var _pause: PauseMenu              # меню паузы (Esc)
var _sfx: Sfx                      # шаги, снаряжение, гул города
var _music: Music                  # фоновая музыка (music.gd)
var _sens := 1.0                   # чувствительность мыши (меню паузы → Настройки)
var _zoom_want := 0.0              # куда крутят колесом; _zoom догоняет плавно, с лёгкой задержкой
var _zoom := 0.0                   # приближение камеры колесом: 0 — обычная даль, 1 — как в бою (за плечом)
var _was_floor := true
var _body_turn := false
var _reface := 0.0                  # с: после уворота в захвате герой быстро разворачивается обратно к врагу
var _shake := 0.0                   # с: тряска камеры от попадания (затухает)
var _shake_amp := 0.0
var _city_leaves: Array = []
var _city_lights: Array = []
var _city_smoke: Array = []
var _city_glass: Array = []
var _city_paper: Array = []
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _daynight: DayNight            # тело доворачивается к цели (голова уже не достаёт)
var _gfx: Gfx                       # качество картинки (gfx.gd, config/location.json → gfx)
var _shoulder := 1.0               # плечо камеры в захвате: 1 — правое, −1 — левое (Z)
var _inv: Inventory                # инвентарь (TAB)
var _wrist: Wrist                  # наручный терминал (TAB / Esc): инвентарь, карта, меню
var _talk: Talk                    # разговор с жителем (E рядом) — через нейросеть игры
var _talk_npc: Node                # ближайший житель в 2.5 м (ему — подсказка «E · имя»)
var _npcs: Array = []
var _talk_t := 0.0
var city_data: Dictionary = {}     # что за место построено (config/cities.json; лес задания — {"id": "forest", "seed"})
var _quest_item: Node3D            # находка задания в лесу (светится; вошёл в зону — взял)
var building := false              # город ещё строится (по кадрам) — экран загрузки ждёт is_ready()
var _build_gen := 0                # номер стройки: clear() посреди неё — старая сопрограмма бросает работу
var _build_finished := false
var _grass: Grass
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


## Орк-чемпион перед героем (консоль rpg_orc — проверка боя).
func spawn_orc() -> String:
	if _view == null or not is_instance_valid(_player):
		return "нет локации"
	var g := Orc.new()
	var fwd := Vector3(-sin(_body_mesh.rotation.y), 0.0, -cos(_body_mesh.rotation.y))
	g.setup(mod, _player, _on_hero_hit, _player.global_position + fwd * 8.0, _hero_attacking, _hero_blocking)
	_view.add_child(g)
	_goblins.append(g)
	return "orc spawned"


func _hp_max() -> float:
	return HERO_HP * (_prog.hp_mult() if _prog != null else 1.0)


func _pos_max() -> float:
	return HERO_POSTURE * (_prog.posture_mult() if _prog != null else 1.0)


## Готова ли локация (экран загрузки не открывает её раньше — travel.gd).
func is_ready() -> bool:
	return not building


## Заранее, ещё на глобусе: горы и степь городов считаются в потоке — к входу в город уже готовы.
func prewarm() -> void:
	var parsed: Variant = JSON.parse_string(mod.read_text("config/cities.json"))
	if not (parsed is Dictionary):
		return
	for c: Variant in (parsed as Dictionary).get("cities", []):
		var layout := _city_layout(str((c as Dictionary).get("id", "")))
		if not layout.is_empty() and bool(layout.get("landscape", true)):
			Landscape.request(Landscape.area_of(layout))


## Сопрограмма для города (строится несколько кадров, экран загрузки живой); арена без города — сразу.
func build(city: Dictionary) -> void:
	clear()
	_input_first()
	_build_gen += 1
	var gen := _build_gen
	building = true
	_build_finished = false
	_load_t0 = Time.get_ticks_msec()
	_mark("start " + str(city.get("id", "")))
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
	_view.msaa_3d = Viewport.MSAA_2X                 # 4x на 1440p съедал треть кадра
	_box.add_child(_view)
	_gfx = Gfx.new()
	_gfx.setup(cfg.get("gfx", {}) as Dictionary)
	_gfx.mod = mod
	_gfx.load_overrides()                            # свои настройки игрока (меню «Графика») главнее конфига
	_gfx.apply_viewport(_view)                       # TAA / FSR2 вместо MSAA, debanding
	_gfx.push_globals()
	_map_rects.clear()
	_make_sky()
	_city_lights = []
	_city_glass = []
	_city_paper = []
	city_data = city
	var layout := Forest.generate(int(city.get("seed", 0)), Quest.get_q(mod)) if str(city.get("id", "")) == "forest" \
		else _city_layout(str(city.get("id", "")))
	START = ARENA_START
	_gate_radius = GATE_RADIUS
	var goblins := int(cfg.get("goblins", 1))
	if layout.is_empty():
		_arena_cfg = []
		_make_ground()
		_make_gate()
	else:                                            # настоящий город: планировка config/<id>.json
		var c := City.new()
		_mark("city…")
		await c.build(mod, _view, layout)              # по кадрам, горы и степь — из потока
		_mark("city done (%d items)" % c.count)
		if gen != _build_gen or c.cancelled or not is_instance_valid(_view):
			return                                     # локацию убрали посреди стройки
		_arena_cfg = layout.get("arena", [])
		_map_rects.append_array(c.rects)
		_grass = Grass.new()                           # сплошная трава с ветром: считается в потоке
		var gcfg: Dictionary = (cfg.get("gfx", {}) as Dictionary).duplicate()
		gcfg["grass_density"] = float(mod.get_setting("gfx_grass_density", gcfg.get("grass_density", 6.0)))
		_grass.start(mod, _view, layout, c.rects, gcfg, _check_ready.bind(gen))
		_mark("grass started")
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
		if layout.has("quest_item"):
			_make_quest_item.call_deferred(layout)       # после героя (гоблинам нужен герой)
		_shots = layout.get("shots", [])
		if not layout.has("forest"):                  # лес задания — без портала: выход в наручном терминале
			_make_portal()
		else:
			_gate_radius = 0.0
		var probe := ReflectionProbe.new()             # отражения неба и улиц в стёклах (снимок — один раз)
		probe.size = Vector3(200.0, 50.0, 200.0)
		probe.position = Vector3(0.0, 12.0, 0.0)
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.box_projection = false
		probe.intensity = 1.0
		_view.add_child(probe)
		_gfx.probe = probe
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
	if _arena_cfg.size() >= 3:
		_arena = Arena.new()
		add_child(_arena)
		_arena.setup(mod, _view, self, _arena_cfg, _player, _arena_spawn, func() -> void:
			_hp = _hp_max()
			_posture = 0.0)
		_arena.toast.connect(func(t: String) -> void: _toast = {"text": t, "t": 0.0})
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_view.add_child(_cam)
	_cam.current = true
	_mark("player, enemies")
	_gfx.cam = _cam
	_gfx.player = _player
	_gfx.lights = _city_lights
	_gfx.daynight = _daynight
	_gfx.sun = _sun
	_view.add_child(_gfx)
	_hud = Hud.new()
	_hud.setup(mod, mod.texture(str(hero_cfg.get("enemy_portrait", "models/goblin/portrait.png"))))
	_hud.apply_theme(str(mod.get_setting("character", "black_knight")))   # палитра HUD — своя у каждого героя
	add_child(_hud)
	if not is_instance_valid(_vignette):
		_add_vignette()
	_iai = Iai.new()
	add_child(_iai)
	move_child(_iai, _vignette.get_index() + 1)
	_iai.setup(mod, _view, _hero, _player, _cam, func() -> Array: return _goblins, _iai_cut,
		_mana_burst,
		func(on: bool) -> void:
			if is_instance_valid(_hud):
				_hud.visible = on)
	_iai.finished.connect(func(interrupted: bool) -> void:
		if interrupted:
			_iai_cd = _hf("iai_cooldown", 90.0) * 0.5)
	_inv = Inventory.new()
	_inv.setup(mod)
	add_child(_inv)
	_inv.closed.connect(func() -> void: _set_inventory(false))
	_wrist = Wrist.new()
	_wrist.setup(mod, _hud)
	add_child(_wrist)
	_wrist.picked.connect(_on_wrist)
	_talk = Talk.new()
	_talk.setup(mod, _hud)
	add_child(_talk)
	_talk.closed.connect(_end_talk)
	_inv.stat_added.connect(func(key: String) -> void:
		if _prog.add_stat(key):
			_set_inventory(false)
			_set_inventory(true))                  # открыть заново — числа и урон пересчитаны
	_city_map = CityMap.new()
	_city_map.setup(mod)
	_city_map.set_city(layout)
	add_child(_city_map)
	_help = HelpPanel.new()
	_help.setup(mod)
	_help.toggled.connect(func(on: bool) -> void:
		if not paused():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED)
	add_child(_help)
	_sfx = Sfx.new()
	_sfx.setup(mod, not layout.is_empty())
	add_child(_sfx)
	AudioBus.ensure(mod)
	_sens = float(mod.get_setting("mouse_sens", 1.0))
	_music = Music.new()
	_music.setup(mod, not layout.is_empty())
	_music.daynight = _daynight
	add_child(_music)
	_pause = PauseMenu.new()
	_pause.setup(mod, mod.tr_key("pax_rpg_pause_leave"), cfg.get("gfx", {}) as Dictionary)
	_pause.visible = false
	_pause.resume.connect(_set_paused.bind(false))
	_pause.sens_changed.connect(func(v: float) -> void: _sens = v)
	_pause.fog_changed.connect(_apply_volfog)
	_pause.gfx_changed.connect(func(key: String, value: Variant) -> void:
		if is_instance_valid(_gfx):
			_gfx.set_option(key, value))
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
		if _daynight != null:
			ct.sub = DayNight.label(mod, _daynight.hour)   # под названием — время суток (в городе оно стоит)
		add_child(ct)
		ct.play(3.4)                                   # после экрана загрузки (он раскрывается ~3 с после готовности)
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
	_game_3d(false)
	if is_instance_valid(_gfx):
		_gfx.apply_frame_limits()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # камера — мышью, без зажатой кнопки (ПКМ — блок)
	_build_finished = true
	_mark("build done")
	if not layout.is_empty():
		_warmup()                                    # шейдеры боя — под закрытым экраном загрузки
	_check_ready(gen)


## 3D игры (глобус, космос) под локацией не видно, но оно рисовалось каждый кадр — пока герой в городе, окно игры
## не рисует свой 3D (свой мир локации — в своём SubViewport и рисуется дальше).
func _game_3d(on: bool) -> void:
	var root := get_tree().root
	if root != null:
		root.disable_3d = not on


## Всё построено и трава встала — локацию можно показывать.
func _check_ready(gen: int) -> void:
	if gen == _build_gen and _build_finished and (_grass == null or _grass.done) and building:
		building = false
		_mark("ready (grass %d)" % (_grass.count if _grass != null else 0))
		get_tree().create_timer(0.5).timeout.connect(func() -> void:   # облака, блики, размытие — уже после загрузки
			if gen == _build_gen and is_instance_valid(_gfx):
				_gfx.apply_camera(_cam, _sun))


## Журнал загрузки (godot.log): этап и секунды от начала — видно, где загрузка теряет время.
var _load_t0 := 0


func _mark(stage: String) -> void:
	print("[pax_rpg] load %.2f s: %s" % [(Time.get_ticks_msec() - _load_t0) / 1000.0, stage])


## Прогрев шейдеров: эффекты, которые впервые появятся только в бою (искры со шлейфом, вспышка, лужа крови, разрез
## и рыбий глаз иая), один раз рисуются перед камерой, пока экран загрузки закрыт, — их шейдеры и конвейеры
## компилируются сейчас, а не рывком на первом ударе.
func _warmup() -> void:
	if not is_instance_valid(_cam) or not is_instance_valid(_view):
		return
	var at := _cam.global_position - _cam.global_transform.basis.z * 3.0
	_sparks(at, Color(1.0, 0.8, 0.35), 4, 1.0)
	Goblin.blood_decal(_view, at - Vector3(0.0, 1.0, 0.0))
	Rift.warm(mod, _view, at - Vector3(0.0, 1.0, 0.0))   # «Разлом»: трещины, шипы, их шейдеры — сейчас, а не рывком в бою
	if is_instance_valid(_iai):
		_iai.warmup(at)

func clear() -> void:
	_build_gen += 1                                  # недостроенный город бросает стройку
	building = false
	_build_finished = false
	_grass = null
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_game_3d(true)
		if is_instance_valid(_gfx):
			_gfx.leave_frame_limits()
	active = false
	visible = false
	_turning = false
	for n: Node in [_box, _hud, _pause, _sfx, _help, _music, _city_map, _arena, _vignette, _iai, _inv, _wrist, _talk]:
		if is_instance_valid(n):
			n.queue_free()
	Assets.clear_tracking(mod)
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
	env.tonemap_exposure = 0.92
	var fplus := RenderingServer.get_current_rendering_method() == "forward_plus"   # SSAO и SSR — только в Forward+
	env.ssao_enabled = fplus                         # тени в углах и под крышами
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.glow_enabled = true                          # фонари, мана, вода фонтана светятся
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95                    # светится только по-настоящему яркое: огонь, ореолы, мана
	env.glow_hdr_scale = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true                           # розовая дымка маны вдали
	env.fog_light_color = Color(0.95, 0.62, 0.8)
	env.fog_density = 0.0016                         # реже: за стеной видны холмы и горы в дымке
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.3
	env.ssr_enabled = fplus                          # стёкла окон и лужи отражают город
	env.ssr_max_steps = 24
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0                   # цвет даёт LUT: тёплые света против холодных теней
	env.adjustment_color_correction = _grade_lut()      # общий тон Юрумы: тёплые света, сиреневые тени
	_env = env
	_apply_volfog(float(mod.get_setting("vol_fog", 0.5)))
	var we := WorldEnvironment.new()
	we.environment = env
	_gfx.apply_env(env, we)                          # отражённый свет, SSIL, туман у земли, экспозиция, DOF
	_view.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 145.0, 0.0)   # низкое тёплое солнце — длинные тени по улицам
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0       # дальше тени не видны за дымкой, а каждый метр — лишняя отрисовка
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_gfx.apply_sun(sun)                              # мягкие тени по угловому размеру солнца
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
		npc.set("npc_index", n)
		npc.set("relation", Quest.relation(mod, str(city_data.get("id", "")), n, int(npc.get("relation"))))
		_view.add_child(npc)
		_npcs.append(npc)


## Находка задания: светящаяся вещь на поляне (зона 1.6 м), рядом — гоблины задания (quest_goblins).
func _make_quest_item(layout: Dictionary) -> void:
	var q := Quest.get_q(mod)
	var at: Array = layout.quest_item
	var pos := Vector3(float(at[0]), 0.0, float(at[1]))
	if str(q.get("state", "")) == "active":
		_quest_item = Node3D.new()
		_quest_item.position = pos
		_view.add_child(_quest_item)
		var gem := MeshInstance3D.new()
		var sm := PrismMesh.new()
		sm.size = Vector3(0.35, 0.5, 0.35)
		gem.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.3)
		mat.emission_energy_multiplier = 2.5
		gem.material_override = mat
		gem.position = Vector3(0.0, 0.9, 0.0)
		_quest_item.add_child(gem)
		var tw := gem.create_tween().set_loops()
		tw.tween_property(gem, "rotation:y", TAU, 3.0).from(0.0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.4)
		l.light_energy = 1.4
		l.omni_range = 5.0
		l.light_volumetric_fog_energy = 0.0
		l.position = Vector3(0.0, 1.2, 0.0)
		_quest_item.add_child(l)
		var lb := Label3D.new()
		lb.text = mod.tr_key("pax_rpg_qitem_" + str(q.get("item", "amulet")))
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 48
		lb.outline_size = 10
		lb.pixel_size = 0.004
		lb.position = Vector3(0.0, 1.6, 0.0)
		_quest_item.add_child(lb)
	for i: int in int(layout.get("quest_goblins", 0)):    # стерегут находку
		var g := Goblin.new()
		var a := TAU * i / maxf(1.0, float(layout.get("quest_goblins", 1)))
		g.setup(mod, _player, _on_hero_hit, pos + Vector3(cos(a) * 4.0, 1.0, sin(a) * 4.0), _hero_attacking, _hero_blocking)
		_view.add_child(g)
		_goblins.append(g)


## Герой у находки (1.6 м) — вещь у него: задание «найдено», вернуться к жителю.
func _quest_pickup() -> void:
	if not is_instance_valid(_quest_item) or not is_instance_valid(_player):
		return
	if _quest_item.global_position.distance_to(_player.global_position) < 1.6:
		Quest.found(mod)
		var q := Quest.get_q(mod)
		_toast = {"text": mod.tr_key("pax_rpg_quest_found") % [mod.tr_key("pax_rpg_qitem_" + str(q.get("item", ""))),
			str(q.get("npc_name", ""))], "t": 0.0}
		_quest_item.queue_free()
		_quest_item = null


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
	q.size = Vector2(5.0, 5.4)                       # по проёму ворот (между створками ~5.4 м), не шире
	glow.mesh = q
	var sh: Shader = mod.shader("shaders/portal.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		glow.material_override = m
	glow.position = _gate_pos + Vector3(0.0, 2.7, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.85)
	l.light_energy = 1.2
	l.omni_range = 7.0
	l.light_volumetric_fog_energy = 0.0                # в объёмный туман не светит: его ячейки проступали квадратами
	l.position = _gate_pos + Vector3(0.0, 2.0, -1.5)
	_view.add_child(l)
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.3, 0.2, 0.4)
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
	if not on:
		_pause.reset_view()
	if is_instance_valid(_box):
		_box.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_rmb = false
	_lmb_queued = false


## Пассивка «Железная стена» (config/hero.json → character.block_reduce): доля урона, которую блок гасит сверх обычного.
func _block_reduce() -> float:
	var ch: Variant = hero_cfg.get("character", {})
	if ch is Dictionary and str((ch as Dictionary).get("passive", "")) == "iron_wall":
		return clampf(float((ch as Dictionary).get("block_reduce", 0.3)), 0.0, 0.9)
	return 0.0


func _character() -> Dictionary:
	var ch: Variant = hero_cfg.get("character", {})
	return ch if ch is Dictionary else {}


## Характеристики персонажа (config/hero.json → character.attributes) + очки, вложенные за уровни.
func _attributes() -> Dictionary:
	var base: Dictionary = {}
	var ch: Variant = hero_cfg.get("character", {})
	if ch is Dictionary and (ch as Dictionary).get("attributes", {}) is Dictionary:
		base = (ch as Dictionary)["attributes"]
	return _prog.attributes(base) if _prog != null else base


## Масштабирование оружия героя (character.weapon.scaling, буквы как в DS3).
func _weapon_scaling() -> Dictionary:
	var w: Variant = _character().get("weapon", {})
	if w is Dictionary and (w as Dictionary).get("scaling", {}) is Dictionary:
		return (w as Dictionary)["scaling"]
	return {}


## Урон героя: рост от уровня × масштабирование оружия от характеристик.
func _dmg_mult() -> float:
	return _prog.damage_mult() * Progress.scaling_mult(_weapon_scaling(), _attributes())


func paused() -> bool:
	return (is_instance_valid(_pause) and _pause.visible) or (is_instance_valid(_inv) and _inv.visible) 		or (is_instance_valid(_wrist) and _wrist.visible) or (is_instance_valid(_talk) and _talk.visible)


## Ближайший житель в 2.5 м — подсказка над ним (раз в 0.2 с).
func _talk_scan(delta: float) -> void:
	_talk_t -= delta
	if _talk_t > 0.0 or not is_instance_valid(_player):
		return
	_talk_t = 0.2
	var best: Node = null
	var bd := 2.5
	for n: Variant in _npcs:
		if not is_instance_valid(n):
			continue
		var d := (n as Node3D).global_position.distance_to(_player.global_position)
		if d < bd:
			bd = d
			best = n
	if best != _talk_npc:
		if is_instance_valid(_talk_npc):
			_talk_npc.call("show_prompt", false)
		_talk_npc = best
	if is_instance_valid(_talk_npc) and not (is_instance_valid(_talk) and _talk.visible):
		_talk_npc.call("show_prompt", true)


func _start_talk() -> void:
	if not is_instance_valid(_talk_npc) or not is_instance_valid(_talk):
		return
	if is_instance_valid(_arena) and _arena.fighting:
		return                                       # в бою не до разговоров
	_talk_npc.call("talk", true, _player.global_position)
	var place := {"city": _city_name, "hero": mod.tr_key("pax_rpg_hero_name"), "hero_title": mod.tr_key("pax_rpg_hero_title")}
	if _daynight != null and is_instance_valid(_daynight):
		place["time"] = DayNight.label(mod, _daynight.hour)
	place["city_data"] = city_data
	_talk.context = place
	_talk.open(_talk_npc)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rmb = false
	_lmb_queued = false


func _end_talk() -> void:
	if is_instance_valid(_talk_npc):
		_talk_npc.call("talk", false)
	if not paused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Клавиши — сначала локации: _input идёт с конца дерева, а узлы мира игры созданы позже мода и раньше ловили Esc —
## под локацией открывалось меню паузы игры, и после выхода из города игрок оказывался в нём. Последний ребёнок корня
## получает ввод первым.
func _input_first() -> void:
	var root := get_tree().root
	if get_parent() != root:
		reparent.call_deferred(root)
	else:
		root.move_child.call_deferred(self, -1)


## Наручный терминал: над левым запястьем героя; мир на паузе, мышь — интерфейсу.
func _set_wrist(on: bool) -> void:
	if not is_instance_valid(_wrist):
		return
	if on:
		var at := Vector2(get_viewport().get_visible_rect().size * Vector2(0.3, 0.7))
		if _hero != null and is_instance_valid(_cam):
			var wp: Vector3 = _hero.bone_pos("LeftHand")
			if not _cam.is_position_behind(wp):
				at = _cam.unproject_position(wp)
		var extra: Array = []
		if str(city_data.get("id", "")) == "forest":
			extra.append(["leave", "pax_rpg_wrist_leave", ""])
		_wrist.open_at(at, extra)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_wrist.close()
		if not paused():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_rmb = false
	_lmb_queued = false


func _on_wrist(id: String) -> void:
	_set_wrist(false)
	match id:
		"inventory":
			_set_inventory(true)
		"map":
			if is_instance_valid(_city_map):
				_city_map.toggle()
		"menu":
			_set_paused(true)
		"leave":
			exit_requested.emit()


## Инвентарь (TAB): мир на паузе, мышь — интерфейсу; закрыть — TAB или Esc.
func _set_inventory(on: bool) -> void:
	if not is_instance_valid(_inv):
		mod.log_error("Pax RPG: inventory is missing")
		return
	if on and _inv.visible:
		return
	mod.log_info("Pax RPG: inventory %s" % ("open" if on else "closed"))
	if on:
		var st := {"hp_abs": _hp, "hp_max": _hp_max(), "posture": _posture / _pos_max(), "level": _prog.level,
			"xp_abs": _prog.xp, "xp_need": _prog.need(), "attributes": _attributes()}
		st["main_stat"] = str(_character().get("main_stat", ""))
		st["passive"] = str(_character().get("passive", ""))
		st["scaling"] = _weapon_scaling()
		st["weapon"] = str((_character().get("weapon", {}) as Dictionary).get("name", "")) if _character().get("weapon", {}) is Dictionary else ""
		st["dmg_mult"] = _dmg_mult()
		st["stat_points"] = _prog.stat_points()
		st["level_mult"] = _prog.damage_mult()
		st["model"] = str(hero_cfg.get("model", "models/knight.glb"))
		_inv.open(_view, _player, _body_mesh, _hero, st)
	else:
		_inv.visible = false
	if is_instance_valid(_box):
		_box.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(_hud):
		_hud.visible = not on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_rmb = false
	_lmb_queued = false


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(_player) or paused():
		return
	var t0 := Time.get_ticks_usec()
	_goblins = _goblins.filter(func(g: Variant) -> bool: return is_instance_valid(g))   # павшие на арене — удалены
	_quake_cd = maxf(0.0, _quake_cd - delta)
	_iai_cd = maxf(0.0, _iai_cd - delta)
	_physics_body(delta)
	Prof.add("локация физика", t0)


## «Земной разлом» (T): тратит концентрацию героя (риск — переполнится, стойка сломана), перезарядка quake_cooldown;
## пока герой на колене, раз в секунду волна: всё ближе радиуса волны получает урон, теряет равновесие, отлетает.
func _iai_try() -> void:
	if _hero == null or not is_instance_valid(_iai) or _iai_cd > 0.0 or _stagger > 0.0 or not _player.is_on_floor():
		return
	if _iai.start():
		_iai_cd = _hf("iai_cooldown", 90.0)


## Выброс маны из разреза (финал Иай): светящиеся сгустки поднимаются и гаснут, немного искр — густо, но без каши.
func _mana_burst(at: Vector3, c: Color) -> void:
	if _vfx == null:
		_vfx = Vfx.new(mod)
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	q.material = _vfx._glow_mat(c, 1.8)
	p.mesh = q
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 34
	p.lifetime = 1.3
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, 0.8, 0)                       # мана лёгкая — уходит вверх
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.add_point(0.4, Color(1, 0.8, 1, 0.8))
	ramp.set_color(1, Color(1, 0.6, 1, 0))
	p.color_ramp = ramp
	_view.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	_sparks(at, c, 28, 5.0)


## Финал Иай: удар по каждому, кого задели разрезы. Рядовые падают, у босса — тяжёлый урон и сбитая стойка.
func _iai_cut(v: Node) -> void:
	var g := v as Goblin
	if g == null or not g.is_alive():
		return
	var dmg := _hf("iai_damage", 60.0) * _dmg_mult()
	if not g.boss and is_instance_valid(_cam):          # разрез — по диагонали кадра: тело рубится пополам
		var cb := _cam.global_transform.basis
		var line := cb.x.rotated(-cb.z, randf_range(-1.0, 1.0))
		g.mark_slice((-cb.z).cross(line))
	g.take_damage(dmg if g.boss else maxf(dmg, g.hp + 1.0), _player.global_position, not g.boss)
	g.posture = minf(g.max_posture, g.posture + (g.max_posture * 0.4 if g.boss else g.max_posture))
	if not g.boss:
		g.deathblow()                                    # щелчок цубы — падает сразу, без «на коленях»
	_numbers.append({"pos": g.global_position + Vector3(0, 1.4, 0), "v": int(dmg), "crit": true, "t": 0.0})


func _quake_tex() -> Texture2D:
	if _quake_icon == null:
		_quake_icon = mod.texture("textures/icon_quake.png")
	return _quake_icon


func _quake_try() -> void:
	if _hero == null or _quake_cd > 0.0 or _stagger > 0.0 or not _player.is_on_floor():
		return
	if not _hero.quake(true):
		return
	_quake_cd = _hf("quake_cooldown", 30.0)
	_quake_waves_done = 0
	_posture = minf(_pos_max(), _posture + _hf("quake_posture", 35.0))
	_since_hit = 0.0
	if _posture >= _pos_max():                     # перебрал — стойка сломана прямо в приёме
		_posture = _pos_max() * 0.35
		_stagger = _hf("guard_break_time", 1.2)


func _quake_step() -> void:
	if _hero == null or _hero.action != "Quake" or _hero.quake_since < 0.0:
		return
	var waves: Array = hero_cfg.get("quake_waves", [[3.0, 22.0], [5.5, 18.0], [8.0, 15.0]])
	if _quake_waves_done < waves.size() and _hero.quake_since >= float(_quake_waves_done):
		var w: Array = waves[_quake_waves_done]
		_quake_wave(float(w[0]), float(w[1]), _quake_waves_done)
		_quake_waves_done += 1


func _quake_wave(radius: float, dmg: float, i: int) -> void:
	var c := _player.global_position - Vector3(0, 0.9, 0)
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var d := Vector2(gob.global_position.x - c.x, gob.global_position.z - c.z).length()
		if d <= radius:
			gob.take_damage(dmg * _dmg_mult(), c, i == 2)          # последняя волна — отбрасывает
			gob.posture = minf(gob.max_posture, gob.posture + dmg * 0.8)
			if d >= maxf(0.0, radius - 3.0):                               # шипы на кольце волны — подбрасывают
				var away := Vector3(gob.global_position.x - c.x, 0.0, gob.global_position.z - c.z).normalized()
				gob.launch(away * 2.5 + Vector3(0.0, 7.5 if not gob.boss else 3.5, 0.0))
			_numbers.append({"pos": gob.global_position + Vector3(0, 1.3, 0), "v": int(dmg), "crit": i == 2, "t": 0.0})
	if _sfx != null:
		_sfx.impact()
	# «Разлом» Разрубателя: земля раскалывается (декаль трещин с глубиной), по кольцу волны — земляные шипы
	var waves: Array = hero_cfg.get("quake_waves", [[3.0, 22.0], [5.5, 18.0], [8.0, 15.0]])
	if i == 0:
		Rift.crack(mod, _view, c, float((waves[waves.size() - 1] as Array)[0]) + 1.5, 7.0)
	Rift.spikes(mod, _view, c, maxf(0.9, radius - 2.5), radius, int(radius * 2.2), 0.35)
	# волна: пыль по кругу (без светящегося кольца — земля трескается, а не светится)
	if _vfx == null:
		_vfx = Vfx.new(mod)
	var dust := _vfx.smoke(_view, c + Vector3(0, 0.2, 0), 0.9 + i * 0.3, Color(0.7, 0.58, 0.5, 0.5), 18, 1.4)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.preprocess = 0.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = radius
	dust.emission_ring_inner_radius = radius * 0.8
	dust.emission_ring_height = 0.1
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
	_sparks(c + Vector3(0, 0.3, 0), Color(0.62, 0.48, 0.36), 30 + i * 10, 6.0)   # каменная крошка, не мана


func _physics_body(delta: float) -> void:
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
		_hero.lock_on = _lock != null
	if _lock != null and (not is_instance_valid(_lock) or not (_lock as Goblin).is_alive()
			or _lock.global_position.distance_to(_player.global_position) > 22.0):
		_set_lock(null)
	if _lmb_queued and _hero != null and _stagger <= 0.0:
		if not _try_deathblow():
			if _hero.action == "":
				_face_now(_aim_yaw())                # удар — куда смотрит камера (мышь); при захвате — во врага
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
		# в захвате — как в соулсах: лицом к врагу; назад — отскок, вбок — уклон, вперёд — кувырок
		var dir := ""
		if _lock != null and wish.length() > 0.01:
			var ty := _aim_yaw()
			var lf := Vector3(-sin(ty), 0.0, -cos(ty))
			var lr := Vector3(cos(ty), 0.0, -sin(ty))
			var w := wish.normalized()
			var fy := w.dot(lf)
			if fy < -0.5:
				dir = "B"
			elif fy < 0.6:
				dir = "R" if w.dot(lr) > 0.0 else "L"
			if dir != "":
				_face_now(ty)
		if _hero.dodge(on_floor, dir):
			if _hero.side_dodge():
				pass                                     # уклон — лицом к врагу, смещение ведёт root motion клипа
			elif wish.length() > 0.01:
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
	vel.x = move.x * speed
	vel.z = move.z * speed
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
			if moving or _reface > 0.0 or (_hero != null and (_hero.blocking or _hero_attacking())):
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
			# цель за спиной (бежит от врага в захвате) — голову отпускаем: иначе она упирается в предел и «кивает»
			var to := _lock.global_position - _player.global_position
			var off := absf(angle_difference(_body_mesh.rotation.y, atan2(-to.x, -to.z)))
			if off < deg_to_rad(_hf("head_limit", 70.0) * _hf("look_release", 1.0)):
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
		var th := Time.get_ticks_usec()
		var r: Dictionary = _hero.tick(delta, moving, speed * move.length(), running, on_floor)
		Prof.add("герой (с плащом)", th)
		if _hero.action != _prev_action and _hero.action.begins_with("Attack"):
			_face_now(_aim_yaw())                    # каждый удар серии — заново туда, куда смотрит камера
		if _prev_action.begins_with("Dodge") and _hero.action == "" and _lock != null:
			_reface = _hf("reface_time", 0.35)
		_reface = maxf(0.0, _reface - delta)
		_prev_action = _hero.action
		_quake_step()
		var step: Vector3 = r.root
		if r.has("hit"):
			_strike(r.hit)
		if r.has("blade"):
			_blade_strike(r.blade)
		if step != Vector3.ZERO and delta > 0.0:
			# смещение клипа — в осях модели; модель повёрнута вместе с _body_mesh (и на PI внутри него)
			var w := _body_mesh.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI) * step
			vel.x = w.x / delta
			vel.z = w.z / delta
		if mag != null:
			vel = _magnet_pull(vel, mag, delta)
	_player.velocity = vel
	var was := _player.global_position
	var tm := Time.get_ticks_usec()
	_player.move_and_slide()
	Prof.add("движение героя", tm)
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
	var tc := Time.get_ticks_usec()
	_follow_camera(delta)
	Prof.add("камера", tc)
	if is_instance_valid(_arena):
		_arena.tick()
	_quest_pickup()
	var near := Vector2(_player.position.x - _gate_pos.x, _player.position.z - _gate_pos.z).length() < _gate_radius
	if near != _near_gate:
		_near_gate = near
		_update_hud()


## Отладка (консоль rpg_probe): всё видимое в радиусе 2 м от героя — имя, родитель, высота над ступнями.
func probe() -> String:
	if not is_instance_valid(_player):
		return "нет героя"
	var out: PackedStringArray = []
	var feet := _player.global_position.y - 0.9
	var stack: Array = [_view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
			var g := n as GeometryInstance3D
			var d := Vector2(g.global_position.x - _player.global_position.x, g.global_position.z - _player.global_position.z)
			if d.length() < 2.0:
				out.append("%s (%s) ← %s, h=%.2f" % [g.name, g.get_class(), g.get_parent().name, g.global_position.y - feet])
	mod.log_info("[pax_rpg] probe:\n" + "\n".join(out))
	return "%d объектов рядом — список в логе" % out.size()


## Боец арены (arena.gd): гоблин или орк-чемпион, как обычные враги локации.
func _arena_spawn(kind: String, pos: Vector3) -> Node:
	var g: Goblin = Orc.new() if kind == "orc" else Goblin.new()
	g.setup(mod, _player, _on_hero_hit, pos, _hero_attacking, _hero_blocking)
	_view.add_child(g)
	_goblins.append(g)
	return g


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
	if is_instance_valid(_iai) and _iai.cam_override:
		return                                       # камерой правит «Иай»
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
		# за плечом (Z — сменить плечо): чуть сбоку и позади — враг открыт, спина не закрывает обзор
		var shoulder := _player.position + Vector3(0.0, _f("lock_camera_height", 1.7), 0.0) \
			+ right * _f("lock_camera_side", 1.05) * _shoulder + back * _f("lock_camera_distance", 3.2)
		var enemy := _lock_point if want == 0.0 else _lock.global_position + Vector3(0.0, 0.9, 0.0)
		if want > 0.0:
			_lock_point = enemy
		var lock_look := (_player.position + Vector3(0.0, 1.3, 0.0)).lerp(enemy, 0.65)
		pos = free_pos.lerp(shoulder, k)
		look = target.lerp(lock_look, k)
	if _shake > 0.0 and delta > 0.0:
		# тряска от попадания: короткая, затухает; смещаем и камеру, и точку взгляда — картинка вздрагивает целиком
		_shake = maxf(0.0, _shake - delta)
		var a := _shake_amp * _shake / maxf(_f("shake_time", 0.18), 0.01)
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * a
		pos += off
		look += off * 0.6
	var sway := _f("camera_sway", 0.0)                # по умолчанию выкл.: RPG, а не съёмка с плеча
	if sway > 0.0 and is_instance_valid(_player):
		# «ручная» камера (приём Bodycam): дыхание в покое, покачивание на бегу — кадр живой, а не на штативе
		var t := Time.get_ticks_msec() * 0.001
		var run := clampf(Vector2(_player.velocity.x, _player.velocity.z).length() / maxf(_f("run_speed", 5.0), 0.1), 0.0, 1.0)
		var amp := sway * (0.012 + 0.035 * run)
		var hand := Vector3(sin(t * 1.1) * 0.6 + sin(t * 2.3 + 1.7) * 0.4,
			sin(t * 1.7 + 0.5) * 0.5 + sin(t * 3.1) * 0.3 + sin(t * 9.0) * 0.25 * run, 0.0) * amp
		hand = _cam.global_transform.basis * hand
		pos += hand
		look += hand * 0.35
	_cam.position = pos
	_cam.look_at(look, Vector3.UP)


## Вес попадания: герой и враг замирают на миг (hitstop), камера вздрагивает. Тяжёлый удар — дольше и сильнее.
## Несколько врагов одним взмахом — замирание не складывается.
func _impact_feel(gob: Goblin, heavy: bool) -> void:
	var t := _hf("hitstop_heavy", 0.14) if heavy else _hf("hitstop", 0.08)
	if _hero != null:
		_hero.hitstop(t)
	if is_instance_valid(gob):
		gob.hitstop(t)
	_shake = _f("shake_time", 0.18)
	_shake_amp = _hf("shake_heavy", 0.09) if heavy else _hf("shake", 0.045)


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
		gob.take_damage(float(hit.damage) * _dmg_mult(), _player.global_position, bool(hit.get("knock", false)))
		_impact_feel(gob, bool(hit.get("knock", false)))
		_numbers.append({"pos": gob.global_position + Vector3(randf_range(-0.3, 0.3), 1.3, 0.0),
			"v": int(hit.damage), "crit": bool(hit.get("knock", false)), "t": 0.0})


## Удар клинком по пути: враг задет, если полоса клинка (сейчас, кадр назад и посередине) прошла ближе
## blade_radius к его телу (вертикальный отрезок от колен до головы). Один взмах — один урон каждому.
var _blade_hit := {}                 # id взмаха → {враг: true}


func _blade_strike(b: Dictionary) -> void:
	var id := int(b.id)
	if not _blade_hit.has(id):
		_blade_hit = {id: {}}
	var done: Dictionary = _blade_hit[id]
	# полоса клинка между прошлым и нынешним кадром — с шагом ~blade_sub_step по острию: тяжёлый меч в ударе
	# пролетает за кадр физики до метра, и три положения могли проскочить врага
	var segs := []
	var tip_step := ((b.b as Vector3) - (b.pb as Vector3)).length()
	var n := clampi(int(ceil(tip_step / _hf("blade_sub_step", 0.25))), 2, 12)
	for i in n + 1:
		var k := float(i) / float(n)
		segs.append([(b.pa as Vector3).lerp(b.a as Vector3, k), (b.pb as Vector3).lerp(b.b as Vector3, k)])
	var rad := _hf("blade_radius", 0.55)
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive() or done.has(g):
			continue
		var gob: Goblin = g
		var lo := gob.global_position + Vector3(0, 0.3, 0)
		var hi := gob.global_position + Vector3(0, 1.6 if gob.boss else 1.2, 0)
		var hit := false
		for sg: Array in segs:
			var cp := Geometry3D.get_closest_points_between_segments(sg[0], sg[1], lo, hi)
			if (cp[0] as Vector3).distance_to(cp[1]) < rad + (0.35 if gob.boss else 0.0):
				hit = true
				break
		if not hit:
			continue
		done[g] = true
		var dmg := float(b.damage) * _dmg_mult()
		gob.take_damage(dmg, _player.global_position, false)
		_impact_feel(gob, false)
		_numbers.append({"pos": gob.global_position + Vector3(randf_range(-0.3, 0.3), 1.3, 0.0), "v": int(dmg),
			"crit": false, "t": 0.0})


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
## kind: "heavy" — блок копит вдвое больше; "perilous" — не блокируется и не парируется (только уйти);
## "charge" — таран: блок не держит, сбивает с ног; "parried" — враг отбил удар героя, стойка героя проседает.
func _on_hero_hit(damage: float, attacker: Node3D = null, kind := "") -> void:
	if _hero != null and _hero.invulnerable():
		return
	if is_instance_valid(_iai) and _iai.active and not _iai.interrupt():
		return                                       # время стоит — по герою не попасть
	if kind == "parried":
		_posture = minf(_pos_max(), _posture + 18.0)
		_since_hit = 0.0
		_stagger = maxf(_stagger, 0.5)
		if _hero != null:
			_hero.hurt()
		if _posture >= _pos_max():
			_posture = _pos_max() * 0.35
			_stagger = _hf("guard_break_time", 1.2)
		_update_hud()
		return
	var unblockable := kind == "perilous" or kind == "charge"
	var fwd := Vector3(-sin(_body_mesh.rotation.y), 0.0, -cos(_body_mesh.rotation.y))
	var facing := true
	if attacker != null:
		var to := attacker.global_position - _player.global_position
		to.y = 0.0
		facing = to.length() < 0.01 or fwd.dot(to.normalized()) > 0.2
	var spark_at := _player.global_position + fwd * 0.7 + Vector3(0.0, 1.2, 0.0)
	if _hero != null and facing and not unblockable and _hero.parry_window():
		_hero.deflect()
		_hero.block_hit(false)
		_posture = minf(_pos_max(), _posture + 4.0)
		_sparks(spark_at, Color(1.0, 0.8, 0.35), 40, 5.0)
		if attacker is Goblin:
			(attacker as Goblin).deflected(_player.global_position)
		return
	if _hero != null and facing and not unblockable and _hero.blocking:
		var guard := 1.0 - _block_reduce()               # пассивка героя (Чёрный рыцарь — «Железная стена»)
		_posture = minf(_pos_max(), _posture + damage * (4.4 if kind == "heavy" else 2.2) * guard)
		_since_hit = 0.0
		_sparks(spark_at, Color(1.0, 0.6, 0.25), 14, 3.0)
		_hero.block_hit(kind == "heavy")                # отдача: сдвиг назад — root motion клипа
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
		if kind == "charge" and _hp > 0.0:
			_hero.knock_down()
			if attacker != null:
				var push := _player.global_position - attacker.global_position
				push.y = 0.0
				_player.velocity += push.normalized() * 7.0
		else:
			_hero.hurt()
	if _hp <= 0.0 and is_instance_valid(_arena) and _arena.fighting:
		_hp = 1.0                                    # пал на арене — уносят с песка, без потери прогресса
		_arena.leave(true)
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
## Объёмный туман (настройка «Объёмный туман», 0 — выкл.): свет фонарей и костров висит в воздухе. Только Forward+.
func _apply_volfog(v: float) -> void:
	if _env == null:
		return
	var on := v > 0.01 and RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.volumetric_fog_enabled = on
	if on:
		_env.volumetric_fog_density = 0.0005 + 0.0035 * v  # тонкий: лучи и ореолы огней, а не стена (0.5 → 0.0023)
		_env.volumetric_fog_albedo = Color(0.95, 0.9, 0.93)
		_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		_env.volumetric_fog_length = 64.0
		_env.volumetric_fog_detail_spread = 2.0
		_env.volumetric_fog_ambient_inject = 0.05
		_env.volumetric_fog_sky_affect = 0.0


## LUT 17³ (цветокоррекция сцены): тени уходят в холодную бирюзу, света — в тёплое золото, мягкая S-кривая.
## Делаем в коде — без файлов и без потерь при сжатии.
static func _grade_lut() -> ImageTexture3D:
	var n := 17
	var layers: Array[Image] = []
	var lilac := Vector3(0.9, 0.97, 1.08)            # тени — в холодную бирюзу поверхности Юрумы (контраст тёплым огням)
	var warm := Vector3(1.07, 1.0, 0.88)
	for b: int in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g: int in n:
			for r: int in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var lum := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var ws := 1.0 - smoothstep(0.0, 0.45, lum)
				var wh := smoothstep(0.45, 1.0, lum)
				c = c.lerp(c * lilac + Vector3(0.0, 0.012, 0.03), ws * 0.65)
				c = c.lerp(c * warm, wh * 0.55)
				c += (c - Vector3.ONE * 0.5) * 0.06
				img.set_pixel(r, g, Color(clampf(c.x, 0, 1), clampf(c.y, 0, 1), clampf(c.z, 0, 1)))
		layers.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	return t


## Виньетка: мягко темнит и чуть сиренит края кадра (поверх 3D, под HUD).
const VIGNETTE := """shader_type canvas_item;
uniform float strength = 0.55;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.85)));
	COLOR = vec4(0.06, 0.03, 0.1, v * strength);
}"""


func _add_vignette() -> void:
	var r := ColorRect.new()
	r.name = "PaxRpgVignette"
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	add_child(r)
	move_child(r, _box.get_index() + 1 if is_instance_valid(_box) else 0)   # сразу над 3D, под интерфейсом
	_vignette = r


func _sparks(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := GPUParticles3D.new()                    # искры со шлейфами (видно, куда летят), а не точки
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.35
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	p.process_material = pm
	p.trail_enabled = true
	p.trail_lifetime = 0.07
	var tm := RibbonTrailMesh.new()
	tm.shape = RibbonTrailMesh.SHAPE_CROSS
	tm.size = 0.014
	tm.sections = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.use_particle_trails = true
	m.albedo_color = Color(color.r * 4.0, color.g * 4.0, color.b * 4.0)   # HDR — ловит bloom
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.material = m
	p.draw_pass_1 = tm
	_view.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	_flash(at, color, 2.6, 4.0)


## Вспышка света от удара, искр, разреза: короткий огонёк без тени — освещает лицо, клинок и землю вокруг.
func _flash(at: Vector3, color: Color, energy: float, radius: float) -> void:
	if not is_instance_valid(_view):
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	_view.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


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


var _stream_t := 0.0


var _tab_was := false


func _process(delta: float) -> void:
	# TAB — ещё и опросом: если событие клавиши перехватил кто-то из игры раньше _input, инвентарь всё равно откроется
	var tab := active and Input.is_physical_key_pressed(KEY_TAB) and not _typing()
	if tab and not _tab_was and not (is_instance_valid(_pause) and _pause.visible):
		if is_instance_valid(_inv) and _inv.visible:
			_set_inventory(false)
		else:
			_set_wrist(not (is_instance_valid(_wrist) and _wrist.visible))   # TAB — наручный терминал
	_tab_was = tab
	_stream_t -= delta
	if active and _stream_t <= 0.0 and is_instance_valid(_cam):
		_stream_t = 0.5
		var t0 := Time.get_ticks_usec()
		Assets.stream_tick(mod, _cam.global_position)        # полные текстуры — только вблизи камеры
		Prof.add("стриминг", t0)
	if active and not paused():
		_talk_scan(delta)
	if active and is_instance_valid(_hud):
		var t0 := Time.get_ticks_usec()
		_hud_tick(delta)
		Prof.add("HUD", t0)


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
		st["enemy"] = {"name": mod.tr_key(e.display_key), "hp": e.hp / e.max_hp,
			"posture": e.posture / e.max_posture, "broken": e.can_deathblow(), "boss": e.boss,
			"title": mod.tr_key(e.title_key) if e.title_key != "" else ""}
		st["ult"] = e.posture / e.max_posture if not e.can_deathblow() else 1.0
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
		{"k": "風", "key": "Alt", "label": mod.tr_key("pax_rpg_hud_dodge"), "on": act.begins_with("Dodge"),
			"color": Color(0.47, 0.84, 1.0)},
		{"k": "鎖", "key": "Q", "label": mod.tr_key("pax_rpg_hud_lock"), "on": _lock != null,
			"color": Color(1.0, 0.55, 0.78)},
		{"k": "震", "key": "T", "label": mod.tr_key("pax_rpg_hud_quake"), "on": act == "Quake",
			"color": Color(1.0, 0.71, 0.28), "icon": _quake_tex(), "cd": _quake_cd / _hf("quake_cooldown", 30.0),
			"cd_s": ceili(_quake_cd), "ready": _quake_cd <= 0.0},
		{"k": "居", "key": "V", "label": mod.tr_key("pax_rpg_hud_iai"), "on": act == "Iai",
			"color": Color(0.75, 0.6, 1.0), "cd": _iai_cd / _hf("iai_cooldown", 90.0), "cd_s": ceili(_iai_cd),
			"ready": _iai_cd <= 0.0}]
	_hud.st = st
	if is_instance_valid(_city_map):
		_city_map.st = st
	_hud.refresh()


const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_Q, KEY_SPACE, KEY_SHIFT, KEY_ALT, KEY_C, KEY_R, KEY_H, KEY_M, KEY_X, KEY_T, KEY_V,
	KEY_Z, KEY_TAB]


func _input(event: InputEvent) -> void:
	if not active:
		return
	if paused():
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var pk := (event as InputEventKey).physical_keycode
			if is_instance_valid(_talk) and _talk.visible and pk == KEY_ESCAPE:
				_talk.close()
				get_viewport().set_input_as_handled()
			elif is_instance_valid(_wrist) and _wrist.visible and pk == KEY_ESCAPE:
				_set_wrist(false)
				get_viewport().set_input_as_handled()
			elif is_instance_valid(_inv) and _inv.visible and pk == KEY_ESCAPE:
				if not _inv.back():                       # сначала — окно оружия, потом сам инвентарь
					_set_inventory(false)
				get_viewport().set_input_as_handled()
			elif pk == KEY_ESCAPE:
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
			_yaw -= (event as InputEventMouseMotion).relative.x * _f("turn_speed", 0.004) * _sens
		return
	if event is InputEventKey and not _typing():
		var key: InputEventKey = event
		if key.physical_keycode in KEYS or key.keycode in KEYS:
			get_viewport().set_input_as_handled()   # горячие клавиши игры молчат, пока герой ходит
		if key.pressed and not key.echo and key.physical_keycode == KEY_E and is_instance_valid(_talk_npc) and not _near_gate:
			_start_talk()                            # житель рядом — разговор
		elif key.pressed and not key.echo and key.physical_keycode == KEY_E and _near_gate:
			exit_requested.emit()
		elif key.pressed and not key.echo and key.physical_keycode == KEY_E and is_instance_valid(_arena) \
				and _arena.can_start():
			_arena.start()
		if key.pressed and not key.echo and key.physical_keycode == KEY_V:
			_iai_try()                               # «Иай: остановка времени»
		if key.pressed and not key.echo and key.physical_keycode == KEY_T:
			_quake_try()                             # «Земной разлом»
		if key.pressed and not key.echo and key.physical_keycode == KEY_X and is_instance_valid(_arena):
			_arena.leave()                           # покинуть арену
		if key.pressed and not key.echo and key.physical_keycode == KEY_Q:
			_toggle_lock()                           # захват цели (как в Sekiro)
		if key.pressed and not key.echo and key.physical_keycode == KEY_Z:
			_shoulder = -_shoulder                   # плечо камеры в захвате
			_toast = {"text": mod.tr_key("pax_rpg_hud_shoulder_left" if _shoulder < 0.0 else "pax_rpg_hud_shoulder_right"),
				"t": 0.0}
		if key.pressed and not key.echo and key.physical_keycode == KEY_M and is_instance_valid(_city_map):
			_city_map.toggle()                       # карта города
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE and is_instance_valid(_city_map) \
				and _city_map.visible:
			_city_map.visible = false
		elif key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			_set_wrist(true)                         # меню — через наручный терминал
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
