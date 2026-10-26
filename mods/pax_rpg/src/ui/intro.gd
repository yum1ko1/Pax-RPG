extends CanvasLayer
## Вступительный ролик «Битва при Расколе» перед новым главным меню: video/intro.ogv — всё до кадра меню, кинорамка
## вшита, зерна нет (его кладёт шейдер — так видео сжимается без блоков). Субтитры, имена и карточку «Юрума»
## рисуем сами, на языке игры, как в ролике: строка — Cormorant курсивом в нижней полосе рамки, имя — капителью
## над ней. Esc, пробел, Enter или щелчок — пропустить. Кончился или пропущен — сигнал done: меню появляется на
## бочке из саундтрека. Монтаж и тайминги — pax_rpg/dev/intro_cut (edl.py, overlays.py).

signal done

const SRC := Vector2(1920.0, 1080.0)            # кадр ролика
const BAR := 138.0                              # нижняя полоса кинорамки
const SUBS := [                                 # кто, с, по, ключ перевода
	["selune", 19.00, 21.30, "pax_rpg_intro_1"],
	["iru", 22.00, 24.30, "pax_rpg_intro_2"],
	["iru", 26.60, 28.00, "pax_rpg_intro_3"],
	["iru", 31.25, 33.60, "pax_rpg_intro_4"],
	["selune", 33.70, 36.20, "pax_rpg_intro_5"],
	["selune", 36.35, 37.69, "pax_rpg_intro_6"],
	["both", 51.50, 54.30, "pax_rpg_intro_7"],
	["both", 56.30, 57.45, "pax_rpg_intro_8"],
]
const NAME_COL := {"iru": Color(0.87, 0.75, 1.0), "selune": Color(0.96, 0.54, 0.56)}
const TEXT_COL := {"iru": Color(1.0, 0.94, 0.97), "selune": Color(0.93, 0.93, 0.95), "both": Color(0.95, 0.93, 0.89)}
const CARD := Vector2(1.0, 5.5)                 # карточка «Юрума»: с, по (проявление 0,83 с, уход 1 с)

var mod: PaxMod
var _root: Control
var _player: VideoStreamPlayer
var _name: Label
var _line: Label
var _card: Control
var _card_big: Label
var _card_rule: ColorRect
var _card_small: Label
var _card_shade: TextureRect
var _hint: Label
var _sc: Font
var _it: Font
var _s := -1.0                                  # масштаб кадра на экране (раскладка пересчитывается при смене)
var _cur := -1
var _t := 0.0
var _ending := false
var _held := true                               # клавишу пропуска держали ещё до ролика — ждём, пока отпустят
const SKIP_KEYS: Array[Key] = [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]


## Есть ли файл ролика (без чтения 46 МБ).
static func available(m: PaxMod) -> bool:
	return m.list_files("video").has("intro.ogv")


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgIntro"
	layer = 70
	_sc = _font("fonts/cormorant_sc.ttf", 0.25)
	_it = _font("fonts/cormorant_garamond_italic.ttf", 0.2)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP       # меню под роликом не нажимается
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	_player = VideoStreamPlayer.new()
	var vs := VideoStreamTheora.new()
	vs.file = mod.path("video/intro.ogv")
	_player.stream = vs
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.material = grain_material(0.06)
	_player.finished.connect(_finish)
	_root.add_child(_player)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_root.add_child(_card)
	_card_shade = TextureRect.new()                       # тёмное пятно под карточкой — читается на облаках
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.02, 0.07, 0.5))
	g.set_color(1, Color(0.04, 0.02, 0.07, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_card_shade.texture = gt
	_card_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_card_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_shade)
	_card_big = _label(_sc, Color(1.0, 0.97, 0.93), mod.tr_key("pax_rpg_intro_card").to_upper())
	_card.add_child(_card_big)
	_card_rule = ColorRect.new()
	_card_rule.color = Color(1.0, 0.9, 0.78, 0.63)
	_card.add_child(_card_rule)
	_card_small = _label(_it, Color(1.0, 0.96, 0.91), mod.tr_key("pax_rpg_intro_card_sub"))
	_card.add_child(_card_small)
	_name = _label(_sc, Color.WHITE, "")
	_root.add_child(_name)
	_line = _label(_it, Color.WHITE, "")
	_root.add_child(_line)
	_hint = _label(_sc, Color(0.86, 0.82, 0.9), mod.tr_key("pax_rpg_intro_skip").to_upper())
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	_root.add_child(_hint)
	ready.connect(_player.play)


func _font(rel: String, bold: float) -> Font:
	var f := FontFile.new()
	f.data = mod.read_bytes(rel)
	var v := FontVariation.new()
	v.base_font = f
	v.variation_embolden = bold
	return v


func _label(f: Font, col: Color, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.06, 0.03, 0.1, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Плёночное зерно поверх видео: в файле его нет — Theora сжимает чистую картинку без блоков.
static func grain_material(amount: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GRAIN
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("amount", amount)
	return m


const GRAIN := """shader_type canvas_item;
uniform float amount = 0.06;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 cell = floor(FRAGCOORD.xy * 0.6);
	float g = h(cell + vec2(floor(TIME * 24.0) * 17.31, 0.0)) - 0.5;
	float w = clamp(1.0 - abs(dot(c.rgb, vec3(0.333)) - 0.5) * 1.2, 0.15, 1.0);   // в средних тонах сильнее
	c.rgb += g * amount * w;
	COLOR = c;
}"""


## Кадр ролика вписан в экран с полями; надписи — в пикселях ролика × масштаб (шрифт растеризуется в своём
## размере, без размытия масштабом).
func _layout(vs: Vector2) -> void:
	var s := minf(vs.x / SRC.x, vs.y / SRC.y)
	if is_equal_approx(s, _s):
		return
	_s = s
	var size := SRC * s
	var o := (vs - size) * 0.5
	_player.position = o
	_player.size = size
	_name.add_theme_font_size_override("font_size", roundi(24.0 * s))
	_name.add_theme_constant_override("outline_size", 0)
	_line.add_theme_font_size_override("font_size", roundi(40.0 * s))
	for l: Label in [_name, _line]:
		l.position = Vector2(o.x, 0.0)
		l.size = Vector2(size.x, 0.0)
	var yb := 0.40 * SRC.y
	_card_shade.position = o + Vector2(SRC.x * 0.5 - 620.0, yb - 150.0) * s
	_card_shade.size = Vector2(1240.0, 480.0) * s
	_card_big.add_theme_font_size_override("font_size", roundi(64.0 * s))
	_card_big.add_theme_constant_override("shadow_outline_size", roundi(18.0 * s))
	var bf := FontVariation.new()
	bf.base_font = _sc
	bf.spacing_glyph = roundi(22.0 * s)
	_card_big.add_theme_font_override("font", bf)
	_card_big.position = o + Vector2(0.0, yb - 14.0 * s)
	_card_big.size = Vector2(size.x, 0.0)
	_card_rule.position = o + Vector2(SRC.x * 0.5 - 120.0, yb + 80.0) * s
	_card_rule.size = Vector2(240.0 * s, maxf(1.0, s))
	_card_small.add_theme_font_size_override("font_size", roundi(40.0 * s))
	_card_small.position = o + Vector2(0.0, yb + 84.0 * s)
	_card_small.size = Vector2(size.x, 0.0)
	_hint.add_theme_font_size_override("font_size", roundi(18.0 * s))
	_hint.position = o + Vector2(SRC.x - 60.0 - 500.0, SRC.y - BAR * 0.5 - 14.0) * s
	_hint.size = Vector2(500.0 * s, 0.0)
	_cur = -1                                            # строку разложить заново


func _process(delta: float) -> void:
	if _ending:
		return
	_t += delta
	var vs := _root.get_viewport_rect().size
	if vs.x <= 0.0:
		return
	_layout(vs)
	var down := false                                    # опрос, а не только событие: Esc игра может забрать раньше
	for k: Key in SKIP_KEYS:
		down = down or Input.is_key_pressed(k) or Input.is_physical_key_pressed(k)
	if down and not _held:
		_finish()
		return
	_held = down
	var t := _player.stream_position if _player.stream_position > 0.0 else _t
	_hint.modulate.a = 0.6 * clampf((t - 0.8) / 0.6, 0.0, 1.0)
	_card.modulate.a = clampf(minf((t - CARD.x) / 0.83, (CARD.y - t) / 1.0), 0.0, 1.0)
	var idx := -1
	for i: int in SUBS.size():
		var sb: Array = SUBS[i]
		if t >= float(sb[1]) and t < float(sb[2]):
			idx = i
	if idx != _cur:
		_cur = idx
		_show_line(idx)
	if idx >= 0:
		var sb: Array = SUBS[idx]
		var a := clampf(minf((t - float(sb[1])) / 0.29, (float(sb[2]) - t) / 0.33), 0.0, 1.0)
		_name.modulate.a = a
		_line.modulate.a = a


## Строка в нижней полосе рамки: имя капителью над ней (у общей финальной реплики имени нет).
func _show_line(idx: int) -> void:
	if idx < 0:
		_name.text = ""
		_line.text = ""
		return
	var sb: Array = SUBS[idx]
	var who := str(sb[0])
	var named := NAME_COL.has(who)
	_name.text = mod.tr_key("pax_rpg_intro_" + who).to_upper() if named else ""
	_name.add_theme_color_override("font_color", NAME_COL.get(who, Color.WHITE) as Color)
	var nf := FontVariation.new()
	nf.base_font = _sc
	nf.spacing_glyph = roundi(6.0 * _s)
	_name.add_theme_font_override("font", nf)
	_line.text = mod.tr_key(str(sb[3]))
	_line.add_theme_color_override("font_color", TEXT_COL.get(who, Color.WHITE) as Color)
	var top := _player.position.y + (SRC.y - BAR) * _s
	var block := (70.0 if named else 42.0) * _s
	var y0 := top + (BAR * _s - block) * 0.5 - 6.0 * _s
	_name.position.y = y0
	_line.position.y = y0 + (20.0 * _s if named else -6.0 * _s)


func _input(e: InputEvent) -> void:
	if _ending:
		return
	var skip := false
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		skip = ke.keycode in SKIP_KEYS or ke.physical_keycode in SKIP_KEYS
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		skip = (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func skip() -> void:
	_finish()


## Конец или пропуск: пропущенный ролик гаснет за четверть секунды (картинка и звук), досмотренный — уже чёрный.
func _finish() -> void:
	if _ending:
		return
	_ending = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_root, "modulate", Color.BLACK, 0.25)
	tw.tween_property(_player, "volume_db", -60.0, 0.25)
	tw.chain().tween_callback(func() -> void:
		_player.stop()
		done.emit()
		queue_free())
