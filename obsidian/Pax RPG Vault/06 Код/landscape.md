---
тип: код
mod: pax_rpg
file: src/location/landscape.gd
lines: 159
weight: 1
tags: [мод/rpg, функция/location]
---

# landscape

`src/location/landscape.gd` · [[Код Pax RPG]] · `extends RefCounted` · 159 строк · подключают: **1**

> Мир за частоколом: степь холмами до горизонта, три гряды гор со снежными шапками (дымка тумана делает их синими и далёкими), кочевые юрты на холмах. Без коллизий — герой за стену не выходит. Высоты — шум (FastNoiseLite), город — в плоской «чаше» (land: [центр X, центр Z, полуширина, полуглубина]). Высота степи: в городе — ниже земли города, за стеной поднимается холмами.

## Кто подключает
- [[city]]

## Функции
- `func build(m: PaxMod, parent: Node3D, area: Rect2) -> void`
- `func height(x: float, z: float) -> float` — Высота степи: в городе — ниже земли города, за стеной поднимается холмами.
- `func _terrain() -> void`
- `func _mountains() -> void` — Горы: три кольца пиков (ближние ниже и теплее, дальние выше, голубее — дымка), снег на вершинах.
- `func _peak(st: SurfaceTool, base: Vector3, w: float, h: float, rng: RandomNumberGenerator) -> void`
- `func _camps() -> void` — Кочевья на холмах: юрты по 2–4, где склон пологий.
- `func yurt_y(x: float, z: float) -> float`
