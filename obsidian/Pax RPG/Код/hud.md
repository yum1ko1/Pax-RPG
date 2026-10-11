---
mod: pax_rpg
file: src/location/hud.gd
lines: 432
weight: 1
tags: [мод/rpg, функция/location]
---

# hud

`src/location/hud.gd` · [[Код Pax RPG]] · `extends Control` · 432 строк · подключают: **1**

> HUD локации «Сакура и сталь» (концепт A): ночная лазурь и сакура, иероглифы вместо иконок. Слева вверху — герой (портрет, уровень, здоровье, концентрация), сверху — компас, справа — миникарта, задание и враг в бою; внизу — эликсир, боевые приёмы, кольцо добивания, опыт и мана. Всё рисуется здесь (_draw) по словарю st, который location.gd заполняет каждый кадр. Макет — 1920×1080, на другом экране масштаб по высоте.

## Кто подключает
- [[location]]

## Функции
- `func setup(m: PaxMod, enemy_portrait: Texture2D) -> void`
- `static func _sys(names: Array, weight: int) -> Font`
- `func refresh() -> void` — Новый кадр: location.gd положил st — перерисовать.
- `func _g(k: String, d: Variant = 0.0) -> Variant`
- `func _tr(k: String) -> String`
- `func _draw() -> void`
- `func _text(pos: Vector2, s: String, font: Font, fs: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,`
- `func _center(c: Vector2, s: String, font: Font, fs: int, color: Color, outline := 0) -> void` — Текст по центру точки (по ширине и примерно по высоте).
- `func _diamond(c: Vector2, r: float) -> PackedVector2Array`
- `func _outline(pts: PackedVector2Array, color: Color, width: float) -> void`
- `func _skew_bar(x: float, y: float, w: float, h: float, frac: float, color: Color) -> void` — Полоса-параллелограмм (наклон как у мазка кисти).
- `func _draw_player() -> void`
- `func _draw_compass() -> void`
- `func _draw_map_frame() -> void`
- `func _draw_mask() -> void`
- `func _draw_map() -> void` — Миникарта (внутри круга): верх — куда смотрит камера; платформы, ворота, враги, герой.
- `func _draw_quest() -> void`
- `func _draw_enemy() -> void`
- `func _draw_marks() -> void` — Метки поверх мира: прицел захвата и цифры урона (координаты — пиксели экрана, location.gd проецирует).
- `func _draw_toast() -> void`
- `func _draw_flask() -> void`
- `func _draw_skills() -> void`
- `func _draw_xp() -> void`
- `func _wrap(line: String, width: float, fs: int) -> PackedStringArray` — Разбить строку по словам (разделитель « · » — по пунктам), чтобы каждая часть влезала в width.
- `func _draw_hint() -> void`
