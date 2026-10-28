"""Тестовая HTML-версия прокрутки лута: прототип подсказки (tooltip_src.html) без библиотеки вещей + loot_roll.js.
    python build_loot.py <папка tooltip> → loot.html (все картинки и звуки внутри)."""
import base64, re, sys, os
d = sys.argv[1]
s = open(os.path.join(d, "tooltip_src.html"), encoding="utf-8").read()
js = open(os.path.join(d, "loot_roll.js"), encoding="utf-8").read()


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep("<title>Подсказка предмета Pax RPG</title>", "<title>Прокрутка лута</title>")
rep("<h1>Подсказка предмета</h1>", "<h1>Прокрутка лута</h1>")
s = re.sub(r'<p class="lead">.*?</p>', '<p class="lead">Нажмите «Крутить»: радужная сфера улетает в правый нижний угол, там растекается тушь, '
           'на кляксах — вещи в ряд, под золотым указателем. Вещь известна заранее: пока ряд ещё едет, появляется катана и на ходу '
           'обрубает путь прямо перед ней, а на остановке вторым взмахом отсекает хвост; оставшуюся вещь обводит тушевое кольцо цвета редкости. Легендарная и выше или пропитанная маной: '
           'вещь уходит влево-вверх, рядом открываются её характеристики, усиленные статы прокручиваются по очереди. Потом вещь '
           'сферой улетает в сумку и появляется в выборе своего слота: кликните по слоту в инвентаре ниже. Библиотеки вещей нет — '
           'в сумке только надетое и выбитое. Можно запустить несколько прокруток сразу: «Крутить ×3».</p>', s, count=1, flags=re.S)
rep('<button id="reroll" type="button">Перебросить статы</button>',
    '<button id="lootGo" type="button">Крутить</button>\n'
    '    <label for="lootR">Выпадет <select id="lootR"><option value="-1">по шансам</option><option value="0">Обычное</option>'
    '<option value="1">Необычное</option><option value="2">Редкое</option><option value="3">Эпическое</option>'
    '<option value="4">Легендарное</option><option value="5">Мифическое</option></select></label>\n'
    '    <label for="lootMana"><input id="lootMana" type="checkbox"> пропитано маной</label>\n'
    '    <label for="lootSnd"><input id="lootSnd" type="checkbox" checked> звук</label>\n'
    '    <button id="reroll" type="button">Перебросить статы</button>')
rep('    <div class="menu" id="menu" role="dialog" aria-label="Выбор вещи" aria-hidden="true"></div>\n  </div>',
    '    <div class="menu" id="menu" role="dialog" aria-label="Выбор вещи" aria-hidden="true"></div>\n  </div>\n'
    '  <canvas id="lootCv" aria-hidden="true"></canvas>')
rep('<button id="lootGo" type="button">Крутить</button>',
    '<button id="lootGo" type="button">Крутить</button>\n    <button id="lootGo3" type="button">Крутить ×3</button>')
rep("</style>", """#lootCv { position: fixed; inset: 0; width: 100vw; height: 100vh; pointer-events: none; z-index: 50; }
.lttWrap { position: fixed; left: 0; top: 0; transform-origin: 0 0; z-index: 51; pointer-events: none; opacity: 0; }
.lttWrap .tt { position: relative; left: auto !important; top: auto !important; width: 316px; max-width: none; margin: 0; }
@keyframes landFlash { from { filter: brightness(2.4); } to { filter: none; } }
.lttWrap li.landed { animation: landFlash .45s ease-out, glow 3.6s ease-in-out infinite; }
@keyframes lootNew { 0% { box-shadow: 0 0 0 2px #ffd98c, 0 0 26px #ffd98c; } 100% { box-shadow: 0 0 0 0 transparent; } }
.lootNew { animation: lootNew 2.4s ease-out; }
input[type=checkbox] { accent-color: #c9a35c; }
</style>""")
# сумка без библиотеки: надетое (сет Самурая с редкостями макета) + выбитое
rep("""    bag = SLOTS.map((s, k) => SET_KEYS.flatMap(key => [false, true].flatMap(mana => RAR.map((_, r) => {
      const it = makeItem(s, r, lvl + r, mana, mana && r >= 4);   // чем реже вещь, тем выше её уровень (для примера)
      return Object.assign(it, { set: true, setKey: key, name: SETS[key].names[k], id: `${key}-${r}${mana ? "-m" : ""}` });
    }))));""", """    bag = SLOTS.map((s, k) => {
      const it = makeItem(s, s.demo, lvl + s.demo, false, false);
      return [Object.assign(it, { set: true, setKey: "samurai", name: SETS.samurai.names[k], id: `samurai-${s.demo}` }), ...lootBag[k]];
    });""")
rep("  function generate() {", "  const lootBag = SLOTS.map(() => []);                 // выбитое прокруткой\n  function generate() {")
rep("  generate();\n})();", js + """
  const lootRoll = () => L.roll(+document.getElementById("lootR").value, document.getElementById("lootMana").checked ? true : undefined);
  document.getElementById("lootGo").addEventListener("click", lootRoll);
  document.getElementById("lootGo3").addEventListener("click", () => { lootRoll(); setTimeout(lootRoll, 450); setTimeout(lootRoll, 900); });
  document.getElementById("lootSnd").addEventListener("change", e => L.sound(e.target.checked));
  generate();
})();""")


def uri(path):
    ext = path.rsplit(".", 1)[1]
    mime = {"webm": "video/webm", "ogg": "audio/ogg", "jpg": "image/jpeg"}.get(ext, f"image/{ext}")
    return f"data:{mime};base64," + base64.b64encode(open(os.path.join(d, path), "rb").read()).decode()


s = re.sub(r'url\("((?:ui/)?[\w_]+\.(?:png|jpg))"\)', lambda m: f'url("{uri(m.group(1))}")', s)
s = re.sub(r'"((?:ui/[\w]+\.(?:png|webm))|items(?:_gharn)?\.jpg)"', lambda m: '"' + uri(m.group(1)) + '"', s)
s = re.sub(r'`loot/\$\{n\}\.png`', lambda m: "LOOT_PNG[n]", s)
names = ["ink_strip", "ink_glow", "ink_ring", "slash", "splat_l", "splat_r", "blot_0", "blot_1", "blot_2", "blot_3", "blot_4", "blot_5", "orb_rainbow", "bag_closed", "bag_open"]
s = s.replace("  const L = (() => {", "  const LOOT_PNG = {" + ",".join(f'{n}:"{uri(f"loot/{n}.png")}"' for n in names) + "};\n  const L = (() => {", 1)
s = re.sub(r'"(loot/[\w]+\.(?:webp|ogg))"', lambda m: '"' + uri(m.group(1)) + '"', s)
keys = ["atk", "arm", "hp", "ha", "crit", "cdmg", "rphy", "rele", "aspd"]
sti = "const STI = {" + ",".join(f'{k}:"{uri(f"ui/st_{k}_s.png")}"' for k in keys) + "};\n"
s = s.replace('src="ui/st_${key}_s.png"', 'src="${STI[key]}"').replace("(() => {\n", "(() => {\n  " + sti, 1)
assert "loot/" not in re.sub(r"data:[^\"]+", "", s).replace("pax_rpg/src/location/loot/", ""), "не всё встроено"
open(os.path.join(d, "loot.html"), "w", encoding="utf-8").write(s)
print(len(s.encode()) // 1024, "KB")
