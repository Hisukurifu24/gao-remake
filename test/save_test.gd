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
var _title_notices: PackedStringArray = PackedStringArray()
var _countdowns: Array[int] = []
var _cleared := 0
var _fight_result: CombatResult = null
## The idle watch's clock, wound by hand: nobody waits five minutes for a test.
var _now := 1000.0
var _main: Node = null


func _ready() -> void:
	SaveGame.directory = TEST_DIR
	_wipe()
	# Whatever this machine's settings have moved, the suite presses the shipped keys.
	Settings.reset()
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
	_test_modes_in_memory()
	_test_names()

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _until_unlocked()
	_check(SaveGame.slot == 0, "a game booted by a test saves nowhere (slot 0)")
	_check(not (_main.get_node("TitleScreen") as CanvasLayer).visible,
			"and gets no title screen: it is not the game proper")
	var solid := _main.get_node("TitleScreen").find_children("*", "TileMapLayer", true, false) \
			.filter(func(layer: TileMapLayer) -> bool: return layer.collision_enabled)
	_check(solid.is_empty(),
			"the town drawn behind the title is not solid -- it shares the maps' physics space")
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.title_requested.connect(_on_title_requested)

	await _test_round_trip()
	await _test_slots()
	await _test_refusals()
	await _test_resume_fallback()
	await _test_autosave()
	await _test_game_menu()
	await _test_keys()
	await _test_new_game()
	await _test_marathon()
	await _test_idle_logout()
	await _test_game_cleared()
	await _test_hardcore()
	await _test_title_screen()


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
	# The clock runs on through the load, so it is checked for coming back, not
	# for standing still.
	var played: float = after["game"]["play_time"] - before["game"]["play_time"]
	_check(played >= 0.0 and played < 10.0,
			"the time played comes back with the save (%.2f s on)" % played)
	for data: Dictionary in [before, after]:
		data["meta"].erase("saved_at")
		data["meta"].erase("play_time")
		data["game"].erase("play_time")
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


# --- names -------------------------------------------------------------------

func _test_names() -> void:
	_check(GameState.clean_name("  Asuna   Yuuki  ") == "Asuna Yuuki",
			"a name loses its outer spaces and any doubled ones")
	_check(GameState.clean_name("[b]Kl{ei}n%s") == "bKleins",
			"and anything a line it is written into could trip over")
	_check(GameState.clean_name("Nicolò-d'Asti") == "Nicolò-d'Ast"
			and GameState.clean_name("x".repeat(40)).length() == GameState.NAME_MAX,
			"it keeps accents and stops at %d letters" % GameState.NAME_MAX)
	_check(GameState.clean_name(" \t[]{}%  ").is_empty(), "and may come to nothing, for the caller to refuse")
	_check(GameState.name_chars("Asuna ") == "Asuna ", "while typing, a space at the end stays")

	var font := load("res://ui/theme/ui_font.tres") as Font
	var missing: PackedStringArray = []
	for code in range(0x20, 0x180):
		var letter := String.chr(code)
		if GameState.name_chars(letter) == letter and not font.has_char(code):
			missing.append("U+%04X" % code)
	_check(missing.is_empty(), "the font draws everything a name can hold (%s)" % ", ".join(missing))


# --- modes -------------------------------------------------------------------

func _test_modes_in_memory() -> void:
	GameState.from_save({})
	_check(GameState.mode == GameState.Mode.STANDARD,
			"a save from before modes existed is a standard game")
	GameState.mode = GameState.Mode.HARDCORE
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_save()))
	_check(data.get("mode") == "hardcore", "a mode is saved by name, not by number")
	GameState.from_save({})
	GameState.from_save(data)
	_check(GameState.mode == GameState.Mode.HARDCORE, "and a hardcore game loads as one")
	var old := SaveGame._migrate({"game": {"mode": "death_game"}, "meta": {"mode": "death_game"}}, 1)
	_check(old["game"]["mode"] == "hardcore" and old["meta"]["mode"] == "hardcore",
			"a version 1 Death Game loads as Hardcore, slot card included")
	# Version 2 knew only classic floors: what it explored of a floor that is an
	# open field now was another map, and is forgotten; a classic floor's is kept.
	var open_floor := 0
	var classic_floor := 0
	for n in range(3, FloorTuning.TOP_FLOOR):
		var shape := FloorRegistry.shape_in(12345, n)
		if shape == FloorDefinition.Shape.OPEN_FIELD and open_floor == 0:
			open_floor = n
		elif shape == FloorDefinition.Shape.CLASSIC and not FloorRegistry.AUTHORED.has(n) and classic_floor == 0:
			classic_floor = n
	var charted := {"floor_%d" % open_floor: "x", "floor_%d" % classic_floor: "y"}
	var shaped := SaveGame._migrate({"game": {"world_seed": 12345, "explored": charted.duplicate(),
			"walked": charted.duplicate()}}, 2)
	_check(open_floor > 0 and classic_floor > 0
			and not shaped["game"]["explored"].has("floor_%d" % open_floor)
			and not shaped["game"]["walked"].has("floor_%d" % open_floor)
			and shaped["game"]["explored"].has("floor_%d" % classic_floor),
			"a version 2 save forgets what it explored of a floor that is an open field now (%d), and keeps a classic one's (%d)" % [
				open_floor, classic_floor])
	# Version 3 built the floors that pick a dungeon as classic ones: what it explored
	# of one is forgotten, and a purse dropped on it goes back in the purse, since
	# where it lay may be rock now. Every other floor's is kept.
	var dungeon_floor := 0
	for n in range(3, FloorTuning.TOP_FLOOR):
		if FloorRegistry.shape_in(12345, n) == FloorDefinition.Shape.DUNGEON:
			dungeon_floor = n
			break
	charted = {"floor_%d" % dungeon_floor: "x", "floor_%d" % classic_floor: "y"}
	var climbed := SaveGame._migrate({"game": {"world_seed": 12345, "explored": charted.duplicate(),
			"walked": charted.duplicate(), "col": 10,
			"dropped_col": {"map": "floor_%d" % dungeon_floor, "x": 40.0, "y": 40.0, "amount": 25}}}, 3)
	_check(dungeon_floor > 0
			and not climbed["game"]["explored"].has("floor_%d" % dungeon_floor)
			and not climbed["game"]["walked"].has("floor_%d" % dungeon_floor)
			and climbed["game"]["explored"].has("floor_%d" % classic_floor)
			and climbed["game"]["col"] == 35 and climbed["game"]["dropped_col"].is_empty(),
			"a version 3 save forgets a floor that is a dungeon now (%d), and its purse dropped there comes back" % dungeon_floor)
	GameState.from_save({"mode": "nonsense"})
	_check(GameState.mode == GameState.Mode.STANDARD, "a mode nobody knows loads as standard")
	GameState.from_save({})


# --- a new game ----------------------------------------------------------------

func _test_new_game() -> void:
	# A game in progress, in memory and saving nowhere.
	SaveGame.slot = 0
	while GameState.level < 3:
		GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp)
	GameState.set_flag(&"save_test_flag")
	GameState.clear_floor(1)
	Inventory.add_id(&"small_potion", 2)
	QuestLog.start(&"argo_first_errand")
	EventBus.col_granted.emit(40)
	var old_seed := GameState.world_seed
	SaveGame.delete(2)

	_saved_events.clear()
	await SaveGame.new_game(2)
	await _until_unlocked()
	await _idle(3)
	_check(GameState.level == 1 and GameState.xp == 0 and GameState.col() == 0
			and GameState.hp == GameState.total_max_hp() and not GameState.has_flag(&"save_test_flag")
			and not GameState.is_floor_cleared(1),
			"a new game starts over: level 1, no Col, full HP, no flags, nothing cleared")
	_check(Inventory.is_empty() and QuestLog.active_count() == 0 and QuestLog.completed_count() == 0,
			"with an empty bag and an empty journal")
	_check(GameState.world_seed != old_seed and GameState.mode == GameState.Mode.STANDARD,
			"on a new seed, as a standard game")
	_check(SceneRouter.current_map() != null and GameState.current_floor == 1,
			"in the Town of Beginnings")
	_check(SaveGame.slot == 2 and SaveGame.exists(2) and _saved_events == [[2, true]],
			"saving into its slot, which its first autosave fills (%s)" % [_saved_events])
	_check(SaveGame.summary(2).get("mode") == "standard" and SaveGame.can_go_back()
			and SaveGame.why_unsaved().is_empty(),
			"and the slot says how it is played; a standard game can go back to its save")

	var knocked_out := (load("res://scenes/world/monster.tscn") as PackedScene).instantiate()
	knocked_out.call(&"_knock_out", true)
	knocked_out.free()
	await _idle(2)
	_check(SaveGame.exists(2) and SceneRouter.current_map() != null and GameState.hp > 0,
			"losing a fight in a standard game costs HP, not the save")
	await _close_boxes()


# --- marathon ----------------------------------------------------------------

func _test_marathon() -> void:
	SaveGame.delete(3)
	_saved_events.clear()
	await SaveGame.new_game(3, GameState.Mode.MARATHON)
	await _until_unlocked()
	await _idle(3)
	_check(GameState.mode == GameState.Mode.MARATHON and SaveGame.slot == 0
			and not SaveGame.exists(3) and _saved_events.is_empty(),
			"a marathon takes no slot, and arriving autosaves nothing")
	_check(not SaveGame.save_game(3) and not SaveGame.exists(3),
			"it can't be saved, even into a slot asked for by name")
	_check(not SaveGame.why_unsaved().is_empty() and not SaveGame.can_go_back(),
			"and has nothing to go back to")

	var menu := _main.get_node("GameMenu")
	menu.call(&"open", 4)
	var rows: MenuList = menu.call(&"page", 4).call(&"list")
	_check(GameState.is_input_locked() and menu.call(&"tab") == 4 and rows.row_count() == 5
			and not rows.is_enabled(1) and not rows.is_enabled(2) and rows.is_enabled(4),
			"its game menu holds the lock, with Save and going back greyed out on System")
	rows.select(4)
	rows.choose()
	_check(menu.call(&"is_open") and SceneRouter.current_map() != null
			and rows.text_of(4).contains("again"),
			"and asks twice before quitting a run that is never saved")
	rows.select(0)
	_check(not rows.text_of(4).contains("again"), "moving off Quit takes the first press back")
	rows.choose()
	_check(not menu.call(&"is_open") and not GameState.is_input_locked(),
			"Resume closes it and lets go of the lock")


# --- marathon's idle watch ------------------------------------------------------

func _test_idle_logout() -> void:
	IdleWatch.clock = _clock
	IdleWatch.shatter_time = 0.0
	EventBus.idle_countdown.connect(_on_idle_countdown)
	EventBus.idle_cleared.connect(_on_idle_cleared)
	var limit := IdleWatch.limit
	var warning := IdleWatch.warning

	IdleWatch.touch()
	await _idle(2)
	_check(IdleWatch.is_watching() and is_equal_approx(IdleWatch.seconds_left(), limit),
			"a marathon on a map is watched for a player who has gone")
	GameState.mode = GameState.Mode.STANDARD
	_check(not IdleWatch.is_watching(), "a standard game is not")
	GameState.mode = GameState.Mode.MARATHON

	_now += limit - warning - 1.0
	await _idle(2)
	_check(_countdowns.is_empty(), "nothing shows until the last %d seconds" % warning)
	_now += 2.0
	await _idle(2)
	_check(_countdowns.size() == 1 and _countdowns[0] <= int(warning) and _countdowns[0] > int(warning) - 3,
			"then the countdown starts (%s)" % [_countdowns])
	_now += 20.0
	await _idle(2)
	_check(_countdowns.size() == 2 and _countdowns[1] < _countdowns[0], "and counts down (%s)" % [_countdowns])

	_cleared = 0
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.physical_keycode = KEY_F12
	key.pressed = true
	Input.parse_input_event(key)
	await _idle(2)
	_check(_cleared == 1 and is_equal_approx(IdleWatch.seconds_left(), limit),
			"any key stops it and winds the clock back up (cleared %d, %.0f s left)"
			% [_cleared, IdleWatch.seconds_left()])
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)

	# Run out with the game menu open: nowhere is safe to stand still.
	var menu := _main.get_node("GameMenu")
	menu.call(&"open", 1)
	_title_notices.clear()
	_now += limit + 1.0
	await _idle(1)
	_check(IdleWatch.is_logging_out() and SaveGame.end_if_fatal(),
			"run out, the avatar is being logged out, and a defeat now is the end of the game")
	await _until_true(func() -> bool:
		return not _title_notices.is_empty() and not SceneRouter.is_busy() and not IdleWatch.is_logging_out())
	_check(not menu.call(&"is_open") and SceneRouter.current_map() == null and SaveGame.slot == 0,
			"the menu closes under it and the run is over")
	_check(_title_notices.size() == 1 and _title_notices[0].contains("logged out")
			and _title_notices[0].contains("marathon"),
			"and the title says why (%s)" % [_title_notices])
	_check(not IdleWatch.is_watching() and is_equal_approx(IdleWatch.seconds_left(), limit),
			"the title is not watched")
	_now += limit * 3.0
	await _idle(3)
	_check(_title_notices.size() == 1, "and sitting on it ends nothing")

	# A fight is the hiding place that has to be closed: the command menu would
	# otherwise wait on a player forever.
	_main.get_node("TitleScreen").call(&"_hand_over")
	await SaveGame.new_game(3, GameState.Mode.MARATHON)
	await _until_unlocked()
	await _idle(3)
	var step_delay := CombatManager.step_delay
	CombatManager.step_delay = 0.0
	_fight_result = null
	_title_notices.clear()
	_start_fight(Bestiary.single_encounter(Bestiary.get_enemy(Bestiary.ENEMIES[0]), 1, 1))
	await _until_true(func() -> bool: return CombatManager.is_awaiting_command())
	await _test_forfeit_refused()
	_now += limit + 1.0
	await _until_true(func() -> bool: return _fight_result != null)
	_check(_fight_result != null and not _fight_result.victory and not _fight_result.fled
			and GameState.hp == 0,
			"run out in a fight, the avatar stands still and the fight is lost")
	var knocked_out := (load("res://scenes/world/monster.tscn") as PackedScene).instantiate()
	knocked_out.call(&"_knock_out", true)
	knocked_out.free()
	_check(GameState.hp == 0 and GameState.dropped_col().is_empty(),
			"and losing it neither revives the player nor spills their purse")
	await _until_true(func() -> bool:
		return not _title_notices.is_empty() and not SceneRouter.is_busy() and not IdleWatch.is_logging_out())
	_check(_title_notices.size() == 1 and _title_notices[0].contains("logged out")
			and SceneRouter.current_map() == null,
			"then the run ends the same way (%s)" % [_title_notices])

	CombatManager.step_delay = step_delay
	EventBus.idle_countdown.disconnect(_on_idle_countdown)
	EventBus.idle_cleared.disconnect(_on_idle_cleared)
	IdleWatch.clock = func() -> float: return Time.get_unix_time_from_system()
	IdleWatch.shatter_time = IdleWatch.SHATTER_TIME
	_main.get_node("TitleScreen").call(&"_hand_over")
	await SaveGame.new_game(3, GameState.Mode.STANDARD)
	await _until_unlocked()


func _test_forfeit_refused() -> void:
	_check(not CombatManager.submit(CombatAction.forfeit("nobody")),
			"the command menu can't forfeit a fight: only the idle watch can")
	await _idle(1)


func _start_fight(encounter: Encounter) -> void:
	_fight_result = await CombatManager.start(encounter)


func _clock() -> float:
	return _now


func _on_idle_countdown(seconds_left: int) -> void:
	_countdowns.append(seconds_left)


func _on_idle_cleared() -> void:
	_cleared += 1


# --- hardcore ------------------------------------------------------------------

# --- the game cleared -------------------------------------------------------------

## Floor 100's boss beaten: the ending runs itself to the title, the player is put
## down in the town on the way, and the save it writes says the game is cleared --
## Continue goes back to a castle with every floor open.
func _test_game_cleared() -> void:
	SaveGame.delete(3)
	await SaveGame.new_game(3, GameState.Mode.STANDARD)
	await _until_unlocked()
	for n in range(1, FloorTuning.TOP_FLOOR):
		GameState.clear_floor(n)
	await SceneRouter.enter_floor(FloorTuning.TOP_FLOOR)
	await _until_unlocked()
	var gates := SceneRouter.current_map().find_children("*", "BossGate", true, false)
	var gate := gates[0] as BossGate if not gates.is_empty() else null
	_check(gate != null and gate.get_prompt() == "Challenge %s" % FinalBoss.UNMET,
			"floor 100's door doesn't name its boss before you meet him (%s)" % (
				gate.get_prompt() if gate != null else "no door"))
	GameState.set_flag(FinalBoss.MET_FLAG)
	_check(gate.get_prompt() == "Challenge %s" % FloorTuning.FINAL_BOSS,
			"and is Hisukurifu's once you have (%s)" % gate.get_prompt())
	_check(SaveGame.save_game(3) and SaveGame.summary(3).get("cleared") == false,
			"a save short of the top isn't cleared")

	GameState.clear_floor(FloorTuning.TOP_FLOOR)
	_check(gate.get_prompt() == "The top of the castle", "and once he falls there is nothing to climb to")
	_title_notices.clear()
	Ending.pace = 0.01
	Ending.begin(get_tree())
	var over := func() -> bool:
		return not _title_notices.is_empty() and not SceneRouter.is_busy() \
				and get_tree().root.get_node_or_null("Ending") == null
	await _until_true(over, 3000)
	Ending.pace = 1.0
	var title := _main.get_node("TitleScreen")
	_check(_title_notices.size() == 1 and _title_notices[0].contains("cleared the game"),
			"the ending runs itself to the title, saying so (%s)" % [_title_notices])
	_check(title.call(&"is_open") and SceneRouter.current_map() == null,
			"and leaves the title up with nothing over it")
	var meta := SaveGame.summary(3)
	_check(meta.get("cleared", false) == true and SaveCodec.whole(meta.get("floor"), 0) == 1,
			"the save it wrote on the way out is cleared, and in the town (%s)" % [meta])
	var card := SaveCard.new()
	card.show_slot(3, meta)
	_check(card.text().contains("Cleared"), "and its card says so")
	card.free()

	title.call(&"_hand_over")
	var loaded: bool = await SaveGame.load_slot(3)
	await _until_unlocked()
	_check(loaded and GameState.current_floor == 1 and GameState.is_floor_cleared(FloorTuning.TOP_FLOOR)
			and SceneRouter.current_map() != null,
			"Continue goes back to the Town of Beginnings with the game cleared")


func _test_hardcore() -> void:
	SaveGame.delete(3)
	await SaveGame.new_game(3, GameState.Mode.HARDCORE)
	await _until_unlocked()
	await _idle(3)
	_check(SaveGame.slot == 3 and SaveGame.exists(3)
			and SaveGame.summary(3).get("mode") == "hardcore",
			"a hardcore game saves into its slot like any other, and the slot says what it is")
	_check(not SaveGame.can_go_back(), "but there is no going back to the save")

	EventBus.combat_started.emit(&"save_test")
	_check(SaveGame.left_mid_fight(3), "a fight in a hardcore game is marked beside its slot")
	EventBus.combat_ended.emit(true)
	_check(not SaveGame.left_mid_fight(3), "and the mark goes when the fight ends")

	# The game closed in the middle of one: the mark is still down.
	EventBus.combat_started.emit(&"save_test")
	var loaded: bool = await SaveGame.load_slot(3)
	_check(not loaded, "a hardcore game left mid-fight won't load")
	var notices := SaveGame.bury_fallen()
	_check(not SaveGame.exists(3) and not SaveGame.left_mid_fight(3) and notices.size() == 1,
			"and is buried when the slots are listed, with a word why (%s)" % [notices])

	EventBus.combat_started.emit(&"save_test")
	EventBus.combat_ended.emit(true)
	_check(not SaveGame.left_mid_fight(3), "(setup) and a fight with no save behind it marks nothing")
	_check(SaveGame.save_game(3) and SaveGame.exists(3), "(setup) the hardcore game saves again")

	_title_notices.clear()
	var knocked_out := (load("res://scenes/world/monster.tscn") as PackedScene).instantiate()
	knocked_out.call(&"_knock_out", true)
	knocked_out.free()
	_check(not SaveGame.exists(3) and SaveGame.slot == 0,
			"losing a fight in a hardcore game deletes the save on the spot")
	await _close_boxes()
	await _until_true(func() -> bool:
		return not _title_notices.is_empty() and not SceneRouter.is_busy())
	var title := _main.get_node("TitleScreen")
	_check(_title_notices.size() == 1 and _title_notices[0].contains("died"),
			"and the game goes back to the title, saying so (%s)" % [_title_notices])
	_check(SceneRouter.current_map() == null and title.call(&"is_open") and GameState.is_input_locked(),
			"with the map gone and the title holding the lock")


# --- the title screen ----------------------------------------------------------

func _test_title_screen() -> void:
	var title := _main.get_node("TitleScreen")
	var menu := _main.get_node("GameMenu")
	title.call(&"open", "")
	var rows: MenuList = title.call(&"list")
	var cards: CardList = title.call(&"cards")
	_check(title.call(&"page") == 0 and rows.row_count() == 6 and rows.is_enabled(0) and rows.is_enabled(2),
			"the title is a main menu -- Continue, New game, Load game, Settings, Credits, Quit")
	menu.call(&"open")
	_check(not menu.call(&"is_open"), "the game menu doesn't open over the title")

	rows.select(2)
	rows.choose()
	_check(title.call(&"page") == 1 and cards.card_count() == SaveGame.SLOTS and cards.index == 1
			and cards.card(1).call(&"text").contains("Kirito") and cards.card(0).call(&"text").contains("Empty"),
			"Load game lists the three slots, the cursor on the latest save")
	title.call(&"delete_selected")
	_check(SaveGame.exists(2) and cards.card(1).call(&"text").contains("again"), "delete asks twice")
	cards.select(0)
	_check(not cards.card(1).call(&"text").contains("again"), "and moving off it takes the first press back")
	cards.select(1)
	_loaded_events.clear()
	cards.choose()
	await _until_unlocked()
	await _idle(3)
	_check(_loaded_events == [2] and SaveGame.slot == 2 and SceneRouter.current_map() != null
			and not title.call(&"is_open") and not (title as CanvasLayer).visible,
			"choosing a save loads it and the title gets out of the way")

	menu.call(&"open", 4)
	var system: MenuList = menu.call(&"page", 4).call(&"list")
	_check(system.is_enabled(1) and system.is_enabled(2), "a standard game's System page can save and go back")
	_saved_events.clear()
	system.select(4)
	system.choose()
	await _until_true(func() -> bool:
		return title.call(&"is_open") and not SceneRouter.is_busy())
	_check(_saved_events == [[2, false]] and SceneRouter.current_map() == null and SaveGame.slot == 0,
			"Save and quit saves into the slot and leaves for the title (%s)" % [_saved_events])

	rows.select(1)
	rows.choose()
	_check(title.call(&"page") == 2 and cards.card_count() == 3, "New game asks how to play first")
	cards.select(1)
	cards.choose()
	_check(title.call(&"page") == 3 and cards.index == 0,
			"and then where to save, starting on the first empty slot")
	cards.select(1)
	cards.choose()
	_check(title.call(&"page") == 3 and SceneRouter.current_map() == null
			and cards.card(1).call(&"text").contains("again"),
			"a slot with a save in it asks before it is overwritten")
	cards.select(2)
	cards.choose()
	var field: LineEdit = title.call(&"name_field")
	_check(title.call(&"page") == 6 and SceneRouter.current_map() == null and field.is_visible_in_tree()
			and field.has_focus() and field.text == GameState.DEFAULT_NAME,
			"and last who you are, with a name ready in the box")
	await _tap_key(KEY_E, true)
	_check(title.call(&"page") == 6 and field.text == GameState.DEFAULT_NAME,
			"the key that chose the slot, held down, types nothing into the box")
	await _tap_key(KEY_ENTER, true)
	_check(title.call(&"page") == 6 and SceneRouter.current_map() == null, "nor logs in with what is there")
	await _tap_key(KEY_ESCAPE)
	_check(title.call(&"page") == 3 and cards.index == 2, "Esc goes back a page, not only out of the box")
	cards.choose()
	field.clear()
	await _tap_key(KEY_ENTER)
	_check(title.call(&"page") == 6 and SceneRouter.current_map() == null
			and String(title.get("_detail").text).contains("no name"),
			"an empty box logs nobody in, and says why")
	await _type("Eve[ E}%")
	_check(field.text == "Eve E", "letters go into the box, E among them, and nothing a name can't hold (%s)" % field.text)
	await _tap_key(KEY_ENTER)
	await _until_unlocked()
	await _idle(3)
	_check(GameState.mode == GameState.Mode.HARDCORE and SaveGame.slot == 3 and SaveGame.exists(3)
			and not title.call(&"is_open"),
			"Hardcore, then an empty slot, starts one there")
	_check(GameState.player_name == "Eve E" and SaveGame.summary(3).get("name") == "Eve E",
			"as whoever the box said, in the game and on the save (%s)" % GameState.player_name)
	_check(not field.has_focus(), "and the box lets go of the keyboard")
	menu.call(&"open", 4)
	system = menu.call(&"page", 4).call(&"list")
	_check(system.is_enabled(1) and not system.is_enabled(2),
			"whose System page saves but can't go back")
	menu.call(&"close")

	await SaveGame.quit_to_title()
	await _until_true(func() -> bool: return not SceneRouter.is_busy())
	rows.select(1)
	rows.choose()
	cards.select(2)
	cards.choose()
	_check(title.call(&"page") == 6, "Marathon goes straight to the name: it has no slot to ask about")
	title.call(&"_back")
	_check(title.call(&"page") == 2 and cards.index == 2, "and back from there is the ways to play")
	cards.choose()
	title.call(&"confirm_name")
	await _until_unlocked()
	await _idle(3)
	_check(GameState.mode == GameState.Mode.MARATHON and SaveGame.slot == 0
			and SceneRouter.current_map() != null and not title.call(&"is_open")
			and GameState.player_name == GameState.DEFAULT_NAME,
			"and leaving the box as it stands starts as that")
	await SaveGame.quit_to_title()
	await _until_true(func() -> bool: return title.call(&"is_open") and not SceneRouter.is_busy())

	rows.select(2)
	rows.choose()
	cards.select(2)
	title.call(&"delete_selected")
	title.call(&"delete_selected")
	_check(not SaveGame.exists(3) and cards.card(2).call(&"text").contains("Empty"),
			"and pressing Delete twice empties a slot")
	title.call(&"_back")
	_check(title.call(&"page") == 0 and rows.index == 2, "Esc goes back to the main menu, on the row it left")

	Settings.path = TEST_DIR.path_join("settings.cfg")
	Settings.reset()
	rows.select(3)
	rows.choose()
	var settings := title.call(&"list") as MenuList
	_check(title.call(&"page") == 4 and settings is SettingsList and settings.row_count() == 8,
			"Settings lists the window, the text, the camera, the two volumes, the keys, and Back")
	settings.select(2)
	settings.step(1)
	var file := ConfigFile.new()
	_check(Settings.text_speed == 2 and Settings.chars_per_second() > 45.0
			and file.load(Settings.path) == OK and int(file.get_value("settings", "text_speed")) == 2,
			"stepping a value changes it and writes it at once")
	settings.select(3)
	settings.choose()
	_check(not Settings.screen_shake and settings.text_of(3).contains("Off"),
			"the confirm key steps it too, and the row says so")
	Settings.reset()
	_check(Settings.load_settings() and Settings.text_speed == 2 and not Settings.screen_shake,
			"and the file reads back as written")
	Settings.reset()

	var keys_row := SettingsList.ROWS.find(&"keys")
	settings.select(keys_row)
	settings.choose()
	await _idle(2)
	var window := settings.get_parent().get_parent() as Control
	_check(settings.is_on_keys() and window.get_global_rect().end.y <= 336.0,
			"the keys fit the title's window, above its key line (to %d)" % window.get_global_rect().end.y)
	Settings.bind(&"interact", KEY_F)
	title.call(&"_back")
	_check(title.call(&"page") == 4 and not settings.is_on_keys() and settings.index == keys_row,
			"Esc steps out of the keys first, onto their row")
	title.call(&"_back")
	_check(String(title.get("_hints").call(&"text")).contains("[F] choose"),
			"and the title's key line names the key as it is now")
	Settings.reset()
	rows.select(3)
	rows.choose()

	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.PATH
	title.call(&"_back")
	title.call(&"_hand_over")
	await _idle(2)
	_check(not GameState.is_input_locked(), "(cleanup) the title lets go of the lock")


## The game menu over a standard game: the keys that open it on each tab, Tab
## through the tabs, the bag's filter and comparison, and the settings inside System.
func _test_game_menu() -> void:
	var menu := _main.get_node("GameMenu")
	await _tap(&"inventory")
	_check(menu.call(&"is_open") and menu.call(&"tab") == 1 and GameState.is_input_locked(),
			"I opens the game menu on Items, holding the lock")
	await _tap_key(KEY_TAB)
	_check(not menu.call(&"is_open") and not GameState.is_input_locked(), "Tab closes Items, as I does")
	await _tap_key(KEY_TAB)
	_check(menu.call(&"is_open") and menu.call(&"tab") == 1, "and opens it from the map")
	menu.call(&"show_tab", 3)
	await _tap_key(KEY_TAB)
	_check(menu.call(&"is_open") and menu.call(&"tab") == 1,
			"and from any other tab goes to Items, not on to the next tab")
	var bag_before := Inventory.stacks().size()
	await _tap_key(KEY_E)
	_check(menu.call(&"tab") == 2 and Inventory.stacks().size() == bag_before,
			"E moves on a tab too, and never reaches the page as a confirm")
	await _tap_key(KEY_Q)
	await _tap_key(KEY_Q)
	_check(menu.call(&"tab") == 0, "and Q goes back, one tab a press")
	await _tap_key(KEY_E)
	_check(String(menu.call(&"hint_text")).contains("[Q] [E] tab"), "and the key line says so")
	await _tap(&"journal")
	_check(menu.call(&"tab") == 2, "J goes to Quests")
	await _tap(&"journal")
	_check(not menu.call(&"is_open") and not GameState.is_input_locked(),
			"and J again closes the menu, letting go of the lock")
	await _tap(&"pause")
	_check(menu.call(&"is_open") and menu.call(&"tab") == 0, "Esc opens it on Status")
	await _tap(&"pause")
	_check(not menu.call(&"is_open"), "and Esc closes it")

	var start_time := GameState.play_time
	await _idle(5)
	_check(GameState.play_time > start_time, "time on a map counts as time played")

	Inventory.add_id(&"leather_coat", 1)
	Inventory.add_id(&"small_potion", 1)
	menu.call(&"open", 1)
	var items: Node = menu.call(&"page", 1)
	items.call(&"set_category", 2)
	var shown: Array[ItemStack] = items.call(&"shown_stacks")
	_check(not shown.is_empty() and shown.all(func(s: ItemStack) -> bool: return s.item.is_equipment()),
			"the Equipment tab shows only equipment (%d stacks)" % shown.size())
	items.call(&"select_cell", shown.find(_stack_of(&"leather_coat")))
	var trying: ItemStack = items.call(&"selected_stack")
	var change := Inventory.change_if_worn(trying, &"defense")
	_check(trying != null and change != 0 and items.call(&"stat_delta", 1) == "%+d" % change,
			"and the stats under the player show what wearing the piece would change (DEF %+d)" % change)
	items.call(&"set_category", 1)
	shown = items.call(&"shown_stacks")
	_check(shown.all(func(s: ItemStack) -> bool: return s.item.is_consumable()),
			"the Consumables tab shows only consumables")
	Inventory.remove(&"leather_coat")
	Inventory.remove(&"small_potion")

	# Every item's details, at its longest -- the most a smith can add to it.
	items.call(&"set_category", 0)
	var overflowing: PackedStringArray = []
	for item in ItemLibrary.all():
		if Inventory.add(item, 1) != 1:
			overflowing.append("%s (no room to try it)" % item.id)
			continue
		# The copy just added: equipment goes to the back, anything else merges.
		var stack: ItemStack = null
		for each in Inventory.stacks():
			if each.item == item:
				stack = each
		var was := stack.plus
		stack.plus = item.max_plus()
		items.call(&"select_cell", (items.call(&"shown_stacks") as Array).find(stack))
		await _idle(1)
		if not items.call(&"details_fit"):
			overflowing.append(String(item.id))
		stack.plus = was
		Inventory.remove_from(stack, 1)
	_check(overflowing.is_empty(), "every item's details fit the Items page (%s)" % ", ".join(overflowing))

	menu.call(&"show_tab", 2)
	await _idle(1)
	var journal: Node = menu.call(&"page", 2)
	var cut: PackedStringArray = []
	for quest in QuestLibrary.all():
		journal.call(&"show_quest", quest.id)
		await _idle(1)
		if not journal.call(&"fits"):
			cut.append(String(quest.id))
	_check(cut.is_empty(), "every quest's page fits the journal (%s)" % ", ".join(cut))

	menu.call(&"show_tab", 4)
	var system: Node = menu.call(&"page", 4)
	var rows: MenuList = system.call(&"list")
	rows.select(3)
	rows.choose()
	_check(system.call(&"list") is SettingsList, "System's Settings opens the settings in place")
	await _tap(&"pause")
	_check(menu.call(&"is_open") and not (system.call(&"list") is SettingsList),
			"and Esc steps back out of them before it closes anything")
	await _tap(&"pause")
	_check(not menu.call(&"is_open") and not GameState.is_input_locked(), "(cleanup) the menu is closed")


## Moving keys: the rule, the file, the input map, the page in System and what
## names a key on screen.
func _test_keys() -> void:
	var menu := _main.get_node("GameMenu")
	Settings.path = TEST_DIR.path_join("settings.cfg")
	Settings.reset()

	var loose: PackedStringArray = []
	for binding: Array in Settings.BINDINGS:
		var key := Settings.key_of(binding[0])
		if key == KEY_NONE or not Settings.refusal(key).is_empty():
			loose.append("%s can't have the key it ships with" % binding[0])
		for event in InputMap.action_get_events(binding[0]).slice(1):
			if not Settings.FIXED_KEYS.has((event as InputEventKey).physical_keycode):
				loose.append("%s has a second key that isn't fixed" % binding[0])
	_check(loose.is_empty(), "every action's first key can move, and only that one can (%s)" % ", ".join(loose))

	_check(Settings.bind(&"journal", KEY_K) == &"" and _is_on(KEY_K, &"journal") and not _is_on(KEY_J, &"journal"),
			"moving an action takes it off the old key and puts it on the new one")
	await _tap_key(KEY_K)
	_check(menu.call(&"is_open") and menu.call(&"tab") == 2, "so K opens Quests now")
	await _tap_key(KEY_K)
	_check(not menu.call(&"is_open"), "and closes it")
	await _tap_key(KEY_J)
	_check(not menu.call(&"is_open"), "and J does nothing")

	_check(Settings.bind(&"map", KEY_K) == &"journal" and Settings.key_of(&"map") == KEY_K
			and Settings.key_of(&"journal") == KEY_M,
			"a key another action has swaps the two, so neither is left with nothing")
	_check(Settings.bind(&"map", KEY_ESCAPE) == &"" and Settings.key_of(&"map") == KEY_K
			and not Settings.refusal(KEY_TAB).is_empty(), "Esc and the other fixed keys can't be given away")
	_check(not Settings.refusal(KEY_INSERT).is_empty() and Settings.refusal(KEY_F12).is_empty()
			and Settings.refusal(KEY_SEMICOLON).is_empty(),
			"and nor can a key no cap could show, though a character on a blank cap will do")

	Settings.bind(&"move_up", KEY_Y)
	Settings.bind(&"interact", KEY_F)
	_check(_is_on(KEY_UP, &"move_up") and _is_on(KEY_SPACE, &"interact") and _is_on(KEY_ENTER, &"interact")
			and _is_on(KEY_TAB, &"inventory"), "an action's other keys stay on it")
	var prompt := _main.get_node("Hud/InteractPrompt/Row/Key") as TextureRect
	_check(prompt.texture == KeyHints.texture_for("F"), "the prompt's keycap follows the key")
	var gate := _main.get_node("GateMenu")
	gate.call(&"open", 1)
	_check(String(gate.get_node("Hints").text).begins_with("[F] travel"), "and the gate's key line names it")
	gate.call(&"close")
	var shop := _main.get_node("ShopScreen")
	shop.call(&"open", ShopLibrary.all()[0])
	_check(String(shop.get_node("Hints").text).begins_with("[F] trade"), "and the shop's")
	shop.call(&"close")

	var file := ConfigFile.new()
	_check(file.load(Settings.path) == OK and file.get_value("keys", "map") == KEY_K
			and not file.has_section_key("keys", "inventory"), "only moved keys are written")
	Settings.reset()
	_check(Settings.keys_are_default() and _is_on(KEY_E, &"interact") and not _is_on(KEY_F, &"interact"),
			"(setup) a reset puts them all back")
	_check(Settings.load_settings() and Settings.key_of(&"map") == KEY_K and _is_on(KEY_F, &"interact"),
			"and the file reads back into the input map")
	file.set_value("keys", "map", KEY_F)
	file.save(Settings.path)
	_check(Settings.load_settings() and Settings.keys_are_default(),
			"a file giving one key to two actions is ignored whole")
	file.set_value("keys", "map", KEY_ESCAPE)
	file.set_value("keys", "interact", KEY_G)
	file.save(Settings.path)
	_check(Settings.load_settings() and Settings.keys_are_default(), "and so is one taking a fixed key")

	await _test_keys_on_a_layout(prompt)
	await _test_keys_in_the_bag()

	# Q and E are the menu's tab keys, so a key can only be picked up ahead of them.
	menu.call(&"open", 4)
	var system: Node = menu.call(&"page", 4)
	var rows: MenuList = system.call(&"list")
	rows.select(3)
	rows.choose()
	var list: SettingsList = system.call(&"list")
	list.select(SettingsList.ROWS.find(&"keys"))
	list.choose()
	await _idle(2)
	_check(list.is_on_keys() and list.row_count() == Settings.BINDINGS.size() + 2
			and list.text_of(4) == "Interact [E]", "Keys lists every action with its key, and Reset and Back")
	var column := list.get_parent() as Control
	_check(column.get_combined_minimum_size().y <= system.size.y,
			"and fits the System page (%d of %d)" % [column.get_combined_minimum_size().y, system.size.y])
	_check(not list.is_enabled(Settings.BINDINGS.size()), "with nothing to reset yet")
	list.select(4)
	list.choose()
	_check(list.is_waiting() and list.text_of(4).contains("press a key")
			and menu.call(&"hint_text") == "[Esc] leave it", "choosing a row waits for a key, and says only how out")
	var line := list.get_child(4).get_node("Plate/Line")
	_check(line.get_child(1).name == &"Value" and line.get_child(2).name == &"Cap",
			"and what a row grows later still takes its place along the row")
	await _tap_key(KEY_ESCAPE)
	_check(not list.is_waiting() and list.is_on_keys() and menu.call(&"is_open") and Settings.keys_are_default(),
			"Esc leaves the key as it was, and nothing else")
	list.choose()
	await _tap_key(KEY_TAB)
	_check(list.is_waiting() and menu.call(&"tab") == 4 and list.describe(4).contains("keep"),
			"a fixed key is refused, still waiting, and doesn't change tab")
	await _tap_key(KEY_Q)
	_check(not list.is_waiting() and Settings.key_of(&"interact") == KEY_Q and menu.call(&"tab") == 4
			and list.text_of(4) == "Interact [Q]", "Q is taken for the key, not for the tab")
	list.select(5)
	list.choose()
	await _tap_key(KEY_Q)
	_check(Settings.key_of(&"inventory") == KEY_Q and Settings.key_of(&"interact") == KEY_I
			and list.describe(5).contains("Swapped with Interact"), "a swap says what it swapped with")
	list.select(6)
	_check(not (system.get(&"_detail") as Label).text.contains("Swapped"),
			"and the line under the list lets go of that as the cursor moves")
	list.select(Settings.BINDINGS.size())
	list.choose()
	_check(Settings.keys_are_default() and list.text_of(4) == "Interact [E]", "Reset keys puts them all back")
	list.select(4)
	list.choose()
	list.select(Settings.BINDINGS.size())
	list.choose()
	_check(not list.is_waiting() and not list.text_of(4).contains("press a key"),
			"the greyed Reset row, clicked, leaves a waiting row and says so")
	list.select(4)
	list.choose()
	menu.call(&"close")
	_check(not list.is_waiting() and not list.is_on_keys(), "closing the menu leaves the keys")
	await _tap_key(KEY_P)
	_check(Settings.keys_are_default(), "a menu closed under a waiting row takes no key")

	menu.call(&"open", 4)
	rows.select(3)
	rows.choose()
	list.select(SettingsList.ROWS.find(&"keys"))
	list.choose()
	list.select(Settings.BINDINGS.size() + 1)
	list.choose()
	_check(not list.is_on_keys() and system.call(&"list") == list, "Back goes back to the settings")
	list.choose()
	await _tap(&"pause")
	_check(not list.is_on_keys() and system.call(&"list") == list and menu.call(&"is_open"),
			"as Esc does, one step at a time")
	await _tap(&"pause")
	await _tap(&"pause")
	_check(not menu.call(&"is_open"), "(cleanup) the menu is closed")

	Settings.bind(&"map", KEY_E)
	await _tap_key(KEY_E)
	_check(menu.call(&"tab") == 3 and menu.call(&"is_open"), "a tab may be given E")
	menu.call(&"show_tab", 0)
	await _tap_key(KEY_E)
	_check(menu.call(&"tab") == 3, "and in the menu E goes to that tab rather than the next one")
	await _tap_key(KEY_E)
	_check(not menu.call(&"is_open"), "and closes it as its own key should")

	Settings.reset()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.PATH


## A layout can put anything on a key, and what it does must not reach the keys
## themselves. Headless there is no layout, so one is lent: Dvorak's punctuation, an
## accent, and a key that types nothing a cap can show.
func _test_keys_on_a_layout(prompt: TextureRect) -> void:
	var board: Callable = Settings.layout
	Settings.layout = func(key: Key) -> int:
		return {KEY_E: KEY_PERIOD, KEY_W: KEY_COMMA, KEY_J: 0xC8, KEY_I: KEY_CAPSLOCK}.get(key, key)
	Settings.changed.emit()
	_check(Settings.key_name(&"interact") == "Period" and Settings.key_name(&"journal") == "È",
			"a key is called what the layout calls it")
	_check(Settings.key_name(&"inventory") == "I", "or its own name, where no cap can show that")
	var blank: PackedStringArray = []
	for binding: Array in Settings.BINDINGS:
		if KeyHints.texture_for(Settings.key_name(binding[0])) == null or not Settings.refusal(Settings.key_of(binding[0])).is_empty():
			blank.append(binding[0])
	_check(blank.is_empty(), "so every key the game ships has a cap on it, and is allowed (%s)" % ", ".join(blank))
	var cap := KeyHints.texture_for("Period")
	_check(cap is GlyphCap and cap.get_size() == KeyHints.texture_for("E").get_size()
			and cap == KeyHints.texture_for("Period"), "the pack's blank, a pack cap's size, the one texture")
	_check(prompt.texture == cap, "the prompt draws it rather than nothing")
	Settings.bind(&"journal", KEY_K)
	_check(Settings.load_settings() and Settings.key_of(&"journal") == KEY_K,
			"and a key moved on that layout is still there on the next boot")
	Settings.reset()
	Settings.layout = board
	Settings.changed.emit()


## In the bag, X and R do what the key line says, whatever else is on them -- and
## where a tab's own key beats them, the key line stops saying it.
func _test_keys_in_the_bag() -> void:
	var menu := _main.get_node("GameMenu")
	var title := _main.get_node("TitleScreen")
	_check(title.call(&"_delete_keys") == ["Del", "X"], "the title deletes a slot on Del or X")
	Settings.bind(&"interact", KEY_X)
	_check(title.call(&"_delete_keys") == ["Del"], "and says only Del once X is interact, which it reads first")
	var hp := GameState.hp
	GameState.hp = 1
	Inventory.clear()
	Inventory.add_id(&"small_potion", 1)
	menu.call(&"open", 1)
	(menu.call(&"page", 1) as Node).call(&"set_category", 0)
	await _idle(2)
	await _tap_key(KEY_X)
	_check(Inventory.count(&"small_potion") == 0 and GameState.hp == 1,
			"with interact on X, X in the bag drops the potion rather than drinking it")
	Settings.reset()
	Inventory.add_id(&"small_potion", 1)
	Settings.bind(&"journal", KEY_R)
	Settings.bind(&"inventory", KEY_X)
	Inventory.add_id(&"small_potion", 1)
	await _idle(2)
	var said: String = menu.call(&"hint_text")
	_check(not said.contains("[X]") and not said.contains("[R]"), "a tab's key on X or R takes it off the key line (%s)" % said)
	await _tap_key(KEY_X)
	_check(not menu.call(&"is_open") and Inventory.count(&"small_potion") == 2,
			"and X closes the bag as its own key, and throws nothing away")
	Settings.reset()
	Inventory.clear()
	GameState.hp = hp


## Whether pressing the physical [param key] now counts as [param action].
func _is_on(key: Key, action: StringName) -> bool:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.pressed = true
	return press.is_action_pressed(action)


## Types [param text] a key at a time, into whatever has focus.
func _type(text: String) -> void:
	for i in text.length():
		var press := InputEventKey.new()
		press.physical_keycode = text.unicode_at(i) as Key
		press.keycode = press.physical_keycode
		press.unicode = text.unicode_at(i)
		press.pressed = true
		Input.parse_input_event(press)
		await _idle(1)
		var release := press.duplicate() as InputEventKey
		release.pressed = false
		Input.parse_input_event(release)
		await _idle(1)


func _tap_key(key: Key, echo := false) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.echo = echo
	press.pressed = true
	Input.parse_input_event(press)
	await _idle(2)
	if echo:
		return
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _idle(2)


func _tap(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _idle(2)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _idle(2)


# --- helpers ---------------------------------------------------------------

func _on_title_requested(notice: String) -> void:
	_title_notices.append(notice)


## Presses on through whatever the box is saying until it closes.
func _close_boxes() -> void:
	for _i in 600:
		if not DialogueRunner.is_running():
			return
		DialogueRunner.advance()
		await get_tree().process_frame
	_check(false, "timed out waiting for the box to close")


func _until_true(predicate: Callable, timeout_frames := 600) -> void:
	for _i in timeout_frames:
		if predicate.call():
			return
		await get_tree().process_frame
	_check(false, "timed out waiting for %s" % predicate)


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
