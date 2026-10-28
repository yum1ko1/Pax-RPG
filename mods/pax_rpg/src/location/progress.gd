extends RefCounted
## Уровень героя (как в мобильных RPG): опыт копится, порог растёт с каждым уровнем; уровень понемногу поднимает
## статы (здоровье, урон, концентрация), каждый 10-й — очко умений. Опыт — это мана повергнутых врагов: она
## перетекает шариками в шкалу опыта (location.gd), add_xp зовётся по прилёту каждого шарика.
## Сохраняется в настройках мода (progress), переживает выход из города и перезапуск игры.
## Числа — config/hero.json → "progress": xp_base, xp_growth, hp_per_level, damage_per_level, posture_per_level,
## skill_every.

var mod: PaxMod
var level := 1
var xp := 0.0                      # опыт внутри текущего уровня
var skill_points := 0
var gold := 0                      # золотые монеты (враги, задания; HUD — слева вверху)
var stats_added: Dictionary = {}   # очки характеристик, вложенные игроком: ключ характеристики → сколько
var flask_bonus := 0               # заряды эликсира сверх героя (тыква-фляга из лавки — shop.gd)
var cfg: Dictionary = {}


func setup(m: PaxMod, c: Dictionary) -> void:
	mod = m
	cfg = c
	var saved: Variant = mod.get_setting("progress", {})
	if saved is Dictionary:
		level = maxi(1, int((saved as Dictionary).get("level", 1)))
		xp = float((saved as Dictionary).get("xp", 0.0))
		skill_points = int((saved as Dictionary).get("skill_points", 0))
		gold = int((saved as Dictionary).get("gold", 0))
		flask_bonus = int((saved as Dictionary).get("flask_bonus", 0))
		var sa: Variant = (saved as Dictionary).get("stats_added", {})
		stats_added = sa if sa is Dictionary else {}


func _f(k: String, d: float) -> float:
	return float(cfg.get(k, d))


## Опыт до следующего уровня: base · growth^(уровень−1), округлённо (100, 115, 132, …).
func need(lvl := -1) -> float:
	var l := level if lvl < 0 else lvl
	return roundf(_f("xp_base", 100.0) * pow(_f("xp_growth", 1.15), l - 1))


func frac() -> float:
	return clampf(xp / need(), 0.0, 1.0)


## Добавить опыт. Возвращает, сколько уровней набрано (обычно 0 или 1).
func add_xp(v: float) -> int:
	xp += v
	var ups := 0
	while xp >= need():
		xp -= need()
		level += 1
		ups += 1
		if level % int(_f("skill_every", 10.0)) == 0:
			skill_points += 1
	_save()
	return ups


func _save() -> void:
	mod.set_setting("progress", {"level": level, "xp": xp, "skill_points": skill_points, "stats_added": stats_added,
		"gold": gold, "flask_bonus": flask_bonus})


func add_gold(v: int) -> void:
	gold = maxi(0, gold + v)
	_save()


func add_flask() -> void:
	flask_bonus += 1
	_save()


# ---------- очки характеристик и масштабирование урона ----------

## Свободные очки характеристик: одно за каждый stat_every-й уровень (10, 20, …) минус уже вложенные.
func stat_points() -> int:
	var spent := 0
	for k: Variant in stats_added:
		spent += int(stats_added[k])
	return maxi(0, level / int(_f("stat_every", 10.0)) - spent)


func add_stat(key: String) -> bool:
	if stat_points() <= 0:
		return false
	stats_added[key] = int(stats_added.get(key, 0)) + 1
	_save()
	return true


## Итоговые характеристики: базовые героя (config/hero.json → character.attributes) + вложенные очки.
func attributes(base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k: Variant in stats_added:
		out[k] = int(out.get(k, 0)) + int(stats_added[k])
	return out


## Буква масштабирования → коэффициент (как в Dark Souls 3: S лучше всех, E почти ничего).
const GRADES := {"S": 1.4, "A": 1.1, "B": 0.85, "C": 0.6, "D": 0.35, "E": 0.15}


## Насыщение характеристики 0..1 (кривая «мягких порогов» DS3): до 10 ничего не даёт, 10→20 быстро растёт,
## 20→40 ровно, после 40 и особенно 60 отдача падает.
static func saturation(v: float) -> float:
	var pts := [[10.0, 0.0], [20.0, 0.35], [40.0, 0.75], [60.0, 0.9], [99.0, 1.0]]
	if v <= 10.0:
		return 0.0
	for i: int in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if v <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (v - float(a[0])) / (float(b[0]) - float(a[0])))
	return 1.0


## Множитель урона оружия: 1 + Σ коэффициент буквы · насыщение характеристики (scaling — {"strength": "A"}).
static func scaling_mult(scaling: Dictionary, attrs: Dictionary) -> float:
	var m := 1.0
	for k: Variant in scaling:
		m += float(GRADES.get(str(scaling[k]).to_upper(), 0.0)) * saturation(float(attrs.get(k, 0)))
	return m


## Множители статов от уровня: здоровье +4 %, урон +3 %, концентрация +2 % за уровень (по умолчанию).
func hp_mult() -> float:
	return 1.0 + _f("hp_per_level", 0.04) * (level - 1)


func damage_mult() -> float:
	return 1.0 + _f("damage_per_level", 0.03) * (level - 1)


func posture_mult() -> float:
	return 1.0 + _f("posture_per_level", 0.02) * (level - 1)
