extends PaxMod
## Pax RPG — прототип RPG в Pax Universe. Сейчас только механика: планета Юрума вместо Земли (planet/), города на
## глобусе; щелчок по городу — экран загрузки (travel/) и локация-платформа (location/), где герой-овал ходит
## на WASD; ворота на локации возвращают на карту мира. main.gd только регистрирует части.

const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Location := preload("res://mods/pax_rpg/src/location/location.gd")
const Loading := preload("res://mods/pax_rpg/src/travel/loading.gd")
const Travel := preload("res://mods/pax_rpg/src/travel/travel.gd")
const ProfS := preload("res://mods/pax_rpg/src/location/prof.gd")
const GfxS := preload("res://mods/pax_rpg/src/location/gfx.gd")
const Trace := preload("res://mods/pax_rpg/src/trace.gd")
const MainMenu := preload("res://mods/pax_rpg/src/ui/main_menu.gd")
const Names := preload("res://mods/pax_rpg/src/location/names.gd")

var planet: Planet
var location: Location
var loading: Loading
var travel: Travel
var _autostart_city := ""
var _mm: MainMenu


func _mod_loaded() -> void:
	planet = Planet.new()
	planet.setup(self)
	add_child(planet)
	location = Location.new()
	location.setup(self)
	add_child(location)
	loading = Loading.new()
	loading.setup(self)
	add_child(loading)
	travel = Travel.new()
	travel.setup(self, planet, location, loading)
	add_child(travel)
	# Временное меню (по просьбе автора): «Продолжить», «Новая игра», «Загрузить», «Мультиплеер», «Настройки», «Выход».
	# Тестовая арена — в коде (команда rpg_arena), в меню вернём, когда понадобится. Мультиплеер — сеть игры
	# (её лобби и серверы); в городе герои игроков видят друг друга (src/location/net_sync.gd).
	for id: String in ["load", "new_game", "presets", "network", "settings"]:
		Pax.hide_menu_item(id)
	Pax.add_menu_item("pax_rpg_continue", tr_key("pax_rpg_menu_continue"), _menu_continue)
	Pax.add_menu_item("pax_rpg_new", tr_key("pax_rpg_menu_new"), _rpg_new_game)
	Pax.add_menu_item("pax_rpg_load", tr_key("pax_rpg_menu_load"), _menu_screen.bind("_loading_screen"))
	Pax.add_menu_item("pax_rpg_mp", tr_key("pax_rpg_menu_mp"), _menu_screen.bind("_network_screen"))
	Pax.add_menu_item("pax_rpg_settings", tr_key("pax_rpg_menu_settings"), _menu_screen.bind("_settings_screen"))
	var mm := MainMenu.new()
	_mm = mm                       # свой экран поверх меню игры (фон Юрумы, глубина, эффекты)
	mm.setup(self, func() -> Variant: return _menu(), [
		["pax_rpg_menu_continue", _menu_continue], ["pax_rpg_menu_new", _rpg_new_game, true],
		["pax_rpg_menu_load", Callable()], ["pax_rpg_menu_char", func() -> void: travel.pick_from_menu()], ["pax_rpg_menu_mp", _menu_screen.bind("_network_screen"), true],
		["pax_rpg_menu_settings", _menu_screen.bind("_settings_screen"), true], ["pax_rpg_menu_exit", _menu_screen.bind("_to_launcher")]])
	mm.slots = _slots
	mm.open_slot = _open_slot
	add_child(mm)
	Pax.register_command("rpg_arena", _arena_command, "rpg_arena — открыть тестовую арену Pax RPG")
	Pax.register_command("rpg_probe", _probe_command, "rpg_probe — что видно вокруг героя (отладка)")
	Pax.register_command("rpg_orc", _orc_command, "rpg_orc — орк-чемпион перед героем (тест боя)")
	Pax.register_command("rpg_city", _city_command, "rpg_city <id> — открыть город (напр. gharn)")
	Pax.register_command("rpg_cam", _cam_command, "rpg_cam N — ракурс превью города (0 — обычная камера)")
	Pax.register_command("rpg_perf", _perf_command, "rpg_perf [off|on <particles|omni|shadows|landscape>] — FPS, отрисовка, счёт тяжёлых узлов")
	Pax.register_command("rpg_weather", _weather_command, "rpg_weather <clear|cloudy|fog|rain|storm|auto> — погода в локации (перестраивает её)")
	Pax.register_command("rpg_time", _time_command, "rpg_time H — время суток в локации (0–24)")
	Pax.register_command("rpg_gfx", _gfx_command, "rpg_gfx <sdfgi_rays 8..128|ssil_half 0/1|ssao_half 0/1|hide_hud 0/1> — качество рендера на лету (сравнение A/B)")
	# Для разработки: pax_rpg/dev/arena.ps1 ставит настройку autostart_arena — арена откроется сразу после запуска.
	# Флаг одноразовый: следующий обычный запуск идёт как всегда.
	var city := str(get_setting("autostart_city", ""))
	if city != "":
		set_setting("autostart_city", "")
		_autostart_city = city
	if bool(get_setting("autostart_arena", false)) or _autostart_city != "":
		set_setting("autostart_arena", false)
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 2.0
		t.autostart = true
		t.timeout.connect(_open_test_arena)
		add_child(t)


## Новая игра Pax RPG: сценарий «Юрума» без выбора, сразу экран страны появления (карта и список), «Далее»
## (или двойной щелчок по стране) — сразу в партию: играем только за своего героя, экран «кто ты» не нужен.
## Экраны — меню игры (src/ui/Menu.gd, исходники pax-universe-source): ставим выбор и подменяем шаг «Далее».
const PRESET := "Юрума"


## Мир сейчас сменится: до нового world_ready мод мира игры не трогает (с 0.31.4 опрос планеты и материала,
## пока игра их разбирает в своих потоках, ронял её на «Продолжить» и «Загрузить»).
func _world_going() -> void:
	planet.suspend()
	travel.suspend()


func _rpg_new_game() -> void:
	travel.pick_next = true
	_world_going()
	var menu: Variant = _menu()
	if menu == null:
		log_warning("Pax RPG: главное меню не найдено — открываю обычную новую игру")
		return
	menu.preset_chosen = PRESET
	menu.role_menu = "country"
	menu.faction_chosen = ""
	menu.leader_chosen = {}
	menu._country_choice_screen()
	var go := func() -> void:
		if str(menu.faction_chosen) != "":
			Names.new_run(self)                         # новое прохождение — другие жители, имена и ремёсла
			menu._start_game()
	var map: Variant = menu.choice_map
	if map is Control:
		for c: Dictionary in (map as Control).get_signal_connection_list("double_clicked"):
			(map as Control).disconnect("double_clicked", c.callable)
		(map as Control).connect("double_clicked", func(name_v: String) -> void:
			menu._choose_country(name_v)
			go.call())
	var screen: Control = menu.screen
	var row := screen.get_child(screen.get_child_count() - 1)
	for b: Node in row.get_children():
		if b is Button and (b as Button).text == str(menu.t_("next")):
			for c: Dictionary in (b as Button).pressed.get_connections():
				(b as Button).pressed.disconnect(c.callable)
			(b as Button).pressed.connect(go)


## Экран меню игры (загрузка, настройки) — тем же методом, что её кнопки.
func _menu_screen(which: String) -> void:
	var menu: Variant = _menu()
	if menu == null:
		return
	if which == "_loading_screen":
		travel.pick_next = true
		_world_going()
		menu._loading_screen()
	elif which == "_network_screen":
		menu._network_screen()
	elif which == "_to_launcher":
		menu._to_launcher()
	else:
		menu._settings_screen()


## «Продолжить» — партия, открытая последней (slot корня игры), иначе самое новое сохранение; грузим тем же
## путём, что и меню игры (mp_session().open_slot — так же его зовёт мост для ИИ-агентов), без экранов меню.
func _menu_continue() -> void:
	var list := _slots()
	if list.is_empty():
		log_warning("Pax RPG: нет сохранений — «Продолжить» ничего не открывает")
		return
	var m: Variant = _main_root()
	var cur := str((m as Object).get("slot")) if m != null else ""
	_open_slot(cur if list.has(cur) else str(list.back()))


func _slots() -> Array:
	return load("res://src/save/Save.gd").slots()


func _open_slot(slot: String) -> void:
	MainMenu.off()
	var m: Variant = _main_root()
	if m == null:
		log_warning("Pax RPG: корень игры не найден — сохранение не открыть")
		return
	var menu: Variant = _menu()
	if menu != null and _game != null and str((m as Object).get("slot")) == slot:
		# эта партия уже открыта за меню (игра грузит последнюю при запуске): заново её не грузят — просто
		# закрываем меню, как его «Продолжить», и спрашиваем героя (world_ready сейчас не придёт)
		travel.pick_next = true
		menu.close_button()
		travel.start(_game)
		return
	travel.pick_next = true
	_world_going()
	m.mp_session().open_slot(slot)


## Меню игры (Menu.gd) — свойство menu_node корня игры. Раньше искали обходом ВСЕГО дерева сцены: с 0.31.4 это
## роняло игру на любой кнопке меню (дерево игры живёт и в её потоках). Корень — из world_ready: за главным
## меню игры уже стоит мир.
var _game: PaxGame


## Корень игры (Main): из world_ready, а если его ещё не было — текущая сцена (у главного меню бывает без мира).
func _main_root() -> Variant:
	var m: Variant = _game.main if _game != null else null
	if m is Object and is_instance_valid(m):
		return m
	var cs := get_tree().current_scene
	return cs if cs != null and "menu_node" in cs else null


func _menu() -> Variant:
	var m: Variant = _main_root()
	if m == null:
		return null
	var mn: Variant = (m as Object).get("menu_node")
	return mn if mn is Node and is_instance_valid(mn) else null


func _mod_unloaded() -> void:
	if is_instance_valid(location):
		location.clear()
		location.queue_free()                         # локация может жить прямо под корнем (ввод — первой)
	if is_instance_valid(planet):
		planet.restore()


func _world_ready(g: PaxGame) -> void:
	Trace.mark("main: world_ready")
	_game = g
	if is_instance_valid(_mm):
		_mm.attach(_menu())
	Trace.armed_until = Engine.get_process_frames() + 300
	planet.start(g)
	travel.start(g)
	location.prewarm()                    # горы и степь городов — в потоке, пока игрок на глобусе
	Trace.mark("main: world_ready done")


## Загружен сейв: игра собирает мир заново, но world_ready при этом может не прийти («Продолжить» и «Загрузить»
## через open_slot) — тогда без этого глобус оставался без городов, а выбор героя не предлагался.
func _game_loaded(g: PaxGame, _state: Dictionary) -> void:
	Trace.mark("main: game_loaded")
	_world_ready(g)


## Время пошло, а мод всё ещё «ждёт мир» (ни world_ready, ни game_loaded не пришли) — подхватываем партию тут.
func _days_starting(g: PaxGame, _from_day: int, _days: int) -> void:
	if planet.game == null:
		_world_ready(g)


## Консоль F8: rpg_arena.
func _arena_command(_args: PackedStringArray) -> String:
	_open_test_arena()
	return "Pax RPG: test arena"


func _probe_command(_args: PackedStringArray) -> String:
	return location.probe()


func _orc_command(_args: PackedStringArray) -> String:
	return location.spawn_orc()


func _city_command(args: PackedStringArray) -> String:
	var id := args[0] if args.size() > 0 else "gharn"
	location.build({"id": id})
	return "Pax RPG: city " + id


func _weather_command(args: PackedStringArray) -> String:
	const W := preload("res://mods/pax_rpg/src/location/weather.gd")
	var k := args[0] if args.size() > 0 else "auto"
	if k != "auto" and not k in W.KINDS:
		return "rpg_weather: " + "|".join(W.KINDS) + "|auto"
	W.forced = "" if k == "auto" else k
	return "rpg_weather: %s — войдите в локацию заново (выйти и зайти), погода применится" % k


## Консоль F8: rpg_gfx <ключ> <значение> — внутренние ручки качества на время сеанса (для скриншотов A/B).
func _gfx_command(args: PackedStringArray) -> String:
	if args.size() < 2:
		return "rpg_gfx sdfgi_rays 8|16|32|64|96|128 · ssil_half 0|1 · ssao_half 0|1 · hide_hud 0|1"
	var v := args[1].to_int()
	match args[0]:
		"sdfgi_rays":
			var rc: Dictionary = {8: RenderingServer.ENV_SDFGI_RAY_COUNT_8, 16: RenderingServer.ENV_SDFGI_RAY_COUNT_16,
				32: RenderingServer.ENV_SDFGI_RAY_COUNT_32, 64: RenderingServer.ENV_SDFGI_RAY_COUNT_64,
				96: RenderingServer.ENV_SDFGI_RAY_COUNT_96, 128: RenderingServer.ENV_SDFGI_RAY_COUNT_128}
			if not rc.has(v):
				return "sdfgi_rays: 8, 16, 32, 64, 96, 128"
			RenderingServer.environment_set_sdfgi_ray_count(rc[v])
		"ssil_half":
			RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH, v == 1, 0.5, 4, 50.0, 300.0)
		"ssao_half":
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, v == 1, 0.5, 2, 50.0, 300.0)
		"hide_hud":
			var hud: Variant = location.get("_hud")
			if hud is CanvasItem:
				(hud as CanvasItem).visible = v == 0
		_:
			return "rpg_gfx: неизвестный ключ " + args[0]
	return "rpg_gfx %s = %d" % [args[0], v]


func _time_command(args: PackedStringArray) -> String:
	return location.set_hour(float(args[0]) if args.size() > 0 else 12.0)


## Замер производительности локации: FPS, draw calls, примитивы и сколько тяжёлых узлов; off/on — выключить
## категорию, чтобы сравнить FPS (что именно ест кадр).
func _perf_command(args: PackedStringArray) -> String:
	if args.size() >= 1 and args[0] == "prof":
		_perf_prof()
		return "rpg_perf prof: 5 с замера, итог в логе"
	if args.size() >= 1 and args[0] == "auto":
		_perf_auto()
		return "rpg_perf auto: замер ~70 с, итог в логе ([pax_rpg] perf)"
	if args.size() >= 1 and args[0] == "bench":
		_perf_bench()
		return "rpg_perf bench: день и ночь по 8 с (~30 с), итог в логе ([pax_rpg] bench)"
	if args.size() >= 1 and args[0] == "err":
		_perf_err()
		return "rpg_perf err: поиск источника ошибок рендера ~1.5 мин, метки в логе ([pax_rpg] err-test)"
	if args.size() >= 1 and args[0] == "gpu":
		_perf_gpu(args[1] if args.size() >= 2 else "")
		return "rpg_perf gpu [часть]: A/B по частям картинки ~4 мин, итог в логе ([pax_rpg] perf gpu)"
	var cnt := {"particles": 0, "omni": 0, "omni_shadow": 0, "mesh": 0, "multimesh_inst": 0}
	var stack: Array = [location]
	var hide := args.size() >= 2 and args[0] == "off"
	var show := args.size() >= 2 and args[0] == "on"
	var cat := args[1] if args.size() >= 2 else ""
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CPUParticles3D or n is GPUParticles3D:
			cnt.particles += 1
			if cat == "particles" and (hide or show):
				(n as Node3D).visible = show
		elif n is OmniLight3D:
			cnt.omni += 1
			if (n as OmniLight3D).shadow_enabled:
				cnt.omni_shadow += 1
			if cat == "omni" and (hide or show):
				(n as Node3D).visible = show
		elif n is DirectionalLight3D and cat == "shadows" and (hide or show):
			(n as DirectionalLight3D).shadow_enabled = show
		elif n is MultiMeshInstance3D:
			cnt.multimesh_inst += (n as MultiMeshInstance3D).multimesh.instance_count if (n as MultiMeshInstance3D).multimesh else 0
		elif n is MeshInstance3D:
			cnt.mesh += 1
		if cat == "landscape" and (hide or show) and n.name == "Landscape":
			(n as Node3D).visible = show
	if args.size() >= 1 and args[0] == "top":           # самые тяжёлые меши: треугольники × копии
		var heavy := {}
		stack = [location]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mesh: Mesh = null
			var k := 1
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				mesh = (n as MultiMeshInstance3D).multimesh.mesh
				k = (n as MultiMeshInstance3D).multimesh.instance_count
			elif n is MeshInstance3D:
				mesh = (n as MeshInstance3D).mesh
			if mesh == null:
				continue
			var tris := 0
			for si: int in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var key := "%s/%s" % [n.get_parent().name, n.name]
			heavy[key] = int(heavy.get(key, 0)) + tris * k
		var keys := heavy.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(heavy[a]) > int(heavy[b]))
		var out := []
		for i: int in mini(15, keys.size()):
			out.append("%s %dk" % [keys[i], int(heavy[keys[i]]) / 1000])
		return " | ".join(out)
	var rs := RenderingServer
	var vp: Viewport = location.get("_view")
	var gpu := ""
	if vp != null:
		rs.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		gpu = " · 3D: gpu %.1f мс cpu %.1f мс" % [rs.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()),
			rs.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())]
	gpu += " · скрипты %.1f мс · физика %.1f мс · узлов %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)]
	return gpu + " · fps %d · draw %d · obj %d · prim %dk · vram %d МБ · %s" % [Engine.get_frames_per_second(),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576, str(cnt)]


func _cam_command(args: PackedStringArray) -> String:
	return location.cine(int(args[0]) if args.size() > 0 else 0)


## Кнопка «Тест» в главном меню: сразу тестовая арена (герой + гоблин), без карты мира.
func _open_test_arena() -> void:
	if _autostart_city != "":
		location.build({"id": _autostart_city})
		_autostart_city = ""
		if bool(get_setting("perf_on_start", false)):      # замер для разработчика: снимок, тяжёлые меши, части мода, автозамер
			set_setting("perf_on_start", false)
			await get_tree().create_timer(45.0).timeout
			log_info("Pax RPG perf snap: " + _perf_command(PackedStringArray()))
			log_info("Pax RPG perf top: " + _perf_command(PackedStringArray(["top"])))
			await _perf_prof()
			_perf_auto()
		return
	location.build_test()


## Автозамер: по очереди выключает подсистему на 6 с и пишет в лог FPS и время кадра (что съедает кадр).
func _perf_auto() -> void:
	var env: Environment = location.get("_env")
	var sun: DirectionalLight3D = location.get("_sun")
	var vp: SubViewport = location.get("_view")
	var hud: CanvasItem = location.get("_hud")
	var steps: Array = [
		["база", func(_on: bool) -> void: pass],
		["частицы", func(on: bool) -> void:
			for n: Node3D in _kids("GPUParticles3D") + _kids("CPUParticles3D"):
				n.visible = on],
		["огни omni", func(on: bool) -> void:
			for n: Node3D in _kids("OmniLight3D"):
				n.visible = on],
		["тени солнца", func(on: bool) -> void:
			if sun: sun.shadow_enabled = on],
		["ssao+ssr+glow", func(on: bool) -> void:
			if env:
				env.ssao_enabled = on
				env.ssr_enabled = on
				env.glow_enabled = on],
		["туман", func(on: bool) -> void:
			if env: env.fog_enabled = on],
		["msaa", func(on: bool) -> void:
			if vp: vp.msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED],
		["анимации", func(on: bool) -> void:
			for n: Node in _kids("AnimationPlayer"):
				n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED],
		["NPC", func(on: bool) -> void:
			var pl: Node = location.get("_player")
			for n: Node in _kids("CharacterBody3D"):
				if n != pl:
					n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED],
		["плащ", func(on: bool) -> void:
			var h: Variant = location.get("_hero")
			if h is Node:
				(h as Node).set("cloth_paused", not on)],
		["HUD", func(on: bool) -> void:
			if hud: hud.visible = on],
		["ландшафт", func(on: bool) -> void:
			for n: Node in location.find_children("Landscape", "", true, false):
				(n as Node3D).visible = on],
		["город (меши)", func(on: bool) -> void:
			for n: Node3D in _kids("MultiMeshInstance3D"):
				n.visible = on],
	]
	var rid := vp.get_viewport_rid() if vp else RID()
	if vp:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	for st: Array in steps:
		(st[1] as Callable).call(false)
		await get_tree().create_timer(2.0).timeout
		var f := 0
		var gpu := 0.0
		var t0 := Time.get_ticks_msec()
		var proc := 0.0
		var phys := 0.0
		while Time.get_ticks_msec() - t0 < 4000:
			await get_tree().process_frame
			f += 1
			if vp:
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		log_info("Pax RPG perf: без «%s» — fps %.1f · gpu 3D %.1f мс · скрипты %.1f мс · физика %.1f мс · draw %d" % [st[0], f / secs,
			gpu / maxf(f, 1), proc / maxf(f, 1) * 1000.0, phys / maxf(f, 1) * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		(st[1] as Callable).call(true)
	log_info("Pax RPG perf: готово")


func _kids(cls: String) -> Array:
	return location.find_children("*", cls, true, false)


## Сколько мс на кадр тратит каждая часть мода (5 с).
func _perf_prof() -> void:
	ProfS.report(1)
	var f := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
		f += 1
	log_info("Pax RPG perf prof: fps %.1f · %s" % [f / 5.0, ProfS.report(f)])


## Сравнимый замер «до/после»: камера стоит, 8 с днём (как есть) и 8 с ночью (22:00), потом час — обратно. Средний FPS,
## 1 % худших кадров, время видеокарты (3D и окно), процессор отрисовки, части мода (Prof), проходы.
func _perf_bench() -> void:
	var vp: SubViewport = location.get("_view")
	var dn: Node = location.get("_daynight")
	if vp == null:
		log_info("Pax RPG bench: нет локации")
		return
	var rid := vp.get_viewport_rid()
	var root_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	RenderingServer.viewport_set_measure_render_time(root_rid, true)
	var hour0: float = float(dn.get("hour")) if dn != null else 12.0
	log_info("Pax RPG bench: вид %s · окно %s" % [str(vp.size), str(DisplayServer.window_get_size())])
	for phase: Array in [["день", hour0], ["ночь", 22.0]]:
		if dn != null:
			location.set_hour(float(phase[1]))
		await get_tree().create_timer(4.0).timeout
		ProfS.report(1)
		var times: Array = []
		var g3 := 0.0
		var g2 := 0.0
		var cpu := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < 8000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(now - last)
			last = now
			g3 += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			g2 += RenderingServer.viewport_get_measured_render_time_gpu(root_rid)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		var n := maxi(times.size(), 1)
		var secs := (Time.get_ticks_usec() - t0) / 1000000.0
		times.sort()
		var worst := times.slice(int(n * 0.99))
		var w_avg := 0.0
		for t: Variant in worst:
			w_avg += float(t)
		w_avg /= maxf(worst.size(), 1)
		log_info("Pax RPG bench %s: fps %.1f · 1%% low %.1f · 3D gpu %.2f мс · окно %.2f мс · отрисовка ЦП %.2f мс · физика(макс) %.2f мс · %s" % [
			phase[0], n / secs, 1000000.0 / maxf(w_avg, 1.0), g3 / n, g2 / n, cpu / n,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _pass_info(rid)])
		log_info("Pax RPG bench %s: мод — %s" % [phase[0], ProfS.report(n)])
	if dn != null:
		location.set_hour(hour0)
	log_info("Pax RPG bench: готово")


## Замер видеокарты A/B: каждая часть картинки по очереди выключается (или ставится дешевле), до и после — время
## видеокарты 3D-вида локации и окна (слой камеры, HUD), FPS и время кадра на процессоре. Камера стоит — сравнение
## честное. rpg_perf gpu — все части; rpg_perf gpu <начало имени> — одна.
func _perf_gpu(only: String) -> void:
	var env: Environment = location.get("_env")
	var sun: DirectionalLight3D = location.get("_sun")
	var vp: SubViewport = location.get("_view")
	var hud: CanvasItem = location.get("_hud")
	var box: SubViewportContainer = location.get("_box")
	var gfx: GfxS = location.get("_gfx")
	if env == null or vp == null or sun == null:
		log_info("Pax RPG perf gpu: нет локации")
		return
	var rs := RenderingServer
	var rid := vp.get_viewport_rid()
	var root_rid := get_viewport().get_viewport_rid()
	rs.viewport_set_measure_render_time(rid, true)
	rs.viewport_set_measure_render_time(root_rid, true)
	var lens: Material = box.material if box != null else null
	var lod := vp.mesh_lod_threshold
	var sun_far := sun.directional_shadow_max_distance
	var vis := func(nodes: Array, on: bool) -> void:
		for n: Variant in nodes:
			if is_instance_valid(n) and n is Node3D:
				(n as Node3D).visible = on
	var city_mmi: Array = []
	var city_mi: Array = []
	var grass: Array = []
	for n: Node in _kids("MultiMeshInstance3D"):
		if n.get_parent() == vp and is_equal_approx((n as GeometryInstance3D).extra_cull_margin, 1.0):
			grass.append(n)                                  # ячейки травы (grass.gd): прямо в виде, запас рамки 1 м
		elif n.get_parent() != null and n.get_parent().name == "City":
			city_mmi.append(n)
	for c: Node in location.find_children("City", "", true, false):
		for n: Node in c.find_children("*", "MeshInstance3D", true, false):
			if not n is MultiMeshInstance3D and (n as Node3D).visible:
				city_mi.append(n)
	var pl: Variant = location.get("_player")
	var bodies: Array = _kids("CharacterBody3D").filter(func(n: Node) -> bool: return n != pl and (n as Node3D).visible)
	var lights: Array = _kids("OmniLight3D").filter(func(n: Node) -> bool: return (n as Node3D).visible)
	var parts: Array = (_kids("GPUParticles3D") + _kids("CPUParticles3D")).filter(func(n: Node) -> bool: return (n as Node3D).visible)
	var fogs: Array = _kids("FogVolume")
	var land: Array = location.find_children("Landscape", "", true, false)
	var probes: Array = _kids("ReflectionProbe")
	var steps: Array = []
	if env.sdfgi_enabled:
		steps.append(["SDFGI", func(on: bool) -> void: env.sdfgi_enabled = on, 3.0])
		steps.append(["GI в полразрешения", func(on: bool) -> void: rs.gi_set_use_half_resolution(not on), 1.5])
		steps.append(["SDFGI лучи 64→16", func(on: bool) -> void:
			rs.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64 if on else RenderingServer.ENV_SDFGI_RAY_COUNT_16), 2.0])
		steps.append(["SDFGI лучи 64→32", func(on: bool) -> void:
			rs.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64 if on else RenderingServer.ENV_SDFGI_RAY_COUNT_32), 2.0])
	if env.ssil_enabled:
		steps.append(["SSIL", func(on: bool) -> void: env.ssil_enabled = on, 1.5])
		steps.append(["SSIL в полразмера", func(on: bool) -> void:
			rs.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH, not on, 0.5, 4, 50.0, 300.0), 1.5])
	if env.ssao_enabled:
		steps.append(["SSAO", func(on: bool) -> void: env.ssao_enabled = on, 1.5])
		steps.append(["SSAO в полразмера", func(on: bool) -> void:
			rs.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, not on, 0.5, 2, 50.0, 300.0), 1.5])
	if env.ssr_enabled:
		steps.append(["SSR", func(on: bool) -> void: env.ssr_enabled = on, 1.5])
	if env.volumetric_fog_enabled:
		steps.append(["объёмный туман", func(on: bool) -> void: env.volumetric_fog_enabled = on, 1.5])
	steps.append(["ореол (glow)", func(on: bool) -> void: env.glow_enabled = on, 1.0])
	steps.append(["TAA", func(on: bool) -> void: vp.use_taa = on, 1.0])
	steps.append(["тени солнца", func(on: bool) -> void: sun.shadow_enabled = on, 1.0])
	steps.append(["тени солнца мягкие→низкие", func(on: bool) -> void:
		rs.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if on else RenderingServer.SHADOW_QUALITY_SOFT_LOW), 1.0])
	steps.append(["атлас солнца 8192→4096", func(on: bool) -> void: rs.directional_shadow_atlas_set_size(8192 if on else 4096, true), 1.0])
	steps.append(["тени солнца дальность→60 м", func(on: bool) -> void: sun.directional_shadow_max_distance = sun_far if on else 60.0, 1.0])
	if gfx != null:
		steps.append(["тени огней", func(on: bool) -> void:
			gfx.set_option("lamp_shadows_n", float(mod_setting_or("gfx_lamp_shadows_n", 40.0)) if on else 0.0), 3.0])
	steps.append(["огни omni", func(on: bool) -> void: vis.call(lights, on), 1.0])
	steps.append(["трава", func(on: bool) -> void: vis.call(grass, on), 1.0])
	steps.append(["частицы", func(on: bool) -> void: vis.call(parts, on), 1.0])
	steps.append(["дымка огней (FogVolume)", func(on: bool) -> void: vis.call(fogs, on), 1.0])
	steps.append(["проба отражений", func(on: bool) -> void: vis.call(probes, on), 1.0])
	steps.append(["жители и враги", func(on: bool) -> void: vis.call(bodies, on), 1.0])
	steps.append(["ландшафт", func(on: bool) -> void: vis.call(land, on), 1.0])
	steps.append(["город MultiMesh", func(on: bool) -> void: vis.call(city_mmi, on), 1.0])
	steps.append(["город модели", func(on: bool) -> void: vis.call(city_mi, on), 1.0])
	var casters: Array = (city_mmi + city_mi).filter(func(n: Node) -> bool:
		return (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	steps.append(["тени города (отбрасывание)", func(on: bool) -> void:
		for n: Variant in casters:
			if is_instance_valid(n):
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 1.0])
	var fades: Array = (city_mmi + city_mi).filter(func(n: Node) -> bool:
		return (n as GeometryInstance3D).visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED)
	steps.append(["растворение мелочи (fade)", func(on: bool) -> void:
		for n: Variant in fades:
			if is_instance_valid(n):
				(n as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if on else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED, 1.0])
	steps.append(["LOD 1→4 px", func(on: bool) -> void: vp.mesh_lod_threshold = lod if on else 4.0, 1.0])
	if lens != null:
		steps.append(["слой камеры (lens)", func(on: bool) -> void: box.material = lens if on else null, 1.0])
	if hud != null:
		steps.append(["HUD", func(on: bool) -> void: hud.visible = on, 1.0])
	var root := get_tree().root
	log_info("Pax RPG perf gpu: %s · вид %s ×%.2f · окно %s · корень %s, база %s, режим %d, ×%.2f · контейнер %s · %d частей · огней %d · тел %d · трава %d · модели %d" % [
		rs.get_video_adapter_name(), str(vp.size), vp.scaling_3d_scale, str(DisplayServer.window_get_size()), str(root.size),
		str(root.content_scale_size), root.content_scale_mode, root.content_scale_factor, str(box.size if box != null else Vector2.ZERO),
		steps.size(), lights.size(), bodies.size(), grass.size(), city_mi.size()])
	var base: Array = await _gpu_sample(rid, root_rid, 3.0)
	log_info("Pax RPG perf gpu: база — " + _gpu_line(base))
	log_info("Pax RPG perf gpu: проходы — " + _pass_info(rid) + " · город: MultiMesh %d, модели %d, отбрасывают тень %d" % [
		city_mmi.size(), city_mi.size(), casters.size()])
	for st: Array in steps:
		if only != "" and not str(st[0]).begins_with(only):
			continue
		var a: Array = await _gpu_sample(rid, root_rid, 2.0)
		(st[1] as Callable).call(false)
		await get_tree().create_timer(float(st[2])).timeout
		var b: Array = await _gpu_sample(rid, root_rid, 2.0)
		(st[1] as Callable).call(true)
		log_info("Pax RPG perf gpu: без «%s» — 3D %.2f→%.2f (%+.2f) · окно %.2f→%.2f · fps %.0f→%.0f · кадр ЦП %.2f→%.2f мс" % [
			st[0], a[1], b[1], float(b[1]) - float(a[1]), a[2], b[2], a[0], b[0], a[3], b[3]])
		await get_tree().create_timer(float(st[2])).timeout
	log_info("Pax RPG perf gpu: готово")


## Вызовы отрисовки, объекты и треугольники вида: видимый проход и тени отдельно; физика — тела, пары, острова.
func _pass_info(rid: RID) -> String:
	var rs := RenderingServer
	var out := []
	for t: Array in [["вид", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE], ["тени", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]]:
		out.append("%s: draw %d · obj %d · tri %dk" % [t[0],
			rs.viewport_get_render_info(rid, t[1], RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			rs.viewport_get_render_info(rid, t[1], RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			rs.viewport_get_render_info(rid, t[1], RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000])
	out.append("физика: активных %d · пар %d · островов %d · такт %.2f мс" % [
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	return " · ".join(out)


## Поиск источника ошибок рендера (И-132, «uniform_set is null» ~1 на кадр): подозреваемые по очереди выключаются на 3 с,
## в логе — метки «err-test A/B <имя>»; источник — тот, при выключении которого ошибок между метками нет.
func _perf_err() -> void:
	var env: Environment = location.get("_env")
	var vp: SubViewport = location.get("_view")
	var pl: Variant = location.get("_player")
	if env == null or vp == null:
		log_info("Pax RPG err-test: нет локации")
		return
	var we: WorldEnvironment = null
	for n: Node in _kids("WorldEnvironment"):
		we = n as WorldEnvironment
	var ca: CameraAttributes = we.camera_attributes if we != null else null
	var bg := env.background_mode
	var tm := env.tonemap_mode
	var vis := func(nodes: Array, on: bool) -> void:
		for n: Variant in nodes:
			if is_instance_valid(n) and n is Node3D:
				(n as Node3D).visible = on
	var other_mi: Array = []
	for n: Node in _kids("MeshInstance3D"):
		var a: Node = n
		var in_city := false
		while a != null and a != vp:
			if a.name == "City" or a is CharacterBody3D:
				in_city = true
				break
			a = a.get_parent()
		if not in_city and (n as Node3D).visible:
			other_mi.append(n)
	var gfx: GfxS = location.get("_gfx")
	var rs := RenderingServer
	var tests: Array = [
		["глобальные настройки рендера мода", func(on: bool) -> void:
			if gfx != null:
				if on: gfx.push_globals()
				else: gfx.restore_globals()],
		["фильтр декалей", func(on: bool) -> void:
			rs.decals_set_filter(RenderingServer.DECAL_FILTER_LINEAR_MIPMAPS_ANISOTROPIC if on else RenderingServer.DECAL_FILTER_LINEAR_MIPMAPS)],
		["фильтр проекторов", func(on: bool) -> void:
			rs.light_projectors_set_filter(RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS_ANISOTROPIC if on else RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS)],
		["SSS качество", func(on: bool) -> void:
			rs.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH if on else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW)],
		["бикубический ореол", func(on: bool) -> void: rs.environment_glow_set_use_bicubic_upscale(on)],
		["весь 3D-вид", func(on: bool) -> void: vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED],
		["контейнер 3D-вида (вывод на экран)", func(on: bool) -> void:
			var b: Variant = location.get("_box")
			if b is CanvasItem: (b as CanvasItem).visible = on],
		["весь слой локации", func(on: bool) -> void: location.visible = on],
		["цветокоррекция LUT", func(on: bool) -> void: env.adjustment_enabled = on],
		["небо → цвет", func(on: bool) -> void: env.background_mode = bg if on else Environment.BG_COLOR],
		["тонмаппинг ACES → линейный", func(on: bool) -> void: env.tonemap_mode = tm if on else Environment.TONE_MAPPER_LINEAR],
		["камера: экспозиция", func(on: bool) -> void: if we != null: we.camera_attributes = ca if on else null],
		["герой", func(on: bool) -> void: if pl is Node3D: (pl as Node3D).visible = on],
		["прочие сетки вне города", func(on: bool) -> void: vis.call(other_mi, on)],
		["декали", func(on: bool) -> void: vis.call(_kids("Decal"), on)],
		["Label3D/Sprite3D", func(on: bool) -> void: vis.call(_kids("Label3D") + _kids("Sprite3D") + _kids("AnimatedSprite3D"), on)],
		["свет направленный", func(on: bool) -> void: vis.call(_kids("DirectionalLight3D"), on)],
		["ореол", func(on: bool) -> void: env.glow_enabled = on],
		["туман", func(on: bool) -> void: env.fog_enabled = on],
	]
	# все SubViewport игры: размер, обновление, свой мир — что ещё рисуется каждый кадр
	var root := get_tree().root
	for n: Node in root.find_children("*", "SubViewport", true, false):
		var sv := n as SubViewport
		log_info("Pax RPG err-test: SubViewport %s · %s · обновление %d · 3D %s · в дереве под %s" % [sv.get_path(), str(sv.size),
			sv.render_target_update_mode, str(not sv.disable_3d), sv.get_parent().name])
	# видимые 2D-узлы до 3 уровней от корня: каждый — отдельной пробой
	var cis: Array = []
	var st: Array = [[root, 0]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		var n: Node = e[0]
		if int(e[1]) >= 3:
			continue
		for c: Node in n.get_children():
			if c is CanvasItem and (c as CanvasItem).visible and c != location.get("_box"):
				cis.append(c)
			if c is CanvasLayer or c is Window or c == self or c is Control:
				st.append([c, int(e[1]) + 1])
	for c: Variant in cis:
		var ci := c as CanvasItem
		tests.append(["2D " + str(ci.get_path()).right(60), func(on: bool) -> void: if is_instance_valid(ci): ci.visible = on])
	log_info("Pax RPG err-test: начало, прочих сеток %d, 2D-узлов %d" % [other_mi.size(), cis.size()])
	for t: Array in tests:
		log_info("Pax RPG err-test A " + str(t[0]))
		await get_tree().create_timer(1.5).timeout
		(t[1] as Callable).call(false)
		await get_tree().process_frame
		log_info("Pax RPG err-test B " + str(t[0]))
		await get_tree().create_timer(1.5).timeout
		(t[1] as Callable).call(true)
		await get_tree().process_frame
	log_info("Pax RPG err-test: конец")


func mod_setting_or(key: String, fallback: Variant) -> Variant:
	var v: Variant = get_setting(key, null)
	return fallback if v == null else v


## [fps, мс видеокарты 3D-вида, мс видеокарты окна, мс процессора на кадр (без ожидания видеокарты не отличить —
## берём время обработки кадра)] за secs секунд.
func _gpu_sample(rid: RID, root_rid: RID, secs: float) -> Array:
	var f := 0
	var g3 := 0.0
	var g2 := 0.0
	var cpu := 0.0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(secs * 1000000.0):
		await get_tree().process_frame
		f += 1
		g3 += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		g2 += RenderingServer.viewport_get_measured_render_time_gpu(root_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	f = maxi(f, 1)
	return [f / dt, g3 / f, g2 / f, cpu / f]


func _gpu_line(s: Array) -> String:
	return "fps %.1f · 3D %.2f мс · окно %.2f мс · отрисовка ЦП %.2f мс" % [s[0], s[1], s[2], s[3]]
