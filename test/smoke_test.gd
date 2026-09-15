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
	_check(main.get_node_or_null("QuestJournal") != null, "and a quest journal")
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
	await _close_dialogue()

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
	monster.interact(field_player)
	await _auto_battle()
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
	gate.interact(field_player)
	await _auto_battle()
	_check(GameState.is_floor_cleared(1), "beating the boss clears the floor")
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

	await _test_roaming(floor_two, floor_two_player as Player)


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
	var screen: CanvasLayer = find_child("CombatScreen", true, false)
	var second := _spawn_monster(map, player.global_position + Vector2(20, 0))
	second.interact(player)
	await get_tree().create_timer(screen.OUTRO_TIME + 0.4).timeout
	_check(CombatManager.is_running() and screen.visible,
			"a fight started during the last one's outro keeps its screen")
	await _auto_battle()


func _spawn_monster(map: Node2D, at: Vector2) -> Monster:
	var monster := (load("res://scenes/world/monster.tscn") as PackedScene).instantiate() as Monster
	monster.enemy = Bestiary.pool_for_floor(2)[0]
	monster.level = 1
	monster.floor_number = 2
	monster.position = at
	map.add_child(monster)
	return monster


## The first rect of [param size] with no wall in it or round it.
func _open_block(walls: TileMapLayer, size: Vector2i) -> Rect2i:
	var used := walls.get_used_rect()
	for y in range(used.position.y + 1, used.end.y - size.y - 1):
		for x in range(used.position.x + 1, used.end.x - size.x - 1):
			var clear := true
			for dy in range(-1, size.y + 1):
				for dx in range(-1, size.x + 1):
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
