extends "res://tools/screenshot.gd"
## M5.5 §6.1, the fight-on-the-map spike: one monster fight on Floor 2, staged
## in a room, in a field corridor and in a dark labyrinth passage, at zoom 1 and
## zoom 2 -- the six shots the go/no-go gate is decided on.
##
##     "$GODOT" --path . res://tools/battle_spike.tscn
##
## Throwaway: goes when the spike is decided, its shots folded into screenshot.gd.

const FLOOR := 2


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _until(func() -> bool: return not GameState.is_input_locked(), 10.0)

	GameState.level = 3
	GameState.attack = 14
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
	var corridor := _corridor_cell(map, walls, lab)
	for zoom in [1.0, 2.0]:
		BattleStage.zoom = zoom
		await _fight_at(map, player, monsters.pop_back(), walls, room[0], room[1], "room", zoom)
		await _fight_at(map, player, monsters.pop_back(), walls, corridor[0], corridor[1], "corridor", zoom)

	# The passage: walked to, so the dark has lit the way there and remembers it.
	var path := _path_within(walls, walls.local_to_map(player.position),
			map.get_meta(&"boss_room").position, walls.get_used_rect())
	var inside: Array[int] = []
	for i in path.size() - 1:
		if lab.has_point(path[i]) and not (map.get_meta(&"labyrinth_mouth") as Rect2i).has_point(path[i]):
			inside.append(i)
	var stop := inside[inside.size() / 2]
	GameState.push_input_lock()
	for i in stop + 1:
		player.global_position = walls.map_to_local(path[i])
		await get_tree().physics_frame
	GameState.pop_input_lock()
	for zoom in [1.0, 2.0]:
		BattleStage.zoom = zoom
		await _fight_at(map, player, monsters.pop_back(), walls, path[stop],
				path[stop + 1] - path[stop], "passage", zoom)
		GameState.push_input_lock()
		player.global_position = walls.map_to_local(path[stop])
		await get_tree().physics_frame
		GameState.pop_input_lock()

	_contact_sheet()
	print("spike shots in ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


## Stands the player on [param cell], brings [param monster] in from
## [param toward], and lets it start the fight the way a chase ends.
func _fight_at(map: GameMap, player: Player, monster: Monster, walls: TileMapLayer,
		cell: Vector2i, toward: Vector2i, where: String, zoom: float) -> void:
	var tag := "spike_%s_x%d" % [where, int(zoom)]
	GameState.push_input_lock()
	player.global_position = walls.map_to_local(cell) + Vector2(0, 4)
	player.facing = Vector2(toward)
	monster.global_position = player.global_position + Vector2(toward) * 12.0
	await _wait(0.3)
	GameState.pop_input_lock()
	monster.call(&"_engage", Encounter.Opening.NORMAL)
	await _wait(0.2)
	await _capture(tag + "a_intro")
	await _until_command()
	await _wait(0.2)
	await _capture(tag + "b_menu")
	var target := CombatManager.living_enemies()[0]
	_submit(CombatAction.use(SkillLibrary.get_skill(&"slant"), target))
	await _wait(0.14)
	await _capture(tag + "c_strike")
	await _wait(0.3)
	await _capture(tag + "d_hit")
	await _until_command()
	await _end_fight()


## The middle of the field's biggest open space: a cell with floor five each way.
func _room_cell(map: GameMap, walls: TileMapLayer, lab: Rect2i, player_at: Vector2) -> Array:
	var used := walls.get_used_rect()
	for y in range(used.position.y + 3, used.end.y - 3):
		for x in range(used.position.x + 3, used.end.x - 3):
			var cell := Vector2i(x, y)
			if lab.grow(2).has_point(cell) or Vector2(cell).distance_to(walls.local_to_map(player_at)) < 8.0:
				continue
			var open := true
			for dy in range(-3, 4):
				for dx in range(-4, 5):
					if not map.is_standable(cell + Vector2i(dx, dy)):
						open = false
			if open:
				return [cell, Vector2i.RIGHT]
	return [used.get_center(), Vector2i.RIGHT]


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
	return [used.get_center(), Vector2i.RIGHT]


func _run(map: GameMap, cell: Vector2i, axis: Vector2i) -> int:
	var count := 1
	for sign in [1, -1]:
		var at: Vector2i = cell + axis * sign
		while map.is_standable(at) and count < 40:
			count += 1
			at += axis * sign
	return count


## The six shots on one sheet, half size: rows are the places, columns the zooms.
func _contact_sheet() -> void:
	var cell := Vector2i(640, 360)
	var sheet := Image.create(cell.x * 2, cell.y * 3, false, Image.FORMAT_RGBA8)
	for row in 3:
		for column in 2:
			var path := "%s/spike_%s_x%dd_hit.png" % [SHOTS, ["room", "corridor", "passage"][row], column + 1]
			var shot := Image.load_from_file(path)
			if shot == null:
				continue
			shot.convert(Image.FORMAT_RGBA8)
			shot.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i(column * cell.x, row * cell.y))
	sheet.save_png("%s/spike_sheet.png" % SHOTS)
