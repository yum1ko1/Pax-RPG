extends RefCounted
## Лавка торговца и рулетка (окно — shop_view.gd, числа — config/shop.json). Товар дня обновляется раз в сутки по
## часам компьютера (reset_hour): у торговца каждого города свой прилавок (зерно — номер дня, run_seed и город), что
## на нём сегодня и что продано — помнится до новых суток. Вечные улучшения (фляга, свиток пути) дорожают с каждой
## покупкой; per_city — сколько штук товара продаст один город за всю игру (тыква-фляга — одна на город). Рулетка: платишь
## золото (или жетон) — выпадает награда по редкости; гарант эпического раз в epic_pity прокрутов и легендарного
## не позже legend_pity-го (с soft_from шанс легендарного растёт). Золото, очки характеристик, заряды фляги и
## жетоны начисляет сам (progress.gd, своя настройка «shop»); эликсир и опыт — через granted (location.gd).

signal granted(effect: String, amount: int)   # любая выданная награда (location.gd: refill — эликсир, xp — опыт)

const Names := preload("res://mods/pax_rpg/src/location/names.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const RARITIES := ["common", "rare", "epic", "legend"]

var mod: PaxMod
var prog: Progress                   # золото, очки характеристик, заряды фляги
var cfg: Dictionary = {}
var day := -1                        # номер суток магазина (смена — в reset_hour)
var goods: Array = []                # товар дня: [{"id", "price", "left", "deal"}]
var tickets := 0                     # жетоны рулетки
var pity_epic := 0                   # прокрутов без эпического и выше
var pity_legend := 0                 # прокрутов без легендарного
var owned: Dictionary = {}           # вечные улучшения, купленные в лавке: id → сколько
var city := ""                       # город торговца (у каждого свой прилавок)
var _sold: Dictionary = {}           # куплено сегодня: город → {id → сколько}
var _stall: Dictionary = {}          # прилавок сегодня: город → {"ids": [...], "deal": id}
var _city_bought: Dictionary = {}    # куплено в городе за всю игру (для per_city): город → {id → сколько}
var _rng := RandomNumberGenerator.new()


func setup(m: PaxMod, p: Progress) -> void:
	mod = m
	prog = p
	var parsed: Variant = JSON.parse_string(m.read_text("config/shop.json"))
	cfg = parsed if parsed is Dictionary else {}
	_rng.randomize()
	var s: Variant = m.get_setting("shop", {})
	if s is Dictionary:
		var d: Dictionary = s
		day = int(d.get("day", -1))
		tickets = int(d.get("tickets", 0))
		pity_epic = int(d.get("pity_epic", 0))
		pity_legend = int(d.get("pity_legend", 0))
		owned = d.get("owned", {}) if d.get("owned", {}) is Dictionary else {}
		_sold = d.get("sold", {}) if d.get("sold", {}) is Dictionary else {}
		_stall = d.get("stall", {}) if d.get("stall", {}) is Dictionary else {}
		_city_bought = d.get("city_bought", {}) if d.get("city_bought", {}) is Dictionary else {}
	refresh()


func _save() -> void:
	mod.set_setting("shop", {"day": day, "tickets": tickets, "pity_epic": pity_epic, "pity_legend": pity_legend,
		"owned": owned, "sold": _sold, "stall": _stall, "city_bought": _city_bought})


func _gacha() -> Dictionary:
	return cfg.get("gacha", {}) if cfg.get("gacha", {}) is Dictionary else {}


func good(id: String) -> Dictionary:
	var g: Variant = (cfg.get("goods", {}) as Dictionary).get(id, {}) if cfg.get("goods", {}) is Dictionary else {}
	return g if g is Dictionary else {}


# ---------- сутки ----------

## Секунды местного времени со сдвигом на час обновления: целые сутки — номер дня магазина.
func _clock() -> float:
	var tz: Dictionary = Time.get_time_zone_from_system()
	return Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0 - float(cfg.get("reset_hour", 4)) * 3600.0


func secs_to_reset() -> int:
	return int(86400.0 - fmod(_clock(), 86400.0))


## Торговец какого города (location.gd — id города): его прилавок.
func set_city(c: String) -> void:
	city = c
	refresh()


## Наступили новые сутки — новые прилавки (купленное за день забыто). Иначе — тот же товар, минус проданное.
func refresh() -> void:
	var d := int(floor(_clock() / 86400.0))
	if d != day:
		day = d
		_sold = {}
		_stall = {}
		_save()
	if not _stall.has(city):
		_roll_stall()
	_build_goods()


## Что сегодня на прилавке города: pinned и slots случайных по weight (без того, что уже не продать). Раз в сутки —
## покупки за день прилавок не тасуют.
func _roll_stall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, Names.run_seed(mod), city])
	var ids: Array = []
	for id: Variant in cfg.get("pinned", []):
		ids.append(str(id))
	var pool: Dictionary = {}
	for id: Variant in cfg.get("goods", {}):
		var g := good(str(id))
		if not ids.has(str(id)) and int(g.get("weight", 0)) > 0 and not _capped(str(id)) and not _city_limited(str(id)):
			pool[str(id)] = int(g.weight)
	var picked: Array = []
	for i: int in int(cfg.get("slots", 3)):
		var total := 0
		for id: Variant in pool:
			total += int(pool[id])
		if total <= 0:
			break
		var r := rng.randi_range(1, total)
		for id: Variant in pool:
			r -= int(pool[id])
			if r <= 0:
				picked.append(str(id))
				pool.erase(id)
				break
	var deal := str(picked[rng.randi() % picked.size()]) if not picked.is_empty() else ""
	ids.append_array(picked)
	_stall[city] = {"ids": ids, "deal": deal}
	_save()


## Карточки прилавка: цена (рост улучшений, скидка дня) и остаток на сегодня.
func _build_goods() -> void:
	goods.clear()
	var st: Dictionary = _stall.get(city, {})
	var deal := str(st.get("deal", ""))
	var sold: Dictionary = _sold.get(city, {})
	for id: Variant in st.get("ids", []):
		var g := good(str(id))
		if g.is_empty():
			continue
		goods.append({"id": str(id), "deal": str(id) == deal, "price": _price(str(id), str(id) == deal),
			"left": maxi(0, int(g.get("stock", 1)) - int(sold.get(str(id), 0)))})


## Цена: вечные улучшения дорожают (price · grow^куплено), выгода дня — со скидкой; круглая до 5.
func _price(id: String, deal: bool) -> int:
	var g := good(id)
	var p := float(g.get("price", 0)) * pow(float(g.get("grow", 1.0)), int(owned.get(id, 0)))
	if deal:
		p *= 1.0 - float(cfg.get("deal_off", 0.3))
	return maxi(5, roundi(p / 5.0) * 5)


## Улучшение больше не взять: фляга — по зарядам героя (и из рулетки тоже), свиток пути — по купленным в лавке.
func _capped(id: String) -> bool:
	var g := good(id)
	if not g.has("cap"):
		return false
	if str(g.get("effect", "")) == "flask":
		return prog.flask_bonus >= int(g.cap)
	return int(owned.get(id, 0)) >= int(g.cap)


## Город продал всё, что мог, за всю игру (per_city): тыква-фляга — одна на город.
func _city_limited(id: String) -> bool:
	var n := int(good(id).get("per_city", 0))
	return n > 0 and int((_city_bought.get(city, {}) as Dictionary).get(id, 0)) >= n


func _flask_capped() -> bool:
	for id: Variant in cfg.get("goods", {}):
		if str(good(str(id)).get("effect", "")) == "flask":
			return _capped(str(id))
	return false


# ---------- покупка ----------

## Почему нельзя купить ("" — можно): sold_out, city_sold (город своё уже продал), capped, no_gold.
func why_not(i: int) -> String:
	if i < 0 or i >= goods.size():
		return "sold_out"
	var it: Dictionary = goods[i]
	if _city_limited(str(it.id)):
		return "city_sold"
	if int(it.left) <= 0:
		return "sold_out"
	if _capped(str(it.id)):
		return "capped"
	if prog.gold < int(it.price):
		return "no_gold"
	return ""


func buy(i: int) -> bool:
	if why_not(i) != "":
		return false
	var it: Dictionary = goods[i]
	var id := str(it.id)
	var g := good(id)
	prog.add_gold(-int(it.price))
	var sold: Dictionary = _sold.get(city, {})
	sold[id] = int(sold.get(id, 0)) + 1
	_sold[city] = sold
	if g.has("cap"):
		owned[id] = int(owned.get(id, 0)) + 1
	if int(g.get("per_city", 0)) > 0:
		var cb: Dictionary = _city_bought.get(city, {})
		cb[id] = int(cb.get(id, 0)) + 1
		_city_bought[city] = cb
	_save()
	_give(str(g.get("effect", "")), int(g.get("amount", 1)))
	_build_goods()                                   # остаток и новая цена улучшения
	return true


func _give(effect: String, amount: int) -> void:
	match effect:
		"gold":
			prog.add_gold(amount)
		"stat":
			prog.add_bonus_point()
		"flask":
			prog.add_flask()
		"ticket":
			tickets += amount
			_save()
	granted.emit(effect, amount)


# ---------- рулетка ----------

## Хватает ли на n прокрутов: жетонами (use_ticket) или золотом.
func can_spin(n: int, use_ticket: bool) -> bool:
	if use_ticket:
		return tickets >= n
	return prog.gold >= spin_price(n)


func spin_price(n: int) -> int:
	var g := _gacha()
	return int(g.get("spin10", 900)) if n >= 10 else int(g.get("spin", 100)) * n


## Прокрутить n раз. Возвращает награды по порядку: [{"rarity", "effect", "amount"}]; уже выданы.
func spin(n: int, use_ticket: bool) -> Array:
	if not can_spin(n, use_ticket):
		return []
	if use_ticket:
		tickets -= n
	else:
		prog.add_gold(-spin_price(n))
	var out: Array = []
	var good_seen := false                           # в десятке — хотя бы одна редкая или выше
	for k: int in n:
		var rar := _roll_rarity()
		if n >= 10 and k == n - 1 and not good_seen and rar == "common":
			rar = "rare"
		if rar != "common":
			good_seen = true
		var rw := _pick_reward(rar)
		out.append(rw)
	_save()
	for rw: Dictionary in out:
		_give(str(rw.effect), int(rw.amount))
	return out


## Шанс легендарного сейчас: базовый, с soft_from — растёт на soft_step за прокрут, на legend_pity — наверняка.
func legend_chance() -> float:
	var g := _gacha()
	var c := float(((g.get("rarity", {}) as Dictionary).get("legend", {}) as Dictionary).get("chance", 0.008))
	var n := pity_legend + 1
	if n >= int(g.get("soft_from", 50)):
		c += (n - int(g.get("soft_from", 50)) + 1) * float(g.get("soft_step", 0.06))
	if n >= int(g.get("legend_pity", 70)):
		c = 1.0
	return minf(c, 1.0)


func _roll_rarity() -> String:
	var g := _gacha()
	var rt: Dictionary = g.get("rarity", {})
	pity_epic += 1
	pity_legend += 1
	var pl := legend_chance()
	var pe := float((rt.get("epic", {}) as Dictionary).get("chance", 0.06))
	var pr := float((rt.get("rare", {}) as Dictionary).get("chance", 0.27))
	var r := _rng.randf()
	var rar := "common"
	if r < pl:
		rar = "legend"
	elif r < pl + pe or pity_epic >= int(g.get("epic_pity", 10)):
		rar = "epic"
	elif r < pl + pe + pr:
		rar = "rare"
	if rar == "legend":
		pity_legend = 0
		pity_epic = 0
	elif rar == "epic":
		pity_epic = 0
	return rar


func _pick_reward(rar: String) -> Dictionary:
	var g := _gacha()
	var pool: Array = (g.get("pool", {}) as Dictionary).get(rar, [])
	var options: Array = []
	var total := 0
	for e: Variant in pool:
		if e is Dictionary and not (str((e as Dictionary).get("effect", "")) == "flask" and _flask_capped()):
			options.append(e)
			total += int((e as Dictionary).get("weight", 1))
	var pick: Dictionary = {}
	if total > 0:
		var r := _rng.randi_range(1, total)
		for e: Dictionary in options:
			r -= int(e.get("weight", 1))
			if r <= 0:
				pick = e
				break
	if pick.is_empty():
		pick = (g.get("fallback", {}) as Dictionary).get(rar, {"effect": "gold", "amount": 10})
	return {"rarity": rar, "effect": str(pick.get("effect", "gold")), "amount": int(pick.get("amount", 1))}


func rarity_color(rar: String) -> Color:
	var c: Variant = (((_gacha().get("rarity", {}) as Dictionary).get(rar, {})) as Dictionary).get("color", [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() >= 3 else Color.WHITE


## Случайная награда для ленты рулетки (только вид, ничего не выдаёт): редкость по базовым шансам.
func filler() -> Dictionary:
	var rt: Dictionary = _gacha().get("rarity", {})
	var r := _rng.randf()
	var rar := "common"
	var acc := 0.0
	for k: String in ["legend", "epic", "rare"]:
		acc += float((rt.get(k, {}) as Dictionary).get("chance", 0.0)) * 3.0    # на ленте яркие мелькают чаще
		if r < acc:
			rar = k
			break
	var pool: Array = ((_gacha().get("pool", {}) as Dictionary).get(rar, []))
	var e: Dictionary = pool[_rng.randi() % pool.size()] if not pool.is_empty() else {"effect": "gold", "amount": 10}
	return {"rarity": rar, "effect": str(e.get("effect", "gold")), "amount": int(e.get("amount", 1))}
