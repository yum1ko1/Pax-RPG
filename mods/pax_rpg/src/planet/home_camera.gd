extends "res://src/ui/CameraNavigation.gd"
## Служба camera_navigation игры (main.gd → Pax.replace_service): камера всегда держится за Юруму. Колесо отдаляет
## её до предела игры (около 30 радиусов планеты), но в вид системы она не уходит — там камера висит в пустоте, а
## планета уплывает по орбите. Щелчки, советник и события тоже не уводят её к другим телам: любой фокус — на Юруму.


func zoom(k: float) -> void:
	if view.view_mode == "system":               # мир сохранили в виде системы — колесо возвращает камеру к Юруме
		focus_on(model.earth_index)
		return
	super.zoom(k)


func focus_on(_i: int, instant: bool = false) -> void:
	super.focus_on(model.earth_index, instant)


func to_system(_smooth: bool = false) -> void:
	pass
