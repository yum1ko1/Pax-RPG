---
mod: pax_rpg
file: src/location/progress.gd
lines: 69
weight: 1
tags: [мод/rpg, функция/location]
---

# progress

`src/location/progress.gd` · [[Код Pax RPG]] · `extends RefCounted` · 69 строк · подключают: **1**

> Уровень героя (как в мобильных RPG): опыт копится, порог растёт с каждым уровнем; уровень понемногу поднимает статы (здоровье, урон, концентрация), каждый 10-й — очко умений. Опыт — это мана повергнутых врагов: она перетекает шариками в шкалу опыта (location.gd), add_xp зовётся по прилёту каждого шарика. Сохраняется в настройках мода (progress), переживает выход из города и перезапуск игры. Числа — config/hero.json → "progress": xp_base, xp_growth, hp_per_level, damage_per_level, posture_per_level, skill_every. Опыт до следующего уровня: base · growth^(уровень−1), округлённо (100, 115, 132, …). Добавить опыт. Возвращает, сколько уровней набрано (обычно 0 или 1).

## Кто подключает
- [[location]]

## Функции
- `func setup(m: PaxMod, c: Dictionary) -> void`
- `func _f(k: String, d: float) -> float`
- `func need(lvl := -1) -> float` — Опыт до следующего уровня: base · growth^(уровень−1), округлённо (100, 115, 132, …).
- `func frac() -> float`
- `func add_xp(v: float) -> int` — Добавить опыт. Возвращает, сколько уровней набрано (обычно 0 или 1).
- `func _save() -> void`
- `func hp_mult() -> float` — Множители статов от уровня: здоровье +4 %, урон +3 %, концентрация +2 % за уровень (по умолчанию).
- `func damage_mult() -> float`
- `func posture_mult() -> float`
