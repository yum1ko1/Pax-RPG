extends Node
## Переходы: карта мира → город и обратно, всегда через экран загрузки (loading.gd). Пока игрок в локации, значки
## городов на глобусе выключены, время мира стоит («pause_world» в config/location.json). Рассказчик — готовые
## строки из data/lang, позже их заменит ИИ.

const ENTER_LINES := 4             # pax_rpg_narrator_enter_1 … _4
const LEAVE_LINES := 2             # pax_rpg_narrator_leave_1 … _2

const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Location := preload("res://mods/pax_rpg/src/location/location.gd")
const Loading := preload("res://mods/pax_rpg/src/travel/loading.gd")

var mod: PaxMod
var game: PaxGame
var planet: Planet
var location: Location
var loading: Loading
var _rng := RandomNumberGenerator.new()   # свой — общий randf() игры не трогаем (повторяемость мира)


func setup(m: PaxMod, p: Planet, l: Location, ld: Loading) -> void:
	mod = m
	planet = p
	location = l
	loading = ld
	name = "PaxRpgTravel"
	_rng.randomize()
	planet.city_chosen.connect(enter)
	location.exit_requested.connect(leave)


func start(g: PaxGame) -> void:
	game = g
	location.game = g


func _line(prefix: String, count: int, city_name: String) -> String:
	var key := "%s_%d" % [prefix, _rng.randi_range(1, count)]
	return mod.tr_key(key).replace("{city}", city_name)


func enter(city: Dictionary) -> void:
	if loading.busy() or location.active:
		return
	var city_name := mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
	planet.enabled = false
	var cfg := location.cfg
	if bool(cfg.get("pause_world", true)) and game != null:
		game.set_speed(0)
	loading.run(city_name, _line("pax_rpg_narrator_enter", ENTER_LINES, city_name),
		float(cfg.get("loading_seconds", 1.6)), location.build.bind(city), func() -> void: pass)


func leave() -> void:
	if loading.busy():
		return
	var cfg := location.cfg
	loading.run(mod.tr_key("pax_rpg_world_map"), _line("pax_rpg_narrator_leave", LEAVE_LINES, ""),
		float(cfg.get("loading_seconds", 1.6)) * 0.6, location.clear, _back_on_map)


func _back_on_map() -> void:
	planet.enabled = true
