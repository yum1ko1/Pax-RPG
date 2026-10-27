extends "res://src/ui/GalaxyView.gd"
## Служба galaxy_view игры (main.gd → Pax.replace_service): за Юрумовской системой ничего нет — галактика не
## открывается ни колесом у края системы (CameraNavigation.zoom), ни кнопкой, ни консолью. Камера упирается в край
## системы: дальше CameraNavigation её не отпускает. Остальное — как у игры (карта планеты, метки).


func open_galaxy() -> void:
	pass
