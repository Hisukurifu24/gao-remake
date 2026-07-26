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
	DialogueRunner.cancel()

	await _capture_combat()

	# Generated floors, one per biome band worth showing off.
	for floor_number in [2, 24, 55, 87, 100]:
		await _capture_floor(floor_number)

	print("screenshots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


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


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, shot_name])
