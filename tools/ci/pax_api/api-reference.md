# Pax API reference

_Generated from doc comments by `tools/modding/api_reference.py` — do not edit by hand._

Guides: [README](README.md) · [Code](04-code.md) · [Recipes](05-recipes.md)

## PaxMod

Base class of your mod's code (`extends PaxMod`). Override the callbacks you need.

### PaxMod — Callbacks

#### `_mod_loaded`

```gdscript
func _mod_loaded()
```

Mod code is loaded (launcher start, before any world). Register commands here.

#### `_world_ready`

```gdscript
func _world_ready(_game: PaxGame)
```

A world (new or loaded game) is fully built: bodies, factions, UI exist.

#### `_days_passed`

```gdscript
func _days_passed(_game: PaxGame, _from_day: int, _days: int)
```

Time moved forward: the world lived `days` days starting at `from_day`.

#### `_save_state`

```gdscript
func _save_state(_game: PaxGame) -> Dictionary
```

The game is being saved. Return a Dictionary (JSON types only) — it is stored in the save and handed back to `_game_loaded`. Return {} to store nothing.

#### `_game_loaded`

```gdscript
func _game_loaded(_game: PaxGame, _state: Dictionary)
```

A save was loaded. `state` is what `_save_state` returned last time ({} if none).

#### `_body_created`

```gdscript
func _body_created(_game: PaxGame, _body: Dictionary)
```

A celestial body was created in the 3D scene. `body` — the game's body record (name, kind, radius, node, material…). Change its material/node freely.

#### `_ship_arrived`

```gdscript
func _ship_arrived(_game: PaxGame, _ship: Dictionary)
```

A ship launched by anyone (see PaxGame.launch_ship) reached its target. ship["mod"] — id of the mod that launched it, ship["data"] — the data you passed.

#### `_data_reloaded`

```gdscript
func _data_reloaded()
```

Data caches were cleared by the console command `reload`. Re-read your JSON here.

### PaxMod — Constants

#### `ModDatabaseScript`

```gdscript
const ModDatabaseScript = preload("res://src/mods/ModDatabase.gd")
```

#### `SaveFolderScript`

```gdscript
const SaveFolderScript = preload("res://src/save/Save.gd")
```

#### `KeyMigration`

```gdscript
const KeyMigration = preload("res://src/save/KeyMigration.gd")
```

### PaxMod — Properties

#### `id`

```gdscript
var id: String
```

Base class for a Pax Universe mod's code. In mod.json:  "entry": "main.gd"   →   main.gd:  extends PaxMod Everything is optional: override only the callbacks you need. Your files live at res://mods/<id>/ — use `path` to build paths. Full guide: docs/modding/en/README.md  (RU: docs/modding/ru/README.md) Mod id from mod.json. / id мода из mod.json.

#### `manifest`

```gdscript
var manifest: Dictionary
```

Parsed mod.json (plus "root", "source", "enabled"). / Разобранный mod.json.

#### `root`

```gdscript
var root: String
```

"res://mods/<id>/"

### PaxMod — Methods

#### `path`

```gdscript
func path(relative: String) -> String
```

Path inside this mod: path("textures/sky.png") → "res://mods/<id>/textures/sky.png".

#### `load_json`

```gdscript
func load_json(relative: String, default_value = null)
```

JSON file of this mod (parsed). / JSON-файл мода.

#### `texture`

```gdscript
func texture(relative: String) -> Texture2D
```

Image from this mod (png/jpg/webp/svg/tga/bmp) — no Godot import needed.

#### `sound`

```gdscript
func sound(relative: String) -> AudioStream
```

Sound from this mod (ogg/mp3/wav).

#### `model`

```gdscript
func model(relative: String) -> Node3D
```

3D model from this mod (glb/gltf) → ready Node3D.

#### `shader`

```gdscript
func shader(relative: String) -> Shader
```

Shader from this mod (.gdshader).

#### `scene`

```gdscript
func scene(relative: String) -> Node
```

Scene from this mod (.tscn) → instance.

#### `load_resource`

```gdscript
func load_resource(relative: String) -> Resource
```

Any resource of this mod (scene, script, material…) — instead of load(path(...)).

#### `read_text`

```gdscript
func read_text(relative: String) -> String
```

Text file of this mod. / Текстовый файл мода.

#### `read_bytes`

```gdscript
func read_bytes(relative: String) -> PackedByteArray
```

Bytes of a file of this mod. / Байты файла мода.

#### `list_files`

```gdscript
func list_files(relative_folder := "") -> PackedStringArray
```

Files in a folder of this mod (relative names). / Файлы в папке мода.

#### `save_data`

```gdscript
func save_data(name: String, value)
```

Save any data of your mod (JSON-compatible) under a name; survives restarts.

#### `load_data`

```gdscript
func load_data(name: String, default_value = null)
```

#### `database`

```gdscript
func database(name: String = "data") -> RefCounted
```

Your mod's own SQLite database (shared by all games): user://mods_data/<id>/<name>.db. Returns a ModDatabase (query/table/index/insert/select/update/delete/transaction) or null if SQLite is not installed. Each thread gets its own connection, so it is safe from the world step too.

#### `save_database`

```gdscript
func save_database(name: String = "data") -> RefCounted
```

A database stored in the current game's save folder — it travels with the save. Null if no game is running or SQLite is not installed. / База в папке сейва партии.

#### `bundled_database`

```gdscript
func bundled_database(relative: String) -> RefCounted
```

A read-only .db file shipped inside your mod (res://mods/<id>/<relative>). Only SELECT.

#### `open_link`

```gdscript
func open_link(url: String) -> bool
```

Open a web link (https only) in the browser. / Открыть ссылку https в браузере.

#### `tr_key`

```gdscript
func tr_key(key: String, args: Array = []) -> String
```

Translated text: your mod's data/lang/<code>.json keys merge into the game dictionary.

#### `get_setting`

```gdscript
func get_setting(key: String, default_value = null)
```

Persistent per-mod settings (user://mod_settings/<id>.json) — survive across saves.

#### `set_setting`

```gdscript
func set_setting(key: String, value)
```

#### `hook`

```gdscript
func hook(name: String, handler: Callable, priority: int = 0) -> bool
```

Subscribe to a game hook — the game asks your mod at a key moment and you may change the data (see Pax.HOOKS and docs/modding/en/api-reference.md). hook("law_passed", func(d): log_info("law: " + str(d.law.get("title", ""))))

#### `ask_ai`

```gdscript
func ask_ai(channel: String, prompt: String, data: Dictionary, done: Callable, options: Dictionary = {}) -> bool
```

Ask the AI with your own prompt (see Pax.ask_ai). `done` gets a Dictionary.

#### `log_info`

```gdscript
func log_info(message: String)
```

Print to the Godot output and the in-game dev console (F8), tagged with the mod id.

#### `log_warning`

```gdscript
func log_warning(message)
```

#### `log_error`

```gdscript
func log_error(message)
```

## PaxGame

The running game. You get it in callbacks or as `Pax.game` (null in the launcher).

### PaxGame — Constants

#### `ProvincesScript`

```gdscript
const ProvincesScript = preload("res://src/sim/Provinces.gd")
```

The running game as seen by mods: a stable, documented facade over Main. Get it from callbacks (_world_ready(game) …) or anywhere via `Pax.game` (null while no world is loaded — e.g. in the launcher). STABLE: every method below keeps its name and meaning across game updates. UNSTABLE: `main`, `sim`, `world`, `stock` give raw access to the game's internals (Russian identifiers). Anything is possible there, nothing is promised.

#### `PaxEconomyScript`

```gdscript
const PaxEconomyScript = preload("res://src/mods/Economy.gd")
```

#### `KM_PER_UNIT`

```gdscript
const KM_PER_UNIT := 1000.0
```

1 scene unit = this many kilometres. / Сколько км в единице сцены.

#### `CalendarScript`

```gdscript
const CalendarScript = preload("res://src/core/Calendar.gd")
```

### PaxGame — Properties

#### `main`

```gdscript
var main: Node
```

Raw Main node (src/core/GameRoot.gd). DEPRECATED: goes away in two updates — use the methods of this class (ask in #моддинг if one is missing). The first access writes a warning to the Pax log with the replacement table: docs/modding/MAIN_TO_API.md.

#### `sim`

```gdscript
var sim
```

Simulation (src/sim/PlanetSim.gd): params of home planet, day, leader… UNSTABLE.

#### `world`

```gdscript
var world
```

World chronicle and colonies (src/sim/World.gd). UNSTABLE.

#### `stock`

```gdscript
var stock
```

Resources (src/economy/Resources.gd): stock {body: {resource: amount}}. UNSTABLE.

#### `econ`

```gdscript
var econ: RefCounted
```

The economy facade (src/mods/Economy.gd, PaxEconomy in the reference): catalogue of goods and enterprise types, the weekly step and its parts, enterprises, accounting, the world market, deposits. STABLE.

### PaxGame — Methods

#### `day`

```gdscript
func day() -> int
```

Days since the campaign start. / Дней от старта партии.

#### `date`

```gdscript
func date() -> Dictionary
```

{"year", "month", "day"} of the current in-game date.

#### `date_text`

```gdscript
func date_text() -> String
```

Human-readable date in the player's language style ("03.07.2030", "66 млн лет назад"…).

#### `set_speed`

```gdscript
func set_speed(speed: int)
```

Observation speed: 0 — pause, 1..5 — faster.

#### `body_names`

```gdscript
func body_names() -> PackedStringArray
```

Names of all celestial bodies in the scene (stars, planets, moons, mod bodies).

#### `body`

```gdscript
func body(name: String) -> Dictionary
```

Live body record (edit carefully). Keys: name, genus (star|rock|gas), radius (scene units), r_km, a_km (orbit), node (Node3D), material (ShaderMaterial), parameters (climate 0..1), map, open (discovered), description. {} if not found. (Before 0.24 the keys were Russian.)

#### `body_node`

```gdscript
func body_node(name: String) -> Node3D
```

The body's 3D node (MeshInstance3D) or null.

#### `body_material`

```gdscript
func body_material(name: String) -> Material
```

The body's material (ShaderMaterial for planets/stars) or null. set_shader_parameter freely.

#### `body_params`

```gdscript
func body_params(name: String) -> Dictionary
```

Climate parameters of a body, 0..1: temperature, water, biomass, radiation, atmosphere, urban, magnetic.

#### `set_body_param`

```gdscript
func set_body_param(name: String, param: String, value: float)
```

Change one climate parameter (0..1) and redraw the planet.

#### `province_count`

```gdscript
func province_count(body: String) -> int
```

Number of provinces on a body (0 if it has none). Province ids run from 1.

#### `province_at`

```gdscript
func province_at(body: String, direction: Vector3) -> int
```

Province id at a direction from the body's centre (unit vector; +Y is the north pole). 0 — water or none.

#### `province_direction`

```gdscript
func province_direction(body: String, id: int) -> Vector3
```

Direction from the body's centre to the middle of a province.

#### `province`

```gdscript
func province(body: String, id: int) -> Dictionary
```

Province record: name (player's language), owner ("" — nobody), area_km2, coastal, neighbours (ids), direction.

#### `province_owner`

```gdscript
func province_owner(body: String, id: int) -> String
```

Who owns the province ("" — nobody).

#### `set_province_owner`

```gdscript
func set_province_owner(body: String, id: int, owner: String)
```

Hand a province to a country (its exact name, see `countries`) or to nobody ("").

#### `provinces_of`

```gdscript
func provinces_of(body: String, owner: String) -> Array
```

Ids of all provinces a country owns on a body.

#### `economy`

```gdscript
func economy(body: String) -> Dictionary
```

The economy of a body: the live record the game steps every week (enterprises, prices, accounting, fulfilled needs…). {} if the body has no economy. Change it in place; the keys are the game's own.

#### `economy_context`

```gdscript
func economy_context(body: String) -> Dictionary
```

What the economy knows about the world this week — the context the game hands to the weekly step: people, science, corruption, price index, world prices, season, outside capacity and load, labour and tax multipliers, deposits… A fresh Dictionary: edit it and pass it to `economy_step`. {} if the body has no economy.

#### `econ_ok`

```gdscript
func econ_ok(body: String) -> Dictionary
```

Same as `economy_context` — the short name mods already used for the internal call.

#### `economy_step`

```gdscript
func economy_step(body: String, weeks: float, context: Dictionary = {})
```

Run the core economy step of a body yourself: production, consumption and the market for `weeks` weeks. `context` — from `economy_context`, changed as you like; empty — the game's own. Only the core: budget, deliveries, laws and science are the game's weekly step and are not run here. The world step may run off the main thread — do not touch nodes from a hook that calls this.

#### `season`

```gdscript
func season(body: String = "") -> Dictionary
```

The season on a body right now: {name: "winter" | "spring" | "summer" | "autumn" | "none", strength: -1 (deep winter) … 1 (high summer), food: harvest multiplier, cold: 0…1 heating need, omen: bool, years: present for a wrong, planet-wide winter}. For the home body it is the season at the player's capital. {} if the body is unknown.

#### `season_food`

```gdscript
func season_food(body: String = "") -> float
```

Harvest multiplier of the season on a body (1.0 — no effect). / Множитель урожая от сезона.

#### `season_cold`

```gdscript
func season_cold(body: String = "") -> float
```

How cold it is on a body, 0 (not winter) … 1 (the hardest winter). / Холод на теле, 0…1.

#### `deposits`

```gdscript
func deposits(province: int) -> Dictionary
```

Deposits of a province of the home body: {kind: {left, depleted_percent}} for oil, gas, coal, ores… {} — none. All provinces at once — `econ.deposits_map()`.

#### `deposit_left`

```gdscript
func deposit_left(province: int, kind: String) -> float
```

How much of a deposit is left in a province (0 — none or exhausted). / Сколько залежи осталось.

#### `deposit_was`

```gdscript
func deposit_was(province: int, kind: String) -> float
```

How much of a deposit the province had at the start. / Сколько залежи было изначально.

#### `deposit_put`

```gdscript
func deposit_put(province: int, kind: String, amount: float)
```

Make sure a province holds at least `amount` of a deposit (a smaller one grows to it, a bigger one

#### `deposit_add`

```gdscript
func deposit_add(province: int, kind: String, amount: float)
```

Add to a deposit of a province. / Добавить к залежи провинции.

#### `deposit_take`

```gdscript
func deposit_take(province: int, kind: String, amount: float) -> float
```

Take from a deposit; returns how much was really taken. / Взять из залежи; вернёт, сколько взято.

#### `nature_strength`

```gdscript
func nature_strength(province: int, kind: String) -> float
```

What nature gives in a province without digging — strength 0…1 of "soil", "forest", "fish", "sun", "wind", "water"… (data/economy: nature kinds). / Сила природного дара провинции, 0…1.

#### `home_body`

```gdscript
func home_body() -> String
```

The player's home body (usually Earth).

#### `focused_body`

```gdscript
func focused_body() -> String
```

Body the camera looks at.

#### `focus`

```gdscript
func focus(name: String, instant: bool = false)
```

Fly the camera to a body.

#### `set_discovered`

```gdscript
func set_discovered(name: String, discovered: bool = true)
```

Mark a body discovered/undiscovered (visible in the scene and lists).

#### `systems`

```gdscript
func systems() -> Array
```

Star systems: [{name, star, position_ly: Vector3, mass (suns), description}]. Index 0 — the Solar System.

#### `body_system`

```gdscript
func body_system(name: String) -> String
```

Name of the star system a body belongs to.

#### `system_bodies`

```gdscript
func system_bodies(system_name: String) -> PackedStringArray
```

Bodies of one star system.

#### `distance_km`

```gdscript
func distance_km(from_body: String, to_body: String) -> float
```

Current distance between two bodies, km (-1 if a body is missing).

#### `distance_ly`

```gdscript
func distance_ly(from_body: String, to_body: String) -> float
```

Same in light years.

#### `galaxies`

```gdscript
func galaxies() -> Array
```

Galaxies you can enter: "млечный" (Milky Way) and neighbours with "key" and "stars_of" in data/galaxy.json.

#### `galaxy`

```gdscript
func galaxy(key: String = "млечный") -> Dictionary
```

A galaxy by key: {"stars": [star…], "radius", "sun", "offset", …}. Star: {id, галактика, name: {ru, en}, class, x, z, famous, system, sv_years}. Deterministic: same for every player.

#### `chart_star`

```gdscript
func chart_star(star_key: String) -> String
```

Build a star's system now (as if the player entered it). `star_key` — "млечный:17". Returns the system name ("" if no such star). Bodies appear as usual (body_created fires).

#### `enter_star`

```gdscript
func enter_star(star_key: String)
```

Fly the camera into a star's system (builds it first if needed; opens its secret if it has one).

#### `charted_stars`

```gdscript
func charted_stars() -> Array
```

Keys of stars whose systems are built in this game ("млечный:17", …).

#### `secrets_found`

```gdscript
func secrets_found() -> Array
```

Ids of galaxy secrets found in this game.

#### `travel_days`

```gdscript
func travel_days(from_body: String, to_body: String, speed_c: float) -> int
```

Days a ship needs at `speed_c` (fraction of light speed, 0.0001..0.99). Minimum 30.

#### `launch_ship`

```gdscript
func launch_ship(from_body: String, to_body: String, speed_c: float, people: float,
```

Launch an ark/ship. `people` are taken from the colony on `from_body` (if any). On arrival at a rocky body: a colony is founded (or grows), the body becomes discovered, a chronicle entry is written, then Pax.ship_arrived / PaxMod._ship_arrived fire. `model`: ковчег | станция | спутник | орбиталка. `data` — anything JSON, returned on arrival. Returns the ship record ({} if a body is missing). Saved in the save file automatically.

#### `ships`

```gdscript
func ships() -> Array
```

Ships in flight (live records).

#### `resources`

```gdscript
func resources(body_name: String) -> Dictionary
```

Resource stock of a colony body: {"humans": 120, "energy": …}. Live dictionary. {} if no colony.

#### `add_resource`

```gdscript
func add_resource(body_name: String, resource: String, amount: float) -> float
```

Add (or subtract with a negative amount) a resource on a colony. Creates the key if missing. Returns the new amount.

#### `colonies`

```gdscript
func colonies() -> PackedStringArray
```

Bodies where the player has colonies.

#### `people`

```gdscript
func people(body_name: String) -> float
```

People living on a body.

#### `add_character`

```gdscript
func add_character(body_name: String, info: Dictionary, portrait: String = "", open_talk: bool = false) -> bool
```

Add a person the player can meet and talk to (the AI plays them using these fields). `info` keys (all text in the player's language): name (required), who (role), lore (backstory), character (personality), age (number), чем_занят (what they do), wants (what they want). `portrait` — optional image path from your mod (png/jpg, any size; 256×320 looks best). The body must have a colony or inhabitants. Returns false if not added.

#### `has_character`

```gdscript
func has_character(name: String) -> bool
```

Is there already a person with this name (met or added)?

#### `factions`

```gdscript
func factions() -> Array
```

All factions (live array of dictionaries: name, type, colour, ours, capital, description…).

#### `player_faction`

```gdscript
func player_faction() -> Dictionary
```

The faction the player leads.

#### `country`

```gdscript
func country() -> String
```

The player's country (or side) name.

#### `countries`

```gdscript
func countries() -> PackedStringArray
```

Names of all other countries and factions.

#### `query`

```gdscript
func query(sql: String, parameters: Array = []) -> Array
```

Read the game with SQL (SELECT only): tables chronicle(day, body, tone, text, weight), provinces(id, owner, name) for the home planet, countries(name, humans, ours). A snapshot of the world is built on the first call of the day (per thread) and reused. Returns rows (Array of Dictionary); [] if SQLite is not installed or the SQL is not a SELECT.

#### `money`

```gdscript
func money() -> float
```

Money in the treasury (the home body's «деньги»).

#### `add_money`

```gdscript
func add_money(amount: float) -> float
```

Add (or take with a negative amount) money. Returns the new amount.

#### `relation`

```gdscript
func relation(country_name: String) -> float
```

Relations with a country, 0 (hostile) … 1 (ally). -1 if there is no such country.

#### `change_relation`

```gdscript
func change_relation(country_name: String, delta: float) -> float
```

Shift relations with a country by `delta` (clamped to 0..1). Returns the new value or -1.

#### `at_war`

```gdscript
func at_war(country_name: String = "") -> bool
```

Is the player at war — with `country_name`, or with anyone if empty.

#### `declare_war`

```gdscript
func declare_war(country_name: String)
```

Declare war on a country (the war_declared hook runs; a mod may cancel it).

#### `laws`

```gdscript
func laws() -> PackedStringArray
```

Titles of the laws in force.

#### `government_form`

```gdscript
func government_form() -> String
```

Form of government key (see data/politics/forms.json), "" if none.

#### `show_choice`

```gdscript
func show_choice(title: String, text: String, options: PackedStringArray, done: Callable, image: String = "")
```

Show a choice card: title, text, optional picture from your mod, and buttons. `done` gets the index of the chosen option. The card waits for the player.

#### `toast`

```gdscript
func toast(text: String)
```

Short message in the on-screen feed (BBCode allowed).

#### `chronicle`

```gdscript
func chronicle(body_name: String, text: String, tone: String = "neutral", weight: int = 2)
```

Permanent chronicle entry. tone: good | bad | mixed | neutral. weight 1..5 — how important.

#### `tr_key`

```gdscript
func tr_key(key: String) -> String
```

Game translation by key (includes keys added by mods' data/lang/<code>.json).

#### `language`

```gdscript
func language() -> String
```

Current language code: ru, en, de…

#### `add_bottom_button`

```gdscript
func add_bottom_button(text: String, on_pressed: Callable, width: float = 110.0) -> Button
```

Add a button to the bottom bar. Returns it (change icon, tooltip, disable…).

#### `add_window`

```gdscript
func add_window(button_text: String, content: Control, min_size: Vector2 = Vector2(380, 300)) -> PanelContainer
```

Add a window above the bottom bar, opened/closed by its own bottom button, hidden when another game window opens. `content` — any Control you built. Returns the window panel.

#### `hud_layer`

```gdscript
func hud_layer() -> CanvasLayer
```

CanvasLayer of the game HUD — add any Control on top of the game.

#### `scene_root`

```gdscript
func scene_root() -> Node
```

Node to add your own 3D objects to (the 3D world root) (ships, stations, effects). The scene uses a floating origin: to stay attached to a body, add your node as a child of `body_node`.

#### `camera`

```gdscript
func camera() -> Camera3D
```

The game camera.

## Pax

Autoload singleton, available everywhere as `Pax`: signals, data with mods applied, console.

### Pax — Signals

#### `mods_loaded`

```gdscript
signal mods_loaded
```

All mods' code is loaded (instances exist, _mod_loaded called).

#### `world_ready`

```gdscript
signal world_ready(game: PaxGame)
```

A world is fully built (new game or loaded save).

#### `days_passed`

```gdscript
signal days_passed(game: PaxGame, from_day: int, days: int)
```

The world lived `days` days from `from_day`.

#### `days_starting`

```gdscript
signal days_starting(game: PaxGame, from_day: int, days: int)
```

Time is about to move (before the world step) — changes made here count in this step.

#### `body_created`

```gdscript
signal body_created(game: PaxGame, body: Dictionary)
```

A body was created in the 3D scene (record — see PaxGame.body()).

#### `saving`

```gdscript
signal saving(game: PaxGame, mods_state: Dictionary)
```

The game is saving; write into `mods_state`[your_id] if you don't use PaxMod._save_state.

#### `loaded`

```gdscript
signal loaded(game: PaxGame, mods_state: Dictionary)
```

A save was loaded; `mods_state` — what was stored by mods.

#### `ship_launched`

```gdscript
signal ship_launched(game: PaxGame, ship: Dictionary)
```

A ship/ark was launched (record: id, origin, where_to, s_day, until_day, speed_c, humans, data, mod).

#### `ship_arrived`

```gdscript
signal ship_arrived(game: PaxGame, ship: Dictionary)
```

A ship/ark reached its target (a colony is founded or grows before this fires).

#### `data_reloaded`

```gdscript
signal data_reloaded
```

Console command `reload`: data caches cleared.

#### `system_charted`

```gdscript
signal system_charted(game: PaxGame, system_name: String, star: Dictionary)
```

A star's system was built in the galaxy (first entry). `star` — see PaxGame.galaxy().

#### `secret_found`

```gdscript
signal secret_found(game: PaxGame, secret_id: String, body_name: String)
```

A galaxy secret (data/galaxy_secrets.json) was found; `body_name` — where its guests appeared.

#### `log_added`

```gdscript
signal log_added(mod_id: String, text: String, level: String)
```

Any mod log line (for tools).

### Pax — Constants

#### `DiscordPresenceScript`

```gdscript
const DiscordPresenceScript = preload("res://src/platform/discord/DiscordPresence.gd")
```

Pax — the modding API singleton (autoload). Available everywhere as `Pax`. • Signals — subscribe from any script:  Pax.days_passed.connect(func(game, from_day, days): …) • Data with mods applied — Pax.json("res://data/bodies.json"), Pax.texture(…), Pax.model(…) • The running game — Pax.game (PaxGame, null in the launcher) • Dev console — F8 in game or launcher; add commands with Pax.register_command(…) Guide: docs/modding/en/README.md

#### `ProtectedScript`

```gdscript
const ProtectedScript = preload("res://src/mods/Protected.gd")
```

#### `ProviderScript`

```gdscript
const ProviderScript = preload("res://src/ai/Provider.gd")
```

#### `TerminalScript`

```gdscript
const TerminalScript = preload("res://src/ui/Terminal.gd")
```

#### `ModsScript`

```gdscript
const ModsScript = preload("res://src/mods/Mods.gd")
```

#### `KeyMigrationScript`

```gdscript
const KeyMigrationScript = preload("res://src/save/KeyMigration.gd")
```

#### `DevConsoleScript`

```gdscript
const DevConsoleScript = preload("res://src/mods/DevConsole.gd")
```

#### `ModCheckScript`

```gdscript
const ModCheckScript = preload("res://src/mods/ModCheck.gd")
```

#### `CodeGuardScript`

```gdscript
const CodeGuardScript = preload("res://src/mods/CodeGuard.gd")
```

#### `ModTrustScript`

```gdscript
const ModTrustScript = preload("res://src/mods/ModTrust.gd")
```

#### `ModEventsScript`

```gdscript
const ModEventsScript = preload("res://src/mods/ModEvents.gd")
```

#### `API_VERSION`

```gdscript
const API_VERSION := ModsScript.API_VERSION
```

API version. Bumped only on breaking changes; mods declare "api" in mod.json.

#### `ServiceRegistryScript`

```gdscript
const ServiceRegistryScript = preload("res://src/core/ServiceRegistry.gd")
```

World event bus (the game's own features subscribe the same way): `Pax.bus.on("step_rules", Callable(self, "_my_step"), 50, "<mod id>")`. Events: step_begin (game, days), step_rules (game, days), loaded (game), hud_built (game), map_layers (game, indicators), map_pushed (game), resource_rows (panel, body), lore (game, out), data_changed (). Lower order runs first. Subscriptions made with the mod id as owner are removed when the mod is unloaded.

#### `WorldStepScript`

```gdscript
const WorldStepScript = preload("res://src/sim/WorldStep.gd")
```

#### `SystemsScript`

```gdscript
const SystemsScript = preload("res://src/core/Systems.gd")
```

#### `GameModesScript`

```gdscript
const GameModesScript = preload("res://src/core/GameModes.gd")
```

#### `UiRulesScript`

```gdscript
const UiRulesScript = preload("res://src/core/UiRules.gd")
```

#### `KEYS_MARK`

```gdscript
const KEYS_MARK := ".keys_en"
```

#### `KEYS_RULES`

```gdscript
const KEYS_RULES := "2"
```

#### `HOOKS`

```gdscript
const HOOKS := {
```

Hooks: the game asks mods at key moments. A handler receives ONE Dictionary and may change it in place (or return a Dictionary to merge into it). Hooks marked [cancel] stop the action when a handler sets d["cancel"] = true. Game records inside (law, faction, research, order request…) use English keys, the same as in data/*.json. A cancelled order gets d["reason"] shown to the player. Pax.hook("law_passed", func(d): Pax.game.toast("Passed: " + d.law.get("title", ""))) Pax.hook("order_parsed", func(d): if "nuke" in d.order: d.cancel = true)

#### `HOOKS_CANCEL`

```gdscript
const HOOKS_CANCEL := ["order_parsed", "war_declared", "ai_request", "secret_reveal"]
```

Hooks that can be cancelled with d["cancel"] = true.

#### `AI_PER_MINUTE`

```gdscript
const AI_PER_MINUTE := 12
```

How many AI requests one mod may send per real minute: a broken mod must not burn the player's money.

### Pax — Properties

#### `bus`

```gdscript
var bus: Script
```

#### `features`

```gdscript
var features: Script
```

Feature registry (the game's own features are listed there): a mod declares its feature with `Pax.features.register({"id": "<mod id>", "scripts": ["res://mods/<id>/my_feature.gd"], "optional": true})`; the scripts may define `static func declare_state(fs)` and `static func connect_bus(bus)` — both are called right away if the game is already running. The manifest may also carry "editor" (world editor blocks), "editor_tabs", "sections" (its sections of the world rules file) and "rule_points". See docs/modding, page 10.

#### `state`

```gdscript
var state: Script
```

Feature state registry: what features keep in the game (save, multiplayer, time machine). Read a declared value with `Pax.state.value(game.model.features, "<key>")`; declare it in your feature script's `static func declare_state(fs)` with `fs.declare(key, default, {"personal": false, "rollback": "keep", "epoch": "keep"})`.

#### `rule_points`

```gdscript
var rule_points: Script
```

Rule points — places where the game asks the world for its own formula (data/rule_points.json). A mod adds its points with rule_points.patch.json or with "rule_points" in its feature manifest; the world editor then offers them to the author. `Pax.rule_points.all()` lists the points and the names a formula sees there.

#### `jobs`

```gdscript
var jobs: Script
```

Threads: the game's own job system (the game spreads its heavy calculations over CPU cores through it). `Pax.jobs.map(items, fn)` runs `fn(item)` on all cores and returns the results in the order of `items`; `Pax.jobs.background(work, done)` computes in a thread and calls `done(result)` on the main thread. A task must be pure: read its input, return a result, never touch nodes, UI or shared dictionaries. Use `Pax.jobs.rng(day, id)` for randomness inside a task.

#### `game`

```gdscript
var game: PaxGame
```

The running game or null (launcher, main menu before a world exists).

#### `instances`

```gdscript
var instances
```

Loaded mod code instances by id.

#### `log_lines`

```gdscript
var log_lines: Array
```

Recent log lines [{mod, text, level}] — shown in the dev console.

#### `events`

```gdscript
var events
```

Events and decisions from data/mod_events.json (no-code modding). / События и решения модов.

#### `voxel`

```gdscript
var voxel
```

Voxels for mods: models from data, voxel planets and terrain, provinces on them (see PaxVoxel in the reference).

#### `graphics`

```gdscript
var graphics
```

Graphics for mods: planet atmospheres, clouds, lens flares, post effects, sky, scattering (see PaxGraphics).

#### `perf`

```gdscript
var perf
```

Performance for mods: FPS/CPU/GPU panel, stats, distance LOD and impostors, MultiMesh, occluders (see PaxPerf).

#### `net`

```gdscript
var net
```

Multiplayer for mods: is this a network game, who is in it, your own messages between the players' copies of a mod (see PaxNet).

#### `map_editor`

```gdscript
var map_editor
```

Map editor building blocks (vector borders, topology, dimensions, map features) — see PaxMapEditor.

#### `terminals`

```gdscript
var terminals
```

### Pax — Methods

#### `enable_mods`

```gdscript
func enable_mods()
```

Called when the game starts (license checked). / Зовут при входе в игру.

#### `sleep_mods`

```gdscript
func sleep_mods()
```

#### `terminal_hide`

```gdscript
func terminal_hide(mod_folder: String, window: Control)
```

#### `terminal_return`

```gdscript
func terminal_return(mod_folder: String) -> Control
```

#### `pty_create`

```gdscript
func pty_create() -> Node
```

#### `pty_release`

```gdscript
func pty_release(p: Node)
```

#### `code_was_run`

```gdscript
func code_was_run() -> bool
```

#### `reload_mods`

```gdscript
func reload_mods(force_code := false)
```

Re-read mods and apply toggles/order right away: data caches are cleared, code of disabled mods is unloaded (_mod_unloaded, then freed), newly enabled mods are loaded. The launcher calls this when you tick a mod — no restart needed. force_code: reload code even if the version did not change (F6 in game — for modders).

#### `world_rule`

```gdscript
func world_rule(point: String, default_value: float, seen: Dictionary = {}) -> float
```

Ask the world for its own value at a rule point. Returns `default_value` unless the world's rules (data/world_formulas.json → "rules") define a formula for `point`; `seen` — the values that formula may read.

#### `json`

```gdscript
func json(path: String, default_value = null)
```

Game JSON with all enabled mods' replacements and patches. Returns a deep copy.

#### `text`

```gdscript
func text(path: String) -> String
```

Text file with mods' replacements/appends (prompts, news, markdown).

#### `exists`

```gdscript
func exists(path: String) -> bool
```

Does the file exist in the game or any enabled mod?

#### `resolve`

```gdscript
func resolve(path: String) -> String
```

Final path of a file after mod overrides (the last mod that has it wins).

#### `list_files`

```gdscript
func list_files(folder: String) -> PackedStringArray
```

File names in a game folder merged with the same folder of every enabled mod.

#### `texture`

```gdscript
func texture(path: String) -> Texture2D
```

#### `sound`

```gdscript
func sound(path: String) -> AudioStream
```

#### `model`

```gdscript
func model(path: String) -> Node3D
```

#### `shader`

```gdscript
func shader(path: String) -> Shader
```

#### `bytes`

```gdscript
func bytes(path: String) -> PackedByteArray
```

Raw bytes of a game file with mod overrides: province maps (*.bin), pictures, any binary data.

#### `list_folders`

```gdscript
func list_folders(folder: String) -> PackedStringArray
```

Folder names in a game folder merged with the same folder of every enabled mod.

#### `image`

```gdscript
func image(path: String) -> Image
```

Picture as pixels (Image), not as a texture: read or change it, then ImageTexture.create_from_image().

#### `resource`

```gdscript
func resource(path: String) -> Resource
```

Any resource of the game by its res:// path: a script (call its static functions, make an instance, read its constants), a scene (PackedScene), a font, a material, a mesh, a theme. Everything in res:// is open except the protected core — the player's keys, the licence and the mod guard: for those and for a missing file it returns null. Use it instead of load()/preload() of game paths.

#### `scene`

```gdscript
func scene(path: String) -> Node
```

A fresh instance of a game scene (res://….tscn); null if there is no such scene.

#### `has_resource`

```gdscript
func has_resource(path: String) -> bool
```

Is there such a file or resource in res:// (the game itself, without mod layers)? For data use exists().

#### `mods`

```gdscript
func mods() -> Array
```

Enabled mods' manifests in load order.

#### `has_mod`

```gdscript
func has_mod(mod_id: String) -> bool
```

Is a mod with this id enabled? Use for optional integration between mods.

#### `get_mod`

```gdscript
func get_mod(mod_id: String) -> PaxMod
```

Code instance of another mod (or null) — call its public methods for cross-mod APIs.

#### `tr_key`

```gdscript
func tr_key(key: String, args: Array = []) -> String
```

Translation by key with %s args. Works in launcher and game.

#### `log_line`

```gdscript
func log_line(mod_id: String, message: String, level: String = "info")
```

#### `hook`

```gdscript
func hook(name: String, handler: Callable, priority: int = 0) -> bool
```

Subscribe to a hook (names — see [constant HOOKS]). Higher `priority` runs first. Returns false for an unknown hook name.

#### `emit_hook`

```gdscript
func emit_hook(name: String, data: Dictionary = {}) -> Dictionary
```

Fire a hook yourself. Two uses: (1) your own events for other mods — name them "your_mod_id.event" (a dot in the name; such hooks need no declaration, anyone may `hook` them); (2) a game hook your mod takes over — a mod that replaces the economy step still fires "economy_week", so mods built on it keep working. Handlers run by priority and may change `data` or return a Dictionary to merge; Pax.emit_hook("my_econ.prices_set", {"body": body, "prices": prices})

#### `hooks`

```gdscript
func hooks() -> Dictionary
```

All hook names with their descriptions (for tools and the console).

#### `ask_ai`

```gdscript
func ask_ai(channel: String, prompt: String, data: Dictionary, done: Callable, options: Dictionary = {}) -> bool
```

Ask the AI with your own prompt. The game adds the world's lore, rules and the player's language, counts the cost under channel "mod_<id>_<channel>" and calls `done` with the parsed JSON answer (empty Dictionary — no AI, error or limit). Pax.ask_ai("oracle", "You are an oracle… Return ONLY JSON: {\"prophecy\": \"…\"}", {"country": Pax.game.player_faction().get("name", "")}, func(a): print(a.get("prophecy", ""))) Your prompt should end with the JSON you expect. Returns false if the request was not sent.

#### `schema_errors`

```gdscript
static func schema_errors(answer: Dictionary, schema: Dictionary) -> Array
```

#### `register_condition`

```gdscript
func register_condition(name: String, check: Callable)
```

Add a condition keyword for data/mod_events.json. `check` gets (value, game) and returns bool. Pax.register_condition("my_mod_winter", func(v, game): return game.date().month in [12, 1, 2])

#### `register_effect`

```gdscript
func register_effect(name: String, apply: Callable)
```

Add an effect keyword for data/mod_events.json. `apply` gets (value, game). Pax.register_effect("my_mod_spawn_ark", func(v, game): game.launch_ship(…))

#### `fire_event`

```gdscript
func fire_event(id: String) -> bool
```

Fire an event from data/mod_events.json by id right now (ignores its conditions and chance).

#### `replace_service`

```gdscript
func replace_service(id: String, script_path: String) -> String
```

Replace a game service (system) with your script — usually `extends "res://src/economy/Market.gd"` overriding what you need. `id` is the service name (as in the game code: "market", "elections", "research"…). Applies from the next game start. The protected core (payments, licence, account, keys, the mod sandbox) can't be replaced; network play can: "network", "multiplayer". Returns "" on success or the reason it was refused.

#### `replace_module`

```gdscript
func replace_module(module: String, script_path: String) -> String
```

Replace a rules module (elections, state, cadres, diplomacy, technologies, market, easter eggs, quests… — names in data/modules.json, or a res://src/… path) by functions: your script's `static func` with the same names run instead of the game's; the rest stay as in the game. The game's version of foo is Module._base_foo(…) — call it to wrap instead of rewrite. Applies at once. Returns "" or the reason.

#### `disable_service`

```gdscript
func disable_service(id: String) -> String
```

Turn a game service off: the world step skips its stages and its windows hide (as each system moves to the pipeline and features). The protected core can't be disabled.

#### `step_stage`

```gdscript
func step_stage(id: String, fn: Callable, where: Dictionary = {})
```

Add your own stage to the world step. `fn` is called as fn(ctx: Dictionary) with ctx.d (days in this step), ctx.with_dice (light far rewind), and whatever earlier stages put there. `where`: {"after": "market"} or {"before": "armies"} (stage ids — data/world_step.json); without it the stage goes last. Runs on the world thread: no windows or nodes (show via an event), randomness only from Pax.jobs.rng. Свою стадию в шаг мира.

#### `before_stage`

```gdscript
func before_stage(id: String, fn: Callable)
```

Run fn(ctx) right before a world-step stage (any stage, including other mods'). Several mods may wrap the same stage; they run in load order. World thread: no windows or nodes.

#### `after_stage`

```gdscript
func after_stage(id: String, fn: Callable)
```

Run fn(ctx) right after a world-step stage — read what it did, correct it. После стадии шага мира.

#### `on_event`

```gdscript
func on_event(event: String, fn: Callable, order: int = 100)
```

Subscribe to a world-bus event (step_begin, step_rules — world thread; resource_rows, map_layers, map_pushed, lore, loaded, hud_built, data_changed — main thread). `order`: lower runs first. Your subscriptions are removed when the mod unloads. Подписка на событие шины мира.

#### `on_event_plan`

```gdscript
func on_event_plan(event: String, plan: Callable, apply: Callable, order: int = 100)
```

Like on_event, but split: plan(args) runs on all cores (pure calculation, return a result), apply(result) runs in order on the event's thread. For heavy work in step_rules.

#### `remove_stage`

```gdscript
func remove_stage(id: String)
```

Remove a stage of the world step (e.g. "armies"). Убрать стадию шага мира.

#### `replace_stage`

```gdscript
func replace_stage(id: String, fn: Callable)
```

Replace a stage of the world step with fn(ctx). Заменить стадию шага мира своей.

#### `disable_system`

```gdscript
func disable_system(id: String) -> String
```

Turn a whole game system off (data/systems.json: "war", "market", "politics", "space", "research"…): its services and world-step stages stop, its AI rules are not sent. A world can do the same with meta.features.off. Applies from the next game start. Returns "" or the reason.

#### `set_victory`

```gdscript
func set_victory(fn: Callable)
```

Your own game's end: `fn` is called after every world step as fn(ctx) (ctx.day, ctx.d, ctx.game) and returns {} to go on, or {"result": "victory" | "defeat", "title": "…", "text": "…"}. The first result is shown to the player and sent to mods as the game_over hook. World thread: no windows.

#### `hide_ui`

```gdscript
func hide_ui(button_id: String)
```

Hide a game window button (codes: orders, projects, laws, power, facility, mining, course, science, planets, links, inbox, state, map, galaxy, rewind). Applies when the HUD is built.

#### `rename_ui`

```gdscript
func rename_ui(button_id: String, text: String)
```

#### `replace_window`

```gdscript
func replace_window(button_id: String, fn: Callable)
```

Open your own window instead of the game's: the button stays, pressing it calls `fn`.

#### `replace_show`

```gdscript
func replace_show(kind: String, fn: Callable)
```

Show your own window instead of the game's for a display event: "fate" (fate cards), "dilemma", "mystery_open", "base_open", "person_note", "camera_to"… — fn gets the same arguments as the game's

#### `hide_menu_item`

```gdscript
func hide_menu_item(id: String)
```

Hide a main menu item: "load", "new_game", "presets", "network", "settings". Спрятать пункт главного меню.

#### `add_menu_item`

```gdscript
func add_menu_item(id: String, caption: String, fn: Callable)
```

Add your own main menu item (your game's entry, your screen). Свой пункт главного меню.

#### `add_ui_button`

```gdscript
func add_ui_button(id: String, caption: String, fn: Callable)
```

Add your own button next to the game's window buttons. Своя кнопка рядом с кнопками окон.

#### `mod_conflicts`

```gdscript
func mod_conflicts() -> Array
```

Conflicts between mods' changes to the game (shown in the mod log when a game starts): [{"kind": "service" | "stage" | "useless_replacement", "id", "mods": [...], "why"}].

#### `services_report`

```gdscript
func services_report() -> Dictionary
```

What mods replaced and disabled: {"replaced": {id: {script, mod}}, "disabled": {id: mod}, "refused": {id: why}}.

#### `register_command`

```gdscript
func register_command(name: String, handler: Callable, help: String = "")
```

Add a dev-console command. `handler` receives PackedStringArray args and may return a String. Pax.register_command("spawn_ark", func(args): return "ok", "spawn_ark <star> — launch an ark")

#### `run_command`

```gdscript
func run_command(line: String) -> String
```

#### `pty_`

```gdscript
func pty_отпустить(p: Node)
```

#### `pty_`

```gdscript
func pty_создать() -> Node
```

## PaxEconomy

The economy for mods, available as `Pax.game.econ`: the catalogue of goods and enterprise types, the weekly step and its parts, enterprises, accounting, the world market, deposits — instead of the game's internals.

### PaxEconomy — Constants

#### `EconomyScript`

```gdscript
const EconomyScript = preload("res://src/economy/Economy.gd")
```

#### `WorldMarket`

```gdscript
const WorldMarket = preload("res://src/economy/Market.gd")
```

#### `WEEK_PARTS`

```gdscript
const WEEK_PARTS := ["jobs", "budget", "supplies", "laws", "science"]
```

Parts of the game's own week around the core step, in the order the game runs them.

### PaxEconomy — Methods

#### `goods`

```gdscript
func goods() -> Dictionary
```

Goods of this world: {key: {class, unit, price, people, flow…}} — data/economy/goods.json with mods and what the AI invented in this game. Live: read freely, add through `create_goods`.

#### `types`

```gdscript
func types() -> Dictionary
```

Enterprise types: {key: {kind, input, output, workers, science, costs, upkeep…}} — data/economy/enterprises.json with mods and invented ones. Live. / Типы предприятий — живой каталог.

#### `classes`

```gdscript
func classes() -> Dictionary
```

Goods classes: {class: {price, extraction, production…}}. / Классы товаров.

#### `goods_item`

```gdscript
func goods_item(key: String) -> Dictionary
```

One goods record ({} — unknown). / Запись товара.

#### `price`

```gdscript
func price(key: String, index: float = 1.0) -> float
```

Base price of a unit of goods at a price index (see `price_index`). / Базовая цена товара.

#### `people_norm`

```gdscript
func people_norm(key: String, science: float) -> float
```

What one person needs of the goods per week at a science level. / Норма на человека в неделю.

#### `flow`

```gdscript
func flow(key: String) -> bool
```

true — the goods is a flow (energy, services): made and spent the same week, never stored.

#### `classname`

```gdscript
func classname(key: String) -> String
```

Class of the goods ("fuel", "raw", "food"…). / Класс товара.

#### `price_index`

```gdscript
func price_index(year: float) -> float
```

Price index of a year (1.0 — today's money). / Индекс цен года.

#### `create_goods`

```gdscript
func create_goods(key: String, goods_class: String, options: Dictionary = {}) -> Array
```

Add a new goods to this world (as the AI does when it invents one). `goods_class` — a key of `classes`; `options` — any goods fields to set. Returns the game's record of the result.

#### `bodies`

```gdscript
func bodies() -> PackedStringArray
```

Bodies that have an economy the game steps every week. / Тела, у которых есть хозяйство.

#### `of`

```gdscript
func of(body: String) -> Dictionary
```

The live economy record of a body ({} — none). Same as PaxGame.economy. / Живая запись хозяйства тела.

#### `ensure`

```gdscript
func ensure(body: String) -> Dictionary
```

The economy of a body, created if the body has a colony and no economy yet (without one the colony is

#### `new_economy`

```gdscript
func new_economy() -> Dictionary
```

A fresh empty economy record — for your own bookkeeping or a dry run. / Пустая запись хозяйства.

#### `capacities`

```gdscript
func capacities(economy: Dictionary) -> Dictionary
```

Power capacities of an economy by station kind. / Мощности хозяйства по видам станций.

#### `output_per_week`

```gdscript
func output_per_week(economy: Dictionary, goods_key: String) -> float
```

How much of the goods an economy makes per week at full load. / Выпуск товара в неделю.

#### `add_enterprise`

```gdscript
func add_enterprise(body: String, type: String, province: int, levels: float) -> Dictionary
```

Add `levels` of an enterprise of a type in a province of a body. Returns its live record

#### `remove_enterprise`

```gdscript
func remove_enterprise(body: String, type: String, province: int, levels: float) -> float
```

Remove up to `levels` of an enterprise; returns how many were removed. / Снять уровни предприятия.

#### `shock`

```gdscript
func shock(body: String, industry: String, multiplier: float, weeks: float)
```

Shock an industry of a body: its output is multiplied for some weeks (strike, boom, blockade).

#### `context`

```gdscript
func context(body: String, apply_season: bool = true) -> Dictionary
```

What the economy of a body knows about the world this week (people, science, prices, season, deposits, labour and tax multipliers…) — a fresh Dictionary to edit and pass to `step`. `apply_season` false — do not let the call refresh the season shown on the map (ask for the context as often as you like). {} — no economy. / Условия недели для хозяйства тела.

#### `step`

```gdscript
func step(economy: Dictionary, stock: Dictionary, weeks: float, context_: Dictionary)
```

Run the core step — production, consumption, the market — on ANY economy record and stock, not only a body's own: your own economy, or duplicates for a dry run (pass `economy.duplicate(true)` and `stock.duplicate(true)`, and set `context["deposits"] = null` so the forecast does

#### `forecast`

```gdscript
func forecast(body: String, weeks: float, context_: Dictionary = {}) -> Dictionary
```

A dry run of a body's core step on copies: nothing in the game changes. Returns {economy, stock} as they would be after `weeks`. {} — no economy. / Прогноз: шаг на копиях, игра не меняется.

#### `week_part`

```gdscript
func week_part(part: String, body: String, weeks: float) -> bool
```

Run one part of the game's week around the core (see [constant WEEK_PARTS]): "jobs" — works and building sites, "budget" — taxes and spending, "supplies" — deliveries between bodies, "laws" — law-making, "science" — research. A mod that replaces the core step calls the parts it keeps. "jobs", "supplies" and "science" belong to the home body. false — unknown part or no economy.

#### `snapshot`

```gdscript
func snapshot() -> Dictionary
```

Stocks of every economy right now: {body: {goods: amount, money: …}} (flows are left out). Take it before you move goods, then call `account_since`. / Снимок складов всех хозяйств.

#### `account_since`

```gdscript
func account_since(before: Dictionary, article: String)
```

Write everything that changed in the stocks since `before` into the ledgers under an article ("deliveries", "trade", your own…) — the player sees it in the resources window.

#### `account`

```gdscript
func account(body: String, goods_key: String, article: String, amount: float)
```

Write one line into a body's ledger. / Одна строка в учёт тела.

#### `ledger`

```gdscript
func ledger(body: String) -> Dictionary
```

The ledger of an economy per week: {goods: {article: amount}}. / Учёт хозяйства за неделю.

#### `market_goods`

```gdscript
func market_goods() -> Dictionary
```

Goods traded on the world market: {key: record}. / Товары мирового рынка.

#### `world_price`

```gdscript
func world_price(goods_key: String) -> float
```

The world price of a unit of market goods now (0 — not traded). / Мировая цена сейчас.

#### `price_shift`

```gdscript
func price_shift(goods_key: String) -> float
```

How far the world price of the goods has moved from its base: 1.0 — at base, 1.3 — 30% dearer.

#### `set_price_shift`

```gdscript
func set_price_shift(goods_key: String, value: float)
```

Set the shift of a world price (see `price_shift`). / Задать сдвиг мировой цены.

#### `price_shifts`

```gdscript
func price_shifts() -> Dictionary
```

All price shifts: {goods: multiplier}. / Все сдвиги цен.

#### `prices_for_us`

```gdscript
func prices_for_us() -> Dictionary
```

What the market is for the player's country: {goods: {sale, purchase — multipliers to the world price from sanctions and reputation, allowed — how much it may buy}}. / Рынок для нашей страны.

#### `deposits_map`

```gdscript
func deposits_map(kind: String = "") -> Dictionary
```

Provinces of the home body that hold deposits: {province id: {kind: {left, depleted_percent}}}. `kind` — only this kind ("" — all). Walks every province: call it once, not every frame.

#### `wealth`

```gdscript
func wealth(body: String) -> Dictionary
```

What the body itself is rich in: {resource: 0…3}. Live. / Чем богато само тело.

#### `set_wealth`

```gdscript
func set_wealth(body: String, resource: String, value: float)
```

Set how rich a body is in a resource, 0…3. / Задать богатство тела ресурсом.

#### `outside_power`

```gdscript
func outside_power(body: String) -> Dictionary
```

Power the body has and needs outside the economy: {capacity, built, vehicles, jobs_now}.

#### `season_now`

```gdscript
func season_now() -> Dictionary
```

The season the map shows now (see PaxGame.season for its fields). / Сезон, который сейчас показывает карта.

#### `set_season_now`

```gdscript
func set_season_now(value: Dictionary)
```

Replace the season the map shows (the game recomputes it at the next week unless your mod keeps

## PaxVoxel

Voxels for mods, available as `Pax.voxel`: models from data, voxel planets and terrain, provinces on them.

### PaxVoxel — Constants

#### `ProvinceMapScript`

```gdscript
const ProvinceMapScript = preload("res://src/sim/Provinces.gd")
```

Voxels for mods: `Pax.voxel`. Voxel worlds, destructible planets and models built from data. The game itself does not use voxels; this is a toolbox for mods. Models (`model`, `model_mesh`) work everywhere. Terrain and planets need the "voxel" component (Voxel Tools by Zylann, MIT): put `"components": ["voxel"]` into mod.json — the launcher installs it and the game loads it before your code, so your scripts may use the Voxel* classes by name.

#### `ModsScript`

```gdscript
const ModsScript = preload("res://src/mods/Mods.gd")
```

#### `MODEL_LIMIT`

```gdscript
const MODEL_LIMIT := 96
```

#### `SHADER`

```gdscript
const SHADER := "res://shaders/voxel_planet.gdshader"
```

### PaxVoxel — Methods

#### `library_path`

```gdscript
static func library_path() -> String
```

#### `available`

```gdscript
func available() -> bool
```

True when the voxel component is installed (it may still be not loaded — see `enable`).

#### `ready`

```gdscript
func ready() -> bool
```

True when the Voxel* classes are loaded and usable.

#### `enable`

```gdscript
func enable() -> bool
```

Load the voxel component now. The game does it itself for mods with `"components": ["voxel"]` in mod.json. Returns false if the component is not installed.

#### `create`

```gdscript
func create(type: String) -> Object
```

Create an object of the voxel library by class name: "VoxelLodTerrain", "VoxelBuffer", "VoxelMesherTransvoxel", "VoxelGeneratorGraph", "ZN_FastNoiseLite"… null if the component is missing or the class is not part of it. Every class of the library is available, file streams included.

#### `constant`

```gdscript
func constant(type: String, name: String) -> int
```

Integer constant of a voxel class, e.g. constant("VoxelTool", "MODE_REMOVE"). -1 if unknown.

#### `model_grid`

```gdscript
func model_grid(data: Dictionary) -> Dictionary
```

Fill a voxel grid from a model description (see `model`). Returns {"size": Vector3i, "cells": PackedByteArray (palette index per cell, 0 = empty), "palette": Array[Color]}.

#### `model_mesh`

```gdscript
func model_mesh(data: Dictionary) -> ArrayMesh
```

Build a mesh from a voxel model described by data — no modelling tools needed: [codeblock] {"size": [32, 12, 32], "palette": ["#d8dce4", "#f2b33d", "#5b7fc7"], "shapes": [{"type": "torus", "center": [16, 6, 16], "radius": 12, "tube": 1.6, "color": 1}, {"type": "cylinder", "center": [16, 6, 16], "radius": 2.2, "height": 10, "color": 2}, {"type": "line", "from": [4, 6, 16], "to": [28, 6, 16], "color": 3}], "voxels": [[16, 11, 16, 2]]} [/codeblock] Shapes: box (from, to), sphere, cylinder, torus (center, radius, tube, axis), line (from, to, width); "color" is a palette index starting at 1, 0 carves. Up to 96 cells per side. Works without the voxel component. Vertex colours carry the palette.

#### `model`

```gdscript
func model(data: Dictionary) -> MeshInstance3D
```

Same as `model_mesh`, but returns a ready MeshInstance3D. "scale" in data sets the size of one voxel (default 1.0).

#### `planet`

```gdscript
func planet(params: Dictionary = {}) -> Node3D
```

A voxel planet: a sphere with relief, levels of detail, optionally editable (`dig`, `fill`). Needs the voxel component; returns null without it. params: radius (voxels, default 300), relief (height of hills in voxels, default 24), noise {seed, frequency, octaves}, heightmap (Image, 2:1, laid out like the game's planet maps; replaces noise), lods (2..8, default 5), editable (bool), color, material (Material), collisions (bool), occlusion (bool, default true — the far side of the planet is not drawn, see `occlusion`). Add it to the scene and attach a viewer to your camera: `viewer`.

#### `viewer`

```gdscript
func viewer(target: Node3D, distance: float = 2048.0) -> Node
```

Attach a voxel viewer to a camera (or any Node3D): terrain loads and refines around it. Without a viewer a voxel world stays empty.

#### `occlusion`

```gdscript
func occlusion(node: Node, enabled: bool = true)
```

Turn on occlusion culling for the window the node is shown in, so voxel planets do not draw their far side (planet() puts an invisible sphere inside each planet). viewer() calls it for you. Godot performs it in the main game window; inside a SubViewport it has no effect.

#### `dig`

```gdscript
func dig(terrain: Node, position: Vector3, radius: float)
```

Carve a sphere out of voxel terrain (a crater, a tunnel). `position` is in the terrain's local space. The terrain must be editable (planet({"editable": true})).

#### `fill`

```gdscript
func fill(terrain: Node, position: Vector3, radius: float)
```

Add a sphere of matter to voxel terrain (a mountain, a plug). See `dig`.

#### `raycast`

```gdscript
func raycast(terrain: Node, from: Vector3, direction: Vector3, max_distance: float = 4096.0) -> Dictionary
```

Cast a ray against voxel terrain (terrain local space). Returns {} on miss or {"position": Vector3, "normal": Vector3, "distance": float}.

#### `body_heightmap`

```gdscript
func body_heightmap(body: String) -> Image
```

Heightmap of a game body for `planet`: built from the body's maps (mods included) — land above the sea, brighter ground higher. Returns null if the body has no colour map.

#### `body_material`

```gdscript
func body_material(body: String, params: Dictionary = {}) -> ShaderMaterial
```

Material for a voxel planet that shows a game body: its colour map and, on top, its provinces painted by their owners — the same data the game map uses, so presets and scenarios made in the preset editor look right on the voxel world. params: provinces (0..1, how strongly owners tint the land, default 0.55), borders (bool), color (fallback colour). Call `refresh_provinces` after ownership changes.

#### `refresh_provinces`

```gdscript
func refresh_provinces(material: ShaderMaterial)
```

Re-read province ownership into a material made by `body_material` (call it from the `province_captured` hook or after you change owners).

#### `body_planet`

```gdscript
func body_planet(body: String, params: Dictionary = {}) -> Node3D
```

A voxel copy of a game body (Earth, Mars, a mod planet): its continents as real relief, its colours and its provinces. params as in `planet` plus those of `body_material`; "relief" defaults to 6% of the radius.

#### `body_planets`

```gdscript
func body_planets(body: String) -> Array
```

Voxel copies of a body made by `body_planet` that are still alive.

#### `pick_province`

```gdscript
func pick_province(body: String, what) -> int
```

Pick a province for scripts and events: an id, "random" (any land province of the body), or a country name (a random province it owns). 0 if nothing fits.

#### `crater`

```gdscript
func crater(body: String, province, radius_km: float = 300.0) -> int
```

Blow a crater into every voxel copy of a body, right over a province (see `pick_province`). radius — in km of the real planet; it is scaled to each copy. Returns the province id (0 — none). The same is available to no-code events as the effect "crater" (кратер).

#### `place`

```gdscript
func place(terrain: Node3D, transform: Transform3D)
```

Move or rotate a voxel planet made by `body_planet`: sets its transform and keeps its map material aligned. Setting `position` directly leaves the colours behind.

#### `direction`

```gdscript
func direction(position: Vector3) -> Vector3
```

Direction from the planet's centre for a point in the terrain's local space (feed it to `province_at` or to PaxGame.province_at).

#### `province_at`

```gdscript
func province_at(body: String, position: Vector3) -> int
```

Province id of a game body under a point of its voxel copy (terrain local space). 0 — water or none.

#### `province_position`

```gdscript
func province_position(body: String, id: int, radius: float) -> Vector3
```

Point on a voxel planet of the given radius above the centre of a province (terrain local space) — to place a city, a label or a camera target.

## PaxNet

Multiplayer for mods, available as `Pax.net` (main thread only): whether the game is a network game, who is in it, your own messages between the players' copies of a mod.

### PaxNet — Signals

#### `message`

```gdscript
signal message(from: int, channel: String, data: Dictionary)
```

A message from another player's copy of a mod arrived: from — player id (1 is the host), channel — the name given in send(), data — the Dictionary sent.

#### `players_changed`

```gdscript
signal players_changed
```

The list of players changed (someone joined, left or picked a country).

### PaxNet — Constants

#### `TYPE`

```gdscript
const TYPE := "mod_msg"   # тип сообщения сети, которым едут сообщения модов
```

#### `NODE`

```gdscript
const NODE := "Сеть"
```

### PaxNet — Properties

#### `sent`

```gdscript
var sent
```

#### `received`

```gdscript
var received
```

### PaxNet — Methods

#### `active`

```gdscript
func active() -> bool
```

Is this a network game right now (lobby or session)?

#### `is_host`

```gdscript
func is_host() -> bool
```

Is this copy the host? In a single-player game — false (see active()).

#### `is_guest`

```gdscript
func is_guest() -> bool
```

Is this copy a guest of someone's game?

#### `my_id`

```gdscript
func my_id() -> int
```

This player's id in the network game (the host is 1); 0 outside a network game.

#### `players`

```gdscript
func players() -> Array
```

Players in the game: [{id, name, faction, host, …}] — the lobby record of each, with its id.

#### `node`

```gdscript
func node() -> Node
```

The game's network node itself (src/net/Network.gd) or null: its `message(from, type, data)` signal carries every game message, `send(to, type, data)` / `broadcast(type, data)` send your own types, `players`, `open_lobby`, `log_in`… — the whole thing. Replace it: Pax.replace_service("network", path("MyNetwork.gd")).

#### `session`

```gdscript
func session() -> Object
```

The running network session (src/net/Multiplayer.gd: orders, time, mail, lobby panel) or null in single player. Replace it: Pax.replace_service("multiplayer", path("MyMultiplayer.gd")).

#### `send`

```gdscript
func send(channel: String, data: Dictionary = {}, to: int = 0) -> bool
```

Send data to the other players' copies of your mod. channel — your own name ("my_mod.sync"); to — a player id, or 0 for everyone else. Returns false outside a network game.

#### `on`

```gdscript
func on(channel: String, handler: Callable)
```

Subscribe to one channel: handler(from: int, data: Dictionary). The `message` signal gets everything.

#### `poll`

```gdscript
func poll()
```

## PaxPerf

Performance for mods, available as `Pax.perf` (main thread only): an FPS/CPU/GPU panel (F3), stats, distance LOD and impostors, thousands of copies in one draw call, occluders.

### PaxPerf — Constants

#### `JobsScript`

```gdscript
const JobsScript = preload("res://src/core/Jobs.gd")
```

#### `MENU`

```gdscript
const MENU := "res://addons/debug_menu/debug_menu.tscn"
```

#### `IMPOSTOR_SHADER`

```gdscript
const IMPOSTOR_SHADER := "res://addons/Imposter/imposter/materials/shaders/ImpostorShader.gdshader"
```

Shaders of godot-imposter for impostor scenes you baked with the plugin in the Godot editor.

#### `IMPOSTOR_SHADOW_SHADER`

```gdscript
const IMPOSTOR_SHADOW_SHADER := "res://addons/Imposter/imposter/materials/shaders/ImpostorShaderShadows.gdshader"
```

### PaxPerf — Methods

#### `overlay`

```gdscript
func overlay(style: String = "compact") -> Node
```

The in-game performance panel: "hidden", "compact" (FPS, frame time) or "detailed" (graphs of FPS, frame, CPU and GPU time, best/worst/average). F3 cycles it. Returns the panel node.

#### `stats`

```gdscript
func stats() -> Dictionary
```

Numbers right now: fps, frame_ms (process), physics_ms, draw_calls, objects, primitives, video_mb, memory_mb, nodes, orphans. Read them in your own panel or log.

#### `lod`

```gdscript
func lod(node: Node, far: float, near: float = 0.0, fade: float = 0.0)
```

Draw `node` (and every mesh inside) only between `near` and `far` metres from the camera, fading out over `fade` metres. The simplest big win for many objects.

#### `lod_swap`

```gdscript
func lod_swap(full: Node, cheap: Node, distance: float, fade: float = 5.0)
```

Swap a detailed model for a cheap one (a low-poly copy or a baked impostor) at `distance`: `full` is drawn closer, `cheap` farther.

#### `impostor`

```gdscript
func impostor(scene_path: String) -> Node3D
```

Load an impostor scene you baked with godot-imposter (Project → Tools in the Godot editor, saved into your mod) — a flat card that looks like the model from any side. null if it does not load.

#### `instances`

```gdscript
func instances(parent: Node3D, mesh: Mesh, transforms: Array, colors: Array = []) -> MultiMeshInstance3D
```

Thousands of copies of one `mesh` in ONE draw call (trees, houses, asteroids, units): a MultiMeshInstance3D under `parent`. `transforms` — Array of Transform3D (compute them in Pax.jobs). `colors` — optional Array of Color, one per copy.

#### `occluder`

```gdscript
func occluder(parent: Node3D, shape: String, size: Vector3) -> OccluderInstance3D
```

An occluder: what is fully behind it is not drawn (walls, mountains, a planet). `shape` — "box" (size = Vector3) or "sphere" (size.x = radius). Occlusion culling of the viewport must be on — `occlusion` turns it on.

#### `occlusion`

```gdscript
func occlusion(node: Node, on: bool = true)
```

Turn occlusion culling on (or off) for the viewport of `node` — needed for `occluder`.

## PaxGraphics

Graphics for mods, available as `Pax.graphics` (main thread only): planet atmospheres, volumetric clouds, lens flares, post effects, a day-night sky, scattering; respects the player's graphics settings.

### PaxGraphics — Constants

#### `SettingsScript`

```gdscript
const SettingsScript = preload("res://src/ui/GraphicsSettings.gd")
```

#### `JobsScript`

```gdscript
const JobsScript = preload("res://src/core/Jobs.gd")
```

#### `ADDON`

```gdscript
const ADDON := {
```

#### `SETTING`

```gdscript
const SETTING := {"atmosphere": "atmosphere", "clouds": "clouds", "lens": "lens", "post": "post", "sky": "surface", "scatter": "surface"}
```

#### `ATMOSPHERE_SHADERS`

```gdscript
const ATMOSPHERE_SHADERS := {
```

#### `POST`

```gdscript
const POST := {"vignette": "Vignette", "grain": "Grain", "glitch": "Glitch", "blur": "Blur", "chromatic": "ChromaticAberration",
```

#### `SPACE_LENS`

```gdscript
const SPACE_LENS := {"sun_color": Color(1.0, 0.86, 0.62, 0.25), "Effect_Multiplier": 1.2}
```

### PaxGraphics — Methods

#### `available`

```gdscript
func available(effect: String) -> bool
```

True when the effect is installed and the player allows it: atmosphere, clouds, lens, post, sky, scatter.

#### `hdr`

```gdscript
func hdr() -> bool
```

The window outputs HDR now (the player turned HDR on and the monitor supports it).

#### `max_brightness`

```gdscript
func max_brightness() -> float
```

Brightest colour value the screen shows right now (1.0 without HDR) — scale your emissive colours by it.

#### `atmosphere`

```gdscript
func atmosphere(planet: Node3D, radius: float, height: float, params: Dictionary = {}) -> Node3D
```

Put an atmosphere around a planet node. `radius` — the planet's radius in scene units, `height` — atmosphere thickness. `params`: "clouds" (bool), "sun" (Node3D — the light source), "color" and any shader parameter of the plugin. Returns the atmosphere node or null. Pax.graphics.atmosphere($Mars, 1.0, 0.08, {"clouds": false, "sun": $Sun, "color": Color(1, 0.6, 0.4)})

#### `lens`

```gdscript
func lens(camera: Camera3D, params: Dictionary = {}, sun: DirectionalLight3D = null) -> CompositorEffect
```

Lens flare and god rays on `camera` from `sun` (a DirectionalLight3D — the flare follows where it shines from, every frame). `params` — plugin settings (Effect_Multiplier, Decay, Density, Weight, sun_color…). Returns the effect or null.

#### `clouds`

```gdscript
func clouds(camera: Camera3D, params: Dictionary = {}) -> CompositorEffect
```

Volumetric clouds seen from `camera` (surface or low-orbit views). `params` — plugin settings (clouds_coverage, clouds_density, atmosphere_color…). Returns the effect or null.

#### `remove_effect`

```gdscript
func remove_effect(camera: Camera3D, effect: CompositorEffect)
```

Remove an effect added by `lens` or `clouds`.

#### `post`

```gdscript
func post(effect: String, params: Dictionary = {}, seconds: float = 0.0) -> bool
```

Screen post effect: vignette, grain, glitch, blur, chromatic, crt, analog, pixelate, palette, color, fisheye, shake, speed_lines, outline, ascii, waves. `params` — the plugin's fields for it (VignetteIntensity, ScreenShakePower, ColorCorrectionTint…). `seconds` > 0 turns it off by itself. Pax.graphics.post("vignette", {"VignetteIntensity": 0.6}, 3.0)

#### `clear_post`

```gdscript
func clear_post(effect: String = "")
```

Turn a post effect off ("" — all of them).

#### `sky`

```gdscript
func sky(parent: Node, params: Dictionary = {}) -> Node
```

A day-night sky with sun, moon and stars (Sky3D) for your own 3D scene; it is a WorldEnvironment, add only one per scene. `params`: Sky3D fields (current_time, minutes_per_day, latitude…).

#### `raytracing`

```gdscript
func raytracing() -> bool
```

True when the video card and driver can trace rays in hardware (Vulkan + an RT-capable card). Then `rendering_device` gives the device with raytracing_pipeline_create, blas_create / tlas_create, raytracing_list_* — write your own ray-traced effects (shadows, reflections, GI) as a CompositorEffect, like the plugins do. On D3D12 or older cards — false: keep a fallback.

#### `rendering_device`

```gdscript
func rendering_device() -> RenderingDevice
```

The game's RenderingDevice (main thread) — for compute and ray-tracing effects. null without one.

#### `space_view`

```gdscript
func space_view(camera: Camera3D, sun: DirectionalLight3D)
```

#### `world_effects`

```gdscript
func world_effects()
```

#### `terrain_library`

```gdscript
static func terrain_library() -> String
```

#### `terrain_ready`

```gdscript
func terrain_ready() -> bool
```

True when the Terrain3D classes are loaded.

#### `enable_terrain`

```gdscript
func enable_terrain() -> bool
```

Load the terrain component now (the game does it for mods with `"components": ["terrain"]`). False if it is not installed.

#### `terrain`

```gdscript
func terrain(parent: Node3D, height: Image, params: Dictionary = {}) -> Node3D
```

A big LOD terrain (Terrain3D) under `parent` from a height map: `height` — Image (FORMAT_RF or any; red = height 0..1). `params`: "height_scale" (metres for 1.0, default 400), "position" (Vector3 of the map's corner), "spacing" (metres between vertices, default 1), "color" (Image — albedo), "camera" (Camera3D the terrain follows). Needs the "terrain" component. Returns the Terrain3D node or null. var t = Pax.graphics.terrain($World, heights, {"height_scale": 800.0})

#### `scatter`

```gdscript
func scatter(parent: Node3D) -> Node3D
```

A ProtonScatter node under `parent` — scatter trees, rocks, buildings over a surface (configure its modifiers and items as in the plugin). Compute your own points in Pax.jobs.
