extends "res://tools/screenshot.gd"
## M5.5 §6 step 4: bosses step out of their doors. Every authored boss and two
## generated ones, challenged from the doorstep and fought on the map -- the
## shots the boss zoom is decided on.
##
##     "$GODOT" --path . res://tools/boss_spike.tscn
##
## Throwaway, like battle_spike.gd: its shots fold into screenshot.gd in step 7.

## [floor, the map to fight on (empty: the floor's own), a name for the shots]
## In floor order: each fight clears every floor below it, and a cleared door
## offers the way up instead of a fight.
const FIGHTS := [
	[1, "res://scenes/world/field.tscn", "illfang"],
	[2, "", "gen_f2"],
	[10, "", "nerith"],
	[25, "", "karvos"],
	[52, "", "gen_f52_escort"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)

	GameState.level = 60
	GameState.attack = 14
	GameState.defense = 100000
	GameState.set_hp(GameState.total_max_hp())
	for fight: Array in FIGHTS:
		await _boss_fight(fight[0], fight[1], fight[2])

	_contact_sheet()
	print("boss shots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


func _boss_fight(floor_number: int, map_path: String, tag: String) -> void:
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	if map_path.is_empty():
		SceneRouter.enter_floor(floor_number)
	else:
		SceneRouter.change_map(map_path, &"default")
	await _until(func() -> bool:
		var arrived := SceneRouter.current_map() as GameMap
		return arrived != null and arrived.floor_number == floor_number \
				and (map_path.is_empty() or arrived.scene_file_path == map_path) \
				and not GameState.is_input_locked(), 10.0)
	await _wait(0.3)

	var map := SceneRouter.current_map() as GameMap
	var walls := map.get_node("Walls") as TileMapLayer
	var gate := map.get_node("BossGate") as BossGate
	var player := map.get_node("Player") as Player
	gate.reveal()
	await _dismiss()
	map.refresh_solids()
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
	await _capture("boss_%s_0_door" % tag)

	gate.interact(player)
	await _dismiss()
	await _wait(0.25)
	await _capture("boss_%s_a_stepout" % tag)
	await _until_command()
	await _wait(0.3)
	await _capture("boss_%s_b_menu" % tag)
	var boss := CombatManager.living_enemies()[0]
	if CombatManager.living_enemies().size() > 1:
		# Attack, onto the target list: the pointer over the boss.
		await _press(&"interact")
		await _wait(0.2)
		await _capture("boss_%s_c_target" % tag)
		await _press(&"ui_cancel")
	_submit(CombatAction.use(SkillLibrary.get_skill(&"slant"), boss))
	await _wait(0.4)
	await _capture("boss_%s_d_hit" % tag)
	await _until_command()
	for enemy in CombatManager.living_enemies():
		if enemy != boss:
			enemy.take_damage(enemy.hp)
	boss.take_damage(boss.hp - 1)
	_submit(CombatAction.use(SkillLibrary.basic_attack(), boss))
	await _wait(0.4)
	await _capture("boss_%s_e_fall" % tag)
	await _until(func() -> bool: return not CombatManager.is_running() \
			or CombatManager.is_awaiting_command(), 10.0)
	if CombatManager.is_running():
		await _end_fight()
	await _wait(1.0)
	await _dismiss()
	await _capture("boss_%s_f_after" % tag)


## Reads through whatever box is up.
func _dismiss() -> void:
	await _frames(4)
	for _i in 12:
		if not DialogueRunner.is_running():
			return
		await _wait(0.3)
		await _press(&"interact")


## Menu and hit for each fight, half size: rows are the bosses.
func _contact_sheet() -> void:
	var cell := Vector2i(640, 360)
	var columns := ["b_menu", "d_hit"]
	var sheet := Image.create(cell.x * columns.size(), cell.y * FIGHTS.size(), false, Image.FORMAT_RGBA8)
	for row in FIGHTS.size():
		for column in columns.size():
			var shot := Image.load_from_file("%s/boss_%s_%s.png" % [SHOTS, FIGHTS[row][2], columns[column]])
			if shot == null:
				continue
			shot.convert(Image.FORMAT_RGBA8)
			shot.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i(column * cell.x, row * cell.y))
	sheet.save_png("%s/boss_sheet.png" % SHOTS)
