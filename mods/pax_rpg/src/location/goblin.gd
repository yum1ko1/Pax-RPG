extends CharacterBody3D
## Гоблин — враг-дуэлянт. Заметив героя, подходит на дистанцию поединка и кружит вокруг него лицом к нему, выжидая
## окно; потом короткий выпад: вспышка-предупреждение и рубящий удар. После удара — миг уязвимости и отход.
## Концентрация — выдержка бойца (ДИЗДОК — бой): от 100 к 0, тратится своим ударом, блоком и пропущенным ударом,
## парирование его удара — сразу 0; восстанавливается, пока не бьёт и не блокирует (на расстоянии быстрее, раненый —
## медленнее). На 0 — слом: падает на колени, окно Кровожадной атаки героя (рядовой гибнет). Гибель — тело
## рассыпается маной. Атакует одновременно только один гоблин (жетон атаки). Модель и клипы — models/goblin/ (Meshy).
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")
const BodyFx := preload("res://mods/pax_rpg/src/location/body_fx.gd")

const DIR := "models/goblin/"
const CLIPS := {"idle": "idle.glb", "walk": "walk.glb", "run": "run.glb", "attack": "attack.glb", "hit": "hit.glb",
	"combat_idle": "combat_idle.glb", "strafe_l": "strafe_l.glb", "strafe_r": "strafe_r.glb", "back": "back.glb",
	"deflected": "deflected.glb", "knockdown": "knockdown.glb", "getup": "getup.glb", "stagger": "stagger.glb",
	"parry": "parry.glb", "block": "block.glb"}
const LOOPED := ["idle", "walk", "run", "combat_idle", "strafe_l", "strafe_r", "back"]
const FALLBACK := {"combat_idle": "idle", "strafe_l": "walk", "strafe_r": "walk", "back": "walk", "deflected": "hit",
	"knockdown": "hit", "getup": "combat_idle", "stagger": "hit", "parry": "deflected", "block": "hit"}

const MAX_HP := 60.0
const MAX_CONC := 100.0
const CONC_ATTACK := 10.0     # свой удар (замах) — усталость
const CONC_REGEN := 12.0      # в секунду, пока не бьёт и не блокирует (дальше 5 м — ×1.5; раненый — медленнее)
const CONC_IDLE := 1.2        # с без трат — и концентрация пошла вверх
const RISE_CONC := 0.4        # доля концентрации после слома, если Кровожадной атаки не было
const KNEEL_AT := 0.45        # доля клипа слома: на коленях — тут клип замирает до конца окна
const DETECT := 14.0          # м, замечает героя
const LOSE := 24.0            # м, теряет
const CIRCLE_DIST := 4.0      # м, дистанция поединка — на ней кружит
const STRIKE_DIST := 2.3      # м, отсюда начинает замах (подходит крадучись, не бросается издалека)
const ATTACK_RANGE := 1.7     # м, с такой бьёт
const WALK_SPEED := 2.0
const RUN_SPEED := 4.2
const STRAFE_SPEED := 1.35
const LUNGE_SPEED := 1.6      # шаг в замахе
const STALK_SPEED := 1.4      # подкрадывается
const ATTACK_HIT_AT := 0.5    # доля клипа атаки — миг удара
const ATTACK_SPEED := 1.5
const DAMAGE := 12.0
## Три атаки (план боя, этап 2): у каждой свой замах, ритм и предупреждение — парирование снова требует внимания.
##   quick — тычок: короткий замах, быстрый удар, слабее; блик белый;
##   heavy — рубящий с задержкой: длинный замах, удар медленнее (не поймать «по привычке»), сильнее, блок дороже;
##          вспышка оранжевая;
##   leap — прыжок: неблокируемый и непарируемый (危 над головой и свой звук), от него только уворот.
const GOB_ATTACKS := {
	"quick": {"windup": 0.3, "speed": 1.25, "dmg": 0.75, "kind": "", "col": Color(0.75, 0.9, 1.0)},
	"heavy": {"windup": 0.7, "speed": 0.75, "dmg": 1.35, "kind": "heavy", "col": Color(1.0, 0.5, 0.1)},
	"leap": {"windup": 0.6, "speed": 1.0, "dmg": 1.5, "kind": "perilous", "col": Color(1.0, 0.1, 0.08)},
}
const LEAP_UP := 4.2           # м/с вверх в начале прыжка
const LEAP_FWD := 5.5          # м/с вперёд, пока не ударил
const HURT_TIME := 0.45
const DEFLECTED_TIME := 0.9
const BROKEN_TIME := 2.6      # с на коленях после слома — окно Кровожадной атаки
const RECOVER_TIME := 0.6
const RESPAWN := 9.0           # с до нового гоблина (тело лежит BODY_STAY, потом уходит в землю)
const BODY_STAY := 4.0
const KNOCKBACK := 2.0        # м/с, отшатывается от удара комбо — следующий удар ещё достаёт
const KNOCK_FLY := 7.5        # м/с, отлетает от финального удара комбо
const KNOCK_UP := 4.0
const DOWN_TIME := 0.7        # с, лежит после падения
const GETUP_SKIP := 0.27      # с начала клипа вставания (Meshy начинает стоя) — с кадра, где лежит на боку
const STUN_MAX := 1.3         # с, дольше под ударами не стоит — уходит
const GRAVITY := 20.0
const FLINCH := 0.16          # рад: наклон корпуса от удара (лёгкий удар, гоблин 45 кг); тяжелее — меньше
const MANA := Color(0.75, 0.45, 1.0)

static var _attacker: Node = null   # у кого жетон атаки

var mod: PaxMod
var max_hp := MAX_HP
var conc_max := MAX_CONC
var hit_conc := 1.4                  # пропущенный удар героя → столько концентрации за единицу урона
var veteran := false                 # ветеран арены (4-й этап): блок чаще, парирует удары героя
var phase := 0                       # сломов с Кровожадной атакой пережито (босс: три — три фазы)
static var hero_broken := false      # location.gd: концентрация героя на нуле — враги спешат наказать
var mass := 45.0                    # кг: сколько уносит удар (location.gd → _mass_hit, weight.gd)
var boss := false                   # мини-босс: своя полоса внизу экрана (HUD), а не карточка врага
var title_key := ""                 # титул под именем босса
var display_key := "pax_rpg_goblin"   # имя в HUD (ключ перевода)
var hp := max_hp
var conc := MAX_CONC
var _conc_idle := 0.0
var dead := false
var respawns := true
# характер — у каждого свой (setup): как часто ставит блок, связывает удары в серию, как терпелив
var _guard_chance := 0.25
var _combo_chance := 0.4
var _atk_kind := ""            # атака гоблина (GOB_ATTACKS); "" — прежний один удар (так у наследников — орка)
var _warn: Label3D             # 危 над головой — перед прыжком
var _warn_snd: AudioStreamPlayer3D
var _combo_n := 0
var _riposte := false          # на арене — нет: павший уходит насовсем
var _target: Node3D
var _hero_attacking: Callable  # () -> bool — герой сейчас бьёт (повод отскочить)
var _hero_blocking: Callable   # () -> bool — герой в блоке (повод подождать или обмануть)
var _on_hit: Callable          # on_hit.call(damage, self) — удар по герою (там решают: блок, парирование, урон)
var _spawn := Vector3.ZERO
var _model: Node3D
var _model_y := 0.0
var _anim: AnimationPlayer
var _mark: MeshInstance3D       # красная метка добивания
var _state := "idle"
var _state_t := 0.0
var _struck := false
var _wait := 2.0               # с кружения до следующего выпада
var _circle_dir := 1.0         # +1 — вправо от героя, −1 — влево
var _switch_t := 2.0
var _since_hit := 99.0
var _lethal := false
var _last_away := Vector3.FORWARD   # куда отбросил последний удар — туда и падает тело
var _slice_n := Vector3.ZERO         # иай: плоскость разреза (нормаль в мире) — тело рубится пополам
var _layer_saved := -1
var voiced := true                   # свои звуки гоблина (орк-чемпион — без них)
var _bark_t := randf_range(4.0, 9.0)  # с до следующего боевого выкрика
var _hurt_cd := 0.0
var _voice: AudioStreamPlayer
var flinch_pitch := true             # наклон вперёд/назад от удара (орк сам ведёт наклон корпуса — у него только вбок)
var _fl := Vector2.ZERO              # наклон от удара: x — вдоль лица (рад), y — вбок
var _fl_on := Vector2.ZERO           # сколько из него уже наложено на модель
var _flash_t := 0.0
var _flashed: Array = []
static var _flash_mat: StandardMaterial3D
static var _streams := {}


## Голос гоблина: kind "hurt" (урон) или "bark" (выкрик в бою). Громкость — по расстоянию до героя (у вида локации
## нет своего слушателя 3D-звука, поэтому без AudioStreamPlayer3D).
var _whooshed := false
var _whoosh: AudioStreamPlayer3D


## Свист взмаха оружия (sounds/foe_swing_1.mp3, временный — общий для врагов).
func _play_whoosh() -> void:
	if mod == null:
		return
	if _whoosh == null:
		var st: AudioStream = mod.sound("sounds/foe_swing_1.mp3")
		if st == null:
			return
		_whoosh = AudioStreamPlayer3D.new()
		_whoosh.stream = st
		_whoosh.bus = "PaxRpgSfx"
		_whoosh.unit_size = 8.0
		_whoosh.position = Vector3(0, 1.0, 0)
		add_child(_whoosh)
	_whoosh.pitch_scale = randf_range(0.92, 1.08)
	_whoosh.play()


func _say(kind: String, n: int) -> void:
	if not voiced or mod == null:
		return
	var path := "sounds/goblin_%s_%d.mp3" % [kind, randi_range(1, n)]
	if not _streams.has(path):
		_streams[path] = mod.sound(path)
	var st: AudioStream = _streams[path]
	if st == null:
		return
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		_voice.bus = "PaxRpgSfx"
		add_child(_voice)
	var d := global_position.distance_to(_target.global_position) if is_instance_valid(_target) else 0.0
	var k := clampf(1.0 - d / 26.0, 0.0, 1.0)
	if k <= 0.02:
		return
	_voice.stream = st
	_voice.volume_db = linear_to_db(k) - (2.0 if kind == "bark" else 0.0)
	_voice.pitch_scale = randf_range(0.92, 1.1)
	_voice.play()


## Подбросить (шипы «Разлома»): скорость v; падает сам — гравитация капсулы.
func launch(v: Vector3) -> void:
	if dead:
		return
	velocity = v


## Иай: следующая гибель — разрубить по плоскости с нормалью n (location.gd → _iai_cut).
func mark_slice(n: Vector3) -> void:
	_slice_n = n.normalized()
var _stun_t := 0.0             # с под ударами подряд
var _swing_seen := false      # замах героя уже замечен (уходить или нет — решает один раз за удар)
var _feint := false            # этот подход — обманный: подойдёт и отскочит, не ударив


func setup(m: PaxMod, target: Node3D, on_hit: Callable, at: Vector3, hero_attacking := Callable(),
		hero_blocking := Callable()) -> void:
	mod = m
	_hero_blocking = hero_blocking
	_guard_chance = randf_range(0.12, 0.4)
	_combo_chance = randf_range(0.2, 0.55)
	_target = target
	_on_hit = on_hit
	_hero_attacking = hero_attacking
	_spawn = at
	name = "Goblin"
	position = at
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.1
	shape.shape = cap
	shape.position = Vector3(0.0, 0.55, 0.0)
	add_child(shape)
	_model = Assets.model(mod, DIR + "goblin_rigged.glb")
	if _model == null:
		mod.log_warning("Pax RPG: goblin model did not load — the goblin is a box")
		_model = MeshInstance3D.new()
		(_model as MeshInstance3D).mesh = BoxMesh.new()
		(_model as MeshInstance3D).position = Vector3(0.0, 0.55, 0.0)
	add_child(_model)
	Assets.track(DIR + "goblin_rigged.glb", _model)
	_model_y = _model.position.y
	_anim = _find_anim(_model)
	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if _anim != null:
		_add_clips()
	_mark = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.1, 0.1)
	mm.no_depth_test = true
	sm.material = mm
	_mark.mesh = sm
	_mark.position = Vector3(0.0, 0.8, 0.0)
	_mark.visible = false
	add_child(_mark)
	_update_bars()
	_set_state("idle")


## Клипы Meshy — отдельными glb. Берём их анимацию и кладём в плеер гоблина под своим именем; нет файла — запасной.
func _add_clips() -> void:
	var lib: AnimationLibrary = _anim.get_animation_library("") if _anim.has_animation_library("") else AnimationLibrary.new()
	for clip: String in CLIPS:
		var src := Assets.model(mod, DIR + CLIPS[clip])
		if src == null:
			continue
		var from := _find_anim(src)
		if from != null and from.get_animation_list().size() > 0:
			var anim: Animation = (from.get_animation(from.get_animation_list()[0]).duplicate() as Animation)
			anim.loop_mode = Animation.LOOP_LINEAR if clip in LOOPED else Animation.LOOP_NONE
			lib.add_animation(clip, anim)
		src.free()
	if not _anim.has_animation_library(""):
		_anim.add_animation_library("", lib)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


func is_alive() -> bool:
	return not dead


## Концентрация на нуле — окно Кровожадной атаки (на коленях).
func can_deathblow() -> bool:
	return _state == "broken" and not dead


## Концентрация ниже трети: удары медленнее, блок реже.
func low_conc() -> bool:
	return conc < conc_max / 3.0


## Трата концентрации (удар, блок, пропущенный удар). Дошла до 0 — слом.
func spend(a: float) -> void:
	if dead or a <= 0.0:
		return
	conc = maxf(0.0, conc - a)
	_conc_idle = 0.0
	if conc <= 0.0 and _state != "broken":
		_lethal = false
		_release_token()
		_set_state("broken")


## Полосы здоровья и концентрации — в HUD справа (location.gd читает hp / conc), над головой ничего.
func _update_bars() -> void:
	pass


## В бою с героем (для HUD): заметил его и не мёртв.
func in_combat() -> bool:
	return not dead and _state != "idle"


# ---------- что с ним делают ----------

## Удар героя. Ответ — что вышло: "hit" — ранен, "guard" — принял на клинок (урона нет, своя концентрация
## потрачена немного — герою дороже, location.gd), "parry" — ветеран отбил (концентрация героя в 0), "broken" —
## своя концентрация кончилась (слом), "dead".
func take_damage(amount: float, from: Vector3, knock := false) -> String:
	if dead:
		return "dead"
	if _state == "broken":                         # на коленях: удары всё равно ранят
		hp = maxf(0.0, hp - amount)
		_update_bars()
		if hp <= 0.0:
			_lethal = true
			_die()
			return "dead"
		return "hit"
	var face := global_position.direction_to(from)
	var fwd := _model.global_transform.basis.z if _model != null else -global_transform.basis.z   # модель смотрит по +Z
	var facing := fwd.dot(Vector3(face.x, 0.0, face.z).normalized()) > 0.3
	var ready := not knock and facing and _state in ["idle", "circle", "stalk", "evade", "recover", "guard", "approach"]
	if ready and veteran and randf() < (0.35 if _state == "guard" else 0.22):
		_since_hit = 0.0                                    # ветеран: отбил — герой открыт
		_burst(global_position + Vector3(0.0, 1.0, 0.0) + face * 0.4, face, Color(1.0, 0.85, 0.4), 30, 4.5, 6.0, 0.3,
			0.035, true)
		_riposte = true
		_set_state("parry")
		return "parry"
	var gc := _guard_chance * (0.5 if low_conc() else 1.0)
	if ready and randf() < gc:
		_since_hit = 0.0
		_burst(global_position + Vector3(0.0, 1.0, 0.0) + face * 0.4, face, Color(1.0, 0.75, 0.35), 14, 3.0, 6.0,
			0.25, 0.03, true)
		spend(amount * 0.4)                                 # принял на клинок: урона нет, выдержка чуть тратится
		if _state != "broken":
			_riposte = randf() < 0.5                         # после блока — иногда сразу ответный удар
			_set_state("guard")
		_update_bars()
		return "broken" if _state == "broken" else "guard"
	hp = maxf(0.0, hp - amount)
	_since_hit = 0.0
	if _hurt_cd <= 0.0:
		_hurt_cd = 0.3
		_say("hurt", 2)
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_last_away = away
	_burst(global_position + Vector3(0.0, 0.75, 0.0) - away * 0.2, away, Color(0.55, 0.02, 0.03), 36, 3.5, 9.0, 0.5,
		0.06)
	if hp <= 0.0:
		_lethal = true
		velocity = away * KNOCK_FLY * (1.0 if knock else 0.5) + Vector3(0.0, KNOCK_UP * (1.0 if knock else 0.5), 0.0)
		_die()
		_update_bars()
		return "dead"
	spend(amount * hit_conc)
	if _state == "broken":
		velocity = away * KNOCKBACK
		_update_bars()
		return "broken"
	if knock:
		velocity = away * KNOCK_FLY + Vector3(0.0, KNOCK_UP, 0.0)   # финальный удар — отлетает и падает навзничь
		_face(-away, 1.0)
		_set_state("knockdown")
	elif _state in ["knockdown", "down", "getup"]:
		pass                                         # лежит или встаёт — только урон
	else:
		velocity = away * KNOCKBACK + Vector3(0.0, 1.0, 0.0)
		var chain := _state == "hurt"
		var t := _stun_t if chain else 0.0
		_set_state("hurt")
		_stun_t = t
	_update_bars()
	return "hit"


## Герой парировал его удар: концентрация сразу 0 — слом, отбрасывает в сторону.
func deflected(from: Vector3) -> void:
	if dead:
		return
	var away := global_position - from
	away.y = 0.0
	velocity = (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 3.0
	spend(conc + 1.0)
	_update_bars()


## Удар принят героем в блок: атакующий тратит больше блокирующего (долбить в блок невыгодно).
func on_blocked(dmg: float, heavy: bool) -> void:
	spend(dmg * (0.9 if heavy else 0.7))
	_update_bars()


## Кровожадная атака героя (концентрация на нуле): рядовой — гибнет.
func bloodthirsty() -> void:
	if dead:
		return
	cine = false
	_lethal = true
	_die()


## Совместимость (иай, старые вызовы): добить — как Кровожадная атака.
func deathblow() -> void:
	bloodthirsty()


func _die() -> void:
	_fl = Vector2.ZERO
	_flinch_apply()
	_flash_off()
	dead = true
	_release_token()
	_mark.visible = false
	_set_state("dead")
	# тело не исчезает: лежит, потом медленно уходит в землю; мана улетает в шкалу опыта (location.gd)
	_burst(global_position + Vector3(0.0, 0.5, 0.0), Vector3.UP, MANA, 24, 0.8, -0.6, 0.9, 0.05, true)
	blood_decal(get_parent(), global_position)
	_layer_saved = collision_layer
	collision_layer = 0                                  # павший никому не мешает (и рэгдолл о него не бьётся)
	if _model != null:
		var cut := false
		if _slice_n != Vector3.ZERO:                     # иай: пополам, половинки падают и тают в ману
			cut = BodyFx.slice(mod, _model, get_parent(), _slice_n, global_position + Vector3(0.0, 0.75, 0.0),
				_last_away * 1.5, 2.2)
		if cut:
			_model.visible = false
		else:
			# падение — клип смерти модели (knockdown / Death); тело отлетает от удара по физике капсулы, лежит и
			# плавно тает в ману. Рэгдолл (BodyFx.ragdoll) выключен: на скелетах Meshy с масштабом 0.01 тела улетали.
			velocity = _last_away * 2.5 + Vector3(0.0, 2.0, 0.0)
			var t := create_tween()
			t.tween_interval(BODY_STAY * 0.55)
			t.tween_callback(func() -> void:
				BodyFx.dissolve(mod, _model, 3.0, func() -> void: _model.visible = false))
	if respawns:
		get_tree().create_timer(RESPAWN).timeout.connect(_respawn)
	else:
		get_tree().create_timer(BODY_STAY + 3.5).timeout.connect(queue_free)


static var _blood_tex: ImageTexture


## Лужа крови под павшим (декаль на земле): растекается, лежит, потом тает. Рисунок — свой, из пятен шума.
## Статическая — её же зовёт прогрев шейдеров локации (location.gd → _warmup).
static func blood_decal(parent: Node, at: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _blood_tex == null:
		_blood_tex = ImageTexture.create_from_image(_blood_image())
	var d := Decal.new()
	d.texture_albedo = _blood_tex
	d.size = Vector3(1.9, 1.4, 1.9)
	d.modulate = Color(0.32, 0.03, 0.04, 0.0)
	d.albedo_mix = 0.92
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	parent.add_child(d)
	d.global_position = at + Vector3(0.0, 0.2, 0.0)
	d.rotation.y = randf() * TAU
	d.scale = Vector3(0.4, 1.0, 0.4)
	var tw := d.create_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(d, "scale", Vector3.ONE, 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(40.0)
	tw.tween_property(d, "modulate:a", 0.0, 6.0)
	tw.tween_callback(d.queue_free)


static func _blood_image() -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.045
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var drops: Array = []
	for i: int in 9:                                  # брызги вокруг лужи
		var a := rng.randf() * TAU
		drops.append([Vector2(cos(a), sin(a)) * rng.randf_range(0.55, 0.85), rng.randf_range(0.03, 0.07)])
	for y: int in n:
		for x: int in n:
			var p := Vector2(x, y) / float(n) * 2.0 - Vector2.ONE
			var r := p.length() + noise.get_noise_2d(x, y) * 0.35
			var a := 1.0 - smoothstep(0.38, 0.5, r)
			for dr: Array in drops:
				a = maxf(a, 1.0 - smoothstep(float(dr[1]) * 0.6, float(dr[1]), p.distance_to(dr[0])))
			var dark := 0.7 + 0.3 * (noise.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(dark, dark, dark, a))
	img.generate_mipmaps()
	return img


func _respawn() -> void:
	hp = max_hp
	conc = conc_max
	phase = 0
	dead = false
	_lethal = false
	if _model != null:
		BodyFx.stop_ragdoll(BodyFx.find_skeleton(_model))
		BodyFx.clear(_model)
		_model.scale = Vector3.ONE
		_model.position.y = _model_y
		_model.visible = true
	if _anim != null:
		_anim.active = true
	if _layer_saved >= 0:
		collision_layer = _layer_saved
	_slice_n = Vector3.ZERO
	position = _spawn
	velocity = Vector3.ZERO
	_update_bars()
	_set_state("idle")


## Искры / капли: amount частиц из at в сторону dir; gravity < 0 — летят вверх; glow — светятся (мана).
func _burst(at: Vector3, dir: Vector3, color: Color, amount: int, speed: float, gravity: float, life: float,
		size: float, glow := false) -> void:
	var p := CPUParticles3D.new()
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = 55.0 if not glow else 80.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.damping_min = 0.5
	p.damping_max = 2.0
	if glow:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
	if _burst_curve == null:
		_burst_curve = Curve.new()
		_burst_curve.add_point(Vector2(0.0, 1.0))
		_burst_curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = _burst_curve
	p.mesh = _burst_mesh(color, size, glow)
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## Сетки и материалы брызг — общие на одинаковые (цвет, размер, свечение): раньше каждый удар создавал свою сферу и
## материал — новые ресурсы на сервере рендера в разгар боя. Видов немного (цвета в коде), кэш не растёт.
static var _burst_curve: Curve
static var _burst_meshes := {}


static func _burst_mesh(color: Color, size: float, glow: bool) -> SphereMesh:
	var key := "%s|%s|%s" % [color, size, glow]
	if _burst_meshes.has(key):
		return _burst_meshes[key]
	var q := SphereMesh.new()
	q.radius = size
	q.height = size * 2.0
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	q.material = m
	_burst_meshes[key] = q
	return q


## Предупреждение перед выпадом: вспышка над оружием (как красный иероглиф опасности в Sekiro — здесь мана).
## Цвет — по атаке: белый блик — обычный удар, оранжевый — тяжёлый, алый с 危 и звуком — неблокируемый прыжок.
func _telegraph() -> void:
	var a: Dictionary = GOB_ATTACKS.get(_atk_kind, {})
	var col: Color = a.get("col", Color(1.0, 0.35, 0.2))
	var n := {"quick": 8, "heavy": 20, "leap": 24}.get(_atk_kind, 14) as int
	_burst(global_position + Vector3(0.0, 1.25, 0.0), Vector3.UP, col, n, 0.6, 0.0, 0.45, 0.05, true)
	if _atk_kind == "leap":
		_warn_show(true)
		if _warn_snd == null and mod != null:
			var st: AudioStream = mod.sound("sounds/iai_tsuba.wav")    # короткий звон гарды — «опасно», не звук удара
			if st != null:
				_warn_snd = AudioStreamPlayer3D.new()
				_warn_snd.stream = st
				_warn_snd.bus = "PaxRpgSfx"
				_warn_snd.unit_size = 12.0
				_warn_snd.pitch_scale = 0.8
				_warn_snd.position = Vector3(0, 1.6, 0)
				add_child(_warn_snd)
		if _warn_snd != null:
			_warn_snd.play()


func _warn_show(on: bool) -> void:
	if not on and _warn == null:
		return
	if _warn == null:
		_warn = Label3D.new()
		_warn.text = "危"
		_warn.font_size = 120
		_warn.modulate = Color(1.0, 0.15, 0.1)
		_warn.outline_size = 20
		_warn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_warn.no_depth_test = true
		_warn.position = Vector3(0.0, 2.3, 0.0)
		add_child(_warn)
	_warn.visible = on


## Выбрать атаку перед замахом. Сломленного героя — быстрым ударом; ветеран прыгает чаще.
func _pick_attack() -> void:
	if hero_broken:
		_atk_kind = "quick"
		return
	var leap := 0.25 if veteran else 0.15
	var r := randf()
	_atk_kind = "leap" if r < leap else ("heavy" if r < leap + 0.4 else "quick")


func _atk_speed() -> float:
	return ATTACK_SPEED * float((GOB_ATTACKS.get(_atk_kind, {}) as Dictionary).get("speed", 1.0))


# ---------- состояния ----------

func _take_token() -> bool:
	if _attacker == null or not is_instance_valid(_attacker) or _attacker == self:
		_attacker = self
		return true
	return false


func _release_token() -> void:
	if _attacker == self:
		_attacker = null


func _set_state(s: String) -> void:
	_state = s
	_state_t = 0.0
	_struck = false
	_whooshed = false
	if _anim != null:
		_anim.speed_scale = 1.0
	if s in ["hurt", "deflected", "broken", "dead", "recover", "circle", "idle", "evade", "knockdown", "down", "getup"]:
		if s != "recover":
			_release_token()
	_mark.visible = s == "broken"
	if _warn != null and _warn.visible and not (s in ["windup", "attack"] and _atk_kind == "leap"):
		_warn_show(false)
	match s:
		"idle":
			_play("idle")
		"circle", "recover":
			_play("combat_idle")
			if s == "circle":
				_wait = randf_range(1.2, 3.2)
		"windup":
			_telegraph()
		"attack":
			_play("attack", true)
			if _anim != null:
				_anim.speed_scale = _atk_speed() * (0.85 if low_conc() else 1.0)   # устал — бьёт медленнее
			if _atk_kind == "leap" and is_on_floor():
				velocity.y = LEAP_UP                        # прыжок: подлетает и рушится сверху
		"hurt":
			_play("hit", true)
		"deflected":
			_play("deflected", true)
		"knockdown":
			_play("knockdown", true)
		"getup":
			_play("getup", true, 0.35)
			if _anim != null and _clip("getup") == "getup":
				_anim.seek(GETUP_SKIP, true)
		"broken":
			_play("stagger", true, 0.1)                 # шатается и падает на колени (stagger.glb)
		"rise":
			if _anim != null:
				_anim.play()                            # с колен — дальше по клипу слома
				_anim.speed_scale = 1.7
		"guard":
			_play("block", true, 0.08)
		"parry":
			_play("parry", true, 0.06)
		"dead":
			_play("knockdown", true)                  # падает и остаётся лежать (клип не зациклен)


## Сменить состояние, не трогая клип (лежит — поза падения остаётся).
func _set_state_keep(s: String) -> void:
	_state = s
	_state_t = 0.0


func _clip(name_: String) -> String:
	if _anim == null:
		return ""
	if _anim.has_animation(name_):
		return name_
	return str(FALLBACK.get(name_, "idle"))


func _play(clip: String, restart := false, blend := 0.2) -> void:
	var c := _clip(clip)
	if c == "" or not _anim.has_animation(c):
		return
	if restart or _anim.current_animation != c:
		_anim.play(c, blend)


## Замирание на миг попадания героя (location.gd, вместе с героем): поза и движение стоят — удар «вязнет» в теле.
var _hitstop := 0.0


## Кат-сцена (ультимейт копья, spear_ult.gd): врага ведут по пути, своя физика и решения стоят.
var cine := false


func cine_state(s: String) -> void:
	if not dead:
		_set_state(s)


## Анимация в кат-сцене: hurt — получил удар, knock — отброшен, fall — падает и лежит, getup — встаёт.
func cine_anim(kind: String) -> void:
	if dead:
		return
	match kind:
		"hurt":
			_set_state_keep("hurt")
			_play("hit", true, 0.05)
		"knock":
			_set_state_keep("knockdown")
			_play("knockdown", true, 0.05)
		"fall":
			_set_state_keep("knockdown")
			_play("knockdown", true, 0.08)
		"getup":
			_set_state("getup")


## Конец кат-сцены: своя физика и решения снова его; после удара в спину — отлетает и падает (дальше встаёт сам).
func cine_release(v: Vector3) -> void:
	cine = false
	_hitstop = 0.0
	if _anim != null:
		_anim.active = true
	conc = maxf(conc, conc_max * 0.25)                  # не на нуле после сцены — иначе стоит и ждёт добивания
	if dead:
		return
	velocity = v
	_set_state("knockdown")


## Вздрог от удара: корпус наклоняется туда, куда уносит удар (away — в мире), и в замирании так и стоит, потом
## выпрямляется. power — вес удара (location.gd → _mass_hit); тяжёлого бойца качает меньше.
func flinch(away: Vector3, power: float) -> void:
	if _model == null or dead:
		return
	var f := _model.global_transform.basis.z
	var r := _model.global_transform.basis.x
	f.y = 0.0
	r.y = 0.0
	var k := FLINCH * clampf(power, 0.5, 2.0) * clampf(45.0 / maxf(mass, 1.0), 0.35, 1.0)
	_fl = Vector2(away.dot(f.normalized()) if flinch_pitch else 0.0, -away.dot(r.normalized())) * k
	_flinch_apply()


func _flinch_apply() -> void:
	if _model == null:
		return
	var d := _fl - _fl_on                         # прибавкой: свои повороты модели (лицо, наклон орка) не трогаем
	_model.rotation.x += d.x
	_model.rotation.z += d.y
	_fl_on = _fl


## Вспышка попадания: тело на миг светлеет (наложенный материал на все меши модели).
func hit_flash(t: float) -> void:
	if _model == null or dead or t <= 0.0:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.albedo_color = Color(1.0, 0.92, 0.85, 0.55)
	if _flashed.is_empty():
		for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_overlay == null:
				(mi as MeshInstance3D).material_overlay = _flash_mat
				_flashed.append(mi)
	_flash_t = t


func _flash_tick(delta: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash_off()


func _flash_off() -> void:
	_flash_t = 0.0
	for mi: Variant in _flashed:
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == _flash_mat:
			(mi as MeshInstance3D).material_overlay = null
	_flashed.clear()


## Угроза для указателя у края экрана (location.gd): 0 — нет, 1 — замахивается, 2 — удар, который не парировать.
func threat() -> int:
	if dead:
		return 0
	if _state == "windup" or (_state == "attack" and not _struck):
		return 2 if _atk_kind == "leap" else 1
	return 0


func hitstop(t: float) -> void:
	_hitstop = maxf(_hitstop, t)
	if _anim != null:
		_anim.active = false


func _physics_process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("goblin._physics_process")
	_hurt_cd -= delta
	if in_combat() and not dead:                          # в бою время от времени выкрикивает
		_bark_t -= delta
		if _bark_t <= 0.0:
			_bark_t = randf_range(5.0, 11.0)
			_say("bark", 3)
	_flash_tick(delta)
	if _hitstop > 0.0:
		_hitstop -= delta
		if _hitstop <= 0.0 and _anim != null:
			_anim.active = true
		return
	if not dead:
		_fl = _fl.lerp(Vector2.ZERO, minf(1.0, delta * 9.0))   # корпус выпрямляется
		_flinch_apply()
	if cine:
		return
	var t0 := Time.get_ticks_usec()
	_phys(delta)
	Prof.add("гоблины", t0)


func _phys(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0                                 # на земле; подброс ударом (y > 0) не гасим
	if position.y < -20.0:
		_respawn()
	_state_t += delta
	_since_hit += delta
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_conc_idle += delta
	if _state not in ["attack", "windup", "guard", "parry", "broken", "rise", "dead"] and _conc_idle > CONC_IDLE \
			and conc < conc_max:                           # отдыхает: выдержка возвращается (раненый — медленнее)
		var kr := (1.5 if dist > 5.0 else 1.0) * (0.35 + 0.65 * hp / maxf(max_hp, 1.0))
		conc = minf(conc_max, conc + CONC_REGEN * kr * delta)
	var dir := to / maxf(dist, 0.001)
	var side := Vector3(-dir.z, 0.0, dir.x)          # вправо от гоблина, если он смотрит на героя
	var flat := Vector3.ZERO
	var swinging := _hero_attacking.is_valid() and bool(_hero_attacking.call())
	var new_swing := swinging and not _swing_seen
	match _state:
		"idle":
			if not dead and dist < DETECT:
				_set_state("approach")
		"approach":
			if dist > LOSE:
				_set_state("idle")
			elif dist <= CIRCLE_DIST + 0.8:
				_set_state("circle")
			else:
				var fast := dist > 9.0                   # издалека бежит, ближе — идёт, не врываясь
				flat = dir * (RUN_SPEED if fast else WALK_SPEED)
				_play("run" if fast else "walk")
				_face(dir, delta)
		"circle":
			_face(dir, delta)
			var hero_swing := _hero_attacking.is_valid() and bool(_hero_attacking.call())
			if dist > LOSE:
				_set_state("idle")
			elif dist > CIRCLE_DIST + 3.0:
				_set_state("approach")
			elif hero_swing and dist < 3.4 and not _swing_seen and randf() < 0.45:
				_set_state("evade")                      # герой замахнулся рядом — иногда успевает уйти вбок-назад
			else:
				_switch_t -= delta
				if _switch_t <= 0.0:
					_switch_t = randf_range(1.2, 2.8)
					_circle_dir = -_circle_dir
				var radial := 0.0
				if dist < CIRCLE_DIST - 0.7:
					radial = -1.0
				elif dist > CIRCLE_DIST + 0.7:
					radial = 1.0
				flat = side * _circle_dir * STRAFE_SPEED + dir * radial * WALK_SPEED * 0.5
				if radial < 0.0:
					_play("back")
				elif radial > 0.0:
					_play("walk")
				else:
					_play("strafe_r" if _circle_dir > 0.0 else "strafe_l")
				_wait -= delta
				if hero_broken and dist < 7.0:
					_wait = minf(_wait, 0.05)                # герой сломлен — не ждать, наказать
				if _wait <= 0.0:
					if not hero_broken and _hero_blocking.is_valid() and bool(_hero_blocking.call()) and randf() < 0.4:
						_wait = randf_range(0.8, 1.6)    # герой в блоке — подождать, пусть раскроется
					elif _take_token():
						_feint = randf() < 0.25 and not hero_broken
						_pick_attack()
						_set_state("stalk")
					else:
						_wait = randf_range(0.5, 1.2)
		"stalk":
			_face(dir, delta)
			flat = dir * (RUN_SPEED if hero_broken else STALK_SPEED)
			_play("walk")
			if _hero_attacking.is_valid() and bool(_hero_attacking.call()) and dist < 3.0 and not _swing_seen \
					and randf() < 0.45:
				_set_state("evade")
			elif dist <= STRIKE_DIST + (0.4 if _feint else 0.0):
				if _feint:
					velocity = -dir * 4.0 + side * _circle_dir * 1.5   # финт: дёрнулся вперёд — и отскок
					_set_state("evade")
				else:
					_set_state("windup")
			elif _state_t > 3.0:
				_set_state("circle")
		"guard":
			_face(dir, delta * 2.0)
			_damp(delta)
			if _state_t > 0.35:
				if _riposte and dist <= STRIKE_DIST + 0.6:
					_riposte = false
					_atk_kind = "quick"
					_attack_begin()                      # ответ без замаха — надо ловить
				else:
					_set_state("circle")
		"parry":                                         # отбил удар героя — сразу ответ (герой открыт)
			_face(dir, delta * 2.0)
			_damp(delta)
			if _state_t > 0.32:
				_riposte = false
				if dist <= ATTACK_RANGE + 1.4:
					_atk_kind = "quick"
					_attack_begin()
				else:
					_set_state("circle")
		"rise":                                          # встаёт с колен (клип слома дальше), потом — снова в бой
			_damp(delta)
			_face(dir, delta * 0.5)
			if _state_t >= maxf(0.4, (_clip_len("stagger") * (1.0 - KNEEL_AT)) / 1.7 * 0.85) or _clip("stagger") != "stagger":
				_set_state("circle")
		"evade":
			_face(dir, delta)
			flat = -dir * WALK_SPEED * 1.2 + side * _circle_dir * STRAFE_SPEED
			_play("back")
			if _state_t > 0.7:
				_set_state("circle")
		"windup":
			_face(dir, delta)
			flat = dir * LUNGE_SPEED
			_play("combat_idle")
			if _state_t >= _f_windup():
				_attack_begin()
		"attack":
			_face(dir, delta * 0.4)
			var hit_at := _clip_len("attack") / _atk_speed() * ATTACK_HIT_AT
			if _atk_kind == "leap" and _state_t < hit_at and dist > 0.9:
				flat = dir * LEAP_FWD                    # летит на героя
			elif _state_t < hit_at * 0.7 and dist > 1.2:
				flat = dir * 2.0                         # шаг с ударом
			if not _whooshed and _state_t >= hit_at - 0.12:   # свист оружия — чуть до удара
				_whooshed = true
				_play_whoosh()
			if not _struck and _state_t >= hit_at:
				_struck = true
				if dist <= ATTACK_RANGE + 0.5 and _on_hit.is_valid():
					var a: Dictionary = GOB_ATTACKS.get(_atk_kind, {})
					_on_hit.call(DAMAGE * float(a.get("dmg", 1.0)), self, str(a.get("kind", "")))
			if _state == "attack" and _state_t >= _clip_len("attack") / _atk_speed() * 0.85:
				if _combo_n < 2 and _atk_kind != "leap" and dist <= ATTACK_RANGE + 1.0 and randf() < _combo_chance:
					_combo_n += 1                        # серия: следующий удар сразу, без отката — быстрый
					if _atk_kind != "":
						_atk_kind = "quick"
					_attack_begin()
				else:
					_combo_n = 0
					_set_state("recover")
		"recover":
			_face(dir, delta)
			if _state_t > RECOVER_TIME:
				_release_token()
				flat = -dir * WALK_SPEED
				_play("back")
				if _state_t > RECOVER_TIME + 0.8:
					_set_state("circle")
		"hurt":
			_damp(delta)
			_face(dir, delta)
			_stun_t += delta
			# пока герой бьёт комбо — стоит под ударами (не дольше STUN_MAX), потом отступает
			if _state_t >= HURT_TIME and (not swinging or _stun_t >= STUN_MAX):
				_set_state("evade")
		"knockdown":
			if is_on_floor() and _state_t > 0.25:
				_damp(delta * 2.0)
			if _state_t >= maxf(_clip_len("knockdown") * 0.9, 0.8) and is_on_floor():
				if _anim != null:
					_anim.pause()                        # лежит на спине
				_set_state_keep("down")
		"down":
			_damp(delta * 2.0)
			if _state_t >= DOWN_TIME:
				_set_state("getup")
		"getup":
			_damp(delta * 2.0)
			_face(dir, delta * 0.5)
			if _state_t >= (_clip_len("getup") - GETUP_SKIP) * 0.92:
				_set_state("evade")                      # встал — отходит и снова кружит
		"deflected":
			_damp(delta)
			if _state_t >= DEFLECTED_TIME:
				_set_state("circle")
		"broken":
			_damp(delta)
			if _anim != null and _anim.is_playing() and _anim.current_animation != "" \
					and _anim.current_animation_position >= _anim.current_animation_length * KNEEL_AT:
				_anim.pause()                            # на коленях — окно Кровожадной атаки
			if _state_t >= BROKEN_TIME:
				if _lethal:
					_die()
				else:
					conc = conc_max * RISE_CONC          # окно упущено: выдержка частично вернулась
					_update_bars()
					_set_state("rise")
		"dead":                                          # отлёт от удара гаснет трением о землю
			velocity.x = move_toward(velocity.x, 0.0, delta * 7.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 7.0)
	if new_swing:
		_swing_seen = true
	elif not swinging:
		_swing_seen = false
	if _state in ["approach", "circle", "stalk", "evade", "windup", "attack", "recover", "idle"]:
		velocity.x = lerpf(velocity.x, flat.x, minf(1.0, delta * 10.0))
		velocity.z = lerpf(velocity.z, flat.z, minf(1.0, delta * 10.0))
	move_and_slide()


## Замах — короткая пауза с предупреждением (у слабых врагов короче).
func _f_windup() -> float:
	if hero_broken:
		return 0.25
	return float((GOB_ATTACKS.get(_atk_kind, {}) as Dictionary).get("windup", 0.45))


## Начать удар: сам замах тратит концентрацию (усталость); на нуле — слом вместо удара.
func _attack_begin() -> void:
	spend(CONC_ATTACK)
	if _state != "broken" and not dead:
		_set_state("attack")


func _damp(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, minf(1.0, delta * 6.0))
	velocity.z = lerpf(velocity.z, 0.0, minf(1.0, delta * 6.0))


func _clip_len(clip: String) -> float:
	var c := _clip(clip)
	if c == "" or not _anim.has_animation(c):
		return 1.0
	return _anim.get_animation(c).length


## Модель смотрит вперёд по +Z (у гоблина Meshy ставит вперёд +Z).
func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, want, minf(1.0, delta * 10.0))
