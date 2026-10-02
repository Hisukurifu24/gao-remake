extends "res://tools/battle_spike.gd"
## M5.5 §6 step 5: the pack's juice. Two monster fights on Floor 2 -- one you
## open, one that catches you -- shot for the alarm bubble, the menu's icons, a
## sword skill's effect landing, a monster's claw landing on you, a heal, and
## statuses showing as bubbles over the heads that wear them.
##
##     "$GODOT" --path . res://tools/juice_spike.tscn
##
## Throwaway, like the other spikes: its shots fold into screenshot.gd in step 7.


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)

	# Every skill in the menu, and a blade too blunt to end a fight early.
	GameState.level = 30
	GameState.attack = 2
	GameState.defense = 100000
	GameState.set_hp(GameState.total_max_hp())
	GameState.clear_floor(1)
	SceneRouter.enter_floor(FLOOR)
	await _frames(2)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)

	var map := SceneRouter.current_map() as GameMap
	var walls := map.get_node("Walls") as TileMapLayer
	var lab: Rect2i = map.get_meta(&"labyrinth")
	var player := map.get_node("Player") as Player
	var monsters: Array[Monster] = []
	for child in map.get_children():
		if child is Monster:
			monsters.append(child)
	var room := _room_cell(map, walls, lab, player.position)
	BattleStage.zoom = 2.0

	await _juiced_fight(player, monsters.pop_back(), walls, room[0], room[1],
			Encounter.Opening.PARTY_FIRST, "juice_open")
	await _juiced_fight(player, monsters.pop_back(), walls, room[0], room[1],
			Encounter.Opening.ENEMIES_FIRST, "juice_caught")

	_juice_sheet()
	print("juice shots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


func _juiced_fight(player: Player, monster: Monster, walls: TileMapLayer, cell: Vector2i,
		toward: Vector2i, opening: Encounter.Opening, tag: String) -> void:
	GameState.push_input_lock()
	player.global_position = walls.map_to_local(cell) + Vector2(0, 4)
	player.facing = Vector2(toward)
	monster.global_position = player.global_position + Vector2(toward) * 12.0
	await _wait(0.3)
	GameState.pop_input_lock()
	monster.call(&"_engage", opening)
	# The opening is announced after the runner's pause before round 1.
	await _wait(0.75)
	await _capture(tag + "_a_alarm")
	if opening == Encounter.Opening.ENEMIES_FIRST:
		# Its blow lands one step_delay after the alarm.
		await _wait(0.5)
		await _capture(tag + "_b_clawed")
	await _until_command()
	var enemy := CombatManager.living_enemies()[0]
	enemy.apply_status(load("res://resources/statuses/weakened.tres"))
	enemy.apply_status(load("res://resources/statuses/poison.tres"))
	await _wait(0.3)
	await _capture(tag + "_c_menu")
	await _press(&"move_down")
	await _press(&"interact")
	await _wait(0.2)
	await _capture(tag + "_d_skills")
	await _press(&"ui_cancel")
	await _wait(0.1)
	var skill := &"slant" if opening == Encounter.Opening.PARTY_FIRST else &"vorpal_strike"
	_submit(CombatAction.use(SkillLibrary.get_skill(skill), enemy))
	await _wait(0.2)
	await _capture(tag + "_e_fx")
	await _wait(0.15)
	await _capture(tag + "_f_fx_late")
	await _until_command()
	await _wait(0.9)
	await _capture(tag + "_g_bubbles")
	var second_wind := SkillLibrary.get_skill(&"second_wind")
	_submit(CombatAction.use(second_wind, null))
	await _wait(0.25)
	await _capture(tag + "_h_heal")
	await _until_command()
	if enemy.is_alive():
		enemy.take_damage(enemy.hp - 1)
		_submit(CombatAction.use(SkillLibrary.basic_attack(), enemy))
	await _until(func() -> bool: return not CombatManager.is_running() \
			or CombatManager.is_awaiting_command(), 10.0)
	if CombatManager.is_running():
		await _end_fight()
	else:
		await _wait(1.3)


func _juice_sheet() -> void:
	var shots := ["juice_open_a_alarm", "juice_open_c_menu", "juice_open_d_skills",
			"juice_open_e_fx", "juice_open_g_bubbles", "juice_open_h_heal",
			"juice_caught_a_alarm", "juice_caught_b_clawed", "juice_caught_e_fx"]
	var cell := Vector2i(640, 360)
	var sheet := Image.create(cell.x * 3, cell.y * 3, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var shot := Image.load_from_file("%s/%s.png" % [SHOTS, shots[i]])
		if shot == null:
			continue
		shot.convert(Image.FORMAT_RGBA8)
		shot.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i((i % 3) * cell.x, (i / 3) * cell.y))
	sheet.save_png("%s/juice_sheet.png" % SHOTS)
