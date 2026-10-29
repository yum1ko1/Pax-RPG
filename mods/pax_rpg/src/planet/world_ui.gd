extends CanvasLayer
## Интерфейс карты мира (макет A5, рамки — config/world_ui.json и textures/world/, pax_rpg/dev/world_ui/build_world_ui.py)
## поверх глобуса, вместо окон игры (их слой HUD спрятан, пока идёт партия):
##   слева вверху — герой (портрет, имя, здоровье, слава в мире, опыт, ранг, золото) и задание (рамки HUD v2);
##   вверху — полоса неба: Хоэн, Селунэ (серая, с красными потоками маны) и Иру (розовая) идут с востока (слева)
##     на запад по часам и дню мира (sky_clock.gd — та же модель, что небо локаций), под ней дата и час;
##   справа — карточка города, выбранного на глобусе: картинка, герб империи, путь (км и часы), опасность,
##     репутация с империей, места города; «В путь» и «Задания» (список — слева от карточки);
##   внизу — «В путь», «Ждать 1 ч», «Отдых до рассвета» (время мира стоит и идёт только от этих кнопок и в пути);
##   слева внизу — событие мира (война, Дикая охота к схождению лун…), справа внизу — герой и меню, справа
##     вверху — приближение глобуса.
## Щелчки по рамкам — свои (_input, до планеты и игры); щелчок по городу на глобусе приходит из travel.gd (select).

const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const SkyClock := preload("res://mods/pax_rpg/src/sky_clock.gd")
const Quest := preload("res://mods/pax_rpg/src/location/quest.gd")
const Planet := preload("res://mods/pax_rpg/src/planet/planet.gd")
const Travel := preload("res://mods/pax_rpg/src/travel/travel.gd")

const IVORY := Color(0.957, 0.894, 0.784)
const IVORY_DIM := Color(0.78, 0.69, 0.55)
const GOLD := Color(0.86, 0.68, 0.38)
const CRIMSON := Color(0.78, 0.09, 0.16)
const AMBER := Color(0.91, 0.66, 0.19)
const XP_COL := Color(0.47, 0.67, 0.9)
const WELL := Color(0.055, 0.03, 0.04, 0.92)
const SHADOW := Color(0.03, 0.01, 0.02, 0.85)
const KM_PER_DEG := 111.2
const HOURS_PER_DEG := 0.6                       # как travel.gd
const DAYS_PER_MONTH := 30
const START_MONTH := 2                           # день 0 мира — 1 Персика 1047 (третий месяц)
const START_YEAR := 1047
const HUNT_SOON := 8.0                           # за сколько дней до схождения лун событие — Дикая охота
## город (cities.json) → ключ империи в equipment.json и герб
const EMPIRE_KEY := {"azure": "throne", "haddur": "haddur", "gharn": "gharn", "saerit": "saerith", "bloom": "blossom"}

var mod: PaxMod
var travel: Travel                               # game, planet, location, loading, enter(), pick_from_menu()
var menu_node: Callable                          # main.gd: () -> меню игры (пауза) или null
var main_menu: CanvasLayer                       # наш главный экран (main_menu.gd)

var _root: Control
var _cfg := {}
var _ftex := {}
var _hud2 := {}
var _hud2_tex := {}
var _ui := {}                                    # config/world_ui.json целиком (art, events)
var _f_sc: Font
var _f_serif: Font
var _s := 1.0
var _w := 1920.0
var _h := 1080.0                                 # высота экрана в px макета (меньше масштаб — больше места)
var _sel: Dictionary = {}                        # выбранный город
var _popup := false
var _hits: Array = []                            # [Rect2 макета, id]
var _hover := ""
var _eq := {}                                    # config/equipment.json (ранги, ступени репутации, империи)
var _tex := {}
var _glyphs: Texture2D
var _places := {}                                # город → [[ключ, номер значка]]
var _stars: PackedVector2Array
var _pause_t := 0.0
var _pause_open := false


func setup(m: PaxMod, tr: Travel) -> void:
	mod = m
	travel = tr
	name = "PaxRpgWorldUi"
	layer = 30                                    # над подписями городов, под меню (60) и локацией (100)
	var c: Variant = JSON.parse_string(m.read_text("config/world_ui.json"))
	_ui = c if c is Dictionary else {}
	_cfg = _ui.get("frames", {})
	for k: String in _cfg:
		_ftex[k] = m.texture(str((_cfg[k] as Dictionary).get("tex", "")))
	var h: Variant = JSON.parse_string(m.read_text("config/hud2.json"))
	_hud2 = (h as Dictionary).get("frames", {}) if h is Dictionary else {}
	for k: String in ["hero", "quest"]:
		_hud2_tex[k] = m.texture(str((_hud2.get(k, {}) as Dictionary).get("tex", "")))
	var e: Variant = JSON.parse_string(m.read_text("config/equipment.json"))
	_eq = e if e is Dictionary else {}
	_f_sc = _font("fonts/cormorant_sc.ttf")
	_f_serif = _font("fonts/cormorant_garamond.ttf")
	_glyphs = m.texture("textures/map/glyphs.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1047
	for i: int in 70:
		_stars.append(Vector2(rng.randf(), rng.randf() * 0.8))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw)
	add_child(_root)
	visible = false


## Масштаб интерфейса: config/world_ui.json → ui_scale.world, настройка мода ui_scale — поверх.
func _scale() -> float:
	var d: Variant = _ui.get("ui_scale", {})
	var k := float((d as Dictionary).get("world", 1.0)) if d is Dictionary else 1.0
	return clampf(float(mod.get_setting("ui_scale", k)), 0.4, 1.5)


func _font(path: String) -> Font:
	var f := FontFile.new()
	f.data = mod.read_bytes(path)
	return f if not f.data.is_empty() else ThemeDB.fallback_font


func _t(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = mod.texture(path) if path != "" else null
	return _tex[path]


func _tr(k: String) -> String:
	return mod.tr_key(k)


## Город на глобусе выбран (travel.gd): карточка; тот же город ещё раз — карточка закрыта.
func select(city: Dictionary) -> void:
	if not _sel.is_empty() and str(_sel.get("id", "")) == str(city.get("id", "")):
		_sel = {}
	else:
		_sel = city
	_popup = false
	_root.queue_redraw()


# ---------- когда виден ----------

func _shown() -> bool:
	if travel == null or travel.game == null:
		return false
	var g: PaxGame = travel.game
	var pl: Planet = travel.planet
	if not pl.enabled or travel.loading.busy() or travel.location.active:
		return false
	if is_instance_valid(main_menu) and main_menu.visible:
		return false
	if _pause_open:
		return false
	if pl.game == null or g.focused_body() != g.home_body() or pl._flat_map_open():
		return false
	return true


func _process(delta: float) -> void:
	if travel != null and travel.game != null:
		var hl: CanvasLayer = (travel.game as PaxGame).hud_layer()
		if hl != null and hl.visible:
			hl.visible = false                     # окна и кнопки игры (и Оракул) — не в этой игре
	_pause_t -= delta
	if _pause_t <= 0.0:
		_pause_t = 0.25
		var mn: Variant = menu_node.call() if menu_node.is_valid() else null
		_pause_open = mn is CanvasLayer and (mn as CanvasLayer).visible
	var on := _shown()
	if on != visible:
		visible = on
		if not on:
			_hover = ""
	if visible:
		var vs := _root.get_viewport_rect().size
		_s = maxf(vs.y, 1.0) / 1080.0 * _scale()
		_w = vs.x / _s
		_h = vs.y / _s
		_root.queue_redraw()                       # небо и часы — дёшево, а состояние меняется отовсюду


# ---------- ввод ----------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var id := _hit((event as InputEventMouseMotion).position / _s)
		if id != _hover:
			_hover = id
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _popup or not _sel.is_empty():
			if _popup:
				_popup = false
			else:
				_sel = {}
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	var id := _hit(mb.position / _s)
	if id == "":
		return
	get_viewport().set_input_as_handled()          # щелчок по рамке не уходит ни планете, ни игре
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_press(id)


func _hit(p: Vector2) -> String:
	for i: int in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if (h[0] as Rect2).has_point(p):
			return str(h[1])
	return ""


func _press(id: String) -> void:
	match id:
		"go":
			if not _sel.is_empty():
				var city := _sel
				_sel = {}
				_popup = false
				travel.enter(city)
		"wait":
			DayNight.advance(travel.location.cfg, 1.0)
		"rest":
			var h := DayNight.world_hour(travel.location.cfg)
			var d := fposmod(6.0 - h, 24.0)
			DayNight.advance(travel.location.cfg, d if d > 0.01 else 24.0)
		"quests":
			_popup = not _popup
		"close":
			_sel = {}
			_popup = false
		"zoom_in":
			_wheel(MOUSE_BUTTON_WHEEL_UP)
		"zoom_out":
			_wheel(MOUSE_BUTTON_WHEEL_DOWN)
		"hero":
			travel.pick_from_menu()
		"menu":
			var mn: Variant = menu_node.call() if menu_node.is_valid() else null
			if mn is Object and (mn as Object).has_method("open_pause"):
				mn.open_pause()


## Приближение глобуса — колесо мыши игры над серединой экрана (курсор не двигается: событие своё).
func _wheel(button: MouseButton) -> void:
	var vs := _root.get_viewport_rect().size
	for i: int in 3:
		for pressed: bool in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = button
			e.pressed = pressed
			e.factor = 1.0
			e.position = vs * 0.5
			e.global_position = vs * 0.5
			Input.parse_input_event(e)


# ---------- рисование: помощники ----------

func _frame(cfg: Dictionary, key: String, x: float, y: float, w := -1.0) -> Rect2:
	var f: Dictionary = cfg.get(key, {})
	var fw := float(f.get("size", 100.0)) if w < 0.0 else w
	return Rect2(x, y, fw, fw * float(f.get("aspect", 1.0)))


func _hole(cfg: Dictionary, key: String, r: Rect2, i: int) -> Rect2:
	var hs: Array = (cfg.get(key, {}) as Dictionary).get("holes", [])
	if i >= hs.size():
		return Rect2(r.get_center(), Vector2.ZERO)
	var h: Array = hs[i]
	var a := r.position + r.size * Vector2(float(h[0]), float(h[1]))
	var b := r.position + r.size * Vector2(float(h[2]), float(h[3]))
	return Rect2(a, b - a)


func _tex_frame(t: Texture2D, r: Rect2, hot := false) -> void:
	if t != null:
		_root.draw_texture_rect(t, r, false, Color(1.18, 1.1, 1.02) if hot else Color.WHITE)


func _text(pos: Vector2, s: String, font: Font, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if width > 0.0:
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > width:
			fs = maxi(9, int(fs * width / tw))
	_root.draw_string_outline(font, pos, s, align, width, fs, 3, Color(SHADOW, SHADOW.a * col.a))
	_root.draw_string(font, pos, s, align, width, fs, col)


## Текст по центру точки.
func _ctext(c: Vector2, s: String, font: Font, fs: int, col: Color, maxw := 300.0) -> void:
	_text(Vector2(c.x - maxw * 0.5, c.y + fs * 0.32), s, font, fs, col, HORIZONTAL_ALIGNMENT_CENTER, maxw)


func _fill(r: Rect2, frac: float, col: Color) -> void:
	var g := r.grow(2.0)
	_root.draw_rect(g, WELL)
	var f := clampf(frac, 0.0, 1.0)
	if f <= 0.002:
		return
	var fr := Rect2(g.position, Vector2(g.size.x * f, g.size.y))
	var hi := col.lerp(Color.WHITE, 0.18)
	var lo := col.darkened(0.35)
	_root.draw_polygon(PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]),
		PackedColorArray([hi, hi, lo, lo]))
	_root.draw_rect(Rect2(fr.position.x, fr.position.y + fr.size.y * 0.18, fr.size.x, maxf(1.0, fr.size.y * 0.14)), Color(1, 1, 1, 0.16))


func _disc(c: Vector2, r: float, col: Color, tex: Texture2D = null) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in 40:
		var a := TAU * i / 40.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	if tex != null:
		_root.draw_polygon(pts, PackedColorArray([col]), uvs, tex)
	else:
		_root.draw_colored_polygon(pts, col)


## Треугольник; вырожденный (у полюсов диска луны) не рисуем — Godot на нём ругается.
func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	if absf((b - a).cross(c - a)) > 0.02:
		_root.draw_colored_polygon(PackedVector2Array([a, b, c]), col)


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _glyph(idx: int, r: Rect2) -> void:
	if _glyphs == null or idx < 0:
		return
	_root.draw_texture_rect_region(_glyphs, r, Rect2((idx % 5) * 96, (idx / 5) * 96, 96, 96))


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _button(key: String, id: String, r: Rect2, label: String, icon := "", disabled := false) -> void:
	var hot := _hover == id and not disabled
	_tex_frame(_ftex.get(key), r, hot)
	if disabled:
		_root.draw_rect(r.grow(-6.0), Color(0, 0, 0, 0.35))
	var col := IVORY if not disabled else IVORY_DIM
	var c := r.get_center()
	var fs := int(r.size.y * 0.46)
	var tw := _f_sc.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ix := c.x - tw * 0.5 - (fs * 0.7 if icon != "" else 0.0)
	if icon != "":
		_icon(icon, Vector2(ix, c.y), fs * 0.42, col)
		ix += fs * 1.0
	_text(Vector2(ix, c.y + fs * 0.32), label, _f_sc, fs, col, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.8)
	_hits.append([r, id])


## Значки кнопок — простые фигуры: «в путь» — треугольник, «ждать» — песочные часы, «отдых» — месяц.
func _icon(id: String, c: Vector2, r: float, col: Color) -> void:
	match id:
		"play":
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r), c + Vector2(r, 0), c + Vector2(-r * 0.7, r)]), col)
		"glass":
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r), c + Vector2(r * 0.7, -r), c, ]), col)
			_root.draw_colored_polygon(PackedVector2Array([c, c + Vector2(r * 0.7, r), c + Vector2(-r * 0.7, r)]), col)
			_root.draw_line(c + Vector2(-r * 0.85, -r), c + Vector2(r * 0.85, -r), col, 2.0)
			_root.draw_line(c + Vector2(-r * 0.85, r), c + Vector2(r * 0.85, r), col, 2.0)
		"moon":
			_disc(c, r, col)
			_disc(c + Vector2(r * 0.45, -r * 0.25), r * 0.85, Color(0.12, 0.04, 0.05))
		"scroll":
			_root.draw_rect(Rect2(c - Vector2(r * 0.7, r * 0.8), Vector2(r * 1.4, r * 1.6)), col, false, 2.0)
			for k: int in 3:
				_root.draw_line(c + Vector2(-r * 0.4, -r * 0.35 + k * r * 0.35), c + Vector2(r * 0.4, -r * 0.35 + k * r * 0.35), col, 1.5)


# ---------- рисование ----------

func _draw() -> void:
	_hits.clear()
	if _cfg.is_empty() or travel == null or travel.game == null:
		return
	_root.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	_draw_sky()
	_draw_hero()
	_draw_quest()
	_draw_event()
	_draw_bottom()
	_draw_round()
	if not _sel.is_empty():
		_draw_card()
		if _popup:
			_draw_popup()


# ---------- герой ----------

func _hero_cfg() -> Dictionary:
	var hc: Variant = travel.location.hero_cfg
	var ch: Variant = (hc as Dictionary).get("character", {}) if hc is Dictionary else {}
	return ch if ch is Dictionary else {}


func _draw_hero() -> void:
	var r := _frame(_hud2, "hero", 22.0, 18.0, 520.0)
	var prog: Variant = mod.get_setting("progress", {})
	var p: Dictionary = prog if prog is Dictionary else {}
	var pr := _hole(_hud2, "hero", r, 0)
	var pc := pr.get_center()
	var prad := minf(pr.size.x, pr.size.y) * 0.5 + 2.0
	_disc(pc, prad, WELL)
	var ch_id := str(mod.get_setting("character", ""))
	var pp := str((_ui.get("portraits", {}) as Dictionary).get(ch_id, _hero_cfg().get("portrait", "")))   # арт-аватар героя
	var portrait := _t(pp) if pp != "" else null
	_disc(pc, prad, Color.WHITE, portrait if portrait != null else _t("textures/hero_portrait.png"))
	var lvl := maxi(1, int(p.get("level", 1)))
	var b1 := _hole(_hud2, "hero", r, 1)
	var b2 := _hole(_hud2, "hero", r, 3)
	var b3 := _hole(_hud2, "hero", r, 4)
	_fill(b1, 1.0, CRIMSON)
	var fame := _renown()
	_fill(b2, (fame + 100.0) / 200.0, AMBER)
	var need := roundf(100.0 * pow(1.15, lvl - 1))      # как progress.gd (xp_base, xp_growth)
	var pc_cfg: Variant = travel.location.hero_cfg
	var pgv: Variant = (pc_cfg as Dictionary).get("progress", {}) if pc_cfg is Dictionary else {}
	if pgv is Dictionary:
		var pg: Dictionary = pgv
		need = roundf(float(pg.get("xp_base", 100.0)) * pow(float(pg.get("xp_growth", 1.15)), lvl - 1))
	_fill(b3, float(p.get("xp", 0.0)) / maxf(need, 1.0), XP_COL)
	_tex_frame(_hud2_tex.get("hero"), r)
	var ch := str(mod.get_setting("character", ""))
	var nk := "pax_rpg_char_%s_name" % ch
	var nm := _tr(nk)
	if nm == nk or nm == "":
		nm = _tr("pax_rpg_hero_name")
	_ctext(r.position + r.size * Vector2(0.5195, 0.279), nm.to_upper(), _f_sc, 21, IVORY, 0.27 * r.size.x)
	_ctext(r.position + r.size * Vector2(0.3055, 0.809), str(lvl), _f_sc, 27, IVORY, 44.0)
	# ранг и золото — строка под рамкой
	var rank := clampi(int(mod.get_setting("rank", 0)), 0, 6)
	var y := r.end.y + 4.0
	var x := r.position.x + r.size.x * 0.3
	var rt := _t("textures/inventory/rank_%d.png" % rank)
	if rt != null:
		_root.draw_texture_rect(rt, Rect2(x, y - 3.0, 36.0, 36.0), false)
	_text(Vector2(x + 40.0, y + 23.0), _tr("pax_rpg_rank_%d" % rank), _f_sc, 25, IVORY, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	var gx := x + 250.0
	_disc(Vector2(gx + 12.0, y + 15.0), 12.0, AMBER)
	_disc(Vector2(gx + 12.0, y + 15.0), 7.0, AMBER.darkened(0.35))
	_text(Vector2(gx + 32.0, y + 24.0), _thousands(int(p.get("gold", 0))), _f_sc, 26, IVORY, HORIZONTAL_ALIGNMENT_LEFT, 130.0)


## Слава в мире — средняя репутация с империями (как «отношение» в инвентаре), −100…100.
func _renown() -> int:
	var rel: Variant = mod.get_setting("reputation", {})
	var d: Dictionary = rel if rel is Dictionary else {}
	var emp: Array = _eq.get("empires", [])
	var t := 0
	for e: Variant in emp:
		t += int(d.get(str((e as Dictionary).get("key", "")), 0))
	return roundi(float(t) / maxf(1.0, emp.size()))


func _rep(city: Dictionary) -> int:
	var rel: Variant = mod.get_setting("reputation", {})
	var d: Dictionary = rel if rel is Dictionary else {}
	return int(d.get(EMPIRE_KEY.get(str(city.get("empire", "")), ""), 0))


func _tier(v: int) -> int:
	var tiers: Array = _eq.get("rep_tiers", [])
	var cur := 0
	for i: int in tiers.size():
		if v >= int((tiers[i] as Dictionary).get("min", -100)):
			cur = i
	return cur


# ---------- задание ----------

func _draw_quest() -> void:
	var r := _frame(_hud2, "quest", 22.0, 262.0, 470.0)
	_tex_frame(_hud2_tex.get("quest"), r)
	var q := Quest.get_q(mod)
	var x := r.position.x + 38.0
	var w := r.size.x - 76.0
	var rows: Array = []
	if not q.is_empty():
		var found := str(q.get("state", "")) == "found"
		rows.append([Quest.goal(mod, q), not found])
		rows.append([(_tr("pax_rpg_journal_found") if found else _tr("pax_rpg_journal_active")) + " · " +
			_tr("pax_rpg_city_" + str(q.get("city", ""))), found])
	else:
		rows.append([_tr("pax_rpg_wui_quest_none"), true])
		rows.append([_tr("pax_rpg_wui_quest_hint"), false])
	_text(Vector2(x, r.position.y + r.size.y * 0.2 + 8.0), _tr("pax_rpg_hud_quest"), _f_sc, 30, IVORY, HORIZONTAL_ALIGNMENT_LEFT, w - 120.0)
	var y := r.position.y + r.size.y * 0.47
	for rv: Variant in rows:
		var row: Array = rv
		var on := bool(row[1])
		var dc := Vector2(x + 12.0, y)
		if on:
			_root.draw_colored_polygon(_diamond(dc, 6.0), IVORY)
		else:
			var lp := _diamond(dc, 6.0)
			lp.append(lp[0])
			_root.draw_polyline(lp, IVORY_DIM, 1.0, true)
		_text(Vector2(x + 30.0, y + 9.0), str(row[0]), _f_serif, 27, IVORY if on else IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 32.0)
		y += r.size.y * 0.19


# ---------- небо ----------

func _world_t() -> float:
	return DayNight.world_time(travel.location.cfg)


func _draw_sky() -> void:
	var fw := 640.0
	var r := _frame(_cfg, "sky", (_w - fw) * 0.5, -6.0, fw)
	var a := _hole(_cfg, "sky", r, 0)
	var b := _hole(_cfg, "sky", r, 1)
	var band := a.merge(b).grow(3.0)
	var t := _world_t()
	var sun := SkyClock.sun_sky(t)
	var day := smoothstep(-0.12, 0.3, sun.y)
	var dusk := clampf(1.0 - absf(sun.y) / 0.25, 0.0, 1.0)
	var top := Color(0.04, 0.02, 0.1).lerp(Color(0.28, 0.42, 0.82), day)
	var low := Color(0.16, 0.05, 0.2).lerp(Color(0.92, 0.62, 0.78), day).lerp(Color(0.98, 0.45, 0.22), dusk * 0.75)
	_root.draw_polygon(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]),
		PackedColorArray([top, top, low, low]))
	var night := 1.0 - day
	if night > 0.02:
		for sp: Vector2 in _stars:
			_root.draw_rect(Rect2(band.position + band.size * sp, Vector2(1.6, 1.6)), Color(1, 0.92, 0.98, 0.75 * night))
	# тела: восток слева, запад справа, высота — от горизонта (низ полосы) к зениту
	var bodies := [["selune", SkyClock.moon_sky("selune", t)], ["iru", SkyClock.moon_sky("iru", t)], ["hoen", sun]]
	for bv: Variant in bodies:
		var bb: Array = bv
		_draw_body(str(bb[0]), bb[1], band, t)
	# горы по горизонту
	var hc := Color(0.05, 0.02, 0.05).lerp(Color(0.2, 0.1, 0.16), day * 0.6)
	var n := 48
	var prev := Vector2.ZERO
	for i: int in n + 1:                          # полосой четырёхугольников: невыпуклый контур Godot не всегда режет
		var u := float(i) / n
		var hgt := maxf(3.0, 10.0 + 5.0 * sin(u * 23.0) + 4.0 * sin(u * 61.0 + 1.3) + 3.0 * sin(u * 7.0 + 0.4))
		var p := Vector2(band.position.x + band.size.x * u, band.end.y - hgt)
		if i > 0:
			_root.draw_colored_polygon(PackedVector2Array([prev, p, Vector2(p.x, band.end.y), Vector2(prev.x, band.end.y)]), hc)
		prev = p
	_tex_frame(_ftex.get("sky"), r)
	for bv: Variant in bodies:                      # подписи — поверх рамки (полоса низкая)
		var bb: Array = bv
		var v: Vector3 = bb[1]
		if v.y > -0.02:
			var c := _sky_xy(v, band, 15.0)
			_ctext(Vector2(clampf(c.x, band.position.x + 40.0, band.end.x - 40.0), minf(c.y + 28.0, band.end.y - 9.0)), _tr("pax_rpg_wui_" + str(bb[0])), _f_sc, 15, IVORY, 90.0)
	# дата и час — на плашке под полосой
	_ctext(Vector2(r.get_center().x, r.position.y + r.size.y * 0.845), _date(t), _f_sc, 20, IVORY, r.size.x * 0.5)


## Место тела в полосе: угол от зенита к востоку/западу — по ширине, высота над горизонтом — по высоте.
func _sky_xy(v: Vector3, band: Rect2, rad: float) -> Vector2:
	var th := atan2(v.x, maxf(v.y, 0.0))         # +π/2 — восток у горизонта, 0 — зенит, −π/2 — запад
	var alt := asin(clampf(v.y, -1.0, 1.0)) / (PI * 0.5)
	var x := band.get_center().x - th / (PI * 0.5) * (band.size.x * 0.5 - rad)
	var y := band.end.y - rad * 0.6 - (band.size.y - rad * 2.2) * clampf(alt, 0.0, 1.0)
	return Vector2(x, y)


func _draw_body(id: String, v: Vector3, band: Rect2, t: float) -> void:
	if v.y < -0.02:
		return
	var rad := 17.0 if id == "hoen" else (15.0 if id == "selune" else 12.0)
	var c := _sky_xy(v, band, rad)
	if id == "hoen":
		for k: int in 5:
			_disc(c, rad + 3.0 + k * 4.0, Color(1.0, 0.8, 0.4, 0.09))
		_disc(c, rad, Color(1.0, 0.86, 0.5))
		_disc(c, rad * 0.7, Color(1.0, 0.97, 0.85))
		return
	var col := Color(0.66, 0.65, 0.7) if id == "selune" else Color(1.0, 0.45, 0.86)
	var glow := Color(1.0, 0.25, 0.3, 0.1) if id == "selune" else Color(1.0, 0.4, 0.9, 0.14)
	for k: int in 3:
		_disc(c, rad + 2.0 + k * 3.0, glow)
	_disc(c, rad, Color(0.09, 0.06, 0.1))
	# освещённая часть: край диска со стороны Хоэна и терминатор-полуэллипс
	var f := SkyClock.moon_phase(id, t)
	var s := 1.0 if SkyClock.moon_waxing(id, t) else -1.0
	if f > 0.02:                                  # полоса между краем и терминатором (серп невыпуклый)
		for i: int in 16:
			var a0 := -PI * 0.5 + PI * i / 16.0
			var a1 := -PI * 0.5 + PI * (i + 1) / 16.0
			var k := 1.0 - 2.0 * f
			var l0 := c + Vector2(s * rad * cos(a0), rad * sin(a0))
			var l1 := c + Vector2(s * rad * cos(a1), rad * sin(a1))
			var t0 := c + Vector2(s * rad * cos(a0) * k, rad * sin(a0))
			var t1 := c + Vector2(s * rad * cos(a1) * k, rad * sin(a1))
			_tri(l0, l1, t1, col)
			_tri(l0, t1, t0, col)
	if id == "selune":                              # красные потоки маны — видны и в тени
		var streams := [[Vector2(-0.8, -0.3), Vector2(-0.2, 0.0), Vector2(0.3, -0.35), Vector2(0.75, -0.1)],
			[Vector2(-0.6, 0.45), Vector2(-0.1, 0.25), Vector2(0.45, 0.5)], [Vector2(-0.15, -0.8), Vector2(0.05, -0.3), Vector2(-0.05, 0.2)]]
		for sv: Variant in streams:
			var pts := PackedVector2Array()
			for q: Vector2 in sv:
				pts.append(c + q * rad)
			_root.draw_polyline(pts, Color(1.0, 0.18, 0.22, 0.9), 1.6, true)
	else:
		_disc(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.25, Color(1, 0.8, 0.97, 0.35 * f))


func _date(t: float) -> String:
	var day := int(floor(t))
	var total := START_MONTH * DAYS_PER_MONTH + day
	var year := START_YEAR + total / (DAYS_PER_MONTH * 12)
	var m := (total % (DAYS_PER_MONTH * 12)) / DAYS_PER_MONTH
	var d := total % DAYS_PER_MONTH + 1
	var h := fposmod(t, 1.0) * 24.0
	return "%d %s %d %s   ·   %02d:%02d" % [d, _tr("pax_rpg_month_%d" % m), year, _tr("pax_rpg_era"), int(h), int(fmod(h, 1.0) * 60.0)]


# ---------- событие мира ----------

func _draw_event() -> void:
	var t := _world_t()
	var soon := SkyClock.next_conjunction(t)
	var ev := "war"
	var lines := [_tr("pax_rpg_wui_ev_war_1"), _tr("pax_rpg_wui_ev_war_2")]
	var cells := 5
	if SkyClock.in_conjunction(t) or soon <= HUNT_SOON:
		ev = "hunt"
		var now := SkyClock.in_conjunction(t)
		lines = [_tr("pax_rpg_wui_ev_hunt_1"), _tr("pax_rpg_wui_ev_hunt_now") if now else _tr("pax_rpg_wui_ev_hunt_2") % ceili(soon)]
		cells = 8 if now else clampi(8 - ceili(soon), 0, 8)
	var md := 150.0
	var mc := Vector2(22.0 + md * 0.5, _h - 22.0 - md * 0.5)
	var pr := _frame(_cfg, "event", mc.x + md * 0.36, 0.0, 340.0)
	pr.position.y = mc.y - pr.size.y * 0.5
	_tex_frame(_ftex.get("event"), pr)
	for i: int in 8:
		var hr := _hole(_cfg, "event", pr, i)
		_root.draw_rect(hr.grow(1.0), WELL)
		if i < cells:
			var hc := Color(0.86, 0.12, 0.16) if ev == "war" else Color(0.95, 0.4, 0.85)
			_root.draw_polygon(PackedVector2Array([hr.position, Vector2(hr.end.x, hr.position.y), hr.end, Vector2(hr.position.x, hr.end.y)]),
				PackedColorArray([hc.lightened(0.2), hc.lightened(0.2), hc.darkened(0.3), hc.darkened(0.3)]))
	var tx := pr.position.x + pr.size.x * 0.25
	var tw := pr.size.x * 0.66
	_text(Vector2(tx, pr.position.y + pr.size.y * 0.33), _tr("pax_rpg_wui_ev_" + ev), _f_sc, 26,
		Color(1.0, 0.3, 0.3) if ev == "war" else Color(1.0, 0.55, 0.9), HORIZONTAL_ALIGNMENT_LEFT, tw)
	_text(Vector2(tx, pr.position.y + pr.size.y * 0.5), str(lines[0]), _f_serif, 17, IVORY, HORIZONTAL_ALIGNMENT_LEFT, tw)
	_text(Vector2(tx, pr.position.y + pr.size.y * 0.66), str(lines[1]), _f_serif, 16, IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, tw)
	var mt := _t("textures/world/event_%s.png" % ev)
	if mt != null:
		_root.draw_texture_rect(mt, Rect2(mc - Vector2(md, md) * 0.5, Vector2(md, md)), false)


# ---------- нижняя полоса и круглые кнопки ----------

func _draw_bottom() -> void:
	var bw := 250.0
	var gap := 12.0
	var x0 := (_w - bw * 3.0 - gap * 2.0) * 0.5
	var y := _h - 30.0
	var specs := [["btn_red", "go", _tr("pax_rpg_wui_travel"), "play", _sel.is_empty()], ["btn_dark", "wait", _tr("pax_rpg_wui_wait"), "glass", false],
		["btn_dark", "rest", _tr("pax_rpg_wui_rest"), "moon", false]]
	for i: int in specs.size():
		var sp: Array = specs[i]
		var r := _frame(_cfg, str(sp[0]), x0 + i * (bw + gap), 0.0, bw)
		r.position.y = y - r.size.y
		_button(str(sp[0]), str(sp[1]), r, str(sp[2]), str(sp[3]), bool(sp[4]))


func _draw_round() -> void:
	var d := 76.0
	var specs := [["menu", "menu"], ["hero", "hero"]]
	for i: int in specs.size():
		var c := Vector2(_w - 22.0 - d * 0.5 - i * (d + 10.0), _h - 22.0 - d * 0.5)
		_round(str(specs[i][1]), c, d)
	var zc := Vector2(_w - 22.0 - 30.0, 52.0)
	_round("zoom_in", zc, 58.0)
	_round("zoom_out", zc + Vector2(0, 66.0), 58.0)


func _round(id: String, c: Vector2, d: float) -> void:
	var r := Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d))
	var hot := _hover == id
	_disc(c, d * 0.42, Color(0.1, 0.03, 0.04, 0.92))
	_tex_frame(_ftex.get("round"), r, hot)
	var col := IVORY if not hot else Color(1.0, 0.95, 0.85)
	var k := d * 0.16
	match id:
		"zoom_in", "zoom_out":
			_root.draw_line(c - Vector2(k, 0), c + Vector2(k, 0), col, 3.0, true)
			if id == "zoom_in":
				_root.draw_line(c - Vector2(0, k), c + Vector2(0, k), col, 3.0, true)
		"menu":
			for j: int in 3:
				_root.draw_line(c + Vector2(-k, (j - 1) * k * 0.8), c + Vector2(k, (j - 1) * k * 0.8), col, 3.0, true)
		"hero":
			_disc(c + Vector2(0, -k * 0.7), k * 0.5, col)
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.8, k * 1.1), c + Vector2(-k * 0.45, 0.0),
				c + Vector2(k * 0.45, 0.0), c + Vector2(k * 0.8, k * 1.1)]), col)
	_hits.append([r, id])
	if hot and id in ["hero", "menu"]:
		_ctext(Vector2(c.x, r.position.y - 12.0), _tr("pax_rpg_wui_" + ("char" if id == "hero" else "menu")), _f_sc, 16, IVORY, 140.0)


# ---------- карточка города ----------

func _card_r() -> Rect2:
	return _frame(_cfg, "card", _w - 22.0 - 372.0, 150.0, 372.0)


func _city_deg(city: Dictionary) -> float:
	var pp: Vector2 = travel.planet.player_pos()
	return rad_to_deg(Planet.dir_of(pp.x, pp.y).angle_to(Planet.dir_of(float(city.get("lat", 0.0)), float(city.get("lon", 0.0)))))


func _draw_card() -> void:
	var r := _card_r()
	var id := str(_sel.get("id", ""))
	var emp := str(_sel.get("empire", ""))
	var ek: String = EMPIRE_KEY.get(emp, "")
	# картинка города и герб — в окнах рамки (под ней)
	var pic := _hole(_cfg, "card", r, 0)
	var art := _t(str((_ui.get("city_art", {}) as Dictionary).get(id, "")))
	_root.draw_rect(pic.grow(2.0), Color(0.08, 0.03, 0.04))
	if art != null:
		var ts := art.get_size()
		var k := maxf(pic.size.x / ts.x, pic.size.y / ts.y)
		var src := Rect2((ts - pic.size / k) * 0.5, pic.size / k)
		_root.draw_texture_rect_region(art, pic.grow(2.0), src)
	else:
		var et := _t("textures/inventory/emp_%s.png" % ek) if ek != "" else null
		if et != null:
			var s := pic.size.y * 0.9
			_root.draw_texture_rect(et, Rect2(pic.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.25))
	var em := _hole(_cfg, "card", r, 1)
	_disc(em.get_center(), em.size.x * 0.52, Color(0.08, 0.03, 0.04))
	_tex_frame(_ftex.get("card"), r)
	var et2 := _t("textures/inventory/emp_%s.png" % ek) if ek != "" else null
	if et2 != null:
		var es := em.size.x * 0.92
		_root.draw_texture_rect(et2, Rect2(em.get_center() - Vector2(es, es) * 0.5, Vector2(es, es)), false)
	# закрыть
	var xr := Rect2(r.end.x - 52.0, r.position.y + 2.0, 30.0, 30.0)
	_text(Vector2(xr.position.x + 8.0, xr.position.y + 23.0), "×", _f_serif, 28, IVORY if _hover == "close" else IVORY_DIM)
	_hits.append([xr, "close"])
	var x := r.position.x + r.size.x * 0.115
	var w := r.size.x * 0.77
	var y := r.position.y + r.size.y * 0.262
	_text(Vector2(x, y), _tr("pax_rpg_city_" + id), _f_sc, 34, IVORY, HORIZONTAL_ALIGNMENT_LEFT, em.position.x - x - 6.0)
	y += 14.0
	_text(Vector2(x, y + 10.0), _tr("pax_rpg_emp_" + ek), _f_serif, 16, IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, em.position.x - x - 6.0)
	y = r.position.y + r.size.y * 0.345
	# путь и опасность
	var deg := _city_deg(_sel)
	var here := deg < 0.6
	var hrs := clampf(deg * HOURS_PER_DEG, 0.25, 8.0)
	var rep := _rep(_sel)
	var tier := _tier(rep)
	var danger := 2 if tier == 0 else (1 if tier == 1 else 0)
	var rows := [[_tr("pax_rpg_wui_distance"), _tr("pax_rpg_wui_here") if here else _tr("pax_rpg_wui_km") % _thousands(roundi(deg * KM_PER_DEG)), IVORY],
		[_tr("pax_rpg_wui_time"), "—" if here else _tr("pax_rpg_wui_hours") % ("%.1f" % hrs).replace(".0", ""), IVORY],
		[_tr("pax_rpg_wui_danger"), _tr("pax_rpg_wui_danger_%d" % danger), [Color(0.55, 0.85, 0.6), AMBER, Color(1.0, 0.35, 0.3)][danger]]]
	for rv: Variant in rows:
		var row: Array = rv
		_text(Vector2(x + 4.0, y + 6.0), str(row[0]), _f_serif, 19, IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6)
		_text(Vector2(x + w * 0.45, y + 6.0), str(row[1]), _f_sc, 19, row[2], HORIZONTAL_ALIGNMENT_RIGHT, w * 0.55 - 4.0)
		_root.draw_line(Vector2(x, y + 15.0), Vector2(x + w, y + 15.0), Color(GOLD, 0.25), 1.0)
		y += 34.0
	# репутация
	y += 8.0
	_text(Vector2(x, y), _tr("pax_rpg_wui_rep"), _f_sc, 16, GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
	y += 10.0
	var rt := _t("textures/inventory/rep_%d.png" % tier)
	if rt != null:
		_root.draw_texture_rect(rt, Rect2(x, y, 36.0, 36.0), false)
	var tiers: Array = _eq.get("rep_tiers", [])
	var tcol := Color.html(str((tiers[tier] as Dictionary).get("color", "#cfc6b4"))) if tier < tiers.size() else IVORY
	_text(Vector2(x + 44.0, y + 15.0), _tr("pax_rpg_emp_" + ek), _f_serif, 16, IVORY, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5)
	_text(Vector2(x + w * 0.5, y + 15.0), _tr("pax_rpg_rep_%d" % tier), _f_sc, 18, tcol, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5)
	_fill(Rect2(x + 44.0, y + 24.0, w - 46.0, 7.0), (rep + 100.0) / 200.0, tcol)
	y += 52.0
	# места
	var places := _city_places(id)
	if not places.is_empty():
		_text(Vector2(x, y), _tr("pax_rpg_wui_places"), _f_sc, 16, GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		y += 8.0
		for i: int in mini(places.size(), 8):
			var pl: Array = places[i]
			var px := x + (i % 2) * w * 0.5
			var py := y + (i / 2) * 31.0
			_glyph(int(pl[1]), Rect2(px, py, 26.0, 26.0))
			_text(Vector2(px + 30.0, py + 19.0), _tr(str(pl[0])), _f_serif, 17, IVORY, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5 - 34.0)
	# кнопки под карточкой
	var bw := r.size.x * 0.86
	var br := _frame(_cfg, "btn_red", r.get_center().x - bw * 0.5, r.end.y + 4.0, bw)
	_button("btn_red", "go", br, _tr("pax_rpg_wui_enter") if here else _tr("pax_rpg_wui_travel"), "play")
	var qr := _frame(_cfg, "btn_dark", r.get_center().x - bw * 0.5, br.end.y + 4.0, bw)
	var n := _city_quests(id).size()
	_button("btn_dark", "quests", qr, _tr("pax_rpg_wui_quests") + ("  (%d)" % n if n > 0 else ""), "scroll")


## Места города — значки его карты (config/<город>_map.json → art.markers), крупные — первыми.
func _city_places(id: String) -> Array:
	if _places.has(id):
		return _places[id]
	var out: Array = []
	var txt := mod.read_text("config/%s_map.json" % id)
	var mp: Variant = JSON.parse_string(txt) if txt != "" else null
	if mp is Dictionary and (mp as Dictionary).get("art", {}) is Dictionary:
		var art: Dictionary = (mp as Dictionary).art
		var mk: Dictionary = art.get("markers", {})
		var big: Array = art.get("big", [])
		for k: String in mk:
			out.append([k, int(mk[k]), 0 if big.has(k) else 1])
		out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
	_places[id] = out
	return out


func _city_quests(id: String) -> Array:
	var q := Quest.get_q(mod)
	if q.is_empty() or str(q.get("city", "")) != id:
		return []
	var item := Quest.short(mod, q)
	return [[_tr("pax_rpg_wui_quest_row") % [item, str(q.get("npc_name", ""))], str(q.get("state", "")) == "found"]]


func _draw_popup() -> void:
	var cr := _card_r()
	var r := _frame(_cfg, "popup", cr.position.x - 420.0 - 10.0, 0.0, 420.0)
	r.position.y = cr.end.y + 60.0 - r.size.y
	_tex_frame(_ftex.get("popup"), r)
	_hits.append([r, "popup"])
	var x := r.position.x + r.size.x * 0.1
	var w := r.size.x * 0.8
	var id := str(_sel.get("id", ""))
	_text(Vector2(x, r.position.y + r.size.y * 0.21), _tr("pax_rpg_wui_quests_in") % _tr("pax_rpg_city_" + id), _f_sc, 22, IVORY,
		HORIZONTAL_ALIGNMENT_LEFT, w)
	var qs := _city_quests(id)
	var y := r.position.y + r.size.y * 0.42
	if qs.is_empty():
		_text(Vector2(x, y), _tr("pax_rpg_wui_no_quests"), _f_serif, 18, IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		_text(Vector2(x, y + 26.0), _tr("pax_rpg_wui_no_quests_2"), _f_serif, 18, IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	for qv: Variant in qs:
		var q: Array = qv
		_root.draw_colored_polygon(_diamond(Vector2(x + 8.0, y - 6.0), 5.0), AMBER if bool(q[1]) else IVORY)
		_text(Vector2(x + 22.0, y), str(q[0]), _f_serif, 19, IVORY, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0)
		y += 30.0
