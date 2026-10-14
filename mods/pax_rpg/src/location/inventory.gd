extends Control
## Инвентарь (TAB), макет «Инвентарь A»: живой герой в центре на фоне лунного диска (своя камера видит только слой героя
## — gfx.gd RIM_LAYER; мышью — повернуть), слева оружие (Разрубатель — надет; клинок иая; талисман), справа броня
## 2 × 3 (плащ — надеть / снять щелчком, hero.toggle_slot) и состояние — числа здоровья, концентрации и опыта, которых нет
## на HUD; слева под оружием — характеристики персонажа (config/hero.json → character.attributes) со знаками-иероглифами. Панели — shaders/ui_panel.gdshader (лак, золотая рамка). Мир на паузе, пока открыт (location.gd).

signal closed
signal stat_added(key: String)       # «+» у характеристики — вложить очко (location.gd → progress.add_stat)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const HERO_LAYER := 1 << 19
const W := 1920.0
const H := 1080.0

var mod: PaxMod
var _frame: Control                  # макет 1920 × 1080, масштабируется под экран
var _bg: Control
var _pv: SubViewport
var _cam: Camera3D
var _player: Node3D
var _body: Node3D
var _hero: Object                    # hero.gd (toggle_slot, worn)
var _yaw := 0.0
var _drag := false
var _stats: VBoxContainer
var _attrs: VBoxContainer
var _cape: Button
var _panel_sh: Shader
var _serif: Font
var _sans: Font
var _cjk: Font
var _t := 0.0
var _points := 0                     # свободные очки характеристик
var _main_stat := ""                 # главная характеристика героя — ★ у её строки


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgInventory"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel_sh = m.shader("shaders/ui_panel.gdshader")
	_serif = Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 700)
	_sans = Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	_cjk = Hud._sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "Noto Serif CJK JP", "SimSun"], 700)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.1, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_bg = Control.new()
	_bg.size = Vector2(W, H)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	_frame.add_child(_bg)
	_build_preview()
	_build_tabs()
	_build_left()
	_build_right()
	_build_hints()
	resized.connect(_fit)


func _tr(k: String) -> String:
	return mod.tr_key(k)


func _fit() -> void:
	var s := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(s, s)
	_frame.position = (size - Vector2(W, H) * s) * 0.5


## Открыть: кто герой и что показать (st — те же числа, что у HUD: hp_abs, hp_max, posture, level, xp_abs, xp_need;
## attributes — характеристики персонажа из config/hero.json).
func open(view: SubViewport, player: Node3D, body: Node3D, hero: Object, st: Dictionary) -> void:
	_player = player
	_body = body
	_hero = hero
	_yaw = 0.0
	if is_instance_valid(view):
		_pv.world_3d = view.find_world_3d()             # у локации свой мир (own_world_3d) — world_3d его не отдаёт
	_hero_layer(player)
	_pv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_fill_stats(st)
	_main_stat = str(st.get("main_stat", ""))
	_points = int(st.get("stat_points", 0))
	_fill_attrs(st.get("attributes", {}) as Dictionary)
	_update_cape()
	visible = true
	_fit()


## Вся геометрия героя (тело, меч, плащ, надетое) — на слое HERO_LAYER: камера инвентаря видит только его.
func _hero_layer(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers |= HERO_LAYER


func close() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		if _pv.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_pv.render_target_update_mode = SubViewport.UPDATE_DISABLED   # закрыт — превью героя не рисуется
		return
	_t += delta
	_place_camera()
	_bg.queue_redraw()


# ---------- герой ----------

func _build_preview() -> void:
	_pv = SubViewport.new()
	_pv.size = Vector2i(700, 860)
	_pv.transparent_bg = true
	_pv.msaa_3d = Viewport.MSAA_4X
	_pv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_pv)
	_cam = Camera3D.new()
	_cam.cull_mask = HERO_LAYER                         # только герой, без города вокруг
	_cam.fov = 30.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_cam.environment = env
	_pv.add_child(_cam)
	_cam.current = true
	var hero_rect := TextureRect.new()
	hero_rect.texture = _pv.get_texture()
	hero_rect.position = Vector2(610, 140)
	hero_rect.size = Vector2(700, 860)
	hero_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	hero_rect.gui_input.connect(_on_preview_input)
	_frame.add_child(hero_rect)


func _place_camera() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_body):
		return
	var center := _player.global_position + Vector3(0.0, 0.05, 0.0)
	var fwd := -_body.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var dir := fwd.rotated(Vector3.UP, _yaw + 0.35)      # чуть сбоку — видно и лицо, и меч за спиной
	_cam.global_position = center + dir * 3.9 + Vector3(0.0, 0.25, 0.0)
	_cam.look_at(center, Vector3.UP)


func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
	elif e is InputEventMouseMotion and _drag:
		_yaw -= (e as InputEventMouseMotion).relative.x * 0.01


## Фон: лунный диск за героем, туманные гряды, лепестки сакуры.
func _draw_bg() -> void:
	var c := Vector2(960, 560)
	_bg.draw_circle(c, 300.0, Color(0.12, 0.13, 0.31))
	_bg.draw_circle(c, 286.0, Color(0.16, 0.17, 0.38))
	_bg.draw_arc(c, 300.0, 0.0, TAU, 128, Color(0.86, 0.66, 0.34, 0.35), 2.0, true)
	for k: int in 3:                                    # гряды тумана
		var y := 760.0 + k * 34.0
		var pts := PackedVector2Array()
		for i: int in 33:
			var x := 560.0 + i * 25.0
			pts.append(Vector2(x, y + sin(i * 0.7 + k * 1.3) * 10.0))
		_bg.draw_polyline(pts, Color(0.22, 0.24, 0.45, 0.6 - k * 0.15), 3.0, true)
	_bg.draw_set_transform(Vector2.ZERO)
	var ring := Vector2(960, 960)
	_bg.draw_arc(ring, 170.0, PI, TAU, 64, Color(1.0, 0.55, 0.78, 0.45), 1.5, true)
	for i: int in 14:                                   # лепестки
		var ph := float(i) * 1.7
		var p := Vector2(fmod(200.0 + i * 131.0 + _t * (12.0 + i), W), fmod(80.0 + i * 77.0 + _t * (18.0 + i * 2.0), H))
		_bg.draw_circle(p + Vector2(sin(_t + ph) * 8.0, 0.0), 3.0, Color(1.0, 0.6, 0.8, 0.55))


# ---------- панели и слоты ----------

func _panel(rect: Rect2, parent: Control, selected := false, empty := false) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel_sh != null:
		var m := ShaderMaterial.new()
		m.shader = _panel_sh
		m.set_shader_parameter("px", rect.size)
		m.set_shader_parameter("selected", 1.0 if selected else 0.0)
		m.set_shader_parameter("empty", 1.0 if empty else 0.0)
		r.material = m
	else:
		r.color = Hud.INK
	parent.add_child(r)
	return r


func _label(text: String, pos: Vector2, font: Font, fs: int, color: Color, parent: Control, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, 0.0)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Слот: кнопка с лаковой панелью, знак (иероглиф) слева или сверху, подписи.
func _slot(rect: Rect2, glyph: String, glyph_color: Color, kicker: String, title: String, sub: String, selected: bool,
		empty: bool, vertical := false) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	b.tooltip_text = title
	_frame.add_child(b)
	_panel(Rect2(Vector2.ZERO, rect.size), b, selected, empty)
	if vertical:
		var gl := _label(glyph, Vector2(0, 14), _cjk, 40, glyph_color, b, rect.size.x)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tl := _label(title, Vector2(0, rect.size.y - 40), _sans, 16, Hud.TEXT if not empty else Hud.DIM, b, rect.size.x)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return b
	var gs := rect.size.y - 28.0
	var box := _panel(Rect2(Vector2(14, 14), Vector2(gs, gs)), b, false, empty)
	if glyph != "":
		var g := _label(glyph, Vector2(0, gs * 0.12), _cjk, int(gs * 0.5), glyph_color, box, gs)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var x := 14.0 + gs + 18.0
	if kicker != "":
		_label(kicker, Vector2(x, 16), _sans, 12, Hud.PINK if selected else Hud.DIM, b)
	_label(title, Vector2(x, 32 if kicker != "" else rect.size.y * 0.5 - 16), _serif, 30 if selected else 24,
		Hud.TEXT if not empty else Hud.DIM, b)
	if sub != "":
		_label(sub, Vector2(x, rect.size.y - 34), _sans, 14, Hud.MUTED, b)
	return b


func _build_tabs() -> void:
	_panel(Rect2(0, 0, W, 88), _frame)
	var tabs := ["pax_rpg_inv_equipment", "pax_rpg_inv_bag", "pax_rpg_inv_skills", "pax_rpg_inv_journal", "pax_rpg_inv_map"]
	var x := 960.0 - (tabs.size() * 190.0) * 0.5
	for i: int in tabs.size():
		var l := _label(_tr(str(tabs[i])), Vector2(x + i * 190.0, 24), _serif, 26, Hud.TEXT if i == 0 else Hud.DIM, _frame,
			190.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 0:
			var u := ColorRect.new()
			u.color = Hud.PINK
			u.position = Vector2(x + 45.0, 72)
			u.size = Vector2(100, 2)
			_frame.add_child(u)
	_label("荷", Vector2(60, 16), _cjk, 38, Hud.PINK, _frame)


func _build_left() -> void:
	_label(_tr("pax_rpg_hero_name"), Vector2(90, 130), _serif, 40, Hud.TEXT, _frame)
	_label(_tr("pax_rpg_hero_title").to_upper(), Vector2(92, 182), _sans, 14, Hud.MUTED, _frame)
	_label(_tr("pax_rpg_inv_weapons").to_upper(), Vector2(90, 300), _sans, 13, Hud.DIM, _frame)
	_slot(Rect2(90, 330, 440, 124), "斬", Color(1.0, 0.71, 0.28), _tr("pax_rpg_inv_main"), _tr("pax_rpg_weapon_greatsword"),
		_tr("pax_rpg_inv_greatsword_sub"), true, false)
	_slot(Rect2(90, 474, 440, 96), "居", Hud.PINK, _tr("pax_rpg_inv_iai"), _tr("pax_rpg_inv_katana"), "", false, false)
	_slot(Rect2(90, 590, 440, 96), "", Hud.DIM, "", _tr("pax_rpg_inv_talisman_empty"), "", false, true)
	_panel(Rect2(90, 706, 440, 298), _frame)
	_label(_tr("pax_rpg_inv_stats").to_upper(), Vector2(114, 718), _sans, 13, Hud.DIM, _frame)
	_attrs = VBoxContainer.new()
	_attrs.position = Vector2(110, 744)
	_attrs.size = Vector2(400, 252)
	_attrs.add_theme_constant_override("separation", 6)
	_frame.add_child(_attrs)


func _build_right() -> void:
	_label(_tr("pax_rpg_inv_armor").to_upper(), Vector2(1390, 130), _sans, 13, Hud.DIM, _frame)
	var cells := [["兜", "pax_rpg_inv_helm"], ["鎧", "pax_rpg_inv_body"], ["篭", "pax_rpg_inv_gloves"],
		["脛", "pax_rpg_inv_legs"], ["靴", "pax_rpg_inv_boots"], ["套", "pax_rpg_inv_cape"]]
	for i: int in cells.size():
		var col := i % 2
		var row := i / 2
		var r := Rect2(1390 + col * 226, 158 + row * 146, 210, 130)
		var is_cape := i == 5
		var b := _slot(r, str(cells[i][0]), Hud.PINK if is_cape else Hud.MUTED, "", _tr(str(cells[i][1])), "", false,
			not is_cape, true)
		if is_cape:
			_cape = b
			b.pressed.connect(func() -> void:
				if _hero != null and _hero.has_method("toggle_slot"):
					_hero.call("toggle_slot", "back")
				_update_cape())
	_panel(Rect2(1390, 620, 436, 300), _frame)
	_label(_tr("pax_rpg_inv_status").to_upper(), Vector2(1414, 640), _sans, 13, Hud.DIM, _frame)
	_stats = VBoxContainer.new()
	_stats.position = Vector2(1414, 672)
	_stats.size = Vector2(388, 230)
	_stats.add_theme_constant_override("separation", 10)
	_frame.add_child(_stats)


## Надет ли плащ — рамка слота светится.
func _update_cape() -> void:
	if not is_instance_valid(_cape):
		return
	var on := _hero != null and _hero.has_method("worn") and str(_hero.call("worn", "back")) != ""
	for c: Node in _cape.get_children():
		if c is ColorRect and (c as ColorRect).material is ShaderMaterial:
			((c as ColorRect).material as ShaderMaterial).set_shader_parameter("selected", 1.0 if on else 0.0)
			((c as ColorRect).material as ShaderMaterial).set_shader_parameter("empty", 0.0 if on else 1.0)
			break


func _fill_stats(st: Dictionary) -> void:
	for c: Node in _stats.get_children():
		c.queue_free()
	var rows := [
		["pax_rpg_hero_hp", "%d / %d" % [int(st.get("hp_abs", 0)), int(st.get("hp_max", 0))], Hud.PINK],
		["pax_rpg_hud_posture_label", "%d%%" % int(float(st.get("posture", 0.0)) * 100.0), Hud.AMBER],
		["pax_rpg_hud_level", str(int(st.get("level", 1))), Hud.BLUE],
		["pax_rpg_inv_xp", "%d / %d" % [int(st.get("xp_abs", 0)), int(st.get("xp_need", 0))], Hud.BLUE],
		["pax_rpg_inv_damage", _scaling_text(st), Hud.TEXT],
		["pax_rpg_inv_defense", "—", Hud.TEXT],
	]
	if str(st.get("passive", "")) != "":
		rows.append(["pax_rpg_inv_passive", _tr("pax_rpg_passive_" + str(st.get("passive", ""))), Hud.AMBER])
	for r: Array in rows:
		var hb := HBoxContainer.new()
		var a := Label.new()
		a.text = _tr(str(r[0]))
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.add_theme_font_override("font", _sans)
		a.add_theme_font_size_override("font_size", 18)
		a.add_theme_color_override("font_color", Hud.MUTED)
		hb.add_child(a)
		var v := Label.new()
		v.text = str(r[1])
		v.add_theme_font_override("font", _sans)
		v.add_theme_font_size_override("font_size", 18)
		v.add_theme_color_override("font_color", r[2] as Color)
		hb.add_child(v)
		_stats.add_child(hb)


## Характеристики: знак (иероглиф в лаковой плашке, как у слотов), название, шкала 0–100 и число.
## Цвет знака: 0 — голубой (Hud.BLUE), 1 — розовый (Hud.PINK), 2 — янтарный (Hud.AMBER).
const ATTRS := [["agility", "敏", 0], ["intellect", "智", 0], ["charisma", "魅", 1], ["strength", "力", 2],
	["smithing", "鍛", 2], ["inlay", "嵌", 1], ["luck", "運", 0]]


func _fill_attrs(attrs: Dictionary) -> void:
	for c: Node in _attrs.get_children():
		c.queue_free()
	for a: Array in ATTRS:
		var key := str(a[0])
		var tone := int(a[2])
		var col: Color = Hud.BLUE if tone == 0 else (Hud.PINK if tone == 1 else Hud.AMBER)
		var val: int = int(attrs.get(key, 0))
		var row := Control.new()
		row.custom_minimum_size = Vector2(400, 30)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_attrs.add_child(row)
		var box := _panel(Rect2(0, 0, 30, 30), row)
		var g := _label(str(a[1]), Vector2(0, 2), _cjk, 18, col, box, 30.0)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var main := key == _main_stat
		_label(_tr("pax_rpg_attr_" + key) + ("  ★" if main else ""), Vector2(44, 3), _sans, 18,
			Hud.AMBER if main else Hud.MUTED, row)
		var track := ColorRect.new()
		track.color = Hud.INK2
		track.position = Vector2(220, 13)
		track.size = Vector2(120, 4)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(track)
		var fill := ColorRect.new()
		fill.color = col
		fill.position = track.position
		fill.size = Vector2(120.0 * clampf(float(val) / 100.0, 0.0, 1.0), 4)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(fill)
		var v := _label(str(val), Vector2(350, 3), _sans, 18, Hud.TEXT, row, 50.0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _points > 0:                                      # есть очки — «+» вложить
			var plus := Button.new()
			plus.text = "+"
			plus.position = Vector2(406, 0)
			plus.size = Vector2(30, 30)
			plus.add_theme_color_override("font_color", Hud.AMBER)
			plus.pressed.connect(func() -> void: stat_added.emit(key))
			row.add_child(plus)
	if _points > 0:
		var pl := Label.new()
		pl.text = "◆ %s: %d" % [_tr("pax_rpg_inv_stat_points"), _points]
		pl.add_theme_color_override("font_color", Hud.AMBER)
		pl.add_theme_font_override("font", _sans)
		pl.add_theme_font_size_override("font_size", 16)
		_attrs.add_child(pl)


## «Разрубатель · Сила A · ×1.94» — оружие, буквы масштабирования и итоговый множитель урона.
func _scaling_text(st: Dictionary) -> String:
	var parts: Array[String] = []
	var sc: Dictionary = st.get("scaling", {}) as Dictionary
	for k: Variant in sc:
		parts.append("%s %s" % [_tr("pax_rpg_attr_" + str(k)), str(sc[k])])
	var w := str(st.get("weapon", ""))
	var head := _tr(w) if w != "" else ""
	return "%s · %s · ×%.2f" % [head, ", ".join(parts), float(st.get("dmg_mult", 1.0))]


func _build_hints() -> void:
	_panel(Rect2(0, H - 60, W, 60), _frame)
	var l := _label(_tr("pax_rpg_inv_hint"), Vector2(0, H - 44), _sans, 16, Hud.MUTED, _frame, W)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
