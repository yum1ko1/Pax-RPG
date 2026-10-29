extends RefCounted
## Мини-задание жителя (одно за раз): житель (talk.gd, манера/слова «задание») просит найти потерянную вещь в лесу у
## своего города. Задание — запись в настройках мода «quest»: кто дал (город, номер жителя, имя), что найти, зерно леса
## (forest.gd), где точка на глобусе, состояние active → found → (сдано: запись стёрта, точка и лес исчезают).
## Отношения жителей к герою — «npc_rel» (город → номер жителя → 0..100): переживают выход из города.
##
## Поручения (контракты) Гхарна — четыре заготовки CONTRACTS из забот жителей: кузнец (принести), стражник и охотник
## (убить), пастух (спасти). Квестодатель — кузнец Кузнечного двора и первые жители своей роли (bind_givers).
## Поручение — та же запись «quest» с полем «contract» (id заготовки) и «kind»: fetch — вещь в лагере, kill — вожак
## лагеря, rescue — пленник в клетке. «found» — дело сделано, осталось вернуться. Сданные — «contracts_done»,
## спасённые — «rescued» (ждут героя у ворот города). Логово — тот же лес (forest.gd) с лагерем в конце.

const ITEMS := ["amulet", "pouch", "dagger", "lamp", "ring", "scroll"]

## id → роль квестодателя, вид, вещь (fetch), ступень (сколько поручений сдано до него), награда, кто в лагере и
## на полпути (дозор), вожак лагеря (kind для location._arena_spawn), реквизит лагеря.
const CONTRACTS := {
	"coal": {"role": "blacksmith", "alt": "smith", "kind": "fetch", "item": "coal", "tier": 0, "gold": 120, "xp": 90,
		"patrol": 2, "camp": 2, "leader": "", "props": "caravan"},
	"scouts": {"role": "guard", "kind": "kill", "tier": 0, "gold": 150, "xp": 120,
		"patrol": 2, "camp": 2, "leader": "veteran", "props": "camp"},
	"shepherd": {"role": "herder", "kind": "rescue", "tier": 1, "gold": 180, "xp": 150, "loot": 1,
		"patrol": 3, "camp": 2, "leader": "veteran", "props": "cage"},
	"beast": {"role": "hunter", "kind": "kill", "tier": 2, "gold": 300, "xp": 240, "loot": 2,
		"patrol": 2, "camp": 2, "leader": "orc", "props": "lair"},
}
const ORDER := ["coal", "scouts", "shepherd", "beast"]


static func get_q(mod: PaxMod) -> Dictionary:
	var q: Variant = mod.get_setting("quest", {})
	return q if q is Dictionary else {}


static func active(mod: PaxMod) -> bool:
	return not get_q(mod).is_empty()


## Новое задание от жителя: вещь, зерно леса, точка на глобусе рядом с городом (lat/lon города + сдвиг).
static func give(mod: PaxMod, city: Dictionary, npc_index: int, npc_name: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var q := {
		"city": str(city.get("id", "")), "npc": npc_index, "npc_name": npc_name,
		"item": ITEMS[rng.randi() % ITEMS.size()], "seed": rng.randi(), "state": "active", "goblins": 2,
		"lat": float(city.get("lat", 0.0)) + rng.randf_range(1.2, 2.0) * (1.0 if rng.randf() < 0.5 else -1.0),
		"lon": float(city.get("lon", 0.0)) + rng.randf_range(1.2, 2.0) * (1.0 if rng.randf() < 0.5 else -1.0),
	}
	mod.set_setting("quest", q)
	return q


static func found(mod: PaxMod) -> void:
	var q := get_q(mod)
	if q.is_empty():
		return
	q["state"] = "found"
	mod.set_setting("quest", q)


## Сдано: запись стёрта — точка на глобусе и лес (он строится только по ней) пропадают.
static func finish(mod: PaxMod) -> void:
	mod.set_setting("quest", {})


static func relation(mod: PaxMod, city: String, idx: int, def: int) -> int:
	var all: Variant = mod.get_setting("npc_rel", {})
	var c: Variant = (all as Dictionary).get(city, {}) if all is Dictionary else {}
	if c is Dictionary:
		return int((c as Dictionary).get(str(idx), def))
	return def


static func set_relation(mod: PaxMod, city: String, idx: int, v: int) -> void:
	var all: Variant = mod.get_setting("npc_rel", {})
	var d: Dictionary = all if all is Dictionary else {}
	var c: Dictionary = d.get(city, {}) if d.get(city, {}) is Dictionary else {}
	c[str(idx)] = v
	d[city] = c
	mod.set_setting("npc_rel", d)


# ---------- поручения ----------

static func _arr(mod: PaxMod, key: String) -> Array:
	var v: Variant = mod.get_setting(key, [])
	return v if v is Array else []


static func done_list(mod: PaxMod) -> Array:
	return _arr(mod, "contracts_done")


static func is_done(mod: PaxMod, id: String) -> bool:
	return done_list(mod).has(id)


## Поручение открыто: не сдано и сдано не меньше «ступени» других.
static func available(mod: PaxMod, id: String) -> bool:
	return CONTRACTS.has(id) and not is_done(mod, id) and done_list(mod).size() >= int((CONTRACTS[id] as Dictionary).tier)


## Квестодатели города: id поручения → номер жителя. Один раз на прохождение (run_seed): первый житель нужной роли,
## нет такого — любой мирный житель с маршрута, ещё не занятый.
static func bind_givers(mod: PaxMod, city_id: String, npcs: Array) -> Dictionary:
	if city_id != "gharn":
		return {}
	var all: Variant = mod.get_setting("givers", {})
	var g: Dictionary = all if all is Dictionary else {}
	var seed_v := int(mod.get_setting("run_seed", 0))
	if int(g.get("seed", -1)) == seed_v and (g.get("npc", {}) as Dictionary).size() == ORDER.size():
		return g.npc
	var by: Dictionary = {}
	var used: Dictionary = {}
	for pass_i: int in 3:                                    # своя роль, запасная роль, любой мирный житель
		for id: String in ORDER:
			if by.has(id):
				continue
			var want := str((CONTRACTS[id] as Dictionary).role) if pass_i == 0 else str((CONTRACTS[id] as Dictionary).get("alt", ""))
			for n: Variant in npcs:
				if not is_instance_valid(n):
					continue
				var idx := int((n as Node).get("npc_index"))
				if idx < 0 or idx >= 1000 or used.has(idx):           # 1000+ — торговцы базара, 2000+ — спасённые
					continue
				if pass_i < 2 and str((n as Node).get("role")) != want:
					continue
				if pass_i == 2 and str((n as Node).get("role")) in ["arena_master", "seer", "trader", "blacksmith"]:
					continue
				by[id] = idx
				used[idx] = true
				break
	mod.set_setting("givers", {"seed": seed_v, "npc": by})
	return by


## Какое поручение у жителя (id или ""): по привязке bind_givers.
static func contract_of(mod: PaxMod, city_id: String, npc_index: int) -> String:
	if city_id != "gharn":
		return ""
	var all: Variant = mod.get_setting("givers", {})
	var by: Variant = (all as Dictionary).get("npc", {}) if all is Dictionary else {}
	if by is Dictionary:
		for id: Variant in by:
			if int(by[id]) == npc_index:
				return str(id)
	return ""


## Значок над жителем и на карте: offer — есть поручение для героя, turn_in — можно сдать, wait — взято, ждёт; "" — нет.
static func marker(mod: PaxMod, city_id: String, npc_index: int) -> String:
	var q := get_q(mod)
	if not q.is_empty() and str(q.get("city", "")) == city_id and int(q.get("npc", -1)) == npc_index:
		return "turn_in" if str(q.get("state", "")) == "found" else "wait"
	var id := contract_of(mod, city_id, npc_index)
	if id != "" and q.is_empty() and available(mod, id):
		return "offer"
	return ""


## Принять поручение id от жителя: запись «quest» с полями поручения; лес-логово по зерну, точка на глобусе рядом.
static func take(mod: PaxMod, city: Dictionary, id: String, npc_index: int, npc_name: String) -> Dictionary:
	var c: Dictionary = CONTRACTS[id]
	var q := give(mod, city, npc_index, npc_name)
	q["contract"] = id
	q["kind"] = str(c.kind)
	q["item"] = str(c.get("item", "")) if str(c.kind) == "fetch" else ""
	q["goblins"] = int(c.camp)
	if str(c.kind) == "rescue":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(q.seed)
		q["captive"] = mod.tr_key("pax_rpg_contract_captive_" + id) % _captive_name(mod, rng)
	mod.set_setting("quest", q)
	return q


static func _captive_name(mod: PaxMod, rng: RandomNumberGenerator) -> String:
	return preload("res://mods/pax_rpg/src/location/names.gd").goblin_name(mod, rng)


## Поручение сдано: в «contracts_done», спасённый — в «rescued» (город, имя, роль), запись задания стёрта.
static func complete(mod: PaxMod) -> Dictionary:
	var q := get_q(mod)
	var id := str(q.get("contract", ""))
	if id != "":
		var d := done_list(mod).duplicate()
		if not d.has(id):
			d.append(id)
		mod.set_setting("contracts_done", d)
		if str(q.get("kind", "")) == "rescue":
			var r := _arr(mod, "rescued").duplicate()
			r.append({"city": str(q.get("city", "")), "name": str(q.get("captive", "")), "role": "herder", "id": id})
			mod.set_setting("rescued", r)
	finish(mod)
	return q


static func rescued(mod: PaxMod, city_id: String) -> Array:
	return _arr(mod, "rescued").filter(func(r: Variant) -> bool:
		return r is Dictionary and str((r as Dictionary).get("city", "")) == city_id)


## Что сделать — одной строкой: «Найти: …», «Убить вожака: …», «Освободить: …».
static func goal(mod: PaxMod, q: Dictionary) -> String:
	match str(q.get("kind", "fetch")):
		"kill":
			return mod.tr_key("pax_rpg_contract_goal_kill") % mod.tr_key("pax_rpg_contract_leader_" + str(q.get("contract", "")))
		"rescue":
			return mod.tr_key("pax_rpg_contract_goal_rescue") % str(q.get("captive", ""))
	return mod.tr_key("pax_rpg_journal_find") % mod.tr_key("pax_rpg_qitem_" + str(q.get("item", "")))


## Короткое имя цели (для подписей на глобусе): вещь, вожак или пленник.
static func short(mod: PaxMod, q: Dictionary) -> String:
	match str(q.get("kind", "fetch")):
		"kill":
			return mod.tr_key("pax_rpg_contract_leader_" + str(q.get("contract", "")))
		"rescue":
			return str(q.get("captive", ""))
	return mod.tr_key("pax_rpg_qitem_" + str(q.get("item", "")))


## Название места задания: у поручения — своё логово, у простого задания — лес.
static func place(mod: PaxMod, q: Dictionary) -> String:
	var id := str(q.get("contract", ""))
	return mod.tr_key("pax_rpg_contract_place_" + id) if id != "" else mod.tr_key("pax_rpg_city_forest")


static func reward_gold(q: Dictionary) -> int:
	var id := str(q.get("contract", ""))
	return int((CONTRACTS[id] as Dictionary).gold) if CONTRACTS.has(id) else randi_range(80, 150)


static func reward_xp(q: Dictionary) -> float:
	var id := str(q.get("contract", ""))
	return float((CONTRACTS[id] as Dictionary).xp) if CONTRACTS.has(id) else 60.0


static func reward_loot(q: Dictionary) -> int:
	var id := str(q.get("contract", ""))
	return int((CONTRACTS[id] as Dictionary).get("loot", 0)) if CONTRACTS.has(id) else 0


# ---------- цена поражения ----------

## Пал вне арены: часть монет (lose) остаётся кошелём на месте гибели — запись «lost_purse» (место, точка, сколько).
## Прежний несобранный кошель пропадает. Вернулся и подобрал — монеты снова у героя.
static func drop_purse(mod: PaxMod, place_key: String, at: Vector3, gold: int) -> void:
	mod.set_setting("lost_purse", {"place": place_key, "p": [at.x, at.y, at.z], "gold": gold} if gold > 0 else {})


static func purse(mod: PaxMod) -> Dictionary:
	var v: Variant = mod.get_setting("lost_purse", {})
	return v if v is Dictionary else {}


static func clear_purse(mod: PaxMod) -> void:
	mod.set_setting("lost_purse", {})
