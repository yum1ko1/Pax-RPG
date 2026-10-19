extends RefCounted
## Кто живёт в городе — своё в каждом прохождении: имя гоблина из слогов (начало, связка, конец; иногда прозвище),
## ремесло из списка своего рода занятий, забота дня. Слоги и списки — в data/lang (pax_rpg_gen_*), через «|».
## Зерно прохождения — настройка мода run_seed (новая игра RPG — новое зерно, main.gd); житель в городе получает
## своё зерно из номера места и зерна прохождения — тот же город в той же партии встречает тех же жителей.

const ROLES := ["merchant", "guard", "herder", "shaman", "smith", "beggar", "cook", "porter", "craftsman", "hunter",
	"entertainer"]
const UNIQUE := ["arena_master", "seer"]          # единственные в городе: имя и ремесло — свои (data/lang)

static var _used := {}                            # имена, уже данные в этом городе (без двойников)
static var _lists := {}                           # ключ → PackedStringArray (разбор строки один раз)


static func run_seed(mod: PaxMod) -> int:
	var s := int(mod.get_setting("run_seed", 0))
	if s == 0:
		s = new_run(mod)
	return s


## Новое прохождение: новое зерно (жители, имена, ремёсла — другие), отношения жителей прежней партии забыты.
static func new_run(mod: PaxMod) -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := rng.randi_range(1, 2147483646)
	mod.set_setting("run_seed", s)
	mod.set_setting("npc_rel", {})
	return s


## Город строится заново — имена снова свободны.
static func reset() -> void:
	_used.clear()


static func _list(mod: PaxMod, key: String) -> PackedStringArray:
	if not _lists.has(key):
		_lists[key] = mod.tr_key(key).split("|", true)
	return _lists[key]


static func _pick(mod: PaxMod, key: String, rng: RandomNumberGenerator) -> String:
	var l := _list(mod, key)
	return l[rng.randi() % l.size()] if l.size() > 0 else ""


static func goblin_name(mod: PaxMod, rng: RandomNumberGenerator) -> String:
	var nm := ""
	for attempt: int in 12:
		nm = _pick(mod, "pax_rpg_gen_name_start", rng) + _pick(mod, "pax_rpg_gen_name_mid", rng) \
			+ _pick(mod, "pax_rpg_gen_name_end", rng)
		if rng.randf() < 0.35:
			nm += " " + _pick(mod, "pax_rpg_gen_nick", rng)
		if not _used.has(nm):
			break
	_used[nm] = true
	return nm


static func trade(mod: PaxMod, role: String, rng: RandomNumberGenerator) -> String:
	if role in UNIQUE:
		return mod.tr_key("pax_rpg_npc_role_" + role)
	var t := _pick(mod, "pax_rpg_gen_trade_" + role, rng)
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else mod.tr_key("pax_rpg_npc_role_" + role)


static func worry(mod: PaxMod, role: String, rng: RandomNumberGenerator) -> String:
	return _pick(mod, "pax_rpg_gen_worry_" + role, rng)
