extends Node
## Boots the game, captures a few frames to user:// and exits.
##
##     "$GODOT" --path . res://tools/screenshot.tscn
##     "$GODOT" --path . res://tools/screenshot.tscn -- --puzzles   # that pass only
##     "$GODOT" --path . res://tools/screenshot.tscn -- --cracks    # the cracked walls only
##     "$GODOT" --path . res://tools/screenshot.tscn -- --gates     # the teleport gates only
##     "$GODOT" --path . res://tools/screenshot.tscn -- --camps     # the adventurers' camps only
##     "$GODOT" --path . res://tools/screenshot.tscn -- --villages  # the camps settled into villages
##     "$GODOT" --path . res://tools/screenshot.tscn -- --shapes    # open fields: arena, waystones
##     "$GODOT" --path . res://tools/screenshot.tscn -- --dungeons  # dungeons: hall, seals, ladder, top
##     "$GODOT" --path . res://tools/screenshot.tscn -- --modifiers # storms per band, an infested floor
##     "$GODOT" --path . res://tools/screenshot.tscn -- --events    # field boss, escort, ambush, duel
##     "$GODOT" --path . res://tools/screenshot.tscn -- --landmarks # every kind in the bands that draw it
##     "$GODOT" --path . res://tools/screenshot.tscn -- --rooms     # every room shape in every band that draws it
##     "$GODOT" --path . res://tools/screenshot.tscn -- --shops     # the hubs' counters and the purse
##     "$GODOT" --path . res://tools/screenshot.tscn -- --forge     # the smith, Argo's doors, the peddler
##     "$GODOT" --path . res://tools/screenshot.tscn -- --title     # the title screen and its pages
##     "$GODOT" --path . res://tools/screenshot.tscn -- --menu      # the game menu's tabs
##     "$GODOT" --path . res://tools/screenshot.tscn -- --idle      # marathon's idle logout
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
## Floors shot as open fields: the meadow, the cave, the desert, the sky and the castle.
const OPEN_FIELD_FLOORS := [3, 24, 55, 85, 95]
## Floors shot as dungeons: the meadow, the forest, the ruins, the ice and the castle.
const DUNGEON_FLOORS := [4, 16, 33, 64, 96]
## A storm in each weather -- rain on the meadow, the swamp's and the sky's, the
## desert's sand, the ice's snow, the volcanic band's ash -- and an infested floor.
const STORM_FLOORS := [3, 45, 85, 55, 65, 75]
const INFESTED_FLOOR := 14
## A floor for each event: a field boss in the forest and in the ruins, a stranded
## player on the meadow, an ambush in the swamp, a duel on the ice.
const EVENT_FLOORS := {
	FloorEvents.Kind.FIELD_BOSS: [15, 37], FloorEvents.Kind.ESCORT: [5],
	FloorEvents.Kind.AMBUSH: [45], FloorEvents.Kind.DUEL: [65],
}
## The bands each landmark is shot in, by a floor of the band: a lake in every one
## (its liquid changes), a tree wherever one grows, a statue of each stone.
const LANDMARK_FLOORS := {
	FloorLandmarks.Kind.LAKE: [5, 15, 27, 35, 45, 55, 65, 75, 85, 97],
	FloorLandmarks.Kind.GREAT_TREE: [5, 15, 35, 45, 55, 65, 75, 85],
	FloorLandmarks.Kind.MONUMENT: [5, 27, 55, 97],
	FloorLandmarks.Kind.RUIN: [15, 45, 85],
}
## A generated floor in each biome band, clear of the ones shot elsewhere.
const BAND_FLOORS := [5, 15, 27, 35, 45, 55, 65, 75, 85, 97]

## The idle watch's clock in the --idle pass, wound by hand.
var _idle_now := 0.0


## The cracked wall in every way a wall is drawn -- trees, cliffs (green, sandstone,
## the desert's and the volcanic band's), masonry -- as [floor to start looking
## from, whether it should be in a side wall]: on the dark bands a crack in a side
## wall lies on black rock, and is drawn pale.
const CRACK_SHOTS: Array = [[2, false], [24, false], [21, true], [37, false], [55, false],
		[65, false], [75, false], [71, true], [95, false], [91, true]]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	while GameState.is_input_locked():
		await get_tree().process_frame
	await _frames(2)
	if "--cracks" in OS.get_cmdline_user_args():
		for shot: Array in CRACK_SHOTS:
			await _capture_crack(main, shot[0], shot[1])
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--puzzles" in OS.get_cmdline_user_args():
		for floor_number in [2, 37]:
			await _capture_puzzles(main, floor_number)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--bosses" in OS.get_cmdline_user_args():
		await _capture_boss_fights()
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--gates" in OS.get_cmdline_user_args():
		await _capture_gates(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--camps" in OS.get_cmdline_user_args():
		await _capture_camps(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--villages" in OS.get_cmdline_user_args():
		await _capture_villages(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--shapes" in OS.get_cmdline_user_args():
		await _capture_shapes(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--events" in OS.get_cmdline_user_args():
		await _capture_events(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--landmarks" in OS.get_cmdline_user_args():
		await _capture_landmarks(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--rooms" in OS.get_cmdline_user_args():
		await _capture_rooms()
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--modifiers" in OS.get_cmdline_user_args():
		await _capture_modifiers(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--dungeons" in OS.get_cmdline_user_args():
		await _capture_dungeons(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--forge" in OS.get_cmdline_user_args():
		await _capture_forge(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--shops" in OS.get_cmdline_user_args():
		await _capture_shops(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--menu" in OS.get_cmdline_user_args():
		await _capture_quests(main)
		await _capture_inventory(main)
		await _capture_map(main, "04p0_map_tab")
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--title" in OS.get_cmdline_user_args():
		await _capture_title(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--idle" in OS.get_cmdline_user_args():
		await _capture_idle(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
	if "--world" in OS.get_cmdline_user_args():
		await _capture_world(main)
		print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
		get_tree().quit()
		return
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
	await _capture_gates(main)
	await _capture_shops(main)

	# One floor per biome band worth showing off, and the authored ones past the
	# first -- 24 and 25 side by side are the same band generated and built.
	# The labyrinth in three of the ways a wall can be drawn: trees, cliffs, masonry.
	# Before the floor shots, which clear every floor below 100 -- and a cleared
	# floor's door is no longer hidden.
	for floor_number in [2, 24, 95]:
		await _capture_labyrinth(main, floor_number)
	await _capture_trap(main)
	for floor_number in [2, 37]:
		await _capture_puzzles(main, floor_number)
	for shot: Array in CRACK_SHOTS:
		await _capture_crack(main, shot[0], shot[1])

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

	# Left off the grid puts the cursor on the slots under the player.
	await _press(&"move_left")
	await _capture("04c_inventory_gear")

	# Up onto the tabs, and one along: the bag filtered to its equipment, with the
	# cursor on a coat -- the stats under the player say what wearing it would do.
	var menu := main.get_node("GameMenu")
	var page: Control = menu.call(&"page", 1)
	await _press(&"move_up")
	await _press(&"move_right")
	await _press(&"move_right")
	await _capture("04c2_inventory_tabs")
	await _press(&"move_down")
	await _press(&"move_right")
	await _capture("04c3_inventory_compare")
	page.call(&"set_category", 0)

	# A sword carried from the grid to the weapon slot: the whole point of the
	# mouse path, and the state worth looking at is halfway there, with the
	# targets it may land on lit up.
	await _drag(page.call(&"cell", 0), page.call(&"doll_slot", 0), "04d_inventory_drag")
	await _capture("04e_inventory_dropped")

	# The other tabs: who you are, and the system page.
	await _press(&"pause")
	await _press(&"pause")
	await _frames(4)
	await _capture("04e2_status")
	menu.call(&"show_tab", 4)
	await _frames(4)
	await _capture("04e3_system")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _capture("04e4_settings")
	menu.call(&"close")
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

	var camp: Rect2i = map.get_meta(&"safe_zone", Rect2i())
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
		if camp.has_point(path[i]):
			# The safe zone says what it is on the way through; stand by its fire.
			player.global_position = walls.map_to_local(camp.position + Vector2i(1, camp.size.y - 2))
			await _until(func() -> bool: return DialogueRunner.is_running(), 3.0)
			await _typed(main)
			await _capture(tag + "a2_camp")
			while DialogueRunner.is_running():
				DialogueRunner.advance()
				await _typed(main)
			await _wait(0.6)
			await _capture(tag + "a3_camp_fire")
			camp = Rect2i()
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


## A gilded chest on floor 2, the alarm it sounds, and the pack it brings.
func _capture_trap(main: Node) -> void:
	SceneRouter.enter_floor(2)
	await _frames(2)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)
	var map := SceneRouter.current_map() as GameMap
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	var player := map.get_node("Player") as Player
	var walls := map.get_node("Walls") as TileMapLayer
	var at := walls.local_to_map(player.position)
	var chest := (load("res://scenes/world/chest.tscn") as PackedScene).instantiate() as Chest
	chest.gilded = true
	chest.trap = Chest.Trap.ALARM
	chest.item_id = &"guard_ring"
	chest.opened_flag = &"screenshot_trap"
	chest.floor_number = 2
	chest.position = walls.map_to_local(at + Vector2i(0, -1))
	map.add_child(chest)
	player.facing = Vector2.UP
	await _wait(0.4)
	await _capture("05_trap_a_gilded")
	chest.interact(player)
	await _typed(main)
	DialogueRunner.advance()
	await _typed(main)
	await _capture("05_trap_b_alarm")
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)
	await _wait(0.3)
	await _capture("05_trap_c_pack")
	if CombatManager.is_running():
		await _end_fight()
	GameState.push_input_lock()
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	await _frames(2)
	GameState.pop_input_lock()


## A generated floor's puzzles, on the first floor at or above [param from_floor]
## that has all four: the wisp waiting, its shrine lit with the chest beside it,
## the braziers half lit and the tablet read, the statues looking away and then
## turned in, the sealed door, the map with the floor explored, and the vault open.
func _capture_puzzles(main: Node, from_floor: int) -> void:
	var floor_number := from_floor
	while floor_number < from_floor + 8:
		var probe := FloorRegistry.build_floor(floor_number)
		var whole := probe.get_node_or_null("Wisp") != null and probe.get_node_or_null("BrazierRite") != null \
				and probe.get_node_or_null("SealedDoor") != null and probe.get_node_or_null("StatueRing") != null
		probe.free()
		if whole and not FloorRegistry.get_floor(floor_number).is_authored():
			break
		floor_number += 1
	var map := await _enter(floor_number)
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	var player := map.get_node("Player") as Player
	var tag := "05_puzzle_%d" % floor_number

	var wisp := map.get_node("Wisp") as Wisp
	player.global_position = wisp.global_position + Vector2(-40, 18)
	player.facing = Vector2.RIGHT
	await _wait(0.6)
	await _capture(tag + "_a_wisp")

	var shrine := map.get_node("WispShrine") as Node2D
	GameState.set_flag(StringName("puzzle_%d_wisp" % floor_number))
	wisp.queue_free()
	player.global_position = shrine.global_position + Vector2(-28, 20)
	await _wait(0.8)
	await _capture(tag + "_b_shrine")

	var rite := map.get_node("BrazierRite") as BrazierRite
	var tablet := map.get_node("Tablet") as Node2D
	rite.braziers[0].set_lit(true)
	rite.braziers[1].set_lit(true)
	player.global_position = tablet.global_position + Vector2(0, 18)
	player.facing = Vector2.UP
	await _wait(0.4)
	await _capture(tag + "_c_braziers")
	tablet.call(&"interact", player)
	await _typed(main)
	await _capture(tag + "_d_tablet")
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)

	var ring := map.get_node("StatueRing") as StatueRing
	var altar := map.get_node("StatueAltar") as Node2D
	player.global_position = altar.global_position + Vector2(-16, 40)
	player.facing = Vector2.UP
	await _wait(0.6)
	await _capture(tag + "_c2_statues")
	var facings: Array[int] = []
	for statue in ring.statues:
		facings.append(statue.facing)
	var turns := StatueRing.turns_to_solve(facings, ring.targets)
	for i in turns.size():
		for _t in turns[i]:
			ring.statues[i].interact(player)
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)
	await _wait(0.6)
	await _capture(tag + "_c3_statues_solved")

	var seal := map.get_node("SealedDoor") as SealedDoor
	var door: Rect2i = map.get_meta(&"vault_door")
	var vault: Rect2i = map.get_meta(&"vault")
	var outward := Vector2(door.get_center() - vault.get_center()).normalized()
	player.global_position = seal.global_position + outward * 34.0
	player.facing = Vector2i(-outward.round()) as Vector2
	GameState.set_flag(seal.sigils[0])
	await _wait(0.4)
	await _capture(tag + "_e_sealed")

	var walls := map.get_node("Walls") as TileMapLayer
	var everything: Array[Vector2i] = []
	for cell in walls.get_used_rect().size.x * walls.get_used_rect().size.y:
		everything.append(walls.get_used_rect().position
				+ Vector2i(cell % walls.get_used_rect().size.x, cell / walls.get_used_rect().size.x))
	GameState.explore(map.map_id, everything)
	await _capture_map(main, tag + "_f_map")

	for sigil in seal.sigils:
		GameState.set_flag(sigil)
	seal.interact(player)
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)
	# Into the doorway, so the camera takes in the vault behind it.
	player.global_position = seal.global_position - outward * 8.0
	await _wait(0.8)
	await _capture(tag + "_g_open")


## A cracked wall on the first floor at or above [param from_floor] that has one
## -- in a side wall, with [param in_side] -- before and after it breaks: the
## crack (or the boulder, in a forest) with the grit at its foot, then the hollow
## open and its chest there.
func _capture_crack(main: Node, from_floor: int, in_side: bool) -> void:
	var floor_number := from_floor
	while floor_number < from_floor + 8:
		var probe := FloorRegistry.build_floor(floor_number)
		var crack := probe.get_node_or_null("CrackedWall") as CrackedWall
		var has := crack != null and (crack.side != Vector2i.UP) == in_side
		probe.free()
		if has:
			break
		floor_number += 1
	if floor_number == from_floor + 8:
		print("no cracked wall%s from floor %d on" % [" in a side wall" if in_side else "", from_floor])
		return
	GameState.set_flag(StringName("puzzle_%d_crack" % floor_number), false)
	var map := await _enter(floor_number)
	for child in map.get_children():
		if child is Monster:
			child.queue_free()
	var player := map.get_node("Player") as Player
	var crack := map.get_node("CrackedWall") as CrackedWall
	var tag := "05_crack_%d%s" % [floor_number, "_side" if crack.side != Vector2i.UP else ""]
	player.global_position = crack.global_position - Vector2(crack.side) * 30.0 + Vector2(10, 0)
	player.facing = Vector2(crack.side)
	await _wait(0.8)
	await _capture(tag + "_a_shut")
	crack.interact(player)
	await _wait(0.4)
	await _capture(tag + "_b_breaking")
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _typed(main)
	player.global_position = crack.global_position + Vector2(crack.side) * 8.0
	await _wait(1.0)
	await _capture(tag + "_c_open")


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
## in the right place -- behind a roof, under a grove's crowns -- the pieces a
## generated floor never shows, the pond's shoreline, and what the authored floors
## have of the generated ones': a labyrinth's mouth and camp, and their puzzles.
##
## The input lock is held for each shot so the field's monsters stand still rather
## than wandering into frame and starting a fight.
func _capture_world(main: Node) -> void:
	var world: Node = main.get_node("WorldRoot")
	var spots := [
		["res://scenes/world/town.tscn", Vector2(15 * 16 + 8, 9 * 16 + 10), "04j_town_behind_house"],
		["res://scenes/world/field.tscn", Vector2(14 * 16 + 8, 26 * 16 + 8), "04k_field_pond"],
		["res://scenes/world/field.tscn", Vector2(42 * 16, 14 * 16 + 12), "04l_field_under_grove"],
		["res://scenes/world/field.tscn", Vector2(57 * 16 + 8, 24 * 16 + 8), "04m_field_labyrinth"],
		["res://scenes/world/field.tscn", Vector2(31 * 16 + 8, 8 * 16 + 8), "04m2_field_wisp"],
		["res://scenes/world/floor_10.tscn", Vector2(7 * 16 + 8, 4 * 16 + 10), "04n_ashlow_behind_house"],
		["res://scenes/world/floor_10.tscn", Vector2(15 * 16 + 8, 14 * 16 + 8), "04o_ashlow_square"],
		["res://scenes/world/floor_10.tscn", Vector2(36 * 16 + 8, 31 * 16 + 8), "04p_ashlow_pool"],
		["res://scenes/world/floor_10.tscn", Vector2(64 * 16 + 8, 16 * 16 + 8), "04p3_ashlow_braziers"],
		["res://scenes/world/floor_10.tscn", Vector2(79 * 16, 32 * 16), "04p4_ashlow_hollow_camp"],
		["res://scenes/world/floor_25.tscn", Vector2(11 * 16 + 8, 6 * 16 + 10), "04q_lanternfall_behind_tent"],
		["res://scenes/world/floor_25.tscn", Vector2(17 * 16, 12 * 16 + 8), "04r_lanternfall_square"],
		["res://scenes/world/floor_25.tscn", Vector2(52 * 16 + 8, 8 * 16 + 8), "04s_lanternfall_galleries"],
		["res://scenes/world/floor_25.tscn", Vector2(60 * 16 + 8, 34 * 16 + 8), "04t_lanternfall_lake"],
		["res://scenes/world/floor_25.tscn", Vector2(11 * 16 + 8, 49 * 16 + 8), "04u_lanternfall_breach"],
		["res://scenes/world/floor_25.tscn", Vector2(50 * 16, 49 * 16 + 8), "04v_lanternfall_statues"],
		["res://scenes/world/floor_25.tscn", Vector2(31 * 16, 84 * 16), "04w_lanternfall_labyrinth_camp"],
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
		# A labyrinth's camp says what it is the first time you are in it.
		await _dismiss()
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


## The teleport gates: standing at the town's, Ashlow's, Lanternfall's and a
## generated floor's, and the floor list over the town's after a long climb --
## long enough to scroll. Arrived at through each gate's own spawn, so the shot is
## what coming through one looks like.
func _capture_gates(main: Node) -> void:
	for floor_number in range(1, 31):
		if floor_number > 1:
			GameState.clear_floor(floor_number - 1)
		GameState.visit_floor(floor_number)
	var spots := [
		[1, "04x_town_gate"], [10, "04x2_ashlow_gate"], [25, "04x3_lanternfall_gate"],
		[3, "04x4_floor3_gate"],
	]
	for spot: Array in spots:
		SceneRouter.enter_floor(spot[0], &"gate")
		var map := await _arrived(spot[0])
		var player := map.get_node("Player") as Player
		player.facing = Vector2.UP
		await _wait(0.3)
		await _capture(spot[1])
	SceneRouter.enter_floor(1, &"gate")
	await _arrived(1)
	var menu := main.get_node("GateMenu")
	menu.call(&"open", 1)
	await _wait(0.2)
	await _capture("04y_gate_menu")
	for _i in 12:
		await _press(&"move_up")
	await _capture("04y2_gate_menu_scrolled")
	menu.call(&"close")
	await _frames(2)


## Each hub's counter -- standing at it, buying, selling -- then the purse: the
## bag's header, and a fall's dropped pouch on the floor and on the map.
const SHOP_SPOTS := [[1, "Tomas", "town"], [10, "Hesk", "ashlow"], [25, "Odile", "lanternfall"]]


func _capture_shops(main: Node) -> void:
	for floor_number in range(1, 31):
		if floor_number > 1:
			GameState.clear_floor(floor_number - 1)
		GameState.visit_floor(floor_number)
	GameState.reset_col()
	EventBus.col_granted.emit(640)
	Inventory.add_id(&"boar_hide", 4)
	Inventory.add_id(&"wolf_fang", 2)
	Inventory.add_id(&"anneal_blade", 1)
	var screen := main.get_node("ShopScreen")
	for spot: Array in SHOP_SPOTS:
		SceneRouter.enter_floor(spot[0], &"gate")
		var map := await _arrived(spot[0])
		var player := map.get_node("Player") as Player
		var keeper := map.get_node(String(spot[1])) as Npc
		_stand_by(map, player, keeper)
		await _wait(0.3)
		await _capture("04s_%s_counter" % spot[2])
		keeper.interact(player)
		await _wait(0.2)
		await _press(&"move_down")
		await _capture("04s_%s_buy" % spot[2])
		await _press(&"move_right")
		await _capture("04s_%s_sell" % spot[2])
		screen.call(&"close")
		await _frames(2)

	var town := main.get_node("WorldRoot").get_child(0) as GameMap
	var player := town.get_node("Player") as Player
	GameState.drop_col(town.map_id, town.to_local(player.global_position) + Vector2(0, 24))
	await _wait(0.3)
	await _capture("04s_dropped_col")
	await _capture_map(main, "04s_dropped_col_map")
	GameState.recover_col()
	var menu := main.get_node("GameMenu")
	menu.call(&"open", 1, true)
	await _wait(0.2)
	await _capture("04s_bag_purse")
	menu.call(&"close")
	await _frames(2)


## The rest of M5.6's sinks: Nezha's forge on a worn blade (and a failure), Argo's
## door pitch, a door she sold on its floor's map, and a peddler by a safe zone's
## fire with their pack open.
func _capture_forge(main: Node) -> void:
	for floor_number in range(1, 31):
		if floor_number > 1:
			GameState.clear_floor(floor_number - 1)
		GameState.visit_floor(floor_number)
	GameState.reset_col()
	EventBus.col_granted.emit(4000)
	Inventory.add_id(&"anneal_blade", 1)
	Inventory.equip(ItemLibrary.get_item(&"anneal_blade"))
	Inventory.add_id(&"leather_coat", 1)
	Inventory.add_id(&"swift_charm", 1)
	Inventory.add_id(&"boar_hide", 4)
	Inventory.add_id(&"wolf_fang", 3)
	Inventory.add_id(&"lizard_scale", 2)
	SceneRouter.enter_floor(1, &"gate")
	await _arrived(1)
	var forge := main.get_node("ForgeScreen")
	EventBus.forge_requested.emit(ShopLibrary.get_smith(&"town_forge"))
	await _wait(0.2)
	await _capture("04v_forge")
	forge.call(&"work", 0.0)
	await _press(&"move_right")
	await _capture("04v_forge_extra")
	forge.call(&"set_extra", 0)
	forge.call(&"work", 99.9)
	await _capture("04v_forge_failed")
	forge.call(&"close")
	await _frames(2)

	# Argo's pitch: floors 2 to 30 stood on, none of their doors found.
	DialogueRunner.start(DoorIntel.conversation())
	await _typed(main)
	while DialogueRunner.is_running() and not DialogueRunner.is_choosing():
		DialogueRunner.advance()
		await _typed(main)
	await _capture("04v_argo_doors")
	DialogueRunner.choose(0)
	await _typed(main)
	await _capture("04v_argo_sold")
	while DialogueRunner.is_running():
		DialogueRunner.advance()
		await _frames(2)
	var sold := 30
	SceneRouter.enter_floor(sold, &"gate")
	await _arrived(sold)
	await _wait(0.3)
	await _capture_map(main, "04v_argo_door_on_map")

	# The first floor with a peddler by its fire.
	for floor_number in range(2, 31):
		var probe := FloorRegistry.build_floor(floor_number)
		var has_one := probe.get_node_or_null("Merchant") != null
		probe.free()
		if not has_one:
			continue
		SceneRouter.enter_floor(floor_number, &"gate")
		var map := await _arrived(floor_number)
		var player := map.get_node("Player") as Player
		var peddler := map.get_node("Merchant") as Npc
		_stand_by(map, player, peddler)
		await _wait(0.4)
		# Walking in says "the air is calm here" -- let it.
		while DialogueRunner.is_running():
			DialogueRunner.advance()
			await _frames(2)
		await _wait(0.2)
		await _capture("04v_peddler_floor%02d" % floor_number)
		peddler.interact(player)
		await _wait(0.2)
		await _capture("04v_peddler_pack")
		main.get_node("ShopScreen").call(&"close")
		await _frames(2)
		break


## A generated floor's adventurers' camp in every band, as you arrive in it; one
## of its people talking; and the camp on the map.
const CAMP_FLOORS := [2, 15, 22, 35, 45, 55, 65, 75, 85, 95]


func _capture_camps(main: Node) -> void:
	for floor_number: int in CAMP_FLOORS:
		GameState.clear_floor(floor_number - 1)
		SceneRouter.enter_floor(floor_number, &"default")
		var map := await _arrived(floor_number)
		await _wait(0.3)
		await _capture("04z_camp_floor%02d" % floor_number)
		if floor_number != CAMP_FLOORS[0]:
			continue
		var camper := map.get_node_or_null("Camper0") as Npc
		if camper != null:
			var player := map.get_node("Player") as Player
			for offset: Vector2 in [Vector2(0, 16), Vector2(0, -16), Vector2(16, 0), Vector2(-16, 0)]:
				var cell := map.get_node("Walls").local_to_map(camper.position + offset) as Vector2i
				if map.is_standable(cell):
					player.position = camper.position + offset
					player.facing = -offset.normalized()
					break
			await _frames(6)
			await _capture("04z_camp_prompt")
			camper.interact(player)
			await _typed(main)
			await _capture("04z_camp_talk")
			while DialogueRunner.is_running():
				DialogueRunner.advance()
				await _frames(2)
		await _capture_map(main, "04z_camp_map")


## Open fields, built as such on a floor of several bands: the arrival, the arena's
## sealed gate, a waystone woken, the gate open, and the whole field on the map.
func _capture_shapes(main: Node) -> void:
	FloorGenerator.shape_override = FloorDefinition.Shape.OPEN_FIELD
	for floor_number: int in OPEN_FIELD_FLOORS:
		GameState.clear_floor(floor_number - 1)
		SceneRouter.enter_floor(floor_number, &"default")
		var map := await _arrived(floor_number)
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		await _wait(0.3)
		await _capture("04zo_open_floor%02d" % floor_number)
		var player := map.get_node("Player") as Player
		var seal := map.get_node("ArenaSeal") as SealedDoor
		var room: Rect2i = map.get_meta(&"arena_room")
		var outward := (seal.position - Vector2(room.get_center() * 16)).normalized()
		outward = Vector2(signf(outward.x), 0) if absf(outward.x) > absf(outward.y) else Vector2(0, signf(outward.y))
		player.position = seal.position + outward * 28
		player.facing = -outward
		await _settle_camera(player)
		await _capture("04zo_open_gate%02d" % floor_number)
		var stone := map.get_node("Waystone0") as Waystone
		_stand_by(map, player, stone)
		await _settle_camera(player)
		if floor_number == OPEN_FIELD_FLOORS[0]:
			await _capture("04zo_open_waystone")
			stone.interact(player)
			await _typed(main)
			await _capture("04zo_open_waystone_wakes")
			while DialogueRunner.is_running():
				DialogueRunner.advance()
				await _frames(2)
		for flag in seal.sigils:
			GameState.set_flag(flag)
		await _wait(1.0)
		while DialogueRunner.is_running():
			DialogueRunner.advance()
			await _frames(2)
		player.position = seal.position - outward * 40
		player.facing = outward
		await _settle_camera(player)
		await _capture("04zo_open_arena%02d" % floor_number)
		var all: Array[Vector2i] = []
		var used := (map.get_node("Walls") as TileMapLayer).get_used_rect()
		for y in range(used.position.y, used.end.y):
			for x in range(used.position.x, used.end.x):
				all.append(Vector2i(x, y))
		GameState.explore(map.map_id, all)
		await _capture_map(main, "04zo_open_map%02d" % floor_number)
	FloorGenerator.shape_override = -1


## Dungeons, built as such on a floor of several bands: the lamplit entrance hall,
## the dark past it, every level's sealed chamber and what opens it, the climb, the
## landing's fire, the top's boss hall -- and each level on the map.
func _capture_dungeons(main: Node) -> void:
	FloorGenerator.shape_override = FloorDefinition.Shape.DUNGEON
	for floor_number: int in DUNGEON_FLOORS:
		GameState.clear_floor(floor_number - 1)
		for level in range(1, FloorRegistry.levels_of(floor_number) + 1):
			SceneRouter.enter_floor(floor_number, &"default", SceneRouter.FADE_TIME, level)
			await _until(func() -> bool:
				var at := SceneRouter.current_map() as GameMap
				return at != null and at.map_id == DungeonGenerator.map_id_for(floor_number, level) \
						and not GameState.is_input_locked(), 10.0)
			await _wait(0.4)
			var map := SceneRouter.current_map() as GameMap
			for child in map.get_children():
				if child is Monster and child.name != "Warden":
					child.queue_free()
			var player := map.get_node("Player") as Player
			var tag := "04zd_f%02d_l%d" % [floor_number, level]
			await _capture(tag + "_arrive")
			var seal := map.get_node_or_null("StairsSeal") as SealedDoor
			if seal != null:
				# The slab, from the doorway, then the first piece that opens it.
				var room: Rect2i = map.get_meta(&"chamber_room")
				var outward := (seal.position - Vector2(room.get_center() * 16)).normalized()
				outward = Vector2(signf(outward.x), 0) if absf(outward.x) > absf(outward.y) \
						else Vector2(0, signf(outward.y))
				player.position = seal.position + outward * 28
				player.facing = -outward
				await _settle_camera(player)
				await _capture(tag + "_seal")
				for piece_name in ["Warden", "Lever0", "Brazier0", "Statue0"]:
					var piece := map.get_node_or_null(piece_name) as Node2D
					if piece != null:
						_stand_by(map, player, piece)
						await _settle_camera(player)
						await _capture(tag + "_" + str(map.get_meta(&"seal")))
						break
				for flag in seal.sigils:
					GameState.set_flag(flag)
				await _wait(1.0)
				while DialogueRunner.is_running():
					DialogueRunner.advance()
					await _frames(2)
				player.position = (map.get_node("SpawnPoints/stairs_up") as Node2D).position
				player.facing = Vector2.UP
				await _settle_camera(player)
				await _capture(tag + "_ladder")
			var fire := map.get_node_or_null("Campfire") as Node2D
			if fire != null:
				_stand_by(map, player, fire)
				await _settle_camera(player)
				await _capture(tag + "_landing")
			var door := map.get_node_or_null("BossGate") as Node2D
			if door != null:
				player.position = door.position + Vector2(0, 48)
				player.facing = Vector2.UP
				await _settle_camera(player)
				await _capture(tag + "_hall")
			var all: Array[Vector2i] = []
			var used := (map.get_node("Walls") as TileMapLayer).get_used_rect()
			for y in range(used.position.y, used.end.y):
				for x in range(used.position.x, used.end.x):
					all.append(Vector2i(x, y))
			GameState.explore(map.map_id, all)
			await _capture_map(main, tag + "_map")
	FloorGenerator.shape_override = -1


## Floor modifiers: a storm's headline as you arrive, then the storm over a field
## room and over the labyrinth's dark -- in every weather -- and an infested floor,
## its swarm left standing.
func _capture_modifiers(main: Node) -> void:
	FloorGenerator.modifier_override = FloorModifier.Kind.STORM
	FloorGenerator.shape_override = FloorDefinition.Shape.CLASSIC
	for floor_number: int in STORM_FLOORS:
		GameState.clear_floor(floor_number - 1)
		SceneRouter.enter_floor(floor_number, &"default")
		var map := await _arrived(floor_number)
		for child in map.get_children():
			if child is Monster:
				child.queue_free()
		await _wait(0.6)
		await _capture("04zm_storm%02d_arrival" % floor_number)
		var player := map.get_node("Player") as Player
		var lab: Rect2i = map.get_meta(&"labyrinth", Rect2i())
		var mouth: Rect2i = map.get_meta(&"labyrinth_mouth", Rect2i())
		if lab.has_area() and mouth.has_area():
			player.position = Vector2(mouth.position * 16) + Vector2(8, 8)
			await _settle_camera(player)
			await _wait(0.6)
			await _capture("04zm_storm%02d_maze" % floor_number)
	FloorGenerator.modifier_override = FloorModifier.Kind.INFESTED
	GameState.clear_floor(INFESTED_FLOOR - 1)
	SceneRouter.enter_floor(INFESTED_FLOOR, &"default")
	var infested := await _arrived(INFESTED_FLOOR)
	for child in infested.get_children():
		if child is Monster:
			(child as Monster).calm()
	await _wait(0.6)
	await _capture("04zm_infested%02d_arrival" % INFESTED_FLOOR)
	var all: Array[Vector2i] = []
	var used := (infested.get_node("Walls") as TileMapLayer).get_used_rect()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			all.append(Vector2i(x, y))
	GameState.explore(infested.map_id, all)
	await _capture_map(main, "04zm_infested_map")
	FloorGenerator.modifier_override = -1
	FloorGenerator.shape_override = -1


## Landmarks: each kind in the bands that draw it, seen from in front -- and the
## first of each from behind, which is the only way to see it sort over you, and
## read, which is the only way to see its words in the box.
func _capture_landmarks(main: Node) -> void:
	# The floor test's world, so a shot can be found again.
	GameState.new_world_seed(12345)
	FloorGenerator.shape_override = FloorDefinition.Shape.CLASSIC
	FloorGenerator.event_override = FloorEvents.Kind.NONE
	FloorGenerator.modifier_override = FloorModifier.Kind.NONE
	for kind: int in LANDMARK_FLOORS:
		FloorGenerator.landmark_override = kind
		var first := true
		for floor_number: int in LANDMARK_FLOORS[kind]:
			GameState.clear_floor(floor_number - 1)
			SceneRouter.enter_floor(floor_number, &"default")
			var map := await _arrived(floor_number)
			var landmark := map.get_node_or_null("Landmark") as Landmark
			if landmark == null or landmark.kind != kind:
				print("floor %d grew no %s" % [floor_number, FloorLandmarks.KIND_NAMES[kind]])
				continue
			for child in map.get_children():
				if child is Monster:
					child.queue_free()
			var player := map.get_node("Player") as Player
			var room: Rect2i = map.get_meta(&"landmark_room")
			var shot := "04zl_%s%02d" % [FloorLandmarks.KIND_NAMES[kind].replace(" ", "_"), floor_number]
			# On the shore above a lake, by its sign; a little way in front of anything else.
			var lake := kind == FloorLandmarks.Kind.LAKE
			player.position = Vector2(room.get_center().x * 16 + 8, room.position.y * 16 + 8) \
					if lake else landmark.position + Vector2(0, 24)
			player.facing = Vector2.DOWN if lake else Vector2.UP
			await _settle_camera(player)
			await _wait(0.4)
			await _capture(shot)
			if not first:
				continue
			first = false
			if kind != FloorLandmarks.Kind.LAKE:
				player.position = landmark.position + Vector2(-8, -40)
				await _settle_camera(player)
				await _wait(0.3)
				await _capture(shot + "_behind")
			landmark.interact(player)
			await _until(func() -> bool: return DialogueRunner.is_running(), 5.0)
			await _typed(main)
			await _capture(shot + "_read")
			while DialogueRunner.is_running():
				DialogueRunner.advance()
				await _wait(0.1)
	FloorGenerator.landmark_override = -1
	FloorGenerator.modifier_override = -1
	FloorGenerator.event_override = -1
	FloorGenerator.shape_override = -1


## Room shapes ([RoomShapes]): each kind, forced on every room that may take one, in
## every band that draws it -- the biggest room of the kind on the floor, from its
## middle, monsters cleared.
func _capture_rooms() -> void:
	GameState.new_world_seed(12345)
	FloorGenerator.shape_override = FloorDefinition.Shape.CLASSIC
	FloorGenerator.event_override = FloorEvents.Kind.NONE
	FloorGenerator.landmark_override = FloorLandmarks.Kind.NONE
	FloorGenerator.modifier_override = FloorModifier.Kind.NONE
	for kind in range(1, RoomShapes.Kind.size()):
		FloorGenerator.room_shape_override = kind
		for floor_number: int in BAND_FLOORS:
			var weights: Array = RoomShapes.WEIGHTS.get(FloorRegistry.biome_id(floor_number),
					RoomShapes.DEFAULT_WEIGHTS)
			if weights[kind - 1] == 0:
				continue
			GameState.clear_floor(floor_number - 1)
			SceneRouter.enter_floor(floor_number, &"default")
			var map := await _arrived(floor_number)
			var best := Rect2i()
			var shaped: Dictionary = map.get_meta(&"room_shapes", {})
			for room: Rect2i in shaped:
				if shaped[room] == kind and room.get_area() > best.get_area():
					best = room
			if not best.has_area():
				print("floor %d shaped no %s" % [floor_number, RoomShapes.KIND_NAMES[kind]])
				continue
			for child in map.get_children():
				if child is Monster:
					child.queue_free()
			var walls := map.get_node("Walls") as TileMapLayer
			var stand := best.get_center()
			var spots: Array[Vector2i] = [stand]
			for ring in range(1, 4):
				for y in range(-ring, ring + 1):
					for x in range(-ring, ring + 1):
						spots.append(stand + Vector2i(x, y))
			for spot in spots:
				if walls.get_cell_source_id(spot) == -1:
					stand = spot
					break
			var player := map.get_node("Player") as Player
			player.position = Vector2(stand * 16) + Vector2(8, 8)
			player.facing = Vector2.DOWN
			await _settle_camera(player)
			await _wait(0.3)
			await _capture("04zr_%s%02d" % [RoomShapes.KIND_NAMES[kind].replace(" ", "_"), floor_number])
	FloorGenerator.room_shape_override = -1
	FloorGenerator.modifier_override = -1
	FloorGenerator.landmark_override = -1
	FloorGenerator.event_override = -1
	FloorGenerator.shape_override = -1


## Floor events: a field boss in front of its hoard; a stranded player with the
## monsters round them, then following you; player killers stepping out of hiding,
## and what they say; and a duellist in the camp, the duel staged, and a rigged
## one refusing to yield.
func _capture_events(main: Node) -> void:
	FloorGenerator.shape_override = FloorDefinition.Shape.CLASSIC
	for kind: int in EVENT_FLOORS:
		FloorGenerator.event_override = kind
		for floor_number: int in EVENT_FLOORS[kind]:
			GameState.clear_floor(floor_number - 1)
			SceneRouter.enter_floor(floor_number, &"default")
			var map := await _arrived(floor_number)
			var player := map.get_node("Player") as Player
			var shot := "04ze_%s%02d" % [FloorEvents.KIND_NAMES[kind].replace(" ", "_"), floor_number]
			# Only the event's own monsters, so the shot is of it.
			for child in map.get_children():
				if child is Monster and child.name != "FieldBoss" and not String(child.name).begins_with("Besieger"):
					child.queue_free()
				elif child is Monster:
					(child as Monster).calm(30.0)
			match kind:
				FloorEvents.Kind.FIELD_BOSS:
					var keeper := map.get_node_or_null("FieldBoss") as Node2D
					if keeper == null:
						continue
					player.position = keeper.position + Vector2(0, 48)
					player.facing = Vector2.UP
					await _settle_camera(player)
					await _wait(0.4)
					await _capture(shot)
				FloorEvents.Kind.ESCORT:
					var stranded := map.get_node_or_null("Stranded") as Escortee
					if stranded == null:
						continue
					player.position = stranded.position + Vector2(-48, 0)
					await _settle_camera(player)
					await _wait(0.4)
					await _capture(shot + "_cornered")
					for child in map.get_children():
						if child is Monster:
							child.queue_free()
					QuestLog.start(FloorEvents.escort_quest(floor_number))
					stranded.follow()
					for step in 30:
						player.position += Vector2(-2, 0)
						await get_tree().physics_frame
					await _wait(0.4)
					await _capture(shot + "_following")
				FloorEvents.Kind.AMBUSH:
					var area: Rect2i = map.get_meta(&"ambush", Rect2i())
					if not area.has_area():
						continue
					# Paid off after the shot: walking away from them is a fight.
					EventBus.col_granted.emit(FloorEvents.toll(floor_number))
					player.position = Vector2(area.get_center() * 16) + Vector2(8, 8)
					await _settle_camera(player)
					await _until(func() -> bool: return DialogueRunner.is_running(), 5.0)
					await _typed(main)
					await _capture(shot)
					DialogueRunner.advance()
					await _until(func() -> bool: return DialogueRunner.is_choosing(), 5.0)
					DialogueRunner.choose(0)
					await _until(func() -> bool: return not GameState.is_input_locked(), 5.0)
				FloorEvents.Kind.DUEL:
					# Whatever the last pass left on screen, read.
					while DialogueRunner.is_running():
						DialogueRunner.advance()
						await _wait(0.1)
					# A level-1 body on floor 65 is one blow from half: a guard, so
					# there is a duel on screen to shoot.
					var guard := GameState.defense
					GameState.defense = 999
					for rigged in [0, 1]:
						FloorEvents.rigged_override = rigged
						GameState.set_flag(FloorEvents.flag(floor_number, "duel"), false)
						if rigged == 1:
							SceneRouter.enter_floor(floor_number, &"default")
							map = await _arrived(floor_number)
							player = map.get_node("Player") as Player
							for child in map.get_children():
								if child is Monster:
									child.queue_free()
						var duellist := map.get_node_or_null("Duellist") as Duellist
						if duellist == null:
							break
						player.position = duellist.position + Vector2(0, 24)
						player.facing = Vector2.UP
						GameState.set_hp(GameState.total_max_hp())
						EventBus.col_granted.emit(FloorEvents.stake(floor_number))
						await _settle_camera(player)
						if rigged == 0:
							await _wait(0.4)
							await _capture(shot + "_camp")
						duellist.interact(player)
						await _until(func() -> bool: return DialogueRunner.is_choosing(), 5.0)
						DialogueRunner.choose(0)
						while DialogueRunner.is_running():
							await _typed(main)
							DialogueRunner.advance()
							await _wait(0.1)
						await _until_command()
						if rigged == 0:
							await _capture(shot + "_staged")
							await _finish()
						else:
							var foe := CombatManager.living_enemies()[0]
							foe.take_damage(foe.hp - foe.max_hp / 2)
							_submit(CombatAction.use(SkillLibrary.basic_attack(), foe))
							await _until(func() -> bool: return CombatManager.living_enemies().is_empty() \
									or CombatManager.is_awaiting_command() or _said_paralysis(), 10.0)
							await _wait(0.2)
							await _capture(shot + "_betrayal")
							await _until_command()
							await _end_fight()
						await _until(func() -> bool: return not GameState.is_input_locked() \
								or DialogueRunner.is_running(), 5.0)
						while DialogueRunner.is_running():
							DialogueRunner.advance()
							await _wait(0.1)
					FloorEvents.rigged_override = -1
					GameState.defense = guard
	FloorGenerator.event_override = -1
	FloorGenerator.shape_override = -1


## Whether the fight's line is the duellist's paralysis pick going in.
func _said_paralysis() -> bool:
	var hud := get_tree().root.find_child("BattleHud", true, false)
	var said: Variant = hud.get(&"_said") if hud != null else null
	return said is String and "paralysis" in said


## Waits out the camera's smoothing after [param player] has been put somewhere
## far from where it was looking.
func _settle_camera(player: Player) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
	await _wait(0.3)


## The same camps settled into villages, three floors behind the front line; a
## settler offering their job; the lost player it sends you after, waiting in the
## labyrinth; and the village on the map.
func _capture_villages(main: Node) -> void:
	for floor_number: int in CAMP_FLOORS:
		GameState.clear_floor(floor_number - 1)
		GameState.clear_floor(floor_number + LocalQuests.SETTLE_AFTER)
		SceneRouter.enter_floor(floor_number, &"default")
		var map := await _arrived(floor_number)
		await _wait(0.3)
		await _capture("04zv_village_floor%02d" % floor_number)
		if floor_number != CAMP_FLOORS[0]:
			continue
		var player := map.get_node("Player") as Player
		var settler := map.get_node_or_null("Settler0") as Npc
		if settler != null:
			_stand_by(map, player, settler)
			await _frames(6)
			settler.interact(player)
			await _typed(main)
			await _capture("04zv_village_talk")
			while DialogueRunner.is_running():
				if DialogueRunner.is_choosing():
					DialogueRunner.choose(DialogueRunner.offered_choices().size() - 1)
				else:
					DialogueRunner.advance()
				await _frames(2)
		await _capture_map(main, "04zv_village_map")
		var lost := map.get_node_or_null("LostPlayer") as Npc
		if lost != null:
			QuestLog.start(LocalQuests.talk_quest(floor_number))
			_stand_by(map, player, lost)
			await _wait(1.0)
			await _capture("04zv_village_lost")


## Puts [param player] on a free cell beside [param npc], facing them.
## The title screen's three pages and a notice, and the pause menu over a death
## game. Saves into a directory of its own, never the player's slots.
## A marathon left alone: the countdown early and late, the avatar shattering, and
## the title saying why.
func _capture_idle(main: Node) -> void:
	_idle_now = 1000.0
	IdleWatch.clock = func() -> float: return _idle_now
	GameState.mode = GameState.Mode.MARATHON
	IdleWatch.touch()
	await _frames(2)
	_idle_now += IdleWatch.limit - 45.0
	await _wait(0.8)
	await _capture("60_idle_warning")
	_idle_now += 40.0
	await _wait(1.5)
	await _capture("61_idle_last_seconds")
	_idle_now += 10.0
	await _wait(IdleWatch.SHATTER_TIME * 0.12 + 0.35)
	await _capture("62_idle_shatter")
	await _wait(0.5)
	await _capture("62b_idle_shatter_late")
	await _until(func() -> bool:
		return (main.get_node("TitleScreen") as CanvasLayer).visible and not SceneRouter.is_busy(), 10.0)
	await _wait(0.6)
	await _capture("63_idle_title")


func _capture_title(main: Node) -> void:
	SaveGame.directory = "user://screenshot_saves"
	for n in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete(n)
	for below in range(1, 10):
		GameState.clear_floor(below)
	while GameState.level < 14:
		GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp)
	SceneRouter.enter_floor(10)
	await _arrived(10)
	SaveGame.save_game(1)
	# Or arriving on floor 2 autosaves the hardcore game over slot 1.
	SaveGame.slot = 0
	GameState.mode = GameState.Mode.HARDCORE
	SceneRouter.enter_floor(2)
	await _arrived(2)
	SaveGame.save_game(3)

	var menu := main.get_node("GameMenu")
	menu.call(&"open", 4)
	(menu.call(&"page", 4).call(&"list") as MenuList).select(2)
	await _wait(0.2)
	await _capture("50_system_hardcore")
	menu.call(&"close")

	var title := main.get_node("TitleScreen")
	await SaveGame.quit_to_title()
	await _until(func() -> bool: return not SceneRouter.is_busy(), 10.0)
	await _wait(0.5)
	await _capture("51_title")
	var rows: MenuList = title.call(&"list")
	rows.select(2)
	rows.choose()
	await _wait(0.1)
	await _capture("52_title_load")
	await _press(&"ui_cancel")
	rows.select(1)
	rows.choose()
	await _wait(0.1)
	await _capture("53_title_new_game")
	(title.call(&"cards") as CardList).choose()
	await _wait(0.1)
	await _capture("53b_title_new_slot")
	(title.call(&"cards") as CardList).select(0)
	(title.call(&"cards") as CardList).choose()
	await _wait(0.1)
	await _capture("53c_title_overwrite")
	await _press(&"ui_cancel")
	await _press(&"ui_cancel")
	await _press(&"ui_cancel")
	rows.select(3)
	rows.choose()
	await _wait(0.1)
	await _capture("55_title_settings")
	await _press(&"ui_cancel")
	rows.select(4)
	rows.choose()
	await _wait(0.1)
	await _capture("56_title_credits")
	await _press(&"ui_cancel")
	SaveGame.delete(3)
	title.call(&"open", "Kirito died on Floor 2. Slot 3 is empty.")
	await _wait(0.1)
	await _capture("54_title_notice")
	for n in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete(n)


func _stand_by(map: GameMap, player: Player, npc: Node2D) -> void:
	for offset: Vector2 in [Vector2(0, 16), Vector2(0, -16), Vector2(16, 0), Vector2(-16, 0)]:
		var cell := map.get_node("Walls").local_to_map(npc.position + offset) as Vector2i
		if map.is_standable(cell):
			player.position = npc.position + offset
			player.facing = -offset.normalized()
			return


## The map screen over whatever has been explored so far. Opened directly, since
## the caller is holding the input lock that M would wait for.
func _capture_map(main: Node, tag: String) -> void:
	var menu := main.get_node("GameMenu")
	menu.call(&"open", 3, true)
	await _wait(0.2)
	await _capture(tag)
	menu.call(&"close")
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


## A control's middle in window pixels, not in the 640x360 units it is laid out
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
