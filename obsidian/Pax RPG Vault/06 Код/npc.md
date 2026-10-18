---
тип: код
mod: pax_rpg
file: src/location/npc.gd
lines: 118
weight: 1
tags: [мод/rpg, функция/location]
---

# npc

`src/location/npc.gd` · [[Код Pax RPG]] · `extends CharacterBody3D` · 118 строк · подключают: **1**

> Мирный житель (гоблин): ходит по маршрутам улиц из планировки города («paths»: ломаные XZ), иногда останавливается поглазеть; на героя не нападает, обходить его не умеет — просто ждёт, если упёрся. Модель и клипы — как у гоблина-врага (models/goblin/), без боя.

## Кто подключает
- [[location]]

## Функции
- `func setup(m: PaxMod, path: PackedVector3Array, start_i: int, seed_v: int) -> void`
- `static func _find(n: Node) -> AnimationPlayer`
- `func _play(c: String) -> void`
- `func _physics_process(delta: float) -> void`
