---
тип: код
mod: pax_rpg
file: src/planet/planet.gd
lines: 434
weight: 2
tags: [мод/rpg, функция/planet]
---

# planet

`src/planet/planet.gd` · [[Код Pax RPG]] · `extends Node` · 434 строк · подключают: **2**

> Юрума вместо Земли и города на ней. Свой шейдер ставится на материал домашней планеты игры (её узел, сетка и провинции остаются игровыми — меняется только то, как она нарисована); облачная оболочка Земли прячется — облака маны уже нарисованы на карте Юрумы. Города — экранные подписи того же вида, что подписи игры на глобусе (шрифт, размер, обводка берутся у её подписи), над точками-якорями — детьми узла планеты: крутятся вместе с ней и прячутся за ней. Щелчок по подписи — сигнал city_chosen (дальше travel.gd).

## Кто подключает
- [[main]]
- [[travel]]

## Функции
- `func setup(m: PaxMod) -> void`
- `func start(g: PaxGame) -> void`
- `func _process(delta: float) -> void`
- `static func _pick(d: Dictionary, keys: Array) -> Variant`
- `func _attach() -> void`
- `func _find_clouds(node: Node3D) -> void` — Облака Земли — отдельная сфера чуть больше планеты с шейдером облаков игры, рядом с узлом планеты (сосед под Main) или его ребёнок. visible игра ставит сама каждый кадр, поэтому прячем слоями отрисовки.
- `func _hide_clouds() -> void`
- `func _feed_flat_map() -> void`
- `func _feed_water(sm: ShaderMaterial) -> bool` — Вода на плоской карте: маска океана из карты провинций Юрумы (id 0 — море) и простая подложка «суша/море». Собирается один раз в фоне, потом отдаётся шейдеру поверхности.
- `func _build_water(src: Image) -> void` — В потоке: id провинции — R + G·256; ноль — вода.
- `func _set_water(o: Image, a: Image) -> void`
- `func restore() -> void` — Земля как была (мод выключают).
- `func _free_markers() -> void`
- `func _main() -> Node` — Корень сцены игры (PaxGame.main) — один раз: свойство устаревшее и ругается при каждом чтении.
- `func _flat_map_open() -> bool` — Плоская карта игры (M) открыта — города на глобусе не показываем.
- `static func dir_of(lat_deg: float, lon_deg: float) -> Vector3`
- `func _make_markers() -> void`
- `func _game_label() -> Label` — Подпись страны/провинции игры на глобусе — образец вида; null, если её нет.
- `static func _dot_half(lb: Label) -> float` — Половина ширины значка в начале подписи — чтобы значок стоял точно на городе.
- `static func _style(lb: Label, src: Label, color: Color) -> void`
- `func _show_markers(on: bool) -> void` — Подписи видны на ближней к камере стороне планеты и стоят над своими якорями.
- `func _city_at(screen: Vector2) -> Node3D` — Город под курсором — по его подписи на экране (она видна только на нашей стороне планеты), или null.
- `func _input(event: InputEvent) -> void`
