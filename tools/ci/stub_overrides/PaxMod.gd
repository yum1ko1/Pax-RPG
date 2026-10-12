# Рабочие тела для прогона вне игры: файлы мода — из res://mods/<id>/, тексты — из data/lang/ru.json.
var _lang: Dictionary = {}
var _settings: Dictionary = {}
func path(relative: String) -> String:
	return "res://mods/%s/%s" % [id if id != "" else "pax_rpg", relative]
func read_bytes(relative: String) -> PackedByteArray:
	var p := path(relative)
	return FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()
func read_text(relative: String) -> String:
	var p := path(relative)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
func texture(relative: String) -> Texture2D:
	# как в игре: картинка мода без импорта Godot (models/ в CI под .gdignore — импорт 4K-текстур долгий)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path(relative)))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
func sound(relative: String) -> AudioStream:
	return load(path(relative)) as AudioStream if ResourceLoader.exists(path(relative)) else null
func shader(relative: String) -> Shader:
	return load(path(relative)) as Shader if ResourceLoader.exists(path(relative)) else null
func model(relative: String) -> Node3D:
	var full := ProjectSettings.globalize_path(path(relative))
	if not FileAccess.file_exists(full):
		push_error("stub PaxMod.model: no file " + path(relative))
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(full, state) != OK:
		push_error("stub PaxMod.model: bad glb " + path(relative))
		return null
	return doc.generate_scene(state) as Node3D
func tr_key(key: String, args: Array = []) -> String:
	if _lang.is_empty():
		var parsed: Variant = JSON.parse_string(read_text("data/lang/ru.json"))
		_lang = parsed if parsed is Dictionary else {"_": ""}
	var s := str(_lang.get(key, key))
	return s % args if not args.is_empty() else s
func get_setting(key: String, default_value = null):
	return _settings.get(key, default_value)
func set_setting(key: String, value):
	_settings[key] = value
func log_info(message: String):
	print("[mod] ", message)
func log_warning(message):
	push_warning("[mod] " + str(message))
func log_error(message):
	push_error("[mod] " + str(message))
