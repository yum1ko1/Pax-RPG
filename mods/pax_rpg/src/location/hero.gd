extends RefCounted
## Герой локации: модель (config/hero.json → models/*.glb) и её состояние — меч на спине, в руке или волочится
## по земле в беге, доставание и убирание, комбо из трёх тяжёлых ударов, прыжок, увороты; надетые вещи (плащ-ткань).
## Удары ведёт root motion (смещение таза вынуто при сборке — pax_rpg/dev/blender/knight/*.py → *_anim.json):
## инерция меча тянет персонажа. Удар без продолжения кончается сразу после взмаха и плавно уходит в стойку.
## location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.
const FootIK := preload("res://mods/pax_rpg/src/location/foot_ik.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")
const AnimCtl := preload("res://mods/pax_rpg/src/location/anim_ctl.gd")

const ATTACKS := ["Attack1", "Attack2", "Attack3"]
# приёмы комбо (location.gd выбирает по вводу): «Выпад» — захват + вперёд + ЛКМ, «Подброс» — захват + назад + ЛКМ,
# «Пауза» — ЛКМ, ЛКМ, пауза, ЛКМ: вместо третьего удара — тяжёлый сверху. Клипы — из имеющихся (SPECIAL_CLIPS).
const SPECIALS := ["Lunge", "Launcher", "PauseFinisher"]
const SPECIAL_CLIPS := {"Lunge": ["Attack1", 0.3], "Launcher": ["Kick", 0.2], "PauseFinisher": ["HeavySlash", 0.1]}
const LOOPS := ["Idle", "IdleArmed", "Walk", "Run", "RunArmed", "WalkArmed", "GuardStrafeL", "GuardStrafeR",
	"GuardBack", "StrafeL", "StrafeR", "WalkBack", "Block", "BlockWalkF", "BlockWalkB", "BlockWalkL", "BlockWalkR", "CombatIdle"]
const ONCE := ["UltCrush", "SwordTrick", "Draw", "Sheathe", "DrawWalk", "SheatheWalk", "Jump", "JumpArmed", "JumpLand", "JumpLandArmed", "BlockHit",
	"Attack1", "Attack2", "Attack3", "Dodge",
	"DodgeArmed", "Hurt", "Parry", "Deathblow", "Knocked", "GetUp", "Stagger", "Bloodthirsty"]
const SOFT := ["Hurt", "Parry", "BlockHit"]        # реакции: не отнимают управление, шаг или любое действие их обрывают
const ON_THE_GO := ["DrawWalk", "SheatheWalk"]   # меч достают и убирают на ходу — ноги шагают, управление не забрано

var cfg: Dictionary = {}
var meta: Dictionary = {}           # *_anim.json: root_motion, sword_switch, impact, cape
var model: Node3D
var anim: AnimCtl                   # AnimationTree с интерфейсом AnimationPlayer (anim_ctl.gd)
var lock_on := false                # захват цели (location.gd): шаг — пространством смешивания вперёд/назад/вбок
var armed := false
var move_dir := Vector2.ZERO        # куда идём в осях героя (x — вправо, y — вперёд): location.gd ставит перед tick
var combat := false                 # рядом враг в бою или захват цели: боевая стойка (колени согнуты)
var blocking := false               # держит блок (ПКМ)
var _block_t := 0.0                 # с, сколько держит блок: в начале — окно парирования
var _still := -1.0                   # с какой секунды герой стоит без дела (Idle — раз в 20–30 с, иначе стойка)
var _fidget_at := 0.0
var _fidget_pos := 0.0
var _still_held := false              # стойка уже заморожена на первом кадре (после перехода в неё)
var _dir_sector := "F"              # направление шага (F/B/L/R) — с запасом, чтобы клипы не дёргались на диагонали
var action := ""                    # разовый клип: Draw / Sheathe / Jump / AttackN; "" — ходьба и стойки
var swing_side := 0                  # location.gd: враг слева от героя (−1) — удар справа налево (Attack1), справа (+1) — слева направо (Attack2)
var _combo_i := 0                    # номер удара в серии (клип может быть «зеркальным» — Attack1 вместо Attack2)
var _combo_next_i := 0
var _last_i := -1                    # номер в серии последнего законченного удара («Пауза» — после второго)
var _queued := false                # удар нажат во время текущего — следующий удар комбо
var _combo_next := ""               # удар кончился — ещё combo_grace с нажатие продолжает комбо этим ударом
var _combo_left := 0.0
var _airborne := false
var _running := false                # в прошлом кадре бежал (Shift и шаг) — удар с бега без долгого замаха
var _sword_back: Node3D
var _sword_hand: Node3D
var _sword_drag: Node3D            # только как цель: где меч в беге; виден всегда _sword_hand
var _hand_rest := Transform3D.IDENTITY
var _drag_rest := Transform3D.IDENTITY
var _tip := Vector3.ZERO            # остриё в осях меча (из габаритов сетки)
var _drag_w := 0.0                  # 0 — меч в руке как в стойке, 1 — волочится; между — плавный переход
var _on_floor := true
var _sword_q := Quaternion.IDENTITY   # поворот волочащегося меча с отставанием — он тяжёлый
var _sword_lag := false
var _prev_off := Vector2.ZERO       # root motion: смещение клипа на прошлом кадре
var _swing: AudioStreamPlayer       # свист меча (sounds/swing_*.wav)
var _impact: AudioStreamPlayer      # удар о землю (sounds/impact_*.wav)
var _swing_done := false
var _impact_done := false
var _hit_done := false              # удар этого взмаха уже нанесён (tick вернул hit)
var _lands_done := 0                 # сколько приземлений клипа (step_times) уже озвучено
var _hits_done := 0                  # сколько ударов по hit_times клипа уже нанесено (у копья — несколько за клип)
var _skel: Skeleton3D
var _owner_body: PhysicsBody3D       # капсула персонажа — с ней ткань не сталкивается
var _items: Dictionary = {}          # config/items.json → items: что вообще можно надеть
var _worn: Dictionary = {}           # слот → надетый предмет (см. equip)
var _last_in_slot: Dictionary = {}   # слот → что в нём было — «C» надевает обратно
var cloth_paused := false           # для замера (rpg_perf auto)
var tired := false                  # концентрация ниже трети (location.gd): удары медленнее
var _colliders: Array = []           # [AnimatableBody3D, кость от, кость до] — капсулы тела для тканей
var _trail_mesh: ImmediateMesh      # след взмаха — видно, куда достаёт меч
var _trail_mat: StandardMaterial3D
var _trail: Array = []              # [время, у гарды, остриё]
var _clock := 0.0
var _mod: PaxMod


func load_model(mod: PaxMod, c: Dictionary) -> Node3D:
	cfg = c
	_mod = mod
	model = Assets.model(mod, str(cfg.get("model", "models/hero_simple.glb")))
	if model == null:
		return null
	Assets.track(str(cfg.get("model", "models/hero_simple.glb")), model)
	var mp := str(cfg.get("anim_meta", ""))
	if mp != "":
		var parsed: Variant = JSON.parse_string(mod.read_text(mp))
		meta = parsed if parsed is Dictionary else {}
	var old_cape := model.find_child("Knight_cape", true, false)   # плащ модели снят — плащ теперь вещь (items.json)
	if old_cape != null:
		old_cape.get_parent().remove_child(old_cape)
		old_cape.free()
	_tone_eyes()
	_sword_back = model.find_child("Sword_Back", true, false) as Node3D
	_sword_hand = model.find_child("Sword_Hand", true, false) as Node3D
	_sword_drag = model.find_child("Sword_Drag", true, false) as Node3D
	_retune_swords()
	if _sword_hand != null:
		_hand_rest = _sword_hand.transform
		_tip = _tip_of(_sword_hand)
	if _sword_drag != null:
		_drag_rest = _sword_drag.transform
		_sword_drag.visible = false
	var ip: Variant = JSON.parse_string(mod.read_text(str(cfg.get("items", "config/items.json"))))
	if ip is Dictionary:
		_items = (ip as Dictionary).get("items", {})
	_swing = _player(cfg.get("swing_files", []), _f("swing_pitch_spread", 1.06), _f("swing_volume_db", -4.0))
	_impact = _player(cfg.get("impact_files", []), 1.04, _f("impact_volume_db", 0.0))
	return model


## Глаза модели (Тян Лун): в материалах свечение (emission) и лак — ночью светились сами, мимо света сцены.
## Свечение глаз — eye_glow (доля, 0 — нет), у глазниц — нет; лак — слабый блик.
func _tone_eyes() -> void:
	for n: Node in model.find_children("Eye*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si: int in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m == null:
				continue
			m = m.duplicate() as BaseMaterial3D
			if m.emission_enabled:
				m.emission_energy_multiplier *= _f("eye_glow", 0.2) if not mi.name.begins_with("EyeSocket") else 0.0
				m.emission_enabled = m.emission_energy_multiplier > 0.0
			m.clearcoat = minf(m.clearcoat, 0.3)
			mi.set_surface_override_material(si, m)


## Меч крупнее (sword_scale) и на спине — по диагонали, как у Гатса: рукоять над правым плечом, клинок к левому бедру,
## плашмя к спине (sword_back_grip / sword_back_dir — в осях модели, м; модель смотрит на +Z, правое у героя — −X).
## Начало сетки меча — хват, остриё — дальняя от него точка (_tip_of). Мечи в руке — только крупнее (вокруг хвата).
func _retune_swords() -> void:
	var k := float(cfg.get("sword_scale", 1.3))
	var mp := str(cfg.get("sword_model", ""))                 # своя модель меча (хват — в начале координат, клинок — +Y)
	if mp != "":
		var sw := Assets.model(_mod, mp)
		if sw != null:
			var mis := sw.find_children("*", "MeshInstance3D", true, false)
			if mis.size() > 0:
				var mesh := (mis[0] as MeshInstance3D).mesh
				for s: Node3D in [_sword_back, _sword_hand, _sword_drag]:
					if s is MeshInstance3D:
						(s as MeshInstance3D).mesh = mesh
						(s as MeshInstance3D).material_override = null
			sw.free()
	for s: Node3D in [_sword_hand, _sword_drag]:
		if s != null:
			s.transform = Transform3D(s.transform.basis.scaled_local(Vector3.ONE * k), s.transform.origin)
	if _sword_back == null or not (_sword_back.get_parent() is BoneAttachment3D):
		return
	if bool(cfg.get("sword_back_from_model", false)):   # место за спиной — из модели (1-й кадр Draw), не из чисел;
		_sword_back.transform = Transform3D(_sword_back.transform.basis.scaled_local(Vector3.ONE * k), _sword_back.transform.origin)
		return                                           # размер — как у копья в руке, чтобы смена не прыгала
	var ba := _sword_back.get_parent() as BoneAttachment3D
	var sk := ba.get_parent() as Skeleton3D
	if sk == null:
		return
	var bi := sk.find_bone(ba.bone_name)
	if bi < 0:
		return
	var sk_to_model := Transform3D.IDENTITY                # скелет в осях модели (модель ещё не в дереве)
	var c: Node = sk
	while c != model and c is Node3D:
		sk_to_model = (c as Node3D).transform * sk_to_model
		c = c.get_parent()
	var bone_m := sk_to_model * sk.get_bone_global_rest(bi)
	var old_m := bone_m * _sword_back.transform
	var s0 := old_m.basis.get_scale().x
	var tip := _tip_of(_sword_back)
	if tip.length() < 0.001:
		return
	var t := tip.normalized()                                # клинок в осях меча
	var mi := _sword_back as MeshInstance3D
	var flat := Vector3(0, 0, 1)                             # нормаль плашмя — самая тонкая сторона сетки
	if mi != null and mi.mesh != null:
		var sz := mi.mesh.get_aabb().size
		flat = Vector3.RIGHT if sz.x <= sz.y and sz.x <= sz.z else (Vector3.UP if sz.y <= sz.z else Vector3.BACK)
	flat = (flat - t * flat.dot(t)).normalized()
	var chest := bone_m.origin
	var gv: Array = cfg.get("sword_back_grip", [-0.24, 0.42, -0.26])
	var dv: Array = cfg.get("sword_back_dir", [0.62, -0.78, -0.04])
	var grip := chest + Vector3(float(gv[0]), float(gv[1]), float(gv[2]))
	var b := Vector3(float(dv[0]), float(dv[1]), float(dv[2])).normalized()
	var n := Vector3(0, 0, -1)
	n = (n - b * n.dot(b)).normalized()                      # плашмя к спине
	var local_f := Basis(t, flat, t.cross(flat))
	var world_f := Basis(b, n, b.cross(n))
	var bs := (world_f * local_f.inverse()).scaled_local(Vector3.ONE * s0 * k)
	_sword_back.transform = bone_m.affine_inverse() * Transform3D(bs, grip)


## Остриё: дальняя от хвата точка габаритов сетки меча (в осях узла меча).
static func _tip_of(n: Node3D) -> Vector3:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi == null:
		for c: Node in n.find_children("*", "MeshInstance3D", true, false):
			mi = c as MeshInstance3D
			break
	if mi == null or mi.mesh == null:
		return Vector3.ZERO
	var box := mi.mesh.get_aabb()
	var to_node := Transform3D.IDENTITY          # сетка в осях меча — по локальным, модель ещё не в дереве
	var c: Node = mi
	while c != n and c is Node3D:
		to_node = (c as Node3D).transform * to_node
		c = c.get_parent()
	var best := Vector3.ZERO
	for i: int in 8:
		var p := to_node * box.get_endpoint(i)
		if p.length() > best.length():
			best = p
	var ax := best.abs().max_axis_index()        # остриё — по длинной оси, посередине ширины
	var tip := Vector3.ZERO
	tip[ax] = best[ax]
	return tip


const CLOTH_LAYER := 1 << 4           # слой капсул тела: с ними сталкивается только ткань


## Плеер со случайным из вариантов звука (без повторов подряд) и разбросом высоты.
func _player(files: Variant, pitch: float, volume: float) -> AudioStreamPlayer:
	if not (files is Array) or (files as Array).is_empty():
		return null
	var rnd := AudioStreamRandomizer.new()
	rnd.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rnd.random_pitch = pitch
	rnd.random_volume_offset_db = 1.5
	for f: Variant in files:
		var st: AudioStream = _mod.sound(str(f))
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count == 0:
		return null
	var p := AudioStreamPlayer.new()           # не 3D: у SubViewport локации нет своего слушателя
	p.bus = "PaxRpgSfx"
	p.stream = rnd
	p.volume_db = volume
	model.add_child(p)
	return p


## После того как модель в дереве (вне дерева AnimationPlayer не играет).
var _look: SkeletonModifier3D        # голова следит за целью (LookAtModifier3D на кости головы)
var _look_target: Node3D


## Голова смотрит на точку p (null — отпустить, голова плавно возвращается к анимации). Поворот головы —
## в пределах head_limit градусов (дальше доворачивается всё тело — это решает location.gd).
func look_at_point(p: Variant, delta: float) -> void:
	if _skel == null:
		return
	if _look == null:
		var bone := str(cfg.get("head_bone", "Head"))
		if _skel.find_bone(bone) < 0:
			return
		_look_target = Node3D.new()
		_look_target.top_level = true
		model.add_child(_look_target)
		var la := LookAtModifier3D.new()
		la.bone_name = bone
		la.set("forward_axis", int(cfg.get("head_forward_axis", 4)))     # 4 — +Z кости
		la.use_angle_limitation = true
		la.symmetry_limitation = true
		la.primary_limit_angle = deg_to_rad(float(cfg.get("head_limit", 70.0)) * 2.0)
		la.primary_damp_threshold = 0.8
		la.secondary_limit_angle = deg_to_rad(float(cfg.get("head_limit_pitch", 40.0)) * 2.0)
		la.duration = 0.2
		la.influence = 0.0
		_skel.add_child(la)
		la.target_node = la.get_path_to(_look_target)
		_look = la
	var want := 1.0 if p != null else 0.0
	_look.influence = move_toward(_look.influence, want, delta * 3.0)
	if p != null:
		_look_target.global_position = p


func start(owner_body: PhysicsBody3D = null) -> void:
	var player := _find_anim(model)
	if player == null:
		return
	var spaces: Dictionary = cfg.get("blend_spaces", {})
	var loops: Array = LOOPS.duplicate()
	loops.append("IaiHold")
	for sp: Variant in spaces.values():
		if not (sp is Dictionary):
			continue                                 # "_note" и прочие пояснения
		for clip: Variant in (sp as Dictionary).values():
			loops.append(str(clip))
	for n: Variant in loops:
		if player.has_animation(str(n)):
			player.get_animation(str(n)).loop_mode = Animation.LOOP_LINEAR
	for n: String in ONCE:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_NONE
	if bool(cfg.get("sheathe_from_draw", false)):
		_sheathe_from_draw(player)
	# анимация, поворот головы и меч — в такте физики, как движение и камера: иначе при FPS выше 60 кадры
	# с поправками и без чередуются — поза дёргается, а бег кажется быстрее (дерево — тоже в такте физики)
	anim = AnimCtl.new()
	anim.name = "AnimCtl"
	anim.blend_smooth = _f("blend_space_smooth", 10.0)
	model.add_child(anim)
	anim.setup(player, spaces)
	anim.animation_finished.connect(_on_finished)
	anim.play("Idle", 0.0)                         # сразу в стойке — без перехода из первой петли списка
	_skel = _find_skeleton(model)
	if _skel != null:
		_skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
		if bool(cfg.get("foot_ik", true)) and owner_body is CharacterBody3D:   # стопы на ступенях и склонах
			var ik := FootIK.new()
			ik.name = "FootIK"
			ik.body = owner_body
			ik.feet_root = model
			ik.reach = _f("foot_ik_reach", 0.45)
			ik.hip_max = _f("foot_ik_hip", 0.35)
			_skel.add_child(ik)
	_owner_body = owner_body
	# меч за спиной — чуть дальше от спины, поверх плаща (иначе клинок тонет в ткани)
	if _sword_back != null and _sword_back.is_inside_tree() and _sword_back.get_parent() is Node3D \
			and not bool(cfg.get("sword_back_from_model", false)):
		var spine := _skel.find_bone("Spine02")
		var back := Vector3.ZERO
		if spine >= 0:                                    # «наружу» — от позвоночника к мечу, по горизонтали
			back = _sword_back.global_position - _bone_world(spine).origin
			back.y = 0.0
		back = back.normalized() * _f("sword_back_out", 0.12)
		_sword_back.position += (_sword_back.get_parent() as Node3D).global_transform.basis.inverse() * back
	for id: Variant in cfg.get("equipped", []):
		equip(str(id))
	_make_trail()
	_show_sword(0.0)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c: Node in n.get_children():
		var a := _find_anim(c)
		if a != null:
			return a
	return null


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c: Node in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


func _f(k: String, d: float) -> float:
	return float(cfg.get(k, d))


## Значение по клипу из словаря настроек ({"Attack1": 0.4, ...}) или общее.
func _per(k: String, clip: String, d: float) -> float:
	var v: Variant = cfg.get(k, d)
	if v is Dictionary:
		return float((v as Dictionary).get(clip, d))
	return float(v)


func has(n: String) -> bool:
	return anim != null and anim.has_animation(n)


func locks_move() -> bool:
	return action != "" and action != "Jump" and action not in SOFT and action != "ComboEnd" and action not in ON_THE_GO


## Достаёт или убирает меч на ходу — бежать нельзя, только шаг.
func walk_only() -> bool:
	return action in ON_THE_GO


# ---------- предметы: надеть / снять ----------
# Предмет (config/items.json) сделан в позе покоя модели героя, в её осях. Виды:
#   cloth — ткань SoftBody3D (плащ): верх пришит к костям pin_bones, ниже — свободна, бьётся о капсулы тела и землю;
#   rigid — жёсткая вещь (шлем, наплечник): едет за костью bone.
#   cape — плащ со своей тканью (как Max Distance в Unreal / Skinned Cloth в Unity): у каждой точки есть место на
#          анимированном теле, к нему её тянет пружина, и дальше max_dist от него она не уходит — у плеч 0, к подолу
#          больше. Движется только грубая решётка coarse (5 × 7 точек), сетка плаща гладко повторяет её — ткань
#          тяжёлая, отдельные «пиксели» не болтаются. Бьётся о капсулы тела и землю.
# В слоте — одна вещь: надеть новую — старая снимается.

func _bone_world(idx: int, rest := false) -> Transform3D:
	var t := _skel.get_bone_global_rest(idx) if rest else _skel.get_bone_global_pose(idx)
	var g := _skel.global_transform * t
	return Transform3D(g.basis.orthonormalized(), g.origin)


func worn(slot: String) -> String:
	return str((_worn.get(slot, {}) as Dictionary).get("id", ""))


func equip(id: String) -> bool:
	var it: Dictionary = _items.get(id, {})
	if it.is_empty() or _skel == null or not model.is_inside_tree():
		return false
	var slot := str(it.get("slot", id))
	unequip(slot)
	var w := {"id": id, "item": it, "nodes": [], "anchors": [], "cloth": null, "pin_left": 0}
	var ok := false
	match str(it.get("kind", "rigid")):
		"cape":
			ok = _wear_cape(it, w)
		"cloth":
			ok = _wear_cloth(it, w)
		_:
			ok = _wear_rigid(it, w)
	if not ok:
		for n: Node in w.nodes:
			n.queue_free()
		_mod.log_warning("Pax RPG: item %s did not load" % id)
		return false
	_worn[slot] = w
	_last_in_slot[slot] = id
	return true


func unequip(slot: String) -> void:
	var w: Dictionary = _worn.get(slot, {})
	for n: Node in w.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	_worn.erase(slot)


## «C»: снять вещь со слота или надеть ту, что в нём была (или первую из надетых при старте).
func toggle_slot(slot: String) -> void:
	if _worn.has(slot):
		unequip(slot)
		return
	var id := str(_last_in_slot.get(slot, ""))
	if id == "":
		for e: Variant in cfg.get("equipped", []):
			if str((_items.get(str(e), {}) as Dictionary).get("slot", "")) == slot:
				id = str(e)
	if id != "":
		equip(id)


## Сетка предмета из glb и её положение в осях сцены glb.
func _load_mesh(path: String) -> Array:
	var src := Assets.model(_mod, path)
	if src == null:
		return []
	var mi: MeshInstance3D = null
	for c: Node in src.find_children("*", "MeshInstance3D", true, false):
		mi = c as MeshInstance3D
		break
	if mi == null or mi.mesh == null:
		src.free()
		return []
	var local := Transform3D.IDENTITY
	var n: Node = mi
	while n != src and n is Node3D:
		local = (n as Node3D).transform * local
		n = n.get_parent()
	var mesh := mi.mesh
	src.free()
	return [mesh, local]


func _iv(it: Dictionary, k: String, d: float) -> float:
	return float(it.get(k, d))


func _wear_cloth(it: Dictionary, w: Dictionary) -> bool:
	var ml := _load_mesh(str(it.get("model", "")))
	if ml.is_empty():
		return false
	var sb := SoftBody3D.new()
	sb.mesh = ml[0]
	sb.top_level = true
	sb.transform = model.global_transform * (ml[1] as Transform3D)
	w.xform = sb.transform
	sb.collision_layer = 0
	sb.collision_mask = 1 | CLOTH_LAYER
	sb.simulation_precision = int(_iv(it, "precision", 12))
	sb.total_mass = _iv(it, "mass", 0.7)
	sb.linear_stiffness = _iv(it, "stiffness", 0.35)
	sb.damping_coefficient = _iv(it, "damping", 0.012)
	sb.drag_coefficient = _iv(it, "drag", 0.02)
	sb.pressure_coefficient = 0.0
	model.add_child(sb)
	if _owner_body != null:
		sb.add_collision_exception_with(_owner_body)
	w.cloth = sb
	(w.nodes as Array).append(sb)
	for bn: Variant in it.get("pin_bones", ["Spine02", "LeftShoulder", "RightShoulder", "neck"]):
		var bi := _skel.find_bone(str(bn))
		if bi < 0:
			continue
		var an := Node3D.new()
		an.top_level = true
		model.add_child(an)
		an.global_transform = _bone_world(bi, true)    # пришиваем в позе покоя — как сетка
		(w.anchors as Array).append([an, bi])
		(w.nodes as Array).append(an)
	if (w.anchors as Array).is_empty():
		return false
	w.pin_left = 1
	if _colliders.is_empty():
		_make_body_colliders()
	return true


func _wear_cape(it: Dictionary, w: Dictionary) -> bool:
	var parsed: Variant = JSON.parse_string(_mod.read_text(str(it.get("grid", ""))))
	if not (parsed is Dictionary):
		return false
	var g: Dictionary = parsed
	var nx := int(g.get("nx", 0))
	var nz := int(g.get("nz", 0))
	var pts: Array = g.get("points", [])
	if nx < 2 or nz < 2 or pts.size() != nx * nz:
		return false
	var top_b := _skel.find_bone(str(it.get("top_bone", "Spine")))
	var low_b := _skel.find_bone(str(it.get("low_bone", "Hips")))
	var sides: Array = it.get("side_bones", ["LeftShoulder", "RightShoulder"])   # +X — левое плечо рыцаря
	var left_b := _skel.find_bone(str(sides[0]))
	var right_b := _skel.find_bone(str(sides[1]))
	if top_b < 0 or low_b < 0:
		return false
	var rest := PackedVector3Array()
	for p: Variant in pts:
		var a: Array = p
		rest.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	var lift: Array = it.get("lift", [0.0, 0.0, 0.0])            # весь плащ: вверх к плечам и назад (м)
	for k: int in rest.size():
		rest[k] += Vector3(float(lift[0]), float(lift[1]), float(lift[2]))
	# «за шиворот»: середина верхнего края — к основанию шеи сзади (сетка лежала на плечах впереди шеи),
	# три ряда ниже плавно тянутся следом; края у плеч остаются на месте
	var half0 := 0.1
	for i: int in nx:
		half0 = maxf(half0, absf(rest[i].x))
	var neck_b := _skel.find_bone(str(it.get("neck_bone", "neck")))
	var cl: Array = it.get("collar", [0.075, 0.035, 0.11])       # назад от шеи, вниз, полуширина у шеи (м)
	var nk := Vector3.ZERO
	if neck_b >= 0 and it.has("collar"):                       # подтяжка к шее — только если задана: без неё край ровно по плечам
		nk = model.global_transform.affine_inverse() * _bone_world(neck_b, true).origin
		for i: int in nx:
			var u := rest[i].x / half0
			var wgt := 1.0 - smoothstep(0.35, 0.9, absf(u))
			var want := Vector3(nk.x + u * float(cl[2]), nk.y - float(cl[1]), nk.z - float(cl[0]))
			var dd := (want - rest[i]) * wgt
			for j: int in 4:
				rest[j * nx + i] += dd * (1.0 - j / 4.0)
	var shade := PackedFloat32Array()
	for v: Variant in g.get("shade", []):
		shade.append(float(v))
	var cs: Array = it.get("coarse", [5, 7])
	var cx := int(cs[0])
	var cz := int(cs[1])
	# грубая решётка: точки сетки на равных шагах
	var c_idx := PackedInt32Array()
	for j: int in cz:
		for i: int in cx:
			c_idx.append(roundi(float(j) / (cz - 1) * (nz - 1)) * nx + roundi(float(i) / (cx - 1) * (nx - 1)))
	var mesh := ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	var mat := StandardMaterial3D.new()
	var col: Array = g.get("color", [0.2, 0.16, 0.24])
	mat.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]))
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.roughness = 0.92
	var tex_a := _tex_mip(str(it.get("texture", "")), false)
	if tex_a != null:                                  # ткань: шерсть, вышитая кайма, рельеф
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = tex_a
		var tn := _tex_mip(str(it.get("normal", "")), true)
		if tn != null:
			mat.normal_enabled = true
			mat.normal_texture = tn
			mat.normal_scale = 1.4
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var lining := StandardMaterial3D.new()               # изнанка — тёмно-алая подкладка
	var lc: Array = it.get("lining", [0.32, 0.05, 0.1])
	lining.albedo_color = Color(float(lc[0]), float(lc[1]), float(lc[2]))
	lining.vertex_color_use_as_albedo = true
	lining.roughness = 0.6
	lining.cull_mode = BaseMaterial3D.CULL_FRONT
	if mat.normal_texture != null:
		lining.normal_enabled = true
		lining.normal_texture = mat.normal_texture
		lining.normal_scale = 0.6
	model.add_child(mi)
	(w.nodes as Array).append(mi)
	var half := 0.0
	for i: int in nx:
		half = maxf(half, absf(rest[i].x))
	w.cape = {"nx": nx, "nz": nz, "rest": rest, "shade": shade, "cx": cx, "cz": cz, "c_idx": c_idx,
		"top_b": top_b, "low_b": low_b, "left_b": left_b, "right_b": right_b, "half": maxf(half, 0.1),
		"mesh": mesh, "mat": mat, "lining": lining, "item": it,
		"x": PackedVector3Array(), "prev": PackedVector3Array(), "len_h": 0.0, "len_v": 0.0}
	var c: Dictionary = w.cape
	var tg := _cape_targets(c, c_idx)
	c.x = tg.duplicate()
	c.prev = tg.duplicate()
	c.len_h = (rest[c_idx[1]] - rest[c_idx[0]]).length()
	c.len_v = (rest[c_idx[cx]] - rest[c_idx[0]]).length()
	if neck_b >= 0 and bool(it.get("collar_mesh", true)):
		_make_collar(c, w, nk, cl, mat)
	if _colliders.is_empty():
		_make_body_colliders()
	return true


func _tex_mip(path: String, normal: bool) -> Texture2D:
	if path == "":
		return null
	var t := _mod.texture(path)
	if t == null:
		return null
	var img := t.get_image()
	if img == null or img.is_compressed() or img.has_mipmaps():
		return t
	img.generate_mipmaps(normal)
	return ImageTexture.create_from_image(img)


## Воротник: свёрнутая валиком ткань плаща вокруг шеи сзади и по плечам, спереди — две золотые фибулы
## и цепочка между ними. Едет с костью грудной клетки (top_bone), как верх плаща.
func _make_collar(c: Dictionary, w: Dictionary, nk: Vector3, cl: Array, mat: Material) -> void:
	var hw := float(cl[2])
	var path := [Vector3(hw + 0.02, -0.12, 0.085), Vector3(hw + 0.05, -0.045, 0.01), Vector3(hw * 0.55, -0.02, -0.06),
		Vector3(0.0, -0.015, -float(cl[0]) - 0.005), Vector3(-hw * 0.55, -0.02, -0.06), Vector3(-hw - 0.05, -0.045, 0.01),
		Vector3(-hw - 0.02, -0.12, 0.085)]
	var pts := PackedVector3Array()
	var n := 36
	for k: int in n + 1:                                   # Catmull-Rom по опорным точкам
		var f := float(k) / n * (path.size() - 1)
		var i := mini(int(f), path.size() - 2)
		var t := f - i
		var p0: Vector3 = path[maxi(i - 1, 0)]
		var p1: Vector3 = path[i]
		var p2: Vector3 = path[i + 1]
		var p3: Vector3 = path[mini(i + 2, path.size() - 1)]
		pts.append(nk + 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 12
	for k: int in pts.size():
		var tng := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := tng.cross(Vector3.UP).normalized()
		var upv := side.cross(tng).normalized()
		var mid := 1.0 - absf(float(k) / n * 2.0 - 1.0)            # толще сзади, тоньше к застёжкам
		var rad := lerpf(0.022, 0.045, smoothstep(0.0, 0.7, mid))
		for r: int in ring + 1:
			var a := TAU * r / ring
			var off := (side * cos(a) * 1.15 + upv * sin(a) * 0.8) * rad      # валик чуть приплюснут
			off += upv * 0.004 * sin(a * 3.0 + k * 0.9)                      # складки ткани
			st.set_uv(Vector2(float(k) / n * 3.0, float(r) / ring * 0.25))
			st.set_normal(off.normalized())
			st.add_vertex(pts[k] + off)
	for k: int in pts.size() - 1:
		for r: int in ring:
			var a := k * (ring + 1) + r
			var b := a + ring + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.top_level = true
	model.add_child(mi)
	(w.nodes as Array).append(mi)
	# фибулы и цепочка
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.64, 0.28)
	gold.metallic = 1.0
	gold.roughness = 0.3
	var parts: Array = []
	for sgn: float in [1.0, -1.0]:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.028
		cm.bottom_radius = 0.03
		cm.height = 0.012
		cm.radial_segments = 20
		cm.material = gold
		disc.mesh = cm
		var at := nk + Vector3(sgn * (hw + 0.02), -0.12, 0.1)
		disc.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)
		parts.append(disc)
		var gem := MeshInstance3D.new()                   # розовый камень в центре фибулы
		var sm := SphereMesh.new()
		sm.radius = 0.011
		sm.height = 0.016
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(1.0, 0.4, 0.7)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.3, 0.6)
		gm.emission_energy_multiplier = 0.6
		gm.roughness = 0.1
		sm.material = gm
		gem.mesh = sm
		gem.position = at + Vector3(0, 0, 0.008)
		parts.append(gem)
	for k: int in 9:                                       # цепочка с провисом
		var f := float(k) / 8.0
		var link := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.006
		lm.height = 0.012
		lm.material = gold
		link.mesh = lm
		link.position = nk + Vector3(lerpf(hw + 0.02, -hw - 0.02, f), -0.12 - 0.035 * sin(f * PI), 0.105)
		parts.append(link)
	var holder := Node3D.new()
	holder.top_level = true
	model.add_child(holder)
	(w.nodes as Array).append(holder)
	for pt: MeshInstance3D in parts:
		holder.add_child(pt)
	c.collar = [mi, holder]


## Постоянное для каждой точки плаща — один раз при надевании (раньше — каждый такт и дважды: на грубую решётку и
## на всю сетку): веса «середина ↔ плечо» и «верх ↔ низ», сторона, отступ от верха своей колонки; для густой
## сетки — клетка грубой решётки и доли в ней; для ткани — пружина и предел отхода по рядам.
func _cape_prep(c: Dictionary) -> void:
	var rest: PackedVector3Array = c.rest
	var nx: int = c.nx
	var nz: int = c.nz
	var cx: int = c.cx
	var cz: int = c.cz
	var half: float = c.half
	var n := nx * nz
	var wl := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var side := PackedByteArray()
	var dcol := PackedVector3Array()
	wl.resize(n)
	ws.resize(n)
	side.resize(n)
	dcol.resize(n)
	for k: int in n:
		var row := floorf(float(k) / nx) / float(nz - 1)
		wl[k] = smoothstep(0.15, 0.9, row)
		var u := rest[k].x / half
		ws[k] = smoothstep(0.3, 1.0, absf(u)) * (1.0 - smoothstep(0.0, 0.35, row))
		side[k] = 1 if u > 0.0 else 0
		dcol[k] = rest[k] - rest[k % nx]
	c.wl = wl
	c.ws = ws
	c.side = side
	c.dcol = dcol
	# густая сетка: в какой клетке грубой решётки точка и где в ней (по рядам и по колонкам)
	var j0r := PackedInt32Array()
	var tvr := PackedFloat64Array()
	for j: int in nz:
		var fv := float(j) / (nz - 1) * (cz - 1)
		var j0 := mini(int(fv), cz - 2)
		j0r.append(j0 * cx)
		tvr.append(fv - j0)
	var i0c := PackedInt32Array()
	var tuc := PackedFloat64Array()
	for i: int in nx:
		var fu := float(i) / (nx - 1) * (cx - 1)
		var i0 := mini(int(fu), cx - 2)
		i0c.append(i0)
		tuc.append(fu - i0)
	c.j0r = j0r
	c.tvr = tvr
	c.i0c = i0c
	c.tuc = tuc
	# ткань: пружина к месту на теле (у подола слабее) и предел отхода — по рядам грубой решётки
	var it: Dictionary = c.get("item", {})
	var fr := PackedFloat64Array()
	var lim := PackedFloat64Array()
	for j: int in cz:
		var row := float(j) / float(cz - 1)
		fr.append(lerpf(1.0, _iv(it, "follow_hem", 0.12), row))
		lim.append(_iv(it, "max_dist", 0.5) * pow(row, 1.15))
	c.fr = fr
	c.lim = lim
	c.hang_w = _iv(it, "hang", 0.75)


## Где точки плаща сейчас «на теле» — все точки сетки за один проход: верх посередине едет с грудью, углы верха —
## с плечами, низ — с тазом. Кости — один раз за такт (раньше дважды: для решётки и для сетки).
func _cape_targets_all(c: Dictionary) -> PackedVector3Array:
	if not c.has("wl"):
		_cape_prep(c)
	var rest: PackedVector3Array = c.rest
	var nx: int = c.nx
	var mg := model.global_transform
	var t_top := _bone_world(int(c.top_b)) * _bone_world(int(c.top_b), true).affine_inverse()
	var t_low := _bone_world(int(c.low_b)) * _bone_world(int(c.low_b), true).affine_inverse()
	var t_l := t_top
	var t_r := t_top
	if int(c.left_b) >= 0 and int(c.right_b) >= 0:
		t_l = _bone_world(int(c.left_b)) * _bone_world(int(c.left_b), true).affine_inverse()
		t_r = _bone_world(int(c.right_b)) * _bone_world(int(c.right_b), true).affine_inverse()
	c.t_top = t_top                                      # воротник едет с ним (_cape_draw)
	var hang_w: float = c.hang_w
	var yaw := Basis(Vector3.UP, atan2(t_low.basis.z.x, t_low.basis.z.z))   # поворот таза от покоя, только по горизонтали
	# точка тела = кость · модель · покой: произведение «кость · модель» — раз за такт, а не на каждую точку
	var a_top := t_top * mg
	var a_low := t_low * mg
	var a_l := t_l * mg
	var a_r := t_r * mg
	var yb := yaw * mg.basis
	var top_cols := PackedVector3Array()                  # точка крепления каждой колонки (верхний ряд)
	top_cols.resize(nx)
	for col_i: int in nx:
		top_cols[col_i] = a_top * rest[col_i]
	var wl: PackedFloat32Array = c.wl
	var ws: PackedFloat32Array = c.ws
	var side: PackedByteArray = c.side
	var dcol: PackedVector3Array = c.dcol
	var n := rest.size()
	var out := PackedVector3Array()
	out.resize(n)
	for k: int in n:
		var r := rest[k]
		var up := a_top * r
		var s := ws[k]
		if s > 0.0:                                       # к плечу — только у верхних углов
			up = up.lerp((a_l if side[k] == 1 else a_r) * r, s)
		var w := wl[k]
		if w > 0.0:
			# ниже лопаток ткань висит под своим весом: от точки крепления этой колонки — прямо вниз (с поворотом
			# корпуса по горизонтали), а не по наклону спины — иначе в боевой стойке середина выгибается горбом
			var low := (a_low * r).lerp(top_cols[k % nx] + yb * dcol[k], hang_w)
			up = up.lerp(low, w)
		out[k] = up
	return out


## То же для части точек (idx) — при надевании.
func _cape_targets(c: Dictionary, idx: PackedInt32Array) -> PackedVector3Array:
	var all := _cape_targets_all(c)
	var out := PackedVector3Array()
	out.resize(idx.size())
	for k: int in idx.size():
		out[k] = all[idx[k]]
	return out


func _cape_tick(w: Dictionary, delta: float) -> void:
	var c: Dictionary = w.cape
	var it: Dictionary = w.item
	var cx: int = c.cx
	var cz: int = c.cz
	var t0 := Time.get_ticks_usec()
	var base := _cape_targets_all(c)                     # вся сетка «на теле»; решётке — её узлы
	var c_idx: PackedInt32Array = c.c_idx
	var tg := PackedVector3Array()
	tg.resize(c_idx.size())
	for k: int in c_idx.size():
		tg[k] = base[c_idx[k]]
	var x: PackedVector3Array = c.x
	var prev: PackedVector3Array = c.prev
	var dt := clampf(delta, 0.001, 0.05)
	var damp := _iv(it, "damping", 0.9)
	var grav := Vector3(0.0, -_iv(it, "gravity", 9.8), 0.0) * dt * dt
	var follow := _iv(it, "follow", 0.12)
	var floor_y := model.global_position.y + 0.03
	var fr: PackedFloat64Array = c.fr
	var lim: PackedFloat64Array = c.lim
	var n := x.size()
	for k: int in cx:                                    # верхний ряд пришит
		x[k] = tg[k]
		prev[k] = tg[k]
	for k: int in range(cx, n):
		var v := (x[k] - prev[k]) * damp
		prev[k] = x[k]
		x[k] += v + grav
		x[k] += (tg[k] - x[k]) * follow * fr[k / cx]     # верх держит форму, низ — инерция
	var len_h: float = c.len_h
	var len_v: float = c.len_v
	for _it: int in int(_iv(it, "iterations", 4)):
		# связи соседей: длина как в покое (верхний ряд не двигается) — прямо здесь, без вызова на каждую связь
		for j: int in cz:
			for i: int in cx:
				var k := j * cx + i
				if i + 1 < cx and j > 0:
					var d := x[k + 1] - x[k]
					var dl := d.length()
					if dl >= 0.0001:
						var corr := d * ((dl - len_h) / dl)
						x[k] += corr * 0.5
						x[k + 1] -= corr * 0.5
				if j + 1 < cz:
					var b := k + cx
					var d := x[b] - x[k]
					var dl := d.length()
					if dl >= 0.0001:
						var corr := d * ((dl - len_v) / dl)
						if j == 0:
							x[b] -= corr
						else:
							x[k] += corr * 0.5
							x[b] -= corr * 0.5
		for k: int in range(cx, n):                       # дальше max_dist от места на теле не уходит
			var d := x[k] - tg[k]
			if d.length() > lim[k / cx]:
				x[k] = tg[k] + d.normalized() * lim[k / cx]
		_push_all(x, tg, cx)
		for k: int in range(cx, n):
			if x[k].y < floor_y:
				x[k].y = floor_y
	c.x = x
	c.prev = prev
	Prof.add("плащ: ткань", t0)
	_cape_draw(c, base, tg)


## Вытолкнуть точку ткани из капсул тела. ref — где ткань должна быть (цель): если нога «перешагнула» точку и та
## оказалась спереди, выталкиваем в сторону цели (назад, за ногу), а не вперёд сквозь неё.
var _cap_pos := PackedVector3Array()     # капсулы тела на этот такт (_cache_colliders): центр, ось, полудлина, радиус
var _cap_axis := PackedVector3Array()
var _cap_half := PackedFloat32Array()
var _cap_r := PackedFloat32Array()
var _cap_reach := PackedFloat32Array()   # квадрат «полудлина + радиус»: дальше от центра — капсула точку не трогает


var _phys_on := true                     # формы капсул включены (нужны только SoftBody3D)


## Размеры капсул — один раз (и когда меняется их набор); формы — вкл./выкл. под мягкую ткань.
func _cache_dims(phys: bool) -> void:
	var n := _colliders.size()
	if _cap_half.size() != n:
		_cap_pos.resize(n)
		_cap_axis.resize(n)
		_cap_half.resize(n)
		_cap_r.resize(n)
		_cap_reach.resize(n)
		for i: int in n:
			var body: AnimatableBody3D = _colliders[i][0]
			var cap: CapsuleShape3D = (body.get_child(0) as CollisionShape3D).shape
			_cap_half[i] = cap.height * 0.5 - cap.radius
			_cap_r[i] = cap.radius + 0.03
			_cap_reach[i] = pow(_cap_half[i] + _cap_r[i] + 0.01, 2.0)
		_phys_on = not phys                           # набор сменился — формы выставить заново
	if _phys_on != phys:
		_phys_on = phys
		for c: Array in _colliders:
			((c[0] as Node).get_child(0) as CollisionShape3D).set_deferred("disabled", not phys)


func _push_out(p: Vector3, ref := Vector3.INF) -> Vector3:
	for ci: int in _cap_pos.size():
		var axis := _cap_axis[ci]
		var half := _cap_half[ci]
		var rel := p - _cap_pos[ci]
		var along := clampf(rel.dot(axis), -half, half)
		var nearest := _cap_pos[ci] + axis * along
		var off := p - nearest
		var dist := off.length()
		var r := _cap_r[ci]
		if dist < r:
			var dir := off / dist if dist > 0.0001 else Vector3.ZERO
			if ref != Vector3.INF:
				var want := ref - nearest
				want -= axis * want.dot(axis)
				if want.length() > 0.0001 and (dir == Vector3.ZERO or dir.dot(want) < 0.0):
					dir = want.normalized()
			if dir != Vector3.ZERO:
				p = nearest + dir * r
	return p


## _push_out для точек p[from..] (ref — их места на теле) одним проходом: капсула, до центра которой дальше
## полудлины и радиуса, точку не трогает — пропускается одним сравнением (большая часть пар «точка — капсула»).
func _push_all(p: PackedVector3Array, ref: PackedVector3Array, from: int) -> void:
	var nc := _cap_pos.size()
	for k: int in range(from, p.size()):
		var q := p[k]
		var moved := false
		for ci: int in nc:
			var rel := q - _cap_pos[ci]
			if rel.length_squared() > _cap_reach[ci]:
				continue
			var axis := _cap_axis[ci]
			var half := _cap_half[ci]
			var nearest := _cap_pos[ci] + axis * clampf(rel.dot(axis), -half, half)
			var off := q - nearest
			var dist := off.length()
			var r := _cap_r[ci]
			if dist < r:
				var dir := off / dist if dist > 0.0001 else Vector3.ZERO
				var want := ref[k] - nearest
				want -= axis * want.dot(axis)
				if want.length() > 0.0001 and (dir == Vector3.ZERO or dir.dot(want) < 0.0):
					dir = want.normalized()
				if dir != Vector3.ZERO:
					q = nearest + dir * r
					moved = true
		if moved:
			p[k] = q


## Сетка плаща: смещение каждой её точки от «места на теле» — билинейно по грубой решётке; потом вдвое гуще
## и гладко (Catmull-Rom), нормали — по соседям. base — вся сетка на теле, tg — узлы решётки на теле.
func _cape_draw(c: Dictionary, base: PackedVector3Array, tg: PackedVector3Array) -> void:
	var t0 := Time.get_ticks_usec()
	if c.has("collar"):
		var t_top: Transform3D = c.t_top
		for nd: Node3D in c.collar:
			if is_instance_valid(nd):
				nd.global_transform = t_top * model.global_transform
	var nx: int = c.nx
	var nz: int = c.nz
	var cx: int = c.cx
	var x: PackedVector3Array = c.x
	var off := PackedVector3Array()                       # сдвиг узлов решётки от места на теле
	off.resize(tg.size())
	for k: int in tg.size():
		off[k] = x[k] - tg[k]
	var j0r: PackedInt32Array = c.j0r
	var tvr: PackedFloat64Array = c.tvr
	var i0c: PackedInt32Array = c.i0c
	var tuc: PackedFloat64Array = c.tuc
	var pos := PackedVector3Array()
	pos.resize(nx * nz)
	for j: int in nz:
		var r0 := j0r[j]
		var tv := tvr[j]
		var row := j * nx
		for i: int in nx:
			var k00 := r0 + i0c[i]
			var tu := tuc[i]
			pos[row + i] = base[row + i] + off[k00].lerp(off[k00 + 1], tu).lerp(off[k00 + cx].lerp(off[k00 + cx + 1], tu), tv)
	_push_all(pos, base, 0)                              # и густую сетку — не режет ноги
	# вдвое гуще и гладко (Catmull-Rom по сетке): без углов на складках. Середина отрезка у Catmull-Rom —
	# (−p0 + 9·p1 + 9·p2 − p3) / 16, узлы — как есть: без общей формулы и вызова на каждую точку
	var sub := 2
	var mx := (nx - 1) * sub + 1
	var mz := (nz - 1) * sub + 1
	var rows := PackedVector3Array()                      # сначала вдоль колонок
	rows.resize(nx * mz)
	for i: int in nx:
		var p0 := pos[i]
		var p1 := pos[i]
		var p2 := pos[nx + i]
		for k: int in nz - 1:
			var p3 := pos[mini(k + 2, nz - 1) * nx + i]
			rows[k * sub * nx + i] = p1
			rows[(k * sub + 1) * nx + i] = (p1 + p2) * 0.5625 - (p0 + p3) * 0.0625
			p0 = p1
			p1 = p2
			p2 = p3
		rows[(mz - 1) * nx + i] = pos[(nz - 1) * nx + i]
	var sp := PackedVector3Array()                        # потом вдоль рядов
	sp.resize(mx * mz)
	for j2: int in mz:
		var rb := j2 * nx
		var o := j2 * mx
		var p0 := rows[rb]
		var p1 := rows[rb]
		var p2 := rows[rb + 1]
		for k: int in nx - 1:
			var p3 := rows[rb + mini(k + 2, nx - 1)]
			sp[o + k * sub] = p1
			sp[o + k * sub + 1] = (p1 + p2) * 0.5625 - (p0 + p3) * 0.0625
			p0 = p1
			p1 = p2
			p2 = p3
		sp[o + mx - 1] = rows[rb + nx - 1]
	var nrm := PackedVector3Array()                       # нормаль — по соседям слева-справа и сверху-снизу
	nrm.resize(mx * mz)
	for j: int in mz:
		var o := j * mx
		var ou := maxi(j - 1, 0) * mx
		var od := mini(j + 1, mz - 1) * mx
		nrm[o] = (sp[o + 1] - sp[o]).cross(sp[od] - sp[ou]).normalized()
		for i: int in range(1, mx - 1):
			nrm[o + i] = (sp[o + i + 1] - sp[o + i - 1]).cross(sp[od + i] - sp[ou + i]).normalized()
		nrm[o + mx - 1] = (sp[o + mx - 1] - sp[o + mx - 2]).cross(sp[od + mx - 1] - sp[ou + mx - 1]).normalized()
	Prof.add("плащ: сетка", t0)
	_cape_upload(c, sp, nrm, mx, mz, sub)


## Индексы, UV и оттенок — один раз; за такт движку уходят только позиции и нормали (раньше ImmediateMesh
## по вершине: ~50 тыс. вызовов из GDScript на кадр — 13 мс).
func _cape_upload(c: Dictionary, sp: PackedVector3Array, nrm: PackedVector3Array, mx: int, mz: int, sub: int) -> void:
	var t0 := Time.get_ticks_usec()
	var nx: int = c.nx
	var nz: int = c.nz
	if not c.has("arr"):
		var shade: PackedFloat32Array = c.shade
		var idx := PackedInt32Array()
		for j: int in mz - 1:
			for i: int in mx - 1:
				var a := j * mx + i
				idx.append_array([a, a + mx, a + 1, a + 1, a + mx, a + mx + 1])
		var uv := PackedVector2Array()
		var col := PackedColorArray()
		uv.resize(mx * mz)
		col.resize(mx * mz)
		for k: int in mx * mz:
			var ii := k % mx
			var jj := k / mx
			var si := mini(roundi(float(ii) / sub), nx - 1)
			var sj := mini(roundi(float(jj) / sub), nz - 1)
			var s := shade[sj * nx + si] if sj * nx + si < shade.size() else 1.0
			col[k] = Color(s, s, s)
			uv[k] = Vector2(float(ii) / (mx - 1), float(jj) / (mz - 1))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		c.arr = arr
	var arr2: Array = c.arr
	arr2[Mesh.ARRAY_VERTEX] = sp
	arr2[Mesh.ARRAY_NORMAL] = nrm
	var mesh: ArrayMesh = c.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)    # одна поверхность: лицо — ткань, изнанка — next_pass
	var mat: Material = c.mat
	if mat.next_pass != c.lining:
		mat.next_pass = c.lining                                  # подкладка (cull front) — тем же буфером, без второй загрузки
	mesh.surface_set_material(0, mat)
	Prof.add("плащ: загрузка", t0)


func _wear_rigid(it: Dictionary, w: Dictionary) -> bool:
	var bi := _skel.find_bone(str(it.get("bone", "Head")))
	var src := Assets.model(_mod, str(it.get("model", "")))
	if src == null or bi < 0:
		if src != null:
			src.free()
		return false
	var follow := Node3D.new()
	follow.top_level = true
	model.add_child(follow)
	follow.add_child(src)
	w.bone = bi
	w.rel = _bone_world(bi, true).affine_inverse() * model.global_transform   # вещь сделана в позе покоя модели
	follow.global_transform = _bone_world(bi) * (w.rel as Transform3D)
	w.follow = follow
	(w.nodes as Array).append(follow)
	return true


## Капсулы тела (таз, спина, бёдра, голени) — о них бьётся ткань; персонажа и мир они не трогают.
func _make_body_colliders() -> void:
	for d: Array in [["Hips", "Spine01", 0.18], ["Spine01", "Spine02", 0.155], ["Spine02", "neck", 0.07],
			["LeftUpLeg", "LeftLeg", 0.115], ["RightUpLeg", "RightLeg", 0.115],
			["LeftLeg", "LeftFoot", 0.09], ["RightLeg", "RightFoot", 0.09]]:
		var ia := _skel.find_bone(str(d[0]))
		var ib := _skel.find_bone(str(d[1]))
		if ia < 0 or ib < 0:
			continue
		var body := AnimatableBody3D.new()
		body.top_level = true
		body.sync_to_physics = false
		body.collision_layer = CLOTH_LAYER
		body.collision_mask = 0
		var sh := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var len_ := (_bone_world(ib, true).origin - _bone_world(ia, true).origin).length()
		cap.radius = float(d[2]) * _f("cloth_body_scale", 1.5)
		cap.height = len_ + cap.radius * 2.0
		sh.shape = cap
		body.add_child(sh)
		model.add_child(body)
		_colliders.append([body, ia, ib])
	_move_colliders(true)


## Меч за спиной — тоже капсула для ткани: плащ ложится поверх клинка, а не проходит сквозь.
var _sword_cap: Array = []           # [AnimatableBody3D, центр клинка в осях меча, ось клинка в осях меча]


func _sword_collider() -> void:
	if _sword_back == null:
		return
	var box := AABB()
	var first := true
	for mi: Node in _sword_back.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := _sword_back.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		return
	var axis := Vector3.ZERO
	axis[box.get_longest_axis_index()] = 1.0
	var length := box.get_longest_axis_size()
	var body := AnimatableBody3D.new()
	body.top_level = true
	body.sync_to_physics = false
	body.collision_layer = CLOTH_LAYER
	body.collision_mask = 0
	var sh := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _f("cloth_sword_radius", 0.07)
	cap.height = length + cap.radius * 2.0
	sh.shape = cap
	body.add_child(sh)
	model.add_child(body)
	_sword_cap = [body, box.get_center(), axis]
	_colliders.append([body, -1, -1])


## Верх ткани пришивается по всей ширине: точки делятся на полосы по X, в каждой пришиваются те, что у её верхнего
## края, — каждая к ближней из костей pin_bones. Позиции берутся у самих точек мягкого тела (не по номерам вершин —
## сервер физики мог сварить их по-своему). false — точки ещё не готовы.
func _pin_cloth(w: Dictionary) -> bool:
	var sb: SoftBody3D = w.cloth
	var it: Dictionary = w.item
	var xf: Transform3D = w.xform
	var n := (sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var raw := PackedVector3Array()
	var c := Vector3.ZERO
	for i: int in n:
		var p: Vector3 = sb.get_point_transform(i)
		raw.append(p)
		c += p
	if n == 0 or c == Vector3.ZERO:
		return false
	c /= float(n)
	# точки — в мире или в осях узла: что ближе к телу, то и верно
	var global := c.distance_to(model.global_position) < (xf * c).distance_to(model.global_position)
	var to_local := xf.affine_inverse()
	var strip := _iv(it, "pin_strip", 0.05)
	var band := _iv(it, "pin_band", 0.08)
	var loc := PackedVector3Array()
	var tops := {}
	for p: Vector3 in raw:
		var l := to_local * p if global else p
		loc.append(l)
		var k := int(floor(l.x / strip))
		tops[k] = maxf(float(tops.get(k, -INF)), l.y)
	var pinned := 0
	for i: int in n:
		var l := loc[i]
		if l.y < float(tops[int(floor(l.x / strip))]) - band:
			continue
		var wp := xf * l
		var best: Node3D = null
		var bd := INF
		for an: Array in w.anchors:
			var node: Node3D = an[0]
			var d := node.global_position.distance_to(wp)
			if d < bd:
				bd = d
				best = node
		sb.set_point_pinned(i, true, sb.get_path_to(best))
		pinned += 1
	_mod.log_info("Pax RPG: %s pinned %d of %d points" % [w.id, pinned, n])
	return true


## Капсулы тела за костями. Физическим телам они нужны только мягкой ткани (SoftBody3D): без неё формы выключены
## и тела не двигаются в мире физики — капсулы живут числами в _cap_* (их читает _push_out плаща).
func _move_colliders(phys: bool) -> void:
	_cache_dims(phys)
	var sg := _skel.global_transform
	for i: int in _colliders.size():
		var c: Array = _colliders[i]
		var o := Vector3(0, -1000, 0)
		var ax := Vector3.UP
		if int(c[1]) < 0:                              # меч за спиной: по его узлу; в руке — капсула убрана
			if not _sword_cap.is_empty() and _sword_back.is_visible_in_tree():
				var sx := _sword_back.global_transform
				ax = (sx.basis * (_sword_cap[2] as Vector3)).normalized()
				o = sx * (_sword_cap[1] as Vector3)
		else:
			# концы кости — только точки (без поворота и ортонормировки всей кости, как в _bone_world)
			var a := sg * _skel.get_bone_global_pose(int(c[1])).origin
			var b := sg * _skel.get_bone_global_pose(int(c[2])).origin
			var dir := b - a
			if dir.length() < 0.001:
				continue
			ax = dir.normalized()
			o = (a + b) * 0.5
		_cap_pos[i] = o
		if phys:                                       # тело в мире физики — только мягкой ткани
			var xf := Transform3D(Basis(Quaternion(Vector3.UP, ax)), o)
			_cap_axis[i] = xf.basis.y
			(c[0] as AnimatableBody3D).global_transform = xf
		else:
			_cap_axis[i] = ax                          # ось капсулы — сама ось кости (знак не важен)


func _items_tick(delta: float) -> void:
	if _skel == null or not model.is_inside_tree():
		return
	var any_cloth := false
	var soft := false                                   # мягкая ткань SoftBody3D — ей нужны капсулы в мире физики
	for w: Dictionary in _worn.values():
		if w.has("cape"):
			any_cloth = true
		elif w.cloth != null:
			any_cloth = true
			soft = true
			if int(w.pin_left) > 0:
				w.pin_left = int(w.pin_left) - 1
				if int(w.pin_left) == 0 and not _pin_cloth(w):
					w.pin_left = 1              # точки мягкого тела ещё не созданы — через кадр
				continue
			for an: Array in w.anchors:
				(an[0] as Node3D).global_transform = _bone_world(int(an[1]))
		elif w.has("follow"):
			(w.follow as Node3D).global_transform = _bone_world(int(w.bone)) * (w.rel as Transform3D)
	if any_cloth:
		_move_colliders(soft)
	for w: Dictionary in _worn.values():
		if w.has("cape"):
			_cape_tick(w, delta)


## Ткань сама тянется за телом — ветер не нужен (оставлено для location.gd).
func cape_wind(_velocity: Vector3) -> void:
	pass


# ---------- след взмаха ----------

func _make_trail() -> void:
	if _sword_hand == null:
		return
	_trail_mesh = ImmediateMesh.new()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = _trail_mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)


## Клинок в ударе (кроме финального по площади): отрезок «четверть клинка — остриё» сейчас и кадр назад, пока меч
## летит быстро. location.gd бьёт тех, через кого прошла эта полоса, — урон там и тогда, где виден взмах.
var _blade_prev: Array = []
var _swing_id := 0
var _swing_action := ""


## Активная фаза удара: клинок бьёт (и рисует след) только в окне active [с, по] секунд клипа — не на замахе
## (меч, переходя из стойки в замах, мог «чиркнуть» врага раньше удара) и не на возврате. Нет окна — весь удар.
func _active() -> bool:
	if action not in ATTACKS and action not in SPECIALS:
		return false
	var w: Variant = (cfg.get("active", {}) as Dictionary).get(action, null)
	if not (w is Array) or (w as Array).size() < 2:
		return true
	var t := _pos()
	return t >= float((w as Array)[0]) and t <= float((w as Array)[1])


func _blade_out(out: Dictionary) -> void:
	var imp: Dictionary = meta.get("impact", {})
	if not _active() or imp.has(action) or action == "Launcher" or _sword_hand == null or not _sword_hand.is_inside_tree() \
			or (cfg.get("hit_times", {}) as Dictionary).has(action):           # удары по hit_times — не ещё и клинком
		_blade_prev = []
		_swing_action = ""
		return
	if action != _swing_action or _pos() < 0.05:
		if action != _swing_action:
			_swing_id += 1
		_swing_action = action
	var g := _sword_hand.global_transform
	var tip := g * _tip
	var base := g * (_tip * 0.2)
	if not _blade_prev.is_empty():
		var fast := (tip - (_blade_prev[1] as Vector3)).length() > _f("blade_min_step", 0.04)
		if fast and not (meta.get("impact", {}) as Dictionary).has(action):   # финальный бьёт о землю (_hit) — не дважды
			out["blade"] = {"a": base, "b": tip, "pa": _blade_prev[0], "pb": _blade_prev[1], "id": _swing_id,
				"damage": _per("hit_damage", action, 15.0), "move": action}
	_blade_prev = [base, tip]


## Полоса между четвертью клинка и остриём за последние trail_life с — только в ударах и только пока меч летит
## быстро: видно дугу, которую накрывает удар.
var _trail_drawn := true


func _trail_tick(delta: float) -> void:
	if _trail_mesh == null:
		return
	_clock += delta
	var life := _f("trail_life", 0.2)
	if _active() and _sword_hand.visible and _sword_hand.is_inside_tree() and delta > 0.0 \
			and bool(_mod.get_setting("combat_fx", true)):     # настройки → «Боевые эффекты»
		var g := _sword_hand.global_transform
		var tip := g * _tip
		var base := g * (_tip * _f("trail_from", 0.66))       # след — только конец клинка, не вся длина
		var fast := true
		if not _trail.is_empty():
			var last: Array = _trail[-1]
			fast = (tip - (last[2] as Vector3)).length() / delta > _f("trail_speed", 4.0)
		if fast:
			_trail.append([_clock, base, tip])
	while not _trail.is_empty() and _clock - float((_trail[0] as Array)[0]) > life:
		_trail.pop_front()
	if _trail.size() < 2:
		if _trail_drawn:                                  # погас — очистить один раз, а не каждый кадр
			_trail_mesh.clear_surfaces()
			_trail_drawn = false
		return
	_trail_mesh.clear_surfaces()
	_trail_drawn = true
	var col: Array = cfg.get("trail_color", [0.8, 0.45, 1.0])
	var c := Color(float(col[0]), float(col[1]), float(col[2]))
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for p: Array in _trail:
		var k := clampf(1.0 - (_clock - float(p[0])) / life, 0.0, 1.0)
		_trail_mesh.surface_set_color(Color(c, 0.05 * k))
		_trail_mesh.surface_add_vertex(p[1])
		var gain := 1.0 + _f("trail_combo_gain", 0.0) * float(_combo_i)   # серия разгоняется — след ярче
		_trail_mesh.surface_set_color(Color(c, minf(1.0, _f("trail_alpha", 0.6) * gain) * k * k))
		_trail_mesh.surface_add_vertex(p[2])
	_trail_mesh.surface_end()


# ---------- удар о землю: кольцо и пыль под героем ----------

func _ground_burst() -> void:
	if not model.is_inside_tree():
		return
	var at := model.global_position + Vector3(0.0, 0.03, 0.0)
	var col: Array = cfg.get("trail_color", [0.8, 0.45, 1.0])
	var c := Color(float(col[0]), float(col[1]), float(col[2]))
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.5
	tor.rings = 48
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(c, 0.8)
	ring.material_override = rm
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(ring)
	ring.global_transform = Transform3D(Basis().scaled(Vector3(1.0, 0.15, 1.0)), at)
	var r := _f("burst_radius", 3.0)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(r, 0.15, r), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(rm, "albedo_color", Color(c, 0.0), 0.45)
	t.chain().tween_callback(ring.queue_free)
	var dust := CPUParticles3D.new()
	dust.top_level = true
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.amount = 48
	dust.lifetime = 0.8
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 0.6
	dust.emission_ring_inner_radius = 0.2
	dust.emission_ring_height = 0.05
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 75.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 4.5
	dust.gravity = Vector3(0.0, -6.0, 0.0)
	dust.damping_min = 2.0
	dust.damping_max = 4.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	dust.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	q.material = dm
	dust.mesh = q
	dust.color = Color(0.55, 0.5, 0.62, 0.55)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # прозрачная пыль тени не даёт — не в списках теней
	model.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	dust.finished.connect(dust.queue_free)


# ---------- команды ----------

## Точка кости в мире (для наручного терминала — запястье); нет кости — центр героя.
func bone_pos(bone: String) -> Vector3:
	if _skel != null:
		var bi := _skel.find_bone(bone)
		if bi >= 0:
			return _bone_world(bi).origin
	return model.global_position + Vector3(0.0, 1.0, 0.0)


func toggle_sword(on_floor: bool, moving := false) -> void:
	_cancel_hurt()
	if anim == null or action != "" or not on_floor:
		return
	var n := "Sheathe" if armed else "Draw"
	if moving and has(n + "Walk"):
		n += "Walk"
	if not has(n):
		armed = not armed
		_show_sword(0.0)
		return
	_play_once(n)


## Убрать копьё — тот же путь руки, что у Draw, задом наперёд: Draw начинается с руки у копья за спиной (там же
## висит Sword_Back), значит обратный клип кончается ровно там — копьё ложится на своё место, без скачка.
## Свой Sheathe (Cascadeur) рукой до спины не доходил. Root motion и момент «копьё — на спину» — тоже от Draw.
func _sheathe_from_draw(player: AnimationPlayer) -> void:
	if not player.has_animation("Draw"):
		return
	var src := player.get_animation("Draw")
	var rev := src.duplicate(true) as Animation
	var L := src.length
	for ti: int in rev.get_track_count():
		var keys: Array = []
		for ki: int in rev.track_get_key_count(ti):
			keys.append([L - rev.track_get_key_time(ti, ki), rev.track_get_key_value(ti, ki)])
		while rev.track_get_key_count(ti) > 0:
			rev.track_remove_key(ti, 0)
		for k: Array in keys:
			rev.track_insert_key(ti, float(k[0]), k[1])
	rev.loop_mode = Animation.LOOP_NONE
	for lib_name: StringName in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		if lib.has_animation("Sheathe"):
			lib.remove_animation("Sheathe")
		if lib.has_animation("Draw"):
			lib.add_animation("Sheathe", rev)
			break
	var rm: Dictionary = meta.get("root_motion", {})
	if rm.has("Draw"):
		var d: Dictionary = rm["Draw"]
		var off: Array = d.get("offset", [])
		var last: Array = off[off.size() - 1] if off.size() > 0 else [0.0, 0.0]
		var ro: Array = []
		for i: int in range(off.size() - 1, -1, -1):
			var o: Array = off[i]
			ro.append([float(o[0]) - float(last[0]), float(o[1]) - float(last[1])])
		rm["Sheathe"] = {"fps": d.get("fps", 30), "frames": d.get("frames", off.size()), "offset": ro}
	var sw: Dictionary = meta.get("sword_switch", {})
	sw["Sheathe"] = {"time": L * 0.96}
	meta["sword_switch"] = sw


## Реакция на удар (Hurt) — только картинка: любое действие или шаг её прерывают, управление не отнимается.
func _cancel_hurt() -> void:
	if action == "Hurt" or (action in ["Parry", "BlockHit"] and _pos() > _f("react_cancel", 0.22)):
		action = ""


var lunge_t := 0.0                   # с: «Выпад» несёт героя вперёд (location.gd)
var _last_attack := ""
var _last_end_ms := 0


## Приём комбо kind (SPECIALS): из стойки или сразу после удара серии.
func special(kind: String, on_floor: bool) -> bool:
	_cancel_hurt()
	_cancel_recovery()
	if anim == null or not armed or not on_floor or action != "" or not SPECIAL_CLIPS.has(kind):
		return false
	var sc: Array = SPECIAL_CLIPS[kind]
	var clip := str(sc[0])
	if not has(clip):
		clip = "Attack2"
	blocking = false
	_play_once(kind, float(sc[1]), clip)
	if kind == "Lunge":
		lunge_t = _f("lunge_time", 0.28)
	return true


## «Пауза»: после второго удара серии выдержать паузу (pause_min..pause_max с) и ударить — тяжёлая концовка.
func pause_finisher_ready() -> bool:
	var dt := (Time.get_ticks_msec() - _last_end_ms) / 1000.0
	return action == "" and _last_attack != "" and _last_i == 1 and dt >= _f("pause_min", 0.35) and dt <= _f("pause_max", 1.1)


func attack(on_floor: bool) -> void:
	_cancel_hurt()
	blocking = false
	if anim == null or not has("Attack1"):
		return
	if action == "ComboEnd" and _combo_left > 0.0 and _frac() < _per("combo_end_resume", "ComboEnd", 0.5):
		action = ""                         # выход из комбо ещё в начале — ЛКМ продолжает серию
	elif action == "ComboEnd":
		_end_action()                       # позже — новая серия сразу, без ожидания конца клипа
	if action == "" and on_floor:
		if not armed:
			toggle_sword(on_floor)          # меч за спиной — сперва достать
			return
		if _combo_left > 0.0 and _combo_next != "" and has(_combo_next):
			_combo_i = _combo_next_i
			var cn := _side_clip(_combo_i)
			_play_once(cn, _per("combo_skip", cn, 0.0))   # успел после конца удара
		else:
			# с бега — как в соулсах: без раскачки, клинок летит сразу (инерция бега уже есть)
			_combo_i = 0
			_play_once(_side_clip(0), _f("run_attack_skip", 0.3) if _running else 0.0)
	elif action in ATTACKS and _combo_i < ATTACKS.size() - 1:
		_queued = true                      # следующий удар — сразу после взмаха этого


## Уворот (Alt): кувырок туда, куда смотрит герой (location.gd разворачивает его по направлению ввода).
## С мечом — свой клип, тяжелее и дальше. dir — в захвате цели, лицом к врагу: "B" — отскок назад, "L"/"R" — уклон
## вбок (клипы DodgeBack / DodgeL / DodgeR; нет клипа — обычный кувырок).
func dodge(on_floor: bool, dir := "") -> bool:
	_cancel_hurt()
	if action == "ComboEnd":
		_end_action()                       # выход из комбо — не помеха: уворот сразу
	_cancel_recovery()
	if anim == null or not on_floor or action != "":
		return false
	var n := "DodgeArmed" if armed and has("DodgeArmed") else "Dodge"
	var side := {"B": "DodgeBack", "L": "DodgeL", "R": "DodgeR"}
	if side.has(dir) and has(str(side[dir])):
		n = str(side[dir])
	if not has(n):
		return false
	# с мечом — свой клип (меч прижат к телу); root motion — общий у пары (action — без «Armed»)
	var clip := n + "Armed" if armed and n != "DodgeArmed" and has(n + "Armed") else n
	_play_once(n, _per("clip_skip", n, 0.0), clip)   # без раскачки перед кувырком — уворот срабатывает сразу
	return true


## Во время кувырка удары проходят мимо (i-frames).
func invulnerable() -> bool:
	return action.begins_with("Dodge") or action in ["Knocked", "GetUp", "Bloodthirsty"]


## Уворот в стороны (не кувырок вперёд) — location.gd держит героя лицом к врагу.
func side_dodge() -> bool:
	return action in ["DodgeBack", "DodgeL", "DodgeR"]


## Попадание: клипы замирают на миг (вес удара).
func hitstop(t: float) -> void:
	if anim != null:
		anim.hitstop(t, _f("hitstop_scale", 0.05))


## Сбит с ног (таран орка): падение, потом подъём; пока лежит — неуязвим и без управления.
func knock_down() -> void:
	if anim == null or not has("Knocked"):
		hurt()
		return
	blocking = false
	_play_once("Knocked")


## Получил удар: клип Hurt (если есть в модели) — короткая реакция, не сбивает уворот и удар финала.
func hurt() -> void:
	if anim == null or not has("Hurt") or action != "":
		return                                   # удар, уворот, доставание не сбиваются
	_play_once("Hurt")


## Прыжок: анимация с момента отрыва (без долгого приседа), отрыв — сразу (tick вернёт jump).
func jump(on_floor: bool) -> bool:
	_cancel_hurt()
	if action == "ComboEnd":
		_end_action()
	if anim == null or not on_floor or (action != "" and action != "Jump"):
		return false
	if has("Jump"):
		# с мечом — свой прыжок: обе руки на рукояти, меч прижат к телу
		_play_once("Jump", _f("jump_skip", 0.05), "JumpArmed" if armed and has("JumpArmed") else "Jump")
	_airborne = false
	return true


var _clip := ""                       # клип разового действия (у прыжка с мечом — свой клип при том же action)


## Клип удара серии по стороне врага: первые два удара — взмахи в разные стороны (Attack1 справа налево, Attack2 слева
## направо, по клинку в knight.glb), берём тот, что идёт ко врагу; финальный — всегда свой.
func _side_clip(i: int) -> String:
	if i >= 2 or swing_side == 0 or not bool(cfg.get("side_swings", true)):
		return ATTACKS[i]                    # своя серия (Тянь Лун) — удары всегда по порядку
	return "Attack1" if swing_side < 0 else "Attack2"


func _play_once(n: String, skip := 0.0, clip := "") -> void:
	action = n
	_clip = clip if clip != "" else n
	_queued = false
	_prev_off = Vector2.ZERO
	_swing_id += 1                         # новый взмах — даже тот же клип подряд (удар по стороне врага) ранит снова
	_swing_action = n
	_swing_done = false
	_hit_done = false
	_hits_done = 0
	_lands_done = 0
	_impact_done = false
	anim.speed_scale = _per("attack_speed", n, 1.0) * (_f("tired_speed", 0.85) if tired else 1.0) if n in ATTACKS 		else _per("clip_speed", n, 1.0)
	anim.play(_clip, _per("blend_in", n, 0.15))
	if skip > 0.0:
		anim.seek(skip, true)
		_prev_off = _root_at(skip)


func _on_finished(n: StringName) -> void:
	if String(n) == action or String(n) == _clip:
		_end_action()


func _end_action() -> void:
	if action in ATTACKS:
		_last_attack = action
		_last_i = _combo_i
		_last_end_ms = Time.get_ticks_msec()
	elif action != "":
		_last_attack = ""
	if action == "Knocked" and has("GetUp"):
		_play_once("GetUp")
		return
	if action.begins_with("Draw"):
		armed = true
	elif action.begins_with("Sheathe"):
		armed = false
	var i := _combo_i if action in ATTACKS else -1
	if i >= 0 and i + 1 < ATTACKS.size():
		_combo_next = ATTACKS[i + 1]
		_combo_next_i = i + 1
		_combo_left = _f("combo_grace", 0.45)
	else:
		_combo_left = 0.0
	action = ""


func _pos() -> float:
	return anim.current_animation_position if anim != null and anim.current_animation != "" else 0.0


func _frac() -> float:
	if anim == null or anim.current_animation == "":
		return 1.0
	return _pos() / maxf(anim.current_animation_length, 0.001)


# ---------- кадр ----------

## Возвращает {"root": Vector3 — смещение за кадр в осях модели (модель смотрит на +Z)}.
func tick(delta: float, moving: bool, speed: float, running: bool, on_floor: bool) -> Dictionary:
	var out := {"root": Vector3.ZERO}
	if anim == null:
		return out
	_running = running and moving and on_floor and action == ""
	if action == "Quake":
		_quake_tick(delta)
	elif action == "Ultimate":
		_ult_tick(delta)
	elif action == "Finisher":
		_fin_tick()
	elif action == "Iai":
		_iai_tick()
	_combo_left = maxf(0.0, _combo_left - delta)
	lunge_t = maxf(0.0, lunge_t - delta)
	if blocking:
		_block_t += delta
	# выход из комбо доигрывается и на ходу (герой уже идёт — управление не забрано, locks_move); оборвать его
	# могут только удар, уворот, блок и прыжок
	if moving and (action == "Hurt" or (action in ["Parry", "BlockHit"] and _pos() > _f("react_cancel", 0.22))):
		_end_action()                        # пошёл — реакция на удар обрывается, ходьба сливается плавно
	if action != "" and action != "Iai" and action != "Ultimate" and not anim.is_playing():
		_end_action()                        # сигнал конца не пришёл — не застрять (Иай ведёт стадии сам)
	if action in ATTACKS:
		var i := _combo_i
		# комбо: следующий удар — с точки отмены, и сразу с замаха, без долгой подготовки
		if _queued and _frac() >= _per("combo_cancel", action, 0.4) and i + 1 < ATTACKS.size() and has(ATTACKS[i + 1]):
			_combo_i = i + 1
			var nxt := _side_clip(_combo_i)
			_play_once(nxt, _per("combo_skip", nxt, 0.0))
		elif not _queued and _frac() >= _per("attack_end", action, 0.5):
			if bool(cfg.get("combo_end", false)) and has("ComboEnd"):
				_end_action()                # серия оборвалась — выход из комбо своим клипом (обратно в стойку)
				_play_once("ComboEnd")
			else:
				_end_action()                # без продолжения — сразу в стойку, управление вернулось
	if action in ATTACKS:
		# прыжок удара (air: [с, по, во сколько медленнее]) — герой дольше висит в воздухе
		var air: Variant = (cfg.get("air", {}) as Dictionary).get(action, [])
		if air is Array and (air as Array).size() == 3:
			var t := _pos()
			var a0 := float(air[0])
			var a1 := float(air[1])
			var k := smoothstep(a0, a0 + 0.12, t) * (1.0 - smoothstep(a1 - 0.12, a1, t))
			anim.speed_scale = _per("attack_speed", action, 1.0) * lerpf(1.0, float(air[2]), k)
	if action == "Jump":
		if not on_floor:
			_airborne = true
		elif _airborne:
			_end_action()                    # приземлился — амортизация (присед), потом ходьба или стойка
			if has("JumpLand"):
				_play_once("JumpLand", 0.0, "JumpLandArmed" if armed and has("JumpLandArmed") else "JumpLand")
	if action != "":
		_sounds()
		_hit(out)
		_land_steps(out)
		out.root = _root_step()
	else:
		_loop(moving, speed, running)
		_loop_steps(out, (moving or anim.current_animation == "RunStop") and on_floor)
	_on_floor = on_floor
	_show_sword(delta)
	_face_tick(delta)
	_trail_tick(delta)
	_blade_out(out)
	if not cloth_paused:
		var t0 := Time.get_ticks_usec()
		_items_tick(delta)
		Prof.add("плащ", t0)
	return out


func _loop(moving: bool, speed: float, running: bool) -> void:
	var want := "IdleArmed" if armed and has("IdleArmed") else "Idle"
	if armed and combat and has("CombatIdle") and bool(cfg.get("combat_stance", true)):   # Тян Лун — без: стойка = конец Draw и ComboEnd
		want = "CombatIdle"
	var stride := 1.0
	if blocking and has("Block"):
		# блок: меч двумя руками поперёк перед собой; на ходу — ноги шагают, руки держат блок
		want = "Block"
		if moving and anim.has_space("BlockMove"):
			# шаг в блоке: вперёд/назад/вбок смешиваются по направлению — без рывка на диагонали
			want = "BlockMove"
			anim.set_blend(want, move_dir.normalized())
			stride = _f("stride_block", 1.1)
		elif moving:
			_update_sector()
			want = "BlockWalk" + _dir_sector
			stride = _f("stride_back", 1.0) if _dir_sector == "B" else (_f("stride_strafe", 1.0)
				if _dir_sector in ["L", "R"] else _f("stride_walk_armed", 1.3))
			if not has(want):
				want = "Block"
		if anim.current_animation != want or not anim.is_playing():
			anim.play(want, _f("block_blend", 0.1))
		anim.speed_scale = clampf(speed / stride, 0.25, 2.0) if moving and want != "Block" else 1.0
		return
	if moving:
		if running:
			want = "RunArmed" if armed and has("RunArmed") else "Run"
			stride = _f("stride_run_armed", 3.2) if want == "RunArmed" else _f("stride_run", 4.0)
			if want == "Run" and has("RunStart"):        # вход в бег: с места или с шага — разгон, потом цикл
				var cur := anim.current_animation
				if (cur == "RunStart" and anim.is_playing()) or (cur not in ["Run", "RunStart", "RunStop"]):
					want = "RunStart"
		elif (armed and anim.has_space("Lock")) or (lock_on and anim.has_space("LockU")):
			# шаг лицом к цели (с мечом — всегда: тело смотрит туда же, куда камера; без меча — в захвате):
			# клипы вперёд / назад / влево / вправо смешиваются по направлению шага, как в соулсах
			want = "Lock" if armed and anim.has_space("Lock") else "LockU"
			anim.set_blend(want, move_dir.normalized())
			stride = _f("stride_lock", 1.2) if want == "Lock" else _f("stride_lock_unarmed", 1.4)
		else:
			_update_sector()
			match _dir_sector:
				"B":
					want = "GuardBack" if armed else "WalkBack"
					stride = _f("stride_back", 1.0)
				"L":
					want = "GuardStrafeL" if armed else "StrafeL"
					stride = _f("stride_strafe", 1.0)
				"R":
					want = "GuardStrafeR" if armed else "StrafeR"
					stride = _f("stride_strafe", 1.0)
				_:
					want = ""
			if want == "" or not has(want):
				want = "WalkArmed" if armed and has("WalkArmed") else "Walk"
				stride = _f("stride_walk_armed", 1.3) if want == "WalkArmed" else _f("stride_walk", 1.5)
	elif not blocking and has("RunStop") and not armed:  # выход из бега: остановился на бегу — торможение до стойки
		var cur := anim.current_animation
		if cur in ["Run", "RunStart"] or (cur == "RunStop" and anim.is_playing()):
			want = "RunStop"
	if want in ["RunStart", "RunStop"]:
		if anim.current_animation != want:
			anim.play(want, _f("blend_run_edge", 0.15))
		anim.speed_scale = 1.0                         # разгон и торможение — в темпе клипа
		_still = -1.0
		return
	if anim.current_animation != want or not anim.is_playing():
		var bl := _f("blend_loop", 0.3)
		if anim.current_animation == "RunStart" and want == "Run":
			bl = _f("blend_run_in", 0.06)        # конец разгона = начало цикла — почти без смешивания
		if want == "RunArmed" or anim.current_animation == "RunArmed":
			bl = _f("blend_run_armed", 0.5)      # рука с мечом уходит вниз-назад — не рывком
		elif want == "CombatIdle" or anim.current_animation == "CombatIdle":
			bl = _f("blend_stance", 0.45)        # приседает в стойку и выпрямляется плавно
		if anim.current_animation in ["Block", "BlockMove"]:
			bl = maxf(bl, _f("block_blend_out", 0.25))   # меч из вертикали блока в стойку — без рывка через горизонталь
		# меч на плечо (бег) и обратно — через позу «меч вертикально перед грудью», не сквозь корпус
		var shoulder_a := anim.current_animation == "RunArmed"
		var shoulder_b := want == "RunArmed"
		if armed and shoulder_a != shoulder_b and anim.current_animation != "" and has("SwordFront"):
			anim.via("SwordFront", maxf(bl, _f("via_time", 0.4)))
			bl = maxf(bl, _f("via_time", 0.4))
		anim.play(want, bl)
	if want.begins_with("GuardStrafe") and moving and strafe_speed() >= 0.0:
		anim.speed_scale = 1.0                         # шаг вбок — клип в своём темпе, герой идёт за ним (strafe_speed)
	elif not moving and want == "Idle":
		anim.speed_scale = _idle_scale()
	else:
		anim.speed_scale = clampf(speed / stride, 0.25, 2.0) if moving else _f("idle_speed", 1.0)   # стойка/idle — медленнее
	if moving or want != "Idle":
		_still = -1.0


## Без дела: стойка (первый кадр Idle), и только раз в idle_every (20–30 с) — сам клип Idle, один раз.
func _idle_scale() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	if _still < 0.0:
		_still = now
		_fidget_at = now + randf_range(_f("idle_every_min", 20.0), _f("idle_every_max", 30.0))
		_fidget_pos = 0.0
		_still_held = false
	# пока идёт переход в стойку — время течёт: масштаб 0 у loop_ts замораживает и сам кроссфейд, и герой застывал
	# между прежним клипом и стойкой (при появлении — в позе первой петли, после шага — в последнем кадре шага)
	if now - _still < _f("idle_hold_after", 0.6):
		return 1.0
	if not _still_held:
		_still_held = true
		anim.seek(0.0, true)
	if now < _fidget_at:
		return 0.0
	var p := anim.current_animation_position
	if p + 0.05 < _fidget_pos:                       # клип прошёл круг — снова стойка до следующего раза
		_fidget_at = now + randf_range(_f("idle_every_min", 20.0), _f("idle_every_max", 30.0))
		_fidget_pos = 0.0
		anim.seek(0.0, true)
		return 0.0
	_fidget_pos = p
	return _f("idle_speed", 1.0)


## Шаг вбок с оружием: скорость героя — как у ног в клипе в этот миг (root motion клипа, м/с), а не ровная;
## -1 — сейчас не шаг вбок или у клипа нет хода.
func strafe_speed() -> float:
	if anim == null or not anim.current_animation.begins_with("GuardStrafe"):
		return -1.0
	var rm: Dictionary = meta.get("root_motion", {})
	var clip: Dictionary = rm.get(anim.current_animation, rm.get("GuardStrafeL", {}))
	var off: Array = clip.get("offset", [])
	if off.size() < 2:
		return -1.0
	var fps := float(clip.get("fps", 30))
	var i := clampi(int(anim.current_animation_position * fps), 0, off.size() - 2)
	var a: Array = off[i]
	var b: Array = off[i + 1]
	return Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).length() * fps * _f("strafe_speed_scale", 1.0)


## Направление шага по move_dir: ближайшее из вперёд / вправо / назад / влево, но меняется, только когда новое
## заметно ближе (на диагонали клип не мигает).
func _update_sector() -> void:
	var ang := rad_to_deg(atan2(move_dir.x, move_dir.y))   # 0 — вперёд, 90 — вправо, ±180 — назад
	var centers := {"F": 0.0, "R": 90.0, "B": 180.0, "L": -90.0}
	var best := _dir_sector
	var best_d := absf(wrapf(ang - float(centers[_dir_sector]), -180.0, 180.0)) - 20.0
	for k: String in centers:
		var d := absf(wrapf(ang - float(centers[k]), -180.0, 180.0))
		if d < best_d:
			best_d = d
			best = k
	_dir_sector = best


## ПКМ: нажал — блок (и первые parry_window с — парирование, как в Sekiro), отпустил — снял.
func set_block(on: bool) -> void:
	if on and not blocking:
		_cancel_hurt()
		_cancel_recovery()                           # из отката удара — сразу в блок (как в Sekiro)
		if action == "ComboEnd":
			_end_action()
		if not armed or (action != "" and action not in ["Jump"]):
			return
		blocking = true
		_block_t = 0.0
		if has("Block"):
			anim.play("Block", _f("block_blend", 0.1))   # меч поднимается в блок быстро — иначе не успеть
			anim.speed_scale = 1.0
	elif not on:
		blocking = false


## Удар уже нанесён (клинок прошёл пик) — откат можно прервать блоком или кувырком; замах — нельзя.
## Порог — доля клипа recover_cancel (по ударам), финальный по площади — только после касания земли.
func _cancel_recovery() -> void:
	if action not in ATTACKS and action not in SPECIALS:
		return
	var imp: Dictionary = meta.get("impact", {})
	var from := _per("recover_cancel", action, 0.42)
	var peak := _per("swing_peaks", action, -1.0)
	if peak >= 0.0:                              # не раньше, чем клинок прошёл пик взмаха (иначе блок съедает удар)
		from = maxf(from, (peak + _f("recover_after_peak", 0.2)) / maxf(anim.current_animation_length, 0.01))
	if imp.has(action):
		from = maxf(from, float(imp[action]) / maxf(anim.current_animation_length, 0.01) + 0.05)
	if _frac() >= from:
		_combo_left = 0.0
		action = ""
		_blade_prev = []


## Спецприём «Земной разлом» (震): клип Deathblow — меч над головой и вонзить в землю, герой на колене; в миг
## удара клип замирает на quake_hold с, пока по земле идут волны (их бьёт location.gd), потом встаёт.
var quake_since := -1.0
# ультимейт Разрубателя «Сокрушение» (G): разбег → удар сверху в землю → встаёт, держась за рукоять → кувырок → выпад.
# Стадии ведёт _ult_tick; ult_dash — разбег (location.gd толкает героя вперёд); ult_hit — 1/2: удар о землю (волна).
var ult_dash := false
var ult_hit := 0
var ult_leap := false                # кувырок в воздухе: location.gd подбрасывает героя (один раз) и несёт вперёд
var ult_air := false                 # стадия прыжка идёт — location.gd толкает вперёд
var ult_landed := false              # location.gd: герой на земле (после прыжка — выпад)
var _ult_stage := -1
var _ult_t := 0.0
const ULT_DASH := 0.55               # с от удара меча о землю (−1 — ещё не ударил / приём не идёт)


## Бежит ли герой сейчас (бег, не шаг) — ультимейт только с разбега.
func is_running() -> bool:
	return _running


func ult_begin(on_floor: bool, spear := false) -> bool:
	_cancel_hurt()
	_cancel_recovery()
	if spear and has("UltSpear"):                      # копьё (Тян Лун): кат-сцена «Алый Закат» — клип + spear_ult.gd
		if anim == null or not on_floor or action != "":
			return false
		armed = true
		blocking = false
		action = "Ultimate"
		_clip = ""
		_ult_stage = 30
		_ult_t = 0.0
		ult_hit = 0
		ult_dash = false
		ult_leap = false
		ult_air = false
		var rms: Dictionary = meta.get("root_motion", {})
		if rms.has("UltSpear"):
			rms["Ultimate"] = rms["UltSpear"]
		_ult_play("UltSpear", 0.0, 1.0)
		return true
	if anim == null or not armed or not on_floor or action != "" or not has("HeavySlash") or not has("Attack3"):
		return false
	blocking = false
	action = "Ultimate"
	_clip = ""                                        # конец промежуточного клипа не обрывает приём (_on_finished)
	_ult_stage = 0
	_ult_t = 0.0
	ult_hit = 0
	ult_dash = true
	ult_leap = false
	ult_air = false
	_prev_off = Vector2.ZERO
	anim.speed_scale = 1.0
	if has("UltCrush"):                                # свой клип: разбег → меч в землю → стойка на рукояти → прыжок → удар
		_ult_stage = 20
		ult_dash = false                               # двигает root motion клипа (meta root_motion → «Ultimate»)
		_ult_start = _owner_body.global_transform if _owner_body != null else model.global_transform
		var rm: Dictionary = meta.get("root_motion", {})
		if rm.has("UltCrush"):
			rm["Ultimate"] = rm["UltCrush"]
		_ult_play("UltCrush", 0.0, _f("ultc_speed", 1.0))
		return true
	anim.play("Sprint" if has("Sprint") else "RunArmed", 0.1)
	return true


## Секунда клипа ультимейта (spear_ult.gd ведёт по ней кат-сцену).
func ult_time() -> float:
	return _pos() if action == "Ultimate" else 99.0


func _ult_play(clip: String, skip := 0.0, speed := 1.0) -> void:
	anim.speed_scale = speed
	anim.play(clip, 0.1)
	if skip > 0.0:
		anim.seek(skip, true)
	_prev_off = _root_at(skip)


func _ult_tick(delta: float) -> void:
	_ult_t += delta
	var length := anim.current_animation_length
	match _ult_stage:
		30:                                           # копьё: сцену ведёт spear_ult.gd, тут — только конец клипа
			if _pos() >= length - 0.03 or _ult_t > length * 5.0:   # по клипу: в сцене замедления
				_ult_stage = -1
				_end_action()
		20:                                           # клип UltCrush: меч воткнут — стоит на рукояти — выдернул — удар о землю
			var slam := _f("ultc_slam", 3.5)
			ult_dash = false
			ult_air = false
			var tp := _f("ultc_plant", 0.9)
			var toff := _f("ultc_pull", 3.1)
			_ult_flip(clampf((_ult_t - toff) / maxf(0.05, slam - toff), 0.0, 1.0))   # сальто: на вершине — вниз головой
			if _ult_t >= tp and _ult_t < toff:
				_plant_sword()
				_tip_planted(clampf((_ult_t - (toff - _f("ultc_tip_time", 0.4))) / _f("ultc_tip_time", 0.4), 0.0, 1.0))
			elif _planted != null:
				_planted.queue_free()                     # выдернул — меч снова в руке
				_planted = null
			if ult_hit == 0 and _ult_t >= slam:
				ult_hit = 1
			elif ult_hit == 1 and _ult_t >= slam + 0.18:
				ult_hit = 2                           # вторая, сильнее — от вбитого меча
			if _pos() >= length - 0.05 or _ult_t > length + 0.3:
				if _planted != null:
					_planted.queue_free()
					_planted = null
				_ult_flip(1.0)
				_ult_stage = -1
				ult_dash = false
				ult_air = false
				ult_hit = 0
				_end_action()
		0:                                            # разбег
			if _ult_t >= ULT_DASH:
				ult_dash = false
				_ult_stage = 1
				_ult_t = 0.0
				_ult_play("HeavySlash", 0.15, 1.15)
		1:                                            # удар сверху — меч в землю
			if _pos() >= length * _f("ult_slam_at", 0.52) and ult_hit == 0 and _ult_t > 0.1:
				ult_hit = 1
				anim.speed_scale = 0.0                # меч в земле, вес на рукояти
				_ult_stage = 2
				_ult_t = 0.0
		2:                                            # миг на мече
			if _ult_t >= 0.4:
				_ult_stage = 3
				_ult_t = 0.0
				if has("Deathblow"):                  # встаёт, держась за рукоять (вторая половина добивания)
					_ult_play("Deathblow", anim.get_animation("Deathblow").length * _f("quake_plunge", 0.43) + 0.05, 1.3)
				else:
					_ult_stage = 4
		3:                                            # встаёт рывком — сразу в прыжок (не досматривая подъём)
			if _pos() >= length * 0.55 or _ult_t > 0.9:
				_ult_stage = 4
				_ult_t = 0.0
				ult_leap = true
				ult_air = true
				_ult_play("DodgeArmed" if has("DodgeArmed") else "Dodge", 0.0, 0.85)   # кувырок в воздухе с мечом
		4:                                            # в воздухе — до приземления
			if (_ult_t > 0.3 and ult_landed) or _ult_t > 1.6:
				ult_air = false
				_ult_stage = 5
				_ult_t = 0.0
				_ult_play("Attack3", 0.35, 1.2)        # резкий выпад: без долгого замаха
		5:
			var imp := float((meta.get("impact", {}) as Dictionary).get("Attack3", 1.03))
			if ult_hit < 2 and _pos() >= imp:
				ult_hit = 2
			if _pos() >= length - 0.05 or _ult_t > 2.5:
				_ult_stage = -1
				ult_dash = false
				ult_air = false
				ult_hit = 0                           # иначе location.gd видит «новый удар» каждый кадр — волны без конца
				_end_action()


# финишер серии (5 ударов подряд): отскок назад → горизонтальный разрез двумя руками (клип HeavyAttack — клинок
# идёт поперёк на уровне пояса) → волна разреза (location.gd → slash_wave). fin_back — отскок идёт (location.gd толкает).
var fin_back := false
var slash_wave := false
var _fin_stage := -1
var _fin_waved := false


func combo_finisher(on_floor: bool) -> bool:
	if anim == null or not armed or not on_floor or not has("HeavyAttack"):
		return false
	blocking = false
	action = "Finisher"
	_clip = ""
	_fin_stage = 0
	fin_back = true
	slash_wave = false
	_fin_waved = false
	_prev_off = Vector2.ZERO
	var back := "DodgeBackArmed" if has("DodgeBackArmed") else ("DodgeBack" if has("DodgeBack") else "")
	if back != "":
		_ult_play(back, 0.0, 1.0)
	return true


func _fin_tick() -> void:
	var length := anim.current_animation_length
	match _fin_stage:
		0:
			if _pos() >= length * 0.85 or not has("DodgeBack"):
				fin_back = false
				_fin_stage = 1
				_ult_play("HeavyAttack", _f("fin_skip", 0.25), _f("fin_speed", 1.2))
		1:
			if not _fin_waved and _pos() >= length * _f("fin_slash_at", 0.38):
				_fin_waved = true
				slash_wave = true                     # location.gd пускает волну и сбрасывает флаг
			if _pos() >= length - 0.05:
				_fin_stage = -1
				fin_back = false
				_end_action()


var _model_base := Transform3D.IDENTITY
var _flipping := false


## Сальто вокруг таза (k 0..1 — полный оборот назад-вперёд); 0 или 1 — модель на месте.
func _ult_flip(k: float) -> void:
	if not _flipping:
		if k <= 0.0 or k >= 1.0:
			return
		_model_base = model.transform
		_flipping = true
	if k <= 0.0 or k >= 1.0:
		model.transform = _model_base
		_flipping = false
		return
	var hip := Vector3(0, _f("flip_pivot", 1.0), 0)          # от стоп до таза
	var e := smoothstep(0.0, 1.0, k)
	var r := Transform3D(Basis(Vector3.RIGHT, TAU * e), Vector3.ZERO)
	model.transform = _model_base * Transform3D(Basis(), hip) * r * Transform3D(Basis(), -hip)


var _ult_start := Transform3D.IDENTITY
var _planted: MeshInstance3D
var _planted_base := Transform3D.IDENTITY
var _planted_pivot := Vector3.ZERO


## Весом тела рыцарь валит воткнутый меч вперёд (k 0..1 → до ultc_tip_deg°) — вокруг точки, где клинок входит в землю.
func _tip_planted(k: float) -> void:
	if _planted == null:
		return
	var fwd := _ult_start.basis.z.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var ang := deg_to_rad(_f("ultc_tip_deg", 55.0)) * smoothstep(0.0, 1.0, k)
	var r := Transform3D(Basis(right, ang), Vector3.ZERO)
	_planted.global_transform = Transform3D(Basis(), _planted_pivot) * r * Transform3D(Basis(), -_planted_pivot) * _planted_base


## Меч воткнут остриём в землю там, куда встанут стопы (knight_anim.json → ult_pole: x, z от начала приёма,
## top — высота стоп); рукоять — вверх, под ногами. Меч в руке пока скрыт (_show_sword).
func _plant_sword() -> void:
	if _planted != null or _sword_hand == null or not (_sword_hand is MeshInstance3D):
		return
	var pole: Dictionary = meta.get("ult_pole", {})
	if pole.is_empty() or _owner_body == null:
		return
	var world := _owner_body.get_parent()
	_planted = MeshInstance3D.new()
	_planted.mesh = (_sword_hand as MeshInstance3D).mesh
	world.add_child(_planted)
	var spot := _ult_start * Vector3(float(pole.get("x", 0.0)), 0.0, float(pole.get("z", 1.8)))
	var top := _ult_start.origin.y - _f("capsule_height", 1.9) * 0.5 + float(pole.get("top", 1.6)) - _f("ultc_sole", 0.08)
	var tl := _tip.normalized()                              # клинок в осях меча — вниз, в землю
	var sc := _sword_hand.global_transform.basis.get_scale()
	var bs := Basis(Quaternion(tl, Vector3.DOWN)).scaled_local(sc)
	var handle := 0.0                                        # длина рукояти над хватом (навершие — под стопами)
	var box := _planted.mesh.get_aabb()
	for i: int in 8:
		handle = maxf(handle, box.get_endpoint(i).dot(-tl))
	var up := (bs * (-tl * handle)).length()
	_planted.global_transform = Transform3D(bs, Vector3(spot.x, top - up, spot.z))
	_planted_base = _planted.global_transform
	_planted_pivot = Vector3(spot.x, _ult_start.origin.y - _f("capsule_height", 1.9) * 0.5, spot.z)


func quake(on_floor: bool) -> bool:
	_cancel_hurt()
	_cancel_recovery()
	if anim == null or not armed or not on_floor or action != "" or not has("Deathblow"):
		return false
	blocking = false
	action = "Quake"
	quake_since = -1.0
	_prev_off = Vector2.ZERO
	anim.play("Deathblow", 0.15)
	anim.speed_scale = _f("quake_speed", 1.0)
	return true


func _quake_tick(delta: float) -> void:
	var length := anim.current_animation_length
	var plunge := _f("quake_plunge", 0.43) * length
	if quake_since < 0.0:
		if _pos() >= plunge:
			quake_since = 0.0
			anim.speed_scale = 0.0                   # замер: на колене, меч в земле
	else:
		quake_since += delta
		if quake_since >= _f("quake_hold", 2.35):
			anim.speed_scale = _f("quake_speed", 1.0)
		if _pos() >= length - 0.03:
			quake_since = -1.0
			_end_action()


## Иай (iai.gd): IaiKneel — на колено, IaiHold — петля (дыхание, большой палец выталкивает цубу), пока идёт приём;
## iai_end — IaiRise, встать. Клипы — pax_rpg/dev/blender/knight/iai_clips.py (Mixamo Kneeling Down / Standing).
var _iai_stage := 0                                  # 0 — садится, 1 — держит, 2 — встаёт


func iai_begin() -> bool:
	_cancel_hurt()
	_cancel_recovery()
	if action.begins_with("Draw") or action.begins_with("Sheathe"):
		_end_action()                                # приём важнее — меч «долетит» сам
	if anim == null or action != "" or not has("IaiKneel"):
		return false
	blocking = false
	action = "Iai"
	_iai_stage = 0
	_prev_off = Vector2.ZERO
	anim.get_animation("IaiHold").loop_mode = Animation.LOOP_LINEAR
	anim.play("IaiKneel", 0.15)
	anim.speed_scale = _f("iai_speed", 1.4)
	return true


func _iai_tick() -> void:
	var over := not anim.is_playing() or _pos() >= anim.current_animation_length - 0.02
	if _iai_stage == 0 and over:
		_iai_stage = 1
		anim.play("IaiHold", 0.1)
		anim.speed_scale = 1.0
	elif _iai_stage == 2 and over:
		_end_action()


## Сидя: убрать катану в ножны (клип IaiSheathe), потом iai_end — встать.
func iai_sheathe() -> void:
	if action != "Iai" or not has("IaiSheathe"):
		return
	_iai_stage = 3
	anim.play("IaiSheathe", 0.25)
	anim.speed_scale = 1.0


func iai_end() -> void:
	if action != "Iai":
		return
	_iai_stage = 2
	anim.play("IaiRise", 0.15)
	anim.speed_scale = _f("iai_rise_speed", 1.2)


## Узел, который ходит за костью (крепить предметы: катана у бедра).
func bone_holder(bone: String) -> Node3D:
	if _skel == null or _skel.find_bone(bone) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	_skel.add_child(ba)
	return ba


func parry_window() -> bool:
	return blocking and _block_t <= _f("parry_window", 0.25)


## Парировал: меч вздрагивает в блоке (как от удара о сталь). Окно парирования не продлевается — следующий удар
## надо ловить новым нажатием, как в Sekiro.
func deflect() -> void:
	if anim != null and anim.current_animation == "Block":
		anim.seek(0.0, true)


## Удар по блоку (и парирование): отдача — героя сдвигает назад, корпус откидывается за мечом и возвращается
## (клип BlockHit, сдвиг — его root motion). Блок не снимается.
func block_hit(heavy: bool) -> void:
	if anim == null or not has("BlockHit") or (action != "" and action != "BlockHit"):
		return
	var keep := blocking
	_play_once("BlockHit")
	anim.speed_scale = _per("clip_speed", "BlockHit", 1.0) * (0.8 if heavy else 1.0)
	blocking = keep


## Парировал: клип Parry (короткий отбив оружием), блок остаётся; нет клипа — меч вздрагивает в блоке.
func parry_anim() -> void:
	if anim == null:
		return
	if not has("Parry") or (action != "" and action not in SOFT):
		deflect()
		return
	var keep := blocking
	_play_once("Parry")
	blocking = keep


## Концентрация на нуле: шатается и падает на колено (Stagger), встаёт сам; управление отнято (location.gd — 2.6 с).
func stagger() -> void:
	if anim == null:
		return
	if action == "ComboEnd" or action in SOFT or action in ATTACKS or action in SPECIALS or action.begins_with("Dodge") 			or action.begins_with("Draw") or action.begins_with("Sheathe") or action == "Jump":
		_end_action()
	if action != "":
		return                                       # кат-сцена (ульта, иай) — её не рвём
	blocking = false
	if has("Stagger"):
		_play_once("Stagger")
	else:
		hurt()


## Кровожадная атака (концентрация врага на нуле): свой клип (у Тянь Луна — укол Bloodthirsty), иначе добивание
## Deathblow. Возвращает секунду клипа, когда оружие в теле (−1 — не началась).
func bloodthirsty() -> float:
	_cancel_hurt()
	_cancel_recovery()
	if action == "ComboEnd":
		_end_action()
	if anim == null or action != "":
		return -1.0
	var clip := "Bloodthirsty" if has("Bloodthirsty") else ("Deathblow" if has("Deathblow") else "")
	if clip == "":
		return -1.0
	armed = true
	blocking = false
	_play_once(clip)
	return _per("blood_hit", clip, 0.82 if clip == "Bloodthirsty" else _f("deathblow_hit", 1.1))


## Добивание (враг без равновесия): свой клип, двигаться нельзя. true — началось.
func deathblow() -> bool:
	_cancel_hurt()
	if anim == null or not armed or action != "" or not has("Deathblow"):
		return false
	blocking = false
	_play_once("Deathblow")
	return true


## Приземления в клипе (cfg step_times: клип → [с]): out.land_step — location.gd проигрывает шаг (каблук).
## Шаги циклов по кадрам клипа (loop_steps: {"Walk": [кадр, …]} при 30 к/с): звук каблука — ровно в миг касания,
## а не по пройденным метрам. Есть у клипа — location.gd не считает шаги по расстоянию (out.timed_steps).
var _loop_prev := -1.0


func loop_steps_for(clip: String) -> Array:
	var ls: Variant = (cfg.get("loop_steps", {}) as Dictionary).get(clip, null)
	return ls if ls is Array else []


func _loop_steps(out: Dictionary, moving: bool) -> void:
	var frames := loop_steps_for(anim.current_animation) if anim != null else []
	if frames.is_empty():
		_loop_prev = -1.0
		return
	out["timed_steps"] = true
	var t := _pos()
	if moving and _loop_prev >= 0.0:
		for f: Variant in frames:
			var ft := float(f) / 30.0
			var crossed := (t >= ft and _loop_prev < ft) if t >= _loop_prev else (_loop_prev < ft or t >= ft)
			if crossed:
				out["foot_step"] = true
	_loop_prev = t


func _land_steps(out: Dictionary) -> void:
	var times: Variant = (cfg.get("step_times", {}) as Dictionary).get(action, null)
	if times is Array and _lands_done < (times as Array).size() and _pos() >= float((times as Array)[_lands_done]):
		_lands_done += 1
		out["land_step"] = true


## Миг удара: середина взмаха (swing_peaks), у финального — касание земли (impact). tick вернёт
## {"hit": {"range": м, "arc": косинус полуугла перед героем (-1 — круг)}} — location.gd бьёт по врагам.
func _hit(out: Dictionary) -> void:
	if not _hit_done and action == "Launcher":         # пинок: меч не летит — удар по площади в миг касания ногой
		if _frac() >= _f("launcher_hit_at", 0.42):
			_hit_done = true
			out["hit"] = {"range": _per("hit_range", action, 2.3), "arc": 0.3, "damage": _per("hit_damage", action, 18.0),
				"knock": false}
		return
	var times: Variant = (cfg.get("hit_times", {}) as Dictionary).get(action, null)
	if times is Array:                               # свои моменты ударов клипа (с): каждый — отдельный удар
		var ts := times as Array
		if _hits_done < ts.size() and _pos() >= float(ts[_hits_done]):
			_hits_done += 1
			out["hit"] = {"range": _per("hit_range", action, 2.6), "arc": _per("hit_arc", action, 0.35),
				"damage": _per("hit_damage", action, 15.0), "knock": false, "step": _combo_i,
				"final": _combo_i == ATTACKS.size() - 1 and _hits_done == ts.size(),   # финал серии — свой акцент
				"tip": (_sword_hand.global_transform * _tip) if _sword_hand != null and _sword_hand.is_inside_tree() else Vector3.INF}
		return
	if _hit_done or action not in ATTACKS:
		return
	var imp: Dictionary = meta.get("impact", {})
	if not imp.has(action):
		return                                       # обычные взмахи бьют клинком по пути (blade в tick)
	var at := float(imp[action])
	if _pos() < at:
		return
	_hit_done = true
	var ground := imp.has(action)
	out["hit"] = {"range": _per("hit_range", action, 2.6), "arc": -1.0 if ground else 0.2,
		"damage": _per("hit_damage", action, 15.0), "knock": ground}


## Сколько секунд до мига удара (у финального — до касания земли); -1 — удар уже прошёл или герой не бьёт.
func hit_time_left() -> float:
	if _hit_done or action not in ATTACKS:
		return -1.0
	var imp: Dictionary = meta.get("impact", {})
	var at := float(imp[action]) if imp.has(action) else float((cfg.get("swing_peaks", {}) as Dictionary).get(action, 0.5))
	return maxf(0.0, (at - _pos()) / maxf(anim.speed_scale, 0.05))


## С какой секунды клипа удар тянет к врагу (финальный — с отрыва от земли, не скользит по полу).
func pull_on() -> bool:
	return _pos() >= _per("pull_from", action, 0.0)


## До какой дистанции (м, центр — центр) удар подводит героя к врагу.
func attack_reach() -> float:
	return _per("reach", action, 1.5)


func _sounds() -> void:
	var peaks: Dictionary = cfg.get("swing_peaks", {})
	var base := action.trim_suffix("Walk")
	if _swing != null and not _swing_done and peaks.has(base) \
			and _pos() >= float(peaks[base]) - _f("swing_lead", 0.55):
		_swing_done = true
		_swing.volume_db = _f("swing_volume_db", -4.0) + (0.0 if action in ATTACKS else -6.0)
		_swing.play()
	var imp: Dictionary = meta.get("impact", {})
	if _impact != null and not _impact_done and imp.has(action) \
			and _pos() >= float(imp[action]) - _f("impact_lead", 0.05) * anim.speed_scale:
		_impact_done = true
		_impact.play()
		_ground_burst()


func _root_at(t: float) -> Vector2:
	var rm: Dictionary = meta.get("root_motion", {})
	if not rm.has(action):
		return Vector2.ZERO
	var clip: Dictionary = rm[action]
	var off: Array = clip.get("offset", [])
	if off.is_empty():
		return Vector2.ZERO
	var x := t * float(clip.get("fps", 30))
	var i := clampi(int(x), 0, off.size() - 1)
	var j := mini(i + 1, off.size() - 1)
	var a: Array = off[i]
	var b: Array = off[j]
	var k := x - float(i)
	return Vector2(lerpf(float(a[0]), float(b[0]), k), lerpf(float(a[1]), float(b[1]), k))


## Смещение тела за кадр из root motion клипа.
## Вход в бег и выход из него: скорость героя (м/с) — ход таза в клипе на этом кадре, чтобы ноги не скользили;
## −1 — не эти клипы (скорость задаёт ввод).
func edge_speed() -> float:
	if action != "" or anim == null or anim.current_animation not in ["RunStart", "RunStop"] or not anim.is_playing():
		return -1.0
	var off: Array = ((meta.get("root_motion", {}) as Dictionary).get(anim.current_animation, {}) as Dictionary) \
		.get("offset", [])
	if off.size() < 2:
		return -1.0
	var i := clampi(int(_pos() * 30.0), 0, off.size() - 2)
	var a: Array = off[i]
	var b: Array = off[i + 1]
	return Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).length() * 30.0


func _root_step() -> Vector3:
	var cur := _root_at(_pos())
	var d := cur - _prev_off
	_prev_off = cur
	var s := _per("root_motion_scale", action, 0.8)
	return Vector3(d.x * s * _per("root_motion_lateral", action, 0.5), 0.0, d.y * s)


## Меч там, где он сейчас: на спине или в руке. В беге он плавно перекладывается в «волочится» (цель — узел
## Sword_Drag) и в любом клипе не уходит в землю: если остриё ниже пола — меч поворачивается на хвате вверх.
## Лицо (у кого есть кости глаз и морф век Blink — Тян Лун): моргает раз в 2–5 с (иногда дважды), глаза
## иногда смотрят по сторонам — короткий скачок взгляда, потом обратно к центру.
var _lids: Array = []
var _eyes: Array = []
var _face_ready := false
var _blink_t := 3.0
var _blink := -1.0
var _blink_twice := false
var _eye_t := 2.0
var _eye_look := Vector2.ZERO
var _eye_want := Vector2.ZERO
var _blink_w := -1.0
var _lid_idx: Array = []
var _eye_rest: Array = []


func _face_tick(delta: float) -> void:
	if delta <= 0.0 or model == null:
		return
	if not _face_ready:
		_face_ready = true
		for n: Node in model.find_children("Lid_Upper*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.find_blend_shape_by_name(&"Blink") >= 0:
				_lids.append(mi)
		if _skel != null:
			for e: String in ["LeftEye", "RightEye"]:
				var bi := _skel.find_bone(e)
				if bi >= 0:
					_eyes.append(bi)
	if not _lids.is_empty():
		_blink_t -= delta
		if _blink < 0.0 and _blink_t <= 0.0:
			_blink = 0.0
			_blink_twice = randf() < 0.18
			_blink_t = randf_range(2.0, 5.0)
		var w := 0.0
		if _blink >= 0.0:
			_blink += delta
			var dur := 0.16
			w = sin(clampf(_blink / dur, 0.0, 1.0) * PI)
			if _blink >= dur:
				_blink = -1.0
				if _blink_twice:
					_blink_twice = false
					_blink_t = 0.12
		if not is_equal_approx(w, _blink_w):              # веки — только когда двигаются (раньше: поиск формы по имени
			_blink_w = w                                  # и запись 0 в сетку каждый кадр)
			for li: int in _lids.size():
				var mi: MeshInstance3D = _lids[li]
				if li >= _lid_idx.size():
					_lid_idx.append(mi.find_blend_shape_by_name(&"Blink"))
				mi.set_blend_shape_value(_lid_idx[li], w)
	if not _eyes.is_empty():
		_eye_t -= delta
		if _eye_t <= 0.0:
			if _eye_want != Vector2.ZERO and randf() < 0.6:
				_eye_want = Vector2.ZERO                      # обратно к центру
				_eye_t = randf_range(1.5, 3.5)
			else:
				_eye_want = Vector2(randf_range(-0.3, 0.3), randf_range(-0.1, 0.12))
				_eye_t = randf_range(0.6, 1.6)
		_eye_look = _eye_look.lerp(_eye_want, 1.0 - exp(-delta * 18.0))   # взгляд прыгает быстро (саккада)
		# каждый кадр (клип мог перезаписать кости глаз), но покой костей — из кэша, а не два запроса на кадр
		if _eye_rest.is_empty():                      # покой костей глаз — один раз, а не дважды на кадр
			for bi: int in _eyes:
				_eye_rest.append([_skel.get_bone_rest(bi).basis.get_rotation_quaternion(),
					_skel.get_bone_global_rest(bi).basis.get_rotation_quaternion()])
		var off := Quaternion(Vector3.UP, _eye_look.x) * Quaternion(Vector3.RIGHT, -_eye_look.y)   # в осях головы: вбок, вверх
		for k: int in _eyes.size():
			var rest: Quaternion = _eye_rest[k][0]
			var g: Quaternion = _eye_rest[k][1]
			_skel.set_bone_pose_rotation(_eyes[k], rest * (g.inverse() * off * g))


func _show_sword(delta: float) -> void:
	if _sword_back == null or _sword_hand == null:
		return
	var sw: Dictionary = meta.get("sword_switch", {})
	var in_hand := armed
	if action.begins_with("Draw"):
		in_hand = _pos() >= float((sw.get("Draw", {}) as Dictionary).get("time", 0.45))
	elif action.begins_with("Sheathe"):
		in_hand = _pos() < float((sw.get("Sheathe", {}) as Dictionary).get("time", 0.9))
	elif action in ATTACKS or action in SPECIALS or action in ["Ultimate", "Finisher", "SwordTrick", "Bloodthirsty"]:
		in_hand = true
	_sword_hand.visible = in_hand and action != "Iai" and _planted == null
	_curl_fingers(_sword_hand.visible)
	_sword_back.visible = not in_hand and action != "Iai"     # в Иай — только катана (iai.gd)
	if not in_hand:
		_drag_w = 0.0
		_left_hand_ik(false)
		return
	var drag := action == "" and anim != null and anim.current_animation == "RunArmed" and _sword_drag != null 		and bool(cfg.get("sword_drag_run", true))         # клип бега сам держит меч (на плече) — не волочить
	var dur := maxf(0.05, _f("blend_run_armed", 0.5))
	_drag_w = move_toward(_drag_w, 1.0 if drag else 0.0, delta / dur) if delta > 0.0 else (1.0 if drag else 0.0)
	_sword_hand.transform = _hand_rest
	_two_hand_grip()
	_left_hand_ik(bool(cfg.get("left_hand_ik", true)) and _sword_hand.visible and not action.begins_with("Dodge") and action not in ["SwordTrick", "Iai", "Ultimate", "Kick", "Launcher"])
	if _drag_w > 0.0 and _sword_drag != null and _sword_drag.is_inside_tree():
		var k := smoothstep(0.0, 1.0, _drag_w)
		var a := _sword_hand.global_transform
		var b := _sword_drag.get_parent_node_3d().global_transform * _drag_rest
		var qa := a.basis.get_rotation_quaternion()
		var qb := b.basis.get_rotation_quaternion()
		var sc := a.basis.get_scale()
		var q := qa.slerp(qb, k)
		if _sword_lag and delta > 0.0:
			if _sword_q.dot(q) < 0.0:
				q = -q
			q = _sword_q.slerp(q, 1.0 - exp(-delta * _f("sword_follow", 7.0)))   # меч догоняет руку с запозданием
		_sword_q = q
		_sword_lag = true
		_sword_hand.global_transform = Transform3D(Basis(q).scaled(sc), a.origin.lerp(b.origin, k))
	else:
		_sword_lag = false
	if action == "SwordTrick":
		_trick_sword()
	else:
		_keep_above_floor()


## Трюк после второго удара (клип SwordTrick): подбросил меч — он крутится вокруг левого предплечья через своё
## отверстие (один оборот), герой откинут назад; потом рука выдёргивается, правая перехватывает рукоять.
func flourish() -> bool:
	if anim == null or not armed or action != "" or not has("SwordTrick"):
		return false
	_play_once("SwordTrick", 0.0)
	return true


var _trick_last := Transform3D.IDENTITY


func _trick_sword() -> void:
	if _skel == null or _tip == Vector3.ZERO:
		return
	var t := _pos()
	var t0 := _f("trick_spin_from", 0.4)
	var t1 := _f("trick_spin_to", 1.65)
	var tc := t1 + _f("trick_fall", 0.28)                    # меч чуть падает — правая рука ловит его ниже
	if t > t1 and t < tc and _trick_last != Transform3D.IDENTITY:
		var u := (t - t1) / (tc - t1)
		var drop := 0.5 * 9.8 * pow(t - t1, 2.0)              # свободное падение
		var hand := _sword_hand.global_transform              # поза в руке (_hand_rest уже выставлен)
		var fall_pos := _trick_last.origin - Vector3(0, drop, 0)
		var k := u * u * u                                     # рука догоняет в самом конце — резкий перехват
		var q := _trick_last.basis.get_rotation_quaternion().slerp(hand.basis.get_rotation_quaternion(), k)
		var sc2 := hand.basis.get_scale()
		_sword_hand.global_transform = Transform3D(Basis(q).scaled(sc2), fall_pos.lerp(hand.origin, k))
		return
	if t < t0 or t > t1:
		if t >= tc:
			_trick_last = Transform3D.IDENTITY
		return
	var lh := _skel.find_bone("LeftHand")
	var lf := _skel.find_bone("LeftForeArm")
	if lh < 0 or lf < 0:
		return
	var ph := _skel.global_transform * _skel.get_bone_global_pose(lh).origin
	var pf := _skel.global_transform * _skel.get_bone_global_pose(lf).origin
	var axis := (ph - pf).normalized()
	var on_arm := pf.lerp(ph, 0.55)                          # отверстие меча — на середине предплечья
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var u := clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 3.0)                         # резко раскрутил — к концу притормаживает
	var d := (ref - axis * ref.dot(axis)).normalized().rotated(axis, TAU * e)   # один оборот
	var tl := _tip.normalized()                              # клинок в осях меча
	var fl := (Vector3.UP - tl * Vector3.UP.dot(tl)).normalized()
	if fl.length() < 0.1:
		fl = (Vector3.RIGHT - tl * Vector3.RIGHT.dot(tl)).normalized()
	var sc := _sword_hand.global_transform.basis.get_scale()
	var local_f := Basis(tl, fl, tl.cross(fl))
	var world_f := Basis(-d, axis, (-d).cross(axis))       # рукоять описывает круг вокруг руки, плоскость клинка — поперёк руки
	var bs := (world_f * local_f.inverse()).scaled_local(sc)
	var hole := _tip * _f("trick_hole_at", 0.86)             # отверстие у острия
	_sword_hand.global_transform = Transform3D(bs, on_arm - bs * hole)
	_trick_last = _sword_hand.global_transform


## Хват двумя руками, как у Гатса (Elden Ring): меч на линии рук — правая у гарды (начало сетки), левая ниже по
## рукояти, клинок — дальше за правой рукой. Руки далеко (клип держит одной) — в покое и на ходу остриё назад-вниз,
## в ударах — как держит кисть (_hand_rest). Плоскость клинка — кромкой вперёд/вниз.
var _sw_flat := Vector3.ZERO


func _two_hand_grip() -> void:
	if not bool(cfg.get("two_hand_grip", true)):
		return                                                # не у всех героев двуручник (копьё держится клипом)
	if _skel == null or _tip == Vector3.ZERO or action.begins_with("Dodge") or action in ["SwordTrick", "Iai"]:
		return
	var rh := _skel.find_bone("RightHand")
	var lh := _skel.find_bone("LeftHand")
	var rf := _skel.find_bone("RightForeArm")
	var lf := _skel.find_bone("LeftForeArm")
	if rh < 0 or lh < 0 or rf < 0 or lf < 0:
		return
	var g := _skel.global_transform
	var R := g * _skel.get_bone_global_pose(rh).origin
	var L := g * _skel.get_bone_global_pose(lh).origin
	R += (R - g * _skel.get_bone_global_pose(rf).origin).normalized() * 0.08    # середина кулака
	L += (L - g * _skel.get_bone_global_pose(lf).origin).normalized() * 0.08
	var fwd := model.global_transform.basis.z.normalized()
	var dir := Vector3.ZERO
	if action == "" or action.begins_with("Walk") or action.begins_with("Run"):
		dir = (-fwd * 0.85 + Vector3.DOWN * 0.5).normalized()  # в покое и на ходу — остриём назад, низко (левая — по IK)
	elif (R - L).length() < _f("grip_two_hand", 0.6) and (R - L).length() > 0.05:
		dir = (R - L).normalized()                            # в ударе — от левого кулака через правый, к острию
	else:
		return
	if _sw_flat == Vector3.ZERO and _sword_hand is MeshInstance3D and (_sword_hand as MeshInstance3D).mesh != null:
		var sz := (_sword_hand as MeshInstance3D).mesh.get_aabb().size
		_sw_flat = Vector3.RIGHT if sz.x <= sz.y and sz.x <= sz.z else (Vector3.UP if sz.y <= sz.z else Vector3.BACK)
	var tl := _tip.normalized()
	var fl := (_sw_flat - tl * _sw_flat.dot(tl)).normalized()
	var n := dir.cross(Vector3.UP)                            # нормаль плашмя — вбок: кромка смотрит вперёд/вниз
	if n.length() < 0.1:
		n = dir.cross(fwd)
	n = n.normalized()
	var sc := _sword_hand.global_transform.basis.get_scale()
	var bs := (Basis(dir, n, dir.cross(n)) * Basis(tl, fl, tl.cross(fl)).inverse()).scaled_local(sc)
	_sword_hand.global_transform = Transform3D(bs, R + dir * _f("grip_off", 0.62))   # хват у навершия: гарда выше кулака


## Левая рука — на рукоять (IK: плечо → предплечье → кисть), ниже правой на grip_left_at м по рукояти.
## Клипы Meshy держат воображаемый меч, руки там врозь — без этого левая висит мимо меча.
var _lik: SkeletonIK3D


func _left_hand_ik(on: bool) -> void:
	if _skel == null:
		return
	if _lik == null:
		if not on:
			return
		_lik = SkeletonIK3D.new()                              # без кода из строк: песочница игры такое блокирует
		_lik.root_bone = &"LeftArm"
		_lik.tip_bone = &"LeftHand"
		_lik.override_tip_basis = false
		_skel.add_child(_lik)
		_lik.start()
	_lik.influence = move_toward(_lik.influence, 1.0 if on else 0.0, 0.2)
	if not on or _tip == Vector3.ZERO:
		return
	var sg := _sword_hand.global_transform
	var axis := (sg.basis * _tip).normalized()               # к острию
	var grip := sg.origin - axis * (_f("grip_off", 0.62) + _f("grip_left_at", 0.32))   # ниже правой руки по рукояти
	var tr := Transform3D(sg.basis.orthonormalized(), grip)
	_lik.target = _skel.global_transform.affine_inverse() * tr


## Пальцы (кости RightFingers / LeftFingers — сгиб всех четырёх разом вокруг своей оси X): с мечом — сжаты на рукояти.
var _curl := 0.0


func _curl_fingers(hold: bool) -> void:
	if _skel == null:
		return
	_curl = move_toward(_curl, 1.0 if hold else 0.0, 0.08)
	for n: String in ["RightFingers", "LeftFingers"]:
		var bi := _skel.find_bone(n)
		if bi < 0:
			continue
		var ang := deg_to_rad(_f("finger_curl_deg", -70.0)) * _curl
		_skel.set_bone_pose_rotation(bi, _skel.get_bone_rest(bi).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, ang))


func _keep_above_floor() -> void:
	if not _on_floor or _tip == Vector3.ZERO or not _sword_hand.is_inside_tree():
		return
	if action.begins_with("Dodge"):
		return                                   # в перекате меч едет с телом одним движением (поза клипа), без доворотов
	var g := _sword_hand.global_transform
	var floor_y := model.global_position.y + _f("sword_floor", 0.04)
	var tip := g * _tip
	if tip.y >= floor_y:
		return
	var v := tip - g.origin
	var n := v.length()
	if n < 0.01:
		return
	var vz := clampf((floor_y - g.origin.y) / n, -0.999, 0.999)
	var h := Vector2(v.x, v.z)
	if h.length() < 0.001:
		h = Vector2(0.0, 1.0)
	h = h.normalized() * sqrt(1.0 - vz * vz)
	var v2 := Vector3(h.x, vz, h.y)
	var q := Quaternion(v / n, v2)
	_sword_hand.global_transform = Transform3D(Basis(q) * g.basis, g.origin)
