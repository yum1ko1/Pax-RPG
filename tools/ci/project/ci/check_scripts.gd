extends SceneTree
## Компиляция всех .gd мода: ошибка — строка «check: FAIL <файл>» (сами ошибки с номерами строк Godot печатает
## выше: «SCRIPT ERROR: Parse Error: … at: GDScript::reload (res://…:строка)»). Код выхода 1, если что-то не собралось.

func _initialize() -> void:
	var files := _scan("res://mods")
	var bad := 0
	for f: String in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			print("check: FAIL ", f)
			bad += 1
		else:
			print("check: ok   ", f)
	# скрипт, который не собрался из-за зависимости, Godot иногда отдаёт «живым» — итог считает run_checks.sh по
	# строкам SCRIPT ERROR выше
	print("check: %d файлов" % files.size())
	quit(1 if bad > 0 else 0)


func _scan(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_scan(dir.path_join(d)))
	return out
