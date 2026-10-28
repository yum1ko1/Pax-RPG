extends RefCounted
## Лавка торговца и Колесо Судьбы (окно — shop_view.gd, числа — config/shop.json). Товар — вещи снаряжения
## (config/equipment.json: те же сеты, слоты, редкости и цены, что у добычи с врагов) и свои товары (эликсир,
## тыква-фляга). Прилавок обновляется раз в сутки по часам компьютера (reset_hour), у торговца каждого города свой
## (зерно — номер дня, run_seed и город); что на нём и что продано — помнится до новых суток. per_city — сколько штук
## товара продаст один город за всю игру (тыква-фляга — одна на город). Колесо Судьбы: золото за прокрут, редкость
## вещи — по весам с гарантами (эпическое не реже раза в epic_pity, легендарное не позже legend_pity-го); выпавшая
## вещь — в сумку (настройка inv_loot), как добыча. Золото и заряды фляги — progress.gd; эликсир — через granted.

signal granted(effect: String, amount: int)   # свой товар выдан (location.gd: refill — эликсир, flask — заряд)

const Names := preload("res://mods/pax_rpg/src/location/names.gd")
const Progress := preload("res://mods/pax_rpg/src/location/progress.gd")
const Equip := preload("res://mods/pax_rpg/src/location/inv/equip.gd")
const Fame := preload("res://mods/pax_rpg/src/location/fame.gd")

var mod: PaxMod
var prog: Progress                   # золото, уровень, заряды фляги
var eq := Equip.new()                # снаряжение: редкости, слоты, сеты, вещь по id
var cfg: Dictionary = {}
var day := -1                        # номер суток магазина (смена — в reset_hour)
var city := ""                       # город торговца
var stall := ""                      # чей прилавок: город (лавочник) или город/номер торговца — у каждого свой товар
var goods: Array = []                # прилавок: [{"kind": "item"|"good", "id", "price", "left", "r"}]
var pity_epic := 0                   # прокрутов без эпического и выше
var pity_legend := 0                 # прокрутов без легендарного и выше
var owned: Dictionary = {}           # свои товары с cap, купленные в лавке: id → сколько
var _sold: Dictionary = {}           # куплено сегодня: город → {id → сколько}
var _stall: Dictionary = {}          # прилавок сегодня: город → {"items": [id вещи], "goods": [id товара]}
var _city_bought: Dictionary = {}    # куплено в городе за всю игру (для per_city): город → {id → сколько}
var _rng := RandomNumberGenerator.new()


func setup(m: PaxMod, p: Progress) -> void:
	mod = m
	prog = p
	eq.load_data(m)
	var parsed: Variant = JSON.parse_string(m.read_text("config/shop.json"))
	cfg = parsed if parsed is Dictionary else {}
	_rng.randomize()
	var s: Variant = m.get_setting("shop", {})
	if s is Dictionary:
		var d: Dictionary = s
		day = int(d.get("day", -1))
		pity_epic = int(d.get("pity_epic", 0))
		pity_legend = int(d.get("pity_legend", 0))
		owned = d.get("owned", {}) if d.get("owned", {}) is Dictionary else {}
		_sold = d.get("sold", {}) if d.get("sold", {}) is Dictionary else {}
		_stall = d.get("stall", {}) if d.get("stall", {}) is Dictionary else {}
		_city_bought = d.get("city_bought", {}) if d.get("city_bought", {}) is Dictionary else {}
	refresh()


func _save() -> void:
	mod.set_setting("shop", {"day": day, "pity_epic": pity_epic, "pity_legend": pity_legend, "owned": owned,
		"sold": _sold, "stall": _stall, "city_bought": _city_bought})


func gacha() -> Dictionary:
	return cfg.get("gacha", {}) if cfg.get("gacha", {}) is Dictionary else {}


func good(id: String) -> Dictionary:
	var g: Variant = (cfg.get("goods", {}) as Dictionary).get(id, {}) if cfg.get("goods", {}) is Dictionary else {}
	return g if g is Dictionary else {}


func rarity_name(r: int) -> String:
	return str((eq.rar[clampi(r, 0, eq.rar.size() - 1)] as Dictionary).get("name", ""))


## Вещь прилавка или рулетки целиком (статы, имя, цена) — как в инвентаре, на уровне героя.
func item(id: String) -> Dictionary:
	return eq.from_id(id, prog.level)


# ---------- сутки ----------

## Секунды местного времени со сдвигом на час обновления: целые сутки — номер дня магазина.
func _clock() -> float:
	var tz: Dictionary = Time.get_time_zone_from_system()
	return Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0 - float(cfg.get("reset_hour", 4)) * 3600.0


func secs_to_reset() -> int:
	return int(86400.0 - fmod(_clock(), 86400.0))


## Торговец какого города (location.gd — id города) и какой из его торговцев (s — номер жителя, "" — лавочник): его
## прилавок. Город за всю игру (per_city) считается общим на всех его торговцев.
func set_city(c: String, s := "") -> void:
	city = c
	stall = c if s == "" else c + "/" + s
	refresh()


## Наступили новые сутки — новые прилавки (купленное за день забыто). Иначе — тот же товар, минус проданное.
func refresh() -> void:
	var d := int(floor(_clock() / 86400.0))
	if d != day:
		day = d
		_sold = {}
		_stall = {}
		_save()
	if not _stall.has(stall):
		_roll_stall()
	_build_goods()


## Прилавок дня: вещи (редкость по item_rarity_w, слот и сет — случайно, без повторов слот+сет) и свои товары
## (с chance — не каждый день; что уже не продать — не выкладывается).
func _roll_stall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, Names.run_seed(mod), stall])
	var items: Array = []
	var taken: Dictionary = {}
	var sets: Array = cfg.get("item_sets", ["samurai"])
	for i: int in int(cfg.get("items", 5)):
		var r := _pick_w(cfg.get("item_rarity_w", [1]), rng)
		var k := rng.randi_range(0, eq.slots.size() - 1)
		var key := str(sets[rng.randi_range(0, sets.size() - 1)])
		for attempt: int in 8:                                  # тот же слот того же сета дважды — не выкладываем
			if not taken.has("%d:%s" % [k, key]):
				break
			k = rng.randi_range(0, eq.slots.size() - 1)
		taken["%d:%s" % [k, key]] = true
		items.append("%d:%s-%d#shop%d_%d_%d" % [k, key, r, day, absi(hash(stall)) % 100000, i])
	var own: Array = []
	for id: Variant in cfg.get("goods", {}):
		var g := good(str(id))
		var roll := rng.randf()                                 # бросок — всегда, чтобы прилавок не зависел от покупок
		if g.has("chance") and roll >= float(g.chance):
			continue
		if _capped(str(id)) or _city_limited(str(id)):
			continue
		own.append(str(id))
	_stall[stall] = {"items": items, "goods": own}
	_save()


static func _pick_w(w: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for x: Variant in w:
		total += float(x)
	var roll := rng.randf() * total
	for i: int in w.size():
		roll -= float(w[i])
		if roll < 0.0 and float(w[i]) > 0.0:
			return i
	return maxi(0, w.size() - 1)


## Карточки прилавка: вещи (цена — как у вещи × markup) и свои товары (рост цены за купленные).
func _build_goods() -> void:
	goods.clear()
	var st: Dictionary = _stall.get(stall, {})
	var sold: Dictionary = _sold.get(stall, {})
	for id: Variant in st.get("items", []):
		var it := item(str(id))
		if it.is_empty():
			continue
		goods.append({"kind": "item", "id": str(id), "r": int(it.r), "left": 0 if sold.has(str(id)) else 1,
			"price": maxi(1, roundi(int(it.price) * float(cfg.get("markup", 1.0)) * Fame.discount_mult(mod)))})
	for id: Variant in st.get("goods", []):
		var g := good(str(id))
		if g.is_empty():
			continue
		goods.append({"kind": "good", "id": str(id), "r": -1, "price": _price(str(id)),
			"left": maxi(0, int(g.get("stock", 1)) - int(sold.get(str(id), 0)))})


## Цена своего товара: растёт с каждой купленной (price · grow^куплено); круглая до 5.
func _price(id: String) -> int:
	var g := good(id)
	var p := float(g.get("price", 0)) * pow(float(g.get("grow", 1.0)), int(owned.get(id, 0))) * Fame.discount_mult(mod)
	return maxi(5, roundi(p / 5.0) * 5)


## Предел у героя (cap): фляга — по зарядам героя.
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


# ---------- покупка ----------

## Почему нельзя купить ("" — можно): city_sold (город своё уже продал), sold_out, capped, no_gold.
func why_not(i: int) -> String:
	if i < 0 or i >= goods.size():
		return "sold_out"
	var it: Dictionary = goods[i]
	if str(it.kind) == "good" and _city_limited(str(it.id)):
		return "city_sold"
	if int(it.left) <= 0:
		return "sold_out"
	if str(it.kind) == "good" and _capped(str(it.id)):
		return "capped"
	if prog.gold < int(it.price):
		return "no_gold"
	return ""


func buy(i: int) -> bool:
	if why_not(i) != "":
		return false
	var it: Dictionary = goods[i]
	var id := str(it.id)
	prog.add_gold(-int(it.price))
	var sold: Dictionary = _sold.get(stall, {})
	sold[id] = int(sold.get(id, 0)) + 1
	_sold[stall] = sold
	if str(it.kind) == "item":
		_to_bag([id])
	else:
		var g := good(id)
		if g.has("cap"):
			owned[id] = int(owned.get(id, 0)) + 1
		if int(g.get("per_city", 0)) > 0:
			var cb: Dictionary = _city_bought.get(city, {})
			cb[id] = int(cb.get(id, 0)) + 1
			_city_bought[city] = cb
		if str(g.get("effect", "")) == "flask":
			prog.add_flask()
		granted.emit(str(g.get("effect", "")), 1)
	_save()
	_build_goods()                                   # остаток и новая цена
	return true


## Вещи — в сумку героя (настройка inv_loot: инвентарь показывает их в выборе своего слота).
func _to_bag(ids: Array) -> void:
	var loot: Variant = mod.get_setting("inv_loot", [])
	var list: Array = (loot as Array).duplicate() if loot is Array else []
	list.append_array(ids)
	mod.set_setting("inv_loot", list)


# ---------- Колесо Судьбы ----------

func spin_price(n: int) -> int:
	var g := gacha()
	return int(g.get("spin10", 2250)) if n >= 10 else int(g.get("spin", 250)) * n


func can_spin(n: int) -> bool:
	return prog.gold >= spin_price(n)


## Прокрутить n раз: золото списано, редкости — с гарантами. Возвращает вещи по порядку:
## [{"id", "r", "k", "set", "mana"}]. В сумку кладёт окно (add_to_bag) — после того как показало прокрутку.
func spin(n: int) -> Array:
	if not can_spin(n):
		return []
	prog.add_gold(-spin_price(n))
	var out: Array = []
	var good_seen := false                           # в десятке — хотя бы одна редкая или выше
	for i: int in n:
		var r := _roll_rarity()
		if n >= 10 and i == n - 1 and not good_seen and r < 2:
			r = 2
		if r >= 2:
			good_seen = true
		out.append(_new_item(r))
	_save()
	return out


func add_to_bag(list: Array) -> void:
	var ids: Array = []
	for it: Dictionary in list:
		ids.append(str(it.id))
	_to_bag(ids)


## Шанс легендарного и выше на следующем прокруте: по весам, с soft_from — растёт, на legend_pity — наверняка.
func legend_chance() -> float:
	var g := gacha()
	var w: Array = g.get("rarity_w", [1])
	var total := 0.0
	var hi := 0.0
	for i: int in w.size():
		total += float(w[i])
		if i >= 4:
			hi += float(w[i])
	var c := hi / maxf(total, 0.001)
	var n := pity_legend + 1
	if n >= int(g.get("soft_from", 35)):
		c += (n - int(g.get("soft_from", 35)) + 1) * float(g.get("soft_step", 0.06))
	if n >= int(g.get("legend_pity", 50)):
		c = 1.0
	return minf(c, 1.0)


func _roll_rarity() -> int:
	var g := gacha()
	var w: Array = g.get("rarity_w", [1])
	var lc := legend_chance()
	pity_epic += 1
	pity_legend += 1
	var r := 0
	if w.size() > 4 and _rng.randf() < lc:             # легендарное и выше: внутри — по своим весам
		r = 4 + _pick_w(w.slice(4), _rng)
	else:
		r = _pick_w(w.slice(0, mini(4, w.size())), _rng)
		if pity_epic >= int(g.get("epic_pity", 10)):
			r = 3
	if r >= 4:
		pity_legend = 0
		pity_epic = 0
	elif r == 3:
		pity_epic = 0
	return clampi(r, 0, eq.rar.size() - 1)


func _new_item(r: int) -> Dictionary:
	var sets: Array = cfg.get("item_sets", ["samurai"])
	var key := str(sets[_rng.randi_range(0, sets.size() - 1)])
	var k := _rng.randi_range(0, eq.slots.size() - 1)
	var mana := _rng.randf() < float(gacha().get("mana_chance", 0.04))
	var id := "%d:%s-%d%s#wheel%d%03d" % [k, key, r, "-m" if mana else "", int(Time.get_unix_time_from_system()), _rng.randi_range(0, 999)]
	return {"id": id, "r": r, "k": k, "set": key, "mana": mana}
