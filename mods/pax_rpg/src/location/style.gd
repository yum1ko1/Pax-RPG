extends RefCounted
## Шкала стиля боя (как в Devil May Cry): попадания дают очки, за разнообразие — больше, повтор одного приёма — всё меньше;
## без попаданий шкала тает (на высоких рангах быстрее), пропущенный удар роняет ранг. Ранги D, C, B, A, S, SS, SSS
## (названия — data/lang pax_rpg_style_<ранг>). Ранг множит награду за поверженного (золото, опыт — location.gd).

const RANKS := ["D", "C", "B", "A", "S", "SS", "SSS"]
const STEP := 100.0                  # очков на ранг (внутри ранга — полоска 0..1)
const POINTS := {"Attack1": 10.0, "Attack2": 12.0, "Attack3": 18.0, "Lunge": 22.0, "Launcher": 24.0,
	"PauseFinisher": 30.0, "Quake": 28.0, "Ultimate": 45.0, "Iai": 50.0, "Parry": 25.0, "Deathblow": 40.0}

var points := 0.0
var _recent: Array = []              # последние приёмы — для бонуса разнообразия
var _idle := 0.0
var flash := 0.0                     # ранг вырос — вспышка буквы на HUD


func rank() -> int:
	return clampi(int(points / STEP), 0, RANKS.size() - 1)


func frac() -> float:
	return fmod(points, STEP) / STEP if rank() < RANKS.size() - 1 else 1.0


func letter() -> String:
	return RANKS[rank()] if points > 0.5 else ""


## Множитель награды за поверженного: D — ×1 … SSS — ×2.2.
func reward_mult() -> float:
	return 1.0 + rank() * 0.2 if points > 0.5 else 1.0


## Попадание приёмом move: очки с бонусом разнообразия и штрафом за повтор.
func hit(move: String) -> void:
	var base := float(POINTS.get(move, 10.0))
	var same := 0
	for m: Variant in _recent:
		if str(m) == move:
			same += 1
	var k := 1.0 / (1.0 + same * 0.6)               # повтор: ×1, ×0.63, ×0.45…
	if same == 0 and _recent.size() >= 2:
		k *= 1.35                                   # новый приём в серии — бонус
	var before := rank()
	points = minf(points + base * k, STEP * RANKS.size() - 1.0)
	_recent.append(move)
	if _recent.size() > 5:
		_recent.pop_front()
	_idle = 0.0
	if rank() > before:
		flash = 1.0


## Герой пропустил удар — минус ранг и полрангa сверху, серия разнообразия сброшена.
func hurt() -> void:
	points = maxf(0.0, points - STEP * 1.5)
	_recent.clear()


func tick(delta: float) -> void:
	_idle += delta
	flash = maxf(0.0, flash - delta * 1.5)
	if _idle > 2.5 and points > 0.0:               # без попаданий тает: на высоком ранге быстрее
		points = maxf(0.0, points - delta * (10.0 + rank() * 9.0))
