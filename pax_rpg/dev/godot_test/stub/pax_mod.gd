class_name PaxMod
extends Node
var id := "pax_rpg"
var _lang := {}
func path(r: String) -> String: return "res://mods/pax_rpg/" + r
func read_text(r: String) -> String: return FileAccess.get_file_as_string(path(r))
func shader(r: String) -> Shader: return load(path(r))
func sound(r: String) -> AudioStream:   # как Pax.sound в игре: wav/ogg из папки мода
	var b := FileAccess.get_file_as_bytes(path(r))
	if b.is_empty():
		return null
	return AudioStreamWAV.load_from_buffer(b) if r.ends_with(".wav") else AudioStreamOggVorbis.load_from_buffer(b)
func model(r: String) -> Node3D:   # как Pax.model в игре: glb из папки мода через GLTFDocument
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path(r)), st) != OK:
		return null
	return doc.generate_scene(st) as Node3D
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
