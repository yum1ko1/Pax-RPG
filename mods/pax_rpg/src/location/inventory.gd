extends Control
## Инвентарь (TAB) — экран из прототипа pax_rpg/reference/inventory/tooltip_prototype (макет 1536 × 1024, масштаб под
## экран): в центре арт Тянь Лун (копьё / катана — по основному оружию), над ней пассив, под ней круги ранга и
## репутации; слева окна оружия (основное, второе, медальон смены) с приёмами; справа 8 слотов снаряжения и
## характеристики. Наведение на вещь — подсказка вещи, держать курсор 1,2 с — она закрепляется (кольцо в углу), тогда
## статы и бонусы сета раскрывают мини-подсказки. Клик по слоту — выбор вещи, по окну оружия — выбор оружия.
## Пока только показ: вещи и оружие на бой не влияют (сумка — inv/equip.gd, надетое — настройка inv_equipped).
## Мир на паузе, пока открыт (location.gd).

signal closed
signal weapon_equipped(slot: String, id: String)   # совместимость с location.gd (в этом экране бой не меняется)
signal stat_added(key: String)       # «+» у характеристики — вложить очко (location.gd → progress.add_stat)

const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")
const Equip := preload("res://mods/pax_rpg/src/location/inv/equip.gd")
const ItemTip := preload("res://mods/pax_rpg/src/location/inv/item_tip.gd")
const InfoTip := preload("res://mods/pax_rpg/src/location/inv/info_tip.gd")
const W := 1536.0
const H := 1024.0
const TK := 1.25                     # окна выбора вещи / оружия: пиксели прототипа → единицы макета
const TIP_K := 1.0                   # подсказки (выше экрана — ещё уменьшаются, см. _tk)
const PIN_S := 1.2                   # держать курсор на вещи, чтобы закрепить подсказку
const WSLOTS := [{"name": "Основное оружие", "tag": "ОСНОВНОЕ", "rect": [377, 150, 522, 411], "ui": [370, 321, 556, 418], "sk": [460, 333.5, 515.5, 393]},
	{"name": "Второе оружие", "tag": "ВТОРОЕ", "rect": [377, 417, 522, 650], "ui": [370, 561, 556, 657], "sk": [460, 574, 515.5, 633.5]}]
const HERO_PANEL := [548, 138, 938, 928]
const SWAP_AT := Vector2(413, 414)
const PAS_RECT := [575, 163, 635, 225]
const RANK_RECT := [598, 793, 706, 901]
const REP_RECT := [776, 793, 884, 901]
const GOLD_PLAQUE := [636, 663, 846, 710]          # плашки золота и уровня (на макете)
const LVL_PLAQUE := [616, 708, 867, 760]
const ATTR_Y := [245, 307, 365, 427, 495, 565, 635]
const ATTR_X := [1330, 1505]

var mod: PaxMod
var ui := Ui.new()
var eq := Equip.new()
var _frame: Control
var _st: Dictionary = {}
var _lvl := 1
var _attrs: Dictionary = {}
var _points := 0
var _weapons: Array = ["spear", "katana"]          # [основное, второе]
var _slot_art: Array = []                          # узлы картинок в слотах снаряжения
var _hero_k: TextureRect                           # арт с катаной поверх арта с копьём
var _wicons: Array = []
var _wsk: Array = []
var _rank_pic: TextureRect
var _rep_pic: TextureRect
var _attr_box: Control
var _gold_l: Label
var _lvl_l: Label
var _layer: Control                                # окна подсказок и выбора — поверх всего, масштаб TK
# подсказка: одна на экран (вещь или описание)
var _tip: Control = null
var _tip_id := ""
var _tk := TIP_K
var _hold := 0.0
var _pinned := false
var _inside_t := 0.0
var _mini: Control
var _mini_key := ""
var _menu: Control = null
var _menu_id := ""
var _menu_tiles: Array = []                        # [{rect, id, cb}]
var _menu_cap: Label
var _rel: Dictionary = {}                          # отношения империй (−100…+100)
var _progress := {"combo": 0, "leg": 0, "night": 0}


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgInventory"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	ui.setup(m)
	eq.load_data(m)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.015, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	ui.pic(_frame, "stage.jpg", Rect2(0, 0, W, H), false)
	_hero_k = ui.pic(_frame, "hero_katana.jpg", _r(HERO_PANEL), false)
	_hero_k.modulate.a = 0.0
	_build_weapons()
	_build_slots()
	ui.pic(_frame, "pas_dance.jpg", _r(PAS_RECT), false)
	_rank_pic = ui.pic(_frame, "rank_0.png", _r(RANK_RECT))
	_rep_pic = ui.pic(_frame, "rep_2.png", _r(REP_RECT))
	_gold_l = ui.label(_frame, "0", ui.serif, 22, Color(0.95, 0.84, 0.55), Vector2.ZERO)
	_lvl_l = ui.label(_frame, "", ui.serif, 22, Ui.TEXT, Vector2.ZERO)
	_attr_box = Control.new()
	_attr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_attr_box)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_layer)
	_mini = Control.new()
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.visible = false
	_mini.scale = Vector2(TIP_K, TIP_K)
	_mini.z_index = 20
	_frame.add_child(_mini)
	# подсказка внизу слева — как в прототипе: плашка с тонкой золотой рамкой
	var ht := "Наведите на вещь — подсказка, клик — выбрать другую"
	var hf := ui.caps(12, 0.1)
	var hw := ui.text_w(ht, hf, 12) + 18
	var hb := Control.new()
	hb.position = Vector2(W * 0.012, H * (1.0 - 0.016) - 26)
	hb.size = Vector2(hw, 26)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.draw.connect(func() -> void:
		hb.draw_rect(Rect2(Vector2.ZERO, hb.size), Color(0.04, 0.024, 0.027, 0.72))
		hb.draw_rect(Rect2(Vector2.ZERO, hb.size), Ui.GOLD_DIM, false, 1.0))
	_frame.add_child(hb)
	ui.label(hb, ht, hf, 12, Ui.TEXT, Vector2(9, 5))
	resized.connect(_fit)


func _center(l: Label, a: Array) -> void:
	var r := _r(a)
	l.size = ui.serif.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size"))
	l.position = r.get_center() - l.size * 0.5


func _r(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]) - float(a[0]), float(a[3]) - float(a[1]))


func _fit() -> void:
	var s := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(s, s)
	_frame.position = (size - Vector2(W, H) * s) * 0.5


## Экран закрыт целиком (непрозрачный фон под макетом) — location.gd тогда не рисует 3D-мир под инвентарём.
func covers_screen() -> bool:
	return visible


## Открыть: st — те же числа, что у HUD (level, attributes, stat_points, gold, main_stat…).
func open(_view: SubViewport, _player: Node3D, _body: Node3D, _hero: Object, st: Dictionary) -> void:
	_st = st
	_lvl = maxi(1, int(st.get("level", 1)))
	_attrs = (st.get("attributes", {}) as Dictionary).duplicate()
	_points = int(st.get("stat_points", 0))
	var loot: Variant = mod.get_setting("inv_loot", [])
	eq.build_bag(_lvl, loot if loot is Array else [])
	var saved: Variant = mod.get_setting("inv_equipped", [])
	eq.equipped = []
	for k: int in eq.slots.size():
		var id := "samurai-%d" % int((eq.slots[k] as Dictionary)["demo"])
		if saved is Array and k < (saved as Array).size() and not eq.find(k, str((saved as Array)[k])).is_empty():
			id = str((saved as Array)[k])
		eq.equipped.append(id)
	var ws: Variant = mod.get_setting("inv_weapons", [])
	_weapons = (ws as Array).duplicate() if ws is Array and (ws as Array).size() == 2 else ["spear", "katana"]
	var rel: Variant = mod.get_setting("reputation", {})
	_rel = rel if rel is Dictionary else {}
	_close_tip()
	_close_menu()
	_refresh()
	visible = true
	_fit()


func back() -> bool:
	if _menu != null:
		_close_menu()
		return true
	if _tip != null and _pinned:
		_close_tip()
		return true
	return false


func close() -> void:
	_close_tip()
	_close_menu()
	visible = false
	closed.emit()


func _refresh() -> void:
	_refresh_slots()
	_refresh_weapons()
	_rank_pic.texture = ui.tex("rank_%d.png" % _rank())
	_rep_pic.texture = ui.tex("rep_%d.png" % InfoTip.tier_of(eq.d["rep_tiers"], _rep_total()))
	_gold_l.text = Equip.money(int(_st.get("gold", 0)))
	_lvl_l.text = str(_lvl)
	_center(_gold_l, GOLD_PLAQUE)                            # по центру плашек под героем
	_center(_lvl_l, LVL_PLAQUE)
	_build_attrs()


# ── снаряжение
func _build_slots() -> void:
	for k: int in eq.slots.size():
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.clip_contents = true
		var r := _r((eq.slots[k] as Dictionary)["rect"])
		c.position = r.position
		c.size = r.size
		_frame.add_child(c)
		_slot_art.append(c)


func _refresh_slots() -> void:
	for k: int in eq.slots.size():
		var c: Control = _slot_art[k]
		for n: Node in c.get_children():
			c.remove_child(n)
			n.queue_free()
		var it: Dictionary = eq.item_at(k)
		if it.is_empty():
			continue
		var bg := ColorRect.new()
		bg.color = Color(0.07, 0.04, 0.045)
		bg.size = c.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(bg)
		ui.item_icon(c, str((eq.sets[it["set"]] as Dictionary)["sheet"]), eq.cell(str(it["set"]), k, int(it["r"])), Rect2(Vector2.ZERO, c.size))
		var rc: Color = eq.rc(int(it["r"]))
		var b := Control.new()
		b.size = c.size
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.draw.connect(func() -> void: Ui.rarity_border(b, Rect2(Vector2.ZERO, c.size), rc, 0.75))
		c.add_child(b)
		if bool(it.get("mana", false)):
			var mw := 17.0
			var box := ui.frame(c, "mana_rim.png", [76, 76, 76, 76], mw / 76.0, Rect2(Vector2.ZERO, c.size))
			(box.get_meta(&"np") as NinePatchRect).draw_center = false


# ── оружие
func _build_weapons() -> void:
	for w: int in 2:
		var ws: Dictionary = WSLOTS[w]
		var r := _r(ws["rect"])
		ui.pic(_frame, "wpn_bg.jpg", r, false)
		var ic := ui.pic(_frame, "wpn_spear.png", r.grow_individual(-r.size.x * 0.04, -r.size.y * 0.03, -r.size.x * 0.04, -r.size.y * 0.03))
		_wicons.append(ic)
		ui.pic(_frame, "wui_%d.png" % (w + 1), _r(ws["ui"]), false)
		var sk := ui.pic(_frame, "sk_sunset.jpg", _r(ws["sk"]), false)
		_wsk.append(sk)
		ui.label(_frame, str(ws["tag"]), ui.caps(12, 0.12), 12, Ui.GOLD, r.position + Vector2(9, 8), 0.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0, 0, 0, 0.9))
	var swap := Control.new()
	swap.position = SWAP_AT - Vector2(16, 16)
	swap.size = Vector2(32, 32)
	swap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swap.draw.connect(func() -> void:
		var c := Vector2(16, 16)
		swap.draw_circle(c, 15, Color(0.04, 0.02, 0.03, 0.9))
		swap.draw_circle(c, 13, Color(0.12, 0.07, 0.05))
		swap.draw_arc(c, 13, 0, TAU, 32, Color(0.85, 0.7, 0.42), 1.6)
		var g := Color(0.94, 0.81, 0.54)
		swap.draw_line(Vector2(12, 8), Vector2(12, 23), g, 2.0)
		swap.draw_polyline(PackedVector2Array([Vector2(8, 19), Vector2(12, 23), Vector2(16, 19)]), g, 2.0)
		swap.draw_line(Vector2(20, 24), Vector2(20, 9), g, 2.0)
		swap.draw_polyline(PackedVector2Array([Vector2(16, 13), Vector2(20, 9), Vector2(24, 13)]), g, 2.0))
	_frame.add_child(swap)


func _skill_of(w: int) -> Array:
	return (((eq.d["weapons"] as Dictionary)[_weapons[w]] as Dictionary)["skills"] as Array)[w]


func _refresh_weapons() -> void:
	for w: int in 2:
		var wp: Dictionary = (eq.d["weapons"] as Dictionary)[_weapons[w]]
		(_wicons[w] as TextureRect).texture = ui.tex(str(wp["icon"]))
		(_wsk[w] as TextureRect).texture = ui.tex(str(((eq.d["skills"] as Dictionary)[_skill_of(w)[0]] as Dictionary)["icon"]))
	var tw := create_tween()
	tw.tween_property(_hero_k, "modulate:a", 1.0 if _weapons[0] == "katana" else 0.0, 0.45)


## Одно и то же оружие не может стоять в обоих слотах: выбор оружия из другого слота меняет их местами.
func _choose_weapon(w: int, key: String) -> void:
	if _weapons[w] == key:
		return
	if _weapons[1 - w] == key:
		_weapons[1 - w] = _weapons[w]
	_weapons[w] = key
	mod.set_setting("inv_weapons", _weapons.duplicate())
	for n: Variant in _wicons + _wsk:
		var t := create_tween()
		t.tween_property(n, "modulate:a", 0.0, 0.17)
		t.tween_callback(_refresh_weapons)
		t.tween_property(n, "modulate:a", 1.0, 0.22)


# ── характеристики (правая панель: 7 строк со значками на макете)
func _build_attrs() -> void:
	for n: Node in _attr_box.get_children():
		_attr_box.remove_child(n)
		n.queue_free()
	var main := str(_st.get("main_stat", ""))
	var names: Array = eq.d.get("attributes", [])
	for i: int in mini(names.size(), ATTR_Y.size()):
		var key := str(names[i][0])
		var y := float(ATTR_Y[i])
		ui.label(_attr_box, str(names[i][1]) + (" ★" if key == main else ""), ui.serif, 15, Color(0.94, 0.81, 0.54) if key == main else Ui.TEXT,
			Vector2(ATTR_X[0], y - 12))
		var v := ui.label(_attr_box, str(int(_attrs.get(key, 0))), ui.serif, 20, Color(1.0, 0.95, 0.86), Vector2.ZERO)
		v.position = Vector2(ATTR_X[1] - v.size.x, y - 14)
		if _points > 0:
			var b := Button.new()
			b.text = "+"
			b.flat = true
			b.add_theme_font_override("font", ui.serif)
			b.add_theme_font_size_override("font_size", 20)
			b.add_theme_color_override("font_color", Color(0.94, 0.81, 0.54))
			b.position = Vector2(ATTR_X[1] - 58, y - 16)
			b.size = Vector2(26, 30)
			b.pressed.connect(func() -> void: stat_added.emit(key))
			_attr_box.add_child(b)
	if _points > 0:
		ui.label(_attr_box, "Свободных очков: %d" % _points, ui.body, 12, Color(0.94, 0.81, 0.54), Vector2(ATTR_X[0] + 40, 651))


# ── ранг и репутация
func _rep_total() -> int:
	var t := 0
	var emp: Array = eq.d["empires"]
	for e: Dictionary in emp:
		t += int(_rel.get(e["key"], 0))
	return roundi(float(t) / maxf(1.0, emp.size()))


func _rank_state() -> Dictionary:
	var lo := 5
	var mana := 0
	for k: int in eq.slots.size():
		var it: Dictionary = eq.item_at(k)
		lo = mini(lo, int(it.get("r", 0)))
		if int(it.get("r", 0)) == 5 and bool(it.get("mana", false)):
			mana += 1
	return {"rar": lo, "mana": mana, "lvl": _lvl, "combo": int(_progress["combo"]), "leg": int(_progress["leg"]), "night": int(_progress["night"])}


func _rank() -> int:
	var st := _rank_state()
	var ranks: Array = eq.d["ranks"]
	var cur := 0
	var probe := InfoTip.new()
	probe.eq = eq
	for i: int in range(1, ranks.size()):
		var ok := true
		for q: Array in probe.req_rows(ranks[i], st):
			ok = ok and bool(q[0])
		if not ok:
			break
		cur = i
	probe.free()
	return cur


# ── наведение и закрепление (по геометрии: окна подсказок курсор не ловят, кроме закреплённого)
func _sockets() -> Array:
	var out: Array = []
	for k: int in eq.slots.size():
		out.append(["slot:%d" % k, _r((eq.slots[k] as Dictionary)["rect"])])
	for w: int in 2:
		out.append(["wsk:%d" % w, _r(WSLOTS[w]["sk"])])
	out.append(["pas", _r(PAS_RECT)])
	out.append(["rank", _r(RANK_RECT)])
	out.append(["rep", _r(REP_RECT)])
	return out


func _socket_at(p: Vector2) -> Array:
	for s: Array in _sockets():
		if (s[1] as Rect2).has_point(p):
			return s
	return []


func _tip_rect() -> Rect2:
	return Rect2(_tip.position, _tip.size * _tk) if _tip != null else Rect2()


func _process(delta: float) -> void:
	if not visible:
		return
	var p := _frame.get_local_mouse_position()
	if _menu != null:
		_menu_hover(p)
		return
	var s := _socket_at(p)
	var sid: String = s[0] if not s.is_empty() else ""
	if _tip != null and _pinned:
		var inside := _tip_rect().has_point(p) or sid == _tip_id
		if inside:
			_inside_t = 0.0
		else:
			_inside_t += delta
			if sid != "" and sid != _tip_id:
				_open_tip(s)
				return
			elif _inside_t > 0.06:
				_close_tip()
				return
		_mini_hover(p)
		_pulse()
		return
	if sid == "":
		if _tip != null:
			_inside_t += delta
			if _inside_t > 0.03:
				_close_tip()
		return
	_inside_t = 0.0
	if sid != _tip_id:
		_open_tip(s)
	_hold += delta
	_set_arm(clampf(_hold / PIN_S, 0.0, 1.0))
	if _hold >= PIN_S:
		_pinned = true
		_set_pinned(true)
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_arm(v: float) -> void:
	if _tip is ItemTip:
		(_tip as ItemTip).set_arm(v)
	elif _tip is InfoTip:
		(_tip as InfoTip).set_arm(v)


func _set_pinned(on: bool) -> void:
	if _tip is ItemTip:
		(_tip as ItemTip).set_pinned(on)
	elif _tip is InfoTip:
		(_tip as InfoTip).set_pinned(on)


func _pulse() -> void:
	var g: Variant = _tip.get("glow")
	if g is Control:
		var t := Time.get_ticks_msec() / 1000.0
		(g as Control).modulate.a = 0.55 + 0.35 * sin(t * TAU / 2.6)


func _open_tip(s: Array) -> void:
	_close_tip()
	var sid: String = s[0]
	var anchor: Rect2 = s[1]
	_tip_id = sid
	_hold = 0.0
	_pinned = false
	_inside_t = 0.0
	if sid.begins_with("slot:"):
		var k := int(sid.substr(5))
		var tip := ItemTip.new()
		_layer.add_child(tip)
		tip.build(ui, eq, eq.item_at(k), k, _lvl, eq.d.get("passive", {}))
		_tip = tip
	else:
		var tip := InfoTip.new()
		_layer.add_child(tip)
		tip.on_meta = _on_meta
		if sid.begins_with("wsk:"):
			var w := int(sid.substr(4))
			var sk := _skill_of(w)
			tip.build_skill(ui, eq, str(sk[0]), str(sk[1]), "%s приём · %s" % ["Второй" if w == 1 else "Основной",
				((eq.d["weapons"] as Dictionary)[_weapons[w]] as Dictionary)["name"]], _lvl, _hero_attrs())
		elif sid == "pas":
			tip.build_passive(ui, eq)
		elif sid == "rep":
			tip.build_rep(ui, eq, _rel)
		else:
			tip.build_rank(ui, eq, _rank(), _rank_state())
		_tip = tip
	_tk = minf(TIP_K, (H - 16.0) / maxf(1.0, _tip.size.y))
	_tip.scale = Vector2(_tk, _tk)
	_place(_tip, anchor, _tk)
	_tip.modulate.a = 0.0
	var to_y := _tip.position.y
	_tip.position.y += 6
	var tw := create_tween().set_parallel()
	tw.tween_property(_tip, "modulate:a", 1.0, 0.24).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tip, "position:y", to_y, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Окно — вплотную слева от того, на что навели (не влезает — справа), по высоте — в пределах макета.
func _place(c: Control, anchor: Rect2, k: float) -> void:
	var sz := c.size * k
	var x := anchor.position.x - sz.x - 6
	if x < 8:
		x = anchor.end.x + 6
	var y := clampf(anchor.position.y - 8, 8, H - sz.y - 8)
	c.position = Vector2(x, y)


func _close_tip() -> void:
	if _tip != null:
		_tip.queue_free()
	_tip = null
	_tip_id = ""
	_pinned = false
	_hold = 0.0
	_hide_mini()


func _hero_attrs() -> Dictionary:
	var a := _attrs.duplicate()
	var syn: Dictionary = (eq.d.get("passive", {}) as Dictionary).get("synergy", {})
	if _weapons[0] == str(syn.get("weapon", "")):
		a["agility"] = roundi(float(a.get("agility", 0)) * float(syn.get("agi", 1.0)))
	return a


# ── мини-подсказки (у закреплённой)
func _mini_hover(p: Vector2) -> void:
	var local := (p - _tip.position) / _tk
	var key := ""
	var data: Array = []
	if _tip is ItemTip:
		for l: Dictionary in (_tip as ItemTip).lines:
			if (l["rect"] as Rect2).has_point(local):
				key = "%s:%d" % [l["part"], l["j"]]
				var k := int(_tip_id.substr(5))
				data = (_tip as ItemTip).mini_text(eq.item_at(k), str(l["part"]), int(l["j"]), eq.d.get("passive", {}))
				data.append(l["rect"])
	elif _tip is InfoTip:
		for h: Dictionary in (_tip as InfoTip).hovers:
			if (h["rect"] as Rect2).has_point(local):
				key = "%s:%s" % [h["kind"], h["arg"]]
				data = _hover_info(str(h["kind"]), int(h["arg"]))
				data.append(h["rect"])
	if key == "" and _mini_key.begins_with("meta:"):
		return                                             # разбор числа держится, пока курсор на числе (meta_hover_ended)
	if key == _mini_key:
		return
	_mini_key = key
	if key == "":
		_hide_mini()
		return
	_show_mini(data)


func _on_meta(kind: String, arg: String, on: bool, _grect: Rect2) -> void:
	if not _pinned or not (_tip is InfoTip):
		return
	if not on:
		if _mini_key.begins_with("meta:"):
			_mini_key = ""
			_hide_mini()
		return
	_mini_key = "meta:%s:%s" % [kind, arg]
	var b: Array = (_tip as InfoTip).breakdown(kind, arg, _lvl, _hero_attrs())
	var local := (_frame.get_local_mouse_position() - _tip.position) / _tk
	_show_mini([b[0], b[1], "", Ui.GOLD, "", b[2], Rect2(local - Vector2(4, 10), Vector2(8, 20))])


## [заголовок, текст, «здесь», цвет, метка, (строки таблицы), rect строки в окне]
func _show_mini(data: Array) -> void:
	for n: Node in _mini.get_children():
		_mini.remove_child(n)
		n.queue_free()
	var w := 270.0
	var fr := ui.frame(_mini, "frame_mini.png", [28, 28, 28, 28], 0.5, Rect2(0, 0, w, 100))
	var y := 14.0
	var tl := ui.label(_mini, str(data[0]).to_upper(), ui.caps(14, 0.1), 14, Ui.TEXT, Vector2(14, y), w - 28)
	y += tl.size.y + 4
	if str(data[1]) != "":
		var dl := ui.label(_mini, str(data[1]), ui.body, 13, Ui.MUTED, Vector2(14, y), w - 28)
		y += dl.size.y + 4
	var rows: Array = data[5] if data.size() > 6 and data[5] is Array else []
	for row: Array in rows:
		var hl := row.size() > 2 and bool(row[2])
		var a := ui.label(_mini, str(row[0]), ui.body, 12, Color(0.94, 0.81, 0.54) if hl else Ui.MUTED, Vector2(14, y), w * 0.55)
		var b := ui.label(_mini, str(row[1]), ui.serif, 12, Color(0.94, 0.81, 0.54) if hl else Ui.TEXT, Vector2.ZERO, w * 0.42, HORIZONTAL_ALIGNMENT_RIGHT)
		b.position = Vector2(w - 14 - w * 0.42, y)
		y += maxf(a.size.y, b.size.y) + 2
	if str(data[2]) != "":
		var hl2 := ui.label(_mini, str(data[2]), ui.serif, 13, Ui.TEXT, Vector2(14, y + 3), w - 28)
		y += hl2.size.y + 5
	if str(data[4]) != "":
		var tg := ui.label(_mini, str(data[4]), ui.body, 12, data[3], Vector2(14, y + 2), w - 28)
		y += tg.size.y + 4
	Ui.frame_resize(fr, Vector2(w, y + 12))
	_mini.size = Vector2(w, y + 12)
	var line: Rect2 = data[data.size() - 1]
	var tr := _tip_rect()
	var x := tr.position.x - w * TIP_K - 10
	if x < 4:
		x = tr.end.x + 10
	var top := clampf(tr.position.y + line.position.y * _tk - 8, 4, H - _mini.size.y * TIP_K - 4)
	_mini.position = Vector2(x, top)
	_mini.visible = true


func _hide_mini() -> void:
	_mini_key = ""
	if is_instance_valid(_mini):
		_mini.visible = false


func _hover_info(kind: String, i: int) -> Array:
	if kind == "emp":
		var e: Dictionary = (eq.d["empires"] as Array)[i]
		var tiers: Array = eq.d["rep_tiers"]
		var v := int(_rel.get(e["key"], 0))
		return [e["name"], "", "", Ui.GOLD, "", [["Столица", e["cap"]], ["Правит", e["rule"]], ["Народы", e["folk"]], ["Не выносят", e["hate"]],
			["Отношение к вам", "%s · %s" % [InfoTip.sgn(v), (tiers[InfoTip.tier_of(tiers, v)] as Dictionary)["name"]], true]]]
	if kind == "tier":
		var tiers2: Array = eq.d["rep_tiers"]
		var T: Dictionary = tiers2[i]
		var hi := int((tiers2[i + 1] as Dictionary)["min"]) - 1 if i + 1 < tiers2.size() else 100
		return [T["name"], str(T["info"]), "", Ui.GOLD, "", [["Отношение", "%s … %s" % [InfoTip.sgn(int(T["min"])), InfoTip.sgn(hi)]]]]
	var ranks: Array = eq.d["ranks"]
	var R: Dictionary = ranks[i]
	var cur := _rank()
	var rows: Array = []
	var probe := _tip as InfoTip
	for q: Array in probe.req_rows(R, _rank_state()):
		rows.append([("✓ " if q[0] else "✕ ") + str(q[1]), ""])
	var status := "Пройден" if i < cur else ("Ваш ранг" if i == cur else ("Следующий ранг" if i == cur + 1 else "Впереди"))
	return ["Ранг %d: %s" % [i, R["name"]], "Со старта, без условий." if rows.is_empty() else "", status + (" · условия всех младших рангов тоже нужны" if i > 0 else ""),
		Ui.MUTED, "", rows]


# ── выбор вещи / оружия
func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not (e as InputEventMouseButton).pressed or (e as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var p := _frame.get_local_mouse_position()
	accept_event()
	if _menu != null:
		for t: Dictionary in _menu_tiles:
			if (t["rect"] as Rect2).has_point(p):
				(t["cb"] as Callable).call()
				return
		if not Rect2(_menu.position, _menu.size * TK).has_point(p):
			_close_menu()
		return
	var was_pinned := _pinned
	if _pinned:
		_close_tip()
	if Rect2(SWAP_AT - Vector2(16, 16), Vector2(32, 32)).has_point(p):
		_choose_weapon(0, _weapons[1])
		return
	for k: int in eq.slots.size():
		if _r((eq.slots[k] as Dictionary)["rect"]).has_point(p):
			_close_tip()
			_open_item_menu(k)
			return
	for w: int in 2:
		if _r(WSLOTS[w]["rect"]).has_point(p) or _r(WSLOTS[w]["sk"]).has_point(p):
			_close_tip()
			_open_weapon_menu(w)
			return
	if not was_pinned:
		_close_tip()


func _close_menu() -> void:
	if _menu != null:
		_menu.queue_free()
	_menu = null
	_menu_id = ""
	_menu_tiles = []


func _menu_box(title: String, sub: String, w: float) -> Control:
	_close_menu()
	_menu = Control.new()
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.scale = Vector2(TK, TK)
	_menu.z_index = 15
	_layer.add_child(_menu)
	_menu.set_meta(&"fr", ui.frame(_menu, "frame_mini.png", [28, 28, 28, 28], 0.5, Rect2(0, 0, w, 100)))
	ui.label(_menu, title.to_upper(), ui.caps(16, 0.12), 16, Ui.GOLD, Vector2(16, 13))
	var sl := ui.label(_menu, sub, ui.body, 12, Ui.MUTED, Vector2.ZERO)
	sl.position = Vector2(w - 16 - sl.size.x, 18)
	return _menu


func _menu_end(y: float, w: float, anchor: Rect2) -> void:
	var cap_y := y + 6
	var line := ColorRect.new()
	line.color = Color(0.79, 0.64, 0.36, 0.2)
	line.position = Vector2(16, cap_y)
	line.size = Vector2(w - 32, 1)
	_menu.add_child(line)
	_menu_cap = ui.label(_menu, "", ui.serif, 14, Ui.TEXT, Vector2(16, cap_y + 6), w - 32)
	var h := cap_y + 46
	Ui.frame_resize(_menu.get_meta(&"fr") as Control, Vector2(w, h))
	_menu.size = Vector2(w, h)
	_place(_menu, anchor, TK)
	_menu.modulate.a = 0.0
	create_tween().tween_property(_menu, "modulate:a", 1.0, 0.24)


func _open_item_menu(k: int) -> void:
	var slot: Dictionary = eq.slots[k]
	var w := 336.0
	_menu_box(str(slot["type"]), "%d в сумке" % (eq.bag[k] as Array).size(), w)
	_menu_id = "slot:%d" % k
	var y := 42.0
	var cols := 6
	var gap := 6.0
	var tw := (w - 32 - gap * (cols - 1)) / cols
	var th := tw * 170.0 / 156.0
	for key: String in eq.set_keys:
		var S: Dictionary = eq.sets[key]
		ui.pic(_menu, str(S["emblem"]), Rect2(16, y + 2, 18, 18))
		ui.label(_menu, str(S["name"]).to_upper(), ui.caps(11, 0.1), 11, Color.html(str(S["color"])), Vector2(40, y + 5))
		y += 24
		for mana: bool in [false, true]:
			if mana:
				ui.label(_menu, "ПРОПИТАНО МАНОЙ", ui.caps(10, 0.12), 10, Ui.MANA, Vector2(16, y))
				y += 16
			var i := 0
			for it: Dictionary in eq.bag[k]:
				if str(it["set"]) != key or bool(it.get("mana", false)) != mana:
					continue
				var r := Rect2(16 + (i % cols) * (tw + gap), y + floorf(i / float(cols)) * (th + gap), tw, th)
				_tile(r, it, k)
				i += 1
			y += ceilf(i / float(cols)) * (th + gap) + 4
	_menu_end(y, w, _r(slot["rect"]))
	_caption(eq.item_at(k), k)


func _tile(r: Rect2, it: Dictionary, k: int) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.04, 0.045)
	bg.position = r.position
	bg.size = r.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(bg)
	ui.item_icon(_menu, str((eq.sets[it["set"]] as Dictionary)["sheet"]), eq.cell(str(it["set"]), k, int(it["r"])), r)
	var rc: Color = eq.rc(int(it["r"]))
	var eqd := str(it["id"]) == str(eq.equipped[k])
	var b := Control.new()
	b.position = r.position
	b.size = r.size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.draw.connect(func() -> void:
		Ui.rarity_border(b, Rect2(Vector2.ZERO, r.size), rc, 0.6)
		if eqd:
			b.draw_rect(Rect2(Vector2(-3, -3), r.size + Vector2(6, 6)), Ui.SET, false, 2.0)
			b.draw_rect(Rect2(Vector2(r.size.x - 13, 0), Vector2(13, 13)), Ui.SET))
	_menu.add_child(b)
	if bool(it.get("mana", false)):
		var box := ui.frame(_menu, "mana_rim.png", [76, 76, 76, 76], 11.0 / 76.0, r)
		(box.get_meta(&"np") as NinePatchRect).draw_center = false
	if eqd:
		ui.label(_menu, "✓", ui.serif, 11, Color(0.04, 0.09, 0.08), r.position + Vector2(r.size.x - 11, -1))
	var id := str(it["id"])
	var mr := Rect2(_menu.position + r.position * TK, r.size * TK)
	_menu_tiles.append({"rect": mr, "local": r, "item": it, "k": k, "cb": func() -> void:
		eq.equipped[k] = id
		mod.set_setting("inv_equipped", eq.equipped.duplicate())
		_close_menu()
		_refresh()})


func _menu_hover(p: Vector2) -> void:
	for t: Dictionary in _menu_tiles:
		var r := Rect2(_menu.position + (t["local"] as Rect2).position * TK, (t["local"] as Rect2).size * TK)
		t["rect"] = r
		if r.has_point(p):
			if t.has("item"):
				_caption(t["item"], int(t["k"]))
			elif t.has("weapon"):
				_wcaption(str(t["weapon"]), int(t["w"]))
			return


func _caption(it: Dictionary, k: int) -> void:
	if not is_instance_valid(_menu_cap) or it.is_empty():
		return
	_menu_cap.text = "%s — %s · %s%s%s" % [it["name"], (eq.sets[it["set"]] as Dictionary)["name"], (eq.rar[int(it["r"])] as Dictionary)["name"],
		" · пропитано маной" if bool(it.get("mana", false)) else "", " · надето" if str(it["id"]) == str(eq.equipped[k]) else ""]
	_menu_cap.add_theme_color_override("font_color", eq.rc(int(it["r"])))


func _open_weapon_menu(w: int) -> void:
	var mw := 336.0
	var W2: Dictionary = eq.d["weapons"]
	_menu_box(str(WSLOTS[w]["name"]), "%d в сумке" % W2.size(), mw)
	_menu_id = "wpn:%d" % w
	var y := 46.0
	var tw := (mw - 32 - 8) / 2.0
	var th := tw * 4.0 / 3.0
	var i := 0
	for key: String in W2:
		var r := Rect2(16 + i * (tw + 8), y, tw, th)
		ui.pic(_menu, "wpn_bg.jpg", r, false)
		ui.pic(_menu, str((W2[key] as Dictionary)["icon"]), r.grow(-8))
		var eqd: bool = _weapons[w] == key
		var other: bool = _weapons[1 - w] == key
		var b := Control.new()
		b.position = r.position
		b.size = r.size
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.draw.connect(func() -> void:
			b.draw_rect(Rect2(Vector2.ZERO, r.size), Ui.SET if eqd else Ui.GOLD_DIM, false, 2.0 if eqd else 1.0))
		_menu.add_child(b)
		if other:
			ui.label(_menu, "ВТОРОЕ" if w == 0 else "ОСНОВНОЕ", ui.caps(10, 0.08), 10, Ui.GOLD, r.position + Vector2(5, r.size.y - 18), 0.0,
				HORIZONTAL_ALIGNMENT_LEFT, Color(0, 0, 0, 0.9))
		var k2 := key
		_menu_tiles.append({"rect": Rect2(), "local": r, "weapon": key, "w": w, "cb": func() -> void:
			_close_menu()
			_choose_weapon(w, k2)})
		i += 1
	y += th + 4
	_menu_end(y, mw, _r(WSLOTS[w]["rect"]))
	_wcaption(_weapons[w], w)


func _wcaption(key: String, w: int) -> void:
	if not is_instance_valid(_menu_cap):
		return
	var wp: Dictionary = (eq.d["weapons"] as Dictionary)[key]
	var state := "надето" if _weapons[w] == key else ("сейчас %s — поменяются местами" % ("основное" if w == 1 else "второе") if _weapons[1 - w] == key else "")
	var sk: Array = wp["skills"]
	_menu_cap.text = "%s — главный атрибут %s%s\nОсновным — «%s», вторым — «%s»" % [wp["name"], wp["attr"], (" · " + state) if state != "" else "", sk[0][1], sk[1][1]]
	_menu_cap.add_theme_color_override("font_color", Ui.TEXT)
