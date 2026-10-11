"""Заглушки API Pax для проверки мода вне игры: из справочника tools/ci/pax_api/api-reference.md (копия
docs/modding/en/api-reference.md из папки игры) — классы PaxMod, PaxGame, Pax (автозагрузка) и остальные с теми же
сигнатурами и типами, тела пустые (возвращают значение по умолчанию). Так компилятор Godot проверяет типы вызовов
мода так же, как в игре.

    python gen_stubs.py <справочник.md> <папка заглушек> [stub_overrides]

stub_overrides/<Класс>.gd — рабочие тела отдельных функций (чтение файлов мода, переводы) для прогона арены.

Справочник обновился в игре (новая версия API) — скопировать его заново в tools/ci/pax_api/.
"""
import os
import re
import sys

CLASSES = {  # раздел справочника → (файл, extends, class_name или None для автозагрузки)
    "PaxMod": ("pax_mod.gd", "Node", "PaxMod"),
    "PaxGame": ("pax_game.gd", "RefCounted", "PaxGame"),
    "Pax": ("pax.gd", "Node", None),
    "PaxEconomy": ("pax_economy.gd", "RefCounted", "PaxEconomy"),
    "PaxVoxel": ("pax_voxel.gd", "RefCounted", "PaxVoxel"),
    "PaxNet": ("pax_net.gd", "RefCounted", "PaxNet"),
    "PaxPerf": ("pax_perf.gd", "RefCounted", "PaxPerf"),
    "PaxGraphics": ("pax_graphics.gd", "RefCounted", "PaxGraphics"),
}
DEFAULTS = {"void": None, "bool": "false", "int": "0", "float": "0.0", "String": '""', "StringName": '&""',
            "Array": "[]", "Dictionary": "{}", "Vector2": "Vector2.ZERO", "Vector3": "Vector3.ZERO",
            "Vector2i": "Vector2i.ZERO", "Vector3i": "Vector3i.ZERO", "Color": "Color()", "Rect2": "Rect2()",
            "Rect2i": "Rect2i()", "Basis": "Basis()", "Transform3D": "Transform3D()", "Callable": "Callable()",
            "Quaternion": "Quaternion()", "NodePath": "NodePath()"}


def body_for(ret):
    ret = (ret or "").strip()
    if ret in ("", "Variant"):
        return "return null"
    if ret == "void":
        return "pass"
    if ret in DEFAULTS:
        return "return " + DEFAULTS[ret]
    if ret.startswith("Packed") or ret.startswith("Array["):
        return "return " + (ret + "()" if ret.startswith("Packed") else "[]")
    if ret.startswith("Dictionary["):
        return "return {}"
    return "return null"


def main(src, out, overrides=None):
    text = open(src, encoding="utf-8").read()
    sections = re.split(r"^## (\w+)\s*$", text, flags=re.M)
    for i in range(1, len(sections), 2):
        name, body = sections[i], sections[i + 1]
        if name not in CLASSES:
            continue
        fname, base, cname = CLASSES[name]
        lines = [f"extends {base}"] if cname is None else [f"class_name {cname}", f"extends {base}"]
        lines.insert(0, "# Сгенерировано tools/ci/gen_stubs.py из api-reference.md — не править руками.")
        seen = set()
        extra = ""
        if overrides and os.path.exists(os.path.join(overrides, name + ".gd")):
            extra = open(os.path.join(overrides, name + ".gd"), encoding="utf-8").read()
            seen |= set(re.findall(r"^(?:func|var) (\w+)", extra, flags=re.M))   # их тела — из overrides
        for block in re.findall(r"```gdscript\n(.*?)```", body, flags=re.S):
            code = " ".join(l.strip() for l in block.strip().splitlines())
            m = re.match(r"(static )?func (\w+)\((.*)\)\s*(->\s*([\w\[\], ]+))?\s*:?\s*$", code)
            if m:
                fn = m.group(2)
                if fn in seen:
                    continue
                seen.add(fn)
                args = m.group(3)
                ret = (m.group(5) or "").strip()
                sig = f"{m.group(1) or ''}func {fn}({args})" + (f" -> {ret}" if ret else "") + ":"
                lines.append(sig)
                lines.append("\t" + body_for(ret))
                continue
            m = re.match(r"(var|signal) (\w+)(.*)$", code)
            if m and m.group(2) not in seen:
                seen.add(m.group(2))
                decl = m.group(0)
                if m.group(1) == "var":
                    decl = re.sub(r"\s*(:?=).*$", "", decl)       # без значения: оно может ссылаться на игру
                lines.append(decl)
                continue
            m = re.match(r"const (\w+)\s*(:?=)\s*(.+)$", code)
            if m and m.group(1) not in seen:
                seen.add(m.group(1))
                val = m.group(3)
                literal = re.match(r"\s*(-?\d|\"|'|&\"|true\b|false\b|\[|\{|Vector[23]i?\(|Color\()", val)
                if not literal or "preload(" in val or "load(" in val:   # ссылки на код игры — без значения
                    lines.append(f"const {m.group(1)} = null")
                elif val.count("{") != val.count("}") or val.count("[") != val.count("]"):
                    # справочник обрезал длинное значение — нужен только тип
                    lines.append(f"const {m.group(1)} = " + ("{}" if val.lstrip().startswith("{") else "[]"))
                else:
                    lines.append(f"const {m.group(1)} {m.group(2)} {val}")
        if extra:
            lines.append(extra)
        open(f"{out}/{fname}", "w", encoding="utf-8").write("\n".join(lines) + "\n")
        print(f"{fname}: {len(seen)} членов")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
