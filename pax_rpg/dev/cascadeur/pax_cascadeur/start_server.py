"""Сервер скриптов Cascadeur (встроенный scripts.mcp.script_server) на порту 8766: через него Claude выполняет
Python в Cascadeur (pax_corporations_dev/cascadeur_live.ps1). Стартует сам, когда Cascadeur подгружает команды;
команда меню — запустить вручную, если остановили. Порт 8765 встроенной команды «MCP.Start script server»
на этом ПК занят мостом Pax, поэтому свой порт."""
import scripts.mcp.script_server.server as script_server

PORT = 8766


def name():
    return "Pax.Start script server (8766)"


def description():
    return "Сервер скриптов для Claude (Pax RPG) на 127.0.0.1:8766"


def run(scene):
    if script_server.is_running():
        print(f"[Pax] script server already running")
        return
    script_server.start(scene, port=PORT)


def _autostart():
    try:
        if not script_server.is_running():
            script_server.start(None, port=PORT)
    except Exception as ex:                       # порт занят, модуль сервера сменился — Cascadeur работает дальше
        print(f"[Pax] script server autostart failed: {ex}")


_autostart()
