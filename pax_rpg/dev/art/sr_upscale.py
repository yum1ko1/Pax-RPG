"""2× апскейл картинки нейросетью EDSR (OpenCV dnn_superres), по плиткам с перекрытием — фон инвентаря (stage.jpg).
    pip install opencv-contrib-python-headless
    модель: https://raw.githubusercontent.com/Saafke/EDSR_Tensorflow/master/models/EDSR_x2.pb
    python sr_upscale.py <вход> <выход.png> <EDSR_x2.pb>   (1536×1024 на CPU — ~9 мин)"""
import sys, time
import cv2
import numpy as np
src, dst, model = sys.argv[1:4]
sr = cv2.dnn_superres.DnnSuperResImpl_create()
sr.readModel(model)
sr.setModel("edsr", 2)
img = cv2.imread(src, cv2.IMREAD_COLOR)
h, w = img.shape[:2]
T, P = 256, 16
out = np.zeros((h * 2, w * 2, 3), np.uint8)
t0 = time.time()
for y in range(0, h, T):
    for x in range(0, w, T):
        y0, x0 = max(0, y - P), max(0, x - P)
        y1, x1 = min(h, y + T + P), min(w, x + T + P)
        up = sr.upsample(img[y0:y1, x0:x1])
        oy, ox = (y - y0) * 2, (x - x0) * 2
        th, tw = min(T, h - y) * 2, min(T, w - x) * 2
        out[y * 2:y * 2 + th, x * 2:x * 2 + tw] = up[oy:oy + th, ox:ox + tw]
    print(f"{y}/{h} {time.time() - t0:.0f}s", flush=True)
cv2.imwrite(dst, out)
print("done", out.shape)
