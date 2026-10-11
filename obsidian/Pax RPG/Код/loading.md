---
mod: pax_rpg
file: src/travel/loading.gd
lines: 371
weight: 2
tags: [мод/rpg, функция/travel]
---

# loading

`src/travel/loading.gd` · [[Код Pax RPG]] · `extends CanvasLayer` · 371 строк · подключают: **2**

> Экран загрузки между картой мира и локацией. Фон — арт (textures/loading/art_*.jpg, медленно наезжает), сверху вниз: название места, строка рассказчика; внизу — чёрный воин на колене в кольце загрузки. Каждые 20 % в него вонзается катана (звон, искры, вздрагивает); на 100 % — пять катан, и воин падает замертво (покадровая анимация: textures/loading/death_sheet.png — рыцарь мода с анимацией смерти Meshy, отрисованный силуэтом в Blender, pax_rpg/dev/blender/knight/death_frames.py; катаны едут за его костями из death.json). От места, где он лёг, экран «расползается» (shaders/reveal.gdshader) — под ним уже игра. run(): появление → middle (построить / убрать локацию, пока экран закрыт) → катаны → падение → done.

## Подключает
- [[katana]]
- [[hud]]

## Кто подключает
- [[main]]
- [[travel]]

## Функции
- `func setup(m: PaxMod = null) -> void`
- `func _player(pattern: String, n: int, vol: float) -> AudioStreamPlayer`
- `func _sfx(p: AudioStreamPlayer) -> void`
- `func busy() -> bool`
- `func run(title: String, text: String, seconds: float, middle: Callable, done: Callable) -> void`
- `func _finish(done: Callable) -> void`
- `func _set_reveal(r: float) -> void`
- `func _process(delta: float) -> void`
- `func _new_fx(spread: float) -> Dictionary`
- `func _h() -> float`
- `func _warrior_rect() -> Rect2` — Кадр воина на экране (весь кадр листа; воин на колене — по центру внизу).
- `func _frame() -> int` — Номер кадра: дрожь (первые 12 %) — кадр 0, потом вся анимация падения.
- `func _shiver() -> Vector2`
- `func _bone(name: String) -> Vector2` — Кость в текущем кадре → экран.
- `func _hit_pose(i: int) -> Array` — Где на теле катана и куда смотрит её рукоять.
- `func _body_point(_uv: Vector2) -> Vector2` — Точка на экране для «расползания» — где он лёг (таз в последнем кадре).
- `func _draw_stage() -> void`
- `func _draw_flash(vs: Vector2) -> void`
- `func _draw_ring(h: float) -> void`
