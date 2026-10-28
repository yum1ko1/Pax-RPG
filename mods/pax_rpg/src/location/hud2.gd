extends "res://mods/pax_rpg/src/location/hud.gd"
## HUD v2 в стиле инвентаря: кованые рамки красного лака с золотом (textures/hud2, окна рамок — config/hud2.json,
## их режет pax_rpg/dev/hud2/build_hud2.py). Слева сверху — задание, под ним — враг в бою, слева снизу — герой
## (портрет, здоровье, концентрация, опыт), снизу по центру — панель приёмов (собирается из кусков под 2…7 приёмов,
## в середине — медальон добивания, справа — эликсир), сверху — полоса компаса, под ней — босс, справа — миникарта
## (север вверху, запечённый план города с подписями) и золото. Порядок в каждой рамке: заливки → рамка → текст.
## Данные — тот же словарь st, что у hud.gd; от родителя берутся шрифты, цвета темы, метки, цифры урона, ранг стиля.

const IVORY := Color(0.957, 0.894, 0.784)
const IVORY_DIM := Color(0.78, 0.69, 0.55)
## Цвета — в тон городу днём (лак ворот, песок, дымка), а не ночному GPT-макету: красный приглушён, подложка —
## тёмный орех и чуть прозрачна (рамки так же тонирует pax_rpg/dev/hud2/tone_hud2.py).
const CRIMSON2 := Color(0.7, 0.17, 0.17)
const CRIMSON_HI := Color(0.93, 0.42, 0.36)
const GHOST2 := Color(0.88, 0.62, 0.55)
const AMBER2 := Color(0.86, 0.66, 0.3)
const XP_COL := Color(0.55, 0.68, 0.8)
const WELL := Color(0.15, 0.095, 0.08, 0.82)
const MINI_M := 45.0
const CityMap := preload("res://mods/pax_rpg/src/location/city_map.gd")                  # м мира от центра миникарты до края круга

## Куски панели приёмов (доли ширины рамки): A — левый край с первой ячейкой, B — ячейка-повтор слева,
## C — последняя левая ячейка, медальон и первая правая, D — ячейка-повтор справа, E — эликсир и правый край.
## Ячейки — номера окон рамки: [ячейка, плашка клавиши].
const PIECES := {
	"A": [0.0, 0.17377, [[1, 11]]],
	"B": [0.17377, 0.28721, [[2, 12]]],
	"C": [0.28721, 0.7141, [[3, 13], [4, 14]]],
	"D": [0.7141, 0.82754, [[5, 15]]],
	"E": [0.82754, 1.0, []],
}

var _cfg := {}                        # config/hud2.json → frames
var _ftex := {}                       # ключ рамки → текстура
var _cmp2: Control                    # полоса компаса — свой слой за HUD (крутится с камерой)
var _cmp2_sig := 0
var _f_sc: Font                       # Cormorant SC — заголовки, клавиши
var _f_serif: Font                    # Cormorant Garamond — строки
var _char := ""
var _mini_tex: Texture2D              # запечённая миникарта города (север вверху)
var _mini_rect := Rect2()             # где она лежит в мире (x, z, ш, г)
var _icons := {}
var _quest := {}
var _quest_t := 0
var _eg := 1.0                        # след здоровья врага / босса
var _eg_id := -1
var _h := 1080.0                      # высота экрана в px макета
var _k := 1.0                         # масштаб HUD (config/world_ui.json → ui_scale.hud)


func setup(m: PaxMod, enemy_portrait: Texture2D) -> void:
	super.setup(m, enemy_portrait)
	var c: Variant = JSON.parse_string(m.read_text("config/hud2.json"))
	_cfg = (c as Dictionary).get("frames", {}) if c is Dictionary else {}
	for k: String in _cfg:
		_ftex[k] = m.texture(str((_cfg[k] as Dictionary).get("tex", "")))
	var u: Variant = JSON.parse_string(m.read_text("config/world_ui.json"))
	var us: Variant = (u as Dictionary).get("ui_scale", {}) if u is Dictionary else {}
	_k = float((us as Dictionary).get("hud", 1.0)) if us is Dictionary else 1.0
	_f_sc = _font("fonts/cormorant_sc.ttf")
	_f_serif = _font("fonts/cormorant_garamond.ttf")
	_cmp2 = Control.new()
	_cmp2.show_behind_parent = true                       # под рамкой босса, которая заходит на компас
	_cmp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmp2.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cmp2.draw.connect(_draw_cmp2)
	add_child(_cmp2)
	move_child(_cmp2, 0)


func _font(path: String) -> Font:
	var f := FontFile.new()
	f.data = mod.read_bytes(path)
	return f if not f.data.is_empty() else serif


func apply_theme(id: String) -> void:
	super.apply_theme(id)
	_char = id
	var u: Variant = JSON.parse_string(mod.read_text("config/world_ui.json")) if mod != null else null
	var pp := str(((u as Dictionary).get("portraits", {}) as Dictionary).get(id, "")) if u is Dictionary else ""
	if pp != "" and mod.texture(pp) != null:
		hero_portrait = mod.texture(pp)                   # арт-аватар героя (тот же, что на карте мира)


## Город с запечённой картой (config/<город>_map.json → art): миникарта рисует её, а не коробки построек.
func set_city(layout: Dictionary) -> void:
	_mini_tex = null
	if not layout.has("map"):
		return
	var mp: Variant = JSON.parse_string(mod.read_text(str(layout.get("map", ""))))
	if not (mp is Dictionary) or not (mp as Dictionary).has("art"):
		return
	var art: Dictionary = (mp as Dictionary).art
	var lang := "ru" if mod.tr_key("pax_rpg_map_legend") == "Легенда" else "en"
	var t := mod.texture(str(art.get("mini_" + lang, art.get("mini_ru", ""))))
	if t == null:
		return
	var img := t.get_image()                              # мипмапы — карта ужимается вдвое и плывёт под героем
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	_mini_tex = t
	var r: Array = art.get("rect", [-132, -132, 264, 264])
	_mini_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


# ---------- раскладка ----------

## Рамка key в макете: x, y — левый верх, ширина — из config/hud2.json (или w).
func _frame(key: String, x: float, y: float, w := -1.0) -> Rect2:
	var f: Dictionary = _cfg.get(key, {})
	var fw := float(f.get("size", 100.0)) if w < 0.0 else w
	return Rect2(x, y, fw, fw * float(f.get("aspect", 1.0)))


func _hole(key: String, r: Rect2, i: int) -> Rect2:
	var hs: Array = (_cfg.get(key, {}) as Dictionary).get("holes", [])
	if i >= hs.size():
		return Rect2(r.get_center(), Vector2.ZERO)
	var h: Array = hs[i]
	var a := r.position + r.size * Vector2(float(h[0]), float(h[1]))
	var b := r.position + r.size * Vector2(float(h[2]), float(h[3]))
	return Rect2(a, b - a)


func _hero_r() -> Rect2:
	var r := _frame("hero", 26.0, 0.0)
	r.position.y = _h - 26.0 - r.size.y
	return r


func _quest_r() -> Rect2:
	return _frame("quest", 26.0, 22.0)


func _enemy_r() -> Rect2:
	return _frame("enemy", 30.0, 268.0)


func _mini_r() -> Rect2:
	return _frame("minimap", _w - 26.0 - float((_cfg.get("minimap", {}) as Dictionary).get("size", 250.0)), 18.0)


func _compass_r() -> Rect2:
	var w := float((_cfg.get("compass", {}) as Dictionary).get("size", 900.0))
	return _frame("compass", (_w - w) * 0.5, 4.0)


func _boss_r() -> Rect2:
	var w := float((_cfg.get("boss", {}) as Dictionary).get("size", 940.0))
	return _frame("boss", (_w - w) * 0.5, 64.0)


## Круг миникарты (макет): окно рамки не квадратное — круг по меньшей стороне, по центру окна.
func _mini_circle() -> Vector3:
	var h := _hole("minimap", _mini_r(), 0)
	var c := h.get_center()
	return Vector3(c.x, c.y, minf(h.size.x, h.size.y) * 0.5)


## Панель приёмов на n ячеек: куски [имя, x в макете], ширина и высота.
func _skill_layout(n: int) -> Dictionary:
	var f: Dictionary = _cfg.get("skills", {})
	var unit := float(f.get("size", 760.0))              # px макета на всю исходную рамку
	var h := unit * float(f.get("aspect", 0.2577))
	var nl := maxi(2, ceili(n / 2.0))
	var nr := maxi(1, n - nl)
	var seq: Array = ["A"]
	for i: int in nl - 2:
		seq.append("B")
	seq.append("C")
	for i: int in nr - 1:
		seq.append("D")
	seq.append("E")
	var total := 0.0
	for p: String in seq:
		total += (float(PIECES[p][1]) - float(PIECES[p][0])) * unit
	var x := (_w - total) * 0.5
	var y := _h - 18.0 - h
	var out: Array = []
	for p: String in seq:
		out.append([p, x])
		x += (float(PIECES[p][1]) - float(PIECES[p][0])) * unit
	return {"pieces": out, "unit": unit, "h": h, "y": y, "x0": (_w - total) * 0.5, "w": total}


## Окно i рамки приёмов, если оно лежит в куске p, поставленном в x.
func _skill_hole(L: Dictionary, p: String, x: float, i: int) -> Rect2:
	var hs: Array = (_cfg.get("skills", {}) as Dictionary).get("holes", [])
	var h: Array = hs[i]
	var unit := float(L.unit)
	var x0 := float(PIECES[p][0])
	return Rect2(x + (float(h[0]) - x0) * unit, float(L.y) + float(h[1]) * float(L.h),
		(float(h[2]) - float(h[0])) * unit, (float(h[3]) - float(h[1])) * float(L.h))


# ---------- кадр ----------

func refresh() -> void:
	super.refresh()
	_s *= clampf(float(mod.get_setting("ui_scale", _k)), 0.4, 1.5) if mod != null else _k   # мельче макета: места больше
	_w = size.x / _s
	_h = size.y / _s
	var mc := _mini_circle()
	var r := mc.z * _s
	_mask.position = Vector2(mc.x * _s - r - 2.0 * _s, mc.y * _s - r - 2.0 * _s)
	_mask.size = Vector2(r * 2.0 + 4.0 * _s, r * 2.0 + 4.0 * _s)
	_map.size = _mask.size
	var csig := hash([_g("yaw", 0.0), _g("targets", []), size, _s, CityMap.pin, _g("me", Vector2.ZERO) if CityMap.pin.x != INF else 0])
	if csig != _cmp2_sig:
		_cmp2_sig = csig
		_cmp2.queue_redraw()
	var e: Dictionary = _g("enemy", {})                 # след здоровья врага догоняет — перерисовка, пока догоняет
	var hp := clampf(float(e.get("hp", 1.0)), 0.0, 1.0)
	if int(e.get("id", -1)) != _eg_id:
		_eg_id = int(e.get("id", -1))
		_eg = hp
	if _eg > hp + 0.001:
		_eg = move_toward(_eg, hp, get_process_delta_time() * 0.5)
		queue_redraw()
	else:
		_eg = hp
	var now := Time.get_ticks_msec()
	if now - _quest_t > 1000 and mod != null:            # задание жителя — из настроек мода, раз в секунду
		_quest_t = now
		var q: Variant = mod.get_setting("quest", {})
		var qd: Dictionary = q if q is Dictionary else {}
		if qd.hash() != _quest.hash():
			_quest = qd.duplicate()
			queue_redraw()


func _live_tick() -> void:
	pass                                                  # старые полосы концентрации и рамки врага не нужны


func _draw_deco() -> void:
	pass                                                  # старая оправа (кольцо, плашки) — не рисуется


func _draw_compass() -> void:
	pass                                                  # компас — _draw_cmp2


func _draw_map_frame() -> void:
	pass


func xp_target(frac: float) -> Vector2:
	var xr := _hole("hero", _hero_r(), 4)
	return (xr.position + Vector2(xr.size.x * clampf(frac, 0.0, 1.0), xr.size.y * 0.5)) * _s


func _draw() -> void:
	if st.is_empty() or _cfg.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	_ci = self
	_txt_k = 1.0
	_draw_quest2()
	_draw_hero2()
	_draw_skills2()
	var e: Dictionary = _g("enemy", {})
	if not e.is_empty():
		if bool(e.get("boss", false)):
			_draw_boss2(e)
		else:
			_draw_enemy2(e)
	_draw_marks()
	draw_set_transform(Vector2(100.0 * _s, 0.0), 0.0, Vector2(_s, _s))   # уведомление — правее панели врага
	_draw_toast()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	_draw_style()
	_draw_hint()
	_draw_orbs()


# ---------- помощники ----------

func _tex_frame(key: String, r: Rect2, a := 1.0) -> void:
	var t: Texture2D = _ftex.get(key)
	if t != null:
		draw_texture_rect(t, r, false, Color(1, 1, 1, a))


## Заливка окна: подложка, след, значение (верх светлее), блик. centered — от середины в стороны, vertical — снизу.
func _fill(r: Rect2, frac: float, col: Color, ghost := -1.0, centered := false, vertical := false) -> void:
	var g := r.grow(2.0)
	draw_rect(g, WELL)
	var parts: Array = []
	if ghost > frac:
		parts.append([ghost, GHOST2, GHOST2.darkened(0.25)])
	parts.append([frac, col.lerp(Color.WHITE, 0.18), col.darkened(0.35)])
	for pv: Variant in parts:
		var p: Array = pv
		var f := clampf(float(p[0]), 0.0, 1.0)
		if f <= 0.002:
			continue
		var fr := g
		if vertical:
			fr = Rect2(g.position.x, g.end.y - g.size.y * f, g.size.x, g.size.y * f)
		elif centered:
			fr = Rect2(g.get_center().x - g.size.x * f * 0.5, g.position.y, g.size.x * f, g.size.y)
		else:
			fr = Rect2(g.position, Vector2(g.size.x * f, g.size.y))
		var hi: Color = p[1]
		var lo: Color = p[2]
		if vertical:
			draw_polygon(PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]),
				PackedColorArray([hi, lo, lo, hi]))
		else:
			draw_polygon(PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]),
				PackedColorArray([hi, hi, lo, lo]))
	var f2 := clampf(frac, 0.0, 1.0)
	if f2 > 0.002 and not vertical:                       # блик по верху заливки
		var x0 := g.get_center().x - g.size.x * f2 * 0.5 if centered else g.position.x
		draw_rect(Rect2(x0, g.position.y + g.size.y * 0.18, g.size.x * f2, maxf(1.0, g.size.y * 0.14)), Color(1, 1, 1, 0.16))


func _disc(c: Vector2, r: float, tex: Texture2D, col := Color.WHITE) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in 48:
		var a := TAU * i / 48.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	if tex != null:
		draw_polygon(pts, PackedColorArray([col]), uvs, tex)
	else:
		draw_colored_polygon(pts, col)


func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = mod.texture(id) if mod != null else null
	return _icons[id]


func _txt(c: Vector2, s: String, font: Font, fs: int, col: Color, maxw := 300.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var x := c.x - maxw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else c.x
	_text(Vector2(x, c.y + fs * 0.32), s, font, fs, col, align, maxw, 3)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ---------- задание ----------

func _draw_quest2() -> void:
	var r := _quest_r()
	_tex_frame("quest", r)
	var x := r.position.x + 40.0
	var w := r.size.x - 80.0
	var head := _tr("pax_rpg_hud_quest")
	var rows: Array = []                                  # [текст, главное ли]
	if not _quest.is_empty():
		var found := str(_quest.get("state", "")) == "found"
		rows.append([preload("res://mods/pax_rpg/src/location/quest.gd").goal(mod, _quest), not found])
		rows.append([_tr("pax_rpg_journal_found") if found else _tr("pax_rpg_journal_active"), found])
	else:
		head = _tr("pax_rpg_quest_title")
		rows.append([_tr("pax_rpg_quest_kills") % int(_g("kills", 0)), not bool(_g("near_gate", false))])
		rows.append([_tr("pax_rpg_quest_exit"), bool(_g("near_gate", false))])
	_text(Vector2(x, r.position.y + r.size.y * 0.2 + 8.0), head, _f_sc, 24, IVORY, HORIZONTAL_ALIGNMENT_LEFT, w - 150.0, 3)
	var y := r.position.y + r.size.y * 0.47
	for rv: Variant in rows:
		var row: Array = rv
		var on := bool(row[1])
		var dc := Vector2(x + 14.0, y)
		if on:
			draw_colored_polygon(_diamond(dc, 4.0), IVORY)
		else:
			_outline(_diamond(dc, 4.0), IVORY_DIM, 1.0)
		_text(Vector2(x + 28.0, y + 8.0), str(row[0]), _f_serif, 22, IVORY if on else IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 30.0, 3)
		y += r.size.y * 0.19


# ---------- герой ----------

func _draw_hero2() -> void:
	var r := _hero_r()
	var pr := _hole("hero", r, 0)
	var pc := pr.get_center()
	var prad := minf(pr.size.x, pr.size.y) * 0.5 + 2.0
	_disc(pc, prad, null, WELL)
	_disc(pc, prad, hero_portrait)
	var fl := float(_g("lvl_flash", 0.0))
	if fl > 0.0:                                          # новый уровень: свет вокруг портрета
		var k := clampf(fl / 1.6, 0.0, 1.0)
		for j: int in 4:
			draw_arc(pc, prad + 6.0 + (1.0 - k) * 40.0 + j * 5.0, 0.0, TAU, 64, Color(1.0, 0.75, 0.4, 0.16 * k), 3.0, true)
	var hp := float(_g("hp", 1.0))
	_fill(_hole("hero", r, 1), hp, CRIMSON2 if hp > 0.3 else Color(1.0, 0.12, 0.1), float(_g("hp_ghost", 1.0)))
	var conc_col := AMBER2
	if bool(_g("conc_broken", false)):
		conc_col = Color(1.0, 0.2, 0.15)
	elif bool(_g("conc_low", false)):
		conc_col = AMBER2.lerp(CRIMSON2, 0.5)
	_fill(_hole("hero", r, 3), float(_g("conc", 1.0)), conc_col, -1.0, true)
	_fill(_hole("hero", r, 4), float(_g("xp", 0.0)), XP_COL)
	_tex_frame("hero", r)
	var name_k := "pax_rpg_char_%s_name" % _char
	var nm := _tr(name_k)
	if nm == name_k or nm == "":
		nm = _tr("pax_rpg_hero_name")
	_txt(r.position + r.size * Vector2(0.5195, 0.279), nm.to_upper(), _f_sc, 24, IVORY, 0.27 * r.size.x)
	_txt(r.position + r.size * Vector2(0.3055, 0.809), str(int(_g("level", 1))), _f_sc, 30, IVORY, 50.0)
	if int(_g("skill_points", 0)) > 0:                    # очки умений — ромбик у конца полосы опыта
		var xr := _hole("hero", r, 4)
		draw_colored_polygon(_diamond(Vector2(xr.end.x + 12.0, xr.get_center().y), 5.0), AMBER2)


# ---------- приёмы ----------

## Иконки приёмов без своей картинки (основные удары) — из иконок инвентаря.
const SKILL_ICONS := {"斬": "textures/inventory/sk_iai.jpg", "風": "textures/inventory/sk_moon.jpg"}


func _draw_skills2() -> void:
	var skills: Array = _g("skills", [])
	var L := _skill_layout(skills.size())
	var cells: Array = []                                 # [окно ячейки, окно клавиши]
	var med := Rect2()
	var rkey := Rect2()
	var flask := Rect2()
	var pips: Array = []
	for pv: Variant in L.pieces:
		var p: String = (pv as Array)[0]
		var x := float((pv as Array)[1])
		for ck: Variant in PIECES[p][2]:
			cells.append([_skill_hole(L, p, x, int((ck as Array)[0])), _skill_hole(L, p, x, int((ck as Array)[1]))])
		if p == "C":
			med = _skill_hole(L, p, x, 0)
			rkey = _skill_hole(L, p, x, 16)
		elif p == "E":
			flask = _skill_hole(L, p, x, 6)
			for i: int in range(7, 11):
				pips.append(_skill_hole(L, p, x, i))
	# ячейки идут слева направо: первые ceil(n / 2) приёмов — слева от медальона, остальные — справа
	# медальон добивания: концентрация врага, горит, когда можно добить
	var mc := med.get_center()
	var mr := minf(med.size.x, med.size.y) * 0.5 + 2.0
	var up := float(_g("ult", 0.0))
	var ready := bool(_g("ult_ready", false))
	_disc(mc, mr, null, Color(0.16, 0.02, 0.04, 1.0))
	_disc(mc, mr * 0.78, _icon("textures/icon_ult.png"), Color(1, 1, 1, 1.0 if ready else 0.55))
	if up > 0.0:
		draw_arc(mc, mr - 4.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(up, 0.0, 1.0), 64, CRIMSON_HI if ready else CRIMSON2, 6.0, true)
	if ready:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(mc, mr, Color(1.0, 0.3, 0.3, 0.12 + 0.12 * pulse))
		queue_redraw()                                    # пульс — каждый кадр, пока можно добить
	for i: int in cells.size():
		var cr: Rect2 = (cells[i] as Array)[0]
		draw_rect(cr.grow(2.0), WELL)
		if i >= skills.size():
			continue
		var sd: Dictionary = skills[i]
		var on := bool(sd.get("on", false))
		var rdy := bool(sd.get("ready", true))
		var ic: Variant = sd.get("icon", null)
		if not (ic is Texture2D) and SKILL_ICONS.has(str(sd.get("k", ""))):
			ic = _icon(SKILL_ICONS[str(sd.k)])
		var a := 1.0 if rdy or on else 0.4
		if ic is Texture2D:
			draw_texture_rect(ic, cr.grow(1.0), false, Color(1, 1, 1, a))
		else:
			_center(cr.get_center(), str(sd.get("k", "")), cjk, 34, Color(IVORY, a), 3, cr.size.x)
		var cd := clampf(float(sd.get("cd", 0.0)), 0.0, 1.0)
		if cd > 0.0:                                      # перезарядка: тёмная часть сверху и секунды
			draw_rect(Rect2(cr.position, Vector2(cr.size.x, cr.size.y * cd)), Color(0.02, 0.0, 0.02, 0.7))
		if on:
			var col: Color = sd.get("color", CRIMSON_HI)
			draw_rect(cr.grow(1.0), Color(col, 0.22))
			draw_rect(cr.grow(-1.0), col, false, 2.5)
	# эликсир: бутыль и заряды
	draw_rect(flask.grow(2.0), WELL)
	var n := int(_g("flask", 0))
	var nmax := int(_g("flask_max", 3))
	var fc := flask.get_center()
	var k := flask.size.x / 60.0
	var o := fc + Vector2(-22, -28) * k
	var bottle := PackedVector2Array([o + Vector2(16, 0) * k, o + Vector2(28, 0) * k, o + Vector2(28, 10) * k, o + Vector2(42, 28) * k,
		o + Vector2(42, 56) * k, o + Vector2(2, 56) * k, o + Vector2(2, 28) * k, o + Vector2(16, 10) * k])
	if n > 0:
		var lvl := 56.0 - 30.0 * float(n) / float(maxi(nmax, 1))
		draw_colored_polygon(PackedVector2Array([o + Vector2(4, lvl) * k, o + Vector2(40, lvl) * k, o + Vector2(40, 54) * k,
			o + Vector2(4, 54) * k]), CRIMSON2)
	_outline(bottle, Color(IVORY, 0.9 if n > 0 else 0.4), 2.0)
	for i: int in pips.size():
		var pr: Rect2 = pips[i]
		draw_rect(pr.grow(1.0), CRIMSON2 if i < n else (WELL if i < nmax else Color(0.02, 0.01, 0.01, 0.6)))
	# рамка — кусками
	var t: Texture2D = _ftex.get("skills")
	if t != null:
		var tw := float(t.get_width())
		for pv: Variant in L.pieces:
			var p: String = (pv as Array)[0]
			var x := float((pv as Array)[1])
			var x0 := float(PIECES[p][0])
			var x1 := float(PIECES[p][1])
			var dw := (x1 - x0) * float(L.unit)
			draw_texture_rect_region(t, Rect2(x - 0.25, float(L.y), dw + 0.5, float(L.h)),
				Rect2(x0 * tw, 0.0, (x1 - x0) * tw, float(t.get_height())))
	# клавиши и секунды — поверх рамки
	for i: int in mini(cells.size(), skills.size()):
		var sd: Dictionary = skills[i]
		var cr: Rect2 = (cells[i] as Array)[0]
		var kr: Rect2 = (cells[i] as Array)[1]
		_txt(kr.get_center(), str(sd.get("key", "")), _f_sc, 15, IVORY, kr.size.x + 6.0)
		if float(sd.get("cd", 0.0)) > 0.0 and str(sd.get("cd_s", "")) != "":
			_txt(cr.get_center(), str(sd.get("cd_s", "")), _f_sc, 28, IVORY, cr.size.x)
	_txt(rkey.get_center(), _tr("pax_rpg_key_lmb"), _f_sc, 15, IVORY if ready else IVORY_DIM, rkey.size.x + 6.0)
	_text(Vector2(flask.end.x - 40.0, flask.end.y - 6.0), str(n), _f_sc, 22, IVORY if n > 0 else IVORY_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 3)


# ---------- враг слева и босс сверху ----------

func _draw_enemy2(e: Dictionary) -> void:
	var r := _enemy_r()
	var pr := _hole("enemy", r, 0)
	var pc := pr.get_center()
	var prad := minf(pr.size.x, pr.size.y) * 0.5 + 2.0
	var broken := bool(e.get("broken", false))
	_disc(pc, prad, null, Color(0.2, 0.04, 0.06, 1.0))
	_disc(pc, prad, portrait)
	var hp := clampf(float(e.get("hp", 1.0)), 0.0, 1.0)
	_fill(_hole("enemy", r, 1), hp, CRIMSON2, _eg, false, true)
	var c := clampf(float(e.get("conc", 1.0)), 0.0, 1.0)
	_fill(_hole("enemy", r, 2), c, Color(1.0, 0.2, 0.15) if broken else (AMBER2 if c > 1.0 / 3.0 else AMBER2.lerp(CRIMSON2, 0.5)),
		-1.0, false, true)
	_tex_frame("enemy", r)
	if broken:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
		draw_arc(pc, prad + 3.0, 0.0, TAU, 48, Color(1.0, 0.15, 0.1, 0.4 + 0.5 * pulse), 3.0, true)
		queue_redraw()
	var nx := r.position.x
	var ny := r.end.y + 22.0
	_text(Vector2(nx, ny), str(e.get("name", "")), _f_serif, 22, IVORY, HORIZONTAL_ALIGNMENT_LEFT, 320.0, 4)
	if broken:
		_text(Vector2(nx, ny + 22.0), _tr("pax_rpg_hud_broken"), _f_serif, 17, CRIMSON_HI, HORIZONTAL_ALIGNMENT_LEFT, 360.0, 3)


func _draw_boss2(e: Dictionary) -> void:
	var r := _boss_r()
	var s1 := _hole("boss", r, 1)
	var s4 := _hole("boss", r, 4)
	var ch := Rect2(s1.position, Vector2(s4.end.x - s1.position.x, s1.size.y))   # канал здоровья под медальоном — целый
	var hp := clampf(float(e.get("hp", 1.0)), 0.0, 1.0)
	var broken := bool(e.get("broken", false))
	var c := clampf(float(e.get("conc", 1.0)), 0.0, 1.0)
	var top := Rect2(ch.position, Vector2(ch.size.x, ch.size.y * 0.68))
	var bot := Rect2(ch.position + Vector2(0, ch.size.y * 0.72), Vector2(ch.size.x, ch.size.y * 0.28))
	_fill(top, hp, CRIMSON2, _eg)
	_fill(bot, c, Color(1.0, 0.2, 0.15) if broken else AMBER2, -1.0, true)   # концентрация — тонкая, от середины
	for k: int in [1, 2]:                                 # трети здоровья — три фазы
		var xk := ch.position.x + ch.size.x * k / 3.0
		draw_line(Vector2(xk, top.position.y), Vector2(xk, top.end.y), Color(0, 0, 0, 0.5), 2.0)
	var md := _hole("boss", r, 0)
	var mc := md.get_center()
	var mr := minf(md.size.x, md.size.y) * 0.5 + 2.0
	_disc(mc, mr, null, Color(0.2, 0.02, 0.05, 1.0))
	_disc(mc, mr, portrait)
	_tex_frame("boss", r)
	var nw := float((_cfg.get("boss_name", {}) as Dictionary).get("size", 380.0))
	var nr := _frame("boss_name", (_w - nw) * 0.5, 236.0)
	_tex_frame("boss_name", nr)
	_txt(nr.get_center() + Vector2(0, -3), str(e.get("name", "")), _f_serif, 30, IVORY, nr.size.x * 0.72)
	var title := str(e.get("title", ""))
	if broken:
		title = _tr("pax_rpg_hud_broken")
	if title != "":
		_txt(Vector2(_w * 0.5, nr.end.y + 14.0), title.to_upper(), _f_sc, 16, CRIMSON_HI if broken else Color(0.85, 0.68, 0.45), 600.0)
	var ph := int(e.get("phase", 0))
	for k: int in 3:                                      # фазы — три ромба под медальоном
		var dc := Vector2(_w * 0.5 + (k - 1) * 18.0, md.end.y + 14.0)
		draw_colored_polygon(_diamond(dc, 5.0), CRIMSON2 if k >= ph else Color(0.25, 0.2, 0.2))
		_outline(_diamond(dc, 5.0), Color(1.0, 0.85, 0.55), 1.0)


# ---------- компас ----------

func _draw_cmp2() -> void:
	if st.is_empty() or _cfg.is_empty():
		return
	_ci = _cmp2
	_txt_k = 1.0
	_cmp2.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	var r := _compass_r()
	var ch := _hole("compass", r, 0)
	_cmp2.draw_rect(ch.grow(1.0), Color(0.08, 0.024, 0.035, 0.92))
	var yaw := float(_g("yaw", 0.0))
	var cx := ch.get_center().x
	var cy := ch.get_center().y
	var half := ch.size.x * 0.5
	var at := func(deg: float) -> float:                 # курс (С 0, В 90…) → x; NAN — за краем
		var rel := wrapf(deg_to_rad(-deg) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5 - 0.04:
			return NAN
		return cx - rel / (PI * 0.5) * half
	for a: int in range(0, 360, 15):
		if a % 45 == 0:
			continue
		var x: float = at.call(float(a))
		if not is_nan(x):
			_cmp2.draw_line(Vector2(x, ch.end.y - 5.0), Vector2(x, ch.end.y - 1.0), Color(0.59, 0.41, 0.22, 0.8), 1.0)
	var pts := [[0, "С", true], [45, "СВ", false], [90, "В", true], [135, "ЮВ", false], [180, "Ю", true], [225, "ЮЗ", false],
		[270, "З", true], [315, "СЗ", false]]
	if mod != null and mod.tr_key("pax_rpg_map_legend") != "Легенда":
		pts = [[0, "N", true], [45, "NE", false], [90, "E", true], [135, "SE", false], [180, "S", true], [225, "SW", false],
			[270, "W", true], [315, "NW", false]]
	for pv: Variant in pts:
		var p: Array = pv
		var x: float = at.call(float(p[0]))
		if is_nan(x):
			continue
		var big := bool(p[2])
		var col := CRIMSON_HI if int(p[0]) == 0 else (IVORY if big else Color(0.78, 0.69, 0.55))
		var edge := 1.0 - smoothstep(0.75, 1.0, absf(x - cx) / half)
		_center(Vector2(x, cy - 1.0), str(p[1]), _f_sc, 21 if big else 16, Color(col, edge), 0, 60.0)
	for t: Variant in _g("targets", []):
		var td: Dictionary = t
		var rel := wrapf(float(td.yaw) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5 - 0.04:
			continue
		var x := cx - rel / (PI * 0.5) * half
		var col: Color = td.color
		if bool(td.get("ring", false)):
			_cmp2.draw_arc(Vector2(x, cy), 5.0, 0.0, TAU, 20, col, 2.0, true)
		else:
			var dm := _diamond(Vector2(x, cy), 6.5)
			_cmp2.draw_colored_polygon(dm, col)
			_outline(dm, Color(0.08, 0.02, 0.02), 1.0)
	if CityMap.pin.x != INF:                              # метка с карты города — флажок
		var d: Vector2 = CityMap.pin - (_g("me", Vector2.ZERO) as Vector2)
		var rel := wrapf(atan2(-d.x, -d.y) - yaw, -PI, PI)
		if absf(rel) <= PI * 0.5 - 0.04:
			var x := cx - rel / (PI * 0.5) * half
			_cmp2.draw_line(Vector2(x, cy + 8.0), Vector2(x, cy - 8.0), Color(1.0, 0.85, 0.55), 1.5, true)
			_cmp2.draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 8.0), Vector2(x + 9.0, cy - 5.0), Vector2(x, cy - 2.0)]),
				CRIMSON_HI)
	_ci = self


# ---------- миникарта ----------

func _draw_mask() -> void:
	var r := _mini_circle().z * _s
	_mask.draw_circle(Vector2(r + 2.0 * _s, r + 2.0 * _s), r, Color(0.16, 0.1, 0.07))


## Миникарта: север вверху; план города (запечённый) или коробки построек; враги, герой — стрелка по повороту тела.
func _draw_map() -> void:
	if st.is_empty():
		return
	var rad := _mini_circle().z * _s
	var c := Vector2(rad + 2.0 * _s, rad + 2.0 * _s)
	var k := rad / MINI_M                                 # px экрана на метр
	var me: Vector2 = _g("me", Vector2.ZERO)
	var to_map := func(w: Vector2) -> Vector2:
		return c + (w - me) * k
	if _mini_tex != null:
		var a: Vector2 = to_map.call(_mini_rect.position)
		_map.draw_texture_rect(_mini_tex, Rect2(a, _mini_rect.size * k), false)
	else:
		var rects: Array = _g("map_rects", [])
		if _map_mesh == null or _map_n != rects.size():
			_map_mesh = _rects_mesh(rects)
			_map_n = rects.size()
		if _map_mesh != null:
			_map.draw_set_transform_matrix(Transform2D(Vector2(k, 0), Vector2(0, k), c - me * k))
			_map.draw_mesh(_map_mesh, null)
			_map.draw_set_transform_matrix(Transform2D.IDENTITY)
		_map.draw_arc(to_map.call(_g("gate", Vector2.ZERO)), 7.0 * _s, 0.0, TAU, 20, Color(0.47, 0.84, 1.0), 2.0 * _s, true)
	for e: Variant in _g("enemies", []):
		var ed: Dictionary = e
		var p: Vector2 = to_map.call(ed.pos)
		var dm := PackedVector2Array()
		for v: Vector2 in _diamond(p, 5.0 * _s):
			dm.append(v)
		_map.draw_colored_polygon(dm, CRIMSON_HI if bool(ed.get("locked", false)) else CRIMSON2)
		_map.draw_polyline(dm + PackedVector2Array([dm[0]]), Color(0.1, 0.0, 0.0), 1.0 * _s, true)
	if CityMap.pin.x != INF:                              # метка с карты города
		var pp: Vector2 = to_map.call(CityMap.pin)
		_map.draw_line(pp, pp + Vector2(0, -16) * _s, Color(1.0, 0.85, 0.55), 1.5 * _s, true)
		_map.draw_colored_polygon(PackedVector2Array([pp + Vector2(0, -16) * _s, pp + Vector2(10, -12) * _s, pp + Vector2(0, -8) * _s]),
			CRIMSON_HI)
	var body := float(_g("body_yaw", _g("yaw", 0.0)))
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -11), Vector2(8, 9), Vector2(0, 4), Vector2(-8, 9)]:
		arrow.append(c + v.rotated(-body) * _s)
	_map.draw_colored_polygon(arrow, Color(1.0, 0.91, 0.7))
	_map.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0.35, 0.08, 0.08), 1.2 * _s, true)


## Рамка миникарты, золото и монета — над картой (слой _coin рисуется после круга _mask).
func _draw_coin() -> void:
	if st.is_empty() or _cfg.is_empty():
		return
	_coin.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	var r := _mini_r()
	var t: Texture2D = _ftex.get("minimap")
	var plate := _hole("minimap", r, 1)
	var sock := _hole("minimap", r, 2)
	_coin.draw_rect(plate.grow(2.0), WELL)
	if t != null:
		_coin.draw_texture_rect(t, r, false)
	var fl := float(_g("gold_flash", 0.0))
	var s := _thousands(int(_g("gold", 0)))
	var fs := 22
	var tw := _f_sc.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(plate.get_center().x - minf(tw, plate.size.x) * 0.5, plate.get_center().y + fs * 0.32)
	_coin.draw_string_outline(_f_sc, pos, s, HORIZONTAL_ALIGNMENT_LEFT, plate.size.x, fs, 3, Color(0.05, 0.02, 0.02, 0.9))
	_coin.draw_string(_f_sc, pos, s, HORIZONTAL_ALIGNMENT_LEFT, plate.size.x, fs, IVORY.lerp(Color(1.0, 0.85, 0.5), fl))
	coin(_coin, sock.get_center(), minf(sock.size.x, sock.size.y) * 0.5, Time.get_ticks_msec() * 0.001, fl)


func _draw_hint() -> void:
	var a := float(_g("hint_a", 0.0))
	if a > 0.01:
		var y := 290.0
		var width := minf(900.0, _w - 140.0 - 320.0)        # правее панели врага, не под миникартой
		for line: String in str(_g("hint", "")).split("\n"):
			for part: String in _wrap(line, width, 14):
				_text(Vector2(140, y), part, sans, 14, Color(IVORY_DIM, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
				y += 22.0
	var g := str(_g("gate_hint", ""))
	if g != "":
		_center(Vector2(_w * 0.5, _h - 250.0), g, _f_serif, 24, IVORY, 5, 900.0)
