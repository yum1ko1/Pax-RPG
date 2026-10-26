"""Карта мира (макет A5): рамки GPT на хромакее (gpt-refs: gpt/wui_parts/wui_*_0.png) → textures/world/*.png и
config/world_ui.json — окна рамок в долях, как config/hud2.json (key_hud.py снимает фон, build_hud2.holes ищет окна).

    python build_world_ui.py <папка с wui_*.png> <mods/pax_rpg>
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sp = importlib.util.spec_from_file_location('build_hud2', os.path.join(HERE, '..', 'hud2', 'build_hud2.py'))
B = importlib.util.module_from_spec(sp)
sp.loader.exec_module(B)
KEY = os.path.join(HERE, '..', 'hud', 'key_hud.py')
# имя ассета → (файл, ширина в макете 1920×1080; хранится ×1.5 под 1440p)
FRAMES = {'sky': ('wui_sky.png', 760), 'card': ('wui_card.png', 372), 'btn_red': ('wui_btn_red.png', 300),
          'btn_dark': ('wui_btn_dark.png', 300), 'round': ('wui_round.png', 76), 'popup': ('wui_popup.png', 420),
          'event': ('wui_event.png', 340)}
STORE = 1.5


def main(src, mod):
    path = f'{mod}/config/world_ui.json'
    cfg = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}   # city_art и прочее — руками
    cfg['_note'] = ('frames сгенерированы pax_rpg/dev/world_ui/build_world_ui.py: size — ширина рамки в макете 1920×1080, '
                    'aspect — h/w; holes — окна рамки [x0, y0, x1, y1] в долях её ширины и высоты. city_art — картинка '
                    'города в карточке (нет — герб империи).')
    cfg['frames'] = {}
    tmp = tempfile.mkdtemp()
    for key, (fn, w) in FRAMES.items():
        out = os.path.join(tmp, key + '.png')
        subprocess.run([sys.executable, KEY, os.path.join(src, fn), out, 'none'], check=True, capture_output=True)
        im = Image.open(out).convert('RGBA')
        hs = B.holes(np.asarray(im)[:, :, 3])
        W, H = im.size
        hs.sort(key=lambda r: (r[1] // 40, r[0]))
        cfg['frames'][key] = {'tex': f'textures/world/{key}.png', 'size': w, 'aspect': round(H / W, 5),
                              'holes': [[round(x0 / W, 5), round(y0 / H, 5), round(x1 / W, 5), round(y1 / H, 5)] for x0, y0, x1, y1 in hs]}
        sw = int(w * STORE)
        im.resize((sw, round(sw * H / W)), Image.LANCZOS).save(f'{mod}/textures/world/{key}.png', optimize=True)
        print(key, im.size, '→', sw, len(hs), 'окон', cfg['frames'][key]['holes'])
    json.dump(cfg, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent='\t')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
