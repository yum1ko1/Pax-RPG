extends Control
## Окно лавки торговца (разговор → «Лавка», talk.gd) — в стиле нового инвентаря: сцена textures/shop/stage.jpg (как
## stage.jpg инвентаря: багровая ночь, красная луна, сакура, лаковые панели с золотыми рамками) — сверху две плашки-
## вкладки (мешочек — «Товары дня», колесо — «Колесо Судьбы»), слева окно с торговцем (textures/shop/trader.jpg), имя
## и золото героя, справа широкое окно с товаром или рулеткой. Шрифты и рамки — inv/ui.gd: Cormorant, капитель Cinzel;
## подписи строгие, как пункты меню. Вещи — значки из листов сетов, рамка цвета редкости, подсказка вещи при наведении
## (inv/item_tip.gd). Рулетка — прокрутка добычи (loot/roll.gd: лента в туши, катана), ×10 — потом все десять сеткой.
## Логика и числа — shop.gd / config/shop.json. Нет картинок лавки — панели рисуются сами, вместо значков — иероглифы.
## Макет 1536 × 1024 (как у инвентаря и сцены), масштаб под экран. Мир на паузе.

signal closed
signal talk_requested                                # «Поговорить» — к разговору с этим торговцем (location.gd)
signal sound(path: String, db: float)            # location.gd → _sfx_once

const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")
const Equip := preload("res://mods/pax_rpg/src/location/inv/equip.gd")
const ItemTip := preload("res://mods/pax_rpg/src/location/inv/item_tip.gd")
const Roll := preload("res://mods/pax_rpg/src/location/loot/roll.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Shop := preload("res://mods/pax_rpg/src/location/shop.gd")
const W := 1536.0
const H := 1024.0
const WW := 1820.0                               # stage_wide.jpg — тот же макет на 16:9 (pax_rpg/dev/inventory/build_stage_wide.py)
# окна сцены (px stage.jpg, замер по тёмным внутренним областям)
const LEFT := Rect2(28, 271, 284, 565)           # торговец
const MAIN := Rect2(351, 271, 1154, 573)         # товар / рулетка
const TAB_GOODS := Rect2(365, 55, 390, 100)      # плашки вкладок
const TAB_WHEEL := Rect2(781, 55, 391, 100)
const CARD := Vector2(150.0, 386.0)
const CARD_GAP := 12.0
const TIP_K := 0.72
const TEXT := Color(0.93, 0.87, 0.80)
const PALE := Color(0.86, 0.82, 0.92)            # пункты меню
const BAD := Color(1.0, 0.45, 0.4)

var mod: PaxMod
var shop: Shop
var ui := Ui.new()
var _frame: Control
var _goods_page: Control
var _wheel_page: Control
var _grid: Control                                # ×10: десять вещей сеткой
var _tab_goods: Button
var _tab_wheel: Button
var _title_l: Label
var _btn1: Button
var _btn10: Button
var _name_l: Label
var _gold_l: Label
var _timer_l: Label
var _msg_l: Label
var _pity_l: Label
var _odds_l: RichTextLabel
var _msg_t := 0.0
var _secs_shown := -1
var _roll: Roll
var _results: Array = []                          # вещи последнего прокрута
var _gate: Array = []                             # очередь окна характеристик (roll.gd)
var _hot: Array = []                              # [Rect2 в px макета, id вещи] — наведение → подсказка
var _tip: ItemTip
var _tip_id := ""


func setup(m: PaxMod) -> void:
	mod = m
	ui.setup(m)
	name = "PaxRpgShop"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var base := ColorRect.new()
	base.color = Color(0.03, 0.01, 0.015)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	if _has("textures/shop/stage_wide.jpg"):                      # 16:9: по бокам макета — общий фон инвентаря (backdrop.jpg)
		ui.pic(_frame, "textures/shop/stage_wide.jpg", Rect2(-(WW - W) * 0.5, 0, WW, H), false)
	elif _has("textures/shop/stage.jpg"):
		ui.pic(_frame, "textures/shop/stage.jpg", Rect2(0, 0, W, H), false)
	else:                                                         # без сцены — те же окна простыми рамками
		for r: Rect2 in [LEFT, MAIN, TAB_GOODS, TAB_WHEEL]:
			_box(_frame, r.grow(6), func(ci: Control) -> void:
				ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.04, 0.03, 0.03))
				ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Ui.GOLD_DIM, false, 1.5))
	_build_left()
	_build_tabs()
	_goods_page = _page()
	_wheel_page = _page()
	_build_wheel()
	_title_l = ui.label(_frame, "", ui.caps(15, 0.16), 15, Ui.GOLD, Vector2(MAIN.position.x, MAIN.position.y + 14), MAIN.size.x,
		HORIZONTAL_ALIGNMENT_CENTER)
	var fy := MAIN.end.y - 32.0
	_timer_l = ui.label(_frame, "", ui.caps(11, 0.12), 11, Ui.MUTED, Vector2(MAIN.position.x + 18, fy))
	_msg_l = ui.label(_frame, "", ui.caps(13, 0.12), 13, Ui.GOLD, Vector2(MAIN.position.x, fy - 2), MAIN.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	ui.label(_frame, mod.tr_key("pax_rpg_shop_close").to_upper(), ui.caps(11, 0.12), 11, Ui.MUTED, Vector2(MAIN.end.x - 318, fy), 300.0,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_roll = Roll.new()                                            # прокрутка добычи — поверх окна, на вкладке колеса
	var eq := Equip.new()
	eq.load_data(m)
	var lc: Variant = JSON.parse_string(m.read_text("config/loot.json"))
	_roll.setup(m, eq, ui, lc if lc is Dictionary else {})
	_roll.K = 1.0
	_roll.grant = false                                           # в сумку кладёт лавка — сразу при оплате
	_roll.gate = _gate
	_roll.set_katana(Assets.model(m, "models/weapons/katana.glb"))
	_roll.done.connect(func(_id: String) -> void: _roll_done())
	_roll.visible = false
	add_child(_roll)
	resized.connect(_fit)


func _has(path: String) -> bool:
	return not mod.read_bytes(path).is_empty()


func _page() -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(c)
	return c


func _fit() -> void:
	var s := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(s, s)
	_frame.position = (size - Vector2(W, H) * s) * 0.5
	# лента — в своих px (высота экрана = 1080): центр окна товара чуть выше середины, масштаб — как у макета
	var u := maxf(size.y / 1080.0, 0.001)
	var c := _frame.position + Vector2(MAIN.get_center().x, MAIN.position.y + 215.0) * s
	_roll.anchor = c / u
	_roll.K = s / u * 0.95


## who — имя торговца, role — его ремесло под именем ("" — лавочник Базара Добычи).
func open(s: Shop, who: String, role := "") -> void:
	shop = s
	shop.refresh()
	_roll.eq = shop.eq
	_roll.hero_lvl = shop.prog.level
	_msg_t = 0.0
	_msg_l.text = ""
	_name_l.text = who.to_upper()
	_role_l.text = (role if role != "" else mod.tr_key("pax_rpg_npc_role_trader")).to_upper()
	visible = true
	_fit()
	_show_tab(true)


func close() -> void:
	if not visible:
		return
	_close_tip()
	visible = false
	closed.emit()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo \
			and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------- торговец и вкладки ----------

var _role_l: Label


func _build_left() -> void:
	var pr := Rect2(LEFT.position, Vector2(LEFT.size.x, 410))      # портрет — верх окна
	if _has("textures/shop/trader.jpg"):
		ui.pic(_frame, "textures/shop/trader.jpg", pr, true).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		ui.label(_frame, "商", ui.serif, 120, Ui.GOLD_DIM, pr.position + Vector2(0, 120), pr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_box(_frame, Rect2(pr.position.x, pr.end.y - 90, pr.size.x, 90), func(ci: Control) -> void:   # низ портрета уходит в тень
		for i: int in 30:
			ci.draw_rect(Rect2(0, i * 3.0, ci.size.x, 3.0), Color(0.02, 0.01, 0.01, i / 30.0 * 0.95)))
	var talk := _button(_frame, mod.tr_key("pax_rpg_shop_talk"), Rect2(LEFT.get_center().x - 90, pr.end.y - 46, 180, 34), 12, true)
	talk.pressed.connect(func() -> void: talk_requested.emit())    # низ портрета: лавка → разговор (там «Лавка» — назад)
	var y := pr.end.y + 4.0
	_name_l = ui.label(_frame, "", ui.caps(17, 0.12), 17, TEXT, Vector2(LEFT.position.x + 10, y), LEFT.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	_role_l = ui.label(_frame, mod.tr_key("pax_rpg_npc_role_trader").to_upper(), ui.caps(10, 0.14), 10, Ui.GOLD,
		Vector2(LEFT.position.x + 10, y + 48), LEFT.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	ui.pic(_frame, "div_section.png", Rect2(LEFT.position.x + 42, y + 72, LEFT.size.x - 84, 12), false)
	ui.label(_frame, mod.tr_key("pax_rpg_shop_purse").to_upper(), ui.caps(10, 0.14), 10, Ui.MUTED,
		Vector2(LEFT.position.x + 10, y + 96), LEFT.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	var cy := y + 128.0
	_box(_frame, Rect2(LEFT.get_center().x - 74, cy, 32, 32), func(ci: Control) -> void:     # монета — как в подсказке вещи
		var c := Vector2(16, 16)
		ci.draw_circle(c, 13.0, Color(0.62, 0.42, 0.10))
		ci.draw_circle(c, 11.0, Color(0.95, 0.76, 0.32))
		ci.draw_arc(c, 8.5, 0, TAU, 24, Color(0.55, 0.36, 0.08), 1.2)
		ci.draw_rect(Rect2(c + Vector2(-4, -1.5), Vector2(8, 4)), Color(0.48, 0.30, 0.06)))
	_gold_l = ui.label(_frame, "0", ui.serif, 24, Color(0.95, 0.84, 0.55), Vector2(LEFT.get_center().x - 34, cy - 4))


func _build_tabs() -> void:
	_tab_goods = _tab(TAB_GOODS)
	_tab_goods.pressed.connect(_show_tab.bind(true))
	_tab_wheel = _tab(TAB_WHEEL)
	_tab_wheel.pressed.connect(_show_tab.bind(false))


## Вкладка — сама плашка сцены: щелчок по ней; выбранная светится золотом, другая притушена, над наведённой — свет.
func _tab(r: Rect2) -> Button:
	var b := Button.new()
	b.position = r.position
	b.size = r.size
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.draw.connect(func() -> void:
		var rr := Rect2(Vector2.ZERO, b.size)
		if bool(b.get_meta(&"on", false)):
			for i: int in 5:
				b.draw_rect(rr.grow(-2.0 - i * 2.0), Color(1.0, 0.78, 0.4, 0.18 - i * 0.03), false, 2.0)
		else:
			b.draw_rect(rr.grow(-4), Color(0.0, 0.0, 0.0, 0.25 if b.is_hovered() else 0.45)))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	_frame.add_child(b)
	return b


func _show_tab(goods: bool) -> void:
	_close_tip()
	_goods_page.visible = goods
	_wheel_page.visible = not goods
	_roll.visible = not goods
	_title_l.text = mod.tr_key("pax_rpg_shop_tab_goods" if goods else "pax_rpg_shop_tab_wheel").to_upper()
	for b: Button in [_tab_goods, _tab_wheel]:
		b.set_meta(&"on", (b == _tab_goods) == goods)
		b.queue_redraw()
	if goods:
		_build_goods()
	else:
		_update_wheel()


func _process(delta: float) -> void:
	if not visible or shop == null:
		return
	_gold_l.text = Equip.money(shop.prog.gold)
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg_l.modulate.a = clampf(_msg_t, 0.0, 1.0)
	_timer_l.visible = _goods_page.visible and _msg_t <= 0.0
	var secs := shop.secs_to_reset()
	if secs != _secs_shown:
		if _secs_shown >= 0 and secs > _secs_shown + 60:           # сутки сменились, пока окно открыто — новый прилавок
			shop.refresh()
			if _goods_page.visible:
				_build_goods()
		_secs_shown = secs
		_timer_l.text = (mod.tr_key("pax_rpg_shop_refresh_in") % ("%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60])).to_upper()
	_hover()


# ---------- товары дня ----------

func _build_goods() -> void:
	_close_tip()
	_hot.clear()
	for c: Node in _goods_page.get_children():
		c.queue_free()
	var n := shop.goods.size()
	var x0 := MAIN.get_center().x - (CARD.x * n + CARD_GAP * (n - 1)) * 0.5
	for i: int in n:
		_card(i, Rect2(Vector2(x0 + i * (CARD.x + CARD_GAP), MAIN.position.y + 58), CARD))


func _card(i: int, r: Rect2) -> void:
	var g: Dictionary = shop.goods[i]
	var is_item := str(g.kind) == "item"
	var it: Dictionary = shop.item(str(g.id)) if is_item else {}
	var col: Color = shop.eq.rc(int(g.r)) if is_item else Ui.GOLD_DIM
	var why := shop.why_not(i)
	var gone := why == "sold_out" or why == "city_sold" or why == "capped"
	var dim := Color(1, 1, 1, 0.35 if gone else 1.0)
	_box(_goods_page, r, func(ci: Control) -> void:
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.06, 0.03, 0.03, 0.9))
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(Ui.GOLD_DIM, 0.7), false, 1.0))
	var ir := Rect2(r.position + Vector2(13, 13), Vector2(124, 124))
	_box(_goods_page, ir, func(ci: Control) -> void: ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.05, 0.035, 0.04)))
	if is_item:
		var S: Dictionary = shop.eq.sets[str(it.set)]
		ui.item_icon(_goods_page, str(S["sheet"]), shop.eq.cell(str(it.set), int(it.slot), int(it.r)), ir).modulate = dim
		_hot.append([r, str(g.id)])
	else:
		var path := "textures/shop/%s.png" % str(g.id)
		if _has(path):
			ui.pic(_goods_page, path, ir, false).modulate = dim
		else:
			ui.label(_goods_page, str(shop.good(str(g.id)).get("glyph", "物")), ui.serif, 72, Color(Ui.GOLD, dim.a),
				ir.position + Vector2(0, 18), ir.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_box(_goods_page, ir, func(ci: Control) -> void: Ui.rarity_border(ci, Rect2(Vector2.ZERO, ci.size), col, 0.4 if gone else 0.75))
	var y := ir.end.y + 12.0
	var tag := shop.rarity_name(int(g.r)) if is_item else mod.tr_key("pax_rpg_shop_consumable")
	ui.label(_goods_page, tag.to_upper(), ui.caps(10, 0.12), 10, col if is_item else Ui.MUTED, Vector2(r.position.x + 6, y),
		r.size.x - 12, HORIZONTAL_ALIGNMENT_CENTER)
	var title := str(it.get("name", "")) if is_item else mod.tr_key("pax_rpg_shop_good_" + str(g.id))
	ui.label(_goods_page, title, ui.serif, 17, TEXT, Vector2(r.position.x + 8, y + 16), r.size.x - 16, HORIZONTAL_ALIGNMENT_CENTER)
	var sub := str((shop.eq.slots[int(it.slot)] as Dictionary).get("kind", "")) if is_item \
		else mod.tr_key("pax_rpg_shop_good_" + str(g.id) + "_desc")
	ui.label(_goods_page, sub, ui.body, 12, Ui.MUTED, Vector2(r.position.x + 10, y + 72), r.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	var by := Rect2(r.position.x + 10, r.end.y - 50, r.size.x - 20, 38)
	if gone:
		var k := {"sold_out": "pax_rpg_shop_sold", "city_sold": "pax_rpg_shop_city_sold", "capped": "pax_rpg_shop_capped"}
		ui.label(_goods_page, mod.tr_key(str(k[why])).to_upper(), ui.caps(11, 0.14), 11, Ui.MUTED, by.position + Vector2(0, 11),
			by.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	ui.label(_goods_page, Equip.money(int(g.price)), ui.serif, 18, Color(0.95, 0.84, 0.55), Vector2(r.position.x, by.position.y - 34),
		r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var b := _button(_goods_page, mod.tr_key("pax_rpg_shop_buy"), by, 12, true)
	if why == "no_gold":
		b.add_theme_color_override("font_color", Color(BAD, 0.85))
	b.pressed.connect(_buy.bind(i))


func _buy(i: int) -> void:
	var why := shop.why_not(i)
	if why != "":
		_say(mod.tr_key("pax_rpg_shop_why_" + why), BAD)
		return
	var g: Dictionary = shop.goods[i]
	var title := str(shop.item(str(g.id)).get("name", "")) if str(g.kind) == "item" else mod.tr_key("pax_rpg_shop_good_" + str(g.id))
	if shop.buy(i):
		sound.emit("sounds/loot_bag_lid.ogg", -8.0)
		_say(mod.tr_key("pax_rpg_shop_bought") % title, Ui.GOLD)
	_build_goods()


func _say(text: String, col: Color) -> void:
	_msg_l.text = text.to_upper()
	_msg_l.add_theme_color_override("font_color", col)
	_msg_t = 2.6


# ---------- Колесо Судьбы ----------

func _build_wheel() -> void:
	var cx := MAIN.get_center().x
	var y := MAIN.position.y + 400.0
	_btn1 = _button(_wheel_page, "", Rect2(cx - 290, y, 270, 42), 14, true)
	_btn1.pressed.connect(_spin.bind(1))
	_btn10 = _button(_wheel_page, "", Rect2(cx + 20, y, 270, 42), 14, true)
	_btn10.pressed.connect(_spin.bind(10))
	_pity_l = ui.label(_wheel_page, "", ui.caps(11, 0.12), 11, Ui.GOLD, Vector2(MAIN.position.x, y + 62), MAIN.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_odds_l = RichTextLabel.new()
	_odds_l.bbcode_enabled = true
	_odds_l.scroll_active = false
	_odds_l.add_theme_font_override("normal_font", ui.caps(11, 0.1))
	_odds_l.add_theme_font_size_override("normal_font_size", 11)
	_odds_l.add_theme_color_override("default_color", Ui.MUTED)
	_odds_l.position = Vector2(MAIN.position.x + 10, y + 88)
	_odds_l.size = Vector2(MAIN.size.x - 20, 24)
	_odds_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_page.add_child(_odds_l)
	_grid = Control.new()
	_grid.size = Vector2(W, H)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_page.add_child(_grid)


func _update_wheel() -> void:
	if shop == null:
		return
	var busy := _roll.busy()
	_btn1.text = "%s  ·  %s" % [mod.tr_key("pax_rpg_shop_spin1").to_upper(), Equip.money(shop.spin_price(1))]
	_btn10.text = "%s  ·  %s" % [mod.tr_key("pax_rpg_shop_spin10").to_upper(), Equip.money(shop.spin_price(10))]
	_btn1.disabled = busy
	_btn10.disabled = busy
	_btn1.add_theme_color_override("font_color", PALE if shop.can_spin(1) else Color(BAD, 0.85))
	_btn10.add_theme_color_override("font_color", PALE if shop.can_spin(10) else Color(BAD, 0.85))
	var g := shop.gacha()
	_pity_l.text = (mod.tr_key("pax_rpg_shop_pity") % [maxi(1, int(g.get("epic_pity", 10)) - shop.pity_epic),
		maxi(1, int(g.get("legend_pity", 50)) - shop.pity_legend)]).to_upper()
	var w: Array = g.get("rarity_w", [])                          # шансы — каждая редкость своим цветом
	var total := 0.0
	for x: Variant in w:
		total += float(x)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in w.size():
		if float(w[i]) > 0.0:
			var p := float(w[i]) / maxf(total, 0.001) * 100.0
			parts.append("[color=#%s]%s[/color] %s %%" % [shop.eq.rc(i).to_html(false), shop.rarity_name(i).to_upper(),
				String.num(p, 1 if p < 10.0 else 0)])
	_odds_l.text = "[center]%s:   %s   ·   %s[/center]" % [mod.tr_key("pax_rpg_shop_odds").to_upper(), "   ·   ".join(parts),
		mod.tr_key("pax_rpg_shop_ten").to_upper()]


func _spin(n: int) -> void:
	if _roll.busy():
		return
	if not shop.can_spin(n):
		_say(mod.tr_key("pax_rpg_shop_why_no_gold"), BAD)
		return
	_close_tip()
	_results = shop.spin(n)
	if _results.is_empty():
		return
	shop.add_to_bag(_results)                                     # в сумку сразу: окно закрыли посреди прокрутки — вещи целы
	var best: Dictionary = _results[0]
	for it: Dictionary in _results:
		if int(it.r) > int(best.r) or (int(it.r) == int(best.r) and bool(it.mana) and not bool(best.mana)):
			best = it
	for c: Node in _grid.get_children():
		c.queue_free()
	_hot.clear()
	_roll.hero_lvl = shop.prog.level
	_roll.start(-1, best)                                         # лента встаёт на лучшей вещи прокрута
	_update_wheel()


func _roll_done() -> void:
	_update_wheel()
	if _results.size() > 1:
		_show_grid()


## ×10: десять вещей сеткой 5 × 2 на месте ленты, появляются по очереди; наведение — подсказка вещи.
func _show_grid() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_hot.clear()
	var cell := 112.0
	var gap := 16.0
	var x0 := MAIN.get_center().x - (cell * 5 + gap * 4) * 0.5
	for i: int in _results.size():
		var res: Dictionary = _results[i]
		var r := Rect2(Vector2(x0 + (i % 5) * (cell + gap), MAIN.position.y + 92.0 + (i / 5) * (cell + gap)), Vector2(cell, cell))
		var col: Color = Ui.MANA if bool(res.mana) else shop.eq.rc(int(res.r))
		var box := _box(_grid, r, func(ci: Control) -> void: ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.05, 0.035, 0.04)))
		var S: Dictionary = shop.eq.sets[str(res.set)]
		ui.item_icon(box, str(S["sheet"]), shop.eq.cell(str(res.set), int(res.k), int(res.r)), Rect2(Vector2.ZERO, r.size))
		_box(box, Rect2(Vector2.ZERO, r.size), func(ci: Control) -> void: Ui.rarity_border(ci, Rect2(Vector2.ZERO, ci.size), col, 0.85))
		_hot.append([r, str(res.id)])
		box.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(i * 0.08)
		tw.tween_property(box, "modulate:a", 1.0, 0.25)


# ---------- подсказка вещи ----------

func _hover() -> void:
	var p := _frame.get_local_mouse_position()
	var hit: Array = []
	if not (_wheel_page.visible and _roll.busy()):
		for h: Array in _hot:
			if (h[0] as Rect2).has_point(p):
				hit = h
				break
	if hit.is_empty():
		if _tip_id != "":
			_close_tip()
		return
	if str(hit[1]) == _tip_id:
		return
	_close_tip()
	_tip_id = str(hit[1])
	var it := shop.item(_tip_id)
	if it.is_empty():
		return
	var loot: Variant = mod.get_setting("inv_loot", [])                  # сет в окне считает надетое — как в инвентаре
	var saved: Variant = mod.get_setting("inv_equipped", [])
	shop.eq.build_bag(shop.prog.level, loot if loot is Array else [])
	shop.eq.equipped = []
	for k: int in shop.eq.slots.size():
		shop.eq.equipped.append(str((saved as Array)[k]) if saved is Array and k < (saved as Array).size() else "")
	_tip = ItemTip.new()
	_frame.add_child(_tip)
	_tip.build(ui, shop.eq, it, int(it.slot), shop.prog.level, shop.eq.d.get("passive", {}))
	var k := minf(TIP_K, (H - 20.0) / maxf(1.0, _tip.size.y))
	_tip.scale = Vector2(k, k)
	var a: Rect2 = hit[0]
	var sz := _tip.size * k
	var x := a.end.x + 8.0 if a.end.x + 8.0 + sz.x < W - 8.0 else a.position.x - 8.0 - sz.x
	_tip.position = Vector2(x, clampf(a.position.y - 40.0, 8.0, H - sz.y - 8.0))


func _close_tip() -> void:
	if is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
	_tip_id = ""


# ---------- мелочи ----------

## Кнопка как пункт меню: капитель с разрядкой и тонкая золотая рамка на тёмном лаке.
func _button(parent: Control, text: String, r: Rect2, fs: int, _framed: bool) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", ui.caps(fs, 0.14))
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", PALE)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))
	b.add_theme_color_override("font_pressed_color", Ui.GOLD)
	b.add_theme_color_override("font_disabled_color", Color(Ui.MUTED, 0.6))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.03, 0.04, 0.85 if st == "hover" else 0.6)
		sb.border_color = Color(Ui.GOLD, 0.3 if st == "disabled" else (0.95 if st == "hover" else 0.6))
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override(st, sb)
	parent.add_child(b)
	return b


func _box(parent: Control, r: Rect2, fn: Callable) -> Control:
	var c := Control.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: fn.call(c))
	parent.add_child(c)
	return c
