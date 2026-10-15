extends Node
## The save: every autoload's state goes through a slot on disk and comes back
## the same, and a loaded game stands where it was saved, on the same floor.
##
##     "$GODOT" --headless --path . res://test/save_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so EventBus & co. wouldn't resolve.
##
## Writes only to [constant TEST_DIR], never to the player's slots.

const TEST_DIR := "user://test_saves"

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0
## Spies. Members, not captured locals: GDScript lambdas capture by value.
var _saved_events: Array[Array] = []
var _loaded_events: Array[int] = []


func _ready() -> void:
	SaveGame.directory = TEST_DIR
	_wipe()
	await _run()
	_wipe()
	print("")
	if _failures.is_empty():
		print("save test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("save test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	_test_codec()
	_test_every_field_is_listed()
	_test_old_and_broken_saves_in_memory()

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _until_unlocked()
	_check(SaveGame.slot == 0, "a game booted by a test saves nowhere (slot 0)")
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_loaded.connect(_on_game_loaded)

	await _test_round_trip()
	await _test_slots()
	await _test_refusals()
	await _test_resume_fallback()
	await _test_autosave()


# --- SaveCodec --------------------------------------------------------------

func _test_codec() -> void:
	var cells := {}
	for i in 400:
		cells[Vector2i((i * 37) % 53 - 20, (i * 11) % 29 - 9)] = true
	cells[Vector2i(-300, 140)] = true
	var encoded := SaveCodec.encode_cells(cells)
	var decoded := SaveCodec.decode_cells(JSON.parse_string(JSON.stringify(encoded)))
	_check(decoded.size() == cells.size() and decoded.keys().all(
			func(cell: Vector2i) -> bool: return cells.has(cell)),
			"a cell set survives the bitmap and JSON, negative cells included (%d of %d)"
			% [decoded.size(), cells.size()])
	_check(SaveCodec.encode_cells({}).is_empty() and SaveCodec.decode_cells({}).is_empty(),
			"an empty set is an empty entry")
	_check(SaveCodec.decode_cells({"x": 0, "y": 0, "w": 50, "h": 50, "bits": "AAAA"}).is_empty()
			and SaveCodec.decode_cells({"x": 0, "y": 0, "w": 1 << 20, "h": 1 << 20, "bits": ""}).is_empty()
			and SaveCodec.decode_cells("nonsense").is_empty(),
			"a short, oversized or malformed bitmap decodes to nothing rather than half a map")
	_check(SaveCodec.plain(7.0) is int and SaveCodec.plain(true) is bool
			and SaveCodec.plain(0.5) is float,
			"a whole number comes back an int; bools and fractions stay as they were")
	_check(SaveGame.cardinal(Vector2(0.3, 0.1)) == Vector2.RIGHT
			and SaveGame.cardinal(Vector2(0, -2)) == Vector2.UP
			and SaveGame.cardinal(Vector2.ZERO) == Vector2.DOWN,
			"a hand-edited facing snaps to one of the four the sheet draws")


# --- the field sweep ---------------------------------------------------------

## The load-bearing one. A variable added to an autoload later that nobody put in
## its SAVED or NOT_SAVED list is state the save silently drops -- the M7 notes
## scattered through the code ("the M7 save has to keep it") were this check, by hand.
func _test_every_field_is_listed() -> void:
	for autoload: Node in [GameState, Inventory, QuestLog]:
		var constants: Dictionary = autoload.get_script().get_script_constant_map()
		var saved: Array[StringName] = constants.get("SAVED", [] as Array[StringName])
		var not_saved: Array[StringName] = constants.get("NOT_SAVED", [] as Array[StringName])
		var unlisted: Array[String] = []
		var stale: Array[String] = []
		var names: Array[StringName] = []
		for property in autoload.get_script().get_script_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(StringName(property["name"]))
		for field in names:
			if field not in saved and field not in not_saved:
				unlisted.append(String(field))
		for field in saved + not_saved:
			if field not in names:
				stale.append(String(field))
		var label: String = autoload.name
		_check(unlisted.is_empty(),
				"every variable of %s is saved or listed as not (unlisted: %s)" % [label, unlisted])
		_check(stale.is_empty(), "and %s lists nothing that isn't there (%s)" % [label, stale])


# --- in memory: an older save, a renamed item ------------------------------

func _test_old_and_broken_saves_in_memory() -> void:
	GameState.from_save({"level": 3})
	_check(GameState.level == 3 and GameState.col() == 0 and GameState.world_seed != 0
			and GameState.dropped_col().is_empty() and GameState.attack == 8,
			"a save missing fields loads them as a new game has them, and grows a seed")

	Inventory.from_save({"bag": [
		{"id": "small_potion", "count": 4},
		{"id": "renamed_since", "count": 1},
		{"id": "bronze_sword", "count": 9, "plus": 99},
	], "worn": {"weapon": {"id": "guard_ring"}}})
	var sword := _stack_of(&"bronze_sword")
	_check(Inventory.count(&"small_potion") == 4 and not ItemLibrary.exists(&"renamed_since")
			and Inventory.stacks().size() == 3,
			"an item renamed since the save is dropped, the rest of the bag kept")
	_check(sword != null and sword.count == 1 and sword.plus == sword.item.max_plus(),
			"a count or a +N past what the item allows is cut to it")
	_check(Inventory.worn(&"weapon") == null and Inventory.count(&"guard_ring") == 1,
			"a piece saved in the wrong slot goes in the bag rather than being worn")

	QuestLog.from_save({"active": {"argo_first_errand": {"boars": 2}, "renamed_quest": {}},
			"completed": [], "order": ["renamed_quest", "argo_first_errand"],
			"tracked": "renamed_quest"})
	var progress := QuestLog.progress_for(&"argo_first_errand")
	_check(progress != null and QuestLog.active_count() == 1
			and progress.of(progress.quest.listed_objectives()[0]) == 2,
			"a quest renamed since the save is dropped, a live one keeps its count")
	_check(QuestLog.tracked() == null or QuestLog.tracked().quest.id == &"argo_first_errand",
			"and tracking a quest that is gone tracks nothing that isn't there")
	Inventory.clear()
	QuestLog.clear()
	GameState.from_save({})


# --- the round trip --------------------------------------------------------

func _test_round_trip() -> void:
	# A game worth saving: levels, floors, flags, money and a pile of it on the
	# ground, gear with a smith's work on it, quests live, ready and done, and a
	# generated floor half explored.
	GameState.new_world_seed(424242)
	while GameState.level < 6:
		GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp)
	for n in range(1, 6):
		GameState.clear_floor(n)
	GameState.set_flag(&"save_test_flag")
	GameState.set_flag(&"save_test_number", 7)
	EventBus.col_granted.emit(500)
	GameState.drop_col(&"town", Vector2(104, 120))
	EventBus.col_granted.emit(77)

	Inventory.clear()
	Inventory.add_id(&"bronze_sword")
	Inventory.add_id(&"bronze_sword")
	Inventory.add_id(&"guard_ring")
	Inventory.add_id(&"small_potion", 3)
	Inventory.equip(ItemLibrary.get_item(&"bronze_sword"))
	Inventory.enhance(Inventory.worn(&"weapon"))
	Inventory.enhance(Inventory.worn(&"weapon"))
	Inventory.equip(ItemLibrary.get_item(&"guard_ring"))
	GameState.heal_to_full()

	QuestLog.clear()
	_check(QuestLog.start(&"argo_first_errand"), "(setup) Argo's errand can be taken")
	for _i in 3:
		EventBus.enemy_defeated.emit(&"frenzy_boar")
	EventBus.dialogue_finished.emit(&"nezha")
	_check(QuestLog.turn_in(&"argo_first_errand"), "(setup) and handed in")
	Inventory.add_id(&"boar_hide")
	var local_id: StringName = LocalQuests.ids_for(2)[0]
	_check(QuestLog.start(local_id), "(setup) a settled floor's job can be taken")
	var job := QuestLog.progress_for(local_id)
	var first: QuestObjective = job.quest.listed_objectives()[0]
	if first.kind == QuestObjective.Kind.KILL:
		EventBus.enemy_defeated.emit(first.target)
	QuestLog.track(local_id)

	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := SceneRouter.current_map() as GameMap
	var player := map.get_node("Player") as Player
	var spot := _open_spot_near(map, player.position)
	player.position = spot
	player.facing = Vector2.LEFT
	await _physics(4)
	var fingerprint := _fingerprint(map)
	var map_id := map.map_id
	var explored := GameState.explored_cells(map_id).size()
	var attack := GameState.total_attack()
	var hp := GameState.hp
	var job_count := job.of(first)
	var col := GameState.col()

	var before := SaveGame.snapshot()
	_saved_events.clear()
	_check(SaveGame.save_game(1), "the game saves to slot 1")
	_check(SaveGame.exists(1) and not FileAccess.file_exists(SaveGame.path_for(1) + ".partial"),
			"the slot is on disk, with nothing left of the write beside it")
	_check(_saved_events == [[1, false]], "and says so once, as a save asked for (%s)" % [_saved_events])
	_check(SaveGame.slot == 1, "and the game now saves into that slot")
	var meta := SaveGame.summary(1)
	_check(int(meta.get("level", 0)) == GameState.level and int(meta.get("floor", 0)) == 2
			and int(meta.get("saved_at", 0)) > 0,
			"the slot's summary says who, how far and when (%s)" % meta)

	# Throw it all away: a new game in the town, on another seed -- saving nowhere,
	# or arriving in the town would autosave it over slot 1.
	SaveGame.slot = 0
	GameState.from_save({})
	GameState.new_world_seed(99)
	Inventory.clear()
	QuestLog.clear()
	await SceneRouter.enter_floor(1)
	await _until_unlocked()
	_check(GameState.level == 1 and Inventory.is_empty() and QuestLog.active_count() == 0,
			"(setup) the game in memory is a new one")

	_loaded_events.clear()
	var loaded: bool = await SaveGame.load_slot(1)
	_check(loaded, "slot 1 loads")
	await _until_unlocked()
	_check(_loaded_events == [1], "and says so once")
	map = SceneRouter.current_map() as GameMap
	player = map.get_node("Player") as Player
	await _physics(4)

	var after := SaveGame.snapshot()
	before["meta"].erase("saved_at")
	after["meta"].erase("saved_at")
	_check(JSON.stringify(after) == JSON.stringify(before),
			"a save of the loaded game is the save it was loaded from, field for field")
	_check(GameState.world_seed == 424242 and map.floor_number == 2 and _fingerprint(map) == fingerprint,
			"the same floor 2 grows back from the saved seed, wall for wall")
	_check(player.position.is_equal_approx(spot) and player.facing == Vector2.LEFT,
			"the player stands where they saved, facing the way they were (at %s, wanted %s)"
			% [player.position, spot])
	var monsters := map.get_children().filter(func(n: Node) -> bool: return n is Monster)
	_check(not monsters.is_empty() and monsters.all(
			func(m: Monster) -> bool: return float(m.get(&"_calm")) > 0.0),
			"the floor's monsters are back, and calm for a moment")
	_check(GameState.explored_cells(map_id).size() == explored,
			"the map remembers what was explored (%d cells)" % explored)
	_check(GameState.level == 6 and GameState.is_floor_cleared(5) and GameState.has_visited(2)
			and GameState.has_flag(&"save_test_flag") and GameState.get_flag(&"save_test_number") is int,
			"levels, cleared and visited floors and flags come back, a number flag still an int")
	_check(GameState.col() == col and col > 0 and GameState.dropped_col().get("amount") == 500
			and GameState.dropped_col().get("map") == &"town"
			and (GameState.dropped_col().get("position") as Vector2).is_equal_approx(Vector2(104, 120)),
			"the purse comes back, and so does the pile left where the player fell")
	var worn := Inventory.worn(&"weapon")
	var spare := _stack_of(&"bronze_sword")
	_check(worn != null and worn.plus == 2 and spare != null and spare.plus == 0,
			"the worn sword keeps its +2 and the spare its +0")
	_check(GameState.total_attack() == attack, "and the +2 reaches attack (%d)" % attack)
	_check(GameState.hp == hp and hp == GameState.total_max_hp(),
			"HP is what it was -- not cut to the last game's gear before the ring went back on")
	_check(QuestLog.is_completed(&"argo_first_errand") and QuestLog.is_active(local_id)
			and QuestLog.progress_for(local_id).of(first) == job_count
			and QuestLog.tracked() != null and QuestLog.tracked().quest.id == local_id,
			"the journal comes back: done, live with its count, and which one is tracked")
	_check(GameState.has_flag(QuestLog.flag_for(local_id, QuestLog.FLAG_STARTED))
			and GameState.has_flag(QuestLog.flag_for(&"argo_first_errand", QuestLog.FLAG_DONE)),
			"with the quest flags dialogue reads")


# --- slots -----------------------------------------------------------------

func _test_slots() -> void:
	_check(SaveGame.save_game(2) and SaveGame.save_game(3), "the other two slots take a save")
	_check(not SaveGame.save_game(0) and not SaveGame.save_game(SaveGame.SLOTS + 1),
			"there is no slot 0 or %d" % (SaveGame.SLOTS + 1))
	_check(SaveGame.delete(2) and not SaveGame.exists(2) and SaveGame.summary(2).is_empty(),
			"a slot can be emptied")
	var loaded: bool = await SaveGame.load_slot(2)
	_check(not loaded, "and an empty slot loads nothing")
	_check(SaveGame.exists(1) and SaveGame.exists(3), "without touching the others")


# --- refusals --------------------------------------------------------------

func _test_refusals() -> void:
	GameState.push_input_lock()
	_check(not SaveGame.can_save() and not SaveGame.save_game(1),
			"nothing saves through the input lock -- a box, a menu, a fade")
	var loaded: bool = await SaveGame.load_slot(1)
	_check(not loaded, "and nothing loads through it")
	GameState.pop_input_lock()

	var before := JSON.stringify(_comparable(SaveGame.snapshot()))
	_write_raw(3, "this is not a save {")
	loaded = await SaveGame.load_slot(3)
	_check(SaveGame.read(3).is_empty() and not loaded, "a slot that isn't JSON is refused")
	_write_raw(3, JSON.stringify({"version": SaveGame.VERSION + 1, "game": {}, "quests": {},
			"inventory": {}, "place": {}}))
	loaded = await SaveGame.load_slot(3)
	_check(not loaded, "and so is one from a newer game")
	_write_raw(3, JSON.stringify({"version": SaveGame.VERSION, "game": {}, "place": {}}))
	loaded = await SaveGame.load_slot(3)
	_check(not loaded, "and one with a part missing")
	_check(JSON.stringify(_comparable(SaveGame.snapshot())) == before,
			"a refused load leaves the game exactly as it was")
	_check(SaveGame.summary(3).is_empty(), "and a broken slot has no summary")


# --- a spot the map no longer has ------------------------------------------

func _test_resume_fallback() -> void:
	var map := SceneRouter.current_map() as GameMap
	var walls := map.get_node("Walls") as TileMapLayer
	var wall := Vector2.ZERO
	for cell in walls.get_used_cells():
		wall = map.to_local(walls.to_global(walls.map_to_local(cell)))
		break
	var data := SaveGame.snapshot()
	data["place"]["x"] = wall.x
	data["place"]["y"] = wall.y
	await SaveGame.restore(JSON.parse_string(JSON.stringify(data)))
	await _until_unlocked()
	map = SceneRouter.current_map() as GameMap
	var player := map.get_node("Player") as Player
	var spawns := map.get_node("SpawnPoints")
	var spawn := spawns.get_node_or_null(String(map.default_spawn)) as Node2D
	if spawn == null:
		spawn = spawns.get_child(0) as Node2D
	_check(not map.can_stand_at(wall), "(setup) the saved spot is now rock")
	_check(player.global_position.is_equal_approx(spawn.global_position),
			"a saved spot that is rock now puts the player on the map's spawn instead")


# --- autosave --------------------------------------------------------------

func _test_autosave() -> void:
	SaveGame.delete(1)
	SaveGame.slot = 1
	_saved_events.clear()
	await SceneRouter.enter_floor(1)
	await _until_unlocked()
	await _idle(3)
	var data := SaveGame.read(1)
	_check(not data.is_empty() and data["place"]["map"] == SceneRouter.FLOOR_SCHEME + "1",
			"arriving on a map autosaves into the game's slot")
	_check(_saved_events == [[1, true]], "once, as an autosave (%s)" % [_saved_events])

	_saved_events.clear()
	GameState.push_input_lock()
	GameState.clear_floor(6)
	await _idle(3)
	_check(_saved_events.is_empty(), "a floor cleared under the lock waits for it to come off")
	GameState.pop_input_lock()
	await _idle(3)
	_check(_saved_events == [[1, true]] and SaveGame.read(1)["game"]["cleared_floors"].has(6.0),
			"and then saves, with the floor cleared")

	SaveGame.slot = 0
	SaveGame.delete(1)
	await SceneRouter.enter_floor(1)
	await _until_unlocked()
	await _idle(3)
	_check(not SaveGame.exists(1), "a run with no slot never autosaves")


# --- helpers ---------------------------------------------------------------

func _on_game_saved(slot: int, auto: bool) -> void:
	_saved_events.append([slot, auto])


func _on_game_loaded(slot: int) -> void:
	_loaded_events.append(slot)


func _stack_of(id: StringName) -> ItemStack:
	for stack in Inventory.stacks():
		if stack.item.id == id:
			return stack
	return null


## A cell a few steps from [param from] the player can stand on, clear of every
## node on the map -- not where they were put, so arriving there proves the spot.
func _open_spot_near(map: GameMap, from: Vector2) -> Vector2:
	var walls := map.get_node("Walls") as TileMapLayer
	var origin := walls.local_to_map(walls.to_local(map.to_global(from)))
	for radius in range(3, 12):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var at := map.to_local(walls.to_global(walls.map_to_local(origin + Vector2i(dx, dy))))
				if map.can_stand_at(at) and _clear_of_nodes(map, at):
					return at
	return from


func _clear_of_nodes(map: GameMap, at: Vector2) -> bool:
	for child in map.get_children():
		var node := child as Node2D
		if node != null and not node is Player and not node is TileMapLayer \
				and node.position.distance_to(at) < 24.0:
			return false
	return true


func _fingerprint(map: GameMap) -> int:
	var walls := map.get_node("Walls") as TileMapLayer
	var cells := walls.get_used_cells()
	cells.sort()
	var parts := PackedStringArray()
	for cell in cells:
		parts.append("%d,%d:%s" % [cell.x, cell.y, walls.get_cell_atlas_coords(cell)])
	return hash("|".join(parts))


## A snapshot without the clock in it.
func _comparable(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true)
	if copy.has("meta"):
		copy["meta"].erase("saved_at")
	return copy


func _write_raw(slot: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.directory)
	var file := FileAccess.open(SaveGame.path_for(slot), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe() -> void:
	for slot in range(1, SaveGame.SLOTS + 1):
		if FileAccess.file_exists(SaveGame.path_for(slot)):
			DirAccess.remove_absolute(SaveGame.path_for(slot))
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


func _until_unlocked(timeout_frames := 600) -> void:
	for _i in timeout_frames:
		if not GameState.is_input_locked():
			return
		await get_tree().process_frame
	_check(false, "timed out waiting for the input lock to come off")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)


func _idle(frames := 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _physics(frames := 1) -> void:
	for _i in frames:
		await get_tree().physics_frame
