---
тип: код
mod: pax_rpg
file: src/location/city_title.gd
lines: 77
weight: 1
tags: [мод/rpg, функция/location]
---

# city_title

`src/location/city_title.gd` · [[Код Pax RPG]] · `extends Control` · 77 строк · подключают: **1**

> Заставка входа в город: чуть выше центра слева со звоном влетает катана, замирает посередине, на клинке проступает название места; через несколько секунд надпись тает, и катана со звоном улетает вправо.

## Подключает
- [[katana]]
- [[hud]]

## Кто подключает
- [[location]]

## Функции
- `func setup(mod: PaxMod, place: String) -> void`
- `func play(delay := 0.4) -> void`
- `func _ring() -> void`
- `func _process(_delta: float) -> void`
- `func _draw() -> void`
