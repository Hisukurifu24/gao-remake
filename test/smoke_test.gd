extends Node
## Boots the real game headless and checks the M1 loop end to end.
##
##     "$GODOT" --headless --path . res://test/smoke_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so EventBus & co. wouldn't resolve.
##
## A stopgap until GUT is installed (see test/README.md) -- it exercises
## spawning, collision, interaction and map transitions in one pass, and exits
## non-zero on failure so CI can use it.

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

# Signal spies. Members, not captured locals: GDScript lambdas capture by value,
# so a lambda writing to a local would silently drop the result.
var _last_target: Node = null
var _last_speaker := ""
## Every line shown while [method _spy_text] listens.
var _line_spy: PackedStringArray = PackedStringArray()
## How many figures a [BossGate] stood on the map for the last fight staged, or
## -1 for none. A member, not a captured local: lambdas capture by value.
var _staged_figures := -1
## Duellists who wouldn't yield, while [method _count_betrayal] listens.
var _betrayals := 0
## The last field announced, and the camera the screen was looking through when
## that fight asked for a command. Members for the same reason.
var _field: BattleField = null
var _fight_camera: Camera2D = null


func _ready() -> void:
	await _run()
	print("")
	if _failures.is_empty():
		print("smoke test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("smoke test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var world_root: Node2D = main.get_node("WorldRoot")

	await _idle()
	_check(EventBus != null and GameState != null and SceneRouter != null, "autoloads are registered")
	EventBus.battle_staged.connect(_on_battle_staged)
	CombatManager.command_requested.connect(_on_command_requested)

	# --- boot into the town ---
	await _until_unlocked()
	var town := world_root.get_child(0)
	_check(town.get(&"map_id") == &"town", "boots into the town map")

	var player: Node2D = town.get_node("Player")
	_check(player.global_position.is_equal_approx(Vector2(392, 296)),
			"player starts on the default spawn (got %s)" % player.global_position)

	var camera: Camera2D = player.get_node("Camera2D")
	_check(camera.limit_right == 800 and camera.limit_bottom == 576,
			"camera limits match the painted area (got %d x %d)" % [camera.limit_right, camera.limit_bottom])

	# --- movement and wall collision ---
	var start_y := player.global_position.y
	await _hold(&"move_up", 20)
	_check(player.global_position.y < start_y - 10.0, "walking north moves the player")

	player.global_position = Vector2(392, 40)  # just under the tree border
	await _hold(&"move_up", 60)
	_check(player.global_position.y > 16.0,
			"tree border blocks movement (stopped at y=%.1f)" % player.global_position.y)

	# --- interaction ---
	var argo: Node2D = town.get_node("Argo")
	# Park the player clear of everything first: the signal fires on *change*,
	# so it must not already be targeting Argo when we start listening.
	player.global_position = Vector2(392, 296)
	player.set(&"facing", Vector2.UP)
	await _physics(4)

	EventBus.interact_target_changed.connect(_spy_target)
	player.global_position = argo.global_position + Vector2(0, 17)
	await _physics(4)
	EventBus.interact_target_changed.disconnect(_spy_target)
	_check(_last_target == argo, "facing an NPC selects it as the interact target")

	DialogueRunner.line_shown.connect(_spy_line)
	argo.interact(player)
	await _idle()
	DialogueRunner.line_shown.disconnect(_spy_line)
	_check(_last_speaker == "Argo", "talking to an NPC starts its dialogue")
	_check(GameState.is_input_locked(), "an open dialogue locks player input")

	var box: CanvasLayer = main.get_node("DialogueBox")
	_check(box.get_node("Box").visible, "the dialogue box is on screen")
	await _close_dialogue()
	_check(not box.get_node("Box").visible, "the box closes when the conversation ends")
	_check(not GameState.is_input_locked(), "closing the dialogue unlocks input")
	_check(GameState.has_flag(&"met_argo"), "finishing a conversation sets the NPC's flag")

	# --- quests, in the real booted game ---
	# quest_test.gd owns the rules. What matters here is that the autoload is wired
	# into a running game, that its two views are in the shell, and that a real
	# floor_cleared from a real boss fight reaches an objective further down.
	_check(main.get_node_or_null("QuestTracker") != null, "the shell has a quest tracker")
	_check(main.get_node_or_null("GameMenu") != null, "and a game menu with the journal in it")
	GameState.set_flag(QuestLog.flag_for(&"argo_first_errand", QuestLog.FLAG_DONE))
	_check(QuestLog.start(&"argo_illfang"), "a quest can be taken in the running game")
	_check(QuestLog.tracked() != null and QuestLog.tracked().quest.id == &"argo_illfang",
			"and the tracker follows it")

	# --- chest ---
	var chest: Node2D = town.get_node("Chest")
	_check(chest.is_available(), "an unopened chest is interactable")
	chest.interact(player)
	await _idle()
	_check(GameState.has_flag(&"chest_town_square"), "opening a chest sets its flag")
	_check(not chest.is_available(), "an opened chest is no longer interactable")
	_check(GameState.col() == FloorTuning.chest_col(1, 0), "and pays its Col into the purse")
	await _close_dialogue()

	await _test_shop(main, town, player)
	await _test_forge(main, town, player)

	# --- map transition ---
	SceneRouter.change_map("res://scenes/world/field.tscn", &"from_town")
	await _until_unlocked()
	var field := world_root.get_child(0)
	_check(world_root.get_child_count() == 1, "the old map is freed on transition")
	_check(field.get(&"map_id") == &"field_f1", "transition loads the target map")

	var field_player: Node2D = field.get_node("Player")
	_check(field_player.global_position.is_equal_approx(Vector2(392, 40)),
			"player arrives at the named spawn point (got %s)" % field_player.global_position)
	_check(GameState.current_map_path.ends_with("field.tscn"), "GameState tracks the current map")

	# --- state that must survive the transition ---
	_check(GameState.has_flag(&"met_argo"), "world flags survive a map change")

	# --- roaming monsters ---
	var monster: Node2D = field.get_node("Monster0")
	_check(monster.is_available(), "the field has a monster standing on it")
	var monster_xp := GameState.xp
	_field = null
	_fight_camera = null
	monster.interact(field_player)
	await _auto_battle()
	await _check_staging(field as GameMap, field_player as Player, "a monster fight")
	_check(GameState.xp > monster_xp or GameState.level > 1, "beating a monster pays XP")
	_check(not is_instance_valid(monster) or monster.is_queued_for_deletion(),
			"a beaten monster leaves the map")
	await _close_dialogue()

	# --- clearing floor 1 and ascending ---
	_check(GameState.current_floor == 1, "the authored maps report floor 1")
	_check(not GameState.is_floor_unlocked(2), "floor 2 is locked before the boss")

	# The smoke test is about the loop, not the balance -- combat_test.gd owns
	# whether Illfang is fair. Walk in overpowered so this can't fail on dice.
	GameState.attack = 400
	GameState.max_hp = 4000
	GameState.set_hp(4000)

	var gate: Node2D = field.get_node("BossGate")
	# Floor 1 ends in a labyrinth too: Illfang's door shows only from its room.
	var field_walls: TileMapLayer = field.get_node("Walls")
	var illfang_room: Rect2i = field.get_meta(&"boss_room", Rect2i())
	_check(not (gate as BossGate).revealed and not (gate as BossGate).is_available(),
			"Illfang's door is hidden in the field's labyrinth")
	field_player.global_position = field_walls.map_to_local(illfang_room.position)
	await _physics(4)
	_check((gate as BossGate).revealed and GameState.has_flag(BossGate.found_flag(1)),
			"and shows once you walk into its room")
	await _close_dialogue()
	await _idle(2)
	_staged_figures = -1
	_field = null
	_fight_camera = null
	# Challenged from the doorstep, as it is in play: the boss steps out to where
	# you stand, and the spawn point is the other side of the map.
	field_player.global_position = gate.global_position + Vector2(0, 28)
	gate.interact(field_player)
	await _auto_battle()
	await _check_staging(field as GameMap, field_player as Player, "the boss fight")
	_check(GameState.is_floor_cleared(1), "beating the boss clears the floor")
	# The boss stepped out of its door: Illfang and the sentinel stood on the map,
	# and nothing of them is left on it now.
	_check(_staged_figures == 2, "the boss and its escort step out of the door to fight on the map")
	await get_tree().process_frame
	_check(field.get_children().all(func(node: Node) -> bool: return not node is FoeFigure),
			"and are gone from it once the fight is over")
	_check(GameState.is_floor_unlocked(2), "clearing floor 1 unlocks floor 2")

	# The quest taken back in town, finished by the boss fight it asked for --
	# BossGate never learned that quests exist.
	_check(QuestLog.is_ready(&"argo_illfang"),
			"clearing the floor completes the quest that asked for it")
	_check(QuestLog.turn_in(&"argo_illfang"), "and it can be handed in")
	_check(Inventory.count(&"guard_ring") == 1, "which pays the reward into the real bag")
	await _close_dialogue()

	gate.interact(field_player)
	await _until_unlocked()
	var floor_two := world_root.get_child(0)
	_check(floor_two.get(&"map_id") == &"floor_2", "the cleared gate ascends to floor 2")
	_check(GameState.current_floor == 2, "GameState follows the ascent")
	_check(floor_two.get_node_or_null("BossGate") != null, "a generated floor has a boss gate")
	_check(floor_two.get_node_or_null("StairsDown") != null, "a generated floor has stairs down")

	var floor_two_player: Node2D = floor_two.get_node("Player")
	var walls: TileMapLayer = floor_two.get_node("Walls")
	_check(walls.get_cell_source_id(walls.local_to_map(floor_two_player.position)) == -1,
			"the player spawns in open space, not inside a wall")

	# --- progression ---
	# Relative, not absolute: the fights above already earned levels.
	var level_before := GameState.level
	GameState.grant_xp(GameState.xp_to_next_level())
	_check(GameState.level == level_before + 1, "granting enough xp levels the player up")

	await _test_labyrinth(main, floor_two, floor_two_player as Player)
	await _test_safe_zone(floor_two, floor_two_player as Player)
	await _test_traps(floor_two, floor_two_player as Player)
	await _test_roaming(floor_two, floor_two_player as Player)
	await _test_fallen_purse(main, floor_two as GameMap, floor_two_player as Player)
	await _test_teleport(main, world_root)
	await _test_puzzles(world_root)
	await _test_village(world_root)
	await _test_open_field(world_root)
	await _test_dungeon(world_root)
	await _test_modifiers(main, world_root)
	await _test_events(world_root)


## The hidden door on a real generated floor: not there until you walk into its
## room, there for good once you have; fog of war remembering what you saw on the
## way; and the map screen opening over it on M.
func _test_labyrinth(main: Node, map: Node2D, player: Player) -> void:
	# The floor's monsters would turn a walk into a fight; _test_roaming wants
	# them gone too, and spawns its own.
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)

	var walls: TileMapLayer = map.get_node("Walls")
	var spawn_cell := walls.local_to_map(player.position)
	_check(GameState.is_explored(&"floor_2", spawn_cell) \
			and GameState.is_explored(&"floor_2", spawn_cell + Vector2i(2, 0)),
			"standing on a floor explores what is round you")

	var gate := map.get_node("BossGate") as BossGate
	_check(not gate.revealed and not gate.is_available() and not gate.get_node("Sprite2D").visible,
			"the labyrinth door is hidden until its room is found")
	var room: Rect2i = map.get_meta(&"boss_room")
	_check(not GameState.is_explored(&"floor_2", room.get_center()),
			"and the boss room starts unexplored")
	var dark := map.get_node_or_null("Darkness") as Darkness
	_check(dark != null and dark.area == map.get_meta(&"labyrinth"),
			"the labyrinth is dark beyond what you can see")
	_check(dark != null and dark.light_at(room.position) == 0.0,
			"and its boss room is in the dark from the field")

	# Into the room's corner, clear of the door: it turns solid as it appears.
	player.global_position = walls.map_to_local(room.position)
	await _physics(4)
	_check(dark != null and dark.light_at(room.position + Vector2i(1, 0)) < 1.0,
			"the light fades in rather than jumping")
	_check(gate.revealed and GameState.has_flag(BossGate.found_flag(2)),
			"walking into the boss room reveals the door")
	_check(DialogueRunner.is_running(), "and says so")
	await _close_dialogue()
	await _idle(2)
	_check(gate.is_available() and gate.get_node("Sprite2D").visible, "the found door can be challenged")
	_check(GameState.is_explored(&"floor_2", walls.local_to_map(gate.position)),
			"and the door's cell is explored once you are in its room")
	var door_cell := walls.local_to_map(gate.position)
	for _frame in 60:
		if dark == null or dark.light_at(door_cell) == 1.0:
			break
		await _physics(1)
	_check(dark != null and dark.light_at(door_cell) == 1.0,
			"and lit, now you stand in its room")

	var screen: CanvasLayer = main.get_node("GameMenu")
	await _tap(&"map")
	_check(screen.call(&"is_open") and screen.visible and screen.call(&"tab") == 3
			and GameState.is_input_locked(),
			"M opens the game menu on the map, holding the input lock")
	var header: PackedStringArray = screen.call(&"page", 3).call(&"header")
	_check(header[2].contains("explored") and header[2].contains("door found"),
			"the map reports what is explored and that the door is found (got '%s')" % header[2])
	_check(header[1] == (map as GameMap).region and not header[1].is_empty(),
			"and names the floor's region (got '%s')" % header[1])
	var walked := GameState.walked_cells(&"floor_2")
	var seen := GameState.explored_cells(&"floor_2")
	_check(walked.has(walls.local_to_map(player.position)) and walked.size() < seen.size(),
			"where you stood is walked, and less is walked than seen (%d of %d)" % [walked.size(), seen.size()])
	await _tap(&"map")
	_check(not screen.call(&"is_open") and not GameState.is_input_locked(), "and M closes it again")

	# Found stays found: the same floor, rebuilt, shows its door from the start --
	# losing the boss fight rebuilds it exactly like this.
	var rebuilt := FloorRegistry.build_floor(2)
	add_child(rebuilt)
	_check((rebuilt.get_node("BossGate") as BossGate).revealed, "a found door stays found when the floor is rebuilt")
	rebuilt.free()


## The labyrinth's safe zone: walking in says what it is, a monster at its
## doorway neither steps in nor comes for you while you are inside, and the fire
## puts you back on your feet.
func _test_safe_zone(map: Node2D, player: Player) -> void:
	var walls: TileMapLayer = map.get_node("Walls")
	_check(map.has_meta(&"safe_zone"), "the labyrinth has a safe zone")
	if not map.has_meta(&"safe_zone"):
		return
	var camp: Rect2i = map.get_meta(&"safe_zone")
	player.global_position = walls.map_to_local(camp.position)
	await _physics(4)
	_check(DialogueRunner.is_running(), "walking into the safe zone says what it is")
	await _close_dialogue()
	await _idle(2)

	# A doorway out of the camp, and the cell beyond it, where the monster waits.
	var doorway := Vector2i(-1, -1)
	var outward := Vector2i.ZERO
	for cell in _ring_of(camp.grow(1)):
		if walls.get_cell_source_id(cell) != -1:
			continue
		doorway = cell
		outward = Vector2i(signi(cell.x - camp.get_center().x) if cell.x < camp.position.x or cell.x >= camp.end.x else 0,
				signi(cell.y - camp.get_center().y) if cell.y < camp.position.y or cell.y >= camp.end.y else 0)
		break
	_check(doorway.x >= 0, "the safe zone has a way in")
	if doorway.x < 0:
		return
	var inside := doorway - outward * 2
	player.global_position = walls.map_to_local(inside)
	var monster := _spawn_monster(map, walls.map_to_local(doorway + outward))
	var strayed := false
	for _i in 180:
		await _physics()
		strayed = strayed or camp.has_point(walls.local_to_map(monster.global_position + Monster.FOOT))
	_check(not strayed, "a monster never steps into the safe zone")
	_check(monster.state != Monster.State.CHASE and not CombatManager.is_running(),
			"and does not come for the player inside it, %d px away" \
			% roundi(monster.global_position.distance_to(player.global_position)))
	monster.queue_free()

	var fire := map.get_node_or_null("Campfire") as Campfire
	_check(fire != null and fire.is_available(), "the safe zone has a fire to rest by")
	if fire == null:
		return
	GameState.set_hp(1)
	fire.interact(player)
	_check(GameState.hp == GameState.total_max_hp(), "resting by the fire restores all HP")
	await _close_dialogue()
	await _idle(2)


## Gilded chests, sprung on a real floor 2: the item still lands, an alarm brings
## monsters that come for you, a teleport sets you down where it said it would.
func _test_traps(map: Node2D, player: Player) -> void:
	var walls: TileMapLayer = map.get_node("Walls")
	var block := _open_block(walls, Vector2i(5, 5))
	_check(block.size != Vector2i.ZERO, "floor 2 has a 5x5 open block to spring a trap in")
	if block.size == Vector2i.ZERO:
		return
	var centre := block.position + Vector2i(1, 2)
	var potions := Inventory.count(&"small_potion")
	var alarm := _trapped_chest(map, walls, centre, Chest.Trap.ALARM, &"smoke_alarm")
	player.global_position = walls.map_to_local(centre + Vector2i(0, 1))
	alarm.interact(player)
	_check(Inventory.count(&"small_potion") == potions + 1, "a trapped chest still pays out")
	var pack: Array[Monster] = []
	for child in map.get_children():
		if child is Monster and child.name.begins_with("Alarm"):
			pack.append(child)
	# As many as there is floor for, three cells out -- a 5x5 block may be walled in.
	_check(pack.size() > 0 and pack.size() <= Chest.ALARM_PACK,
			"its alarm brings monsters (%d of %d)" % [pack.size(), Chest.ALARM_PACK])
	await _close_dialogue()
	var hunted := false
	for _i in 20:
		await _physics()
		hunted = hunted or pack.any(func(m: Monster) -> bool: return m.state == Monster.State.CHASE)
	_check(hunted, "and they come for you once the box closes")
	for monster in pack:
		monster.queue_free()
	if CombatManager.is_running():
		await _flee_battle()
		await _close_dialogue()
	await _physics(2)

	var room: Rect2i = map.get_meta(&"boss_room")
	var target := walls.map_to_local(room.position)
	var teleport := _trapped_chest(map, walls, centre + Vector2i(2, 0), Chest.Trap.TELEPORT, &"smoke_teleport")
	teleport.trap_target = target
	player.global_position = walls.map_to_local(centre + Vector2i(2, 1))
	teleport.interact(player)
	await _close_dialogue()
	var moved := false
	for _i in 120:
		await _idle()
		if player.position.distance_to(target) < 1.0 and not GameState.is_input_locked() \
				or DialogueRunner.is_running():
			moved = player.position.distance_to(target) < 1.0
			if moved and DialogueRunner.is_running():
				break
	_check(moved, "a teleport trap sets you down where it leads")
	await _close_dialogue()
	await _idle(2)
	_check(not GameState.is_input_locked(), "and hands the controls back")
	# Out of the way of the roaming test, which paints its wall in the same block.
	alarm.queue_free()
	teleport.queue_free()
	await _physics(2)


## The four puzzles and the cracked wall, on a real floor 2: the wisp leads, waits for you and
## lights its shrine; the braziers go out in the wrong order and when the fire
## runs down, hold their clock through the input lock, and pay out when all are
## lit; a statue turns its neighbours with it, and the ring wakes the altar once
## all four face it; the vault stays shut until the last sigil is in hand. Each
## chest appears only once its puzzle is solved. The cracked wall is rock until
## E breaks it, and broken when you come back.
##
## The teleport gates, through the real menu: from floor 2's gate down to the Town
## of Beginnings, a look and a change of mind there, and back up to floor 2 --
## arriving in front of the gate each time.
func _test_teleport(main: Node, world_root: Node2D) -> void:
	var menu := main.get_node("GateMenu")
	_check(GameState.visited_floors() == ([1, 2] as Array[int]),
			"standing on a floor marks it visited (%s)" % [GameState.visited_floors()])

	var map := world_root.get_child(0) as GameMap
	await _touch_gate(map)
	_check(menu.is_open() and GameState.is_input_locked(),
			"touching floor 2's teleport gate opens the floor list and holds the lock")
	_check(menu.selected_floor() == 1, "and it starts on the one floor that isn't here")
	await _tap(&"interact")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	_check(map.map_id == &"town" and GameState.current_floor == 1 and not menu.is_open(),
			"choosing floor 1 takes you to the Town of Beginnings")
	_check(_at_spawn(map, &"gate"), "arriving in front of the town's gate")

	await _touch_gate(map)
	_check(menu.is_open() and menu.selected_floor() == 2,
			"the town's gate opens on the front line, floor 2")
	await _tap(&"ui_cancel")
	_check(not menu.is_open() and not GameState.is_input_locked(),
			"cancelling closes the list and lets go of the lock")
	await _touch_gate(map)
	await _tap(&"interact")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	_check(map.map_id == &"floor_2" and GameState.current_floor == 2 and _at_spawn(map, &"gate"),
			"and the gate takes you back up, in front of floor 2's gate")


## Stands the player at [param map]'s gate spawn facing the gate and presses
## interact, the way a player would.
func _touch_gate(map: GameMap) -> void:
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	var player := map.get_node("Player") as Player
	player.global_position = (map.get_node("SpawnPoints/gate") as Node2D).global_position
	player.velocity = Vector2.ZERO
	player.facing = Vector2.UP
	await _physics(4)
	await _tap(&"interact")


func _at_spawn(map: GameMap, spawn: StringName) -> bool:
	var marker := map.get_node("SpawnPoints/%s" % spawn) as Node2D
	return (map.get_node("Player") as Node2D).global_position.distance_to(marker.global_position) < 2.0


## The world seed is random per run and a floor may lack a puzzle (the floor test
## counts how many do), so this picks a seed whose floor 2 has all four and a
## cracked wall, with a timed rite, and goes back up to it.
func _test_puzzles(world_root: Node2D) -> void:
	var picked := 0
	for candidate in range(1, 400):
		GameState.new_world_seed(candidate)
		var probe := FloorRegistry.build_floor(2)
		var rite := probe.get_node_or_null("BrazierRite") as BrazierRite
		var whole := probe.get_node_or_null("Wisp") != null and probe.get_node_or_null("SealedDoor") != null \
				and probe.get_node_or_null("StatueRing") != null \
				and probe.get_node_or_null("CrackedWall") != null \
				and rite != null and rite.mode == BrazierRite.Mode.TIMED
		probe.free()
		if whole:
			picked = candidate
			break
	_check(picked > 0, "some world seed's floor 2 has a wisp, a timed rite, statues, a vault and a crack")
	if picked == 0:
		return
	for flag: StringName in [&"puzzle_2_wisp", &"puzzle_2_braziers", &"puzzle_2_statues",
			&"puzzle_2_vault", &"puzzle_2_crack"]:
		GameState.set_flag(flag, false)
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := world_root.get_child(0) as GameMap
	var player := map.get_node("Player") as Player
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)

	# --- the wisp ---
	var wisp := map.get_node("Wisp") as Wisp
	var shrine := map.get_node("WispShrine") as WispShrine
	var wisp_chest := map.get_node("ChestWisp") as Chest
	_check(not wisp_chest.is_available() and not wisp_chest.visible and not shrine.is_lit(),
			"the wisp's chest is not there until the wisp is home")
	player.global_position = wisp.global_position + Vector2(0, 16)
	await _physics(2)
	var setting_off := wisp.global_position
	for _i in 60:
		player.global_position = wisp.global_position + Vector2(0, 16)
		await _physics()
	_check(wisp.state == Wisp.State.LEADING and wisp.global_position.distance_to(setting_off) > 20.0,
			"walking up to the wisp sets it off, and it leads")
	player.global_position = wisp.global_position + Vector2(0, Wisp.WAIT + 40.0)
	await _physics(3)
	var waiting_at := wisp.global_position
	await _physics(30)
	_check(wisp.state == Wisp.State.WAITING and wisp.global_position == waiting_at,
			"it waits for you when you fall behind")
	# The walk itself is long and the floor test proves it; skip to the last stretch.
	wisp.position = wisp.path[wisp.path.size() - 3]
	wisp.set(&"_next", wisp.path.size() - 2)
	for _i in 120:
		if not is_instance_valid(wisp) or DialogueRunner.is_running():
			break
		player.global_position = wisp.global_position + Vector2(0, 16)
		await _physics()
	await _idle(2)
	_check(GameState.has_flag(&"puzzle_2_wisp") and DialogueRunner.is_running(),
			"at the shrine it sinks in, and says so")
	await _close_dialogue()
	await _idle(2)
	_check(shrine.is_lit() and wisp_chest.is_available() and wisp_chest.visible,
			"the shrine lights and its chest appears")
	# It appears a cell below the shrine -- where you stood to watch the wisp go in.
	var lid := wisp_chest.get_node("Solid/CollisionShape2D") as CollisionShape2D
	player.global_position = wisp_chest.global_position
	await _physics(4)
	_check(lid.disabled, "a chest that appears where you stand doesn't close round you")
	player.global_position = wisp_chest.global_position + Vector2(24, 0)
	await _physics(4)
	_check(not lid.disabled, "and is solid once you step off it")
	_check(_open_sealed(wisp_chest, player), "the wisp's chest opens, a sigil under its loot")
	await _close_dialogue()
	await _idle(2)

	# --- the braziers ---
	var rite := map.get_node("BrazierRite") as BrazierRite
	var rite_chest := map.get_node("ChestRite") as Chest
	var fires := rite.braziers
	var tablet := map.get_node("Tablet") as Tablet
	_check(tablet.lines.size() > 0 and tablet.lines[0].contains("while the first still burns"),
			"the tablet says the fires are against the clock")
	_check(not rite_chest.is_available(), "the braziers' chest is not there until they are lit")
	# Out of order first, as an ordered rite: they all go out.
	rite.mode = BrazierRite.Mode.ORDERED
	rite.order.clear()
	for i in fires.size():
		rite.order.append(fires.size() - 1 - i)
	fires[0].interact(player)
	await _physics(40)
	_check(DialogueRunner.is_running() and fires.all(func(b: Brazier) -> bool: return not b.lit),
			"lit out of order, the fires gutter out and the stone says why")
	await _close_dialogue()
	await _idle(2)
	rite.mode = BrazierRite.Mode.TIMED
	var burn := rite.burn
	rite.burn = 0.3
	fires[0].interact(player)
	GameState.push_input_lock()
	await _physics(40)
	_check(fires[0].lit, "a timed rite's clock stops while the input lock is held")
	GameState.pop_input_lock()
	await _physics(40)
	_check(DialogueRunner.is_running() and not fires[0].lit, "and the fire goes out once the time is up")
	await _close_dialogue()
	await _idle(2)
	rite.burn = burn
	for brazier in fires:
		brazier.interact(player)
		await _physics(2)
	_check(GameState.has_flag(&"puzzle_2_braziers") and DialogueRunner.is_running(),
			"lighting every fire in time solves the rite")
	await _close_dialogue()
	await _idle(2)
	_check(rite_chest.is_available() and rite_chest.visible, "and its chest appears")
	_check(_open_sealed(rite_chest, player), "the braziers' chest opens, a sigil under its loot")
	await _close_dialogue()
	await _idle(2)

	# --- the statues ---
	var ring := map.get_node("StatueRing") as StatueRing
	var altar := map.get_node("StatueAltar") as StatueAltar
	var ring_chest := map.get_node("ChestStatues") as Chest
	var statues := ring.statues
	_check(not altar.is_lit() and not ring_chest.is_available() and not ring.all_facing(),
			"the statues look away, the altar is dark and its chest is not there")
	var before: Array[int] = []
	for statue in statues:
		before.append(statue.facing)
	statues[0].interact(player)
	var turned := true
	for i in statues.size():
		var expected := before[i] + (1 if i in StatueRing.turned_by(0, statues.size()) else 0)
		turned = turned and statues[i].facing == posmod(expected, 4)
	_check(turned and statues[2].facing == before[2],
			"turning a statue turns the two beside it and leaves the one across alone")
	var facings: Array[int] = []
	for statue in statues:
		facings.append(statue.facing)
	var turns := StatueRing.turns_to_solve(facings, ring.targets)
	_check(not turns.is_empty(), "the ring can be solved from wherever it stands")
	for i in turns.size():
		for _t in turns[i]:
			statues[i].interact(player)
	await _idle(2)
	_check(GameState.has_flag(&"puzzle_2_statues") and ring.all_facing() and DialogueRunner.is_running(),
			"with all four facing in, the ring is solved and says so")
	await _close_dialogue()
	await _idle(2)
	var facing_now := statues[0].facing
	statues[0].interact(player)
	_check(statues[0].facing == facing_now, "a solved ring turns no more")
	_check(altar.is_lit() and ring_chest.is_available() and ring_chest.visible,
			"the altar's orb lights and its chest appears")
	_check(_open_sealed(ring_chest, player), "the statues' chest opens, a sigil under its loot")
	await _close_dialogue()
	await _idle(2)

	# --- the vault ---
	var seal := map.get_node("SealedDoor") as SealedDoor
	var vault_chest := map.get_node("ChestVault") as Chest
	seal.interact(player)
	await _idle(2)
	_check(not seal.is_opened() and seal.held() == seal.sigils.size() - 1,
			"the sealed door stays shut one sigil short (%d of %d)" % [seal.held(), seal.sigils.size()])
	await _close_dialogue()
	await _idle(2)
	var last: Chest = null
	for child in map.get_children():
		if child is Chest and (child as Chest).sigil_flag in seal.sigils \
				and not GameState.has_flag((child as Chest).sigil_flag):
			last = child
	_check(last != null and not last.sealed, "the last sigil is under one of the floor's own chests")
	if last == null:
		return
	last.trap = Chest.Trap.NONE  # traps have a test of their own
	last.interact(player)
	await _close_dialogue()
	await _idle(2)
	seal.interact(player)
	await _close_dialogue()
	var shut := true
	for _i in 120:
		await _physics()
		shut = false
		for shape in seal.get_node("Solid").get_children():
			shut = shut or not (shape as CollisionShape2D).disabled
		if not shut:
			break
	_check(seal.is_opened() and not shut and not seal.is_available(),
			"with every sigil the door opens for good")
	_check(_open_sealed(vault_chest, player, false), "and the vault's chest is there to open")
	await _close_dialogue()
	await _idle(2)

	# --- the cracked wall ---
	var crack := map.get_node("CrackedWall") as CrackedWall
	var crack_chest := map.get_node("ChestCrack") as Chest
	var walls := map.get_node("Walls") as TileMapLayer
	var face := walls.local_to_map(crack.position)
	_check(walls.get_cell_source_id(face) != -1 and walls.get_cell_source_id(crack.hollow.position) != -1
			and not crack_chest.is_available() and not crack_chest.visible,
			"behind the cracked wall is rock, and the chest in it is not there")
	var toward := StringName({Vector2i.UP: "move_up", Vector2i.LEFT: "move_left",
			Vector2i.RIGHT: "move_right"}[crack.side])
	player.global_position = walls.map_to_local(face - crack.side)
	# Leaning on the wall turns you to it; and the box that just closed leaves E
	# deaf for a moment.
	await _hold(toward, 3)
	await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
	await _tap(&"interact")
	await _idle(2)
	_check(GameState.has_flag(&"puzzle_2_crack") and DialogueRunner.is_running(),
			"E on the crack breaks the wall, and says so")
	await _close_dialogue()
	await _until_unlocked()
	var carved := true
	for rect: Rect2i in [crack.door, crack.hollow]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				carved = carved and walls.get_cell_source_id(Vector2i(x, y)) == -1
	_check(carved and not crack.is_available() and crack_chest.is_available() and crack_chest.visible,
			"the doorway and the hollow are open, and the chest is there")
	# Walked into for real: the wall's collision has to have gone too.
	await _hold(toward, 24)
	_check(crack.door.grow(1).intersects(Rect2i(walls.local_to_map(player.position), Vector2i.ONE))
			and walls.local_to_map(player.position) != face - crack.side,
			"and you can walk in through it")
	_check(_open_sealed(crack_chest, player, false), "the hollow's chest opens")
	await _close_dialogue()
	await _idle(2)
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var again := world_root.get_child(0) as GameMap
	var again_crack := again.get_node("CrackedWall") as CrackedWall
	_check(again != map and not again_crack.is_available()
			and (again.get_node("Walls") as TileMapLayer).get_cell_source_id(face) == -1,
			"and it is still broken when you come back")


## Floor 2 once Floor 5 falls: its camp has settled into a village, with settlers
## where the campers were -- and the lost player its job sends you after is in the
## labyrinth only once you have taken the job, and gone once you have found them.
## Picks a seed whose floor 2 has a lost player and both settlers.
func _test_village(world_root: Node2D) -> void:
	var job := LocalQuests.talk_quest(2)
	var picked := 0
	GameState.clear_floor(5)
	for candidate in range(1, 400):
		GameState.new_world_seed(candidate)
		if not LocalQuests.ids_for(2).has(job):
			continue
		var probe := FloorRegistry.build_floor(2)
		var whole := probe.get_node_or_null("LostPlayer") != null and probe.get_node_or_null("Settler1") != null
		probe.free()
		if whole:
			picked = candidate
			break
	_check(picked > 0, "some world seed's floor 2 settles with both settlers and a lost player")
	if picked == 0:
		return
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := world_root.get_child(0) as GameMap
	var player := map.get_node("Player") as Player
	_check(map.get_node_or_null("Settler0") != null and map.get_node_or_null("Camper0") == null,
			"a settled floor's camp has settlers in it, and its campers have gone up")
	var lost := map.get_node("LostPlayer") as Npc
	_check(not lost.visible and not lost.is_available(), "nobody is lost in the labyrinth until you are asked")
	QuestLog.start(job)
	await _idle(2)
	_check(lost.visible and lost.is_available(), "taking the job puts them there")
	player.global_position = lost.global_position + Vector2(0, 16)
	lost.interact(player)
	await _close_dialogue()
	_check(QuestLog.is_ready(job), "and finding them is the job done")
	await _idle(2)
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	_check(world_root.get_child(0).get_node_or_null("LostPlayer") == null,
			"and they have found their own way out by the time you come back")


## An open field, built as floor 2 for the occasion: the door in plain view in an
## arena whose gate is sealed, examining the gate says so, and waking the waystones
## out in the field -- by walking up and pressing E -- breaks it, from wherever the
## last of them stands, and marks the door found.
func _test_open_field(world_root: Node2D) -> void:
	FloorGenerator.shape_override = FloorDefinition.Shape.OPEN_FIELD
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := world_root.get_child(0) as GameMap
	var player := map.get_node("Player") as Player
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)
	var gate := map.get_node("BossGate") as BossGate
	var seal := map.get_node_or_null("ArenaSeal") as SealedDoor
	_check(seal != null and gate.revealed and not map.dark_area.has_area()
			and map.get_node_or_null("Waystone2") != null,
			"an open field's door stands in plain view in an arena, under the open sky")
	if seal == null:
		FloorGenerator.shape_override = -1
		return
	for flag in seal.sigils:
		GameState.set_flag(flag, false)
	for flag: StringName in [seal.opened_flag, BossGate.found_flag(2)]:
		GameState.set_flag(flag, false)
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	player = map.get_node("Player") as Player
	seal = map.get_node("ArenaSeal") as SealedDoor
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)

	_line_spy.clear()
	DialogueRunner.line_shown.connect(_spy_text)
	seal.interact(player)
	await _close_dialogue()
	DialogueRunner.line_shown.disconnect(_spy_text)
	_check(not seal.is_opened() and _line_spy.size() > 0 and "Waystones" in _line_spy[-1],
			"the arena's gate is sealed, and says the waystones are what opens it")
	var stones: Array[Waystone] = []
	for child in map.get_children():
		if child is Waystone:
			stones.append(child as Waystone)
	for i in stones.size():
		player.global_position = stones[i].global_position + Vector2(0, 14)
		player.facing = Vector2.UP
		await _physics(4)
		# The box before this one has just closed, and E is deaf for a moment after.
		await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
		await _tap(&"interact")
		await _close_dialogue()
		await _idle(2)
		if i < stones.size() - 1:
			_check(stones[i].is_woken() and not seal.is_opened(),
					"a waystone wakes under your hand, and the gate holds while any sleeps (%d)" % i)
	_check(stones.all(func(stone: Waystone) -> bool: return stone.is_woken()), "every waystone is woken")
	_check(seal.is_opened() and GameState.has_flag(BossGate.found_flag(2)),
			"waking the last waystone breaks the seal from across the field, and the door counts as found")
	# The stone fades for half a second before the gate stops being solid.
	await get_tree().create_timer(SealedDoor.OPEN_TIME + 0.2).timeout
	await _physics(2)
	_check(seal.get_node("Solid").get_child(0).disabled, "and the gate can be walked through")
	FloorGenerator.shape_override = -1


## A dungeon, built as floor 2 for the occasion, on a world whose first level is
## sealed by levers and second by a warden: the entrance hall is lit and the rest is
## dark, the seal says what opens it, pulling the levers with real E presses opens
## it, the ladder climbs to level 2 (its own map, [code]floor://2/2[/code]) and the
## stairs there come back down to the ladder; beating the warden opens level 2's,
## the top level's door is found as you arrive, a save made up there comes back up
## there.
func _test_dungeon(world_root: Node2D) -> void:
	FloorGenerator.shape_override = FloorDefinition.Shape.DUNGEON
	var picked := 0
	for candidate in range(1, 600):
		GameState.new_world_seed(candidate)
		var kinds := DungeonGenerator.seal_kinds(FloorRegistry.seed_for(2), FloorRegistry.levels_of(2))
		if kinds[1] != DungeonGenerator.Seal.LEVERS or kinds[2] != DungeonGenerator.Seal.WARDEN:
			continue
		var probe := FloorRegistry.build_floor(2, 1)
		var by_levers: bool = probe.get_meta(&"seal", "") == "levers"
		probe.free()
		if by_levers:
			picked = candidate
			break
	_check(picked > 0, "some world seed's floor 2, built as a dungeon, is sealed by levers and then a warden")
	if picked == 0:
		FloorGenerator.shape_override = -1
		return
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := world_root.get_child(0) as GameMap
	var player := map.get_node("Player") as Player
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)
	var seal := map.get_node_or_null("StairsSeal") as SealedDoor
	_check(map.map_id == &"floor_2" and GameState.current_map_path == "floor://2"
			and "Level 1 of 3" in map.region and map.darkness() != null
			and map.lit_areas.has(map.get_meta(&"camp")) and seal != null
			and map.get_node_or_null("TeleportGate") != null,
			"a dungeon's first level is the floor's own map: a lit entrance hall with the gate, then the dark")
	_check(MapPage.status_line(map).ends_with("stairs sealed"), "the map screen says its stairs are sealed")

	_line_spy.clear()
	DialogueRunner.line_shown.connect(_spy_text)
	seal.interact(player)
	await _close_dialogue()
	DialogueRunner.line_shown.disconnect(_spy_text)
	_check(not seal.is_opened() and _line_spy.size() > 0 and "lever" in _line_spy[-1],
			"the slab across the ladder is sealed, and says levers are what opens it")
	var levers: Array[Waystone] = []
	for child in map.get_children():
		if child is Waystone:
			levers.append(child as Waystone)
	for lever in levers:
		player.global_position = lever.global_position + Vector2(0, 14)
		player.facing = Vector2.UP
		await _physics(4)
		await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
		await _tap(&"interact")
		await _close_dialogue()
		await _idle(2)
	_check(levers.size() == 2 and seal.is_opened(), "pulling both levers opens the stairs")
	await get_tree().create_timer(SealedDoor.OPEN_TIME + 0.2).timeout
	await _physics(2)

	# Up the ladder, onto a map of its own; and down again to the foot of the ladder.
	player.global_position = (map.get_node("SpawnPoints/stairs_up") as Node2D).global_position
	player.facing = Vector2.UP
	await _physics(4)
	await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
	await _tap(&"interact")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	player = map.get_node("Player") as Player
	_check(map.map_id == &"floor_2_2"
			and GameState.current_map_path == "floor://2/2" and GameState.current_floor == 2
			and _at_spawn(map, &"stairs_down"),
			"the ladder climbs to level 2, its own map, arriving at its stairs down")
	for child in map.get_children():
		if child is Monster and child.name != "Warden":
			child.queue_free()
	await _physics(2)
	player.global_position = (map.get_node("StairsDown") as Node2D).global_position + Vector2(0, 14)
	player.facing = Vector2.UP
	await _physics(4)
	await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
	await _tap(&"interact")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	_check(map.map_id == &"floor_2" and _at_spawn(map, &"stairs_up")
			and (map.get_node("StairsSeal") as SealedDoor).is_opened(),
			"the stairs down come back to the foot of the ladder, and the seal stays open")

	# Level 2's warden: beaten, it stays beaten, and its fall opens the way up.
	await SceneRouter.enter_floor(2, &"stairs_down", SceneRouter.FADE_TIME, 2)
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	player = map.get_node("Player") as Player
	var warden := map.get_node_or_null("Warden") as Monster
	_check(warden != null and warden.level > FloorTuning.enemy_level(2) and warden.defeat_flag != &"",
			"level 2's stairs are kept by a warden, stronger than the level's monsters")
	if warden == null:
		FloorGenerator.shape_override = -1
		return
	for child in map.get_children():
		if child is Monster and child != warden:
			child.queue_free()
	player.global_position = warden.global_position + Vector2(0, 16)
	player.facing = Vector2.UP
	await _physics(2)
	warden.interact(player)
	await _auto_battle()
	await _idle(4)
	seal = map.get_node("StairsSeal") as SealedDoor
	_check(not is_instance_valid(warden) or warden.is_queued_for_deletion(), "the warden falls")
	_check(seal.is_opened() and GameState.has_flag(DungeonGenerator.stairs_flag(2, 2)),
			"and its fall opens level 2's stairs")
	await _close_dialogue()
	await SceneRouter.enter_floor(2, &"stairs_down", SceneRouter.FADE_TIME, 2)
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	_check(map.get_node_or_null("Warden") == null, "a beaten warden stays beaten when you come back")

	# The top: the boss hall lit at the end of a short walk, its door found as you arrive.
	GameState.set_flag(BossGate.found_flag(2), false)
	await SceneRouter.enter_floor(2, &"stairs_down", SceneRouter.FADE_TIME, 3)
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	player = map.get_node("Player") as Player
	var door := map.get_node_or_null("BossGate") as BossGate
	_check(door != null and door.revealed and GameState.has_flag(BossGate.found_flag(2))
			and map.get_node_or_null("LadderUp") == null and "Level 3 of 3" in map.region,
			"the top level is the boss hall, its door in plain view and found as you arrive")

	# A save on the top level comes back to the top level.
	player.global_position = (map.get_node("SpawnPoints/default") as Node2D).global_position + Vector2(16, 0)
	await _physics(2)
	var snapshot := SaveGame.snapshot()
	_check(snapshot["place"]["map"] == "floor://2/3", "a save on a dungeon's level names the level")
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var place: Dictionary = snapshot["place"]
	await SceneRouter.resume(place["map"], Vector2(place["x"], place["y"]), Vector2.UP)
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	player = map.get_node("Player") as Player
	_check(map.map_id == &"floor_2_3" and player.position.distance_to(Vector2(place["x"], place["y"])) < 1.0,
			"and loading it puts you back on that level, on the spot")
	FloorGenerator.shape_override = -1


## Floor modifiers on a real floor 2: a storm says so as you arrive, hangs its
## weather over the map and has the scout mention it, and a monster notices you
## from only half as far in it; an infested floor carries its swarm; and a plain
## floor announces nothing.
func _test_modifiers(main: Node, world_root: Node2D) -> void:
	var hud := main.get_node("Hud")
	FloorGenerator.modifier_override = FloorModifier.Kind.STORM
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	var map := world_root.get_child(0) as GameMap
	var player := map.get_node("Player") as Player
	_check(hud.call(&"headline") == "Rainstorm" and "Rainstorm" in map.region,
			"arriving on a storm floor puts its name up over the map, and on the map screen")
	var storm := map.get_node_or_null("Weather") as Weather
	_check(storm != null and storm.kind == &"rain" and storm.is_processing()
			and map.notice_scale == FloorTuning.STORM_NOTICE,
			"a storm on the meadow is rain, falling over the map")
	var scout := map.get_node_or_null("Camper0") as Npc
	var mentioned := false
	if scout != null and scout.dialogue != null:
		for line in scout.dialogue.lines:
			mentioned = mentioned or line.text == FloorModifier.camp_line(FloorModifier.Kind.STORM, &"rain")
	_check(scout == null or mentioned, "and the camp's scout has a word about the weather")

	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)
	var walls: TileMapLayer = map.get_node("Walls")
	var block := _open_block(walls, Vector2i(5, 5))
	if block.size != Vector2i.ZERO:
		player.global_position = walls.map_to_local(block.position + Vector2i(0, 2))
		# Three cells off: inside a monster's reach in clear weather, outside it in a storm.
		var monster := _spawn_monster(map, walls.map_to_local(block.position + Vector2i(3, 2)))
		await _physics(2)
		var in_storm: bool = monster.call(&"_notices", player)
		map.notice_scale = 1.0
		var in_clear: bool = monster.call(&"_notices", player)
		map.notice_scale = FloorTuning.STORM_NOTICE
		monster.global_position = player.global_position + Vector2(24, 0)
		var close: bool = monster.call(&"_notices", player)
		_check(not in_storm and in_clear and close,
				"in a storm a monster three cells off doesn't notice you, as it would in the clear -- only one close by")
		monster.queue_free()

	FloorGenerator.modifier_override = FloorModifier.Kind.INFESTED
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	map = world_root.get_child(0) as GameMap
	var swarm := 0
	for child in map.get_children():
		if child is Monster and String(child.name).begins_with("Swarm"):
			swarm += 1
	_check(hud.call(&"headline") == "Infested" and swarm == FloorTuning.infested_count(2)
			and map.get_node_or_null("Weather") == null,
			"an infested floor says so too, and carries half as many monsters again (%d more)" % swarm)

	# Straight on to a plain floor, the headline still up: it goes.
	FloorGenerator.modifier_override = -1
	await SceneRouter.enter_floor(2, &"default")
	await _until_unlocked()
	_check(hud.call(&"headline") == "" and world_root.get_child(0).get_node_or_null("Weather") == null,
			"floor 2 itself is plain: nothing announced -- the last floor's headline taken down -- and no weather")


## Floor events, each forced onto a real floor: a field boss in front of its hoard,
## which opens as it falls; a stranded player who follows you home, through a fight
## a monster starts on them, and pays for it; player killers who spring as you walk
## into their room, paid off once and fought once; and a duellist in the camp,
## refused hurt, lost to, beaten -- and one who turns on you.
func _test_events(world_root: Node2D) -> void:
	var strength := GameState.attack
	# Every fight here is one to win quickly, not to measure.
	GameState.attack += 400

	# A field boss, and its hoard.
	FloorGenerator.event_override = FloorEvents.Kind.FIELD_BOSS
	var map := await _event_floor(world_root, 2)
	var player := map.get_node("Player") as Player
	var keeper := map.get_node_or_null("FieldBoss") as Monster
	var seal := map.get_node_or_null("HoardSeal") as SealedDoor
	var hoard := map.get_node_or_null("ChestHoard") as Chest
	_check(keeper != null and seal != null and hoard != null and keeper.boss and not seal.is_opened(),
			"a field boss stands guard in front of a hoard, its door shut")
	if keeper != null and seal != null and hoard != null:
		player.global_position = keeper.global_position + Vector2(0, 16)
		await _physics(2)
		keeper.interact(player)
		await _auto_battle()
		await _idle(4)
		_check(GameState.has_flag(FloorEvents.flag(2, "boss")) and seal.is_opened(),
				"it fights as a boss, and as it falls the hoard opens itself")
		await _close_dialogue()
		_check(_open_sealed(hoard, player, false), "and the chest in the hoard pays out")
		await _close_dialogue()
		map = await _event_floor(world_root, 2)
		_check(map.get_node_or_null("FieldBoss") == null
				and (map.get_node("HoardSeal") as SealedDoor).is_opened(),
				"a beaten field boss stays beaten, its hoard open")

	# A stranded player, taken home.
	FloorGenerator.event_override = FloorEvents.Kind.ESCORT
	var job := FloorEvents.escort_quest(2)
	map = await _event_floor(world_root, 2)
	player = map.get_node("Player") as Player
	var stranded := map.get_node_or_null("Stranded") as Escortee
	var besiegers := 0
	for child in map.get_children():
		if child is Monster and String(child.name).begins_with("Besieger"):
			besiegers += 1
	_check(stranded != null and besiegers == FloorEvents.BESIEGERS,
			"a stranded player waits in the far rooms, cornered by %d monsters" % besiegers)
	if stranded != null:
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		player.global_position = stranded.global_position + Vector2(0, 16)
		await _physics(2)
		stranded.interact(player)
		await _choose(0)
		await _close_dialogue()
		await _idle(2)
		_check(QuestLog.state_of(job) == QuestLog.State.ACTIVE and stranded.following,
				"taking the job is a quest in the journal, and they follow you")
		player.global_position += Vector2(40, 0)
		await _physics(30)
		_check(stranded.position.distance_to(player.position) < 30.0,
				"they keep up, a few steps behind")
		var monster := _spawn_monster(map, stranded.global_position)
		await _physics(1)
		_check(monster.call(&"_touching_escort", player), "a monster that reaches them has caught them")
		for _i in 30:
			if CombatManager.is_running():
				break
			await _physics()
		_check(CombatManager.is_running(), "and the fight is yours")
		await _flee_battle()
		await _idle(4)
		await _close_dialogue()
		if is_instance_valid(monster):
			monster.queue_free()
		_check(stranded.following, "a fight fled, they are still with you")
		var plot: Rect2i = map.get_meta(&"camp")
		var walls := map.get_node("Walls") as TileMapLayer
		player.global_position = walls.map_to_local(plot.get_center())
		await _physics(4)
		for _i in 60:
			if DialogueRunner.is_running():
				break
			await _physics()
		await _close_dialogue()
		await _idle(2)
		_check(QuestLog.state_of(job) == QuestLog.State.COMPLETED
				and Inventory.count(FloorEvents._cast(2)["escort_gear"]) > 0,
				"walked into the camp, they say their thanks and the job pays out")
		map = await _event_floor(world_root, 2)
		_check(map.get_node_or_null("Stranded") == null, "and they've gone down to town by the next visit")

	# Player killers: paid off once, fought once.
	FloorGenerator.event_override = FloorEvents.Kind.AMBUSH
	for paying in [true, false]:
		GameState.set_flag(FloorEvents.flag(2, "ambush"), false)
		GameState.set_flag(FloorEvents.flag(2, "ambush_paid"), false)
		EventBus.col_granted.emit(FloorEvents.toll(2))
		map = await _event_floor(world_root, 2)
		player = map.get_node("Player") as Player
		var ambush := map.get_node_or_null("Ambush") as Ambush
		_check(ambush != null, "player killers hide on the floor")
		if ambush == null:
			break
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		await _physics(1)
		var purse := GameState.col()
		_field = null
		player.global_position = Vector2(ambush.area.get_center() * FloorEvents.TILE) + Vector2(8, 8)
		for _i in 30:
			if DialogueRunner.is_running():
				break
			await _physics()
		var figures := map.get_children().filter(func(node: Node) -> bool: return node is FoeFigure).size()
		_check(ambush.is_spent() and DialogueRunner.is_running() and figures == 2,
				"walking into their room, two of them step out of hiding round you")
		await _choose(0 if paying else 1)
		if paying:
			await _close_dialogue()
			await _idle(2)
			_check(GameState.col() == purse - FloorEvents.toll(2)
					and GameState.has_flag(FloorEvents.flag(2, "ambush"))
					and not map.get_children().any(func(node: Node) -> bool: return node is FoeFigure),
					"paying their toll costs it, and they're gone for good")
		else:
			await _auto_battle()
			await _idle(4)
			_check(_staged_figures == 2 and GameState.has_flag(FloorEvents.flag(2, "ambush")),
					"drawing your sword is a fight with the pair of them on the map, and beating them ends it")
			await _close_dialogue()
	map = await _event_floor(world_root, 2)
	_check(map.get_node_or_null("Ambush") == null, "and nobody lies in wait once they're dealt with")

	# A duel: turned down hurt, lost fair, won on the rematch -- and one rigged.
	FloorGenerator.event_override = FloorEvents.Kind.DUEL
	FloorEvents.rigged_override = 0
	map = await _event_floor(world_root, 2)
	player = map.get_node("Player") as Player
	var duellist := map.get_node_or_null("Duellist") as Duellist
	_check(duellist != null and duellist.visible, "a duellist waits in the camp")
	if duellist != null:
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		var stake := FloorEvents.stake(2)
		var wager: StringName = FloorEvents.duellist(2)["wager"]
		player.global_position = duellist.global_position + Vector2(0, 16)
		player.facing = Vector2.UP
		await _physics(2)
		EventBus.col_granted.emit(stake * 3)
		var purse := GameState.col()
		GameState.set_hp(GameState.total_max_hp() / 4)
		duellist.interact(player)
		await _choose(0)
		await _close_dialogue()
		await _idle(2)
		await _close_dialogue()
		_check(GameState.col() == purse and not CombatManager.is_running(),
				"half-dead, they won't take your col or your duel")

		# Lost: no sword and no guard to speak of, so the duellist takes you to half.
		# Unpaced -- a duel lost at attack 1 is a long one.
		var pace := CombatManager.step_delay
		var guard := GameState.defense
		CombatManager.step_delay = 0.0
		var dropped := GameState.dropped_col()
		GameState.set_hp(GameState.total_max_hp())
		GameState.attack = 1
		GameState.defense = 0
		_field = null
		_staged_figures = -1
		duellist.interact(player)
		await _choose(0)
		await _auto_battle()
		_check(_staged_figures == 1 and duellist.visible,
				"accepting stakes out a duel on the map, the duellist stepping up to it")
		_check(GameState.col() == purse - stake and GameState.hp >= 1
				and GameState.hp <= GameState.total_max_hp() / 2 + 1
				and GameState.dropped_col() == dropped
				and not GameState.has_flag(FloorEvents.flag(2, "duel")),
				"losing a duel costs the stake and half your HP, and nothing else")

		# Won: the wager, and the stake back.
		GameState.defense = guard
		GameState.attack = strength + 400
		GameState.set_hp(GameState.total_max_hp())
		var wagers := Inventory.count(wager)
		var xp := GameState.xp
		purse = GameState.col()
		duellist.interact(player)
		await _choose(0)
		await _auto_battle()
		_check(GameState.col() == purse and Inventory.count(wager) == wagers + 1
				and GameState.xp == xp and GameState.has_flag(FloorEvents.flag(2, "duel"))
				and is_instance_valid(duellist) and duellist.visible,
				"winning it pays the wager and your stake back, and no XP")
		CombatManager.step_delay = pace
		map = await _event_floor(world_root, 2)
		duellist = map.get_node_or_null("Duellist") as Duellist
		_check(duellist != null and duellist.dialogue.lines[0].text.begins_with("Good duel"),
				"beaten fair, they stay in the camp and say so")

	# Rigged: decided, they turn on you; beaten, they're gone for good.
	FloorEvents.rigged_override = 1
	GameState.set_flag(FloorEvents.flag(2, "duel"), false)
	map = await _event_floor(world_root, 2)
	player = map.get_node("Player") as Player
	duellist = map.get_node_or_null("Duellist") as Duellist
	if duellist != null:
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		player.global_position = duellist.global_position + Vector2(0, 16)
		player.facing = Vector2.UP
		await _physics(2)
		EventBus.col_granted.emit(FloorEvents.stake(2))
		GameState.set_hp(GameState.total_max_hp())
		var xp := GameState.xp
		_betrayals = 0
		CombatManager.action_resolved.connect(_count_betrayal)
		duellist.interact(player)
		await _choose(0)
		await _auto_battle()
		CombatManager.action_resolved.disconnect(_count_betrayal)
		_check(_betrayals == 1 and GameState.xp > xp and GameState.has_flag(FloorEvents.flag(2, "duel"))
				and not is_instance_valid(duellist),
				"a rigged duel ends in a refusal and a real fight, and the duellist is gone after")
	map = await _event_floor(world_root, 2)
	_check(map.get_node_or_null("Duellist") == null, "an orange duellist doesn't come back to the camp")
	FloorEvents.rigged_override = -1
	FloorGenerator.event_override = -1
	GameState.attack = strength


func _count_betrayal(report: CombatReport) -> void:
	if report.kind == CombatReport.Kind.YIELD and not report.success:
		_betrayals += 1


## Floor [param floor_number] entered for an event, once the arrival is over --
## and whatever it says as you arrive read.
func _event_floor(world_root: Node2D, floor_number: int) -> GameMap:
	await SceneRouter.enter_floor(floor_number, &"default")
	for _i in 600:
		await _idle()
		if DialogueRunner.is_running():
			DialogueRunner.advance()
		elif not GameState.is_input_locked():
			break
	return world_root.get_child(0) as GameMap


## Presses through the conversation on screen to its first choice and takes
## [param index].
func _choose(index: int, timeout_frames := 300) -> void:
	for _i in timeout_frames:
		if DialogueRunner.is_choosing():
			DialogueRunner.choose(index)
			await _idle(2)
			return
		if DialogueRunner.is_running():
			DialogueRunner.advance()
		await _idle()
	_check(false, "timed out waiting for a choice")


## Opens a sealed chest and says whether it paid out -- its item into the bag
## and, if it hides one, its sigil.
func _open_sealed(chest: Chest, player: Player, with_sigil := true) -> bool:
	var before := Inventory.count(chest.item_id)
	chest.interact(player)
	var paid := Inventory.count(chest.item_id) == before + 1
	return paid and chest.sealed and (not with_sigil or GameState.has_flag(chest.sigil_flag))


func _trapped_chest(map: Node2D, walls: TileMapLayer, cell: Vector2i, trap: Chest.Trap,
		flag: StringName) -> Chest:
	var chest := (load("res://scenes/world/chest.tscn") as PackedScene).instantiate() as Chest
	chest.gilded = true
	chest.trap = trap
	chest.item_id = &"small_potion"
	chest.opened_flag = flag
	chest.floor_number = 2
	chest.position = walls.map_to_local(cell)
	map.add_child(chest)
	return chest


func _ring_of(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		cells.append(Vector2i(x, rect.position.y))
		cells.append(Vector2i(x, rect.end.y - 1))
	for y in range(rect.position.y + 1, rect.end.y - 1):
		cells.append(Vector2i(rect.position.x, y))
		cells.append(Vector2i(rect.end.x - 1, y))
	return cells


## Monsters that move, on a real generated floor with real walls: noticing needs
## line of sight, nothing happens through the input lock, contact starts the fight,
## a fight it survives leaves you room to leave, and pressing E first wins round 1.
##
## The floor is random per run, so the wall is painted here rather than hunted for:
## a five-tall column through the middle of an open block, the player on one side
## and the monster on the other, well inside [constant Monster.AGGRO_RADIUS].
func _test_roaming(map: Node2D, player: Player) -> void:
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)

	var walls: TileMapLayer = map.get_node("Walls")
	var block := _open_block(walls, Vector2i(5, 5))
	_check(block.size != Vector2i.ZERO, "floor 2 has a 5x5 open block to test monsters in")
	if block.size == Vector2i.ZERO:
		return
	var wall_cells: Array[Vector2i] = []
	for y in 5:
		wall_cells.append(block.position + Vector2i(2, y))
	var any_wall := walls.get_used_cells()[0]
	for cell in wall_cells:
		walls.set_cell(cell, walls.get_cell_source_id(any_wall), walls.get_cell_atlas_coords(any_wall))

	player.global_position = walls.map_to_local(block.position + Vector2i(0, 2))
	player.facing = Vector2.LEFT  # away from where the monster will be
	# A painted tile gets its collision on a later frame, and a monster looks on
	# its first one -- let the wall exist before anything tries to see through it.
	await _physics(3)
	var monster_at := walls.map_to_local(block.position + Vector2i(4, 2))
	var ray := PhysicsRayQueryParameters2D.create(
			monster_at + Monster.FOOT, player.global_position + Monster.FOOT, 1)
	_check(not map.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),
			"the painted wall blocks a line of sight across it")
	var monster := _spawn_monster(map, monster_at)
	await _physics(60)
	_check(monster.state != Monster.State.CHASE and not CombatManager.is_running(),
			"a monster does not notice the player through a wall")

	for cell in wall_cells:
		walls.erase_cell(cell)
	GameState.push_input_lock()
	var held_at := monster.global_position
	await _physics(30)
	_check(monster.state != Monster.State.CHASE and monster.global_position == held_at \
			and not CombatManager.is_running(),
			"with the input lock held it neither moves, notices nor engages")
	GameState.pop_input_lock()

	var chased := false
	for _i in 240:
		await _physics()
		if CombatManager.is_running():
			break
		chased = chased or monster.state == Monster.State.CHASE
	_check(chased, "with the wall gone it notices the player and gives chase")
	_check(CombatManager.is_running(), "reaching the player starts the fight -- no keypress")
	_check(CombatManager.is_running() \
			and CombatManager.current_encounter().opening == Encounter.Opening.ENEMIES_FIRST,
			"catching the player facing away gives it the first round")

	await _flee_battle()
	await _close_dialogue()
	_check(is_instance_valid(monster) and monster.state == Monster.State.STUNNED,
			"a monster that survives the fight is stunned afterwards")
	_check(not monster.is_available(), "and cannot be picked a fight with while it is")
	await _physics(90)
	_check(not CombatManager.is_running(),
			"the grace period stops it re-engaging the player standing on it")
	monster.queue_free()

	var sleeper := _spawn_monster(map, player.global_position + Vector2(20, 0))
	sleeper.interact(player)
	_check(CombatManager.is_running() \
			and CombatManager.current_encounter().opening == Encounter.Opening.PARTY_FIRST,
			"pressing E on a monster that has not noticed you wins the first round")
	await _auto_battle()
	_check(not is_instance_valid(sleeper) or sleeper.is_queued_for_deletion(),
			"and a pressed fight still ends the way it always did")

	# The result stays on screen for a beat after a fight. A second fight started
	# inside that beat must not be hidden when it runs out: the manager would sit
	# waiting on a command from a menu nobody can see, holding the input lock.
	var hud: BattleHud = find_child("BattleHud", true, false)
	var second := _spawn_monster(map, player.global_position + Vector2(20, 0))
	second.interact(player)
	await get_tree().create_timer(BattleHud.OUTRO_TIME + 0.4).timeout
	_check(CombatManager.is_running() and hud.visible,
			"a fight started during the last one's outro keeps its menu")
	await _auto_battle()


## Tomas's counter on the plaza, through the real screen: talking to him opens
## it, E buys the top of the shelf, left/right turns it to selling, Esc closes it.
func _test_shop(main: Node, town: Node2D, player: Node2D) -> void:
	var screen := main.get_node("ShopScreen")
	var tomas := town.get_node_or_null("Tomas") as Npc
	_check(tomas != null and tomas.shop != null, "the town has an outfitter keeping a shop")
	if tomas == null or tomas.shop == null:
		return
	EventBus.col_granted.emit(100)
	var col := GameState.col()
	var potions := Inventory.count(&"small_potion")
	tomas.interact(player)
	await _idle()
	_check(screen.is_open() and GameState.is_input_locked(),
			"talking to him opens the counter and holds the lock")
	var first: Item = screen.selected_item()
	_check(first != null and first.id == &"small_potion", "starting on the top of the shelf")
	await _tap(&"interact")
	_check(Inventory.count(&"small_potion") == potions + 1 and GameState.col() == col - first.price,
			"E buys one for its price (%d col left)" % GameState.col())
	await _tap(&"move_right")
	_check(screen.mode() == 1 and screen.selected_item() != null, "right turns the counter to selling")
	var selling: Item = screen.selected_item()
	var before := GameState.col()
	await _tap(&"interact")
	_check(GameState.col() == before + selling.sell_price(),
			"and E sells one back for half (%s)" % selling.label())
	await _tap(&"ui_cancel")
	_check(not screen.is_open() and not GameState.is_input_locked(),
			"Esc closes the counter and lets go of the lock")


## Nezha's forge, through his real conversation and the real screen: "Work on my
## gear." closes the box and opens the forge, a mashed E straight after is
## swallowed, a deliberate one works the sword, and Esc leaves.
func _test_forge(main: Node, town: Node2D, player: Node2D) -> void:
	var screen := main.get_node("ForgeScreen")
	var nezha := town.get_node_or_null("Nezha") as Npc
	_check(nezha != null and nezha.dialogue != null, "the town has a smith to talk to")
	if nezha == null:
		return
	var sword := ItemLibrary.get_item(&"bronze_sword")
	Inventory.add(sword, 1)
	Inventory.equip(sword)
	Inventory.add_id(&"boar_hide", 2)
	EventBus.col_granted.emit(200)
	nezha.interact(player)
	var asked := false
	for _i in 600:
		if not DialogueRunner.is_running():
			break
		if DialogueRunner.is_choosing():
			var offered := DialogueRunner.offered_choices()
			var pick := offered.size() - 1
			for i in offered.size():
				if offered[i].text == "Work on my gear.":
					pick = i
					asked = true
			DialogueRunner.choose(pick)
		else:
			DialogueRunner.advance()
		await _idle()
	_check(asked, "his menu offers to work on your gear")
	for _i in 30:
		if screen.is_open():
			break
		await _idle()
	_check(screen.is_open() and GameState.is_input_locked() and not DialogueRunner.is_running(),
			"and the forge opens once the box has closed")
	var worn: ItemStack = screen.selected()
	_check(worn != null and worn == Inventory.worn(&"weapon"), "starting on the sword in your hand")
	var col := GameState.col()
	await _tap(&"interact")
	_check(worn.plus == 0 and GameState.col() == col, "an E mashed through the last line is swallowed")
	await get_tree().create_timer(Player.INTERACT_GRACE + 0.05).timeout
	var attack := GameState.total_attack()
	await _tap(&"interact")
	_check(worn.plus == 1 and GameState.col() < col and GameState.total_attack() > attack,
			"a deliberate E works it: +1, and the attack shows (%d -> %d)" % [attack,
			GameState.total_attack()])
	await _tap(&"ui_cancel")
	_check(not screen.is_open() and not GameState.is_input_locked(),
			"Esc leaves the forge and lets go of the lock")
	Inventory.unequip(&"weapon")
	Inventory.remove(&"bronze_sword", 1)


## Losing a real fight on a real floor: the purse spills where you fell, a pouch
## lies there and the map says so, and walking back to it gets it all back.
func _test_fallen_purse(main: Node, map: GameMap, player: Player) -> void:
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _physics(2)
	GameState.reset_col()
	EventBus.col_granted.emit(250)
	var attack := GameState.attack
	GameState.attack = 1
	GameState.set_hp(1)
	var brute := _spawn_monster(map, player.global_position + Vector2(20, 0))
	brute.level = 60
	brute._engage(Encounter.Opening.ENEMIES_FIRST)
	await _auto_battle()
	GameState.attack = attack
	# Where the fight stood them, which is where they fell.
	var fell_at := map.to_local(player.global_position)
	_check(GameState.col() == 0 and GameState.dropped_col().get("amount", 0) == 250
			and GameState.dropped_col().get("map") == map.map_id,
			"losing a fight spills the whole purse on the map you lost on")
	await _close_dialogue()
	var pouch := map.get_node_or_null("DroppedCol") as DroppedCol
	_check(pouch != null and pouch.position.is_equal_approx(fell_at),
			"and a pouch of it lies where you fell")
	_check(MapPage.status_line(map).contains("250 col dropped"),
			"the map says where it is")
	if pouch != null:
		pouch.interact(player)
		await _close_dialogue()
		await _idle(2)
	_check(GameState.col() == 250 and GameState.dropped_col().is_empty()
			and not is_instance_valid(pouch), "walking back to it picks it all up")
	if is_instance_valid(brute):
		brute.queue_free()
	GameState.heal_to_full()
	# The box just closed, and interaction stays deaf for a beat after one does.
	await get_tree().create_timer(Player.INTERACT_GRACE + 0.1).timeout


func _spawn_monster(map: Node2D, at: Vector2) -> Monster:
	var monster := (load("res://scenes/world/monster.tscn") as PackedScene).instantiate() as Monster
	monster.enemy = Bestiary.pool_for_floor(2)[0]
	monster.level = 1
	monster.floor_number = 2
	monster.position = at
	map.add_child(monster)
	return monster


## The first rect of [param size] with no wall in it -- preferring one with no
## wall round it either, but a generated floor 2 is random per run and some have
## no room that big, so a block walled in on its sides will do: the painted
## column only has to stand between the two of them.
func _open_block(walls: TileMapLayer, size: Vector2i) -> Rect2i:
	for ring in [1, 0]:
		var block := _open_block_within(walls, size, ring)
		if block.size != Vector2i.ZERO:
			return block
	return Rect2i()


func _open_block_within(walls: TileMapLayer, size: Vector2i, ring: int) -> Rect2i:
	var used := walls.get_used_rect()
	for y in range(used.position.y + 1, used.end.y - size.y - 1):
		for x in range(used.position.x + 1, used.end.x - size.x - 1):
			var clear := true
			for dy in range(-ring, size.y + ring):
				for dx in range(-ring, size.x + ring):
					if walls.get_cell_source_id(Vector2i(x + dx, y + dy)) != -1:
						clear = false
						break
				if not clear:
					break
			if clear:
				return Rect2i(Vector2i(x, y), size)
	return Rect2i()


## Runs from whatever fight is on until it ends some way other than a win.
func _flee_battle(timeout_frames := 6000) -> void:
	for _i in timeout_frames:
		if not CombatManager.is_running():
			return
		if CombatManager.is_awaiting_command():
			if not CombatManager.submit(CombatAction.flee()):
				CombatManager.submit(CombatAction.defend())
		await _idle()
	_check(false, "timed out fleeing the battle")


# --- helpers ---------------------------------------------------------------

func _spy_target(target: Node) -> void:
	_last_target = target


func _spy_line(speaker: String, _text: String, _portrait: Texture2D) -> void:
	_last_speaker = speaker


func _spy_text(_speaker: String, text: String, _portrait: Texture2D) -> void:
	_line_spy.append(text)


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


## A real press and release, so screens listening in _unhandled_input see it --
## Input.action_press() sets state but synthesises no event.
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


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _physics(frames)
	Input.action_release(action)
	await _physics(1)


## Presses through whatever is on screen. At a choice it takes the last option,
## which is the "leave" branch by convention in this project's dialogue.
func _close_dialogue(timeout_frames := 600) -> void:
	for _i in timeout_frames:
		if not DialogueRunner.is_running():
			return
		if DialogueRunner.is_choosing():
			DialogueRunner.choose(DialogueRunner.offered_choices().size() - 1)
		else:
			DialogueRunner.advance()
		await _idle()
	_check(false, "timed out closing the dialogue")


## Presses through a fight the way a player would: clear whatever dialogue is in
## the way, then attack until it is over. Attack is always legal, so this can
## never park the turn loop waiting for a command it refused.
func _on_battle_staged(field: BattleField) -> void:
	_field = field
	_staged_figures = field.enemy_nodes.filter(func(node: Node2D) -> bool: return node is FoeFigure).size()


func _on_command_requested(_actor: Combatant) -> void:
	_fight_camera = get_viewport().get_camera_2d()


## The fight just over was fought on the map and handed it back: a field was
## announced, every spot on it is floor, the fight was watched through the
## stage's camera and the player's is current again, and the player is left on
## the spot the formation gave them, in a place their body fits, free to move.
## What the old battle screen's visibility used to stand in for.
func _check_staging(map: GameMap, player: Player, what: String) -> void:
	var field := _field
	_check(field != null and field.map == map, "%s is staged on the map" % what)
	if field == null:
		return
	var walls := map.get_node("Walls") as TileMapLayer
	var cells: Array[Vector2i] = [field.player_cell]
	cells.append_array(field.enemy_cells)
	_check(cells.all(func(cell: Vector2i) -> bool: return walls.get_cell_source_id(cell) == -1),
			"every spot of %s is floor" % what)
	var own := player.get_node("Camera2D") as Camera2D
	_check(_fight_camera != null and _fight_camera != own,
			"%s is watched through the stage's camera" % what)
	# The camera eases home after the lock is off: the player may already walk.
	for _i in 120:
		if get_viewport().get_camera_2d() == own:
			break
		await _idle()
	_check(get_viewport().get_camera_2d() == own, "and the player's camera is current again after")
	_check(player.position.is_equal_approx(field.player_spot),
			"the player is left on the spot %s gave them (%s, not %s)" % [what, player.position, field.player_spot])
	await _physics()
	var body := player.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.transform = body.global_transform
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	_check(player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(),
			"and their body fits where they stand")
	_check(not GameState.is_input_locked(), "the lock is off once %s is over" % what)


func _auto_battle(timeout_frames := 4000) -> void:
	for _i in timeout_frames:
		if CombatManager.is_running():
			if CombatManager.is_awaiting_command():
				var enemies := CombatManager.living_enemies()
				if not enemies.is_empty():
					CombatManager.submit(CombatAction.use(
							SkillLibrary.basic_attack(), enemies[0]))
		elif DialogueRunner.is_running():
			DialogueRunner.advance()
		elif not GameState.is_input_locked():
			return
		await _idle()
	_check(false, "timed out waiting for the battle to finish")


func _until_unlocked(timeout_frames := 600) -> void:
	# The router locks input across the fade; wait for it to hand control back.
	for _i in timeout_frames:
		await get_tree().process_frame
		if not GameState.is_input_locked():
			return
	_check(false, "timed out waiting for input to unlock")
