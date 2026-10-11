extends PaxMod
## Pax RPG — прототип RPG в Pax Universe. Сейчас только механика: планета Юрума вместо Земли (planet/), города на
## глобусе; щелчок по городу — экран загрузки (travel/) и локация-платформа (location/), где герой-овал ходит
## на WASD; ворота на локации возвращают на карту мира. main.gd только регистрирует части.

const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Location := preload("res://mods/pax_rpg/src/location/location.gd")
const Loading := preload("res://mods/pax_rpg/src/travel/loading.gd")
const Travel := preload("res://mods/pax_rpg/src/travel/travel.gd")

var planet: Planet
var location: Location
var loading: Loading
var travel: Travel
var _autostart_city := ""


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
	Pax.add_menu_item("pax_rpg_test", tr_key("pax_rpg_menu_test"), _open_test_arena)
	Pax.register_command("rpg_arena", _arena_command, "rpg_arena — открыть тестовую арену Pax RPG")
	Pax.register_command("rpg_city", _city_command, "rpg_city <id> — открыть город (напр. gharn)")
	Pax.register_command("rpg_cam", _cam_command, "rpg_cam N — ракурс превью города (0 — обычная камера)")
	Pax.register_command("rpg_perf", _perf_command, "rpg_perf [off|on <particles|omni|shadows|landscape>] — FPS, отрисовка, счёт тяжёлых узлов")
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


func _mod_unloaded() -> void:
	if is_instance_valid(location):
		location.clear()
	if is_instance_valid(planet):
		planet.restore()


func _world_ready(g: PaxGame) -> void:
	planet.start(g)
	travel.start(g)


## Консоль F8: rpg_arena.
func _arena_command(_args: PackedStringArray) -> String:
	_open_test_arena()
	return "Pax RPG: test arena"


func _city_command(args: PackedStringArray) -> String:
	var id := args[0] if args.size() > 0 else "gharn"
	location.build({"id": id})
	return "Pax RPG: city " + id


func _time_command(args: PackedStringArray) -> String:
	return location.set_hour(float(args[0]) if args.size() > 0 else 12.0)


## Замер производительности локации: FPS, draw calls, примитивы и сколько тяжёлых узлов; off/on — выключить
## категорию, чтобы сравнить FPS (что именно ест кадр).
func _perf_command(args: PackedStringArray) -> String:
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
		while Time.get_ticks_msec() - t0 < 4000:
			await get_tree().process_frame
			f += 1
			if vp:
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		log_info("Pax RPG perf: без «%s» — fps %.1f · gpu 3D %.1f мс · скрипты %.1f мс · draw %d" % [st[0], f / secs,
			gpu / maxf(f, 1), proc / maxf(f, 1) * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		(st[1] as Callable).call(true)
	log_info("Pax RPG perf: готово")


func _kids(cls: String) -> Array:
	return location.find_children("*", cls, true, false)
