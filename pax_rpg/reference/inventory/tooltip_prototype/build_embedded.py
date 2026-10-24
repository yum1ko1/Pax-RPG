import base64, re, sys, os
d = sys.argv[1]
s = open(os.path.join(d, 'tooltip_src.html'), encoding='utf-8').read()
def uri(path):
    ext = path.rsplit('.', 1)[1]
    mime = "video/webm" if ext == "webm" else f"image/{'jpeg' if ext == 'jpg' else ext}"
    return f"data:{mime};base64," + base64.b64encode(open(os.path.join(d, path), 'rb').read()).decode()
s = re.sub(r'url\("((?:ui/)?[\w_]+\.(?:png|jpg))"\)', lambda m: f'url("{uri(m.group(1))}")', s)
s = re.sub(r'"((?:ui/[\w]+\.(?:png|webm))|items(?:_gharn)?\.jpg)"', lambda m: '"' + uri(m.group(1)) + '"', s)
keys = ["atk", "arm", "hp", "ha", "crit", "cdmg", "rphy", "rele", "aspd"]
sti = "const STI = {" + ",".join(f'{k}:"{uri(f"ui/st_{k}_s.png")}"' for k in keys) + "};\n"
assert 'src="ui/st_${key}_s.png"' in s
s = s.replace('src="ui/st_${key}_s.png"', 'src="${STI[key]}"').replace("(() => {\n", "(() => {\n  " + sti, 1)
open(os.path.join(d, 'tooltip.html'), 'w', encoding='utf-8').write(s)
print(len(s.encode()) // 1024, "KB")
