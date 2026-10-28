"""ink_glow.png: размытая альфа полосы туши, белая (красится в игре) — свет под тушью.
    python make_glow.py <textures/loot>"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

d = sys.argv[1]
st = Image.open(os.path.join(d, "ink_strip.png"))
pad = 60
a = Image.new("L", (st.width + 2 * pad, st.height + 2 * pad), 0)
a.paste(st.getchannel("A"), (pad, pad))
a = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(22))
a = Image.fromarray((np.asarray(a).astype(np.float32) * 0.85).clip(0, 255).astype(np.uint8))
out = Image.merge("RGBA", [Image.new("L", a.size, 255)] * 3 + [a])
out.save(os.path.join(d, "ink_glow.png"), optimize=True)
print(out.size)
