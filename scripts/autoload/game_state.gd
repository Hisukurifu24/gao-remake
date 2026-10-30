extends Node
## Persistent player and world state.
##
## Every number that must survive a scene change lives here: stats, level,
## world flags, which floor of Aincrad we're on. Combat, dialogue and quests
## read and write this; UI listens to [EventBus] rather than polling it.

## The XP curve is deliberately *linear*, not the usual exponential one.
## Monsters pay out linearly in their level ([method EnemyType.xp_at]), so an
## exponential curve means the two diverge and the climb stalls -- measured at
## around floor 17, where a floor's worth of kills stops being a fraction of a
## level. Linear against linear keeps the player near the level the floor curve
## in [FloorTuning] expects them to be, for all 100 floors.
const XP_BASE := 25
const XP_STEP := 40

## How this game is played, chosen at new game and fixed for it. A hardcore game
## ([constant HARDCORE]) saves like any other, and losing a fight deletes the save
## ([method SaveGame.end_if_fatal]); a marathon ([constant MARATHON]) is
## never saved at all, so closing the game ends it.
enum Mode { STANDARD, HARDCORE, MARATHON }
## How [enum Mode] is spelled in a save file, so a reordered enum can't turn every
## standard save into a hardcore game. Hardcore was "death_game" in version 1
## ([method SaveGame._migrate]).
const MODE_NAMES: Array[String] = ["standard", "hardcore", "marathon"]

## Who a new game is until the player says otherwise, and how long a name may be:
## it has to fit a vitals plate and a battle plate beside the numbers.
const DEFAULT_NAME := "Kirito"
const NAME_MAX := 12
## What a name is made of: letters the UI font draws, digits and a little
## punctuation. Everything else is dropped, and no bracket, brace or percent sign
## gets through to the text a name is written into.
const NAME_REFUSED := "[^A-Za-z0-9\\x{C0}-\\x{D6}\\x{D8}-\\x{F6}\\x{F8}-\\x{148}\\x{14A}-\\x{17E} _'.\\-]"

## Compiled the first time a name is cleaned; the title's box cleans one per key.
static var _refused_letters: RegEx
static var _space_runs: RegEx

var player_name := DEFAULT_NAME
## Seconds spent on a map in this run, counted by the main scene. Shown on the
## save slots and the status page; nothing plays differently for it.
var play_time := 0.0
var mode := Mode.STANDARD
var level := 1
var xp := 0

## Base stats: what the player is worth naked, before equipment. Nothing should
## read these directly -- use the [code]total_*[/code] accessors below, which are
## the single point where worn gear folds in. [member hp] is the exception: it is
## a live value, not a base one.
var max_hp := 60
var hp := 60
var attack := 8
var defense := 4
var speed := 10

## Aincrad floor the player is standing on.
var current_floor := 1
var current_map_path := ""

## Seeds every generated floor. Fixed per save, so floor 37 is always the same
## floor 37 for this player -- see FloorRegistry.seed_for().
var world_seed := 0

var _cleared_floors: Dictionary[int, bool] = {}
## Every floor the player has set foot on: where a teleport gate can take them.
## The M7 save has to keep it.
var _visited_floors: Dictionary[int, bool] = {}
var _flags: Dictionary[StringName, Variant] = {}
## What the player has seen of each map, by map id: cell -> true. Fog of war
## writes it ([GameMap]), the map screen draws it, and the M7 save has to keep it
## -- which is one more reason [member world_seed] must be in the save: these
## cells only mean anything on the same layout.
var _explored: Dictionary[StringName, Dictionary] = {}
## The part of [member _explored] the player has actually been: what the map draws
## as walked rather than only glimpsed. Same shape, same save.
var _walked: Dictionary[StringName, Dictionary] = {}
var _input_locks := 0

## Col, SAO's money. Private, and moved only by the methods under "The purse":
## spending is all-or-nothing and nothing but this file announces the balance.
var _col := 0
## The Col left where the player last fell: [code]map[/code], [code]position[/code]
## (map-local) and [code]amount[/code], or empty. One at a time -- fall again
## before picking it up and it is gone. The M7 save has to keep it.
var _dropped_col: Dictionary = {}


func _ready() -> void:
	if world_seed == 0:
		new_world_seed()
	EventBus.col_granted.connect(_on_col_granted)
	EventBus.col_charged.connect(_on_col_charged)


func new_world_seed(value := 0) -> void:
	world_seed = value if value != 0 else randi()


# --- Progression ---

func xp_to_next_level() -> int:
	return XP_BASE + XP_STEP * (level - 1)


func grant_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	EventBus.xp_gained.emit(amount)
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		_level_up()


func _level_up() -> void:
	level += 1
	max_hp += 6
	attack += 2
	defense += 1
	# Speed decides turn order, so it grows at half the rate of the rest --
	# outrunning every monster in Aincrad should take real levels.
	if level % 2 == 0:
		speed += 1
	hp = total_max_hp()
	EventBus.leveled_up.emit(level)
	EventBus.hp_changed.emit(hp, total_max_hp())


# --- stats with equipment ---
## Base stat plus whatever is worn. [Combatant.from_player] and the HUD read
## these and never the bare fields, which is how gear reaches combat without a
## single line of [CombatMath] or [CombatManager] knowing that items exist.

func total_max_hp() -> int:
	return maxi(1, max_hp + Inventory.bonus(&"max_hp"))


func total_attack() -> int:
	return maxi(1, attack + Inventory.bonus(&"attack"))


func total_defense() -> int:
	return maxi(0, defense + Inventory.bonus(&"defense"))


func total_speed() -> int:
	return maxi(1, speed + Inventory.bonus(&"speed"))


# --- Vitals ---
## Combat is the only thing that moves HP right now, but the HUD listens to the
## signal rather than to the battle view, so out-of-battle damage (traps,
## poison on the map) will show up for free.

func set_hp(value: int) -> void:
	var clamped := clampi(value, 0, total_max_hp())
	if clamped == hp:
		return
	hp = clamped
	EventBus.hp_changed.emit(hp, total_max_hp())


func heal_to_full() -> void:
	set_hp(total_max_hp())


## Re-reads the HP ceiling after something moved it -- taking off a coat with
## +20 HP has to be able to lower current HP, which [method set_hp] alone cannot
## do because it only ever moves HP towards a value it was given.
func refresh_vitals() -> void:
	hp = clampi(hp, 0, total_max_hp())
	EventBus.hp_changed.emit(hp, total_max_hp())


func is_down() -> bool:
	return hp <= 0


## Poise is derived, not stored: it is how much punishment the player can absorb
## before being staggered, and it should track their durability without being a
## third number to balance by hand.
func max_poise() -> int:
	return 30 + level * 3 + total_defense() * 2


# --- The purse ---
## Col comes in on [signal EventBus.col_granted] and nowhere else, the same way
## items come in on [signal EventBus.item_granted]: a kill, a chest, a quest, a
## sale. Out goes through [method spend_col], which a shop calls, or a dialogue's
## TAKE_COL through [signal EventBus.col_charged].

func col() -> int:
	return _col


func can_afford(amount: int) -> bool:
	return amount <= _col


## Takes [param amount] out of the purse. [b]All or nothing[/b], like
## [method Inventory.remove]: not enough refuses the whole of it and returns
## false, so a caller that checks the result can never half-pay.
func spend_col(amount: int) -> bool:
	if amount < 0 or amount > _col:
		return false
	if amount == 0:
		return true
	_col -= amount
	EventBus.col_changed.emit(_col)
	return true


func _on_col_granted(amount: int) -> void:
	if amount <= 0:
		return
	_col += amount
	EventBus.col_changed.emit(_col)


func _on_col_charged(amount: int) -> void:
	spend_col(amount)


## The player fell at [param position] on [param map_id], and everything in the
## purse falls with them. Whatever was lying from the last fall is gone -- even
## when the purse is empty this time, since losing again before going back for it
## is what loses it. Returns how much was dropped.
func drop_col(map_id: StringName, position: Vector2) -> int:
	var amount := _col
	var lost := _dropped_col
	_dropped_col = {}
	if not lost.is_empty():
		EventBus.col_dropped.emit(lost["map"], lost["position"], 0)
	if amount <= 0:
		return 0
	_col = 0
	_dropped_col = {"map": map_id, "position": position, "amount": amount}
	EventBus.col_changed.emit(_col)
	EventBus.col_dropped.emit(map_id, position, amount)
	return amount


## What is lying where the player last fell, or an empty dictionary.
func dropped_col() -> Dictionary:
	return _dropped_col


## Picks up what was dropped. Returns how much came back.
func recover_col() -> int:
	if _dropped_col.is_empty():
		return 0
	var pile := _dropped_col
	_dropped_col = {}
	EventBus.col_dropped.emit(pile["map"], pile["position"], 0)
	EventBus.col_granted.emit(pile["amount"])
	return pile["amount"]


## Empties the purse and forgets any dropped pile. For tests and a new game.
func reset_col() -> void:
	var pile := _dropped_col
	_col = 0
	_dropped_col = {}
	if not pile.is_empty():
		EventBus.col_dropped.emit(pile["map"], pile["position"], 0)
	EventBus.col_changed.emit(_col)


# --- Floor progression ---
## Clearing a floor's boss is the only thing that unlocks the next one, which is
## the whole shape of the game: 100 gates, 100 keys.

func clear_floor(floor_number: int) -> void:
	if _cleared_floors.has(floor_number):
		return
	_cleared_floors[floor_number] = true
	set_flag(StringName("floor_%d_cleared" % floor_number))
	EventBus.floor_cleared.emit(floor_number)


func is_floor_cleared(floor_number: int) -> bool:
	return _cleared_floors.has(floor_number)


## Floor 1 is always open; every other floor needs the one below it cleared.
func is_floor_unlocked(floor_number: int) -> bool:
	return floor_number <= 1 or is_floor_cleared(floor_number - 1)


## A floor's teleport gate goes live once the player has stood on the floor, and
## from any gate they can go to any floor that has. [GameMap] calls this on arrival.
func visit_floor(floor_number: int) -> void:
	if floor_number < 1 or _visited_floors.has(floor_number):
		return
	_visited_floors[floor_number] = true
	set_flag(StringName("floor_%d_visited" % floor_number))


func has_visited(floor_number: int) -> bool:
	return _visited_floors.has(floor_number)


## Every floor set foot on, lowest first.
func visited_floors() -> Array[int]:
	var floors: Array[int] = []
	floors.assign(_visited_floors.keys())
	floors.sort()
	return floors


func highest_floor_reached() -> int:
	var highest := 1
	for floor_number in _cleared_floors:
		highest = maxi(highest, floor_number + 1)
	return mini(highest, FloorTuning.TOP_FLOOR)


# --- World flags ---
## Flags are the shared vocabulary between dialogue, quests and the world:
## "chest_town_01_opened", "met_argo", "floor_1_boss_cleared".

func set_flag(flag: StringName, value: Variant = true) -> void:
	if _flags.get(flag) == value:
		return
	_flags[flag] = value
	EventBus.flag_changed.emit(flag, value)


func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return _flags.get(flag, default)


func has_flag(flag: StringName) -> bool:
	return bool(get_flag(flag, false))


# --- Exploration ---

## Marks [param cells] of [param map_id] as seen. Returns how many were new.
func explore(map_id: StringName, cells: Array[Vector2i]) -> int:
	return _mark(_explored, map_id, cells)


## Marks [param cells] of [param map_id] as walked -- been there, not just seen it.
func walk(map_id: StringName, cells: Array[Vector2i]) -> int:
	return _mark(_walked, map_id, cells)


func is_explored(map_id: StringName, cell: Vector2i) -> bool:
	return _explored.has(map_id) and _explored[map_id].has(cell)


## Every cell seen on [param map_id], as cell -> true. Read it; don't write it.
func explored_cells(map_id: StringName) -> Dictionary:
	return _explored.get(map_id, {})


## Every cell walked on [param map_id], as cell -> true. Read it; don't write it.
func walked_cells(map_id: StringName) -> Dictionary:
	return _walked.get(map_id, {})


func _mark(store: Dictionary[StringName, Dictionary], map_id: StringName,
		cells: Array[Vector2i]) -> int:
	if map_id == &"":
		return 0
	if not store.has(map_id):
		store[map_id] = {}
	var marked: Dictionary = store[map_id]
	var before := marked.size()
	for cell in cells:
		marked[cell] = true
	return marked.size() - before


# --- Input locking ---
## Counted, not boolean: a dialogue opening during a map transition must not
## unlock input when only one of the two finishes.

func push_input_lock() -> void:
	_input_locks += 1
	if _input_locks == 1:
		EventBus.input_lock_changed.emit(true)


func pop_input_lock() -> void:
	if _input_locks <= 0:
		return
	_input_locks -= 1
	if _input_locks == 0:
		EventBus.input_lock_changed.emit(false)


func is_input_locked() -> bool:
	return _input_locks > 0


# --- The save ---
## [SaveGame] owns the file; this owns what of it is the player and the world.
## Every variable in this file is in exactly one of the two lists below, and the
## save test reads the file's own variables and fails on one in neither -- so a
## field added later cannot quietly be left out of the save.

## Written by [method to_save] and read back by [method from_save].
const SAVED: Array[StringName] = [
	&"player_name", &"mode", &"play_time", &"level", &"xp", &"max_hp", &"hp", &"attack", &"defense", &"speed",
	&"current_floor", &"current_map_path", &"world_seed",
	&"_cleared_floors", &"_visited_floors", &"_flags", &"_explored", &"_walked",
	&"_col", &"_dropped_col",
]
## Deliberately not saved: the input lock belongs to whatever screen is up, and
## nothing is up in a save.
const NOT_SAVED: Array[StringName] = [&"_input_locks"]


## [param raw] with everything a name can't hold taken out, as it stands while it
## is being typed: a trailing space may be the start of a second word.
static func name_chars(raw: String) -> String:
	return _name_letters(raw).left(NAME_MAX)


## A finished name: what [method name_chars] keeps, with no space at either end or
## two in a row. Empty if there is nothing left of it, which is the caller's to
## refuse.
static func clean_name(raw: String) -> String:
	if _space_runs == null:
		_space_runs = RegEx.create_from_string(" +")
	return _space_runs.sub(_name_letters(raw).strip_edges(), " ", true).left(NAME_MAX).strip_edges()


static func _name_letters(raw: String) -> String:
	if _refused_letters == null:
		_refused_letters = RegEx.create_from_string(NAME_REFUSED)
	return _refused_letters.sub(raw, "", true)


func to_save() -> Dictionary:
	var flags := {}
	for flag in _flags:
		flags[String(flag)] = _flags[flag]
	var pile := {}
	if not _dropped_col.is_empty():
		var at: Vector2 = _dropped_col["position"]
		pile = {"map": String(_dropped_col["map"]), "x": at.x, "y": at.y,
				"amount": _dropped_col["amount"]}
	return {
		"player_name": player_name, "mode": MODE_NAMES[mode], "play_time": play_time,
		"level": level, "xp": xp,
		"max_hp": max_hp, "hp": hp, "attack": attack, "defense": defense, "speed": speed,
		"current_floor": current_floor, "current_map_path": current_map_path,
		"world_seed": world_seed,
		"cleared_floors": _cleared_floors.keys(),
		"visited_floors": _visited_floors.keys(),
		"flags": flags,
		"explored": _cells_to_save(_explored),
		"walked": _cells_to_save(_walked),
		"col": _col,
		"dropped_col": pile,
	}


## Replaces everything [method to_save] wrote with what [param data] says. A key
## that is missing takes the value a new game starts with, so a save written
## before a field existed still loads. Announces only the purse: the map is about
## to be rebuilt round the rest. [SaveGame] decides the order the
## autoloads load in, and this goes first -- the quests and the bag read it.
func from_save(data: Dictionary) -> void:
	player_name = str(data.get("player_name", DEFAULT_NAME))
	mode = mode_named(str(data.get("mode", "")))
	play_time = maxf(0.0, float(data.get("play_time", 0.0)))
	level = maxi(1, SaveCodec.whole(data.get("level"), 1))
	xp = maxi(0, SaveCodec.whole(data.get("xp"), 0))
	max_hp = SaveCodec.whole(data.get("max_hp"), 60)
	hp = SaveCodec.whole(data.get("hp"), max_hp)
	attack = SaveCodec.whole(data.get("attack"), 8)
	defense = SaveCodec.whole(data.get("defense"), 4)
	speed = SaveCodec.whole(data.get("speed"), 10)
	current_floor = clampi(SaveCodec.whole(data.get("current_floor"), 1), 1, FloorTuning.TOP_FLOOR)
	current_map_path = str(data.get("current_map_path", ""))
	world_seed = SaveCodec.whole(data.get("world_seed"), 0)
	if world_seed == 0:
		new_world_seed()

	_cleared_floors.clear()
	for floor_number: Variant in data.get("cleared_floors", []):
		_cleared_floors[SaveCodec.whole(floor_number)] = true
	_visited_floors.clear()
	for floor_number: Variant in data.get("visited_floors", []):
		_visited_floors[SaveCodec.whole(floor_number)] = true
	_flags.clear()
	var flags: Dictionary = data.get("flags", {})
	for flag: String in flags:
		_flags[StringName(flag)] = SaveCodec.plain(flags[flag])
	_explored = _cells_from_save(data.get("explored", {}))
	_walked = _cells_from_save(data.get("walked", {}))

	_col = maxi(0, SaveCodec.whole(data.get("col"), 0))
	_dropped_col = {}
	var pile: Dictionary = data.get("dropped_col", {})
	if SaveCodec.whole(pile.get("amount"), 0) > 0:
		_dropped_col = {"map": StringName(str(pile.get("map", ""))),
				"position": Vector2(float(pile.get("x", 0.0)), float(pile.get("y", 0.0))),
				"amount": SaveCodec.whole(pile["amount"])}

	# HP is not clamped here: the ceiling is the gear's, and the bag that loads
	# next is what wears it. Inventory.from_save() refreshes the vitals.
	EventBus.col_changed.emit(_col)


## The [enum Mode] a save spells [param mode_name]; standard for anything else --
## a save from before modes existed, or one edited by hand.
static func mode_named(mode_name: String) -> Mode:
	var index := MODE_NAMES.find(mode_name)
	return index as Mode if index >= 0 else Mode.STANDARD


static func _cells_to_save(store: Dictionary[StringName, Dictionary]) -> Dictionary:
	var maps := {}
	for map_id in store:
		maps[String(map_id)] = SaveCodec.encode_cells(store[map_id])
	return maps


static func _cells_from_save(data: Variant) -> Dictionary[StringName, Dictionary]:
	var store: Dictionary[StringName, Dictionary] = {}
	if not data is Dictionary:
		return store
	for map_id: String in data:
		var cells := SaveCodec.decode_cells(data[map_id])
		if not cells.is_empty():
			store[StringName(map_id)] = cells
	return store
