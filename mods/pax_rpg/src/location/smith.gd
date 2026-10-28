extends Control
## Кузня (фаза 3 плана, И-8 урезано): кузнец Кузнечного двора (npc.gd, роль blacksmith) точит клинок героя +1…+5 за
## золото — первый повод тратить деньги. Заточка одна на героя (настройка мода «sharpen»), каждая ступень — +BONUS к
## урону (location.gd → _dmg_mult). Цена ступени — PRICES; слава арены даёт скидку, как в лавке (fame.gd).
## Окно — по центру, мир на паузе (location.gd → paused()), Esc — уйти; «Поговорить» — разговор с кузнецом (talk.gd).

signal closed
signal talk_requested
signal sharpened(level: int)
signal sound(path: String, db: float)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Fame := preload("res://mods/pax_rpg/src/location/fame.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const PRICES := [150, 300, 550, 900, 1400]
const BONUS := 0.06                    # +6 % урона за ступень: +5 — +30 %
const W := 640.0
const H := 430.0
const GOLD := Color(0.84, 0.675, 0.384)
const IVORY := Color(0.945, 0.886, 0.769)
const DIM := Color(0.72, 0.63, 0.5)
const RED := Color(0.77, 0.125, 0.17)

var mod: PaxMod
var prog: Progress                     # золото героя
var weapon := ""                       # имя клинка героя (character.weapon.name)
var _who := ""
var _panel: Control
var _sharpen: Button
var _talk_b: Button
var _note := ""
var _note_col := IVORY
var _flash := 0.0
var _f_sc: Font
var _f: Font
var _f_it: Font


static func level(m: PaxMod) -> int:
	return clampi(int(m.get_setting("sharpen", 0)), 0, PRICES.size())


static func mult(m: PaxMod) -> float:
	return 1.0 + BONUS * level(m)


## Цена следующей ступени со скидкой славы; -1 — клинок уже +5.
static func price(m: PaxMod) -> int:
	var l := level(m)
	if l >= PRICES.size():
		return -1
	return roundi(int(PRICES[l]) * Fame.discount_mult(m))


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgSmith"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var back := ColorRect.new()                        # отдельное окно, как лавка: 3D под ним не рисуется
	back.color = Color(0.03, 0.012, 0.02, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	_f_sc = _font("fonts/cormorant_sc.ttf")
	_f = _font("fonts/cormorant_garamond.ttf")
	_f_it = _font("fonts/cormorant_garamond_italic.ttf")
	_panel = Control.new()
	_panel.size = Vector2(W, H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_sharpen = _button(Rect2(W * 0.5 - 150.0, H - 92.0, 300.0, 46.0), 24)
	_sharpen.pressed.connect(_do_sharpen)
	_talk_b = _button(Rect2(36.0, H - 40.0, 170.0, 30.0), 17)
	_talk_b.text = mod.tr_key("pax_rpg_smith_talk")
	_talk_b.pressed.connect(func() -> void: talk_requested.emit())
	var leave := _button(Rect2(W - 36.0 - 170.0, H - 40.0, 170.0, 30.0), 17)
	leave.text = mod.tr_key("pax_rpg_smith_leave")
	leave.pressed.connect(close)
	resized.connect(_place)


func _font(path: String) -> Font:
	var f := FontFile.new()
	f.data = mod.read_bytes(path)
	return f if not f.data.is_empty() else Hud._sys(["Cormorant Garamond", "Georgia"], 600)


func _button(r: Rect2, fs: int) -> Button:
	var b := Button.new()
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _f_sc)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", IVORY)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.59))
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color8(40, 10, 14, 235) if st != "hover" else Color8(70, 16, 22, 245)
		sb.border_color = GOLD if st != "disabled" else Color(GOLD, 0.35)
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override(st, sb)
	_panel.add_child(b)
	return b


func _place() -> void:
	var s := clampf(size.y / 1080.0, 0.6, 2.0) * 1.35
	_panel.scale = Vector2(s, s)
	_panel.position = (size - Vector2(W, H) * s) * 0.5


func open(p: Progress, who: String, weapon_name: String) -> void:
	prog = p
	_who = who
	weapon = weapon_name
	_note = ""
	visible = true
	_place()
	_update()
	sound.emit("sounds/katana_scrape.wav", -14.0)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	var k: InputEventKey = e
	if k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif k.pressed and not k.echo and k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not _sharpen.disabled:
		_do_sharpen()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible and _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		_panel.queue_redraw()


func _update() -> void:
	var pr := price(mod)
	var gold := prog.gold if prog != null else 0
	if pr < 0:
		_sharpen.text = mod.tr_key("pax_rpg_smith_max")
		_sharpen.disabled = true
	else:
		_sharpen.text = mod.tr_key("pax_rpg_smith_do") % pr
		_sharpen.disabled = gold < pr
	_panel.queue_redraw()


func _do_sharpen() -> void:
	var pr := price(mod)
	if pr < 0 or prog == null:
		return
	if prog.gold < pr:
		_note = mod.tr_key("pax_rpg_smith_poor") % (pr - prog.gold)
		_note_col = Color(1.0, 0.5, 0.45)
		_update()
		return
	prog.add_gold(-pr)
	var l := level(mod) + 1
	mod.set_setting("sharpen", l)
	_note = mod.tr_key("pax_rpg_smith_done") % l
	_note_col = Color(1.0, 0.86, 0.5)
	_flash = 1.0
	sound.emit("sounds/katana_hit_0.ogg", -6.0)
	sound.emit("sounds/katana_scrape.wav", -10.0)
	sharpened.emit(l)
	_update()


func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	_panel.draw_rect(r, Color8(16, 5, 8, 245))
	_panel.draw_rect(r, Color(GOLD, 0.9), false, 2.0)
	_panel.draw_rect(r.grow(-6.0), Color(GOLD, 0.3), false, 1.0)
	for cx: float in [0.0, W]:
		for cy: float in [0.0, H]:
			_panel.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - 8), Vector2(cx + 8, cy), Vector2(cx, cy + 8),
				Vector2(cx - 8, cy)]), GOLD)
	# заголовок: кузня и кузнец
	_center(Vector2(W * 0.5, 50), mod.tr_key("pax_rpg_smith_title").to_upper(), _f_sc, 30, IVORY)
	_center(Vector2(W * 0.5, 78), "%s · %s" % [_who, mod.tr_key("pax_rpg_npc_role_blacksmith")], _f_it, 19, DIM)
	_panel.draw_line(Vector2(60, 94), Vector2(W - 60, 94), Color(GOLD, 0.5), 1.0)
	var l := level(mod)
	var wn := weapon if weapon != "" else mod.tr_key("pax_rpg_smith_blade")
	var glow := Color(IVORY.lerp(Color(1.0, 0.8, 0.4), _flash))
	_center(Vector2(W * 0.5, 140), "%s  +%d" % [wn, l] if l > 0 else wn, _f_sc, 34, glow)
	# пять ступеней: закалённые — золотом, следующая — контуром
	var x0 := W * 0.5 - 2.0 * 56.0
	for i: int in PRICES.size():
		var c := Vector2(x0 + i * 56.0, 186)
		var dm := PackedVector2Array([c + Vector2(0, -15), c + Vector2(15, 0), c + Vector2(0, 15), c + Vector2(-15, 0)])
		if i < l:
			_panel.draw_colored_polygon(dm, Color(0.9, 0.62, 0.25).lerp(Color(1, 0.95, 0.7), _flash if i == l - 1 else 0.0))
		else:
			_panel.draw_colored_polygon(dm, Color8(30, 10, 12))
		_panel.draw_polyline(dm + PackedVector2Array([dm[0]]), GOLD if i <= l else Color(GOLD, 0.35), 1.5, true)
		_center(c + Vector2(0, 34), "+%d" % (i + 1), _f_sc, 16, IVORY if i < l else DIM)
	# урон сейчас → после заточки
	var now := roundi(BONUS * l * 100.0)
	var txt := mod.tr_key("pax_rpg_smith_dmg_max") % now if l >= PRICES.size() \
		else mod.tr_key("pax_rpg_smith_dmg") % [now, roundi(BONUS * (l + 1) * 100.0)]
	_center(Vector2(W * 0.5, 264), txt, _f, 22, IVORY)
	var gold := prog.gold if prog != null else 0
	var pl := mod.tr_key("pax_rpg_smith_purse") % gold
	var disc := Fame.discount(mod)
	if disc > 0 and l < PRICES.size():
		pl += "  ·  " + mod.tr_key("pax_rpg_fame_discount") % disc
	_center(Vector2(W * 0.5, 296), pl, _f_it, 19, Color8(240, 190, 100))
	if _note != "":
		_center(Vector2(W * 0.5, 324), _note, _f_it, 19, _note_col)


func _center(c: Vector2, s: String, f: Font, fs: int, col: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_panel.draw_string(f, Vector2(c.x - w * 0.5, c.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
