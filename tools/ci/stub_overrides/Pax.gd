# Рабочие тела для прогона вне игры: пункты меню и команды консоли запоминаются (smoke может их вызвать).
var menu_items: Dictionary = {}
var commands: Dictionary = {}
func add_menu_item(id: String, caption: String, fn: Callable):
	menu_items[id] = fn
func register_command(name: String, handler: Callable, help: String = ""):
	commands[name] = handler
# Сеть — одиночная игра: active() false, send/on ничего не делают (в игре Pax.net есть всегда).
var net: PaxNet = PaxNet.new()
