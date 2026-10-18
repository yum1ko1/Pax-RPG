---
тип: код
mod: pax_rpg
file: src/travel/travel.gd
lines: 67
weight: 1
tags: [мод/rpg, функция/travel]
---

# travel

`src/travel/travel.gd` · [[Код Pax RPG]] · `extends Node` · 67 строк · подключают: **1**

> Переходы: карта мира → город и обратно, всегда через экран загрузки (loading.gd). Пока игрок в локации, значки городов на глобусе выключены, время мира стоит («pause_world» в config/location.json). Рассказчик — готовые строки из data/lang, позже их заменит ИИ.

## Подключает
- [[planet]]
- [[location]]
- [[loading]]

## Кто подключает
- [[main]]

## Функции
- `func setup(m: PaxMod, p: Planet, l: Location, ld: Loading) -> void`
- `func start(g: PaxGame) -> void`
- `func _line(prefix: String, count: int, city_name: String) -> String`
- `func enter(city: Dictionary) -> void`
- `func leave() -> void`
- `func _back_on_map() -> void`
