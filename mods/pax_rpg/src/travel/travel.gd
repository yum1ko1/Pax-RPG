extends Node
## Переходы: карта мира → город и обратно, всегда через экран загрузки (loading.gd). Пока игрок в локации, значки
## городов на глобусе выключены, время мира стоит («pause_world» в config/location.json). Рассказчик — готовые
## строки из data/lang, позже их заменит ИИ.

const ENTER_LINES := 4             # pax_rpg_narrator_enter_1 … _4
const LEAVE_LINES := 2             # pax_rpg_narrator_leave_1 … _2

const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Location := preload("res://mods/pax_rpg/src/location/location.gd")
const Loading := preload("res://mods/pax_rpg/src/travel/loading.gd")
const CharSelect := preload("res://mods/pax_rpg/src/ui/char_select.gd")
const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const HOURS_PER_DEG := 0.6           # часы пути на градус дуги по глобусу (Гхарн → лес у него ≈ 1–1.5 ч)

var mod: PaxMod
var game: PaxGame
var planet: Planet
var location: Location
var loading: Loading
var hero_id := ""                  # кем играем в этом мире; как в Terraria — герой не привязан к сохранению:
                                   # выбор при каждом заходе в мир (start), последний выбор — настройка мода «character»
var _picker: CharSelect
var _rng := RandomNumberGenerator.new()   # свой — общий randf() игры не трогаем (повторяемость мира)


func setup(m: PaxMod, p: Planet, l: Location, ld: Loading) -> void:
	mod = m
	planet = p
	location = l
	loading = ld
	name = "PaxRpgTravel"
	_rng.randomize()
	planet.city_chosen.connect(enter)
	DayNight.clock = m
	location.exit_requested.connect(leave)


func start(g: PaxGame) -> void:
	game = g
	hero_id = ""                                      # новый заход в мир (новая игра или загрузка) — герой выбирается заново
	location.game = g
	_pick_hero(func() -> void: pass)                  # выбор героя — сразу при входе в мир, а не у ворот города


func _line(prefix: String, count: int, city_name: String) -> String:
	var key := "%s_%d" % [prefix, _rng.randi_range(1, count)]
	return mod.tr_key(key).replace("{city}", city_name)


func enter(city: Dictionary) -> void:
	if loading.busy() or location.active:
		return
	if hero_id == "":                                 # окно выбора ещё открыто (или его закрыли) — сначала герой
		_pick_hero(func() -> void: pass)
		return
	var city_name := mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
	_move_to(city)                                    # путь занимает время — часы мира идут только сейчас
	planet.enabled = false
	var cfg := location.cfg
	if bool(cfg.get("pause_world", true)) and game != null:
		game.set_speed(0)
	loading.run(city_name, _line("pax_rpg_narrator_enter", ENTER_LINES, city_name),
		float(cfg.get("loading_seconds", 1.6)), location.build.bind(city), func() -> void: pass, location.is_ready)


func leave() -> void:
	if loading.busy():
		return
	if location.test_mode:
		location.clear()          # тестовая арена из меню — назад в меню, карта мира не нужна
		return
	var cfg := location.cfg
	loading.run(mod.tr_key("pax_rpg_world_map"), _line("pax_rpg_narrator_leave", LEAVE_LINES, ""),
		float(cfg.get("loading_seconds", 1.6)) * 0.6, location.clear, _back_on_map)


## Меню паузы игры, открытое под локацией (Esc дошёл до игры), — закрыть: щёлкнуть его «Продолжить».
func _close_game_pause() -> void:
	var b := _find_continue(get_tree().root)
	if b != null:
		b.pressed.emit()
		if game != null:
			game.set_speed(0)                             # на карте мир всё равно стоит


func _find_continue(n: Node) -> Button:
	if n is Button and (n as Button).is_visible_in_tree():
		var t := (n as Button).text.to_lower()
		if t.contains("продолжить") or t.contains("continue") or t.contains("resume"):
			return n
	for c: Node in n.get_children():
		if c == location or c == loading:
			continue
		var f := _find_continue(c)
		if f != null:
			return f
	return null


## Герой идёт в место city: часы мира + время пути по дуге от прежнего места, место героя — новое.
func _move_to(city: Dictionary) -> void:
	var from := planet.player_pos()
	var to := Vector2(float(city.get("lat", from.x)), float(city.get("lon", from.y)))
	var deg := rad_to_deg(Planet.dir_of(from.x, from.y).angle_to(Planet.dir_of(to.x, to.y)))
	DayNight.advance(location.cfg, clampf(deg * HOURS_PER_DEG, 0.25, 8.0))
	mod.set_setting("player_pos", [to.x, to.y])


var _hold := 0.0


## На глобусе мир стоит: игра на паузе, пока игрок не пошёл куда-то (время — только в пути).
func _process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("travel._process")
	_hold -= delta
	if _hold <= 0.0:
		_hold = 0.5
		if game != null and planet.enabled and not loading.busy() and not location.active:
			game.set_speed(0)


func _back_on_map() -> void:
	planet.enabled = true
	_close_game_pause()
	planet.refresh_quest()                               # задание выдано / найдено / сдано — точка на глобусе


## Экран выбора героя (при входе в мир); после выбора — then. Карточка — из config/hero.json → character.
func _pick_hero(then: Callable) -> void:
	if is_instance_valid(_picker):
		return
	var ch: Variant = location.hero_cfg.get("character", {})
	_picker = CharSelect.new()
	_picker.setup(mod, ch if ch is Dictionary else {})
	add_child(_picker)
	_picker.picked.connect(func(id: String) -> void:
		hero_id = id
		mod.set_setting("character", id)
		_picker.queue_free()
		then.call())
