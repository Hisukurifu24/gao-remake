extends Node
## M7's save: three slots on disk, written whenever the player asks and on the
## way into every map, read back to the very spot the player stood on.
##
## Each autoload owns the shape of its own state -- [method GameState.to_save],
## [method Inventory.to_save], [method QuestLog.to_save] and their
## [code]from_save[/code] -- and this file owns everything around it: which slot,
## the file and its version, when to autosave, and putting the player back.
##
## What is not saved is not lost by accident. Everything that stays done -- an
## opened chest, a solved puzzle, a found door, a broken wall -- is a flag, and
## flags are saved. Monsters come back on a load as they do on any visit, and a
## statue ring left half-turned starts over, as it does when you walk away from it.
## Generated floors are not saved at all: [member GameState.world_seed] is, and
## every floor grows back from it exactly as it was.
##
## The file is JSON, so it can be read, diffed and fixed by hand. Cell sets go in
## as bitmaps ([SaveCodec]).
##
## A game is played in one of three ways ([enum GameState.Mode]), chosen at new
## game. A standard game saves anywhere. A hardcore game saves the same way, but
## losing a fight deletes the save -- and a fight is marked on disk while it runs
## (a [code].fight[/code] file beside the slot), so closing the game to get out of
## a losing one is losing it. A marathon is never saved at all.

const VERSION := 2
const SLOTS := 3
const DIRECTORY := "user://saves"

## Where the slots live. The save test points it somewhere else, so running the
## suite never touches a player's saves.
var directory := DIRECTORY
## The slot this game saves into, 1 to [constant SLOTS]; 0 for a run that is never
## saved -- a debug start, a test, a tool.
var slot := 0

## Set by anything that should autosave; written as soon as nothing is in the way
## (a fade, a fight's outro, an open box).
var _autosave_pending := false


func _ready() -> void:
	SceneRouter.map_changed.connect(func(_path: String) -> void: request_autosave())
	EventBus.floor_cleared.connect(func(_floor_number: int) -> void: request_autosave())
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	set_process(false)


# --- when ------------------------------------------------------------------

## Whether the game can be written right now: a player on a map, and nothing
## half-done that a save would cut in two -- a fight, a conversation, a menu, a
## fade. The input lock covers the last three without this file knowing them.
func can_save() -> bool:
	return _player() != null and not GameState.is_input_locked() \
			and not CombatManager.is_running() and not DialogueRunner.is_running()


## Asks for an autosave into the current slot at the next moment [method can_save]
## allows. Arriving on a map and clearing a floor ask; a run with no slot ignores it.
func request_autosave() -> void:
	if slot <= 0:
		return
	_autosave_pending = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _autosave_pending:
		set_process(false)
	elif can_save():
		_autosave_pending = false
		set_process(false)
		save_game(slot, true)


## Why this game can't be saved at all, or empty if it can be: a marathon,
## or a debug start. What the pause menu greys Save out with.
func why_unsaved() -> String:
	if GameState.mode == GameState.Mode.MARATHON:
		return "Marathon: nothing is ever saved."
	if slot <= 0:
		return "This run isn't saved -- it was started from a debug floor."
	return ""


## Whether there is a save to go back to: a slot with a save in it, and not a
## hardcore game, where going back to before a mistake is the one thing ruled out.
func can_go_back() -> bool:
	return slot > 0 and exists(slot) and GameState.mode != GameState.Mode.HARDCORE


## F5 saves and F9 goes back to the last save: shortcuts for what the pause menu
## does. Deaf on the title screen, where there is no player.
func _unhandled_input(event: InputEvent) -> void:
	if _player() == null:
		return
	if event.is_action_pressed(&"quick_save"):
		if not why_unsaved().is_empty():
			if not GameState.is_input_locked():
				EventBus.message_requested.emit("", PackedStringArray([why_unsaved()]))
		elif can_save():
			save_game(slot)
	elif event.is_action_pressed(&"quick_load"):
		if can_go_back() and can_save():
			load_slot(slot)


# --- writing ---------------------------------------------------------------

## Writes the game to [param to_slot] and makes it the slot this game saves into.
## Refused -- false, nothing written -- when [method can_save] says no or the slot
## is out of range. [param auto] only tells the view which kind of save it was.
func save_game(to_slot := slot, auto := false) -> bool:
	if to_slot < 1 or to_slot > SLOTS or not can_save() \
			or GameState.mode == GameState.Mode.MARATHON:
		return false
	var data := snapshot()
	if data.is_empty() or not _write(to_slot, data):
		return false
	slot = to_slot
	EventBus.game_saved.emit(to_slot, auto)
	return true


## Everything a save holds, as it would be written. Empty with no player on a map.
func snapshot() -> Dictionary:
	var player := _player()
	if player == null:
		return {}
	var map := SceneRouter.current_map() as GameMap
	return {
		"version": VERSION,
		"meta": {
			"saved_at": int(Time.get_unix_time_from_system()),
			"name": GameState.player_name,
			"level": GameState.level,
			"floor": GameState.current_floor,
			"place": map.display_name if map != null else "",
			"mode": GameState.MODE_NAMES[GameState.mode],
			"play_time": int(GameState.play_time),
		},
		"game": GameState.to_save(),
		"quests": QuestLog.to_save(),
		"inventory": Inventory.to_save(),
		"place": {
			"map": GameState.current_map_path,
			"x": player.position.x,
			"y": player.position.y,
			"facing": [player.facing.x, player.facing.y],
		},
	}


## Writes beside the slot and renames over it, so a crash mid-write leaves the
## old save whole rather than half a new one.
func _write(to_slot: int, data: Dictionary) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("SaveGame: can't make %s (%s)" % [directory, error_string(error)])
		return false
	var path := path_for(to_slot)
	var partial := path + ".partial"
	var file := FileAccess.open(partial, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: can't write %s (%s)" % [partial, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	error = DirAccess.rename_absolute(partial, path)
	if error != OK:
		push_error("SaveGame: can't replace %s (%s)" % [path, error_string(error)])
		return false
	return true


# --- reading ---------------------------------------------------------------

## Reads [param from_slot] and puts the player back where it left them, on the
## same floor grown from the same seed. Awaitable; false, with the game untouched,
## if the slot is empty or unreadable, a hardcore game left mid-fight, or something
## is in the way.
func load_slot(from_slot: int) -> bool:
	if CombatManager.is_running() or DialogueRunner.is_running() or GameState.is_input_locked():
		return false
	# A hardcore game left mid-fight is a hardcore game lost: see bury_fallen().
	if left_mid_fight(from_slot):
		return false
	var data := read(from_slot)
	if data.is_empty():
		return false
	await restore(data)
	slot = from_slot
	EventBus.game_loaded.emit(from_slot)
	return true


## Loads [param data] into the autoloads and rebuilds the map round it. The order
## is the point: [GameState] first, since the quests are built from its seed and
## its flags are theirs; then [QuestLog]; then [Inventory], whose one
## [signal EventBus.inventory_changed] has the journal re-read its COLLECT and
## REACH objectives against the bag it now holds rather than the last game's.
func restore(data: Dictionary) -> void:
	GameState.from_save(data["game"])
	QuestLog.from_save(data["quests"])
	Inventory.from_save(data["inventory"])
	var place: Dictionary = data["place"]
	var facing: Array = place.get("facing", [0, 1]) if place.get("facing") is Array else [0, 1]
	await SceneRouter.resume(str(place.get("map", "")),
			Vector2(float(place.get("x", 0.0)), float(place.get("y", 0.0))),
			cardinal(Vector2(float(facing[0]) if facing.size() > 0 else 0.0,
					float(facing[1]) if facing.size() > 1 else 1.0)))
	# Arriving asked for an autosave of the game just read.
	_autosave_pending = false


## The parsed save in [param from_slot], or empty if there is none, it is not
## JSON, it is missing a part, or it was written by a newer game than this one.
func read(from_slot: int) -> Dictionary:
	if not exists(from_slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(from_slot)))
	if not parsed is Dictionary:
		push_warning("SaveGame: slot %d is not a save" % from_slot)
		return {}
	var data: Dictionary = parsed
	var version := SaveCodec.whole(data.get("version"), 0)
	if version < 1 or version > VERSION:
		push_warning("SaveGame: slot %d is version %d; this game reads 1 to %d"
				% [from_slot, version, VERSION])
		return {}
	data = _migrate(data, version)
	for part in ["game", "quests", "inventory", "place"]:
		if not data.get(part) is Dictionary:
			push_warning("SaveGame: slot %d has no %s" % [from_slot, part])
			return {}
	return data


## Brings an older save up to [constant VERSION], one version at a time. A change
## to the shape of a save adds a step here rather than a special case in a
## from_save.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		# Version 1 called Hardcore "death_game". Its "hardcore" (now Marathon) was
		# never saved, so no version 1 file spells it.
		for part in ["game", "meta"]:
			if data.get(part) is Dictionary and data[part].get("mode") == "death_game":
				data[part]["mode"] = "hardcore"
	return data


# --- a new game, and leaving one ---------------------------------------------

## Starts a new game in [param mode]: everything in the three autoloads as a new
## game has it -- which is what loading an empty save gives, so a new game and a
## save with nothing in it can never disagree -- on a fresh seed, in the Town of
## Beginnings. It saves into [param to_slot], whose old save the first autosave
## writes over; a marathon takes no slot. Awaitable.
func new_game(to_slot: int, mode := GameState.Mode.STANDARD) -> void:
	_autosave_pending = false
	GameState.from_save({})
	GameState.mode = mode
	QuestLog.from_save({})
	Inventory.from_save({})
	slot = 0 if mode == GameState.Mode.MARATHON else clampi(to_slot, 0, SLOTS)
	_clear_fight(slot)
	await SceneRouter.enter_floor(1)


## Leaves the game for the title screen, saving it first when [param save_first]
## and there is a slot to save into. Says [param notice] on the title. The game
## in memory stays as it was until the title starts or loads another; nothing
## autosaves meanwhile, since this game no longer has a slot. Awaitable.
func quit_to_title(notice := "", save_first := true) -> void:
	if save_first and slot > 0:
		save_game(slot)
	slot = 0
	_autosave_pending = false
	await SceneRouter.leave(func() -> void: EventBus.title_requested.emit(notice))


# --- hardcore --------------------------------------------------------------

## A real defeat has happened -- [Monster] and [BossGate] ask before deciding
## what it costs. In a hardcore game it costs the save: the slot is deleted, the
## player is told, and the game goes back to the title. Returns whether it was a
## hardcore game, in which case the caller does nothing more -- no revive, no walk
## back to the entrance.
func end_if_hardcore() -> bool:
	if GameState.mode != GameState.Mode.HARDCORE:
		return false
	var lost := slot
	if lost > 0:
		delete(lost)
	slot = 0
	_autosave_pending = false
	_game_over(lost)
	return true


func _game_over(lost: int) -> void:
	var where := "Floor %d" % GameState.current_floor
	await DialogueRunner.say("", PackedStringArray([
		"Your HP reaches zero.",
		"On Hardcore, that is the end of it.",
	]))
	var notice := "%s died on %s." % [GameState.player_name, where]
	if lost > 0:
		notice += " Slot %d is empty." % lost
	await quit_to_title(notice, false)


## Where a hardcore game marks a fight in progress: beside the slot.
func fight_path_for(of_slot: int) -> String:
	return directory.path_join("slot_%d.fight" % of_slot)


## Whether [param of_slot] was left in the middle of a fight -- the game closed,
## or crashed, before it ended. In a hardcore game that is a fight lost.
func left_mid_fight(of_slot: int) -> bool:
	return of_slot >= 1 and of_slot <= SLOTS and FileAccess.file_exists(fight_path_for(of_slot))


## Deletes every hardcore save that was left in the middle of a fight, and says
## so, a line each. The title screen calls it as it opens, before it lists them.
func bury_fallen() -> PackedStringArray:
	var notices := PackedStringArray()
	for of_slot in range(1, SLOTS + 1):
		if not left_mid_fight(of_slot):
			continue
		var meta := summary(of_slot)
		if not meta.is_empty():
			notices.append("Slot %d: %s left a fight unfinished on Floor %d. On Hardcore, that is a fight lost."
					% [of_slot, meta.get("name", "?"), SaveCodec.whole(meta.get("floor"), 1)])
		delete(of_slot)
	return notices


func _on_combat_started(_encounter_id: StringName) -> void:
	if slot <= 0 or GameState.mode != GameState.Mode.HARDCORE or not exists(slot):
		return
	var file := FileAccess.open(fight_path_for(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: can't mark the fight beside slot %d" % slot)
		return
	file.store_string("A fight is on. If this is still here when the game starts, it was lost.\n")
	file.close()


## Every fight ends here, won, fled or lost. A loss is settled straight after, by
## [method end_if_hardcore], which takes the save with it.
func _on_combat_ended(_victory: bool) -> void:
	_clear_fight(slot)


func _clear_fight(of_slot: int) -> void:
	if left_mid_fight(of_slot):
		DirAccess.remove_absolute(fight_path_for(of_slot))


# --- slots -----------------------------------------------------------------

func path_for(of_slot: int) -> String:
	return directory.path_join("slot_%d.json" % of_slot)


func exists(of_slot: int) -> bool:
	return of_slot >= 1 and of_slot <= SLOTS and FileAccess.file_exists(path_for(of_slot))


## What a slot list shows of [param of_slot] -- name, level, floor, place,
## [code]mode[/code] and [code]saved_at[/code] (unix time) -- or empty for an empty
## or unreadable slot.
func summary(of_slot: int) -> Dictionary:
	var data := read(of_slot)
	return data.get("meta", {}) if data.get("meta") is Dictionary else {}


## Empties [param of_slot], and any fight a hardcore game marked beside it.
func delete(of_slot: int) -> bool:
	_clear_fight(of_slot)
	if not exists(of_slot):
		return false
	return DirAccess.remove_absolute(path_for(of_slot)) == OK


# --- helpers ---------------------------------------------------------------

## The player on the current map, or null between maps.
func _player() -> Player:
	var map := SceneRouter.current_map()
	return map.get_node_or_null("Player") as Player if map != null else null


## [param direction] snapped to the nearest of the four ways a sprite can face;
## down for none. A hand-edited facing of (0.3, 0) must not index past the sheet.
static func cardinal(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.DOWN
	if absf(direction.x) > absf(direction.y):
		return Vector2(signf(direction.x), 0.0)
	return Vector2(0.0, signf(direction.y))
