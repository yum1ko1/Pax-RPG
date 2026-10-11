---
mod: pax_rpg
file: src/location/goblin.gd
lines: 568
weight: 1
tags: [мод/rpg, функция/location]
---

# goblin

`src/location/goblin.gd` · [[Код Pax RPG]] · `extends CharacterBody3D` · 568 строк · подключают: **1**

> Гоблин — враг-дуэлянт, бой как в Sekiro. Заметив героя, подходит на дистанцию поединка и кружит вокруг него лицом к нему, выжидая окно; потом короткий выпад: вспышка-предупреждение и рубящий удар. После удара — миг уязвимости и отход. Концентрация (posture): копится от парирований и ударов героя, переполнилась (или кончилось здоровье) — гоблин теряет равновесие, его можно добить (deathblow). Гибель — тело рассыпается маной. Атакует одновременно только один гоблин (жетон атаки). Модель и клипы — models/goblin/ (Meshy).

## Кто подключает
- [[location]]

## Функции
- `func setup(m: PaxMod, target: Node3D, on_hit: Callable, at: Vector3, hero_attacking := Callable(),`
- `func _add_clips() -> void` — Клипы Meshy — отдельными glb. Берём их анимацию и кладём в плеер гоблина под своим именем; нет файла — запасной.
- `static func _find_anim(n: Node) -> AnimationPlayer`
- `func is_alive() -> bool`
- `func can_deathblow() -> bool`
- `func _update_bars() -> void` — Полосы здоровья и концентрации — в HUD справа (location.gd читает hp / posture), над головой ничего.
- `func in_combat() -> bool` — В бою с героем (для HUD): заметил его и не мёртв.
- `func take_damage(amount: float, from: Vector3, knock := false) -> void` — Удар героя: кровь, отлёт, атака сорвана; растёт концентрация. Без равновесия — не принимает обычных ударов.
- `func deflected(from: Vector3) -> void` — Героя парировали удар: сильно сбивает концентрацию, гоблина отбрасывает в сторону.
- `func blocked() -> void` — Удар заблокирован: немного концентрации.
- `func deathblow() -> void` — Добивание: гибель.
- `func _die() -> void`
- `func _respawn() -> void`
- `func _burst(at: Vector3, dir: Vector3, color: Color, amount: int, speed: float, gravity: float, life: float,` — Искры / капли: amount частиц из at в сторону dir; gravity < 0 — летят вверх; glow — светятся (мана).
- `func _telegraph() -> void` — Предупреждение перед выпадом: вспышка над оружием (как красный иероглиф опасности в Sekiro — здесь мана).
- `func _take_token() -> bool`
- `func _release_token() -> void`
- `func _set_state(s: String) -> void`
- `func _set_state_keep(s: String) -> void` — Сменить состояние, не трогая клип (лежит — поза падения остаётся).
- `func _clip(name_: String) -> String`
- `func _play(clip: String, restart := false, blend := 0.2) -> void`
- `func _physics_process(delta: float) -> void`
- `func _f_windup() -> float` — Замах — короткая пауза с предупреждением (у слабых врагов короче).
- `func _damp(delta: float) -> void`
- `func _clip_len(clip: String) -> float`
- `func _face(dir: Vector3, delta: float) -> void` — Модель смотрит вперёд по +Z (у гоблина Meshy ставит вперёд +Z).
