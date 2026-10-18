---
тип: код
mod: pax_rpg
file: src/location/city.gd
lines: 864
weight: 1
tags: [мод/rpg, функция/location]
---

# city

`src/location/city.gd` · [[Код Pax RPG]] · `extends RefCounted` · 864 строк · подключают: **1**

> Сборка города из планировки (config/<город>.json, генератор — pax_rpg/dev/gharn/gharn_layout.py): земля, модели (glb мода) и простые блоки (терраса, пандус, холм). Одинаковые модели ставятся пачкой — по MultiMeshInstance3D на каждую сетку модели (сотни бочек и тайлов дороги — пара вызовов отрисовки). Коллизия «c»: коробка по габаритам модели (здания, стены, юрты) — мелочь и деревья не мешают ходить.

## Подключает
- [[landscape]]

## Кто подключает
- [[location]]

## Функции
- `func build(m: PaxMod, parent: Node, data: Dictionary) -> void`
- `func _ground(size: Vector2, center: Vector2, gm: Dictionary) -> void` — Земля: плоскость с шейдером (глина, кладка дорог и тропы по маске — shaders/ground.gdshader) и коробка-коллизия.
- `func _tex(path: String, normal := false) -> Texture2D` — Картинка мода с мипмапами (без них плитка вдали рябит при движении камеры).
- `func _fix_textures() -> void`
- `func _smoke_for(path: String, list: Array) -> void`
- `func _fountain_water(t: Transform3D) -> void` — Живая вода фонтана: рябь в чаше (shaders/water.gdshader), струя из пасти дракона веером вниз, брызги и пар над водой. Размеры — по модели (чаша r ≈ 2.15, вода на 1.45, верх дракона 4.0 — в единицах модели).
- `func _sign(sg: Array, pos: Vector3, ry: float) -> void`
- `func _laundry(l: Array, seed_v: int) -> void` — Бельё и шкуры между столбами у юрт: верёвка, полотнища колышутся (shaders/flag.gdshader, сплошной цвет). laundry: [x1, z1, x2, z2].
- `func _lantern_line(l: Array, seed_v: int) -> void`
- `func _merchant(pos: Vector3, ry: float, seed_v: int) -> void` — Торговец за прилавком: гоблин с анимацией покоя (модель и клип — как у мирных жителей), смотрит на покупателей.
- `func _leaves(list: Array) -> void` — Листопад: с кроны каждого дерева медленно падают алые листья, кружатся, ветер сносит их (wind.gd: гуще в порыв).
- `func _animal(path: String, pos: Vector3, ry: float, sc: float, clips: Array, col: Array) -> void` — Животное (буйвол): своя копия модели, клипы anim по очереди со случайной паузой — пасётся, оглядывается.
- `static func _find_player(n: Node) -> AnimationPlayer`
- `func _flags(list: Array) -> void` — Знамёна Гхарна: древко с перекладиной и полотнище (textures/gharn_flag.png — герб: огненный зверь), полотнище колышется (shaders/flag.gdshader). Каждое — свой узел: фаза ветра от места, флаги не машут в такт.
- `func _glass(m: BaseMaterial3D) -> void` — Стекло окон: тёмное, почти зеркальное (небо, солнце и фонари в нём — через отражения окружения и SSR), изнутри — слабый тёплый свет очага.
- `func _lights(path: String, list: Array) -> void` — Тёплый свет у фонарей (без теней — их десятки).
- `func _place(path: String, list: Array) -> void` — Модель: её сетки (со своими сдвигами внутри модели) → MultiMesh на все места; коллизии — коробки.
- `func _boxes(t: Transform3D, list: Array) -> void` — Коробки коллизии [sx, sy, sz, ox, oy, oz] в осях модели (с её масштабом).
- `func _collect(n: Node, xf: Transform3D, out: Array) -> void`
- `func _block(size: Vector3, pos: Vector3, mat: String, ry: float, rx: float, collide: bool) -> void`
