---
mod: pax_rpg
file: src/travel/loading.gd
lines: 74
weight: 2
tags: [мод/rpg, функция/travel]
---

# loading

`src/travel/loading.gd` · [[Код Pax RPG]] · `extends CanvasLayer` · 74 строк · подключают: **2**

> Экран загрузки между картой мира и локацией: затемнение, название места, строка рассказчика, полоса. run(): темнеет → вызывает middle (построить или убрать локацию — за чёрным экраном) → полоса доходит до конца → экран уходит → вызывает done. Рассказчик пока — готовые строки из data/lang (потом — ИИ).

## Кто подключает
- [[main]]
- [[travel]]

## Функции
- `func setup() -> void`
- `func busy() -> bool`
- `func run(title: String, text: String, seconds: float, middle: Callable, done: Callable) -> void`
- `func _finish(done: Callable) -> void`
