extends CanvasLayer
## Выбор героя — при первом входе в мир за сессию (travel.gd → enter; новая игра Pax RPG сбрасывает выбор).
## Карточки героев: портрет, имя, главная характеристика (★), пассивка, приёмы. Пока доступен один —
## Чёрный рыцарь (config/hero.json → character); остальные места — «Скоро». Выбор — сигнал picked(id).

signal picked(id: String)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const W := 1920.0
const H := 1080.0
const SLOTS := 3                     # карточек на экране: 1 герой + места под будущих

var mod: PaxMod
var _root: Control
var _frame: Control
var _serif: Font
var _sans: Font
var _cjk: Font
var _panel_sh: Shader


func setup(m: PaxMod, character: Dictionary) -> void:
	mod = m
	name = "PaxRpgCharSelect"
	layer = 120
	_serif = Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 700)
	_sans = Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	_cjk = Hud._sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "SimSun"], 700)
	_panel_sh = m.shader("shaders/ui_panel.gdshader")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.035, 0.09, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	_root.resized.connect(_fit)
	var title := _label(mod.tr_key("pax_rpg_char_title"), Vector2(0, 110), _serif, 56, Hud.TEXT, _frame, W)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var line := ColorRect.new()
	line.color = Color(Hud.GOLD, 0.7)
	line.position = Vector2(W * 0.5 - 180, 190)
	line.size = Vector2(360, 2)
	_frame.add_child(line)
	var cw := 440.0
	var gap := 50.0
	var x0 := (W - cw * SLOTS - gap * (SLOTS - 1)) * 0.5
	for i: int in SLOTS:
		var r := Rect2(x0 + i * (cw + gap), 250, cw, 680)
		if i == 0:
			_hero_card(r, character)
		else:
			_empty_card(r)
	_fit()


func _fit() -> void:
	var sz := _root.size
	var s := minf(sz.x / W, sz.y / H)
	_frame.scale = Vector2(s, s)
	_frame.position = (sz - Vector2(W, H) * s) * 0.5


func _panel(r: Rect2, selected: bool, empty: bool) -> ColorRect:
	var c := ColorRect.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel_sh != null:
		var m := ShaderMaterial.new()
		m.shader = _panel_sh
		m.set_shader_parameter("px", r.size)
		m.set_shader_parameter("selected", 1.0 if selected else 0.0)
		m.set_shader_parameter("empty", 1.0 if empty else 0.0)
		c.material = m
	else:
		c.color = Hud.INK
	_frame.add_child(c)
	return c


func _label(text: String, pos: Vector2, font: Font, fs: int, color: Color, parent: Control, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Hud.SHADOW)
	l.add_theme_constant_override("outline_size", 4)
	if width > 0.0:
		l.size = Vector2(width, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _hero_card(r: Rect2, ch: Dictionary) -> void:
	var p := _panel(r, true, false)
	var id := str(ch.get("id", "black_knight"))
	var tex := mod.texture("textures/hero_portrait.png")
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(30, 30)
		tr.size = Vector2(r.size.x - 60, 280)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	var w := r.size.x - 60
	var name_l := _label(mod.tr_key("pax_rpg_hero_name"), Vector2(30, 324), _serif, 40, Hud.TEXT, p, w)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var main := str(ch.get("main_stat", ""))
	var y := 386.0
	if main != "":
		_label(mod.tr_key("pax_rpg_char_main").to_upper(), Vector2(30, y), _sans, 13, Hud.DIM, p)
		_label("★ " + mod.tr_key("pax_rpg_attr_" + main), Vector2(30, y + 20), _sans, 22, Hud.AMBER, p)
		y += 62.0
	var passive := str(ch.get("passive", ""))
	if passive != "":
		_label(mod.tr_key("pax_rpg_inv_passive").to_upper(), Vector2(30, y), _sans, 13, Hud.DIM, p)
		_label(mod.tr_key("pax_rpg_passive_" + passive), Vector2(30, y + 20), _sans, 22, Hud.PINK, p)
		_label(mod.tr_key("pax_rpg_passive_" + passive + "_desc"), Vector2(30, y + 50), _sans, 15, Hud.MUTED, p, w)
		y += 92.0
	_label(mod.tr_key("pax_rpg_char_moves").to_upper(), Vector2(30, y), _sans, 13, Hud.DIM, p)
	_label(mod.tr_key("pax_rpg_char_%s_moves" % id), Vector2(30, y + 20), _sans, 15, Hud.TEXT, p, w)
	_label(mod.tr_key("pax_rpg_char_weapon_note"), Vector2(30, y + 84), _sans, 13, Hud.DIM, p, w)
	var btn := Button.new()
	btn.text = mod.tr_key("pax_rpg_char_pick")
	btn.position = Vector2(r.position.x + 90, r.end.y - 80)
	btn.size = Vector2(r.size.x - 180, 52)
	btn.add_theme_font_override("font", _serif)
	btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.16)
	sb.border_color = Hud.GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.22, 0.12, 0.22)
	sbh.border_color = Hud.PINK
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.pressed.connect(func() -> void: picked.emit(id))
	_frame.add_child(btn)


func _empty_card(r: Rect2) -> void:
	var p := _panel(r, false, true)
	var q := _label("？", Vector2(0, 220), _cjk, 120, Color(Hud.DIM, 0.5), p, r.size.x)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(mod.tr_key("pax_rpg_char_soon"), Vector2(0, 400), _sans, 22, Hud.DIM, p, r.size.x)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
