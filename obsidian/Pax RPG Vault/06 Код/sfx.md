---
тип: код
mod: pax_rpg
file: src/location/sfx.gd
lines: 93
weight: 1
tags: [мод/rpg, функция/location]
---

# sfx

`src/location/sfx.gd` · [[Код Pax RPG]] · `extends Node` · 93 строк · подключают: **1**

> Звуки локации кроме боя: шаги героя и бряцание снаряжения (по пройденному пути), фоновый гул города (петля sounds/city_bed.ogg — синтез pax_rpg/dev/sfx/city_ambience.py) и редкие бытовые звуки вдали (кузня, котлы, монеты, двери). Шаги и снаряжение — Kenney RPG Audio / Impact Sounds (CC0, sounds/LICENSE_kenney.txt).

## Кто подключает
- [[location]]

## Функции
- `func setup(mod: PaxMod, in_city: bool) -> void`
- `func _rand(mod: PaxMod, pattern: String, n: int, pitch: float, volume: float) -> AudioStreamPlayer`
- `func walk(dist: float, running: bool, armed: bool, on_floor: bool) -> void` — Каждый кадр физики: сколько герой прошёл по земле. Шаг — каждые stride м; бряцание — на каждый второй шаг (с мечом и на бегу — на каждый).
- `func land() -> void` — Приземление после прыжка — двойной шаг.
- `func _process(delta: float) -> void`
