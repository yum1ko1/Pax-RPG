---
mod: pax_rpg
file: src/location/wind.gd
lines: 87
weight: 1
tags: [мод/rpg, функция/location]
---

# wind

`src/location/wind.gd` · [[Код Pax RPG]] · `extends Node3D` · 87 строк · подключают: **1**

> Ветер как в аниме: время от времени у героя проносится порыв — несколько тонких белых изогнутых штрихов (shaders/wind_streak.gdshader) летят по ветру, вспыхивают и тают. В порыв листья с деревьев сносит сильнее (city.gd → leaves, gravity по ветру). Направление ветра медленно гуляет.

## Кто подключает
- [[location]]

## Функции
- `func setup(m: PaxMod, who: Node3D) -> void`
- `func _process(delta: float) -> void`
- `func _spawn_gust() -> void`
