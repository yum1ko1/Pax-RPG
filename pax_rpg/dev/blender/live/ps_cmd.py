"""Команда для моста: отправить Python-код в открытый Blender через blender_live.ps1 (ставится в pax_corporations_dev).

    python ps_cmd.py code.py   → печатает строку для mcp__Bridge__shell
"""
import base64
import sys

b64 = base64.b64encode(open(sys.argv[1], encoding="utf-8").read().encode("utf-8")).decode()
print("& .\\pax_corporations_dev\\blender_live.ps1 '" + b64 + "'")
