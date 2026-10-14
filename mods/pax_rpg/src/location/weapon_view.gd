extends Control
## Окно оружия в инвентаре (щелчок по слоту оружия, inventory.gd): в центре — 3D-модель выбранного оружия (своя сцена
## ui/katana3d.gd; тянуть мышью — крутить, сама медленно вращается), слева — урон и масштабирование по характеристикам,
## справа — способности с описанием, внизу по центру — круги со всем оружием: стрелки / щелчок — листать, «Надеть» —
## для оружия этого слота. Данные — config/weapons.json. Макет 1920 × 1080 (масштабирует inventory.gd вместе с собой).

signal equipped(slot: String, id: String)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Katana3D := preload("res://mods/pax_rpg/src/ui/katana3d.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const W := 1920.0
const H := 1080.0
const VIEW := Vector2i(1000, 600)
const RING_Y := 900.0                 # центр кругов выбора, px макета

var mod: PaxMod
var _cfg: Dictionary = {}
var _order: Array = []
var _sel := 0
var _slot := "main"
var _equipped: Dictionary = {}        # слот → id надетого
var _attrs: Dictionary = {}
var _lvl_mult := 1.0
var _stage: Katana3D
var _model_pivot: Node3D
var _yaw := 0.6
var _pitch := 0.25
var _drag := false
var _idle := 0.0
var _info: Control                    # всё, что меняется с выбором (тексты, круги)
var _panel_sh: Shader
var _serif: Font
var _sans: Font
var _cjk: Font
var _models: Dictionary = {}          # id → Node3D (раз загруженная модель)


func setup(m: PaxMod, panel_sh: Shader, serif: Font, sans: Font, cjk: Font) -> void:
	mod = m
	name = "PaxRpgWeaponView"
	_panel_sh = panel_sh
	_serif = serif
	_sans = sans
	_cjk = cjk
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var parsed: Variant = JSON.parse_string(m.read_text("config/weapons.json"))
	_cfg = parsed if parsed is Dictionary else {}
	var o: Variant = _cfg.get("order", [])
	_order = o if o is Array else []
	for id: Variant in _order:
		var w := _w(str(id))
		if not _equipped.has(str(w.get("slot", ""))):
			_equipped[str(w.get("slot", ""))] = str(id)     # по умолчанию надето первое оружие слота
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.07, 0.94)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_stage = Katana3D.new()
	_stage.setup(m, VIEW, 0.8)
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)
	_stage.pivot.visible = false                        # своя модель на своём шарнире
	_model_pivot = Node3D.new()
	_stage.add_child(_model_pivot)
	var tr := TextureRect.new()
	tr.texture = _stage.get_texture()
	tr.position = Vector2((W - VIEW.x) * 0.5, 150)
	tr.size = Vector2(VIEW)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.gui_input.connect(_on_view_input)
	add_child(tr)
	_info = Control.new()
	_info.size = Vector2(W, H)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)


func _w(id: String) -> Dictionary:
	var v: Variant = _cfg.get(id, {})
	return v if v is Dictionary else {}


## Открыть для слота (main / iai): выбрано надетое; attrs — итоговые характеристики, lvl_mult — рост урона от уровня.
func open(slot: String, attrs: Dictionary, lvl_mult: float) -> void:
	_slot = slot
	_attrs = attrs
	_lvl_mult = lvl_mult
	_sel = maxi(0, _order.find(str(_equipped.get(slot, ""))))
	visible = true
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_show()


func close() -> void:
	visible = false
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if not visible:
		return
	_idle += delta
	if not _drag and _idle > 1.5:
		_yaw += delta * 0.35                          # сама медленно вращается, пока не трогают
	_model_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
		_idle = 0.0
	elif e is InputEventMouseMotion and _drag:
		var r := (e as InputEventMouseMotion).relative
		_yaw += r.x * 0.01
		_pitch = clampf(_pitch + r.y * 0.01, -1.3, 1.3)
		_idle = 0.0


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not (e as InputEventKey).pressed:
		return
	var k := (e as InputEventKey).physical_keycode
	if k == KEY_LEFT or k == KEY_A:
		_step(-1)
	elif k == KEY_RIGHT or k == KEY_D:
		_step(1)


func _step(d: int) -> void:
	if _order.is_empty():
		return
	_sel = posmod(_sel + d, _order.size())
	_show()


# ---------- модель ----------

## Модель оружия: целый glb или узел внутри него (меч из модели героя); центр — в нуле, длинная ось — вдоль X,
## длина — 1.25 м кадра (ортокамера видит 0.8 м по высоте).
func _model(id: String) -> Node3D:
	if _models.has(id):
		return _models[id]
	_models[id] = _build_model(id)
	return _models[id]


## Иконка оружия: модель один раз снята на маленькую сцену (клинок по диагонали, свет студии) — картинка для слотов
## инвентаря и кругов выбора. Сцена живёт дальше (её текстура и есть иконка), но больше не рисуется.
var _icons: Dictionary = {}


func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var st := Katana3D.new()
	st.setup(mod, Vector2i(256, 256), 1.0)
	st.pivot.visible = false
	add_child(st)
	var root := _build_model(id)
	var pv := Node3D.new()
	st.add_child(pv)
	pv.add_child(root)
	_fit(root)
	root.scale = Vector3.ONE * 0.75
	pv.rotation = Vector3(0.35, 0.25, deg_to_rad(40.0))   # остриём вверх-вправо, чуть к зрителю
	st.render_target_update_mode = SubViewport.UPDATE_ONCE
	_icons[id] = st.get_texture()
	return _icons[id]


func _build_model(id: String) -> Node3D:
	var w := _w(id)
	var root := Node3D.new()
	var m := Assets.model(mod, str(w.get("model", "")))
	var node := str(w.get("node", ""))
	var src: Node3D = m
	if m != null and node != "":
		src = m.find_child(node, true, false) as Node3D
	if src != null:
		var piece := src.duplicate() as Node3D
		piece.transform = Transform3D.IDENTITY
		root.add_child(piece)
		for mi: Node in piece.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).skeleton = NodePath("")      # вне героя — без скелета, в позе модели
	if m != null:
		m.free()
	return root


func _fit(root: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null:
			continue
		var rel := Transform3D.IDENTITY                 # до корня по родителям: окно может быть ещё вне дерева
		var n: Node = g
		while n != root and n is Node3D:
			rel = (n as Node3D).transform * rel
			n = n.get_parent()
		var b := rel * g.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var piece := root.get_child(0) as Node3D
	var s := box.size
	var axis := 0 if s.x >= s.y and s.x >= s.z else (1 if s.y >= s.z else 2)
	var rot := Basis.IDENTITY
	if axis == 1:
		rot = Basis(Vector3.BACK, -PI * 0.5)           # вертикальный меч — лечь вдоль X
	elif axis == 2:
		rot = Basis(Vector3.UP, PI * 0.5)
	var k := 1.25 / maxf(s[axis], 0.001)
	var basis := rot.scaled(Vector3.ONE * k)
	piece.transform = Transform3D(basis, -(basis * box.get_center()))


func _show_model(id: String) -> void:
	for c: Node in _model_pivot.get_children():
		_model_pivot.remove_child(c)
	var root := _model(id)
	_model_pivot.add_child(root)
	if not root.has_meta(&"fitted"):
		_fit(root)
		root.set_meta(&"fitted", true)


# ---------- тексты и круги ----------

func _panel(r: Rect2, selected := false, empty := false) -> ColorRect:
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
	_info.add_child(c)
	return c


func _label(text: String, pos: Vector2, font: Font, fs: int, color: Color, width := 0.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Hud.SHADOW)
	l.add_theme_constant_override("outline_size", 4)
	if width > 0.0:
		l.size = Vector2(width, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(l)
	return l


func _button(text: String, r: Rect2, cb: Callable, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _serif)
	b.add_theme_font_size_override("font_size", int(r.size.y * 0.5))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.15, 0.95)
	sb.border_color = Hud.GOLD
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.border_color = accent
	sh.bg_color = Color(0.18, 0.1, 0.2, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.pressed.connect(cb)
	_info.add_child(b)
	return b


func _show() -> void:
	for c: Node in _info.get_children():
		c.queue_free()
	if _order.is_empty():
		return
	var id := str(_order[_sel])
	var w := _w(id)
	_show_model(id)
	var t := _label(_wname(w), Vector2(0, 64), _serif, 52, Hud.TEXT, W, HORIZONTAL_ALIGNMENT_CENTER)
	t.size.x = W
	var slot := str(w.get("slot", ""))
	_label(_tr("pax_rpg_wslot_" + slot).to_upper(), Vector2(0, 128), _sans, 14, Hud.PINK, W, HORIZONTAL_ALIGNMENT_CENTER)
	# слева: урон и масштабирование
	_panel(Rect2(90, 200, 380, 430))
	_label(_tr("pax_rpg_inv_damage").to_upper(), Vector2(116, 220), _sans, 13, Hud.DIM)
	var sc: Dictionary = w.get("scaling", {}) as Dictionary
	var mult := Progress.scaling_mult(sc, _attrs)
	var base := float(w.get("damage", 0))
	_label("%d" % roundi(base * mult * _lvl_mult), Vector2(116, 244), _serif, 64, Hud.AMBER)
	_label("%s %d · ×%.2f" % [_tr("pax_rpg_wbase"), roundi(base), mult * _lvl_mult], Vector2(116, 326), _sans, 16, Hud.MUTED)
	_label(_tr("pax_rpg_wscaling").to_upper(), Vector2(116, 380), _sans, 13, Hud.DIM)
	var y := 406.0
	for k: Variant in sc:
		var grade := str(sc[k]).to_upper()
		var g := _label(grade, Vector2(116, y - 6), _serif, 40, Hud.AMBER if grade in ["S", "A"] else Hud.BLUE, 44.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		g.size.x = 44.0
		_label(_tr("pax_rpg_attr_" + str(k)), Vector2(176, y), _sans, 20, Hud.TEXT)
		_label("%d" % int(_attrs.get(k, 0)), Vector2(360, y), _sans, 20, Hud.MUTED, 80.0, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 56.0
	# справа: способности
	_panel(Rect2(W - 470, 200, 380, 430))
	_label(_tr("pax_rpg_wskills").to_upper(), Vector2(W - 444, 220), _sans, 13, Hud.DIM)
	y = 252.0
	for sk: Variant in w.get("skills", []):
		var pair: Array = sk if sk is Array else []
		if pair.size() < 2:
			continue
		_label("◆ " + _tr(str(pair[0])), Vector2(W - 444, y), _serif, 26, Hud.PINK)
		var d := _label(_tr(str(pair[1])), Vector2(W - 444, y + 36), _sans, 15, Hud.MUTED, 330.0)
		y += 58.0 + 22.0 * ceilf(d.text.length() / 34.0)
	# внизу: круги выбора
	var n := _order.size()
	var gap := 130.0
	var x0 := W * 0.5 - gap * (n - 1) * 0.5
	for i: int in n:
		var wi := _w(str(_order[i]))
		var on := i == _sel
		var r := 52.0 if on else 40.0
		var c := Vector2(x0 + gap * i, RING_Y)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = c - Vector2(r, r)
		b.size = Vector2(r, r) * 2.0
		b.tooltip_text = _wname(wi)
		var idx := i
		b.pressed.connect(func() -> void:
			_sel = idx
			_show())
		_info.add_child(b)
		var disc := _Disc.new()
		disc.r = r
		disc.on = on
		disc.worn = str(_equipped.get(str(wi.get("slot", "")), "")) == str(_order[i])
		disc.glyph = str(wi.get("glyph", "?"))
		disc.tex = icon(str(_order[i]))
		disc.font = _cjk
		disc.size = b.size
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(disc)
	_button("‹", Rect2(x0 - 130, RING_Y - 30, 60, 60), _step.bind(-1), Hud.PINK)
	_button("›", Rect2(x0 + gap * (n - 1) + 70, RING_Y - 30, 60, 60), _step.bind(1), Hud.PINK)
	# надеть / закрыть
	var worn := str(_equipped.get(slot, "")) == id
	if slot == _slot:
		var put := func() -> void:
			_equipped[slot] = id
			equipped.emit(slot, id)
			_show()
		var eb := _button(_tr("pax_rpg_wworn") if worn else _tr("pax_rpg_wequip"), Rect2(W * 0.5 - 140, 980, 280, 56),
			put, Hud.PINK)
		eb.disabled = worn
	else:
		_label(_tr("pax_rpg_wother_slot") % _tr("pax_rpg_wslot_" + slot), Vector2(0, 994), _sans, 16, Hud.DIM, W,
			HORIZONTAL_ALIGNMENT_CENTER)
	_button("✕", Rect2(W - 120, 50, 56, 56), close, Hud.PINK)


## Название оружия; пусто — подпись появится позже (пока без текста, не ключ перевода).
func _wname(w: Dictionary) -> String:
	var k := str(w.get("name", ""))
	return _tr(k) if k != "" else ""


func _tr(k: String) -> String:
	return mod.tr_key(k)


## Круг выбора: лаковый диск, золотой ободок (у выбранного — толще, с розовым свечением), знак оружия;
## надетое — маленький ромб снизу.
class _Disc extends Control:
	var r := 40.0
	var on := false
	var worn := false
	var glyph := ""
	var tex: Texture2D                       # иконка оружия (вместо знака)
	var font: Font

	func _draw() -> void:
		var c := Vector2(r, r)
		if on:
			draw_circle(c, r, Color(1.0, 0.55, 0.78, 0.18))
		draw_circle(c, r - 4.0, Color(0.06, 0.07, 0.16))
		draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(0.32, 0.22, 0.12), 6.0, true)
		draw_arc(c, r - 1.5, 0.0, TAU, 64, Color(0.88, 0.68, 0.32), 2.5 if on else 1.5, true)
		if tex != null:
			var s2 := (r - 6.0) * 1.6
			draw_texture_rect(tex, Rect2(c - Vector2(s2, s2) * 0.5, Vector2(s2, s2)), false,
				Color(1, 1, 1) if on else Color(0.75, 0.75, 0.8))
		elif font != null:
			var fs := int(r * 0.9)
			draw_string(font, Vector2(0, c.y + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs,
				Color(1, 0.9, 0.95) if on else Color(0.7, 0.68, 0.8))
		if worn:
			var d := c + Vector2(0, r - 2.0)
			draw_colored_polygon(PackedVector2Array([d + Vector2(0, -6), d + Vector2(6, 0), d + Vector2(0, 6),
				d + Vector2(-6, 0)]), Color(1.0, 0.71, 0.28))
