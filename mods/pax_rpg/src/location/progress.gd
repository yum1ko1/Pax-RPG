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
var cfg: Dictionary = {}


func setup(m: PaxMod, c: Dictionary) -> void:
	mod = m
	cfg = c
	var saved: Variant = mod.get_setting("progress", {})
	if saved is Dictionary:
		level = maxi(1, int((saved as Dictionary).get("level", 1)))
		xp = float((saved as Dictionary).get("xp", 0.0))
		skill_points = int((saved as Dictionary).get("skill_points", 0))


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
	mod.set_setting("progress", {"level": level, "xp": xp, "skill_points": skill_points})


## Множители статов от уровня: здоровье +4 %, урон +3 %, концентрация +2 % за уровень (по умолчанию).
func hp_mult() -> float:
	return 1.0 + _f("hp_per_level", 0.04) * (level - 1)


func damage_mult() -> float:
	return 1.0 + _f("damage_per_level", 0.03) * (level - 1)


func posture_mult() -> float:
	return 1.0 + _f("posture_per_level", 0.02) * (level - 1)
