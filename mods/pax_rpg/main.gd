extends PaxMod
## Pax RPG — прототип RPG в Pax Universe. Сейчас только механика: планета Юрума вместо Земли (planet/), города на
## глобусе; щелчок по городу — экран загрузки (travel/) и локация-платформа (location/), где герой-овал ходит
## на WASD; ворота на локации возвращают на карту мира. main.gd только регистрирует части.

const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Location := preload("res://mods/pax_rpg/src/location/location.gd")
const Loading := preload("res://mods/pax_rpg/src/travel/loading.gd")
const Travel := preload("res://mods/pax_rpg/src/travel/travel.gd")
const ProfS := preload("res://mods/pax_rpg/src/location/prof.gd")
const Trace := preload("res://mods/pax_rpg/src/trace.gd")
const MainMenu := preload("res://mods/pax_rpg/src/ui/main_menu.gd")

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
	mm.setup(self, func() -> Variant: return _find_menu(get_tree().root), [
		["pax_rpg_menu_continue", _menu_continue], ["pax_rpg_menu_new", _rpg_new_game],
		["pax_rpg_menu_load", _menu_screen.bind("_loading_screen")], ["pax_rpg_menu_mp", _menu_screen.bind("_network_screen")],
		["pax_rpg_menu_settings", _menu_screen.bind("_settings_screen")], ["pax_rpg_menu_exit", _menu_screen.bind("_to_launcher")]])
	add_child(mm)
	Pax.register_command("rpg_arena", _arena_command, "rpg_arena — открыть тестовую арену Pax RPG")
	Pax.register_command("rpg_probe", _probe_command, "rpg_probe — что видно вокруг героя (отладка)")
	Pax.register_command("rpg_orc", _orc_command, "rpg_orc — орк-чемпион перед героем (тест боя)")
	Pax.register_command("rpg_city", _city_command, "rpg_city <id> — открыть город (напр. gharn)")
	Pax.register_command("rpg_cam", _cam_command, "rpg_cam N — ракурс превью города (0 — обычная камера)")
	Pax.register_command("rpg_perf", _perf_command, "rpg_perf [off|on <particles|omni|shadows|landscape>] — FPS, отрисовка, счёт тяжёлых узлов")
	Pax.register_command("rpg_weather", _weather_command, "rpg_weather <clear|cloudy|fog|rain|storm|auto> — погода в локации (перестраивает её)")
	Pax.register_command("rpg_time", _time_command, "rpg_time H — время суток в локации (0–24)")
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


func _rpg_new_game() -> void:
	var menu: Variant = _find_menu(get_tree().root)
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
	var menu: Variant = _find_menu(get_tree().root)
	if menu == null:
		return
	if which == "_loading_screen":
		menu._loading_screen()
	elif which == "_network_screen":
		menu._network_screen()
	elif which == "_to_launcher":
		menu._to_launcher()
	else:
		menu._settings_screen()


## «Продолжить» — последнее сохранение: экран загрузки (сохранения там от новых к старым) и первая «Играть».
func _menu_continue() -> void:
	var menu: Variant = _find_menu(get_tree().root)
	if menu == null:
		return
	menu._loading_screen()
	var want := [str(menu.t_("save_play")), str(menu.t_("save_continue"))]
	for b: Node in (menu.screen as Node).find_children("*", "Button", true, false):
		if (b as Button).text in want and (b as Button).visible:
			(b as Button).pressed.emit()
			return
	log_warning("Pax RPG: нет сохранений — «Продолжить» оставляет экран загрузки")


static func _find_menu(n: Node) -> Variant:
	if n.has_method("_country_choice_screen") and n.has_method("_start_game"):
		return n
	for c: Node in n.get_children():
		var f: Variant = _find_menu(c)
		if f != null:
			return f
	return null


func _mod_unloaded() -> void:
	if is_instance_valid(location):
		location.clear()
		location.queue_free()                         # локация может жить прямо под корнем (ввод — первой)
	if is_instance_valid(planet):
		planet.restore()


func _world_ready(g: PaxGame) -> void:
	Trace.mark("main: world_ready")
	Trace.armed_until = Engine.get_process_frames() + 300
	planet.start(g)
	travel.start(g)
	location.prewarm()
	Trace.mark("main: world_ready done")                    # горы и степь городов — в потоке, пока игрок на глобусе


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
