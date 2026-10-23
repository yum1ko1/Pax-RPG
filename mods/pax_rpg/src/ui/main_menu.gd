extends CanvasLayer
## Главное меню Pax RPG — вместо меню игры (оно спрятано, пока виден наш экран): фон Юрумы (textures/menu/bg.jpg)
## с глубиной — карта глубины (depth.png: скала с самураем ближе всего, город, небо дальше) сдвигает слои за мышью
## (параллакс в шейдере), туман ползёт по долине, кольцо в небе дышит, алые искры поднимаются от скалы.
## Кнопки — свои: наведение — сдвиг, алое свечение, растущая черта; нажатие — искры. «Continue» и «Load» грузят
## партию сами (main.gd → mp_session().open_slot), меню игры показываем только для его экранов: новая игра,
## настройки, сеть; вернулся игрок на главный шаг меню — снова наш экран.

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const MenuSettings := preload("res://mods/pax_rpg/src/ui/menu_settings.gd")
const CRIMSON := Color(1.0, 0.16, 0.22)
const RING := Vector2(0.766, 0.195)              # кольцо в небе — доля картинки
const TIP := Vector2(0.1276, 0.4476)             # алый кончик копья
const IMG := Vector2(3840.0, 2176.0)             # размер фона (доли картинки → пиксели экрана)

var mod: PaxMod
var _find: Callable                              # () -> меню игры (Menu.gd) или null
var _menu: Node                                  # меню игры (CanvasLayer) — из main.gd attach(), на старте его ещё нет
var _want := true                                # наш экран виден (тогда меню игры спрятано)
var slots: Callable                              # main.gd: () -> имена сохранений
var open_slot: Callable                          # main.gd: (слот) — загрузить партию
var _music: AudioStreamPlayer                     # музыка главного меню (sounds/music/mana_lullaby.ogg, по кругу)
var _items: Array = []                           # [[ключ перевода, Callable]]
var _root: Control
var _bg: TextureRect
var _mat: ShaderMaterial
var _sparks: CPUParticles2D
var _col: VBoxContainer
var _hot := 0.0
var _hot_want := 0.0
var _mouse := Vector2.ZERO
var _t := 0.0
var _shown := false
var _rocks: Array = []                           # [TextureRect, u, v, w, h, фаза, амплитуда, период, поворот, глубина]
var _brush: FontFile                             # Katsuno (только латиница) — заголовок и пункты по-английски
## Стили (настройка menu_style): A — «Цусима»: название кистью, пункты — Cinzel, бледно-лиловые, выделение —
## кольцо и мазок; подпись под названием — Cormorant, курсив, лиловая. B — «Сэкиро»: пункты мельче и шире, тускло-
## серые, выделение — алая черта слева и свет текста; подпись — внизу слева. C — «Кисть»: всё кистью Katsuno, но
## пункты лилово-белые без алого (алое — только у названия), подпись — внизу слева.
const STYLES := {
	"A": {"font": "fonts/cinzel.ttf", "size": 25, "spacing": 4, "gap": 10, "col": Color(0.86, 0.82, 0.92),
		"shadow": Color(0.05, 0.0, 0.08, 0.7), "brush": true, "sub_at": "under", "sub_size": 21},
	"B": {"font": "fonts/cinzel.ttf", "size": 20, "spacing": 7, "gap": 16, "col": Color(0.74, 0.71, 0.79),
		"shadow": Color(0.03, 0.0, 0.05, 0.75), "brush": false, "sub_at": "corner", "sub_size": 19},
	"C": {"font": "fonts/katsuno_demo.ttf", "size": 28, "spacing": 3, "gap": 14, "col": Color(0.9, 0.86, 0.95),
		"shadow": Color(0.05, 0.0, 0.08, 0.75), "brush": true, "sub_at": "corner", "sub_size": 19},
}
var st: Dictionary
var _item_font: FontFile
var _sub_font: FontFile
const EN := {"pax_rpg_menu_continue": "Continue", "pax_rpg_menu_new": "New Game", "pax_rpg_menu_load": "Load", "pax_rpg_menu_char": "Character",
	"pax_rpg_menu_mp": "Multiplayer", "pax_rpg_menu_settings": "Settings", "pax_rpg_menu_exit": "Exit"}


func setup(m: PaxMod, find_menu: Callable, items: Array) -> void:
	mod = m
	_find = find_menu
	_items = items
	name = "PaxRpgMainMenu"
	layer = 60
	visible = false
	_build()
	ready.connect(func() -> void: get_tree().node_added.connect(_on_any_node))


func _load_font(rel: String) -> FontFile:
	var f := FontFile.new()
	f.data = mod.read_bytes(rel)
	return f


func _build() -> void:
	st = STYLES.get(str(mod.get_setting("menu_style", "B")), STYLES["B"])
	_item_font = _load_font(str(st.font))
	_sub_font = _load_font("fonts/cormorant_garamond.ttf")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # меню игры под нами не нажимается
	add_child(_root)
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.texture = Assets.tex(mod, "textures/menu/bg_clean.jpg")   # камни вырезаны (dev: menu_rocks) — они летают сами
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BG
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("depth", Assets.tex(mod, "textures/menu/depth.png"))
	_mat.set_shader_parameter("ring", RING)
	_mat.set_shader_parameter("tip", TIP)
	_mat.set_shader_parameter("robe", Assets.tex(mod, "textures/menu/robe.png"))
	_mat.set_shader_parameter("plate", Assets.tex(mod, "textures/menu/plate.jpg"))      # фон без скалы с самураем
	_mat.set_shader_parameter("fgmask", Assets.tex(mod, "textures/menu/fgmask.png"))    # передний план: скала, самурай
	_bg.material = _mat
	_root.add_child(_bg)
	_make_rocks()
	_sparks = CPUParticles2D.new()                   # алые искры от скалы и над долиной
	_sparks.amount = 70
	_sparks.lifetime = 6.0
	_sparks.preprocess = 6.0
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.direction = Vector2(0.25, -1.0)
	_sparks.spread = 25.0
	_sparks.gravity = Vector2(12.0, -14.0)
	_sparks.initial_velocity_min = 12.0
	_sparks.initial_velocity_max = 40.0
	_sparks.scale_amount_min = 1.5
	_sparks.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CRIMSON, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.35, 0.3, 0.95))
	ramp.set_color(1, Color(CRIMSON, 0.0))
	_sparks.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = add
	_root.add_child(_sparks)
	var shade := TextureRect.new()                   # тень слева — пункты читаются на небе и горах
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.01, 0.06, 0.85))
	g.set_color(1, Color(0.03, 0.01, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.42
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var title := Label.new()
	title.text = "PAX RPG"
	_brush = FontFile.new()
	_brush.data = mod.read_bytes("fonts/katsuno_demo.ttf")
	title.add_theme_font_override("font", _brush)
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.98, 0.93, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(CRIMSON, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 18)
	title.position = Vector2(70, 26)
	title.name = "Title"
	_root.add_child(title)
	var sub := Label.new()                           # подпись: другой оттенок и шрифт — название на её фоне ярче
	sub.text = "YURUMA   ·   YEAR MXLVII OF THE SHATTERED SKY"
	var sv := FontVariation.new()
	sv.base_font = _sub_font
	sv.variation_embolden = 0.2
	sv.spacing_glyph = 3
	sub.add_theme_font_override("font", sv)
	sub.add_theme_font_size_override("font_size", int(st.sub_size))
	sub.add_theme_color_override("font_color", Color(0.78, 0.72, 0.88, 0.9))
	sub.add_theme_color_override("font_shadow_color", Color(0.03, 0.0, 0.06, 0.8))
	sub.add_theme_constant_override("shadow_offset_y", 2)
	sub.add_theme_constant_override("shadow_outline_size", 6)
	sub.name = "Sub"
	if str(st.sub_at) == "under":
		sub.position = Vector2(84, 214)
		var tick := ColorRect.new()                  # алая черточка перед подписью — связь с названием
		tick.color = Color(CRIMSON, 0.9)
		tick.size = Vector2(26, 2)
		tick.position = Vector2(-36, 15)
		sub.add_child(tick)
		sub.position.x += 36
	else:
		sub.anchor_top = 1.0
		sub.anchor_bottom = 1.0
		sub.position = Vector2(70, -70)
	_root.add_child(sub)
	_col = VBoxContainer.new()
	_col.position = Vector2(60, 272)
	_col.add_theme_constant_override("separation", int(st.gap))
	_root.add_child(_col)
	_main_items()


## Пункты главного экрана. it[2] — пункту нужен экран меню игры (новая игра, настройки, сеть): тогда меню игры
## показываем, а своё прячем; без него (продолжить, загрузить, выход) меню игры так и не появляется.
func _main_items() -> void:
	for c: Node in _col.get_children():
		c.queue_free()
	for it: Array in _items:
		var key := str(it[0])
		var fn: Callable = it[1]
		if key == "pax_rpg_menu_load":                 # свой список — на месте, наш экран не уходит
			_col.add_child(_button(str(EN.get(key, key)), _saves_items, false, true))
			continue
		elif key == "pax_rpg_menu_char":            # выбор героя — поверх нашего экрана, меню остаётся
			_col.add_child(_button(str(EN.get(key, key)), fn, false, true))
			continue
		elif key == "pax_rpg_menu_settings":
			_col.add_child(_button(str(EN.get(key, key)), _open_settings, false, true))
			continue
		_col.add_child(_button(str(EN.get(key, key)), fn, it.size() > 2 and bool(it[2])))


## «Settings» — свои настройки (menu_settings.gd) на месте пунктов и названия; «Back» — назад.
var _settings: Control


func _open_settings() -> void:
	for n: String in ["Title", "Sub"]:
		var c := _root.get_node_or_null(n)
		if c != null:
			(c as CanvasItem).visible = false
	_col.visible = false
	_settings = MenuSettings.new()
	_settings.setup(mod, _item_font, _sub_font, _find, _close_settings)
	_root.add_child(_settings)


func _close_settings() -> void:
	if is_instance_valid(_settings):
		_settings.queue_free()
	for n: String in ["Title", "Sub"]:
		var c := _root.get_node_or_null(n)
		if c != null:
			(c as CanvasItem).visible = true
	_col.visible = true


## «Load» — свой список сохранений (новые сверху), «Back» — назад к пунктам.
func _saves_items() -> void:
	for c: Node in _col.get_children():
		c.queue_free()
	var list: Array = slots.call() if slots.is_valid() else []
	list.reverse()
	for sl: Variant in list.slice(0, 8):
		var name_s := str(sl)
		_col.add_child(_button(name_s.to_upper(), func() -> void: open_slot.call(name_s), false, true))
	if list.is_empty():
		_col.add_child(_button("NO SAVES", func() -> void: pass, false, true))
	_col.add_child(_button("BACK", _main_items, false, true))


## main.gd на world_ready: меню игры. Его главный экран — сигнал о новой кнопке на нём (наша «Continue» —
## значит, игрок вернулся на главный шаг меню: из настроек, сети или из партии). Ни опроса, ни обхода дерева.
func attach(menu: Node) -> void:
	active = self
	if menu == null or menu == _menu:
		return
	_menu = menu
	var scr: Variant = menu.get("screen")
	if scr is Node and not (scr as Node).child_entered_tree.is_connected(_on_screen_child):
		(scr as Node).child_entered_tree.connect(_on_screen_child)
	if _want:                                        # наш экран на месте — меню игры не показываем
		_game_menu(false)
	if scr is Node:                                  # главный шаг уже построен (выход из партии) — наш экран сразу
		for c: Node in (scr as Node).get_children():
			if c is Button and str(c.get_meta("menu_id", "")) == "mod:pax_rpg_continue":
				show_menu(true)
				break


## Любая новая кнопка в дереве — только проверка её метки (событие игры, без обхода дерева): меню игры могли
## собрать заново (выход из партии на глобусе) — тогда это его главный шаг, и снова наш экран.
func _on_any_node(n: Node) -> void:
	if n is Button and str(n.get_meta("menu_id", "")) == "mod:pax_rpg_continue":
		_check_back.call_deferred(weakref(n))


func _on_screen_child(n: Node) -> void:
	if n is Button:
		_check_back.call_deferred(weakref(n))


func _check_back(w: WeakRef) -> void:
	var b: Object = w.get_ref()
	if b != null and str(b.get_meta("menu_id", "")) == "mod:pax_rpg_continue":
		var m: Node = (b as Node).get_parent()
		while m != null and not (m is CanvasLayer and m.has_method("_start_game")):
			m = m.get_parent()
		if m != null and m != _menu:
			attach(m)
		show_menu(true)


## Игрок ушёл в мир (город, глобус, загрузка сохранения) любым путём — наш экран и его музыка гаснут, меню игры
## не трогаем. Раньше «Загрузить» из нашего списка оставлял _want — колыбельная играла поверх музыки города.
static var active: CanvasLayer


static func off() -> void:
	if is_instance_valid(active):
		active.set("_want", false)


func show_menu(on: bool) -> void:
	_want = on
	_game_menu(not on)


func _game_menu(on: bool) -> void:
	if is_instance_valid(_menu) and _menu is CanvasLayer:
		(_menu as CanvasLayer).visible = on

## Летящие обломки скал: вырезаны из фона (config/menu_rocks.json — место и размер в долях картинки), каждый
## медленно плывёт вверх-вниз и покачивается в своём ритме; крупные ближе — сильнее сдвигаются за мышью.
func _make_rocks() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layer)
	var parsed: Variant = JSON.parse_string(mod.read_text("config/menu_rocks.json"))
	if not (parsed is Array):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1047
	for r: Variant in parsed:
		var d: Dictionary = r
		var tr := TextureRect.new()
		tr.texture = mod.texture("textures/menu/rocks/" + str(d.f))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)
		var big := clampf(float(d.w) * 18.0, 0.0, 1.0)              # 0 — крошка, 1 — крупный обломок
		_rocks.append([tr, float(d.u), float(d.v), float(d.w), float(d.h), rng.randf() * TAU,
			lerpf(0.0018, 0.006, big), rng.randf_range(5.5, 9.5), rng.randf_range(1.5, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			lerpf(0.5, 0.85, big)])


func _rocks_tick(vs: Vector2) -> void:
	var k := maxf(vs.x / IMG.x, vs.y / IMG.y)           # как у фона: KEEP_ASPECT_COVERED
	var size := IMG * k
	var o := (vs - size) * 0.5
	for r: Array in _rocks:
		var tr: TextureRect = r[0]
		var ph := TAU * _t / float(r[7]) + float(r[5])
		var bob := Vector2(sin(ph * 0.5) * 0.35, sin(ph)) * float(r[6])      # плывёт по «восьмёрке»
		var par := _mouse * Vector2(0.018, 0.012) * (float(r[9]) - 0.25)     # параллакс, как у фона
		tr.size = Vector2(float(r[3]), float(r[4])) * size
		tr.pivot_offset = tr.size * 0.5
		tr.position = o + (Vector2(float(r[1]), float(r[2])) + bob + par) * size
		tr.rotation = deg_to_rad(float(r[8]) * sin(ph * 0.7))


func _serif() -> Font:
	return Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)


## Надпись как у заголовка: светлая, с алым отливом снизу.
func _glow_text(l: Label, dy: int, blur: int) -> void:
	l.add_theme_color_override("font_color", Color(0.98, 0.93, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(CRIMSON, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", dy)
	l.add_theme_constant_override("shadow_outline_size", blur)


## Пункт: кисть Katsuno заглавными, с алым отливом. Наведение — в мотиве кольца в небе: слева прорисовывается
## малое алое кольцо, под текстом кисть проводит рваный мазок (шейдер BRUSH: края — шум, по мазку бежит блик),
## с конца мазка — искры; текст сдвигается и чуть разгорается. Нажатие — вспышка мазка и действие.
func _button(text: String, fn: Callable, game_menu := false, stay := false) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(440, 56)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var stroke := ColorRect.new()
	stroke.position = Vector2(26, 4)
	stroke.size = Vector2(430, 56)
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BRUSH
	sm.shader = sh
	sm.set_shader_parameter("seed", randf() * 10.0)
	stroke.material = sm
	stroke.visible = bool(st.brush)
	box.add_child(stroke)
	var tickv := ColorRect.new()                     # стиль B: алая черта слева вместо мазка
	tickv.color = CRIMSON
	tickv.position = Vector2(22, 10)
	tickv.size = Vector2(3, 0)
	tickv.visible = not bool(st.brush)
	box.add_child(tickv)
	var ring := Ring.new()
	ring.position = Vector2(14, 33)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = bool(st.brush)
	box.add_child(ring)
	var lab := Label.new()
	lab.text = text.to_upper()
	lab.add_theme_font_size_override("font_size", int(st.size))
	lab.add_theme_color_override("font_color", st.col as Color)
	lab.add_theme_color_override("font_shadow_color", st.shadow as Color)
	lab.add_theme_constant_override("shadow_offset_y", 2)
	lab.add_theme_constant_override("shadow_outline_size", 8)
	var fv := FontVariation.new()
	fv.base_font = _item_font
	fv.spacing_glyph = int(st.spacing)
	lab.add_theme_font_override("font", fv)
	lab.position = Vector2(34, maxf(0.0, (56.0 - float(st.size) * 1.5) * 0.5))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lab)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 22
	burst.lifetime = 0.8
	burst.explosiveness = 0.85
	burst.direction = Vector2(1, -0.4)
	burst.spread = 60.0
	burst.gravity = Vector2(0, -30)
	burst.initial_velocity_min = 50.0
	burst.initial_velocity_max = 170.0
	burst.scale_amount_min = 1.2
	burst.scale_amount_max = 2.6
	burst.color = Color(1.0, 0.35, 0.35)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = add
	box.add_child(burst)
	var tw_ref := [null]
	var set_p := func(v: float) -> void: sm.set_shader_parameter("progress", v)
	var cur := [0.0]
	var hover := func(on: bool) -> void:
		if tw_ref[0] != null:
			(tw_ref[0] as Tween).kill()
		var tw := box.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_ref[0] = tw
		var w := lab.get_minimum_size().x + 60.0
		stroke.size.x = w
		tw.tween_method(func(v: float) -> void:
			cur[0] = v
			set_p.call(v), cur[0], 1.0 if on else 0.0, 0.32 if on else 0.22)
		tw.tween_property(ring, "progress", 1.0 if on else 0.0, 0.35 if on else 0.2)
		tw.tween_property(tickv, "size:y", 34.0 if on else 0.0, 0.2)
		tw.tween_property(lab, "position:x", 46.0 if on else 34.0, 0.25)
		tw.tween_property(lab, "theme_override_colors/font_color", Color(1.0, 0.96, 0.97) if on else (st.col as Color), 0.18)
		tw.tween_property(lab, "theme_override_colors/font_shadow_color", Color(1.0, 0.18, 0.28, 0.8) if on else (st.shadow as Color), 0.2)
		_hot_want = 1.0 if on else 0.0
	box.mouse_entered.connect(hover.bind(true))
	box.mouse_exited.connect(hover.bind(false))
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			burst.position = Vector2(82.0 + lab.get_minimum_size().x, 33.0)   # искры — при нажатии, не при наведении
			burst.restart()
			var tw := box.create_tween()
			tw.tween_property(stroke, "modulate", Color(1.8, 1.8, 1.8), 0.06)
			tw.tween_property(stroke, "modulate", Color.WHITE, 0.14)
			tw.tween_callback(_leave.bind(fn, game_menu, stay)))
	return box


## Нажата наша кнопка: меню игры ищем один раз сейчас (оно на месте, игра ничего не грузит) — по нему потом
## узнаём, что игрок вернулся на главный экран (из настроек, загрузки или из партии).
func _leave(fn: Callable, game_menu: bool, stay: bool) -> void:
	if _menu == null and _find.is_valid():             # на world_ready меню игры ещё не было — берём сейчас
		attach(_find.call())
	if not stay:
		_want = false
		if game_menu:                                # экран меню игры нужен (новая игра, настройки, сеть)
			_game_menu(true)
	fn.call()


## Малое кольцо слева от пункта — как кольцо в небе: дуга прорисовывается по progress, со свечением.
class Ring extends Control:
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		if progress <= 0.001:
			return
		var a0 := -PI * 0.5
		var a1 := a0 + TAU * progress
		draw_arc(Vector2.ZERO, 9.0, a0, a1, 40, Color(1.0, 0.2, 0.3, 0.35 * progress), 6.0, true)
		draw_arc(Vector2.ZERO, 9.0, a0, a1, 40, Color(1.0, 0.85, 0.88, progress), 1.8, true)


const BRUSH := """shader_type canvas_item;
render_mode blend_add;
uniform float progress = 0.0;
uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	// мазок: толще слева, к концу тоньше и рвётся; края и «волоски» кисти — шум
	float x = uv.x;
	float thick = mix(0.48, 0.3, x);
	float edge = (n(vec2(x * 22.0 + seed, 0.0)) - 0.5) * 0.18;
	float d = abs(uv.y - 0.52 - edge * 0.5);
	float body = smoothstep(thick, thick - 0.1, d);
	float hair = smoothstep(0.35, 0.75, n(vec2(x * 3.0 + seed, uv.y * 40.0)));
	body *= mix(0.78, 1.0, hair);
	body *= smoothstep(1.0, 0.7, x) * smoothstep(0.0, 0.04, x);           // хвост мазка тает
	float reveal = smoothstep(progress * 1.08, progress * 1.08 - 0.08, x);  // кисть ведёт слева направо
	float shine = exp(-pow((x - fract(TIME * 0.45) * 1.3 + 0.15) * 7.0, 2.0)) * 0.6;   // бегущий блик
	vec3 c = mix(vec3(0.75, 0.04, 0.12), vec3(1.0, 0.3, 0.38), smoothstep(0.0, 0.6, 1.0 - x)) + vec3(1.0, 0.6, 0.65) * shine;
	COLOR = vec4(c, body * reveal * 0.95);
}"""


## Музыка меню: на показ — нарастает за 2 с, на уход в игру — гаснет за 1 с.
func _menu_music(on: bool) -> void:
	if _music == null:
		var st: AudioStream = mod.sound("sounds/music/mana_lullaby.ogg")
		if st == null:
			return
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		_music = AudioStreamPlayer.new()
		_music.stream = st
		_music.volume_db = -60.0
		add_child(_music)
	var tw := create_tween()
	if on:
		if not _music.playing:
			_music.play()
		tw.tween_property(_music, "volume_db", -9.0, 2.0)
	else:
		tw.tween_property(_music, "volume_db", -60.0, 1.0)
		tw.tween_callback(_music.stop)


func _process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("main_menu._process")
	var want := _want
	if want != _shown:
		_shown = want
		visible = want
		if want:
			_root.modulate.a = 0.0
			create_tween().tween_property(_root, "modulate:a", 1.0, 0.5)
		_menu_music(want)
	if not visible:
		return
	_t += delta
	var vs := _root.get_viewport_rect().size
	var m := (_root.get_local_mouse_position() / vs - Vector2(0.5, 0.5)) * 2.0
	_mouse = _mouse.lerp(m.clamp(Vector2(-1, -1), Vector2(1, 1)), 1.0 - exp(-delta * 3.0))   # плавно, без дрожи
	_hot = move_toward(_hot, _hot_want, delta * 3.0)
	_mat.set_shader_parameter("mouse", _mouse)
	_mat.set_shader_parameter("hot", _hot)
	_mat.set_shader_parameter("time", fmod(_t, 600.0))   # время по кругу: шум тумана без потери точности
	_rocks_tick(vs)
	_sparks.position = Vector2(vs.x * 0.16, vs.y * 0.78) - _mouse * 18.0
	_sparks.emission_rect_extents = Vector2(vs.x * 0.18, 20.0)


const BG := """shader_type canvas_item;
uniform sampler2D depth : filter_linear;
uniform sampler2D robe : filter_linear;
uniform sampler2D plate : filter_linear;
uniform sampler2D fgmask : filter_linear;
uniform vec2 mouse = vec2(0.0);
uniform vec2 ring = vec2(0.766, 0.195);
uniform vec2 tip = vec2(0.1276, 0.4476);
uniform float hot = 0.0;
uniform float time = 0.0;
float n2(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(n2(i), n2(i + vec2(1, 0)), f.x), mix(n2(i + vec2(0, 1)), n2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
// глубина, размытая по 9 точкам: плавные края — без «лестницы» в тумане и двоения силуэта
float dsoft(vec2 uv) {
	float s = 0.0;
	for (int x = -1; x <= 1; x++)
		for (int y = -1; y <= 1; y++)
			s += texture(depth, uv + vec2(float(x), float(y)) * vec2(0.006, 0.009)).r;
	return s / 9.0;
}
void fragment() {
	vec2 uv = UV;
	// параллакс: за мышью сдвигается только передний план — скала с самураем (fgmask.png); город, горы и небо
	// стоят. Под сдвинутой скалой — plate.jpg (тот же фон, скала и самурай закрашены), без двоения силуэта.
	vec2 off = -mouse * vec2(0.0135, 0.009);
	// ветер треплет полы одежды самурая: волна идёт вниз по подолу, порывы — медленный шум
	float rb = texture(robe, uv + off).r;
	float gust = 0.55 + 0.45 * noise(vec2(time * 0.35, 3.1));
	off.x += rb * gust * 0.0016 * sin(time * 2.1 - uv.y * 70.0);
	off.y += rb * gust * 0.0004 * sin(time * 1.7 - uv.y * 50.0 + 1.3);
	vec2 fuv = clamp(uv + off, vec2(0.001), vec2(0.999));
	float a = texture(fgmask, fuv).r;
	// фон без скалы (plate) — только там, где скала была (маска, расширенная и размытая): plate чуть темнее
	// оригинала, и по всей площади давал заметный прямоугольник в тумане
	float m0 = 0.0;
	for (int x = -2; x <= 2; x++)
		for (int y = -2; y <= 2; y++)
			m0 = max(m0, texture(fgmask, uv + vec2(float(x), float(y)) * vec2(0.006, 0.01)).r);
	vec3 base = mix(texture(TEXTURE, uv).rgb, texture(plate, uv).rgb, smoothstep(0.02, 0.6, m0));
	vec3 c = mix(base, texture(TEXTURE, fuv).rgb, a);
	float d = dsoft(uv);
	vec2 suv = uv;
	// туман: слои с искривлением (domain warp) плывут по долине, ближний — быстрее и прозрачнее
	vec2 p = vec2(uv.x * 2.4 + time * 0.012, uv.y * 5.0);
	vec2 q = vec2(fbm(p + vec2(time * 0.02, 0.0)), fbm(p + vec2(5.2, 1.3) - vec2(time * 0.015, 0.0)));
	float f1 = smoothstep(0.35, 0.85, fbm(p + 1.8 * q));
	float valley = smoothstep(0.4, 0.58, uv.y) * (1.0 - smoothstep(0.84, 1.0, uv.y)) * (1.0 - smoothstep(0.1, 0.9, d) * 0.85);
	c = mix(c, vec3(0.66, 0.55, 0.74), valley * f1 * 0.42);
	vec2 p2 = vec2(uv.x * 1.6 + time * 0.035, uv.y * 3.0 + 4.0);
	float f2 = smoothstep(0.45, 0.9, fbm(p2 + fbm(p2 * 1.3 - time * 0.03)));
	float near_ = smoothstep(0.7, 0.95, uv.y);
	c = mix(c, vec3(0.5, 0.42, 0.58), near_ * f2 * 0.3);
	// кольцо в небе дышит; при наведении на пункт — ярче, с алым ореолом
	vec2 rd = (suv - ring) * vec2(1.77, 1.0);
	float r = length(rd);
	float glow = exp(-pow((r - 0.085) * 28.0, 2.0)) * (0.18 + 0.08 * sin(time * 1.3) + 0.35 * hot);
	glow += exp(-r * 9.0) * 0.12 * hot;
	c += vec3(1.0, 0.45, 0.55) * glow;
	// алый кончик копья тлеет
	float t = length((fuv - tip) * vec2(1.77, 1.0));
	c += vec3(1.0, 0.15, 0.2) * exp(-t * 260.0) * (0.6 + 0.4 * sin(time * 2.6)) * 1.4;
	// огни города чуть мерцают
	float lit = smoothstep(0.55, 0.85, max(c.r, c.g)) * step(0.5, uv.y);
	c += c * lit * 0.12 * sin(time * 2.0 + n2(floor(suv * 300.0)) * 6.28);
	float v = smoothstep(0.45, 1.0, length((uv - 0.5) * vec2(1.0, 1.2)));
	c *= 1.0 - v * 0.45;
	COLOR = vec4(c, 1.0);
}"""
