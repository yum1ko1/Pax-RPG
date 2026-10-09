extends CanvasLayer
## Экран загрузки между картой мира и локацией: затемнение, название места, строка рассказчика, полоса.
## run(): темнеет → вызывает middle (построить или убрать локацию — за чёрным экраном) → полоса доходит до
## конца → экран уходит → вызывает done. Рассказчик пока — готовые строки из data/lang (потом — ИИ).

const FADE := 0.3                  # с, появление и уход экрана

var _bg: ColorRect
var _title: Label
var _text: Label
var _bar: ProgressBar
var _busy := false


func setup() -> void:
	name = "PaxRpgLoading"
	layer = 110                    # над окнами игры и над локацией
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.03, 0.03, 0.1)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 18)
	centre.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.96))
	box.add_child(_title)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color(0.75, 0.86, 1.0))
	box.add_child(_text)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(640, 10)
	box.add_child(_bar)


func busy() -> bool:
	return _busy


func run(title: String, text: String, seconds: float, middle: Callable, done: Callable) -> void:
	if _busy:
		return
	_busy = true
	_title.text = title
	_text.text = text
	_bar.value = 0.0
	_bg.modulate.a = 0.0
	visible = true
	var tw := create_tween()
	tw.tween_property(_bg, "modulate:a", 1.0, FADE)
	tw.tween_callback(middle)
	tw.tween_property(_bar, "value", 100.0, maxf(seconds, 0.1))
	tw.tween_property(_bg, "modulate:a", 0.0, FADE)
	tw.tween_callback(_finish.bind(done))


func _finish(done: Callable) -> void:
	visible = false
	_busy = false
	done.call()
