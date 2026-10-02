extends Node
## Boots the game, captures a few frames to user:// and exits.
##
##     "$GODOT" --path . res://tools/screenshot.tscn
##
## Dev aid for checking how a change actually looks without sitting through the
## game. Needs a real window, so it can't run with --headless.

const SHOTS := "user://screenshots"
## The meadow floor the monster fights are shot on. Not 2, whose labyrinth is
## shot later and should not have been walked into first.
const FIGHT_FLOOR := 3
## [floor, the map to fight on (empty: the floor's own), a name for the shots]
const BOSS_FIGHTS := [
	[1, "res://scenes/world/field.tscn", "illfang"],
	[10, "", "nerith"],
	[25, "", "karvos"],
	[52, "", "f52_escort"],
]
## A generated floor in each biome band, clear of the ones shot elsewhere.
const BAND_FLOORS := [5, 15, 27, 35, 45, 55, 65, 75, 85, 97]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	while GameState.is_input_locked():
		await get_tree().process_frame
	await _frames(2)
	await _capture("01_town")

	var town: Node2D = main.get_node("WorldRoot").get_child(0)
	var player: Node2D = town.get_node("Player")
	var argo: Node2D = town.get_node("Argo")

	player.global_position = argo.global_position + Vector2(0, 20)
	player.set(&"facing", Vector2.UP)
	await _frames(6)
	await _capture("02_prompt")

	argo.interact(player)
	await _typed(main)
	await _capture("03_dialogue")

	# Press on until Argo asks what you want -- that is the choice menu.
	for _i in 20:
		if DialogueRunner.is_choosing():
			break
		DialogueRunner.advance()
		await _typed(main)
	# The box holds the menu back until the question has finished typing, so the
	# wait above is what puts the choices on screen as well as the line.
	await _frames(4)
	await _capture("04_choices")

	await _capture_quests(main)
	await _capture_inventory(main)
	await _capture_combat()

	await _capture_world(main)

	# One floor per biome band worth showing off, and the authored ones past the
	# first -- 24 and 25 side by side are the same band generated and built.
	# The labyrinth in three of the ways a wall can be drawn: trees, cliffs, masonry.
	# Before the floor shots, which clear every floor below 100 -- and a cleared
	# floor's door is no longer hidden.
	for floor_number in [2, 24, 95]:
		await _capture_labyrinth(main, floor_number)

	for floor_number in [2, 10, 15, 24, 25, 37, 45, 55, 65, 75, 87, 100]:
		await _capture_floor(floor_number)

	print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


## The two quest surfaces: the corner tracker, and the journal.
##
## Argo's errand is taken through her real choice menu rather than by calling
## QuestLog, because the thing worth looking at is what a player sees after the
## conversation they actually had. Everything after that is set up by hand -- a
## screenshot pass is not a playthrough.
func _capture_quests(main: Node) -> void:
	var work := _choice_index("Got any work")
	if work >= 0:
		DialogueRunner.choose(work)
		await _typed(main)
		for _i in 10:
			if DialogueRunner.is_choosing() or not DialogueRunner.is_running():
				break
			DialogueRunner.advance()
			await _typed(main)
	DialogueRunner.cancel()

	# The tracker is suppressed while the box is up, so the "new quest" notice
	# only starts its clock here -- which is the frame worth catching.
	await _frames(10)
	await _capture("04f_quest_tracker")

	EventBus.enemy_defeated.emit(&"frenzy_boar")
	await _frames(6)
	await _capture("04g_quest_tracker_progress")

	# One of each state for the journal: a live quest, one waiting to be handed
	# in, and one finished.
	for _i in 2:
		EventBus.enemy_defeated.emit(&"frenzy_boar")
	EventBus.dialogue_finished.emit(&"nezha")
	QuestLog.turn_in(&"argo_first_errand")
	GameState.level = maxi(GameState.level, 2)
	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.start(&"nezha_first_blade")
	QuestLog.start(&"argo_illfang")

	await _press(&"journal")
	await _frames(6)
	await _capture("04h_journal")
	await _press(&"move_down")
	await _capture("04i_journal_selected")
	await _press(&"journal")
	await _frames(4)


## Waits for the typewriter to land rather than counting frames: a capture on a
## frame budget shows however much of the line the machine got through, which is
## two letters of it on a slow run and the whole thing on a fast one.
func _typed(main: Node, seconds := 15.0) -> void:
	var text: Label = main.get_node("DialogueBox/Box/Row/Text")
	await _until(func() -> bool: return not DialogueRunner.is_running() \
			or text.visible_ratio >= 1.0, seconds)
	await _frames(2)


func _choice_index(prefix: String) -> int:
	var choices := DialogueRunner.offered_choices()
	for i in choices.size():
		if choices[i].text.begins_with(prefix) and choices[i].is_unlocked():
			return i
	return -1


## The bag, with enough in it to show rarity colours, a full stack and both
## panels. Stocked by hand -- playing far enough to loot this much is not what
## a screenshot pass is for.
func _capture_inventory(main: Node) -> void:
	Inventory.add_id(&"small_potion", 4)
	for id in [&"health_potion", &"antidote", &"whetstone", &"boar_hide",
			&"wolf_fang", &"nepent_ovule", &"map_floor_2", &"anneal_blade",
			&"blackwyrm_coat", &"swift_charm", &"bronze_sword"]:
		Inventory.add_id(id, 1)
	Inventory.equip(ItemLibrary.get_item(&"anneal_blade"))
	Inventory.equip(ItemLibrary.get_item(&"swift_charm"))
	Inventory.sort()

	await _press(&"inventory")
	await _frames(4)
	await _capture("04b_inventory")

	# Up out of the grid puts the cursor on the equipment list instead.
	await _press(&"move_up")
	await _capture("04c_inventory_gear")

	# A sword carried from the grid to the weapon slot: the whole point of the
	# mouse path, and the state worth looking at is halfway there, with the
	# targets it may land on lit up.
	var screen: CanvasLayer = main.get_node("InventoryScreen")
	var slot: Control = screen.get_node("Bag/Column/Grid").get_child(0)
	var weapon_row: Control = screen.get_node("Gear/Rows/Weapon")
	await _drag(slot, weapon_row, "04d_inventory_drag")
	await _capture("04e_inventory_dropped")

	await _press(&"inventory")
	await _frames(4)


## Fights on the map, caught at the moments worth looking at. Every fight is
## staged where it happens, so the places are the point: a room, a field
## corridor, a passage in the labyrinth's dark, a boss stepping out of each kind
## of door, and one monster fight per biome band.
##
## The player is armoured out of reach throughout -- one who dies before the
## menu is asked for leaves nothing to capture and a fight [method _end_fight]
## cannot end -- and carries a blade blunt enough that a fight lasts as long as
## its shots need. Level 30 puts every skill in the menu. Defence rather than
## HP, so the bar in the shots still reads like a real one.
func _capture_combat() -> void:
	var stats := [GameState.level, GameState.attack, GameState.defense]
	GameState.level = 30
	GameState.attack = 2
	GameState.defense = 100000
	GameState.set_hp(GameState.total_max_hp())

	await _capture_monster_fights()
	# Getting to Floor 3 cleared Floor 1, and a cleared door offers the way up.
	_forget_the_climb()
	await _capture_boss_fights()
	await _capture_band_fights()

	_forget_the_climb()
	GameState.level = stats[0]
	GameState.attack = stats[1]
	GameState.defense = stats[2]
	GameState.set_hp(GameState.total_max_hp())


## Trash on a meadow floor: one fight taken through the menus in a room, one in
## a field corridor, one in a labyrinth passage -- walked to, so the dark has lit
## the way there -- and one that catches you, for the alarm, its claw, a sword
## skill's effect, the status bubbles and a heal.
func _capture_monster_fights() -> void:
	var map := await _enter(FIGHT_FLOOR)
	var walls := map.get_node("Walls") as TileMapLayer
	var lab: Rect2i = map.get_meta(&"labyrinth")
	var player := map.get_node("Player") as Player
	var monsters := _monsters_on(map)
	if monsters.size() < 4:
		push_warning("screenshot: floor %d has %d monsters, not enough to fight" % [
				FIGHT_FLOOR, monsters.size()])
		return
	var room := _room_cell(map, walls, lab, player.position)
	var corridor := _corridor_cell(map, walls, lab)

	await _start_fight(player, monsters.pop_back(), walls, room[0], room[1])
	await _until_command()
	await _capture("05_combat_menu")
	# Second row down is Sword Skills. Fed as real events rather than through
	# Input.action_press, which sets the action state without ever reaching
	# _unhandled_input -- the menu would never see the keypress.
	await _press(&"move_down")
	await _press(&"interact")
	await _capture("06_combat_skills")
	# Back out and two rows further down is Item -- stocked by the inventory
	# capture before this, so there is something on the list.
	await _press(&"ui_cancel")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _capture("06b_combat_items")
	await _press(&"ui_cancel")
	# Caught at the far end of the step, then as the blow lands.
	_submit(CombatAction.use(SkillLibrary.get_skill(&"slant"), CombatManager.living_enemies()[0]))
	await _wait(0.14)
	await _capture("07a_combat_strike")
	await _wait(0.3)
	await _capture("07_combat_hit")
	await _finish("07b_combat_fall")

	await _start_fight(player, monsters.pop_back(), walls, corridor[0], corridor[1])
	await _until_command()
	await _capture("07c_combat_corridor")
	await _finish()

	var path := _path_within(walls, walls.local_to_map(player.position),
			(map.get_meta(&"boss_room") as Rect2i).position, walls.get_used_rect())
	var mouth: Rect2i = map.get_meta(&"labyrinth_mouth")
	var inside: Array[int] = []
	for i in path.size() - 1:
		if lab.has_point(path[i]) and not mouth.has_point(path[i]):
			inside.append(i)
	if inside.is_empty():
		push_warning("screenshot: no way into floor %d's labyrinth" % FIGHT_FLOOR)
	else:
		var stop := inside[inside.size() / 2]
		GameState.push_input_lock()
		for i in stop + 1:
			player.global_position = walls.map_to_local(path[i])
			await get_tree().physics_frame
		GameState.pop_input_lock()
		await _start_fight(player, monsters.pop_back(), walls, path[stop], path[stop + 1] - path[stop])
		await _until_command()
		await _capture("07d_combat_passage")
		await _finish()

	await _start_fight(player, monsters.pop_back(), walls, room[0], room[1],
			Encounter.Opening.ENEMIES_FIRST)
	# The opening is announced after the runner's pause before round 1, and the
	# blow it costs you lands one step_delay after that.
	await _wait(0.75)
	await _capture("07e_combat_alarm")
	await _wait(0.5)
	await _capture("07f_combat_clawed")
	await _until_command()
	var enemy := CombatManager.living_enemies()[0]
	enemy.apply_status(load("res://resources/statuses/weakened.tres"))
	enemy.apply_status(load("res://resources/statuses/poison.tres"))
	_submit(CombatAction.use(SkillLibrary.get_skill(&"vorpal_strike"), enemy))
	await _wait(0.2)
	await _capture("07g_combat_fx")
	await _until_command()
	await _wait(0.9)
	await _capture("07h_combat_bubbles")
	_submit(CombatAction.use(SkillLibrary.get_skill(&"second_wind"), null))
	await _wait(0.25)
	await _capture("07i_combat_heal")
	await _finish()


## The bosses step out of their doors: every authored one, and a generated boss
## room with an escort, in the dark. In floor order, since each clears every
## floor below it and a cleared door offers the way up instead of a fight.
func _capture_boss_fights() -> void:
	for fight: Array in BOSS_FIGHTS:
		var floor_number: int = fight[0]
		var tag := "08_boss_%s_" % fight[2]
		var map: GameMap
		if (fight[1] as String).is_empty():
			map = await _enter(floor_number)
		else:
			for below in range(1, floor_number):
				GameState.clear_floor(below)
			SceneRouter.change_map(fight[1], &"default")
			map = await _arrived(floor_number, fight[1])
		var walls := map.get_node("Walls") as TileMapLayer
		var gate := map.get_node("BossGate") as BossGate
		var player := map.get_node("Player") as Player
		gate.reveal()
		await _dismiss()
		map.refresh_solids()
		# Challenged from the doorstep: below it if that is floor, else beside it.
		var door := walls.local_to_map(gate.position)
		var stand := door + Vector2i.DOWN * 2
		for offset: Vector2i in [Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
				Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			if map.is_standable(door + offset):
				stand = door + offset
				break
		GameState.push_input_lock()
		player.global_position = walls.map_to_local(stand) + Vector2(0, 4)
		player.facing = Vector2(door - stand).normalized()
		await _wait(0.4)
		GameState.pop_input_lock()

		gate.interact(player)
		await _dismiss()
		await _wait(0.25)
		await _capture(tag + "a_stepout")
		await _until_command()
		await _wait(0.3)
		await _capture(tag + "b_menu")
		var boss := CombatManager.living_enemies()[0]
		if CombatManager.living_enemies().size() > 1:
			# Attack, onto the target list: the pointer over the boss.
			await _press(&"interact")
			await _wait(0.2)
			await _capture(tag + "c_target")
			await _press(&"ui_cancel")
		_submit(CombatAction.use(SkillLibrary.get_skill(&"slant"), boss))
		await _wait(0.4)
		await _capture(tag + "d_hit")
		await _finish(tag + "e_fall")
		await _dismiss()


## One monster fight in a room of each band's generated floor, and the lot on
## one sheet: the art a fight stands on is the floor's, so every band has to be
## looked at.
func _capture_band_fights() -> void:
	var shots := PackedStringArray()
	for floor_number: int in BAND_FLOORS:
		var map := await _enter(floor_number)
		var walls := map.get_node("Walls") as TileMapLayer
		var player := map.get_node("Player") as Player
		var monsters := _monsters_on(map)
		if monsters.is_empty():
			push_warning("screenshot: floor %d has no monsters" % floor_number)
			continue
		var room := _room_cell(map, walls, map.get_meta(&"labyrinth"), player.position)
		await _start_fight(player, monsters[0], walls, room[0], room[1])
		await _until_command()
		await _wait(0.3)
		var shot := "09_band_%d_%s" % [floor_number, FloorRegistry.biome_id(floor_number)]
		await _capture(shot)
		shots.append(shot)
		await _finish()
	_sheet(shots, 3, "09_bands_sheet")


## Clears the way up to [param floor_number], goes there, and waits until it can
## be walked on.
func _enter(floor_number: int) -> GameMap:
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	SceneRouter.enter_floor(floor_number)
	return await _arrived(floor_number)


## The map once it is [param floor_number]'s -- and [param path]'s, for a floor
## of several maps -- with the fade over.
func _arrived(floor_number: int, path := "") -> GameMap:
	await _until(func() -> bool:
		var map := SceneRouter.current_map() as GameMap
		return map != null and map.floor_number == floor_number \
				and (path.is_empty() or map.scene_file_path == path) \
				and not GameState.is_input_locked(), 10.0)
	await _wait(0.3)
	return SceneRouter.current_map() as GameMap


func _monsters_on(map: GameMap) -> Array[Monster]:
	var monsters: Array[Monster] = []
	for child in map.get_children():
		if child is Monster:
			monsters.append(child)
	return monsters


## Stands the player on [param cell] facing [param toward], brings
## [param monster] in from that side, and lets it start the fight -- the way a
## chase ends, or by [param opening] the way an ambush does. Positioned under
## the lock, so nothing else on the map wanders into the fight first.
func _start_fight(player: Player, monster: Monster, walls: TileMapLayer, cell: Vector2i,
		toward: Vector2i, opening := Encounter.Opening.NORMAL) -> void:
	GameState.push_input_lock()
	player.global_position = walls.map_to_local(cell) + Vector2(0, 4)
	player.facing = Vector2(toward)
	monster.global_position = player.global_position + Vector2(toward) * 12.0
	await _wait(0.3)
	GameState.pop_input_lock()
	monster.call(&"_engage", opening)


## Ends the fight on the next command: every escort down, the first enemy
## struck dead -- caught as [param shot], for the puff it goes out in, if
## given. A miss leaves the fight on, and [method _end_fight] finishes it.
func _finish(shot := "") -> void:
	await _until_command()
	var living := CombatManager.living_enemies()
	if not living.is_empty():
		for escort in living.slice(1):
			escort.take_damage(escort.hp)
		living[0].take_damage(living[0].hp - 1)
		_submit(CombatAction.use(SkillLibrary.basic_attack(), living[0]))
		if not shot.is_empty():
			await _wait(0.4)
			await _capture(shot)
	await _until(func() -> bool: return not CombatManager.is_running() \
			or CombatManager.is_awaiting_command(), 10.0)
	if CombatManager.is_running():
		await _end_fight()
	else:
		await _wait(1.3)


## Puts every floor back the way a new climb finds it -- none cleared, no door
## found -- for the boss fights, which need their doors uncleared, and the
## labyrinth shots after the fights, which need them still hidden. A screenshot pass is not a playthrough: this reaches into
## [GameState]'s own record rather than give the game a way to un-clear a floor.
func _forget_the_climb() -> void:
	GameState._cleared_floors.clear()
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		GameState.set_flag(StringName("floor_%d_cleared" % floor_number), false)
		GameState.set_flag(BossGate.found_flag(floor_number), false)


## The middle of an open space in the field: a cell with floor four each way
## across and three up and down -- or, on a floor with no room that big, as much
## as there is. Never the map's centre: that can be rock, and a player set down
## in rock is pushed out somewhere no formation starts from.
func _room_cell(map: GameMap, walls: TileMapLayer, lab: Rect2i, player_at: Vector2) -> Array:
	var used := walls.get_used_rect()
	for reach: Vector2i in [Vector2i(4, 3), Vector2i(3, 2), Vector2i(2, 2)]:
		for y in range(used.position.y + reach.y, used.end.y - reach.y):
			for x in range(used.position.x + reach.x, used.end.x - reach.x):
				var cell := Vector2i(x, y)
				if lab.grow(2).has_point(cell) or Vector2(cell).distance_to(walls.local_to_map(player_at)) < 8.0:
					continue
				var open := true
				for dy in range(-reach.y, reach.y + 1):
					for dx in range(-reach.x, reach.x + 1):
						if not map.is_standable(cell + Vector2i(dx, dy)):
							open = false
				if open:
					return [cell, Vector2i.RIGHT]
	push_warning("screenshot: no open room on this floor")
	return [walls.local_to_map(player_at), Vector2i.RIGHT]


## A cell in the middle of a field corridor: three wide one way, long the other.
func _corridor_cell(map: GameMap, walls: TileMapLayer, lab: Rect2i) -> Array:
	var used := walls.get_used_rect()
	for y in range(used.position.y + 2, used.end.y - 2):
		for x in range(used.position.x + 2, used.end.x - 2):
			var cell := Vector2i(x, y)
			if lab.grow(2).has_point(cell) or not map.is_standable(cell):
				continue
			for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var side := Vector2i(axis.y, axis.x)
				var narrow := _run(map, cell, axis) >= 12
				for along in range(-4, 5):
					narrow = narrow and _run(map, cell + axis * along, side) == 3
				if narrow and map.is_standable(cell + side) and map.is_standable(cell - side):
					return [cell, axis]
	push_warning("screenshot: no field corridor on this floor")
	return _room_cell(map, walls, lab, walls.map_to_local(used.position))


## How many standable cells run through [param cell] along [param axis].
func _run(map: GameMap, cell: Vector2i, axis: Vector2i) -> int:
	var count := 1
	for sign in [1, -1]:
		var at: Vector2i = cell + axis * sign
		while map.is_standable(at) and count < 40:
			count += 1
			at += axis * sign
	return count


## Reads through whatever box is up.
func _dismiss() -> void:
	await _frames(4)
	for _i in 12:
		if not DialogueRunner.is_running():
			return
		await _wait(0.3)
		await _press(&"interact")


## [param shots] on one sheet at half size, [param columns] across, saved as
## [param sheet_name]: for looking at a set side by side.
func _sheet(shots: PackedStringArray, columns: int, sheet_name: String) -> void:
	var cell := Vector2i(640, 360)
	var rows := ceili(shots.size() / float(columns))
	var sheet := Image.create(cell.x * columns, cell.y * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var shot := Image.load_from_file("%s/%s.png" % [SHOTS, shots[i]])
		if shot == null:
			continue
		shot.convert(Image.FORMAT_RGBA8)
		shot.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i((i % columns) * cell.x, (i / columns) * cell.y))
	sheet.save_png("%s/%s.png" % [SHOTS, sheet_name])


## Waits for the fight to ask for a command, then a beat for the menu to lay out.
##
## Bounded in seconds rather than frames, like every wait here that is really
## waiting on time. Combat paces itself on wall-clock timers and the typewriter
## is a tween, but this window is not always vsynced -- run it uncapped and a
## frame budget expires while the first pause is still running, so the capture
## of the command menu is a capture of an empty screen and the submit that
## follows is refused by a runner that never asked for anything.
func _until_command(seconds := 20.0) -> void:
	if await _until(func() -> bool: return CombatManager.is_awaiting_command(), seconds):
		await _frames(4)
	else:
		push_warning("screenshot: no command asked for in %.0fs" % seconds)


## Kills whatever is standing and spends a turn to end the fight, then waits out
## the result the screen leaves up.
func _end_fight() -> void:
	for enemy in CombatManager.living_enemies():
		enemy.take_damage(enemy.hp)
	_submit(CombatAction.use(SkillLibrary.basic_attack(), null))
	if not await _until(func() -> bool: return not CombatManager.is_running(), 20.0):
		push_warning("screenshot: the fight never ended")
	await _wait(1.3)


## Submits, and says so when the runner refuses. A silently refused action used
## to leave the pass spinning on a fight that could no longer end.
func _submit(action: CombatAction) -> void:
	if not CombatManager.submit(action):
		push_warning("screenshot: combat refused a submitted action")


## Polls [param predicate] until it holds or [param seconds] run out; false if
## they ran out.
func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _capture_floor(floor_number: int) -> void:
	# Unlock the way up without playing 99 boss fights.
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	SceneRouter.enter_floor(floor_number)
	while GameState.is_input_locked():
		await get_tree().process_frame
	await _frames(2)
	await _capture("%02d_floor_%d_%s" % [
		floor_number / 20 + 5, floor_number, FloorRegistry.biome_id(floor_number)])


## A generated floor's labyrinth: halfway along the way in, the boss room the
## moment its door shows, and the map screen with the walk there explored.
##
## The walk is a real one -- the shortest path from the spawn to the room, a cell
## at a time, so fog of war records exactly what a player taking it would have seen.
func _capture_labyrinth(main: Node, floor_number: int) -> void:
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	SceneRouter.enter_floor(floor_number)
	await _frames(2)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)
	var map := SceneRouter.current_map() as Node2D
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	var player := map.get_node("Player") as Node2D
	var walls := map.get_node("Walls") as TileMapLayer
	var lab: Rect2i = map.get_meta(&"labyrinth")
	var mouth: Rect2i = map.get_meta(&"labyrinth_mouth")
	var room: Rect2i = map.get_meta(&"boss_room")
	var path := _path_within(walls, walls.local_to_map(player.position), room.position,
			walls.get_used_rect())
	var tag := "%02d_labyrinth_%d" % [floor_number / 20 + 5, floor_number]
	var inside := 0
	for cell in path:
		if lab.has_point(cell):
			inside += 1

	GameState.push_input_lock()
	var in_lab := 0
	for i in path.size() - 1:
		player.global_position = walls.map_to_local(path[i])
		await get_tree().physics_frame
		if lab.has_point(path[i]) and not mouth.has_point(path[i]):
			in_lab += 1
			if in_lab == inside / 2:
				await _wait(0.3)
				await _capture(tag + "a_passage")
	GameState.pop_input_lock()

	player.global_position = walls.map_to_local(room.position + Vector2i(1, room.size.y - 2))
	await _until(func() -> bool: return DialogueRunner.is_running(), 3.0)
	await _typed(main)
	await _capture(tag + "b_found")
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)
	await _wait(0.8)
	await _capture(tag + "c_door")

	await _press(&"map")
	await _frames(4)
	await _capture(tag + "d_map")
	await _press(&"map")


## The shortest walk between two cells, staying inside [param bounds].
func _path_within(walls: TileMapLayer, from: Vector2i, to: Vector2i, bounds: Rect2i) -> Array[Vector2i]:
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and not came.has(to):
		var cell := queue[head]
		head += 1
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if came.has(next) or not bounds.has_point(next) or walls.get_cell_source_id(next) != -1:
				continue
			came[next] = cell
			queue.append(next)
	var path: Array[Vector2i] = []
	if not came.has(to):
		return path
	var cell := to
	while cell != from:
		path.push_front(cell)
		cell = came[cell]
	path.push_front(from)
	return path


## Floor 1 up close: the depth sort, which is only visible with somebody standing
## in the right place -- behind a roof, under a grove's crowns -- and the pieces a
## generated floor never shows, the pond's shoreline and the labyrinth door.
##
## The input lock is held for each shot so the field's monsters stand still rather
## than wandering into frame and starting a fight.
func _capture_world(main: Node) -> void:
	var world: Node = main.get_node("WorldRoot")
	var spots := [
		["res://scenes/world/town.tscn", Vector2(15 * 16 + 8, 9 * 16 + 10), "04j_town_behind_house"],
		["res://scenes/world/field.tscn", Vector2(14 * 16 + 8, 26 * 16 + 8), "04k_field_pond"],
		["res://scenes/world/field.tscn", Vector2(42 * 16, 14 * 16 + 12), "04l_field_under_grove"],
		["res://scenes/world/field.tscn", Vector2(49 * 16 + 8, 35 * 16 + 8), "04m_field_door"],
		["res://scenes/world/floor_10.tscn", Vector2(7 * 16 + 8, 4 * 16 + 10), "04n_ashlow_behind_house"],
		["res://scenes/world/floor_10.tscn", Vector2(15 * 16 + 8, 14 * 16 + 8), "04o_ashlow_square"],
		["res://scenes/world/floor_10.tscn", Vector2(36 * 16 + 8, 31 * 16 + 8), "04p_ashlow_pool"],
		["res://scenes/world/floor_25.tscn", Vector2(11 * 16 + 8, 6 * 16 + 10), "04q_lanternfall_behind_tent"],
		["res://scenes/world/floor_25.tscn", Vector2(17 * 16, 12 * 16 + 8), "04r_lanternfall_square"],
		["res://scenes/world/floor_25.tscn", Vector2(52 * 16 + 8, 8 * 16 + 8), "04s_lanternfall_galleries"],
		["res://scenes/world/floor_25.tscn", Vector2(60 * 16 + 8, 34 * 16 + 8), "04t_lanternfall_lake"],
		["res://scenes/world/floor_25.tscn", Vector2(11 * 16 + 8, 49 * 16 + 8), "04u_lanternfall_breach"],
	]
	for spot: Array in spots:
		var current := world.get_child(0) if world.get_child_count() > 0 else null
		if current == null or current.scene_file_path != spot[0]:
			SceneRouter.change_map(spot[0], &"default")
			await _frames(2)
			while GameState.is_input_locked():
				await get_tree().process_frame
		var player := world.get_child(0).get_node("Player") as Node2D
		GameState.push_input_lock()
		player.global_position = spot[1]
		await _wait(0.5)
		await _capture(spot[2])
		if spot[2] == "04p_ashlow_pool":
			# Rue's wolves, killed: the map should send you back to Rue.
			GameState.clear_floor(9)
			if QuestLog.start(&"ashlow_wolves"):
				for _wolf in 6:
					EventBus.enemy_defeated.emit(&"dire_wolf")
				QuestLog.track(&"ashlow_wolves")
			await _capture_map(main, "04p2_ashlow_map")
		elif spot[2] == "04u_lanternfall_breach":
			await _capture_map(main, "04u2_lanternfall_map")
		GameState.pop_input_lock()
		await _frames(2)


## The map screen over whatever has been explored so far. Opened directly, since
## the caller is holding the input lock that M would wait for.
func _capture_map(main: Node, tag: String) -> void:
	var screen := main.get_node("MapScreen")
	screen.call(&"open")
	await _wait(0.2)
	await _capture(tag)
	screen.call(&"close")
	await _frames(2)


## Taps an action as a real input event, so UI listening in _unhandled_input
## actually sees it.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(4)


## Carries [param source] onto [param target] with real mouse events, capturing
## [param shot_name] while the button is still down.
##
## Synthesised the long way round -- press, a run of motions, release -- because
## Godot's drag system starts from accumulated [member InputEventMouseMotion.
## relative] past the drag threshold, so a single jump to the target would arrive
## having never picked anything up.
func _drag(source: Control, target: Control, shot_name: String) -> void:
	var from := _center(source)
	var to := _center(target)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	Input.parse_input_event(press)
	await _frames(2)

	const STEPS := 8
	var previous := from
	for i in STEPS:
		var point := from.lerp(to, (i + 1) / float(STEPS))
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = point
		motion.global_position = point
		motion.relative = point - previous
		Input.parse_input_event(motion)
		previous = point
		await _frames(2)
	await _capture(shot_name)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	Input.parse_input_event(release)
	await _frames(4)


## A control's middle in window pixels, not in the 320x180 units it is laid out
## in. Input arrives ahead of the stretch transform and is mapped down by it, so
## a position handed straight over lands at a fraction of the intended one -- a
## quarter, in the 4x window.
func _center(control: Control) -> Vector2:
	return get_viewport().get_final_transform() * control.get_global_rect().get_center()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, shot_name])
