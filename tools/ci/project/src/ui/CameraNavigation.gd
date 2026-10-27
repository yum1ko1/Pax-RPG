extends RefCounted
## Заглушка службы camera_navigation игры (res://src/ui/CameraNavigation.gd) — исходников игры тут нет, а от неё
## наследует mods/pax_rpg/src/planet/home_camera.gd. Сигнатуры — по исходникам игры 0.24; в заглушке только то, что
## мод переопределяет или читает.

var view
var model


func zoom(_k: float) -> void:
	pass


func focus_on(_i: int, _instant: bool = false) -> void:
	pass


func to_system(_smooth: bool = false) -> void:
	pass
