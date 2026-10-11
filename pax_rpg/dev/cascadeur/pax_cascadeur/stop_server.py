"""Остановить сервер скриптов (порт 8766)."""
import scripts.mcp.script_server.server as script_server


def name():
    return "Pax.Stop script server"


def description():
    return "Остановить сервер скриптов Claude (Pax RPG)"


def run(scene):
    script_server.stop(scene)
