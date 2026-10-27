extends Control
## Окно лавки торговца (разговор → «Лавка», talk.gd): две вкладки — «Товары дня» (карточки: знак, название, что даёт,
## цена, сколько осталось; «выгода дня» со скидкой; до обновления прилавка — часы) и «Колесо Судьбы» (рулетка: лента
## карточек разной редкости бежит и тормозит под меткой, ×10 — потом все десять сеткой; гаранты и шансы — под лентой).
## Логика и числа — shop.gd / config/shop.json. Картинки — из textures/shop/, если есть: <id товара>.png, fx_gold.png,
## shop_bg.jpg (делает pax_rpg/dev/gpt/shop_art.py); нет — знаки-иероглифы и лак, как в инвентаре. Макет 1920 × 1080, масштаб под экран. Мир на паузе.

signal closed
signal sound(path: String, db: float)            # location.gd → _sfx_once

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Shop := preload("res://mods/pax_rpg/src/location/shop.gd")
const W := 1920.0
const H := 1080.0
const CARD := Vector2(150.0, 200.0)              # карточка ленты рулетки
const GAP := 12.0
const STRIP := Rect2(160.0, 300.0, 1600.0, 250.0)
const SPIN_TIME := 5.2                           # с: лента одного прокрута
const SPIN10_TIME := 3.4
const FX_GLYPH := {"gold": "金", "xp": "經", "refill": "藥", "ticket": "運", "flask": "瓢", "stat": "道"}
const FX_ICON := {"gold": "fx_gold.png", "xp": "xp_scroll.png", "refill": "elixir_refill.png", "ticket": "fate_token.png",
	"flask": "flask_vessel.png", "stat": "stat_scroll.png"}       # награда рулетки — значок товара того же действия
const RARITY_ORDER := ["common", "rare", "epic", "legend"]

var mod: PaxMod
var shop: Shop
var hud: Hud
var trader_name := ""
var _frame: Control
var _bg: Control
var _goods_page: Control
var _gacha_page: Control
var _strip: Control
var _tab_goods: Button
var _tab_gacha: Button
var _btn1: Button
var _btn10: Button
var _btn_ticket: Button
var _pity_l: Label
var _odds_l: Label
var _result_l: Label
var _timer_l: Label
var _msg_l: Label
var _msg_t := 0.0
var _serif: Font
var _sans: Font
var _cjk: Font
var _panel_sh: Shader
var _bg_tex: Texture2D
var _tex_names: PackedStringArray = PackedStringArray()
var _tex_cache: Dictionary = {}
var _t := 0.0
var _secs_shown := -1
# лента рулетки
var _cards: Array = []                           # [{"rarity", "effect", "amount"}]
var _off := 0.0                                  # сдвиг ленты, px
var _off_from := 0.0
var _off_to := 0.0
var _spin_t := -1.0                              # <0 — лента стоит
var _spin_len := SPIN_TIME
var _win_i := -1                                 # карточка под меткой после остановки
var _last_tick := 0
var _results: Array = []                         # награды последнего прокрута
var _grid := false                               # ×10 — после ленты сетка из десяти
var _grid_t := 0.0
var _gold_shown := 0                             # золото и жетоны в шапке: пока лента бежит — как до прокрута
var _tickets_shown := 0


func setup(m: PaxMod, h: Hud) -> void:
	mod = m
	hud = h
	name = "PaxRpgShop"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel_sh = m.shader("shaders/ui_panel.gdshader")
	_serif = Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 700)
	_sans = Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	_cjk = Hud._sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "Noto Serif CJK JP", "SimSun"], 700)
	_tex_names = m.list_files("textures/shop")
	_bg_tex = _tex("shop_bg.jpg")
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.04, 0.97)
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
	_tab_goods = _button(_tr("pax_rpg_shop_tab_goods"), Rect2(120, 150, 300, 48), _frame, 20)
	_tab_goods.toggle_mode = true
	_tab_goods.pressed.connect(_show_tab.bind(true))
	_tab_gacha = _button(_tr("pax_rpg_shop_tab_gacha"), Rect2(432, 150, 300, 48), _frame, 20)
	_tab_gacha.toggle_mode = true
	_tab_gacha.pressed.connect(_show_tab.bind(false))
	var close_b := _button("✕", Rect2(W - 120, 40, 60, 52), _frame, 26)
	close_b.pressed.connect(close)
	_goods_page = Control.new()
	_goods_page.size = Vector2(W, H)
	_goods_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_goods_page)
	_gacha_page = Control.new()
	_gacha_page.size = Vector2(W, H)
	_gacha_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_gacha_page)
	_build_gacha()
	_gacha_page.visible = false
	_timer_l = _label("", Vector2(120, 960), _sans, 18, Hud.MUTED, _frame, 900.0)
	_msg_l = _label("", Vector2(0, 900), _serif, 30, Hud.TEXT, _frame, W)
	_msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _label(_tr("pax_rpg_shop_hint"), Vector2(W - 1020, 960), _sans, 18, Hud.MUTED, _frame, 900.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resized.connect(_fit)


func _tr(k: String) -> String:
	return mod.tr_key(k)


func _fit() -> void:
	var s := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(s, s)
	_frame.position = (size - Vector2(W, H) * s) * 0.5


## Картинка лавки из textures/shop/ (одна загрузка); нет файла — null, рисуем знаком.
func _tex(file: String) -> Texture2D:
	if not _tex_names.has(file):
		return null
	if not _tex_cache.has(file):
		_tex_cache[file] = mod.texture("textures/shop/" + file)
	return _tex_cache[file]


func open(s: Shop, who: String) -> void:
	shop = s
	trader_name = who
	shop.refresh()
	_msg_t = 0.0
	_msg_l.text = ""
	_spin_t = -1.0
	_grid = false
	if _cards.is_empty():
		_fill_strip(-1, {})
	_result_l.text = ""
	_gold_shown = shop.prog.gold
	_tickets_shown = shop.tickets
	visible = true
	_fit()
	_show_tab(true)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo \
			and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _show_tab(goods: bool) -> void:
	_tab_goods.set_pressed_no_signal(goods)
	_tab_gacha.set_pressed_no_signal(not goods)
	_goods_page.visible = goods
	_gacha_page.visible = not goods
	if goods:
		_build_goods()
	_update_gacha()
	_bg.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg_l.modulate.a = clampf(_msg_t, 0.0, 1.0)
	var secs := shop.secs_to_reset()
	if secs != _secs_shown:
		if _secs_shown >= 0 and secs > _secs_shown + 60:      # сутки сменились, пока окно открыто — новый прилавок
			shop.refresh()
			if _goods_page.visible:
				_build_goods()
		_secs_shown = secs
		_timer_l.text = _tr("pax_rpg_shop_refresh_in") % ("%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60])
	if _spin_t >= 0.0:
		_spin_t += delta
		var k := clampf(_spin_t / _spin_len, 0.0, 1.0)
		_off = lerpf(_off_from, _off_to, 1.0 - pow(1.0 - k, 4.0))   # быстро, потом долго тормозит
		var tick := int((_off + STRIP.size.x * 0.5) / (CARD.x + GAP))
		if tick != _last_tick:
			_last_tick = tick
			sound.emit("sounds/iai_tsuba.wav", -20.0)
		if k >= 1.0:
			_spin_t = -1.0
			_spin_done()
	if _grid:
		_grid_t += delta
	if _spin_t < 0.0:
		_gold_shown = shop.prog.gold
		_tickets_shown = shop.tickets
	_bg.queue_redraw()                                         # монета дышит
	_strip.queue_redraw()


# ---------- товары дня ----------

func _build_goods() -> void:
	for c: Node in _goods_page.get_children():
		c.queue_free()
	var n := shop.goods.size()
	var cw := 330.0
	var gap := 36.0
	var x0 := (W - (cw * n + gap * (n - 1))) * 0.5
	for i: int in n:
		var it: Dictionary = shop.goods[i]
		var id := str(it.id)
		var g := shop.good(id)
		var r := Rect2(x0 + i * (cw + gap), 260, cw, 600)
		_panel(r, _goods_page, bool(it.deal))
		var icon := _tex(id + ".png")
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.position = r.position + Vector2(65, 40)
			tr.size = Vector2(200, 200)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_goods_page.add_child(tr)
		else:
			var gl := _label(str(g.get("glyph", "物")), r.position + Vector2(0, 50), _cjk, 130, Hud.GOLD, _goods_page, cw)
			gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if bool(it.deal):
			var dl := _label(_tr("pax_rpg_shop_deal") % roundi(float(shop.cfg.get("deal_off", 0.3)) * 100.0),
				r.position + Vector2(0, 14), _sans, 17, Color(1.0, 0.62, 0.4), _goods_page, cw)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_text(_tr("pax_rpg_shop_good_" + id), Rect2(r.position + Vector2(20, 256), Vector2(cw - 40, 84)), _serif, 29, Hud.TEXT)
		_text(fx_text(str(g.get("effect", "")), int(g.get("amount", 1))), Rect2(r.position + Vector2(20, 350), Vector2(cw - 40, 50)),
			_sans, 19, Color(1.0, 0.86, 0.6))
		_text(_tr("pax_rpg_shop_good_" + id + "_desc"), Rect2(r.position + Vector2(28, 400), Vector2(cw - 56, 84)), _sans, 16,
			Hud.MUTED)
		var why := shop.why_not(i)
		var left := _label(_tr("pax_rpg_shop_" + why) if why == "capped" or why == "city_sold" else _tr("pax_rpg_shop_left") % int(it.left),
			r.position + Vector2(0, 492), _sans, 16, Hud.MUTED, _goods_page, cw)
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b := _button(_tr("pax_rpg_shop_buy") % int(it.price) if why != "sold_out" else _tr("pax_rpg_shop_sold_out"),
			Rect2(r.position + Vector2(40, 526), Vector2(cw - 80, 50)), _goods_page, 20)
		b.disabled = why == "sold_out" or why == "capped" or why == "city_sold"
		if why == "no_gold":
			b.add_theme_color_override("font_color", Color(0.85, 0.45, 0.4))
		b.pressed.connect(_buy.bind(i))


func _buy(i: int) -> void:
	var why := shop.why_not(i)
	if why != "":
		_say(_tr("pax_rpg_shop_why_" + why), Color(1.0, 0.5, 0.45))
		return
	var id := str((shop.goods[i] as Dictionary).id)
	if shop.buy(i):
		sound.emit("sounds/gear_2.ogg", -6.0)
		_say(_tr("pax_rpg_shop_bought") % _tr("pax_rpg_shop_good_" + id), Hud.GOLD)
	_build_goods()
	_update_gacha()


func _say(text: String, col: Color) -> void:
	_msg_l.text = text
	_msg_l.add_theme_color_override("font_color", col)
	_msg_t = 2.6


## Что даёт награда словами: «+120 опыта», «70 золота», …
func fx_text(effect: String, amount: int) -> String:
	var k := "pax_rpg_shop_fx_" + effect
	var s := _tr(k)
	return s % amount if s.contains("%d") else s


# ---------- рулетка ----------

func _build_gacha() -> void:
	_strip = Control.new()
	_strip.position = STRIP.position
	_strip.size = STRIP.size
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.draw.connect(_draw_strip)
	_gacha_page.add_child(_strip)
	_result_l = _label("", Vector2(0, 580), _serif, 34, Hud.TEXT, _gacha_page, W)
	_result_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn1 = _button("", Rect2(W * 0.5 - 520, 650, 330, 64), _gacha_page, 22)
	_btn1.pressed.connect(_spin.bind(1, false))
	_btn10 = _button("", Rect2(W * 0.5 - 165, 650, 330, 64), _gacha_page, 22)
	_btn10.pressed.connect(_spin.bind(10, false))
	_btn_ticket = _button("", Rect2(W * 0.5 + 190, 650, 330, 64), _gacha_page, 22)
	_btn_ticket.pressed.connect(_spin.bind(1, true))
	_pity_l = _label("", Vector2(0, 742), _sans, 19, Color(1.0, 0.86, 0.6), _gacha_page, W)
	_pity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_odds_l = _label("", Vector2(0, 778), _sans, 16, Hud.MUTED, _gacha_page, W)
	_odds_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _update_gacha() -> void:
	if not is_instance_valid(_btn1):
		return
	var busy := _spin_t >= 0.0
	_btn1.text = _tr("pax_rpg_shop_spin1") % shop.spin_price(1)
	_btn10.text = _tr("pax_rpg_shop_spin10") % shop.spin_price(10)
	_btn_ticket.text = _tr("pax_rpg_shop_spin_ticket") % (_tickets_shown if busy else shop.tickets)
	_btn1.disabled = busy or not shop.can_spin(1, false)
	_btn10.disabled = busy or not shop.can_spin(10, false)
	_btn_ticket.disabled = busy or not shop.can_spin(1, true)
	var g: Dictionary = shop.cfg.get("gacha", {})
	_pity_l.text = _tr("pax_rpg_shop_pity") % [maxi(1, int(g.get("epic_pity", 10)) - shop.pity_epic),
		maxi(1, int(g.get("legend_pity", 70)) - shop.pity_legend)]
	var parts: PackedStringArray = PackedStringArray()
	var rt: Dictionary = g.get("rarity", {})
	for rar: String in RARITY_ORDER:
		var c := float((rt.get(rar, {}) as Dictionary).get("chance", 0.0)) * 100.0
		parts.append("%s %s %%" % [_tr("pax_rpg_shop_rarity_" + rar), String.num(c, 1 if c < 10.0 else 0)])
	_odds_l.text = _tr("pax_rpg_shop_odds") % " · ".join(parts)


func _spin(n: int, use_ticket: bool) -> void:
	if _spin_t >= 0.0:
		return
	if not shop.can_spin(n, use_ticket):
		_say(_tr("pax_rpg_shop_why_no_gold"), Color(1.0, 0.5, 0.45))
		return
	_gold_shown = shop.prog.gold - (0 if use_ticket else shop.spin_price(n))     # плата видна сразу, выигрыш — потом
	_tickets_shown = shop.tickets - (n if use_ticket else 0)
	_results = shop.spin(n, use_ticket)
	if _results.is_empty():
		return
	var best: Dictionary = _results[0]
	for rw: Dictionary in _results:
		if RARITY_ORDER.find(str(rw.rarity)) > RARITY_ORDER.find(str(best.rarity)):
			best = rw
	_grid = false
	_result_l.text = ""
	var target := 44 if n == 1 else 30
	_fill_strip(target, best)
	_off_from = fmod(_off, CARD.x + GAP)                       # лента начинается с того же места, что стояла
	_off_to = target * (CARD.x + GAP) + CARD.x * 0.5 - STRIP.size.x * 0.5 + randf_range(-CARD.x * 0.38, CARD.x * 0.38)
	_off = _off_from
	_spin_len = SPIN_TIME if n == 1 else SPIN10_TIME
	_spin_t = 0.0
	_win_i = -1
	_last_tick = int((_off + STRIP.size.x * 0.5) / (CARD.x + GAP))
	sound.emit("sounds/air_whoosh.wav", -8.0)
	_update_gacha()


## Лента: случайные карточки, на месте target — настоящая награда (target < 0 — просто заполнить).
func _fill_strip(target: int, win: Dictionary) -> void:
	_cards.clear()
	for i: int in 60:
		_cards.append(win if i == target else shop.filler())


func _spin_done() -> void:
	_win_i = int((_off + STRIP.size.x * 0.5) / (CARD.x + GAP))
	var best: Dictionary = _cards[clampi(_win_i, 0, _cards.size() - 1)]
	var rar := str(best.rarity)
	sound.emit({"legend": "sounds/iai_heart.wav", "epic": "sounds/spear_magic_finish.ogg"}.get(rar, "sounds/gear_4.ogg"),
		-2.0 if rar == "legend" else -6.0)
	if _results.size() > 1:
		_grid = true
		_grid_t = 0.0
		_result_l.text = _tr("pax_rpg_shop_won10") % _tr("pax_rpg_shop_rarity_" + rar)
	else:
		_result_l.text = _tr("pax_rpg_shop_won") % [_tr("pax_rpg_shop_rarity_" + rar), fx_text(str(best.effect), int(best.amount))]
	_result_l.add_theme_color_override("font_color", shop.rarity_color(rar))
	_update_gacha()
	if _goods_page.visible:
		_build_goods()


func _draw_strip() -> void:
	var sz := STRIP.size
	_strip.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.03, 0.9))
	if _grid:
		_draw_grid()
	else:
		var step := CARD.x + GAP
		var first := maxi(0, int(_off / step) - 1)
		for i: int in range(first, mini(_cards.size(), first + int(sz.x / step) + 3)):
			var x := i * step - _off
			var r := Rect2(Vector2(x, (sz.y - CARD.y) * 0.5), CARD)
			_draw_card(_strip, r, _cards[i], i == _win_i and _spin_t < 0.0)
		var cx := sz.x * 0.5                                    # метка
		var gold: Color = hud.c_gold if hud != null else Hud.GOLD
		_strip.draw_line(Vector2(cx, 0), Vector2(cx, sz.y), Color(gold, 0.9), 3.0)
		_strip.draw_colored_polygon(PackedVector2Array([Vector2(cx - 14, 0), Vector2(cx + 14, 0), Vector2(cx, 18)]), gold)
		_strip.draw_colored_polygon(PackedVector2Array([Vector2(cx - 14, sz.y), Vector2(cx + 14, sz.y), Vector2(cx, sz.y - 18)]), gold)
		for side: float in [0.0, 1.0]:                           # края ленты уходят в тень
			for k: int in 12:
				var w := 14.0
				var a := 0.85 * (1.0 - k / 12.0)
				_strip.draw_rect(Rect2(Vector2(k * w if side == 0.0 else sz.x - (k + 1) * w, 0), Vector2(w, sz.y)),
					Color(0.02, 0.02, 0.03, a))
	_strip.draw_rect(Rect2(Vector2.ZERO, sz), Color(hud.c_gold if hud != null else Hud.GOLD, 0.7), false, 2.0)


## ×10: десять наград сеткой 5 × 2, появляются по очереди.
func _draw_grid() -> void:
	var cw := 140.0
	var ch := 112.0
	var x0 := (STRIP.size.x - (cw * 5 + 16.0 * 4)) * 0.5
	for i: int in _results.size():
		var a := clampf((_grid_t - i * 0.12) * 4.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var r := Rect2(Vector2(x0 + (i % 5) * (cw + 16.0), 10.0 + (i / 5) * (ch + 10.0)), Vector2(cw, ch))
		_draw_card(_strip, r, _results[i], str((_results[i] as Dictionary).rarity) != "common", a)


func _draw_card(ci: CanvasItem, r: Rect2, c: Dictionary, lit: bool, alpha := 1.0) -> void:
	var col := shop.rarity_color(str(c.get("rarity", "common")))
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	ci.draw_rect(r, Color(0.06, 0.05, 0.07, 0.95 * alpha))
	ci.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.32, r.size.x, r.size.y * 0.32), Color(col, 0.22 * alpha))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), Color(col, 0.9 * alpha))
	ci.draw_rect(r, Color(col, (0.9 if lit else 0.55) * alpha), false, 3.0 if lit else 1.5)
	if lit:
		for k: int in 4:
			ci.draw_rect(r.grow(2.0 + k * 3.0), Color(col, (0.25 - k * 0.05) * (0.6 + 0.4 * pulse) * alpha), false, 2.0)
	var eff := str(c.get("effect", "gold"))
	var icon := _tex(str(FX_ICON.get(eff, "")))
	var big := r.size.y > 150.0
	var isz := r.size.y * (0.5 if big else 0.46)
	var ic := Vector2(r.get_center().x, r.position.y + r.size.y * 0.38)
	if icon != null:
		ci.draw_texture_rect(icon, Rect2(ic - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, alpha))
	else:
		var fs := int(isz * 0.8)
		ci.draw_string(_cjk, Vector2(r.position.x, ic.y + fs * 0.36), str(FX_GLYPH.get(eff, "?")), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, fs, Color(col.lerp(Color.WHITE, 0.25), alpha))
	var amt := int(c.get("amount", 1))
	var txt := ("×%d" % amt if eff == "ticket" else ("+%d" % amt if eff in ["gold", "xp"] else "+1")) if eff != "refill" else "♦"
	ci.draw_string(_sans, Vector2(r.position.x, r.end.y - (16.0 if big else 12.0)), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
		22 if big else 17, Color(1, 1, 1, alpha))


# ---------- фон ----------

func _draw_bg() -> void:
	var gold: Color = hud.c_gold if hud != null else Hud.GOLD
	if _bg_tex != null:
		_bg.draw_texture_rect(_bg_tex, Rect2(0, 0, W, H), false, Color(1, 1, 1, 0.55))
	_bg.draw_string(_serif, Vector2(120, 98), trader_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Hud.TEXT)
	_bg.draw_string(_sans, Vector2(122, 132), _tr("pax_rpg_npc_role_trader") + " · " + _tr("pax_rpg_shop_title"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Hud.MUTED)
	_bg.draw_line(Vector2(120, 216), Vector2(W - 120, 216), Color(gold, 0.45), 1.0)
	_bg.draw_line(Vector2(120, 930), Vector2(W - 120, 930), Color(gold, 0.3), 1.0)
	Hud.coin(_bg, Vector2(W - 470, 168), 22.0, _t, 0.0)            # золото героя
	_bg.draw_string(_serif, Vector2(W - 438, 182), str(_gold_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(1.0, 0.88, 0.58))
	_bg.draw_string(_cjk, Vector2(W - 270, 182), "運", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.72, 0.6, 1.0))   # жетоны
	_bg.draw_string(_serif, Vector2(W - 232, 182), "× %d" % _tickets_shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Hud.TEXT)
	if _gacha_page.visible:
		_bg.draw_string(_serif, Vector2(0, 270), _tr("pax_rpg_shop_wheel"), HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(gold, 0.95))


# ---------- мелочи ----------

func _panel(rect: Rect2, parent: Control, selected := false) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel_sh != null:
		var m := ShaderMaterial.new()
		m.shader = _panel_sh
		m.set_shader_parameter("px", rect.size)
		m.set_shader_parameter("selected", 1.0 if selected else 0.0)
		r.material = m
	else:
		r.color = Hud.INK
	parent.add_child(r)
	return r


## Текст карточки по центру с переносом по словам в рамке rect. RichTextLabel, а не Label: Label с переносом и системным
## шрифтом иногда растягивался под всю строку (ширина считалась до загрузки шрифта).
func _text(text: String, rect: Rect2, font: Font, fs: int, color: Color) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.text = "[center]%s[/center]" % text.replace("[", "[lb]")
	l.position = rect.position
	l.size = rect.size
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("normal_font", font)
	l.add_theme_font_size_override("normal_font_size", fs)
	l.add_theme_color_override("default_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goods_page.add_child(l)


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


func _button(text: String, r: Rect2, parent: Control, fs: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _serif)
	b.add_theme_font_size_override("font_size", fs)
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.1, 0.06, 0.07, 0.95), "hover": Color(0.22, 0.09, 0.1, 0.98),
			"pressed": Color(0.36, 0.1, 0.12, 1.0), "disabled": Color(0.07, 0.06, 0.07, 0.8)}[st]
		sb.border_color = Color(0.86, 0.66, 0.34, 0.35 if st == "disabled" else 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.72))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.45))
	parent.add_child(b)
	return b
