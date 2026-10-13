extends Node
## Аниматор героя на AnimationTree с интерфейсом AnimationPlayer (play / seek / speed_scale / current_animation…),
## чтобы hero.gd звал его как раньше. Внутри два слоя:
##  • петли — Transition между клипами-петлями и пространствами смешивания (BlendSpace2D): шаг в захвате цели
##    и в блоке смешивает клипы вперёд / назад / вбок по направлению, диагонали — без рывков;
##  • разовые клипы (удары, увороты…) — два слота поочерёдно: следующий удар комбо плавно перетекает из прежнего,
##    а не обрывает его. Переход петли ↔ разовый — тоже плавный (blend, как у AnimationPlayer.play).
## Время разового клипа считаем сами (позиция, конец → animation_finished), а не читаем из дерева: сразу после play
## дерево ещё не пересчитано. hitstop(t) — замирание на миг удара (вес попадания).

signal animation_finished(anim_name: StringName)

var player: AnimationPlayer
var tree: AnimationTree
var current_animation := ""
var current_animation_position := 0.0
var speed_scale := 1.0
var _loops: PackedStringArray = []
var _spaces := {}                    # имя пространства → true
var _blend_want := {}                # имя → Vector2 (куда тянется точка смешивания)
var _blend_now := {}
var _is_loop := true
var _slot := "b"                     # слот последнего разового клипа
var _done := false
var _hit_t := 0.0
var _hit_k := 1.0
var blend_smooth := 10.0             # как быстро точка смешивания догоняет направление (1/с)
var _via_t := -1.0                   # переход через промежуточную позу верха тела: прошло, с (−1 — нет)
var _via_d := 0.4
const UPPER := ["Spine02", "Spine01", "Spine", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]


## spaces: {"Lock": {"center": "IdleArmed", "F": "LockF", "B": "LockB", "L": "LockL", "R": "LockR"}, …}
func setup(p: AnimationPlayer, spaces: Dictionary) -> void:
	player = p
	for n: String in p.get_animation_list():
		if p.get_animation(n).loop_mode != Animation.LOOP_NONE:
			_loops.append(String(n))
	var bt := AnimationNodeBlendTree.new()
	var loop_tr := AnimationNodeTransition.new()
	for n: String in _loops:
		loop_tr.add_input(n)
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(n)
		bt.add_node("L_" + n, a)
	for sname: String in spaces:
		if not (spaces[sname] is Dictionary):
			continue                                 # "_note" и прочие пояснения
		var sp: Dictionary = spaces[sname]
		var bs := AnimationNodeBlendSpace2D.new()
		bs.sync = true
		var pts := {"center": Vector2.ZERO, "F": Vector2(0, 1), "B": Vector2(0, -1), "L": Vector2(-1, 0), "R": Vector2(1, 0)}
		var ok := true
		for k: String in pts:
			var clip := str(sp.get(k, ""))
			if clip == "" or not p.has_animation(clip):
				ok = false
				break
		if not ok:
			continue
		for k: String in pts:
			var a := AnimationNodeAnimation.new()
			a.animation = StringName(str(sp[k]))
			bs.add_blend_point(a, pts[k] as Vector2, -1, StringName(k))   # имя точки — Godot 4.7 требует
		loop_tr.add_input(sname)
		bt.add_node("L_" + sname, bs)
		_spaces[sname] = true
		_blend_want[sname] = Vector2(0, 1)
		_blend_now[sname] = Vector2(0, 1)
	bt.add_node("loop_tr", loop_tr)
	var i := 0
	for n: String in _loops:
		bt.connect_node("loop_tr", i, "L_" + n)
		i += 1
	for sname: String in _spaces:
		bt.connect_node("loop_tr", i, "L_" + sname)
		i += 1
	bt.add_node("loop_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("loop_seek", 0, "loop_tr")
	bt.add_node("loop_ts", AnimationNodeTimeScale.new())
	bt.connect_node("loop_ts", 0, "loop_seek")
	var act_tr := AnimationNodeTransition.new()
	for s: String in ["a", "b"]:
		act_tr.add_input(s)
		var a := AnimationNodeAnimation.new()
		bt.add_node("act_" + s, a)
		bt.add_node("seek_" + s, AnimationNodeTimeSeek.new())
		bt.add_node("ts_" + s, AnimationNodeTimeScale.new())
		bt.connect_node("seek_" + s, 0, "act_" + s)
		bt.connect_node("ts_" + s, 0, "seek_" + s)
	bt.add_node("act_tr", act_tr)
	bt.connect_node("act_tr", 0, "ts_a")
	bt.connect_node("act_tr", 1, "ts_b")
	var mode := AnimationNodeTransition.new()
	mode.add_input("loop")
	mode.add_input("act")
	bt.add_node("mode", mode)
	bt.connect_node("mode", 0, "loop_ts")
	bt.connect_node("mode", 1, "act_tr")
	# слой верха тела: промежуточная поза (via) поверх всего — фильтр по костям корпуса и рук
	var ov := AnimationNodeAnimation.new()
	bt.add_node("ov", ov)
	var up := AnimationNodeBlend2.new()
	up.filter_enabled = true
	var skel_path := _skeleton_path(p)
	for b: String in UPPER:
		up.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("upper", up)
	bt.connect_node("upper", 0, "mode")
	bt.connect_node("upper", 1, "ov")
	bt.connect_node("output", 0, "upper")
	tree = AnimationTree.new()
	tree.tree_root = bt
	p.add_sibling(tree)
	tree.anim_player = tree.get_path_to(p)
	p.stop()
	p.active = false
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.active = true
	# начальные состояния переключателей — явно: у нового AnimationNodeTransition состояние пустое, вывод — без позы
	# (герой стоял в T-позе, пока «достать меч» не переключало mode туда и обратно)
	if not _loops.is_empty():
		tree.set("parameters/loop_tr/transition_request", _loops[0])
	tree.set("parameters/act_tr/transition_request", "a")
	tree.set("parameters/mode/transition_request", "loop")
	tree.advance(0.0)
	set_physics_process(true)


## Путь к скелету в дорожках клипов (до «:кость») — для фильтра слоя верха тела.
static func _skeleton_path(p: AnimationPlayer) -> String:
	for n: String in p.get_animation_list():
		var a := p.get_animation(n)
		for i in a.get_track_count():
			var s := String(a.track_get_path(i))
			if s.ends_with(":Spine02"):
				return s.trim_suffix(":Spine02")
	return "Skeleton3D"


## Переход верха тела через промежуточную позу n за d секунд: вес позы растёт до 1 к середине и спадает —
## меч идёт через эту позу, а не по кратчайшему пути сквозь корпус (стойка ↔ меч на плече).
func via(n: String, d: float) -> void:
	if player == null or not player.has_animation(n):
		return
	(_bt().get_node("ov") as AnimationNodeAnimation).animation = StringName(n)
	_via_t = 0.0
	_via_d = maxf(0.05, d)


func has_animation(n: String) -> bool:
	return _spaces.has(n) or (player != null and player.has_animation(n))


func has_space(n: String) -> bool:
	return _spaces.has(n)


func get_animation(n: String) -> Animation:
	return player.get_animation(n)


## Как у AnimationPlayer: разовый клип, дошедший до конца, уже «не играет» (поза остаётся на последнем кадре).
func is_playing() -> bool:
	return current_animation != "" and not (not _is_loop and _done)


var current_animation_length: float:
	get:
		if current_animation == "" or _spaces.has(current_animation) or not player.has_animation(current_animation):
			return 1.0
		return player.get_animation(current_animation).length


func _bt() -> AnimationNodeBlendTree:
	return tree.tree_root as AnimationNodeBlendTree


func _xfade(node: String, t: float) -> void:
	(_bt().get_node(node) as AnimationNodeTransition).xfade_time = maxf(0.0, t)


func play(n: String, blend := -1.0) -> void:
	var bl := 0.2 if blend < 0.0 else blend
	if _loops.has(n) or _spaces.has(n):
		_xfade("loop_tr", bl if _is_loop else 0.0)
		tree.set("parameters/loop_tr/transition_request", n)
		if not _is_loop:
			_xfade("mode", bl)
			tree.set("parameters/mode/transition_request", "loop")
		_is_loop = true
	else:
		var s := "b" if _slot == "a" else "a"
		(_bt().get_node("act_" + s) as AnimationNodeAnimation).animation = StringName(n)
		tree.set("parameters/seek_" + s + "/seek_request", 0.0)
		_xfade("act_tr", bl if not _is_loop else 0.0)
		tree.set("parameters/act_tr/transition_request", s)
		if _is_loop:
			_xfade("mode", bl)
			tree.set("parameters/mode/transition_request", "act")
		_slot = s
		_is_loop = false
		_done = false
	current_animation = n
	current_animation_position = 0.0


func seek(t: float, _update := false) -> void:
	current_animation_position = t
	if _is_loop:
		tree.set("parameters/loop_seek/seek_request", t)
	else:
		tree.set("parameters/seek_" + _slot + "/seek_request", t)
		_done = false


func stop() -> void:
	current_animation = ""


## Куда смешивать в пространстве n (x — вправо, y — вперёд; длина ≤ 1).
func set_blend(n: String, v: Vector2) -> void:
	if _spaces.has(n):
		_blend_want[n] = v.limit_length(1.0)


## Замирание на миг удара: t секунд клипы идут в k раз медленнее (k≈0 — стоп-кадр).
func hitstop(t: float, k := 0.05) -> void:
	_hit_t = maxf(_hit_t, t)
	_hit_k = k


func hitstopped() -> bool:
	return _hit_t > 0.0


func _physics_process(delta: float) -> void:
	if tree == null:
		return
	var k := 1.0
	if _hit_t > 0.0:
		_hit_t -= delta
		k = _hit_k
	var w := 0.0
	if _via_t >= 0.0:
		_via_t += delta
		var x := _via_t / _via_d
		if x >= 1.0:
			_via_t = -1.0
		else:
			w = sin(PI * x)                          # 0 → 1 (середина перехода) → 0
	tree.set("parameters/upper/blend_amount", w)
	var sc := speed_scale * k
	if _is_loop:
		tree.set("parameters/loop_ts/scale", sc)
	else:
		tree.set("parameters/ts_" + _slot + "/scale", sc)
	for n: String in _blend_now:
		var now: Vector2 = _blend_now[n]
		var want: Vector2 = _blend_want[n]
		now = now.lerp(want, minf(1.0, delta * blend_smooth))
		_blend_now[n] = now
		tree.set("parameters/L_" + n + "/blend_position", now)
	if current_animation == "":
		return
	current_animation_position += delta * sc
	if _is_loop:
		var ln := current_animation_length
		if ln > 0.0:
			current_animation_position = fmod(current_animation_position, ln)
	elif not _done and current_animation_position >= current_animation_length:
		current_animation_position = current_animation_length
		_done = true
		animation_finished.emit(StringName(current_animation))
