---
mod: pax_rpg
file: src/location/location.gd
lines: 1197
weight: 2
tags: [мод/rpg, функция/location]
---

# location

`src/location/location.gd` · [[Код Pax RPG]] · `extends CanvasLayer` · 1197 строк · подключают: **2**

> Локация города — прототип механики. Свой 3D-мир в SubViewport поверх игры (own_world_3d: своя физика и свет, мир игры его не видит): платформа, несколько блоков, ворота выхода и герой (config/hero.json: модель, скорости, комбо; логика анимаций — hero.gd; нет модели — овал). WASD — ходьба относительно камеры, Shift — бег, Пробел — прыжок, F — достать / убрать меч, ЛКМ — удар (три подряд — комбо), правая кнопка мыши + движение — поворот камеры, E у ворот — назад на карту мира (сигнал exit_requested, дальше travel.gd).

## Подключает
- [[hero]]
- [[goblin]]
- [[hud]]
- [[city]]
- [[npc]]
- [[pause_menu]]
- [[sfx]]
- [[city_title]]
- [[wind]]
- [[progress]]

## Кто подключает
- [[main]]
- [[travel]]

## Функции
- `func setup(m: PaxMod) -> void`
- `func _f(key: String, fallback: float) -> float`
- `func build_test() -> void` — Кнопка «Тест» главного меню: арена — та же площадка, герой и гоблин; ворота возвращают в меню.
- `func _spawn_goblins(n: int) -> void` — Гоблины локации (config/location.json → goblins): полукругом перед героем, между ним и воротами.
- `func _hp_max() -> float`
- `func _pos_max() -> float`
- `func build(city: Dictionary) -> void`
- `func clear() -> void`
- `func _make_sky() -> void`
- `func _solid(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D`
- `func _spawn_npcs(layout: Dictionary) -> void` — Мирные жители по маршрутам планировки: «npcs» штук, по кругу маршрутов, в разных точках.
- `func _city_layout(id: String) -> Dictionary` — Планировка города (config/<id>.json); нет файла — {} (локация-прототип).
- `func _make_ground() -> void`
- `func _make_gate() -> void`
- `func _make_portal() -> void` — Выход из города: мерцающая завеса, тёплый свет, искры маны и надпись над ним (вход — E, см. подсказку HUD).
- `func _make_player() -> void`
- `func _hf(key: String, fallback: float) -> float`
- `func _set_paused(on: bool) -> void` — Пауза (Esc): мир локации замирает, мышь свободна, поверх — меню.
- `func paused() -> bool`
- `func _typing() -> bool`
- `func _physics_process(delta: float) -> void`
- `func cine(n: int) -> String`
- `func _follow_camera(delta := 0.0) -> void`
- `func _strike(hit: Dictionary) -> void` — Удар героя по врагам рядом: в пределах range и перед ним (arc — косинус полуугла; -1 — по кругу, удар о землю).
- `func _aim_yaw() -> float` — Куда целиться: в захваченного врага, иначе — туда, куда смотрит камера.
- `func _magnet_pull(vel: Vector3, mag: Goblin, delta: float) -> Vector3` — Подтяг удара к врагу: до мига удара герой доходит (у финального — долетает) до дистанции reach, чтобы клинок попал по врагу, а не по воздуху; ближе reach шаг клипа не несёт — не влезает во врага.
- `func _attack_target() -> Goblin` — Цель удара: захваченный враг, иначе ближайший живой в magnet_range перед камерой (в пределах magnet_angle), а вплотную (magnet_close) — с любой стороны.
- `func _yaw_to(n: Node3D) -> float`
- `func _face_now(yaw: float) -> void`
- `func _hero_attacking() -> bool`
- `func _hero_blocking() -> bool`
- `func _toggle_lock() -> void` — Q: захватить ближнего врага перед камерой (до 16 м) / отпустить.
- `func _set_lock(t: Node3D) -> void`
- `func _try_deathblow() -> bool` — ЛКМ рядом с врагом без равновесия (красная метка) — добивание вместо удара.
- `func _on_hero_hit(damage: float, attacker: Node3D = null) -> void` — Удар гоблина по герою: кувырок — мимо; парирование в первые доли секунды блока — отбит, у врага сбита концентрация; блок — урона нет, но копится своя концентрация (переполнилась — стойка сломана); иначе — урон.
- `func _regen_posture(delta: float) -> void`
- `func _sparks(at: Vector3, color: Color, amount: int, speed: float) -> void` — Искры: блок и парирование.
- `func _hud_enemy() -> Goblin`
- `func _update_hud() -> void`
- `func _drink() -> void` — Эликсир (R): лечит, зарядов мало — пополняются, когда герой пал и вернулся на старт.
- `func _process(delta: float) -> void`
- `func _tick_orbs(delta: float) -> void` — Состояние HUD на кадр: герой, компас, миникарта, враг, цифры урона, мана и опыт за повергнутых. Шарики маны: по кривой от павшего врага к концу полоски опыта; долетел — +опыт (полоска растёт на глазах).
- `func _orb_points() -> Array`
- `static func _bez(p0: Vector2, c: Vector2, p1: Vector2, k: float) -> Vector2`
- `func _hud_tick(delta: float) -> void`
- `func _input(event: InputEvent) -> void`
