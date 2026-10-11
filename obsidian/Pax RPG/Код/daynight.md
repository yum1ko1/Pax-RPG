---
mod: pax_rpg
file: src/location/daynight.gd
lines: 65
weight: 1
tags: [мод/rpg, функция/location]
---

# daynight

`src/location/daynight.gd` · [[Код Pax RPG]] · `extends Node` · 65 строк · подключают: **1**

> Смена суток в локации: час идёт (config/location.json → day_minutes — длина суток в минутах, start_hour), солнце ходит по дуге (восход 6:00, закат 18:00), ночью тот же свет — луна, голубая и слабая; небо (shaders/sky.gdshader: day, dusk), окружение и туман следуют; ночью фонари, костры и кристаллы разгораются, окна светятся тёплым. Консоль F8: rpg_time <час>.

## Кто подключает
- [[location]]

## Функции
- `func setup(e: Environment, s: DirectionalLight3D, sm: ShaderMaterial, cfg: Dictionary) -> void`
- `func _process(delta: float) -> void`
- `func apply() -> void`
