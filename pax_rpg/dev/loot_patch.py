"""Врезка лута (src/location/loot) в location.gd и main.gd по якорям — для копии в репозитории и на ПК (там файлы новее).
    python loot_patch.py <папка мода pax_rpg>
Повторный запуск ничего не меняет."""
import sys, os

root = sys.argv[1]


def patch(rel, pairs):
    p = os.path.join(root, rel)
    s = open(p, encoding="utf-8").read()
    n = 0
    for anchor, new, done in pairs:
        if done in s:
            continue
        assert s.count(anchor) == 1, f"{rel}: якорь не найден или не один: {anchor[:70]!r}"
        s = s.replace(anchor, new)
        n += 1
    open(p, "w", encoding="utf-8", newline="\n").write(s)
    print(rel, "врезок:", n)


patch("src/location/location.gd", [
    ('const Inventory := preload("res://mods/pax_rpg/src/location/inventory.gd")\n',
     'const Inventory := preload("res://mods/pax_rpg/src/location/inventory.gd")\n'
     'const Loot := preload("res://mods/pax_rpg/src/location/loot/loot.gd")\n',
     "const Loot := preload"),
    ("var _inv: Inventory                # инвентарь (TAB)\n",
     "var _inv: Inventory                # инвентарь (TAB)\n"
     "var _loot: Loot                    # сферы с врагов и прокрутка вещей (src/location/loot)\n",
     "var _loot: Loot"),
    ("\t_inv = Inventory.new()\n",
     "\t_loot = Loot.new()                               # под инвентарём: открытый TAB закрывает прокрутку\n"
     "\t_loot.setup(mod)\n"
     "\tadd_child(_loot)\n"
     "\t_loot.gold_picked.connect(func(n: int) -> void:\n"
     "\t\t_prog.add_gold(n)\n"
     "\t\t_gold_flash = 1.0)\n"
     "\t_loot.xp_picked.connect(func(v: float, at: Vector2) -> void:\n"
     "\t\t_orbs.append({\"p0\": at, \"t\": 0.0, \"delay\": 0.0, \"v\": v, \"bend\": randf_range(-1.0, 1.0)}))\n"
     "\t_inv = Inventory.new()\n",
     "_loot = Loot.new()"),
    ("_iai, _inv, _wrist,", "_iai, _inv, _loot, _wrist,", "_inv, _loot,"),
    # сферы вместо мгновенной награды: опыт и золото — по подбору
    ("""			var n := 10
			for k: int in n:
				_orbs.append({"p0": from + Vector2(randf_range(-30, 30), randf_range(-30, 30)), "t": 0.0,
					"delay": k * 0.06, "v": gain / n, "bend": randf_range(-1.0, 1.0)})
			var coins := roundi(randi_range(6, 14) * _style.reward_mult())   # и немного золота (больше — на высоком стиле)
			gain *= _style.reward_mult()
			_prog.add_gold(coins)
			_gold_flash = 1.0
""",
     """			var coins := roundi(randi_range(6, 14) * _style.reward_mult())   # и немного золота (больше — на высоком стиле)
			if is_instance_valid(_loot):                     # сферы: золото и опыт — когда герой их подберёт
				_loot.drop(gob.global_position, _cam, _player, gain, coins, _prog.level)
			else:
				_orbs.append({"p0": from, "t": 0.0, "delay": 0.0, "v": gain, "bend": 0.0})
				_prog.add_gold(coins)
			gain *= _style.reward_mult()
""",
     "_loot.drop(gob.global_position"),
    ("func spawn_orc() -> String:\n",
     "## Проверка лута (команда rpg_roll [редкость 0…5]): радужная сфера перед героем → прокрутка.\n"
     "func test_roll(r := -1) -> String:\n"
     "\tif not is_instance_valid(_loot) or not is_instance_valid(_player):\n"
     "\t\treturn \"нет локации\"\n"
     "\t_loot.test(_cam, _player, _prog.level, r)\n"
     "\treturn \"roll\"\n\n\n"
     "func spawn_orc() -> String:\n",
     "func test_roll("),
])
patch("main.gd", [
    ('\tPax.register_command("rpg_orc", _orc_command, "rpg_orc — орк-чемпион перед героем (тест боя)")\n',
     '\tPax.register_command("rpg_orc", _orc_command, "rpg_orc — орк-чемпион перед героем (тест боя)")\n'
     '\tPax.register_command("rpg_roll", _roll_command, "rpg_roll [0–5] — радужная сфера и прокрутка вещи (тест лута)")\n',
     '"rpg_roll"'),
    ("func _orc_command(_args: PackedStringArray) -> String:\n",
     "func _roll_command(args: PackedStringArray) -> String:\n"
     "\treturn location.test_roll(int(args[0]) if args.size() > 0 else -1)\n\n\n"
     "func _orc_command(_args: PackedStringArray) -> String:\n",
     "func _roll_command("),
])
