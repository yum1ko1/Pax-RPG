# Cascadeur через MCP-скрипты

- В Cascadeur: Scripts → MCP → Start script server 8766 (порт 8765 занят мостом Pax).
- `pax_corporations_dev\csc.ps1 -Code "..."` / `-File x.py` — выполнить Python в открытом Cascadeur.
- Шаблон рига для скелетов Meshy: `meshy_biped.qrt`. Риг: импорт glb (один клип на файл) →
  `rig_mode.on.run_raw(ds, [0,0.5,0])` → `RiggingToolWindowTool.editor(vs).create_from_qrt_by_fileName(qrt)` →
  `rig_mode.off.run(ds, True)`.
- AutoPhysics через API только выключается — включать кнопкой в программе.
- `split_clips_blender.py <glb> <out> Clip...` — по glb на клип; `clip_reach_blender.py <glb> Clip...` —
  досягаемость и скорость кистей/стоп по долям клипа (кадр удара = пик скорости).
