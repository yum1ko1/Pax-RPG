---
mod: pax_rpg
file: src/location/help_panel.gd
lines: 124
weight: 1
tags: [мод/rpg, функция/location]
---

# help_panel

`src/location/help_panel.gd` · [[Код Pax RPG]] · `extends Control` · 124 строк · подключают: **1**

> Подсказка по управлению: слева — кнопка «操 Управление · H» (кликается, когда курсор свободен: Esc), по ней или по H — окно со списком клавиш (из строки pax_rpg_controls: пункты через « · » и строки). Окно открыто — курсор свободен; закрыли — снова у камеры.

## Подключает
- [[hud]]

## Кто подключает
- [[location]]

## Функции
- `func setup(mod: PaxMod) -> void`
- `func _layout() -> void`
- `func over(p: Vector2) -> bool`
- `func is_open() -> bool`
- `func set_open(on: bool) -> void`
