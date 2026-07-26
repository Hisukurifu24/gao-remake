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

var player_name := "Kirito"
var level := 1
var xp := 0

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
var _flags: Dictionary[StringName, Variant] = {}
var _input_locks := 0


func _ready() -> void:
	if world_seed == 0:
		new_world_seed()


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
	hp = max_hp
	EventBus.leveled_up.emit(level)
	EventBus.hp_changed.emit(hp, max_hp)


# --- Vitals ---
## Combat is the only thing that moves HP right now, but the HUD listens to the
## signal rather than to the combat screen, so out-of-battle damage (traps,
## poison on the map) will show up for free.

func set_hp(value: int) -> void:
	var clamped := clampi(value, 0, max_hp)
	if clamped == hp:
		return
	hp = clamped
	EventBus.hp_changed.emit(hp, max_hp)


func heal_to_full() -> void:
	set_hp(max_hp)


func is_down() -> bool:
	return hp <= 0


## Poise is derived, not stored: it is how much punishment the player can absorb
## before being staggered, and it should track their durability without being a
## third number to balance by hand.
func max_poise() -> int:
	return 30 + level * 3 + defense * 2


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


# --- Input locking ---
## Counted, not boolean: a dialogue opening during a map transition must not
## unlock input when only one of the two finishes.

func push_input_lock() -> void:
	_input_locks += 1


func pop_input_lock() -> void:
	_input_locks = maxi(0, _input_locks - 1)


func is_input_locked() -> bool:
	return _input_locks > 0
