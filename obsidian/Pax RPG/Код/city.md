---
mod: pax_rpg
file: src/location/city.gd
lines: 307
weight: 1
tags: [мод/rpg, функция/location]
---

# city

`src/location/city.gd` · [[Код Pax RPG]] · `extends RefCounted` · 307 строк · подключают: **1**

> Сборка города из планировки (config/<город>.json, генератор — pax_rpg/dev/gharn/gharn_layout.py): земля, модели (glb мода) и простые блоки (терраса, пандус, холм). Одинаковые модели ставятся пачкой — по MultiMeshInstance3D на каждую сетку модели (сотни бочек и тайлов дороги — пара вызовов отрисовки). Коллизия «c»: коробка по габаритам модели (здания, стены, юрты) — мелочь и деревья не мешают ходить.

## Кто подключает
- [[location]]

## Функции
- `func build(m: PaxMod, parent: Node, data: Dictionary) -> void`
- `func _ground(size: Vector2, center: Vector2, gm: Dictionary) -> void` — Земля: плоскость с шейдером (глина, кладка дорог и тропы по маске — shaders/ground.gdshader) и коробка-коллизия.
- `func _tex(path: String, normal := false) -> Texture2D` — Картинка мода с мипмапами (без них плитка вдали рябит при движении камеры).
- `func _fix_textures() -> void`
- `func _prep_image(i: int) -> void`
- `func _glass(m: BaseMaterial3D) -> void` — Стекло окон: тёмное, почти зеркальное (небо, солнце и фонари в нём — через отражения окружения и SSR), изнутри — слабый тёплый свет очага.
- `func _lights(path: String, list: Array) -> void` — Тёплый свет у фонарей (без теней — их десятки).
- `func _place(path: String, list: Array) -> void` — Модель: её сетки (со своими сдвигами внутри модели) → MultiMesh на все места; коллизии — коробки.
- `func _boxes(t: Transform3D, list: Array) -> void` — Коробки коллизии [sx, sy, sz, ox, oy, oz] в осях модели (с её масштабом).
- `func _collect(n: Node, xf: Transform3D, out: Array) -> void`
- `func _block(size: Vector3, pos: Vector3, mat: String, ry: float, rx: float, collide: bool) -> void`
