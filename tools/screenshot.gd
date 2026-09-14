extends Node
## Boots the game, captures a few frames to user:// and exits.
##
##     "$GODOT" --path . res://tools/screenshot.tscn
##
## Dev aid for checking how a change actually looks without sitting through the
## game. Needs a real window, so it can't run with --headless.

const SHOTS := "user://screenshots"


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
	await _frames(90)
	await _capture("03_dialogue")

	# Press on until Argo asks what you want -- that is the choice menu.
	for _i in 20:
		if DialogueRunner.is_choosing():
			break
		DialogueRunner.advance()
		await _frames(90)
	await _capture("04_choices")

	await _capture_quests()
	await _capture_inventory(main)
	await _capture_combat()

	# One floor per biome band worth showing off, and the authored ones past the
	# first -- 24 and 25 side by side are the same band generated and built.
	for floor_number in [2, 10, 24, 25, 55, 87, 100]:
		await _capture_floor(floor_number)

	print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


## The two quest surfaces: the corner tracker, and the journal.
##
## Argo's errand is taken through her real choice menu rather than by calling
## QuestLog, because the thing worth looking at is what a player sees after the
## conversation they actually had. Everything after that is set up by hand -- a
## screenshot pass is not a playthrough.
func _capture_quests() -> void:
	var work := _choice_index("Got any work")
	if work >= 0:
		DialogueRunner.choose(work)
		await _frames(60)
		for _i in 10:
			if DialogueRunner.is_choosing() or not DialogueRunner.is_running():
				break
			DialogueRunner.advance()
			await _frames(60)
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
	var slot: Control = screen.get_node("Bag/Margin/Column/Grid").get_child(0)
	var weapon_row: Control = screen.get_node("Gear/Margin/Rows/Weapon")
	await _drag(slot, weapon_row, "04d_inventory_drag")
	await _capture("04e_inventory_dropped")

	await _press(&"inventory")
	await _frames(4)


## The battle interface, caught at the three moments worth looking at: the
## command menu, the skill list, and a resolved swing with numbers in the air.
func _capture_combat() -> void:
	GameState.level = 12
	GameState.max_hp = 126
	GameState.attack = 30
	GameState.set_hp(90)
	CombatManager.start(Bestiary.boss_encounter(1))

	await _until_command()
	await _capture("05_combat_menu")

	# Second row down is Sword Skills. Fed as real events rather than through
	# Input.action_press, which sets the action state without ever reaching
	# _unhandled_input -- the menu would never see the keypress.
	await _press(&"move_down")
	await _press(&"interact")
	await _capture("06_combat_skills")

	# Back out and two rows further down is Item -- stocked by the inventory
	# capture above, so there is something on the list.
	await _press(&"ui_cancel")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _capture("06b_combat_items")
	await _press(&"ui_cancel")

	# Let the round play out so there are numbers and a log line on screen.
	CombatManager.submit(CombatAction.use(SkillLibrary.get_skill(&"slant"),
			CombatManager.living_enemies()[0]))
	await _frames(20)
	await _capture("07_combat_hit")

	# A boss fight can't be fled, so end it the only way it ends. The next
	# capture waits on the input lock, which combat holds until it is over.
	await _until_command()
	for enemy in CombatManager.living_enemies():
		enemy.take_damage(enemy.hp)
	CombatManager.submit(CombatAction.use(SkillLibrary.basic_attack(), null))
	while CombatManager.is_running():
		await get_tree().process_frame
	await _frames(120)
	GameState.set_hp(GameState.max_hp)


func _until_command(timeout := 900) -> void:
	for _i in timeout:
		if CombatManager.is_awaiting_command():
			await _frames(4)
			return
		await get_tree().process_frame


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
## a position handed straight over lands at half the intended height.
func _center(control: Control) -> Vector2:
	return get_viewport().get_final_transform() * control.get_global_rect().get_center()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, shot_name])
