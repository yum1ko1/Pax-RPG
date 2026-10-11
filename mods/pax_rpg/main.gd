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


func _cam_command(args: PackedStringArray) -> String:
	return location.cine(int(args[0]) if args.size() > 0 else 0)


## Кнопка «Тест» в главном меню: сразу тестовая арена (герой + гоблин), без карты мира.
func _open_test_arena() -> void:
	if _autostart_city != "":
		location.build({"id": _autostart_city})
		_autostart_city = ""
		return
	location.build_test()
