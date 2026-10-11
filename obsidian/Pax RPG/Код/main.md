---
mod: pax_rpg
file: main.gd
lines: 86
weight: 0
tags: [мод/rpg, функция/основа]
---

# main

`main.gd` · [[Код Pax RPG]] · `extends PaxMod` · 86 строк · подключают: **0**

> Pax RPG — прототип RPG в Pax Universe. Сейчас только механика: планета Юрума вместо Земли (planet/), города на глобусе; щелчок по городу — экран загрузки (travel/) и локация-платформа (location/), где герой-овал ходит на WASD; ворота на локации возвращают на карту мира. main.gd только регистрирует части.

## Подключает
- [[planet]]
- [[location]]
- [[loading]]
- [[travel]]

## Функции
- `func _mod_loaded() -> void`
- `func _mod_unloaded() -> void`
- `func _world_ready(g: PaxGame) -> void`
- `func _arena_command(_args: PackedStringArray) -> String` — Консоль F8: rpg_arena.
- `func _city_command(args: PackedStringArray) -> String`
- `func _cam_command(args: PackedStringArray) -> String`
- `func _open_test_arena() -> void` — Кнопка «Тест» в главном меню: сразу тестовая арена (герой + гоблин), без карты мира.
