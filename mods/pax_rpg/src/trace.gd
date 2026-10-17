extends RefCounted
## След для поиска вылетов: метки в godot.log через printerr — журнал ошибок игра сбрасывает на диск сразу,
## поэтому после падения в конце лога — последнее, что успел сделать мод. Метки из потоков — [поток].


static func mark(what: String) -> void:
	var th := "" if OS.get_thread_caller_id() == OS.get_main_thread_id() else " [поток]"
	printerr("[pax_rpg trace] %d f%d%s %s" % [Time.get_ticks_msec(), Engine.get_process_frames(), th, what])
