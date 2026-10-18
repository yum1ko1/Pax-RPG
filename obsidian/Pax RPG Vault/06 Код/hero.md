---
тип: код
mod: pax_rpg
file: src/location/hero.gd
lines: 1454
weight: 1
tags: [мод/rpg, функция/location]
---

# hero

`src/location/hero.gd` · [[Код Pax RPG]] · `extends RefCounted` · 1454 строк · подключают: **1**

> Герой локации: модель (config/hero.json → models/*.glb) и её состояние — меч на спине, в руке или волочится по земле в беге, доставание и убирание, комбо из трёх тяжёлых ударов, прыжок, увороты; надетые вещи (плащ-ткань). Удары ведёт root motion (смещение таза вынуто при сборке — pax_rpg/dev/blender/knight/*.py → *_anim.json): инерция меча тянет персонажа. Удар без продолжения кончается сразу после взмаха и плавно уходит в стойку. location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.

## Кто подключает
- [[location]]

## Функции
- `func load_model(mod: PaxMod, c: Dictionary) -> Node3D`
- `static func _tip_of(n: Node3D) -> Vector3` — Остриё: дальняя от хвата точка габаритов сетки меча (в осях узла меча).
- `func _player(files: Variant, pitch: float, volume: float) -> AudioStreamPlayer` — Плеер со случайным из вариантов звука (без повторов подряд) и разбросом высоты.
- `func look_at_point(p: Variant, delta: float) -> void` — Голова смотрит на точку p (null — отпустить, голова плавно возвращается к анимации). Поворот головы — в пределах head_limit градусов (дальше доворачивается всё тело — это решает location.gd).
- `func start(owner_body: PhysicsBody3D = null) -> void`
- `static func _find_anim(n: Node) -> AnimationPlayer`
- `static func _find_skeleton(n: Node) -> Skeleton3D`
- `func _f(k: String, d: float) -> float`
- `func _per(k: String, clip: String, d: float) -> float` — Значение по клипу из словаря настроек ({"Attack1": 0.4, ...}) или общее.
- `func has(n: String) -> bool`
- `func locks_move() -> bool`
- `func walk_only() -> bool` — Достаёт или убирает меч на ходу — бежать нельзя, только шаг.
- `func _bone_world(idx: int, rest := false) -> Transform3D`
- `func worn(slot: String) -> String`
- `func equip(id: String) -> bool`
- `func unequip(slot: String) -> void`
- `func toggle_slot(slot: String) -> void` — «C»: снять вещь со слота или надеть ту, что в нём была (или первую из надетых при старте).
- `func _load_mesh(path: String) -> Array` — Сетка предмета из glb и её положение в осях сцены glb.
- `func _iv(it: Dictionary, k: String, d: float) -> float`
- `func _wear_cloth(it: Dictionary, w: Dictionary) -> bool`
- `func _wear_cape(it: Dictionary, w: Dictionary) -> bool`
- `func _tex_mip(path: String, normal: bool) -> Texture2D`
- `func _make_collar(c: Dictionary, w: Dictionary, nk: Vector3, cl: Array, mat: Material) -> void` — Воротник: свёрнутая валиком ткань плаща вокруг шеи сзади и по плечам, спереди — две золотые фибулы и цепочка между ними. Едет с костью грудной клетки (top_bone), как верх плаща.
- `func _cape_targets(c: Dictionary, idx: PackedInt32Array) -> PackedVector3Array` — Где точки плаща сейчас «на теле»: верх посередине едет с грудью, углы верха — с плечами, низ — с тазом.
- `func _cape_tick(w: Dictionary, delta: float) -> void`
- `static func _cape_link(x: PackedVector3Array, a: int, b: int, rest_len: float, a_pinned: bool) -> void` — Связь двух соседних точек решётки: длина как в покое (верхний ряд не двигается).
- `func _push_out(p: Vector3) -> Vector3`
- `func _cape_draw(c: Dictionary, tg: PackedVector3Array) -> void` — Сетка плаща: смещение каждой её точки от «места на теле» — билинейно по грубой решётке.
- `static func _cr_at(g: PackedVector3Array, i: int, nx: int, nz: int, t: float, along_j: bool) -> Vector3` — Catmull-Rom по сетке: along_j — вдоль колонки i (параметр t в рядах), иначе вдоль ряда (строка = i).
- `func _wear_rigid(it: Dictionary, w: Dictionary) -> bool`
- `func _make_body_colliders() -> void` — Капсулы тела (таз, спина, бёдра, голени) — о них бьётся ткань; персонажа и мир они не трогают.
- `func _pin_cloth(w: Dictionary) -> bool` — Верх ткани пришивается по всей ширине: точки делятся на полосы по X, в каждой пришиваются те, что у её верхнего края, — каждая к ближней из костей pin_bones. Позиции берутся у самих точек мягкого тела (не по номерам вершин — сервер физики мог сварить их по-своему). false — точки ещё не готовы.
- `func _move_colliders() -> void`
- `func _items_tick(delta: float) -> void`
- `func cape_wind(_velocity: Vector3) -> void` — Ткань сама тянется за телом — ветер не нужен (оставлено для location.gd).
- `func _make_trail() -> void`
- `func _trail_tick(delta: float) -> void` — Полоса между четвертью клинка и остриём за последние trail_life с — только в ударах и только пока меч летит быстро: видно дугу, которую накрывает удар.
- `func _ground_burst() -> void`
- `func toggle_sword(on_floor: bool, moving := false) -> void`
- `func _cancel_hurt() -> void` — Реакция на удар (Hurt) — только картинка: любое действие или шаг её прерывают, управление не отнимается.
- `func attack(on_floor: bool) -> void`
- `func dodge(on_floor: bool) -> bool` — Уворот (Alt): кувырок туда, куда смотрит герой (location.gd разворачивает его по направлению ввода). С мечом — свой клип, тяжелее и дальше.
- `func invulnerable() -> bool` — Во время кувырка удары проходят мимо (i-frames).
- `func hurt() -> void` — Получил удар: клип Hurt (если есть в модели) — короткая реакция, не сбивает уворот и удар финала.
- `func jump(on_floor: bool) -> bool` — Прыжок: анимация с момента отрыва (без долгого приседа), отрыв — сразу (tick вернёт jump).
- `func _play_once(n: String, skip := 0.0) -> void`
- `func _on_finished(n: StringName) -> void`
- `func _end_action() -> void`
- `func _pos() -> float`
- `func _frac() -> float`
- `func tick(delta: float, moving: bool, speed: float, running: bool, on_floor: bool) -> Dictionary` — Возвращает {"root": Vector3 — смещение за кадр в осях модели (модель смотрит на +Z)}.
- `func _loop(moving: bool, speed: float, running: bool) -> void`
- `func _update_sector() -> void` — Направление шага по move_dir: ближайшее из вперёд / вправо / назад / влево, но меняется, только когда новое заметно ближе (на диагонали клип не мигает).
- `func set_block(on: bool) -> void` — ПКМ: нажал — блок (и первые parry_window с — парирование, как в Sekiro), отпустил — снял.
- `func parry_window() -> bool`
- `func deflect() -> void` — Парировал: меч вздрагивает в блоке (как от удара о сталь). Окно парирования не продлевается — следующий удар надо ловить новым нажатием, как в Sekiro.
- `func deathblow() -> bool` — Добивание (враг без равновесия): свой клип, двигаться нельзя. true — началось.
- `func _hit(out: Dictionary) -> void` — Миг удара: середина взмаха (swing_peaks), у финального — касание земли (impact). tick вернёт {"hit": {"range": м, "arc": косинус полуугла перед героем (-1 — круг)}} — location.gd бьёт по врагам.
- `func hit_time_left() -> float` — Сколько секунд до мига удара (у финального — до касания земли); -1 — удар уже прошёл или герой не бьёт.
- `func pull_on() -> bool` — С какой секунды клипа удар тянет к врагу (финальный — с отрыва от земли, не скользит по полу).
- `func attack_reach() -> float` — До какой дистанции (м, центр — центр) удар подводит героя к врагу.
- `func _sounds() -> void`
- `func _root_at(t: float) -> Vector2`
- `func _root_step() -> Vector3` — Смещение тела за кадр из root motion клипа.
- `func _show_sword(delta: float) -> void` — Меч там, где он сейчас: на спине или в руке. В беге он плавно перекладывается в «волочится» (цель — узел Sword_Drag) и в любом клипе не уходит в землю: если остриё ниже пола — меч поворачивается на хвате вверх.
- `func _keep_above_floor() -> void`
