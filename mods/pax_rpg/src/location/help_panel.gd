extends Control
## Подсказка по управлению: слева — кнопка «操 Управление · H» (кликается, когда курсор свободен: Esc), по ней
## или по H — окно со списком клавиш (из строки pax_rpg_controls: пункты через « · » и строки). Окно открыто —
## курсор свободен; закрыли — снова у камеры.

signal toggled(open: bool)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")

var _btn: Button
var _panel: PanelContainer
var _list: VBoxContainer


func setup(mod: PaxMod) -> void:
	name = "PaxRpgHelp"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var serif := Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	var sans := Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	_btn = Button.new()
	_btn.text = "操  " + mod.tr_key("pax_rpg_help") + " · H"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_override("font", sans)
	_btn.add_theme_font_size_override("font_size", 15)
	_btn.add_theme_color_override("font_color", Hud.MUTED)
	_btn.add_theme_color_override("font_hover_color", Hud.PINK)
	for st: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(Hud.INK, 0.7) if st == "normal" else Color(0.2, 0.12, 0.3, 0.9)
		s.border_color = Color(Hud.BLUE, 0.35) if st == "normal" else Hud.PINK
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		_btn.add_theme_stylebox_override(st, s)
	_btn.pressed.connect(func() -> void: set_open(not is_open()))
	add_child(_btn)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Hud.INK
	sb.border_color = Color(Hud.PINK, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = mod.tr_key("pax_rpg_help")
	title.add_theme_font_override("font", serif)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Hud.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_color_override("font_color", Hud.MUTED)
	close.add_theme_color_override("font_hover_color", Hud.PINK)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	var sep := HSeparator.new()
	box.add_child(sep)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	for line: String in mod.tr_key("pax_rpg_controls").split("\n"):
		for item: String in line.split(" · "):
			var parts := item.split(" — ", true, 1)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			var k := Label.new()
			k.text = parts[0].strip_edges()
			k.custom_minimum_size = Vector2(150, 0)
			k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			k.add_theme_font_override("font", sans)
			k.add_theme_font_size_override("font_size", 16)
			k.add_theme_color_override("font_color", Hud.PINK)
			row.add_child(k)
			var v := Label.new()
			v.text = parts[1].strip_edges() if parts.size() > 1 else ""
			v.custom_minimum_size = Vector2(430, 0)
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_theme_font_override("font", sans)
			v.add_theme_font_size_override("font_size", 16)
			v.add_theme_color_override("font_color", Hud.TEXT)
			row.add_child(v)
			_list.add_child(row)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var s := maxf(size.y, 1.0) / 1080.0
	_btn.visible = false                                 # кнопки-подсказки нет: на её месте — золото (hud.gd); окно — по H
	_btn.position = Vector2(32, 190) * s
	_btn.scale = Vector2(s, s)
	_panel.position = Vector2(32, 236) * s
	_panel.scale = Vector2(s, s)


func over(p: Vector2) -> bool:
	return _btn.get_global_rect().has_point(p)


func is_open() -> bool:
	return _panel.visible


func set_open(on: bool) -> void:
	_panel.visible = on
	toggled.emit(on)
