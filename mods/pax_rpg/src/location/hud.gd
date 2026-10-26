extends Control
## HUD локации «Сакура и сталь» (концепт A): ночная лазурь и сакура, иероглифы вместо иконок.
## Слева вверху — герой (портрет, уровень, здоровье, концентрация), сверху — компас, справа — миникарта, задание и
## враг в бою; внизу — эликсир, боевые приёмы, кольцо добивания, опыт и мана. Всё рисуется здесь (_draw) по
## словарю st, который location.gd заполняет каждый кадр. Макет — 1920×1080, на другом экране масштаб по высоте.

const PINK := Color(1.0, 0.55, 0.78)
const BLUE := Color(0.47, 0.84, 1.0)
const INK := Color(0.04, 0.06, 0.14, 0.82)
const INK2 := Color(0.11, 0.11, 0.27, 0.95)
const TEXT := Color(0.96, 0.94, 1.0)
const MUTED := Color(0.78, 0.8, 0.94)
const DIM := Color(0.55, 0.58, 0.77)
const AMBER := Color(1.0, 0.71, 0.28)
const RED := Color(1.0, 0.36, 0.56)
const SHADOW := Color(0.03, 0.03, 0.1, 0.85)
const MAP_R := 118.0                # px макета, радиус миникарты
const MAP_M := 30.0                 # м мира от центра до края миникарты

var mod: PaxMod
# палитра — своя у каждого героя (apply_theme; по умолчанию «Сакура и сталь» — константы выше, их же берут окна)
var c_pink := PINK
var c_blue := BLUE
var c_ink := INK
var c_ink2 := INK2
var c_text := TEXT
var c_muted := MUTED
var c_dim := DIM
var c_amber := AMBER
var c_red := RED
var c_gold := Color(0.88, 0.68, 0.32)
var c_bronze := Color(0.32, 0.22, 0.12)
var c_gold_hi := Color(1.0, 0.88, 0.58)
var c_gold_lo := Color(0.46, 0.31, 0.14)
var c_lac := Color(0.14, 0.15, 0.34)    # цвет лака плашек (плитка _lacquer — серая, красится этим)
var embers := false                     # тлеющие угли над нижней панелью (рыцарь)
var emblem := ""                        # знак за кольцом героя: "knight" — щит и скрещённые мечи
var _embers: CPUParticles2D


## Палитры героев. black_knight — как у референса «Thief»: уголь и копоть, старое золото, багрянец, угли.
const THEMES := {
	"black_knight": {
		"pink": Color(0.78, 0.17, 0.12), "blue": Color(0.86, 0.62, 0.3), "ink": Color(0.06, 0.05, 0.045, 0.86),
		"ink2": Color(0.13, 0.1, 0.08, 0.95), "text": Color(0.95, 0.9, 0.82), "muted": Color(0.76, 0.7, 0.6),
		"dim": Color(0.52, 0.47, 0.4), "amber": Color(1.0, 0.6, 0.22), "red": Color(0.92, 0.22, 0.12),
		"gold": Color(0.8, 0.58, 0.3), "bronze": Color(0.2, 0.15, 0.11), "gold_hi": Color(1.0, 0.82, 0.52),
		"gold_lo": Color(0.38, 0.25, 0.12), "lac": Color(0.16, 0.13, 0.11), "embers": true, "emblem": "knight",
	},
	"tian_long": {
		"pink": Color(0.84, 0.14, 0.18), "blue": Color(0.94, 0.8, 0.55), "ink": Color(0.07, 0.025, 0.03, 0.86),
		"ink2": Color(0.17, 0.05, 0.06, 0.95), "text": Color(0.98, 0.93, 0.86), "muted": Color(0.82, 0.73, 0.64),
		"dim": Color(0.56, 0.45, 0.4), "amber": Color(1.0, 0.8, 0.3), "red": Color(0.92, 0.12, 0.14),
		"gold": Color(0.84, 0.66, 0.4), "bronze": Color(0.22, 0.13, 0.09), "gold_hi": Color(1.0, 0.89, 0.64),
		"gold_lo": Color(0.42, 0.27, 0.14), "lac": Color(0.24, 0.05, 0.07), "embers": false, "emblem": "",
	},
}


func apply_theme(id: String) -> void:
	var t: Dictionary = THEMES.get(id, THEMES["tian_long"])     # своей палитры нет — багрянец и старое золото
	if t.is_empty():
		return
	c_pink = t.pink
	c_blue = t.blue
	c_ink = t.ink
	c_ink2 = t.ink2
	c_text = t.text
	c_muted = t.muted
	c_dim = t.dim
	c_amber = t.amber
	c_red = t.red
	c_gold = t.gold
	c_bronze = t.bronze
	c_gold_hi = t.gold_hi
	c_gold_lo = t.gold_lo
	c_lac = t.lac
	embers = bool(t.embers)
	emblem = str(t.emblem)
	if embers and _embers == null:
		_embers = CPUParticles2D.new()
		_embers.show_behind_parent = true
		_embers.amount = 40
		_embers.lifetime = 3.5
		_embers.preprocess = 3.5
		_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_embers.direction = Vector2(0, -1)
		_embers.spread = 25.0
		_embers.gravity = Vector2(0, -12)
		_embers.initial_velocity_min = 12.0
		_embers.initial_velocity_max = 40.0
		_embers.scale_amount_min = 1.2
		_embers.scale_amount_max = 3.0
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.7, 0.3, 0.0))
		g.add_point(0.15, Color(1.0, 0.55, 0.2, 0.9))
		g.set_color(g.get_point_count() - 1, Color(0.8, 0.15, 0.05, 0.0))
		_embers.color_ramp = g
		add_child(_embers)
		move_child(_embers, 0)
	if is_instance_valid(_deco):
		_deco_key = Vector2.ZERO
		_deco.queue_redraw()
var st: Dictionary = {}             # состояние кадра (location.gd)
var portrait: Texture2D             # портрет врага
var hero_portrait: Texture2D        # портрет героя (textures/hero_portrait.png — pax_rpg/dev/blender/knight/portrait.py)
var serif: Font
var sans: Font
var cjk: Font
var _s := 1.0                       # масштаб макета
var _w := 1920.0                    # ширина экрана в px макета
var _mask: Control                  # круг миникарты: всё, что рисует _map, обрезается по нему
var _map: Control


func setup(m: PaxMod, enemy_portrait: Texture2D) -> void:
	mod = m
	portrait = enemy_portrait
	hero_portrait = m.texture("textures/hero_portrait.png")
	name = "PaxRpgHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	serif = _sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	sans = _sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	cjk = _sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "Noto Serif CJK JP", "SimSun", "MS Gothic"], 700)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED      # лак плашек — плиткой (_lacquer)
	_deco = Control.new()
	_deco.show_behind_parent = true
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_deco.draw.connect(_draw_deco)
	add_child(_deco)
	_mask = Control.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_mask.draw.connect(_draw_mask)
	add_child(_mask)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_mask.add_child(_map)
	_coin = Control.new()                                 # монета дышит каждый кадр — свой маленький слой
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_coin.draw.connect(_draw_coin)
	add_child(_coin)
	_live_setup()                                         # полосы концентрации, панель врага, босс — каждый кадр


static func _sys(names: Array, weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


## Новый кадр: location.gd положил st — перерисовать.
func refresh() -> void:
	_s = maxf(size.y, 1.0) / 1080.0
	_w = size.x / _s
	var side := (MAP_R * 2.0 + 4.0) * _s
	_mask.position = Vector2((_w - 40.0 - MAP_R * 2.0 - 2.0) * _s, 28.0 * _s)
	_mask.size = Vector2(side, side)
	_map.size = _mask.size
	# весь HUD (≈200 команд рисования и текста) — только когда изменилось состояние или размер экрана; раньше —
	# каждый кадр. Дышащая монета — свой слой (_coin), он дёшев и рисуется каждый кадр.
	var sig := st.hash() ^ hash(Vector3(size.x, size.y, _s))
	if sig != _sig:
		_sig = sig
		queue_redraw()
	if is_instance_valid(_coin):
		_coin.queue_redraw()
	_live_tick()
	if _embers != null:
		var cc := _core_c()
		var anchor := Vector2(_w * 0.5, 1080.0)
		var bar_top := (anchor + (Vector2(cc.x, cc.y - 52.0) - anchor) * BOT) * _s
		_embers.position = Vector2(bar_top.x, size.y - 30.0 * _s)
		_embers.emission_rect_extents = Vector2(560.0 * BOT * _s, 20.0 * _s)
	var key := Vector2(_w, _s)
	if key != _deco_key or not visible:
		_deco_key = key
		_deco.queue_redraw()
	# миникарта — сотни многоугольников (каждый — свой вызов отрисовки под маской круга, ~1200 в кадре):
	# перерисовывать, только когда герой сдвинулся / повернулся или прошло 0.1 с (враги на карте)
	var me: Vector2 = _g("me", Vector2.ZERO)
	var yaw := float(_g("yaw", 0.0))
	var now := Time.get_ticks_msec()
	if me.distance_to(_map_me) > 0.4 or absf(angle_difference(yaw, _map_yaw)) > 0.03 or now - _map_t > 100:
		_map_me = me
		_map_yaw = yaw
		_map_t = now
		_mask.queue_redraw()
		_map.queue_redraw()


var _sig := 0                        # отпечаток состояния, с которым HUD нарисован последний раз
var _coin: Control


func _draw_coin() -> void:
	if st.is_empty():
		return
	_coin.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	coin(_coin, Vector2(70, 70), 30.0, Time.get_ticks_msec() * 0.001, float(_g("gold_flash", 0.0)))


var _map_mesh: ArrayMesh
var _map_n := -1


func _rects_mesh(rects: Array) -> ArrayMesh:
	if rects.is_empty():
		return null
	var v := PackedVector2Array()
	var col := PackedColorArray()
	for rect: Variant in rects:
		var rr: Array = rect
		var p: Vector2 = rr[0]
		var h: Vector2 = (rr[1] as Vector2) * 0.5
		var cc: Color = rr[2]
		for q: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
			v.append(p + q)
			col.append(cc)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


var _map_me := Vector2(INF, INF)
var _map_yaw := 0.0
var _map_t := 0


func _g(k: String, d: Variant = 0.0) -> Variant:
	return st.get(k, d)


func _tr(k: String) -> String:
	return mod.tr_key(k) if mod != null else k


# ---------- рисование ----------

func _draw() -> void:
	if st.is_empty():
		return
	# низ (панель, кольцо героя, эликсир, приёмы) — уменьшен в BOT раз к середине нижнего края
	var anchor := Vector2(_w * 0.5, 1080.0)
	draw_set_transform(anchor * (1.0 - BOT) * _s, 0.0, Vector2(_s * BOT, _s * BOT))
	_txt_k = BOT_TEXT / BOT
	_draw_core()
	_draw_flask()
	_draw_skills()
	_txt_k = 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	_draw_compass()
	_draw_map_frame()
	_draw_quest()
	_draw_enemy()
	_draw_marks()
	_draw_toast()
	_draw_gold()
	_draw_style()
	_draw_hint()
	_draw_orbs()


# ---------- оправа: лак, кованое золото, накладки, камни (как в Diablo / Sekiro — всё рисуется, без файлов) ----------

const BRONZE := Color(0.32, 0.22, 0.12)
const GOLD_HI := Color(1.0, 0.88, 0.58)
const GOLD_LO := Color(0.46, 0.31, 0.14)
static var _lac: ImageTexture
var _ci: CanvasItem = self           # куда рисуют помощники оправы: сам HUD или слой _deco
var _deco: Control                   # неподвижная оправа (плашки, ободки, навершия) — за HUD (show_behind_parent),
                                     # перерисовывается только при смене размера экрана, а не каждый кадр
var _deco_key := Vector2.ZERO


## Плитка лака 256 × 256: тёмная лазурь с зерном и горизонтальными мазками кисти (один раз за сессию).
static func _lacquer() -> ImageTexture:
	if _lac != null:
		return _lac
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = 11
	grain.frequency = 0.09
	var brush := FastNoiseLite.new()
	brush.seed = 5
	brush.frequency = 0.02
	for y: int in n:
		for x: int in n:
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var b := brush.get_noise_2d(x * 0.15, y * 2.2) * 0.5 + 0.5
			var v := 0.75 + g * 0.3 + b * 0.25
			img.set_pixel(x, y, Color(0.45 * v, 0.45 * v, 0.45 * v, 1.0))   # серая: цвет даёт c_lac
	_lac = ImageTexture.create_from_image(img)
	return _lac


## Восьмиугольник со срезанными углами (cut — срез, px).
static func _octa(r: Rect2, cut: float) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	return PackedVector2Array([Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut),
		Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut),
		Vector2(a.x, a.y + cut)])


## Камень в оправе: ромб цвета col с бликом, золотая кайма.
func _gem(c: Vector2, r: float, col: Color) -> void:
	_ci.draw_colored_polygon(_diamond(c, r + 2.5), c_gold_lo)
	_ci.draw_colored_polygon(_diamond(c, r + 1.2), c_gold)
	_ci.draw_colored_polygon(_diamond(c, r), col.darkened(0.45))
	_ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.5, -r * 0.1), c,
		c + Vector2(-r * 0.5, -r * 0.1)]), col.lightened(0.15))
	_ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.45), r * 0.18, Color(1, 1, 1, 0.75))


## Завиток-филигрань: дуга от угла a0 на span с шариком на конце.
func _curl(c: Vector2, r: float, a0: float, span: float, w: float) -> void:
	_ci.draw_arc(c, r, a0, a0 + span, 18, c_gold_lo, w + 1.5, true)
	_ci.draw_arc(c, r, a0, a0 + span, 18, c_gold, w, true)
	var e := c + Vector2(cos(a0 + span), sin(a0 + span)) * r
	_ci.draw_circle(e, w * 1.3, c_gold)
	_ci.draw_circle(e - Vector2(w * 0.3, w * 0.3), w * 0.5, c_gold_hi)


## Плашка: лак плиткой, срезанные углы, тройная кованая рамка (тёмная бронза, золото, тонкая внутренняя линия),
## на углах — накладки с завитками и камнем. gem — цвет камней (прозрачный — золотой ромбик).
func _plate(r: Rect2, cut := 14.0, gem := Color(0, 0, 0, 0), alpha := 0.92) -> void:
	var tex := _lacquer()
	var o := _octa(r, cut)
	var uv := PackedVector2Array()
	for q: Vector2 in o:
		uv.append(q / 256.0)
	_ci.draw_colored_polygon(o, Color(c_lac, alpha), uv, tex)
	var hi := _octa(Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, r.size.y * 0.35)), cut * 0.7)
	_ci.draw_colored_polygon(hi, Color(0.5, 0.6, 1.0, 0.035))     # блик лака сверху
	_outline(o, Color(0.02, 0.015, 0.03, 0.9), 5.0)
	_outline(o, c_bronze, 3.5)
	_outline(o, c_gold, 1.6)
	_outline(_octa(r.grow(-6.0), maxf(cut - 4.0, 2.0)), Color(c_gold, 0.35), 1.0)
	for k: int in 4:                                        # угловые накладки
		var sx := 1.0 if k % 2 == 0 else -1.0
		var sy := 1.0 if k < 2 else -1.0
		var cx := r.position.x if k % 2 == 0 else r.end.x
		var cy := r.position.y if k < 2 else r.end.y
		var cc := Vector2(cx + sx * cut * 0.5, cy + sy * cut * 0.5)
		var base := atan2(sy, sx)
		_curl(cc + Vector2(sx * 10.0, 0), 6.0, base - PI * 0.9, PI * 1.1, 1.4)
		_curl(cc + Vector2(0, sy * 10.0), 6.0, base + PI * 0.9, -PI * 1.1, 1.4)
		if gem.a > 0.0:
			_gem(cc, 4.5, gem)
		else:
			_ci.draw_colored_polygon(_diamond(cc, 4.0), c_gold)


## Кованый ободок круга радиуса r: тёмная бронза, по краям золото, блик сверху, заклёпки.
func _bezel(c: Vector2, r: float, width := 9.0, rivets := 8) -> void:
	_ci.draw_arc(c, r, 0.0, TAU, 128, Color(0.02, 0.015, 0.03, 0.9), width + 4.0, true)
	_ci.draw_arc(c, r, 0.0, TAU, 128, c_bronze, width, true)
	_ci.draw_arc(c, r + width * 0.5 - 1.0, 0.0, TAU, 128, c_gold, 1.6, true)
	_ci.draw_arc(c, r - width * 0.5 + 1.0, 0.0, TAU, 128, c_gold_lo, 1.4, true)
	_ci.draw_arc(c, r, -PI * 0.85, -PI * 0.15, 48, Color(c_gold_hi, 0.35), width * 0.45, true)
	for i: int in rivets:
		var a := TAU * i / rivets - PI * 0.5 + PI / rivets
		var p := c + Vector2(cos(a), sin(a)) * r
		_ci.draw_circle(p, width * 0.32, c_gold_lo)
		_ci.draw_circle(p, width * 0.24, c_gold)
		_ci.draw_circle(p - Vector2(1, 1), width * 0.1, c_gold_hi)


## Навершие над кругом: кованый шпиль с камнем и завитками по бокам (top — точка на ободке, h — высота).
func _crest(top: Vector2, h: float, gem: Color) -> void:
	var w := h * 0.55
	var spire := PackedVector2Array([top + Vector2(0, -h), top + Vector2(w * 0.55, -h * 0.35), top + Vector2(w, 0),
		top + Vector2(w * 0.4, h * 0.18), top + Vector2(0, h * 0.05), top + Vector2(-w * 0.4, h * 0.18), top + Vector2(-w, 0),
		top + Vector2(-w * 0.55, -h * 0.35)])
	_ci.draw_colored_polygon(spire, c_bronze)
	_outline(spire, c_gold, 1.6)
	_ci.draw_line(top + Vector2(0, -h + 3), top + Vector2(0, -h * 0.55), Color(c_gold_hi, 0.7), 1.2, true)
	_curl(top + Vector2(w * 1.25, -h * 0.05), h * 0.28, PI * 0.9, PI * 1.2, 1.6)
	_curl(top + Vector2(-w * 1.25, -h * 0.05), h * 0.28, PI * 0.1, -PI * 1.2, 1.6)
	_gem(top + Vector2(0, -h * 0.33), h * 0.17, gem)


## Нижняя панель под кольцом героя, эликсиром и приёмами: широкая лаковая плашка с кованой рамкой и гравировкой;
## от кольца по верхней кромке расходятся золотые завитки-«крылья».
func _draw_bar() -> void:
	var cc := _core_c()
	var half_w := minf(660.0, _w * 0.5 - 250.0)
	var top := cc.y - 52.0
	var r := Rect2(cc.x - half_w, top, half_w * 2.0, 1080.0 - top - 6.0)
	_plate(r, 22.0, c_blue, 1.0)
	var gy := r.position.y + 14.0
	var gy2 := r.end.y - 12.0
	_ci.draw_line(Vector2(r.position.x + 40, gy), Vector2(r.end.x - 40, gy), Color(c_gold, 0.28), 1.0, true)
	_ci.draw_line(Vector2(r.position.x + 40, gy2), Vector2(r.end.x - 40, gy2), Color(c_gold, 0.28), 1.0, true)
	var x := r.position.x + 56.0
	while x < r.end.x - 40.0:
		if absf(x - cc.x) > 150.0:
			_ci.draw_colored_polygon(_diamond(Vector2(x, gy2), 3.0), Color(c_gold, 0.6))
		x += 56.0
	for sgn: float in [-1.0, 1.0]:                          # крылья от кольца
		for j: int in 3:
			var rr := 30.0 + j * 18.0
			var cen := cc + Vector2(sgn * (140.0 + rr * 0.2), -52.0 + rr)
			var a0 := -PI * 0.5 - sgn * 0.15
			_curl(cen, rr, a0, sgn * (1.1 - j * 0.2), 1.8 - j * 0.35)


## Копоть за нижней панелью: тёмная дымка поднимается от низа экрана (рыцарь — тёплая, с отсветом углей).
func _smoke() -> void:
	if not embers:
		return
	var cc := _core_c()
	for k: int in 6:
		var r := 260.0 + k * 90.0
		_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_deco.draw_set_transform((Vector2(_w * 0.5, 1080.0) * (1.0 - BOT) + Vector2(cc.x, 1080.0) * BOT) * _s, 0.0,
			Vector2(_s * BOT * 2.2, _s * BOT * 0.6))
		_ci.draw_circle(Vector2.ZERO, r, Color(0.02, 0.015, 0.01, 0.12))
	_deco.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	for k: int in 4:                                         # отсвет углей у самого низа
		_ci.draw_rect(Rect2(0, 1080.0 - 18.0 * (k + 1), _w, 18.0), Color(0.55, 0.16, 0.05, 0.05))
	var anchor := Vector2(_w * 0.5, 1080.0)
	_deco.draw_set_transform(anchor * (1.0 - BOT) * _s, 0.0, Vector2(_s * BOT, _s * BOT))


## Герб рыцаря за кольцом: скрещённые мечи — клинки и рукояти выходят из-за кольца.
func _knight_emblem(c: Vector2) -> void:
	for sgn: float in [-1.0, 1.0]:                           # мечи крест-накрест
		var dir := Vector2(sgn * 0.62, -0.78).normalized()
		var tip := c + dir * 250.0
		var pom := c - dir * 210.0
		var side := Vector2(-dir.y, dir.x)
		_ci.draw_colored_polygon(PackedVector2Array([tip, c + dir * 40.0 + side * 9.0, pom + side * 5.0, pom - side * 5.0,
			c + dir * 40.0 - side * 9.0]), Color(0.32, 0.3, 0.3))
		_ci.draw_line(tip, pom, Color(0.75, 0.72, 0.68, 0.7), 1.5, true)          # дол клинка
		var guard := c - dir * 150.0
		_ci.draw_line(guard + side * 34.0, guard - side * 34.0, c_gold, 7.0, true)  # гарда
		_ci.draw_circle(pom - dir * 6.0, 9.0, c_gold)                              # навершие


## Неподвижная оправа HUD — в слой _deco (рисуется за HUD, только при смене размера экрана).
func _draw_deco() -> void:
	if size.y <= 0.0:
		return
	_ci = _deco
	var anchor := Vector2(_w * 0.5, 1080.0)
	_deco.draw_set_transform(anchor * (1.0 - BOT) * _s, 0.0, Vector2(_s * BOT, _s * BOT))
	if emblem == "knight":
		_knight_emblem(_core_c())                         # под панелью: видны только клинки над ней
	_draw_bar()
	var c := _core_c()
	var disc := PackedVector2Array()
	var duv := PackedVector2Array()
	for i: int in 96:
		var q := c + Vector2(cos(TAU * i / 96.0), sin(TAU * i / 96.0)) * 134.0
		disc.append(q)
		duv.append(q / 256.0)
	_ci.draw_colored_polygon(disc, Color(c_lac, 1.0), duv, _lacquer())
	# оправа: кованый ободок с заклёпками, навершие с камнем сверху, засечки как на гарде
	_bezel(c, 139.0, 11.0, 12)
	_crest(c + Vector2(0, -146.0), 34.0, c_pink)
	_ci.draw_arc(c, 127.0, 0.0, TAU, 128, Color(c_gold, 0.3), 1.0, true)
	for i: int in 24:
		var a := TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		var long := i % 6 == 0
		_ci.draw_line(c + d * (132.0 if not long else 136.0), c + d * (127.0 if not long else 124.0), Color(c_gold, 0.8 if long else 0.45),
			2.0 if long else 1.0, true)
	_plate(Rect2(_core_c().x - 600.0, 1080.0 - CORE_UP - 46.0, 80, 92), 12.0, c_pink)          # эликсир
	_deco.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	var cx := _w * 0.5
	_plate(Rect2(cx - 330.0, 18.0, 660.0, 52.0), 16.0, Color(0, 0, 0, 0), 0.97)            # компас
	for sgn: float in [-1.0, 1.0]:
		_gem(Vector2(cx + sgn * 342.0, 44.0), 7.0, c_pink)
	var mc := Vector2(_w - 40.0 - MAP_R, 30.0 + MAP_R)                                     # миникарта
	_bezel(mc, MAP_R + 7.0, 12.0, 8)
	for i: int in 32:
		var a := TAU * i / 32.0
		var d := Vector2(cos(a), sin(a))
		_deco.draw_line(mc + d * (MAP_R + 14.0), mc + d * (MAP_R + (19.0 if i % 4 == 0 else 16.0)), Color(c_gold, 0.7), 1.0, true)
	_crest(mc + Vector2(0, -MAP_R - 15.0), 26.0, c_blue)
	_plate(Rect2(mc.x - 120.0, mc.y + MAP_R + 14.0, 240.0, 56.0), 12.0, c_pink, 0.97)
	var rx := _w - 40.0                                                                     # задание
	_plate(Rect2(rx - 336.0, 350.0, 344.0, 126.0), 14.0, Color(0, 0, 0, 0), 0.97)
	_deco.draw_line(Vector2(rx - 300, 380.0), Vector2(rx - 8, 380.0), Color(c_gold, 0.45), 1.0, true)
	_deco.draw_set_transform(anchor * (1.0 - BOT) * _s, 0.0, Vector2(_s * BOT, _s * BOT))
	var uc := _ult_c()                                                                      # кольцо добивания
	_deco.draw_circle(uc, 68.0, Color(c_ink, 0.9))
	_bezel(uc, 72.0, 9.0, 6)
	_crest(uc + Vector2(0, -79.0), 22.0, c_pink)
	_ci = self


var _txt_k := 1.0                    # множитель кегля (в нижнем блоке — BOT_TEXT / BOT)


## Текст; width > 0 — строка ужимается кеглем, пока не влезет в ширину (ничего не вылезает за рамки).
func _text(pos: Vector2, s: String, font: Font, fs: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, outline := 4) -> void:
	fs = maxi(8, roundi(fs * _txt_k))
	outline = roundi(outline * _txt_k)
	if width > 0.0:
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > width:
			fs = maxi(8, int(fs * width / tw))
	if outline > 0:
		_ci.draw_string_outline(font, pos, s, align, width, fs, outline, Color(SHADOW, SHADOW.a * color.a))
	_ci.draw_string(font, pos, s, align, width, fs, color)


## Текст по центру точки (по ширине и примерно по высоте).
func _center(c: Vector2, s: String, font: Font, fs: int, color: Color, outline := 0, maxw := 400.0) -> void:
	_text(Vector2(c.x - maxw * 0.5, c.y + fs * _txt_k * 0.36), s, font, fs, color, HORIZONTAL_ALIGNMENT_CENTER, maxw, outline)


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	_ci.draw_polyline(loop, color, width, true)


## Полоса-параллелограмм (наклон как у мазка кисти).
func _skew_bar(x: float, y: float, w: float, h: float, frac: float, color: Color) -> void:
	var k := h * 0.35
	var f := clampf(frac, 0.0, 1.0) * w
	draw_colored_polygon(PackedVector2Array([Vector2(x + k, y), Vector2(x + k + f, y), Vector2(x + f, y + h),
		Vector2(x, y + h)]), color)


## Герой по центру снизу (макет «HUD A»): портрет в круге, вокруг — толстое кольцо здоровья (270°, разрыв внизу —
## там числа), снаружи — тонкое кольцо концентрации (растёт от левого края разрыва; ближе к пределу — краснее).
## Слева от кольца — эликсир и навыки ЛКМ / ПКМ / Alt, справа — Q / T / V (_draw_skills). Опыт — полоса по низу.
const BOT := 0.6                     # масштаб нижнего блока HUD (не занимает пол-экрана)
const BOT_TEXT := 0.82               # текст нижнего блока — во столько от исходного (не мельчит вместе с рамками)
const CORE_UP := 150.0               # px макета от низа экрана до центра кольца
const ARC0 := PI * 0.75              # начало дуг — левый край разрыва внизу
const ARC_LEN := PI * 1.5            # 270°


func _core_c() -> Vector2:
	return Vector2(_w * 0.5, 1080.0 - CORE_UP)


func _draw_core() -> void:
	var c := _core_c()
	# концентрация: внешнее тонкое кольцо
	draw_arc(c, 119.0, ARC0, ARC0 + ARC_LEN, 96, Color(c_gold, 0.35), 2.0, true)   # концентрация — полосой над кольцом
	# здоровье: толстое кольцо; светлый «след» недавней потери, поверх — текущее
	draw_arc(c, 98.0, ARC0, ARC0 + ARC_LEN, 96, c_ink2, 17.0, true)
	var ghost := clampf(float(_g("hp_ghost", 1.0)), 0.0, 1.0)
	var hp := clampf(float(_g("hp", 1.0)), 0.0, 1.0)
	if ghost > 0.003:
		draw_arc(c, 98.0, ARC0, ARC0 + ARC_LEN * ghost, 96, Color(1.0, 0.9, 0.96, 0.55), 17.0, true)
	if hp > 0.003:
		draw_arc(c, 98.0, ARC0, ARC0 + ARC_LEN * hp, 96, c_pink if hp > 0.3 else c_red, 17.0, true)
	# портрет
	draw_circle(c, 80.0, c_bronze)
	draw_circle(c, 76.0, c_ink2)
	if hero_portrait != null:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i: int in 48:
			var a := TAU * i / 48.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * 74.0)
			uvs.append(Vector2(0.5, 0.5) + d * 0.5)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, hero_portrait)
	else:
		_center(c, "騎", cjk, 60, c_text)
	draw_arc(c, 79.0, 0.0, TAU, 72, c_gold, 2.0, true)
	draw_arc(c, 75.0, 0.0, TAU, 72, Color(c_blue, 0.7), 1.2, true)
	draw_arc(c, 70.0, PI * 1.1, PI * 1.9, 32, Color(1, 1, 1, 0.12), 6.0, true)   # стеклянный блик на портрете
	# в разрыве колец под портретом: уровень, под ним — полоска опыта (числа — в инвентаре)
	var lv := c + Vector2(0, 82)                         # крупный ромб уровня — заходит на низ аватарки
	var dm := _diamond(lv, 25.0)
	draw_colored_polygon(_diamond(lv, 31.0), c_bronze)
	_outline(_diamond(lv, 31.0), c_gold, 2.2)
	draw_colored_polygon(dm, Color(c_ink, 1.0))
	_outline(dm, c_blue, 2.0)
	_center(lv, str(int(_g("level", 1))), serif, 26, c_blue, 3)
	var fl := float(_g("lvl_flash", 0.0))
	if fl > 0.0:                                         # новый уровень: свет вокруг кольца
		var k := clampf(fl / 1.6, 0.0, 1.0)
		for j: int in 4:
			draw_arc(c, 126.0 + (1.0 - k) * 50.0 + j * 6.0, 0.0, TAU, 96, Color(c_pink, 0.14 * k), 3.0, true)
	_draw_xp_line()


## Опыт — короткая полоска под ромбом уровня (в разрыве колец); сюда летит мана повергнутых (xp_target).
func _xp_rect() -> Rect2:
	var c := _core_c()
	return Rect2(c.x - 54.0, c.y + 121.0, 108.0, 4.0)


func _draw_xp_line() -> void:
	var r := _xp_rect()
	draw_rect(r, c_ink2)
	var xp := clampf(float(_g("xp", 0.0)), 0.0, 1.0)
	if xp > 0.002:
		var f := r.size.x * xp
		draw_polygon(PackedVector2Array([r.position, r.position + Vector2(f, 0), r.position + Vector2(f, r.size.y),
			r.position + Vector2(0, r.size.y)]), PackedColorArray([c_blue, c_pink, c_pink, c_blue]))
		draw_circle(r.position + Vector2(f, r.size.y * 0.5), 3.0, Color(1, 0.9, 0.97, 0.9))
	draw_rect(r, Color(c_text, 0.25), false, 1.0)
	if int(_g("skill_points", 0)) > 0:                    # очки умений есть — ромбик у полоски
		draw_colored_polygon(_diamond(r.position + Vector2(r.size.x + 10.0, 2.0), 4.0), c_amber)


func _draw_player() -> void:
	var c := Vector2(98, 92)
	draw_circle(c, 66.0, Color(c_pink, 0.10))
	draw_circle(c, 58.0, c_ink2)
	if hero_portrait != null:                            # портрет в круге (многоугольник с UV)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i: int in 48:
			var a := TAU * i / 48.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * 56.0)
			uvs.append(Vector2(0.5, 0.5) + d * 0.5)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, hero_portrait)
	else:
		_center(c, "騎", cjk, 52, c_text)
	draw_arc(c, 58.0, 0.0, TAU, 64, c_pink, 2.0, true)
	var d := _diamond(Vector2(140, 136), 22.0)
	draw_colored_polygon(d, Color(c_ink, 1.0))
	_outline(d, c_blue, 2.0)
	_center(Vector2(140, 136), str(int(_g("level", 1))), sans, 16, c_blue)
	var name_s := _tr("pax_rpg_hero_name")
	_text(Vector2(178, 66), name_s, serif, 32, c_text)
	var nw := serif.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_text(Vector2(178 + nw + 14, 64), _tr("pax_rpg_hero_title").to_upper(), sans, 13, c_muted)
	# здоровье: розовый «след» недавней потери, поверх — голубое текущее
	_skew_bar(176, 84, 440, 16, 1.0, c_ink)
	_skew_bar(176, 84, 440, 16, float(_g("hp_ghost", 1.0)), c_pink)
	_skew_bar(176, 84, 440, 16, float(_g("hp", 1.0)), c_blue)
	_text(Vector2(178, 122), "%s  %d / %d" % [_tr("pax_rpg_hero_hp"), int(_g("hp_abs", 100)),
		int(_g("hp_max", 100))], sans, 13, c_text)
	# концентрация — от середины к краям, как в Sekiro; ближе к пределу — краснее
	var p := float(_g("conc", 1.0))
	draw_rect(Rect2(178, 132, 440, 8), c_ink)
	draw_rect(Rect2(178, 132, 440, 8), Color(c_text, 0.25), false, 1.0)
	if p > 0.005:
		draw_rect(Rect2(398 - 220 * p, 132, 440 * p, 8), c_amber)
	draw_rect(Rect2(397, 128, 2, 16), c_text)
	# опыт: сюда перетекает мана повергнутых врагов
	var xp := float(_g("xp", 0.0))
	draw_rect(Rect2(XP_BAR.position, XP_BAR.size), c_ink)
	if xp > 0.002:
		var f := XP_BAR.size.x * xp
		draw_polygon(PackedVector2Array([XP_BAR.position, XP_BAR.position + Vector2(f, 0), XP_BAR.position + Vector2(f, XP_BAR.size.y),
			XP_BAR.position + Vector2(0, XP_BAR.size.y)]), PackedColorArray([c_blue, c_pink, c_pink, c_blue]))
		draw_circle(XP_BAR.position + Vector2(f, XP_BAR.size.y * 0.5), 4.0, Color(1, 0.9, 0.97, 0.9))
	draw_rect(Rect2(XP_BAR.position, XP_BAR.size), Color(c_text, 0.22), false, 1.0)
	_text(XP_BAR.position + Vector2(0, 22), "%s %d · %d / %d" % [_tr("pax_rpg_hud_level"), int(_g("level", 1)),
		int(_g("xp_abs", 0)), int(_g("xp_need", 100))], sans, 13, c_muted, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var sp := int(_g("skill_points", 0))
	if sp > 0:
		var at := XP_BAR.position + Vector2(XP_BAR.size.x - 150, 22)
		_text(at, "◆ %s: %d" % [_tr("pax_rpg_hud_skill_points"), sp], sans, 13, c_amber, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var fl := float(_g("lvl_flash", 0.0))
	if fl > 0.0:                                         # новый уровень: свет вокруг ромба уровня
		var a := clampf(fl / 1.6, 0.0, 1.0)
		for k: int in 4:
			draw_circle(Vector2(140, 136), 22.0 + (1.0 - a) * 60.0 + k * 6.0, Color(c_pink, 0.12 * a))
		draw_rect(Rect2(XP_BAR.position - Vector2(4, 4), XP_BAR.size + Vector2(8, 8)), Color(c_pink, 0.35 * a), false, 2.0)


const XP_BAR := Rect2(178, 152, 440, 6)              # px макета


## Куда летит мана (экранные px): конец заполненной части полоски опыта (по низу экрана).
func xp_target(frac: float) -> Vector2:
	var r := _xp_rect()
	var p := r.position + Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y * 0.5)
	var anchor := Vector2(_w * 0.5, 1080.0)
	return (anchor + (p - anchor) * BOT) * _s                 # полоска — в уменьшенном нижнем блоке


func _draw_orbs() -> void:
	for o: Variant in _g("orbs", []):
		var trail: Array = (o as Array)[2]
		var k := float((o as Array)[1])
		for j: int in trail.size():                       # шлейф
			var tp: Vector2 = trail[j] / _s
			var ta := float(j + 1) / (trail.size() + 1)
			draw_circle(tp, lerpf(3.0, 9.0, ta) * (1.2 - k * 0.5), Color(1.0, 0.35, 0.72, 0.25 * ta))
		var pos: Vector2 = (o as Array)[0] / _s
		var r := lerpf(13.0, 6.0, k)
		draw_circle(pos, r * 2.4, Color(1.0, 0.3, 0.7, 0.16))
		draw_circle(pos, r * 1.15, Color(0.25, 0.04, 0.2, 0.55))
		draw_circle(pos, r, Color(1.0, 0.36, 0.74))
		draw_circle(pos, r * 0.45, Color(1, 0.95, 0.98))


func _draw_compass() -> void:
	var cx := _w * 0.5
	var yaw := float(_g("yaw", 0.0))
	var line_y := 52.0
	for i: int in 24:
		var a := float(i) / 24.0
		draw_rect(Rect2(cx - 300 + 600 * a, line_y, 600.0 / 24.0, 1), Color(c_text, 0.7 * sin(a * PI)))
	var marks := [["С", 0.0], ["СЗ", 45.0], ["З", 90.0], ["ЮЗ", 135.0], ["Ю", 180.0], ["ЮВ", -135.0], ["В", -90.0],
		["СВ", -45.0]]
	for m: Array in marks:
		var rel := wrapf(deg_to_rad(float(m[1])) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5:
			continue
		var x := cx - rel / (PI * 0.5) * 300.0
		var al := 1.0 - absf(rel) / (PI * 0.5)
		if str(m[0]) == "С":
			_center(Vector2(x, 38), "北", cjk, 18, Color(c_pink, al), 3)
		else:
			_center(Vector2(x, 38), str(m[0]), sans, 15, Color(c_muted if str(m[0]).length() == 2 else c_text, al), 3)
	for t: Variant in _g("targets", []):
		var td: Dictionary = t
		var rel := wrapf(float(td.yaw) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5:
			continue
		var x := cx - rel / (PI * 0.5) * 300.0
		var col: Color = td.color
		if bool(td.get("ring", false)):
			draw_arc(Vector2(x, line_y), 6.0, 0.0, TAU, 20, col, 2.0, true)
		else:
			draw_colored_polygon(_diamond(Vector2(x, line_y), 8.0), col)
		var ly := line_y + (38.0 if bool(td.get("ring", false)) else 22.0)   # ворота — ниже, не налезают на врага
		_center(Vector2(x, ly), "%d м" % int(td.dist), sans, 13, col, 3)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, 70), Vector2(cx + 7, 70), Vector2(cx, 60)]), c_gold)   # указатель
	draw_rect(Rect2(cx - 1, 40, 2, 22), c_gold_hi)


func _draw_map_frame() -> void:
	var c := Vector2(_w - 40.0 - MAP_R, 30.0 + MAP_R)
	# север на кольце: карта вращается с камерой
	var yaw := float(_g("yaw", 0.0))
	var n := c + Vector2(sin(yaw), -cos(yaw)) * (MAP_R - 14.0)
	_center(n, "北", cjk, 14, c_pink, 3)
	_center(Vector2(c.x, c.y + MAP_R + 36), str(_g("place", "")), serif, 26, c_text, 4, 220.0)
	_center(Vector2(c.x, c.y + MAP_R + 60), _tr("pax_rpg_hud_region"), sans, 13, c_muted, 3, 220.0)


func _draw_mask() -> void:
	var r := MAP_R * _s
	_mask.draw_circle(Vector2(r + 2.0 * _s, r + 2.0 * _s), r, Color(0.075, 0.1, 0.235))


## Миникарта (внутри круга): верх — куда смотрит камера; платформы, ворота, враги, герой.
func _draw_map() -> void:
	if st.is_empty():
		return
	var r := MAP_R * _s
	var c := Vector2(r + 2.0 * _s, r + 2.0 * _s)
	var k := r / MAP_M
	var yaw := float(_g("yaw", 0.0))
	var me: Vector2 = _g("me", Vector2.ZERO)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var to_map := func(w: Vector2) -> Vector2:
		var d := w - me
		return c + Vector2(d.dot(right), -d.dot(fwd)) * k
	# все коробки города — одна сетка в мировых метрах (строится один раз): один вызов отрисовки вместо сотен
	var ax := Vector2(right.x, -fwd.x) * k                # мир → карта: p = c + (d.x * ax + d.y * ay)
	var ay := Vector2(right.y, -fwd.y) * k
	var rects: Array = _g("map_rects", [])
	if _map_mesh == null or _map_n != rects.size():
		_map_mesh = _rects_mesh(rects)
		_map_n = rects.size()
	if _map_mesh != null:
		_map.draw_set_transform_matrix(Transform2D(ax, ay, c - me.x * ax - me.y * ay))
		_map.draw_mesh(_map_mesh, null)
		_map.draw_set_transform_matrix(Transform2D.IDENTITY)
	var gate: Vector2 = _g("gate", Vector2.ZERO)
	_map.draw_arc(to_map.call(gate), 7.0 * _s, 0.0, TAU, 20, c_blue, 2.0 * _s, true)
	for e: Variant in _g("enemies", []):
		var ed: Dictionary = e
		var p: Vector2 = to_map.call(ed.pos)
		var col: Color = c_red if bool(ed.get("locked", false)) else c_pink
		var dm := PackedVector2Array()
		for v: Vector2 in _diamond(p, 6.0 * _s):
			dm.append(v)
		_map.draw_colored_polygon(dm, col)
	# герой — стрелка вверх (камера) повёрнута на поворот тела
	var body := float(_g("body_yaw", yaw)) - yaw
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -12), Vector2(8, 10), Vector2(0, 5), Vector2(-8, 10)]:
		arrow.append(c + v.rotated(-body) * _s)
	_map.draw_colored_polygon(arrow, c_blue)


func _draw_quest() -> void:
	var rx := _w - 40.0
	var y := 372.0
	_text(Vector2(rx - 320, y), _tr("pax_rpg_hud_quest").to_upper(), sans, 12, c_pink, HORIZONTAL_ALIGNMENT_RIGHT, 320)
	_text(Vector2(rx - 320, y + 32), _tr("pax_rpg_quest_title"), serif, 27, c_text, HORIZONTAL_ALIGNMENT_RIGHT, 320)
	_text(Vector2(rx - 320, y + 62), _tr("pax_rpg_quest_kills") % int(_g("kills", 0)), sans, 15, c_text,
		HORIZONTAL_ALIGNMENT_RIGHT, 320)
	var near := bool(_g("near_gate", false))
	_text(Vector2(rx - 320, y + 90), _tr("pax_rpg_quest_exit"), sans, 15, c_pink if near else c_dim,
		HORIZONTAL_ALIGNMENT_RIGHT, 320)


func _draw_enemy() -> void:
	var e: Dictionary = _g("enemy", {})
	if e.is_empty() or _live != null:                    # враг и босс — в живом слое (_draw_live)
		_boss_ghost = 1.0
		return
	if bool(e.get("boss", false)):
		_draw_boss(e)
		return
	var r := Rect2(_w - 40.0 - 380.0, 580.0, 380.0, 116.0)
	draw_rect(r, Color(c_ink, 0.72))
	draw_rect(r, Color(c_pink, 0.45), false, 1.0)
	var pic := Rect2(r.position + Vector2(16, 16), Vector2(84, 84))
	draw_rect(pic, Color(0.16, 0.11, 0.24))
	if portrait != null:
		draw_texture_rect(portrait, pic, false)
	else:
		_center(pic.get_center(), "鬼", cjk, 40, c_pink)
	draw_rect(pic, c_pink, false, 1.0)
	var x := r.position.x + 116.0
	var w := r.size.x - 132.0
	_text(Vector2(x, r.position.y + 38), str(e.get("name", "")), serif, 23, c_text)
	draw_rect(Rect2(x, r.position.y + 52, w, 10), Color(0.1, 0.08, 0.19))
	draw_rect(Rect2(x, r.position.y + 52, w * float(e.get("hp", 1.0)), 10), c_red)
	var p := float(e.get("posture", 0.0))
	draw_rect(Rect2(x, r.position.y + 68, w, 6), Color(0.1, 0.08, 0.19))
	if p > 0.005:
		draw_rect(Rect2(x + w * 0.5 * (1.0 - p), r.position.y + 68, w * p, 6), c_amber.lerp(c_red, p))
	var status := ""
	var sc := c_muted
	if bool(e.get("broken", false)):
		status = _tr("pax_rpg_hud_broken")
		sc = c_pink
	elif p > 0.7:
		status = _tr("pax_rpg_hud_posture_high")
		sc = c_amber
	else:
		status = _tr("pax_rpg_hud_weak")
	_text(Vector2(x, r.position.y + 96), status, sans, 13, sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


## Босс — полоса в стиле Гхарна вверху по центру (под компасом, не мешает приёмам внизу): тёмная лакированная
## плашка в двойной золотой рамке с клыками на концах (как Врата Клыка), слева — красный ромб с 闘, над полосой —
## имя золотом, под ней — титул. Здоровье — киноварь со «следом» снятого урона; концентрация — под полосой от центра.
var _boss_ghost := 1.0
const GOLD := Color(0.88, 0.68, 0.32)
const CINNABAR := Color(0.78, 0.12, 0.16)


func _draw_boss(e: Dictionary) -> void:
	var w := 760.0
	var x := (_w - w) * 0.5
	var y := 132.0                                     # верх полосы (под компасом)
	var h := 14.0
	var hp := clampf(float(e.get("hp", 1.0)), 0.0, 1.0)
	_boss_ghost = maxf(hp, move_toward(_boss_ghost, hp, 0.004))
	# плашка
	var plate := PackedVector2Array([Vector2(x - 34, y - 46), Vector2(x + w + 34, y - 46), Vector2(x + w + 20, y + h + 30),
		Vector2(x - 20, y + h + 30)])
	draw_colored_polygon(plate, Color(0.06, 0.03, 0.05, 0.78))
	draw_polyline(plate + PackedVector2Array([plate[0]]), Color(c_gold, 0.35), 1.0, true)
	# имя — золотом по центру, титул — под полосой
	_center(Vector2(_w * 0.5, y - 22.0), str(e.get("name", "")), serif, 28, Color(1.0, 0.9, 0.7), 4)
	var title := str(e.get("title", ""))
	if title != "":
		_center(Vector2(_w * 0.5, y + h + 18.0), title.to_upper(), sans, 12, Color(c_gold, 0.9), 3)
	# полоса: подложка, след, здоровье, блик
	draw_rect(Rect2(x, y, w, h), Color(0.12, 0.04, 0.06))
	draw_rect(Rect2(x, y, w * _boss_ghost, h), Color(1.0, 0.82, 0.7, 0.5))
	draw_rect(Rect2(x, y, w * hp, h), CINNABAR)
	draw_rect(Rect2(x, y + 1.0, w * hp, 3.0), Color(1.0, 0.45, 0.4, 0.75))
	for k: int in range(1, 10):                          # насечки по десятым — читается остаток
		draw_line(Vector2(x + w * k / 10.0, y), Vector2(x + w * k / 10.0, y + h), Color(0, 0, 0, 0.35), 1.0)
	# двойная золотая рамка и клыки на концах
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), c_gold, false, 1.5)
	draw_rect(Rect2(x - 5, y - 5, w + 10, h + 10), Color(c_gold, 0.45), false, 1.0)
	for sd: float in [-1.0, 1.0]:
		var ex := x - 5.0 if sd < 0.0 else x + w + 5.0
		var fang := PackedVector2Array([Vector2(ex, y - 5), Vector2(ex + sd * 26.0, y + h * 0.5), Vector2(ex, y + h + 5),
			Vector2(ex + sd * 9.0, y + h * 0.5)])
		draw_colored_polygon(fang, c_gold)
		draw_line(Vector2(ex + sd * 26.0, y + h * 0.5), Vector2(ex + sd * 38.0, y + h * 0.5), Color(c_gold, 0.6), 1.5)
	# ромб с 闘 слева
	var dc := Vector2(x - 62.0, y + h * 0.5)
	var dm := PackedVector2Array()
	for v: Vector2 in _diamond(dc, 22.0):
		dm.append(v)
	draw_colored_polygon(dm, CINNABAR)
	_outline(dm, c_gold, 2.0)
	_center(dc + Vector2(0, 7), "闘", cjk, 22, Color(1.0, 0.92, 0.8), 2)
	# концентрация — тонкая под полосой, от центра в стороны
	var p := clampf(float(e.get("posture", 0.0)), 0.0, 1.0)
	var broken := bool(e.get("broken", false))
	if p > 0.005 or broken:
		var pw := 420.0
		var py := y + h + 30.0
		draw_rect(Rect2((_w - pw) * 0.5, py, pw, 6.0), Color(0.05, 0.03, 0.06, 0.85))
		var col := c_pink if broken else c_amber.lerp(c_red, p)
		var pp := 1.0 if broken else p
		draw_rect(Rect2((_w - pw * pp) * 0.5, py, pw * pp, 6.0), col)
		draw_rect(Rect2(_w * 0.5 - 1.0, py - 3.0, 2.0, 12.0), Color(c_gold, 0.9))


## Метки поверх мира: прицел захвата и цифры урона (координаты — пиксели экрана, location.gd проецирует).
func _draw_marks() -> void:
	var lk: Variant = _g("lock_screen", null)
	if lk is Vector2:
		var p: Vector2 = lk / _s
		draw_circle(p, 22.0, Color(c_pink, 0.12))
		draw_arc(p, 20.0, 0.0, TAU, 40, c_pink, 2.0, true)
		var dm := _diamond(p, 8.0 if not bool(_g("lock_broken", false)) else 11.0)
		draw_colored_polygon(dm, c_red if bool(_g("lock_broken", false)) else Color(c_pink, 0.8))
	for n: Variant in _g("numbers", []):
		var nd: Dictionary = n
		var p: Vector2 = nd.p / _s
		var a := float(nd.a)
		var crit := bool(nd.get("crit", false))
		if crit:
			_text(p + Vector2(4, -36), _tr("pax_rpg_hud_crit"), sans, 13, Color(1.0, 0.89, 0.95, a), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 3)
		_text(p, str(nd.v), sans, 40 if crit else 30, Color(c_pink if crit else c_text, a), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 6)


func _draw_toast() -> void:
	var t: Dictionary = _g("toast", {})
	if t.is_empty():
		return
	var a := float(t.get("a", 1.0))
	var r := Rect2(40, 430, 380, 42)
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([Color(c_pink, 0.3 * a), Color(c_pink, 0.0), Color(c_pink, 0.0), Color(c_pink, 0.3 * a)]))
	_outline(_diamond(Vector2(62, 451), 10.0), Color(c_blue, a), 2.0)
	_text(Vector2(84, 457), str(t.get("text", "")), sans, 17, Color(c_text, a))


func _draw_flask() -> void:
	var n := int(_g("flask", 0))
	var nmax := int(_g("flask_max", 3))
	var box := Rect2(_core_c().x - 560.0 - 40.0, 1080.0 - CORE_UP - 46.0, 80, 92)   # слева от навыков у кольца
	_text(Vector2(box.position.x - 60, box.position.y - 12), _tr("pax_rpg_hud_flask"), sans, 13, c_muted,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x + 120)
	var o := box.position + Vector2(18, 18)
	var bottle := PackedVector2Array([o + Vector2(16, 0), o + Vector2(28, 0), o + Vector2(28, 10), o + Vector2(40, 26),
		o + Vector2(40, 54), o + Vector2(4, 54), o + Vector2(4, 26), o + Vector2(16, 10)])
	if n > 0:
		var lvl := 54.0 - 28.0 * float(n) / float(maxi(nmax, 1))
		draw_colored_polygon(PackedVector2Array([o + Vector2(6, lvl), o + Vector2(38, lvl), o + Vector2(38, 52),
			o + Vector2(6, 52)]), c_pink)
	_outline(bottle, Color(1.0, 0.89, 0.95), 2.0)
	_text(Vector2(box.end.x - 22, box.end.y - 8), str(n), sans, 20, c_text if n > 0 else c_dim)


## Кольцо добивания — справа на нижней панели, за последним приёмом (симметрично эликсиру слева).
func _ult_c() -> Vector2:
	var cc := _core_c()
	return Vector2(cc.x + 566.0, cc.y + 8.0)


func _draw_skills() -> void:
	# кольцо добивания: заполнено концентрацией врага, горит, когда можно добить
	var uc := _ult_c()
	var up := float(_g("ult", 0.0))
	var ready := bool(_g("ult_ready", false))
	if ready:
		draw_circle(uc, 80.0, Color(c_pink, 0.18))
	if up > 0.0:
		draw_arc(uc, 63.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(up, 0.0, 1.0), 72, c_pink, 10.0, true)
	draw_circle(uc, 58.0, c_ink2)
	_center(uc, "桜", cjk, 56, Color(1.0, 0.89, 0.95) if ready else Color(0.72, 0.66, 0.8))
	_center(Vector2(uc.x, uc.y + 92.0), _tr("pax_rpg_hud_deathblow_ready") if ready else
		_tr("pax_rpg_hud_deathblow") % int(up * 100.0), sans, 13, c_pink if ready else c_muted, 3, 170.0)
	var skills: Array = _g("skills", [])
	var cc := _core_c()
	var half := ceili(skills.size() / 2.0)
	for i: int in skills.size():
		var sd: Dictionary = skills[i]
		# первая половина — слева от кольца (дальняя — первая), вторая — справа (ближняя — первая)
		var gap := 112.0 if skills.size() <= 6 else 98.0      # 7 приёмов — плотнее (кольцо добивания и эликсир по краям)
		var x := cc.x + (-200.0 - (half - 1 - i) * gap if i < half else 200.0 + (i - half) * gap)
		var c := Vector2(x, cc.y + 20.0)
		var on := bool(sd.get("on", false))
		var ring: Color = sd.get("color", c_pink)
		var dm := _diamond(c, 42.0)
		var bev := _diamond(c, 50.0)                                   # кованая оправа ромба
		draw_colored_polygon(bev, c_bronze)
		draw_colored_polygon(dm, Color(c_ink, 0.95 if on else 0.85))
		_outline(bev, c_gold, 1.6)
		_outline(_diamond(c, 46.0), Color(c_gold, 0.45), 1.0)
		draw_line(c + Vector2(-25, -25), c + Vector2(0, -50), Color(c_gold_hi, 0.5), 1.5, true)   # блик по грани
		_outline(dm, ring if on else Color(c_text, 0.35), 2.5 if on else 1.5)
		if on:
			draw_colored_polygon(_diamond(c, 36.0), Color(ring, 0.18))
		var ic: Variant = sd.get("icon", null)
		if ic is Texture2D:                              # своя иконка (приём) вместо иероглифа
			var isz := 62.0
			draw_texture_rect(ic, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
				Color(1, 1, 1, 1.0 if bool(sd.get("ready", true)) else 0.35))
		else:
			_center(c, str(sd.k), cjk, 30, c_text if on or bool(sd.get("ready", true)) else c_dim)
		var cd := float(sd.get("cd", 0.0))
		if cd > 0.0:                                     # перезарядка: тёмная часть ромба сверху и секунды
			var full := _diamond(c, 41.0)
			var cut := c.y + 41.0 - 82.0 * (1.0 - cd)
			var top := Geometry2D.intersect_polygons(full, PackedVector2Array([Vector2(c.x - 50, c.y - 50),
				Vector2(c.x + 50, c.y - 50), Vector2(c.x + 50, cut), Vector2(c.x - 50, cut)]))
			if top.size() > 0:
				draw_colored_polygon(top[0], Color(0.02, 0.02, 0.06, 0.7))
			_center(c + Vector2(0, 10), str(sd.get("cd_s", "")), sans, 22, c_text, 4)
		_gem(c + Vector2(0, -50), 4.5, ring if on else Color(0.5, 0.5, 0.6))
		_center(Vector2(c.x, c.y + 66), "%s · %s" % [sd.key, sd.label], sans, 13, c_muted, 3, 106.0)


func _draw_xp() -> void:
	var x0 := 560.0
	var x1 := _w - 560.0
	if x1 - x0 < 300.0:
		x0 = _w * 0.5 - 150.0
		x1 = _w * 0.5 + 150.0
	var y := 1080.0 - 26.0
	var xp := float(_g("xp", 0.0))
	_text(Vector2(x0, y - 10), "%s %d · %d%%" % [_tr("pax_rpg_hud_level"), int(_g("level", 1)), int(xp * 100.0)], sans,
		13, c_muted, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var mana := "%d %s" % [int(_g("mana", 0)), _tr("pax_rpg_hud_mana")]
	_text(Vector2(x1 - 300, y - 10), mana, sans, 13, c_muted, HORIZONTAL_ALIGNMENT_RIGHT, 300, 3)
	var mw := sans.get_string_size(mana, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_colored_polygon(_diamond(Vector2(x1 - mw - 10, y - 15), 5.0), c_blue)
	draw_rect(Rect2(x0, y, x1 - x0, 3), Color(c_text, 0.15))
	var f := (x1 - x0) * clampf(xp, 0.0, 1.0)
	if f > 1.0:
		draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x0 + f, y), Vector2(x0 + f, y + 3), Vector2(x0, y + 3)]),
			PackedColorArray([c_blue, c_pink, c_pink, c_blue]))


## Разбить строку по словам (разделитель « · » — по пунктам), чтобы каждая часть влезала в width.
func _wrap(line: String, width: float, fs: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word: String in line.split(" "):
		var next := word if cur == "" else cur + " " + word
		if cur != "" and sans.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(cur)
			cur = word
		else:
			cur = next
	if cur != "":
		out.append(cur)
	return out


## Ранг стиля справа (под заданием): крупная буква в огне и золоте, название ранга, полоска до следующего; вспышка — рост.
func _draw_style() -> void:
	var sd: Dictionary = _g("style", {})
	var l := str(sd.get("letter", ""))
	if l == "":
		return
	var rk := int(sd.get("rank", 0))
	var fl := float(sd.get("flash", 0.0))
	# плашка: красный лак в золоте с конём и фениксом (textures/hud/style_frame.png) — слева, под уведомлениями
	var tex := _ht("style_frame")
	var pw := 290.0 + fl * 16.0
	var ph := pw * (tex.get_height() / float(tex.get_width())) if tex != null else 150.0
	var pc := Vector2(40.0 + 145.0, 590.0)
	var pr := Rect2(pc - Vector2(pw, ph) * 0.5, Vector2(pw, ph))
	var hot := Color(1.0, 0.75, 0.3).lerp(Color(1.0, 0.92, 0.6), clampf(rk / 6.0, 0.0, 1.0))
	if fl > 0.0:
		draw_circle(pc, pw * 0.42, Color(1.0, 0.4, 0.2, 0.12 * fl))
	if tex != null:
		draw_texture_rect(tex, pr, false)
	var lc := pr.position + pr.size * Vector2(0.5, 0.56)          # середина красного лака
	_center(lc + Vector2(0, -8), l, serif, 58 + rk * 4 + int(fl * 14.0), c_gold_hi.lerp(hot, 0.3), 6, 160.0)
	_center(lc + Vector2(0, 30), str(sd.get("title", "")).to_upper(), sans, 13, Color(1.0, 0.9, 0.75), 3, 150.0)
	var bw := pr.size.x * 0.36
	var by := pr.position.y + pr.size.y * 0.8
	draw_rect(Rect2(lc.x - bw * 0.5, by, bw, 4), Color(0.2, 0.0, 0.02, 0.9))
	draw_rect(Rect2(lc.x - bw * 0.5, by, bw * clampf(float(sd.get("frac", 0.0)), 0.0, 1.0), 4), hot)


## Золото слева вверху: монета (золото, шлем самурая, розовое переливающееся свечение) и число монет.
func _draw_gold() -> void:
	var fl := float(_g("gold_flash", 0.0))
	_text(Vector2(112, 82), str(int(_g("gold", 0))), serif, 38, c_gold_hi.lerp(Color.WHITE, fl * 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	_text(Vector2(114, 104), _tr("pax_rpg_gold_name").to_upper(), sans, 12, Color(c_muted, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)


## Золотая монета: ореол — мягкое розовое свечение, дышит и переливается; диск — от тёмного золота к светлому, рифлёный
## ободок, внутренний кант; в центре — чеканный шлем самурая (кабуто с рогами-кувагата); по монете бежит блик.
## ci — где рисовать (HUD, окна), flash 0..1 — вспышка, когда монеты пришли.
static func coin(ci: CanvasItem, c: Vector2, r: float, t: float, flash := 0.0) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 2.2)
	for k: int in 5:                                         # розоватое свечение
		var hue := 0.92 + 0.04 * sin(t * 1.3 + k)
		ci.draw_circle(c, r * (1.25 + k * 0.16), Color.from_hsv(hue, 0.45, 1.0, (0.06 + 0.04 * pulse + 0.1 * flash) * (1.0 - k * 0.18)))
	ci.draw_circle(c, r, Color(0.45, 0.28, 0.06))
	for k: int in 6:                                         # объём диска: к центру светлее
		var f := float(k) / 5.0
		ci.draw_circle(c + Vector2(-r * 0.08, -r * 0.08) * f, r * (0.97 - f * 0.25), Color(0.62, 0.42, 0.1).lerp(Color(1.0, 0.82, 0.38), f))
	for i: int in 36:                                        # рифлёный ободок
		var a := TAU * i / 36.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.86, c + d * r * 0.99, Color(0.5, 0.32, 0.08, 0.7), 1.2, true)
	ci.draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(0.55, 0.36, 0.08, 0.9), 1.4, true)
	ci.draw_arc(c, r * 0.99, 0.0, TAU, 48, Color(1.0, 0.9, 0.6, 0.8), 1.2, true)
	# кабуто: купол, назатыльник уступами, рога-кувагата, личина
	var hc := c + Vector2(0, r * 0.08)
	var dark := Color(0.48, 0.3, 0.06)
	var lite := Color(1.0, 0.9, 0.55, 0.9)
	ci.draw_arc(hc, r * 0.32, PI, TAU, 24, dark, r * 0.14, true)                            # купол
	ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-r * 0.5, r * 0.02), hc + Vector2(r * 0.5, r * 0.02),
		hc + Vector2(r * 0.58, r * 0.2), hc + Vector2(-r * 0.58, r * 0.2)]), dark)          # шикоро — назатыльник
	ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-r * 0.42, r * 0.22), hc + Vector2(r * 0.42, r * 0.22),
		hc + Vector2(r * 0.5, r * 0.36), hc + Vector2(-r * 0.5, r * 0.36)]), dark)
	for sgn: float in [-1.0, 1.0]:                          # кувагата — рога вверх
		var base := hc + Vector2(sgn * r * 0.1, -r * 0.3)
		ci.draw_polyline(PackedVector2Array([base, base + Vector2(sgn * r * 0.16, -r * 0.2), base + Vector2(sgn * r * 0.3, -r * 0.42)]),
			dark, r * 0.07, true)
	ci.draw_circle(hc + Vector2(0, -r * 0.3), r * 0.06, dark)                              # маэдатэ
	ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-r * 0.16, r * 0.05), hc + Vector2(r * 0.16, r * 0.05),
		hc + Vector2(r * 0.1, r * 0.2), hc + Vector2(-r * 0.1, r * 0.2)]), Color(0.36, 0.22, 0.04))   # личина
	ci.draw_arc(hc, r * 0.32, PI * 1.15, PI * 1.55, 12, lite, 1.2, true)                    # грань купола на свету
	var sweep := fmod(t * 0.45, 1.6) - 0.3                  # блик пробегает по монете
	if sweep > 0.0 and sweep < 1.0:
		var sx := lerpf(-r, r, sweep)
		var hw := r * 0.18
		var yy := sqrt(maxf(0.0, r * r - sx * sx)) * 0.92
		if yy > 0.5:                                         # у края монеты блик вырождается в линию — не рисовать
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sx - hw, -yy), c + Vector2(sx + hw * 0.4, -yy),
				c + Vector2(sx + hw, yy), c + Vector2(sx - hw * 0.4, yy)]), Color(1.0, 0.97, 0.9, 0.28))


func _draw_hint() -> void:
	var a := float(_g("hint_a", 0.0))
	if a > 0.01:
		var y := 250.0
		var width := minf(1100.0, _w - 40.0 - 480.0)          # не залезать под миникарту и задание справа
		for line: String in str(_g("hint", "")).split("\n"):
			for part: String in _wrap(line, width, 14):
				_text(Vector2(40, y), part, sans, 14, Color(c_muted, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
				y += 22.0
	var g := str(_g("gate_hint", ""))
	if g != "":
		_center(Vector2(_w * 0.5, 1080 - CORE_UP - 175), g, sans, 18, c_pink, 5)   # над кольцом героя


# ---------- живой слой (каждый кадр): концентрация героя, панель врага справа, босс по центру ----------
# Порядок: полосы (shaders/hud_bar.gdshader — глянец, текущая энергия, свечение края) → поверх кованые рамки
# (textures/hud/*.png, канал рамки прозрачный — полоса под рамкой, края её накрывают) → сверху тумблеры, шевроны,
# аватар, имена. Полосы без цифр: концентрация делится по центру — на 100 заполнена в обе стороны, к нулю края
# сходятся к центру; ползунок движется плавно, при резком падении — светлый след и вздрог; тумблеры на краях с
# шевронами: наружу и золотом — растёт, внутрь и красным — убывает (ДИЗДОК — бой).
const CONC_SLOT := [0.0711, 0.3247, 0.8567, 0.3395]       # прозрачный канал conc_frame.png (доли)
const BOSS_SLOT := [0.1118, 0.4599, 0.7736, 0.3029]       # канал boss_frame.png
const FOE_HP := [0.2545, 0.2490, 0.1500, 0.5750]          # каналы enemy_frame.png: здоровье и концентрация
const FOE_CONC := [0.5870, 0.2505, 0.1530, 0.5735]
const FOE_MEDAL := [0.4958, 0.1354, 0.3]                  # центр медальона (доли) и радиус аватара (доля ширины)
const HP_COLS := [Color(1.0, 0.45, 0.45), Color(0.86, 0.07, 0.12), Color(0.32, 0.0, 0.03), Color(1.0, 0.78, 0.72),
	Color(1.0, 0.62, 0.58)]                                 # здоровье: верх, середина, низ, свечение, след
const CONC_COLS := [Color(1.0, 0.95, 0.6), Color(1.0, 0.72, 0.17), Color(0.56, 0.25, 0.02), Color(1.0, 0.98, 0.82),
	Color(1.0, 0.86, 0.55)]
var _live: Control                     # контейнер: полосы, рамки, верхний слой
var _over: Control                     # верхний слой (рисование): тумблеры, аватар, имена
var _tex := {}
var _live_ms := 0
var _bars := {}                        # ключ → {v, ghost, a, shake, trend, last, hold}
var _bar_nodes := {}                   # ключ → ColorRect с шейдером полосы
var _frame_nodes := {}                 # ключ → TextureRect рамки
var _lay := {}                         # ключ → что рисовать сверху: {rect (макет), vertical, centered, low, broken}
var _bar_sh: Shader
var _foe_id := -1
var _foe_e: Dictionary = {}


func _ht(name_: String) -> Texture2D:
	if not _tex.has(name_):
		_tex[name_] = mod.texture("textures/hud/%s.png" % name_) if mod != null else null
	return _tex[name_]


func _live_setup() -> void:
	_live = Control.new()
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_live)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.draw.connect(_draw_over)
	_live.add_child(_over)
	_bar_sh = mod.shader("shaders/hud_bar.gdshader") if mod != null else null


## Полоса-узел с шейдером (ниже всех детей слоя) и рамка-узел (над полосами, под верхним слоем).
func _bar_node(key: String, cols: Array, centered: bool, vertical: bool) -> ColorRect:
	if not _bar_nodes.has(key):
		var n := ColorRect.new()
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.color = Color(0.08, 0.01, 0.02)
		if _bar_sh != null:
			var m := ShaderMaterial.new()
			m.shader = _bar_sh
			m.set_shader_parameter("col_hi", cols[0])
			m.set_shader_parameter("col_mid", cols[1])
			m.set_shader_parameter("col_lo", cols[2])
			m.set_shader_parameter("glow", cols[3])
			m.set_shader_parameter("ghost_col", cols[4])
			m.set_shader_parameter("centered", centered)
			m.set_shader_parameter("vertical", vertical)
			n.material = m
		_live.add_child(n)
		_live.move_child(n, 0)
		_bar_nodes[key] = n
	return _bar_nodes[key]


func _frame_node(key: String, tex_name: String) -> TextureRect:
	if not _frame_nodes.has(key):
		var f := TextureRect.new()
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.texture = _ht(tex_name)
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_SCALE
		_live.add_child(f)
		_live.move_child(f, _over.get_index())
		_frame_nodes[key] = f
	return _frame_nodes[key]


## Плавная полоса: v догоняет цель, след держится миг и догоняет, резкое падение — вздрог, тренд — знак изменения.
func _bar_step(key: String, target: float, dt: float, show: bool) -> Dictionary:
	if not _bars.has(key):
		_bars[key] = {"v": target, "ghost": target, "a": 0.0, "shake": 0.0, "trend": 0.0, "last": target, "hold": 0.0}
	var b: Dictionary = _bars[key]
	var last := float(b.last)
	if target < last - 0.06:
		b.shake = 0.35
		b.hold = 0.45
	if absf(target - last) > 0.0005:
		b.trend = clampf(float(b.trend) + signf(target - last) * 0.6, -1.0, 1.0)
	b.trend = move_toward(float(b.trend), 0.0, dt * 1.2)
	b.last = target
	b.v = move_toward(float(b.v), target, dt * (2.4 if target < float(b.v) else 1.4))
	if target >= float(b.ghost):
		b.ghost = maxf(target, float(b.v))
	else:
		b.hold = maxf(0.0, float(b.hold) - dt)
		if float(b.hold) <= 0.0:
			b.ghost = move_toward(float(b.ghost), float(b.v), dt * 0.7)
	b.shake = maxf(0.0, float(b.shake) - dt)
	b.a = move_toward(float(b.a), 1.0 if show else 0.0, dt / 0.45)
	return b


func _shake_off(b: Dictionary) -> Vector2:
	var k := float(b.get("shake", 0.0)) / 0.35
	if k <= 0.0:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6)) * 4.0 * k


## Поставить полосу и рамку: r — рамка (макет), slot — канал (доли рамки); полоса чуть шире канала — края под рамкой.
func _place(key: String, frame_key: String, tex_name: String, r: Rect2, slot: Array, cols: Array, centered: bool,
		vertical: bool, b: Dictionary, low: bool, broken: bool) -> void:
	var a := smoothstep(0.0, 1.0, float(b.a))
	var sr := Rect2(r.position + r.size * Vector2(float(slot[0]), float(slot[1])), r.size * Vector2(float(slot[2]), float(slot[3])))
	var n := _bar_node(key, cols, centered, vertical)
	n.position = (sr.position - Vector2(2, 2)) * _s
	n.size = (sr.size + Vector2(4, 4)) * _s
	n.visible = a > 0.01
	var m := n.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("fill", float(b.v))
		m.set_shader_parameter("ghost", float(b.ghost))
		m.set_shader_parameter("low", 1.0 if low else 0.0)
		m.set_shader_parameter("broken", 1.0 if broken else 0.0)
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("aspect", maxf(sr.size.x, sr.size.y) / maxf(minf(sr.size.x, sr.size.y), 1.0))
	if frame_key != "":
		var f := _frame_node(frame_key, tex_name)
		f.position = r.position * _s
		f.size = r.size * _s
		f.visible = a > 0.01
		f.modulate.a = a
	_lay[key] = {"rect": sr, "vertical": vertical, "centered": centered, "low": low, "broken": broken, "a": a, "b": b}


func _hide(keys: Array) -> void:
	for k: String in keys:
		if _bar_nodes.has(k):
			(_bar_nodes[k] as Control).visible = false
		if _frame_nodes.has(k):
			(_frame_nodes[k] as Control).visible = false
		_lay.erase(k)


## Кадр живого слоя (из refresh): шаг полос, раскладка узлов, перерисовка верхнего слоя.
func _live_tick() -> void:
	if _live == null or st.is_empty():
		return
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _live_ms) / 1000.0, 0.0, 0.1) if _live_ms > 0 else 0.016
	_live_ms = now
	# герой — над кольцом внизу по центру
	var hb := _bar_step("hero", clampf(float(_g("conc", 1.0)), 0.0, 1.0), dt, bool(_g("conc_on", false)))
	var tex := _ht("conc_frame")
	var w := 440.0
	var h := w * (tex.get_height() / float(tex.get_width())) if tex != null else 60.0
	var c := Vector2(_w * 0.5, 1080.0 - 232.0) + _shake_off(hb)
	_place("hero", "hero", "conc_frame", Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), CONC_SLOT, CONC_COLS, true, false, hb,
		bool(_g("conc_low", false)), bool(_g("conc_broken", false)))
	# враг
	var e: Dictionary = _g("enemy", {})
	var eid := int(e.get("id", -1))
	if eid != _foe_id:
		_foe_id = eid
		for k: String in ["foe_hp", "foe_conc", "boss_hp", "boss_conc"]:
			_bars.erase(k)
	_foe_e = e
	if e.is_empty():
		_hide(["foe_hp", "foe_conc", "foe", "boss_hp", "boss_conc", "boss", "boss_cf"])
	elif bool(e.get("boss", false)):
		_hide(["foe_hp", "foe_conc", "foe"])
		var bh := _bar_step("boss_hp", clampf(float(e.get("hp", 1.0)), 0.0, 1.0), dt, true)
		var bc := _bar_step("boss_conc", clampf(float(e.get("conc", 1.0)), 0.0, 1.0), dt, true)
		var bt := _ht("boss_frame")
		var bw := 720.0
		var bhh := bw * (bt.get_height() / float(bt.get_width())) if bt != null else 60.0
		var br := Rect2(Vector2((_w - bw) * 0.5, 92.0) + _shake_off(bh), Vector2(bw, bhh))
		_place("boss_hp", "boss", "boss_frame", br, BOSS_SLOT, HP_COLS, false, false, bh, false, false)
		var cw := 380.0
		var chh := cw * (tex.get_height() / float(tex.get_width())) if tex != null else 40.0
		var crr := Rect2(Vector2((_w - cw) * 0.5, br.end.y + 2.0) + _shake_off(bc), Vector2(cw, chh))
		_place("boss_conc", "boss_cf", "conc_frame", crr, CONC_SLOT, CONC_COLS, true, false, bc, float(bc.v) < 1.0 / 3.0,
			bool(e.get("broken", false)))
	else:
		_hide(["boss_hp", "boss_conc", "boss", "boss_cf"])
		var fh := _bar_step("foe_hp", clampf(float(e.get("hp", 1.0)), 0.0, 1.0), dt, true)
		var fc := _bar_step("foe_conc", clampf(float(e.get("conc", 1.0)), 0.0, 1.0), dt, true)
		var et := _ht("enemy_frame")
		var hgt := 420.0
		var wid := hgt * (et.get_width() / float(et.get_height())) if et != null else 100.0
		var er := Rect2(Vector2(_w - 46.0 - wid, 500.0) + _shake_off(fc), Vector2(wid, hgt))
		_place("foe_hp", "foe", "enemy_frame", er, FOE_HP, HP_COLS, false, true, fh, false, false)
		_place("foe_conc", "", "", er, FOE_CONC, CONC_COLS, true, true, fc, float(fc.v) < 1.0 / 3.0, bool(e.get("broken", false)))
		_lay["foe_frame"] = {"rect": er}
	_over.queue_redraw()


## Верхний слой: тумблеры и шевроны у краёв концентрации, метка центра, слом; аватар врага в медальоне, имена,
## фазы босса и его трети здоровья.
func _draw_over() -> void:
	if st.is_empty():
		return
	_ci = _over
	_over.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	var t := Time.get_ticks_msec() / 1000.0
	for key: String in ["hero", "boss_conc", "foe_conc"]:
		if _lay.has(key):
			_knobs(_lay[key], t)
	if _lay.has("boss_hp"):
		var L: Dictionary = _lay["boss_hp"]
		var sr: Rect2 = L.rect
		for k: int in [1, 2]:                                    # трети здоровья — три слома, три фазы
			var xk := sr.position.x + sr.size.x * k / 3.0
			_over.draw_line(Vector2(xk, sr.position.y + 2.0), Vector2(xk, sr.end.y - 2.0), Color(0.0, 0.0, 0.0, 0.55), 2.0)
		var e := _foe_e
		_center(Vector2(_w * 0.5, sr.position.y - 88.0), str(e.get("name", "")), serif, 26, Color(1.0, 0.9, 0.72), 5)
		var ph := int(e.get("phase", 0))
		for k: int in 3:
			var pc := Vector2(_w * 0.5 + (k - 1) * 22.0, sr.end.y + 26.0)
			var dm := _diamond(pc, 6.0)
			_over.draw_colored_polygon(dm, Color(0.85, 0.1, 0.12) if k >= ph else Color(0.25, 0.2, 0.2))
			_over.draw_polyline(dm + PackedVector2Array([dm[0]]), c_gold_hi, 1.0, true)
		if bool(e.get("broken", false)) and _lay.has("boss_conc"):
			var cr: Rect2 = (_lay["boss_conc"] as Dictionary).rect
			_center(Vector2(_w * 0.5, cr.end.y + 34.0), _tr("pax_rpg_hud_broken"), sans, 15, Color(1.0, 0.45, 0.4), 3)
	if _lay.has("foe_frame"):
		var er: Rect2 = (_lay["foe_frame"] as Dictionary).rect
		var e2 := _foe_e
		var mc := er.position + er.size * Vector2(FOE_MEDAL[0], FOE_MEDAL[1])
		var mr := er.size.x * float(FOE_MEDAL[2])
		if portrait != null:                                   # аватар — поверх бронзового диска медальона
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i: int in 40:
				var an := TAU * i / 40.0
				var d := Vector2(cos(an), sin(an))
				pts.append(mc + d * mr)
				uvs.append(Vector2(0.5, 0.5) + d * 0.5)
			_over.draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, portrait)
			_over.draw_arc(mc, mr, 0.0, TAU, 48, c_gold_hi, 1.5, true)
		var broken := bool(e2.get("broken", false))
		if broken:
			_over.draw_arc(mc, mr + 3.0, 0.0, TAU, 48, Color(1.0, 0.15, 0.1, 0.5 + 0.5 * sin(t * 9.0)), 3.0, true)
		var tx := er.position.x - 12.0
		_text(Vector2(tx - 320.0, mc.y - 4.0), str(e2.get("name", "")), serif, 24, c_text, HORIZONTAL_ALIGNMENT_RIGHT, 320, 5)
		if broken:
			_text(Vector2(tx - 320.0, mc.y + 20.0), _tr("pax_rpg_hud_broken"), sans, 14, Color(1.0, 0.45, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 320, 3)
	_ci = self


## Тумблеры концентрации: ромбы на краях заливки, шевроны тренда, метка центра, красный ромб слома.
func _knobs(L: Dictionary, t: float) -> void:
	var a := float(L.get("a", 1.0))
	if a <= 0.01:
		return
	var b: Dictionary = L.b
	var sr: Rect2 = L.rect
	var vert := bool(L.vertical)
	var v := float(b.v)
	var c := sr.get_center()
	var along := sr.size.y if vert else sr.size.x
	var thick := sr.size.x if vert else sr.size.y
	var ax := Vector2(0, -1) if vert else Vector2(1, 0)
	var cross := Vector2(1, 0) if vert else Vector2(0, 1)
	var cl := Color(c_gold_hi, 0.65 * a)
	_over.draw_line(c - cross * (thick * 0.5 + 2.0), c + cross * (thick * 0.5 + 2.0), cl, 1.0)
	if v > 0.004:
		for sd: float in [-1.0, 1.0]:
			var kc := c + ax * sd * along * 0.5 * v
			var dm := _diamond(kc, thick * 0.42)
			_over.draw_colored_polygon(dm, Color(c_gold_hi, a))
			_over.draw_polyline(dm + PackedVector2Array([dm[0]]), Color(0.3, 0.16, 0.06, a), 1.2, true)
			_over.draw_circle(kc, thick * 0.6, Color(1.0, 0.85, 0.5, 0.12 * a))
			var tr := float(b.trend)
			if absf(tr) > 0.05:
				var outw := tr > 0.0
				var dir := sd * (1.0 if outw else -1.0)
				var col := Color(1.0, 0.9, 0.5, absf(tr) * a) if outw else Color(1.0, 0.3, 0.25, absf(tr) * a)
				for k: int in 2:
					var p := kc + ax * dir * (thick * 0.62 + k * 7.0)
					var hh := thick * 0.32
					_over.draw_polyline(PackedVector2Array([p - ax * dir * 4.0 - cross * hh, p, p - ax * dir * 4.0 + cross * hh]),
						col, 2.0, true)
	if bool(L.broken) or v <= 0.004:
		var bp := 0.6 + 0.4 * sin(t * 9.0)
		_over.draw_colored_polygon(_diamond(c, thick * 0.55), Color(0.95, 0.1, 0.1, a * bp))
