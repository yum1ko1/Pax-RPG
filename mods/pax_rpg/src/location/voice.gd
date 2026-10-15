extends Node
## Голос игры для реплик в локации (орк в бою и др.): Main.голос.сказать(текст, перебить, голос) синтезирует фразу
## (Piper), но его проигрыватель в локации не слышно — готовую фразу играем сами на шине мода PaxRpgSfx,
## а его глушим (не stop(): игра ждёт его finished, иначе очередь фраз встанет). Нет голоса игры — системный.
## Как в talk.gd (_speak / _relay_voice), только без окна разговора.

var mod: PaxMod
var game: PaxGame
var _player: AudioStreamPlayer
var _gen := 0


func setup(m: PaxMod, g: PaxGame) -> void:
	mod = m
	game = g
	name = "PaxRpgVoice"
	process_mode = Node.PROCESS_MODE_ALWAYS


## Сказать вслух. which — голос игры: "masculine" | "feminine" | "" (из настроек); pitch < 1 — ниже.
func say(text: String, which := "masculine", pitch := 1.0) -> void:
	_gen += 1
	var main: Object = game.main if game != null else null
	var v: Variant = main.get("голос") if main != null else null
	if v is Object and is_instance_valid(v) and (v as Object).has_method("сказать"):
		var pw: Variant = (v as Object).get("player_widget")
		var old: Variant = (pw as AudioStreamPlayer).stream if pw is AudioStreamPlayer else null
		(v as Object).call("сказать", text, true, which)
		if pw is AudioStreamPlayer:
			_relay(pw as AudioStreamPlayer, old, pitch, _gen)
		return
	var voices := DisplayServer.tts_get_voices_for_language("ru" if TranslationServer.get_locale().begins_with("ru") else "en")
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, voices[0], 80, pitch)


func stop() -> void:
	_gen += 1
	if is_instance_valid(_player):
		_player.stop()


func _relay(pw: AudioStreamPlayer, old: Variant, pitch: float, gen: int) -> void:
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if gen != _gen or not is_instance_valid(pw):
			return
		if pw.stream != null and pw.stream != old:
			pw.volume_db = -80.0
			if _player == null:
				_player = AudioStreamPlayer.new()
				_player.process_mode = Node.PROCESS_MODE_ALWAYS
				add_child(_player)
			_player.bus = "PaxRpgSfx" if AudioServer.get_bus_index("PaxRpgSfx") >= 0 else "Master"
			_player.stream = pw.stream
			_player.pitch_scale = pitch
			_player.volume_db = 3.0
			_player.play()
			return
