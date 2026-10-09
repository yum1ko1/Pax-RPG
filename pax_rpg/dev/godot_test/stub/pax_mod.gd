class_name PaxMod
extends Node
var id := "pax_rpg"
var _lang := {}
func path(r: String) -> String: return "res://mods/pax_rpg/" + r
func read_text(r: String) -> String: return FileAccess.get_file_as_string(path(r))
func shader(r: String) -> Shader: return load(path(r))
func texture(r: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path(r)))
	return ImageTexture.create_from_image(img) if img != null else null
func tr_key(key: String, _args: Array = []) -> String:
	if _lang.is_empty():
		_lang = JSON.parse_string(read_text("data/lang/ru.json"))
	return str(_lang.get(key, key))
func log_info(m) -> void: print("[info] ", m)
func log_warning(m) -> void: print("[warn] ", m)
func log_error(m) -> void: push_error(str(m))
