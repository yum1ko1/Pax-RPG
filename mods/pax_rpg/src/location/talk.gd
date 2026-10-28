extends Control
## Разговор с жителем через нейросеть игры (mod.ask_ai, канал «talk»). Подошёл, E — внизу окно: имя и ремесло
## существа, лента реплик, поле ввода (игрок пишет сам). Над полем — «ключи» тона: вопрос, торг, задание, лесть,
## угроза, прощание; не выбран — тон угадывается по словам (_guess). Ключ уходит нейросети вместе с репликой: она
## понимает, чего хочет игрок, и отвечает в характере жителя, с настроением и сдвигом отношения к герою
## (npc.gd: relation 0..100). Нет нейросети или лимит — короткий ответ из заготовок по ключу.
## Enter — сказать, Esc — уйти. Мир на паузе, пока окно открыто (location.gd → paused()).

signal closed
signal rewarded(coins: int)          # сдано задание — награда золотом (location.gd → progress.add_gold)
signal quest_changed                 # выдано или сдано задание — точка на глобусе меняется (location → travel → planet)
signal shop_requested                # «Лавка» у торговца (location.gd → shop_view.gd)
signal contract_done(q: Dictionary)  # сдано поручение — награда и выбор приёма (location.gd → _contract_reward)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Quest := preload("res://mods/pax_rpg/src/location/quest.gd")
const KEYS := ["question", "trade", "quest", "flatter", "threat", "bye"]
const W := 760.0
const H := 380.0

var mod: PaxMod
var hud: Hud
var context: Dictionary = {}         # город, время суток, герой — location.gd
var _npc: Node                       # npc.gd
var game: PaxGame                    # голос игры (Main.голос) — задаёт location.gd
var _log: RichTextLabel
var _edit: LineEdit
var _title: Label
var _sub: Label
var _keys: Array[Button] = []
var _key := ""                       # выбранный ключ тона ("" — угадать)
var _history: Array = []             # [{"who": "hero"|"npc", "text": …}]
var _waiting := false
var _token := 0                      # номер разговора/запроса: ответ и таймеры чужого (прежнего) — не трогают нынешний
const TIMEOUT := 120.0               # с: локальной нейросети игрока нужно время (видеокарта свободна — режим разговора)
const MAX_LEN := 240
var _panel: Control


func setup(m: PaxMod, h: Hud) -> void:
	mod = m
	hud = h
	name = "PaxRpgTalk"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var back := ColorRect.new()                         # отдельное окно: фон на весь экран (3D под ним не рисуется)
	back.color = Color(0.03, 0.025, 0.035, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	_panel = Control.new()
	_panel.size = Vector2(W, H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	var serif := Hud._sys(["Cormorant Garamond", "Georgia", "Times New Roman"], 700)
	var sans := Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	_title = _label(serif, 30, Vector2(28, 14))
	_sub = _label(sans, 14, Vector2(30, 52))
	_log = RichTextLabel.new()
	_log.position = Vector2(28, 80)
	_log.size = Vector2(W - 56, 180)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # реплики переносятся по словам — лента идёт вниз
	_log.add_theme_font_override("normal_font", sans)
	_log.add_theme_font_size_override("normal_font_size", 17)
	_panel.add_child(_log)
	var manner := _label(sans, 15, Vector2(28, 276))      # подпись: ключи — манера реплики, а не её смысл
	manner.text = mod.tr_key("pax_rpg_talk_manner")
	manner.tooltip_text = mod.tr_key("pax_rpg_talk_manner_tip")
	manner.mouse_filter = Control.MOUSE_FILTER_PASS
	# ширину — по шрифту: вне дерева размер надписи ещё не посчитан (reset_size давал 0 — подпись уходила под кнопку)
	var x := 28.0 + sans.get_string_size(manner.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0
	for k: String in KEYS:                              # ключи тона
		var b := Button.new()
		b.text = mod.tr_key("pax_rpg_talk_key_" + k)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(x, 270)
		b.add_theme_font_override("font", sans)
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = mod.tr_key("pax_rpg_talk_manner_tip")
		b.toggled.connect(_on_key.bind(k))
		_panel.add_child(b)
		var bw := sans.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
		b.size = Vector2(bw, 32.0)
		x += bw + 8.0
		_keys.append(b)
	_give_btn = Button.new()                            # «Отдать: вещь» — только выдавшему жителю и если вещь найдена
	_give_btn.position = Vector2(W - 28 - 230, 20)
	_give_btn.size = Vector2(230, 36)
	_give_btn.focus_mode = Control.FOCUS_NONE
	_give_btn.add_theme_font_override("font", sans)
	_give_btn.add_theme_font_size_override("font_size", 15)
	_give_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_give_btn.visible = false
	_give_btn.pressed.connect(_hand_over)
	_panel.add_child(_give_btn)
	_contract_btn = Button.new()                        # «❖ Поручение» → «Принять» — у квестодателя (quest.gd → marker)
	_contract_btn.position = _give_btn.position
	_contract_btn.size = _give_btn.size
	_contract_btn.focus_mode = Control.FOCUS_NONE
	_contract_btn.add_theme_font_override("font", sans)
	_contract_btn.add_theme_font_size_override("font_size", 15)
	_contract_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_contract_btn.visible = false
	_contract_btn.pressed.connect(_contract_press)
	_panel.add_child(_contract_btn)
	_shop_btn = Button.new()                            # «Лавка» — у торговцев базара (npc.shop, лавочник trader)
	_shop_btn.position = Vector2(W - 28 - 180, 20)
	_shop_btn.size = Vector2(180, 36)
	_shop_btn.focus_mode = Control.FOCUS_NONE
	_shop_btn.text = mod.tr_key("pax_rpg_talk_shop")
	_shop_btn.add_theme_font_override("font", sans)
	_shop_btn.add_theme_font_size_override("font_size", 15)
	_shop_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_shop_btn.visible = false
	_shop_btn.pressed.connect(func() -> void: shop_requested.emit())
	_panel.add_child(_shop_btn)
	_edit = LineEdit.new()
	_edit.position = Vector2(28, 314)
	_edit.size = Vector2(W - 56, 40)
	_edit.placeholder_text = mod.tr_key("pax_rpg_talk_placeholder")
	_edit.add_theme_font_override("font", sans)
	_edit.add_theme_font_size_override("font_size", 18)
	_edit.max_length = MAX_LEN                         # длинная простыня съела бы лимит запроса
	_edit.text_submitted.connect(_say)
	_panel.add_child(_edit)
	resized.connect(_place)


func _label(f: Font, fs: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l


func _place() -> void:
	var s := clampf(size.y / 1080.0, 0.6, 2.0) * 1.3          # окно разговора — крупнее
	_panel.scale = Vector2(s, s)
	_panel.position = (size - Vector2(W, H) * s) * 0.5          # по центру окна


func open(npc: Node) -> void:
	_token += 1
	_waiting = false
	_npc = npc
	_history = []
	_key = ""
	for b: Button in _keys:
		b.set_pressed_no_signal(false)
	_title.text = str(npc.get("npc_name"))
	_sub.text = "%s · %s" % [_trade_of(npc), _relation_text()]
	_log.clear()
	_log.append_text("[i][color=#9a9080]%s[/color][/i]\n" % mod.tr_key("pax_rpg_talk_hint"))
	visible = true
	_place()
	_title.add_theme_color_override("font_color", hud.c_text if hud != null else Hud.TEXT)
	_sub.add_theme_color_override("font_color", hud.c_muted if hud != null else Hud.MUTED)
	_edit.text = ""
	_edit.grab_focus()
	_offer_shown = false
	_update_give()
	_panel.queue_redraw()


var _shop_btn: Button


func close() -> void:
	if not visible:
		return
	visible = false
	DisplayServer.tts_stop()
	if is_instance_valid(_voice):
		_voice.stop()
	_token += 1                                        # запоздалый ответ и таймеры этого разговора — больше не его
	_waiting = false
	_giving = false
	_edit.release_focus()
	closed.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(e: InputEvent) -> void:              # Esc и из поля ввода (LineEdit забирает клавиши раньше)
	if visible and e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_key(on: bool, k: String) -> void:
	_key = k if on else ""
	for b: Button in _keys:                            # один ключ за раз
		if b.button_pressed and b.text != mod.tr_key("pax_rpg_talk_key_" + k):
			b.set_pressed_no_signal(false)
	_edit.grab_focus()


func _relation_text() -> String:
	var r := int(_npc.get("relation")) if is_instance_valid(_npc) else 50
	var k := "hostile" if r < 25 else ("wary" if r < 45 else ("neutral" if r < 60 else ("warm" if r < 80 else "friend")))
	return mod.tr_key("pax_rpg_talk_rel_" + k)


## Ключ по словам реплики, если игрок его не выбрал.
func _guess(t: String) -> String:
	var s := t.to_lower()
	var rules := [["bye", ["прощай", "пока", "до встречи", "бывай", "bye", "farewell"]],
		["threat", ["убью", "убить", "зарежу", "отдавай", "смерть", "пожалеешь", "kill", "or else"]],
		["trade", ["купить", "продать", "продаёшь", "цена", "сколько стоит", "товар", "золото", "buy", "sell", "price"]],
		["quest", ["работа", "задание", "помочь", "помощь", "дело", "поручение", "quest", "job", "help"]],
		["flatter", ["красив", "умн", "славн", "лучший", "уважаю", "восхищ", "great", "beautiful"]]]
	for r: Array in rules:
		for w: String in r[1]:
			if s.contains(w):
				return str(r[0])
	return "question"


## Реплика героя снаружи (голосом — voice_talk.gd): как набранная в поле ввода.
func say_text(text: String) -> void:
	_say(text)


func _say(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _waiting or not is_instance_valid(_npc):
		return
	var guessed := _guess(text)
	var key := _key if _key != "" else guessed
	# слова главнее кнопки: угроза или прощание словами — это угроза или прощание, какой бы ключ ни был выбран
	var eff := guessed if (guessed == "threat" or guessed == "bye") and key != guessed else key
	_edit.text = ""
	_history.append({"who": "hero", "text": text})
	_line(str(context.get("hero", "")), text, true)
	_waiting = true
	_log.append_text("[i][color=#8a8070]%s[/color][/i]" % _esc(mod.tr_key("pax_rpg_talk_thinking") % str(_npc.get("npc_name"))))   # пока нейросеть думает
	var data := _context(text, key, guessed, eff)
	_ask(data, eff, _token, 0)


## Чем живёт житель сегодня — по ремеслу (нейросеть опирается на это, а не на пустоту).
const CONCERNS := {
	"merchant": "торговля идёт плохо, караваны боятся разбойников",
	"guard": "устал стоять на воротах, ночью видели чужаков у стены",
	"herder": "пропали две овцы, наверно волки",
	"shaman": "духи степи неспокойны, ждёт дурного знака",
	"smith": "хан заказал наконечники к празднику, а угля мало",
	"beggar": "просит подаяние у фонтана, знает все слухи",
	"cook": "варит похлёбку на всю улицу, соль подорожала",
	"porter": "таскает тюки с рынка, болит спина",
	"trader": "держит лавку на базаре: товар каждый день новый, а ещё при лавке Колесо Судьбы — крутят за золото",
}


## Ремесло жителя словами (генератор names.gd); у прежних — род занятий.
func _trade_of(npc: Node) -> String:
	var t := str(npc.get("trade"))
	return t if t != "" and t != "<null>" else mod.tr_key("pax_rpg_npc_role_" + str(npc.get("role")))


## Сцена для нейросети одним описанием (текстом): вложенные поля она принимала за форму и возвращала их копией вместо
## реплики — житель «молчал». Поля данных — только то, на что отвечать.
func _context(text: String, key: String, guessed: String, eff: String) -> Dictionary:
	var role := str(_npc.get("role"))
	var lines: Array[String] = []
	for h: Variant in _history.slice(maxi(0, _history.size() - 12)):
		var hd: Dictionary = h
		lines.append("%s: %s" % [str(context.get("hero", "Герой")) if str(hd.get("who", "")) == "hero" else str(_npc.get("npc_name")),
			str(hd.get("text", ""))])
	var q := _quest_info(eff)
	var scene := "Мир Юрума: мана течёт в кристаллах и облаках, империи делят степи и горы. Город — %s: %s Сейчас %s. " % [
		str(context.get("city", "")), mod.tr_key("pax_rpg_talk_city_about"), str(context.get("time", ""))]
	scene += "Ты — %s, %s, %s. Характер: %s. Сегодня тебя заботит: %s. К собеседнику ты относишься: %s (%d из 100). " % [
		str(_npc.get("npc_name")), mod.tr_key("pax_rpg_npc_race_" + str(_npc.get("race"))), _trade_of(_npc).to_lower(),
		str(_npc.get("temper")), _worry_now(role), _relation_text(), int(_npc.get("relation"))]
	scene += "Собеседник — %s, %s: %s. " % [str(context.get("hero", "")), str(context.get("hero_title", "")),
		mod.tr_key("pax_rpg_talk_hero_looks")]
	if not lines.is_empty():
		scene += "Уже сказано:\n" + "\n".join(lines)
	return {"scene": scene, "player_line": text, "manner": key, "manner_by_words": guessed,
		"task": str(q.get("state", "none")), "task_item": str(q.get("item", ""))}


## Запрос — коротко и по-русски, с примерами: маленькая локальная модель игрока путалась в длинных английских
## правилах и при высокой температуре отвечала красиво, но невпопад.
func _prompt() -> String:
	return "Ты — житель из описания «scene». Герой сказал тебе «player_line». Ответь ему вслух от лица этого жителя.\n" \
		+ "Главное: сначала прямо и по смыслу ответь на его слова (на вопрос — ответ, на комплимент — реакция, на просьбу — " \
		+ "да или нет). Потом можно одной фразой добавить о себе. Говори просто и понятно, 1–3 коротких предложения, " \
		+ "без странных метафор. Не повторяй уже сказанное.\n" \
		+ "Примеры:\n" \
		+ "Герой: «Как дела?» → Житель-кузнец: «Да всё в работе, рыцарь. Хан заказал наконечники к празднику, а угля не хватает.»\n" \
		+ "Герой: «Ты красивый» → Житель: «Ха! Мне такого давно не говорили. Ты чего-то хочешь, да?»\n" \
		+ "Герой: «Есть работа?» → Житель: «Есть. Я потерял амулет в лесу за городом — найдёшь, отблагодарю.»\n" \
		+ "«task» — о задании: give — попроси найти «task_item» в лесу у города; return — герой отдаёт вещь сейчас, " \
		+ "поблагодари; has_it — вещь у него, попроси отдать; pending — ты ждёшь вещь; other или none — о задании не говори. " \
		+ "«manner» — как герой это сказал (вопрос, торг, задание, лесть, угроза, прощание); смысл — по его словам. " \
		+ "Не говори про ИИ и игры. Ответ — только JSON, ровно так: {\"reply\": \"твои слова\"}"


## Запрос к нейросети игры; пусто (нет связи, лимит, тайм-аут) — ещё одна попытка, потом честное «не ответил».
func _ask(data: Dictionary, eff: String, tok: int, attempt: int) -> void:
	_attempt_live = attempt
	var asked := mod.ask_ai("talk", _prompt(), data, func(a: Dictionary) -> void: _got(a, data, eff, tok, attempt),
		{"temperature": 0.6, "max_tokens": 260})
	mod.log_info("[pax_rpg] talk: ask_ai %s (attempt %d)" % ["sent" if asked else "refused", attempt + 1])
	if not asked:
		_got({}, data, eff, tok, attempt)
	else:
		get_tree().create_timer(TIMEOUT, true).timeout.connect(func() -> void:
			if _waiting and tok == _token and _attempt_live == attempt:
				_got({}, data, eff, tok, attempt))


var _attempt_live := -1


func _got(a: Dictionary, data: Dictionary, eff: String, tok: int, attempt: int) -> void:
	if tok != _token or not _waiting or attempt != _attempt_live:
		return
	mod.log_info("[pax_rpg] talk: answer keys %s" % str(a.keys()))
	var has := false
	for k: String in ["reply", "answer", "text", "line", "response", "speech", "message"]:
		if a.get(k, null) is String and str(a[k]).strip_edges() != "":
			has = true
	if not has:
		mod.log_info("[pax_rpg] talk: no reply in answer: %s" % str(a).left(300))
	if not has and attempt == 0:
		_attempt_live = 1
		get_tree().create_timer(2.5, true).timeout.connect(func() -> void:
			if _waiting and tok == _token:
				_ask(data, eff, tok, 1))
		return
	_answer(a, eff, tok)


func _answer(a: Dictionary, key: String, tok: int) -> void:
	if tok != _token or not _waiting:
		return                                          # ответ на прежний разговор или уже отвечено (тайм-аут)
	_waiting = false
	if not visible or not is_instance_valid(_npc):
		return
	_log.remove_paragraph(_log.get_paragraph_count() - 1)   # «…»
	var reply := ""
	for k: String in ["reply", "answer", "text", "line", "response", "speech", "message"]:
		if a.get(k, null) is String and str(a[k]).strip_edges() != "":
			reply = str(a[k]).strip_edges()
			break
	var delta := clampi(int(a.get("relation_delta", {"flatter": 3, "threat": -8, "quest": 1, "trade": 1}.get(key, 1))), -15, 15) \
		if reply != "" else 0                               # нейросеть даёт только реплику — отношение по манере
	var qs := _quest_after(key)
	if qs == "return":
		delta = maxi(delta, 15)                          # вернул вещь — отношение растёт заметно
	_npc.set("relation", clampi(int(_npc.get("relation")) + delta, 0, 100))
	var cd: Dictionary = context.get("city_data", {})
	Quest.set_relation(mod, str(cd.get("id", "")), int(_npc.get("npc_index")), int(_npc.get("relation")))
	if reply != "":
		_history.append({"who": "npc", "text": reply})
		_line(str(_npc.get("npc_name")), reply, false)
		_speak(reply)
	else:                                               # без заготовок: нейросеть не ответила — так и пишем
		_log.append_text("[i][color=#8a8070]%s[/color][/i]\n\n" % _esc(mod.tr_key("pax_rpg_talk_silent") % str(_npc.get("npc_name"))))
	_sub.text = "%s · %s" % [_trade_of(_npc), _relation_text()]
	if _npc.has_method("react"):
		_npc.call("react", str(a.get("mood", "neutral")))
	_update_give()
	if qs == "give":
		var q := Quest.get_q(mod)
		_log.append_text("[color=#e8c070]◆ %s[/color]\n" % _esc(mod.tr_key("pax_rpg_quest_new") % mod.tr_key("pax_rpg_qitem_" + str(q.get("item", "")))))
		quest_changed.emit()
	elif qs == "return":
		var coins := randi_range(80, 150)
		rewarded.emit(coins)
		_log.append_text("[color=#e8c070]◆ %s[/color]\n" % _esc(mod.tr_key("pax_rpg_gold_got") % coins))
		_log.append_text("[color=#e8c070]◆ %s[/color]\n" % _esc(mod.tr_key("pax_rpg_quest_done")))
		quest_changed.emit()
	if key == "bye":
		var t := _token
		get_tree().create_timer(1.6, true).timeout.connect(func() -> void:
			if t == _token:
				close())


func _line(who: String, text: String, hero: bool) -> void:
	var c: Color = (hud.c_blue if hud != null else Hud.BLUE) if hero else (hud.c_pink if hud != null else Hud.PINK)
	# имя — своей строкой, реплика — под ним с отступом, между репликами — пустая строка: лента сверху вниз
	_log.append_text("[b][color=#%s]%s[/color][/b]\n[indent]%s[/indent]\n\n" % [c.to_html(false), _esc(who), _esc(text)])


func _is_giver() -> bool:
	var q := Quest.get_q(mod)
	var cd: Dictionary = context.get("city_data", {})
	return not q.is_empty() and str(q.get("city", "")) == str(cd.get("id", "")) and int(q.get("npc", -1)) == int(_npc.get("npc_index"))


func _update_give() -> void:
	var q := Quest.get_q(mod)
	var on := _is_giver() and str(q.get("state", "")) == "found"
	_give_btn.visible = on
	var offer := is_instance_valid(_npc) and _marker() == "offer"
	_contract_btn.visible = offer
	_contract_btn.position.x = _give_btn.position.x
	if offer:
		_contract_btn.text = mod.tr_key("pax_rpg_contract_accept" if _offer_shown else "pax_rpg_contract_btn")
	_shop_btn.visible = is_instance_valid(_npc) and (str(_npc.get("role")) == "trader" or bool(_npc.get("shop")))
	_give_btn.position.x = W - 28 - 230 - (190.0 if _shop_btn.visible else 0.0)   # рядом с «Лавкой», не под ней
	_contract_btn.position.x = _give_btn.position.x
	if on:
		_give_btn.text = mod.tr_key("pax_rpg_talk_give") % mod.tr_key("pax_rpg_qitem_" + str(q.get("item", ""))) \
			if not q.has("contract") else mod.tr_key("pax_rpg_contract_turn_in")


## Отдать найденную вещь: реплика героя от его имени, задание сдаётся по ответу.
func _hand_over() -> void:
	if _waiting:
		return
	var q := Quest.get_q(mod)
	if q.has("contract"):                                # поручение сдаётся сразу, без ожидания нейросети
		_turn_in_contract()
		return
	_giving = true
	_say(mod.tr_key("pax_rpg_talk_give_line") % mod.tr_key("pax_rpg_qitem_" + str(q.get("item", ""))))


## Что про задание знает нейросеть в этой реплике: give / return / has_it / pending / other / none (+ что за вещь).
func _quest_info(key: String) -> Dictionary:
	var q := Quest.get_q(mod)
	if q.is_empty():
		if key == "quest" and int(_npc.get("npc_index")) >= 0 and _contract_id() == "":   # у квестодателя — поручение
			_pending_item = Quest.ITEMS[randi() % Quest.ITEMS.size()]
			return {"state": "give", "item": mod.tr_key("pax_rpg_qitem_" + _pending_item)}
		return {"state": "none"}
	var item := Quest.short(mod, q)
	if _is_giver():
		if str(q.get("state", "")) == "found":
			return {"state": "return" if _giving else "has_it", "item": item}
		return {"state": "pending", "item": item}
	return {"state": "other"}


var _pending_item := ""
var _giving := false                 # эта реплика — «отдать вещь» (кнопка _give_btn): только она сдаёт задание
var _give_btn: Button


## После ответа: выдать или принять задание. Возвращает give / return / "".
func _quest_after(key: String) -> String:
	var q := Quest.get_q(mod)
	if q.is_empty() and key == "quest" and _pending_item != "" and int(_npc.get("npc_index")) >= 0:
		var cd: Dictionary = context.get("city_data", {})
		Quest.give(mod, cd, int(_npc.get("npc_index")), str(_npc.get("npc_name")))
		q = Quest.get_q(mod)
		q["item"] = _pending_item                        # та вещь, о которой житель только что говорил
		mod.set_setting("quest", q)
		_pending_item = ""
		return "give"
	if _giving and not q.is_empty() and _is_giver() and str(q.get("state", "")) == "found":
		_giving = false
		Quest.finish(mod)
		return "return"
	_giving = false
	return ""


## Квадратные скобки из ответа или реплики — текстом, не разметкой ленты.
static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	var gold: Color = hud.c_gold if hud != null else Hud.GOLD
	_panel.draw_rect(r, Color(0.04, 0.035, 0.03, 0.92))
	_panel.draw_rect(r, Color(gold, 0.85), false, 2.0)
	_panel.draw_rect(r.grow(-6.0), Color(gold, 0.3), false, 1.0)
	_panel.draw_line(Vector2(28, 74), Vector2(W - 28, 74), Color(gold, 0.45), 1.0)
	for cx: float in [0.0, W]:
		for cy: float in [0.0, H]:
			_panel.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - 7), Vector2(cx + 7, cy), Vector2(cx, cy + 7),
				Vector2(cx - 7, cy)]), gold)


var _voice: AudioStreamPlayer


## Голос игры синтезирует фразу (Piper), но его проигрыватель в локации не слышно: как только он получил новую
## фразу — играем её сами на шине мода PaxRpgSfx, а его глушим (иначе вдвоём, если он всё-таки звучит).
func _relay_voice(pw: AudioStreamPlayer, old: Variant, v: Object, tok: int) -> void:
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if tok != _token or not visible or not is_instance_valid(pw):
			return
		if pw.stream != null and pw.stream != old:
			mod.log_info("talk voice: phrase ready (bus %s, playing %s, mute %s)" % [pw.bus, str(pw.playing),
				str(AudioServer.is_bus_mute(maxi(0, AudioServer.get_bus_index(pw.bus))))])
			pw.volume_db = -80.0                       # не stop(): игра ждёт его finished, иначе очередь фраз встанет
			if _voice == null:
				_voice = AudioStreamPlayer.new()
				_voice.process_mode = Node.PROCESS_MODE_ALWAYS
				add_child(_voice)
			_voice.bus = "PaxRpgSfx" if AudioServer.get_bus_index("PaxRpgSfx") >= 0 else "Master"
			_voice.stream = pw.stream
			_voice.pitch_scale = pw.pitch_scale
			_voice.play()
			return
	mod.log_info("talk voice: no phrase in 30 s (%s)" % str(v.get("last_error")))


const VOICE_METHODS := ["сказать", "говорить", "озвучить", "произнести", "прочитать", "speak", "say", "talk"]


## Реплика вслух: голос игры (Main.голос — его метод «сказать»), иначе системный голос (DisplayServer).
func _speak(text: String) -> void:
	var main: Object = game.main if game != null else null
	var v: Variant = main.get("голос") if main != null else null
	if v is Object and is_instance_valid(v):
		for want: String in VOICE_METHODS:
			for m: Dictionary in (v as Object).get_method_list():
				var n := str(m["name"])
				var args: Array = m.get("args", [])
				if not n.trim_prefix("_").begins_with(want) or args.is_empty():
					continue
				var call_args: Array = [text]
				for k in range(1, args.size() - (m.get("default_args", []) as Array).size()):
					call_args.append("" if int((args[k] as Dictionary).get("type", TYPE_STRING)) == TYPE_STRING else null)
				var pw: Variant = (v as Object).get("player_widget")
				var old: Variant = (pw as AudioStreamPlayer).stream if pw is AudioStreamPlayer else null
				(v as Object).callv(n, call_args)
				mod.log_info("talk voice: Main.голос.%s" % n)
				if pw is AudioStreamPlayer:
					_relay_voice(pw as AudioStreamPlayer, old, v as Object, _token)
				return
	var voices := DisplayServer.tts_get_voices_for_language("ru" if TranslationServer.get_locale().begins_with("ru") else "en")
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, voices[0])



# ---------- поручения (quest.gd → CONTRACTS) ----------

var _contract_btn: Button
var _offer_shown := false            # описание поручения уже в ленте — кнопка стала «Принять»


func _city_id() -> String:
	return str((context.get("city_data", {}) as Dictionary).get("id", ""))


func _contract_id() -> String:
	return Quest.contract_of(mod, _city_id(), int(_npc.get("npc_index"))) if is_instance_valid(_npc) else ""


func _marker() -> String:
	return Quest.marker(mod, _city_id(), int(_npc.get("npc_index")))


## Забота жителя для нейросети: у квестодателя с несданным поручением — его беда (о ней он и попросит).
func _worry_now(role: String) -> String:
	var id := _contract_id()
	if id != "" and not Quest.is_done(mod, id):
		return mod.tr_key("pax_rpg_contract_worry_" + id)
	return str(_npc.get("worry")) if str(_npc.get("worry")) != "" else str(CONCERNS.get(role, ""))


## Первое нажатие — житель рассказывает о деле (описание, награда); второе — герой берётся.
func _contract_press() -> void:
	var id := _contract_id()
	if id == "" or _marker() != "offer":
		return
	var c: Dictionary = Quest.CONTRACTS[id]
	if not _offer_shown:
		_offer_shown = true
		_line(str(_npc.get("npc_name")), mod.tr_key("pax_rpg_contract_ask_" + id), false)
		_log.append_text("[color=#e8c070]◆ %s[/color]\n\n" % _esc(mod.tr_key("pax_rpg_contract_terms") % [
			mod.tr_key("pax_rpg_contract_name_" + id), int(c.gold), int(c.xp)]))
		_update_give()
		return
	var q := Quest.take(mod, context.get("city_data", {}), id, int(_npc.get("npc_index")), str(_npc.get("npc_name")))
	_line(str(context.get("hero", "")), mod.tr_key("pax_rpg_contract_yes"), true)
	_log.append_text("[color=#e8c070]◆ %s[/color]\n\n" % _esc(mod.tr_key("pax_rpg_contract_taken") % [Quest.goal(mod, q),
		Quest.place(mod, q)]))
	_npc.set("relation", clampi(int(_npc.get("relation")) + 3, 0, 100))
	Quest.set_relation(mod, _city_id(), int(_npc.get("npc_index")), int(_npc.get("relation")))
	_update_give()
	quest_changed.emit()


## Сдать поручение: благодарность жителя (заготовка), запись стёрта, награда — location.gd (contract_done).
func _turn_in_contract() -> void:
	var q := Quest.complete(mod)
	var id := str(q.get("contract", ""))
	_line(str(_npc.get("npc_name")), mod.tr_key("pax_rpg_contract_thanks_" + id), false)
	var coins := roundi(Quest.reward_gold(q))
	_log.append_text("[color=#e8c070]◆ %s[/color]\n\n" % _esc(mod.tr_key("pax_rpg_contract_done") % mod.tr_key("pax_rpg_contract_name_" + id)))
	_npc.set("relation", clampi(int(_npc.get("relation")) + 15, 0, 100))
	Quest.set_relation(mod, _city_id(), int(_npc.get("npc_index")), int(_npc.get("relation")))
	_sub.text = "%s · %s" % [_trade_of(_npc), _relation_text()]
	_update_give()
	contract_done.emit(q)
	quest_changed.emit()
	if coins > 0:
		_log.append_text("[i][color=#9a9080]%s[/color][/i]\n" % _esc(mod.tr_key("pax_rpg_contract_close_hint")))
