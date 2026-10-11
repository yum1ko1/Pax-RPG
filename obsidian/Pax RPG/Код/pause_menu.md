---
mod: pax_rpg
file: src/location/pause_menu.gd
lines: 103
weight: 1
tags: [мод/rpg, функция/location]
---

# pause_menu

`src/location/pause_menu.gd` · [[Код Pax RPG]] · `extends Control` · 103 строк · подключают: **1**

> Меню паузы локации (Esc) в стиле HUD «Сакура и сталь»: затемнение, свиток по центру, кнопки. Мир локации на паузе, пока меню открыто (location.gd отключает обработку SubViewport).

## Подключает
- [[hud]]

## Кто подключает
- [[location]]

## Функции
- `func setup(mod: PaxMod, leave_text: String) -> void`
- `func set_leave_text(t: String) -> void`
- `static func _line() -> StyleBoxLine`
- `func _button(text: String, font: Font) -> Button`
