class_name FloorGenerator
extends RefCounted
## Deterministic labyrinth generator: rooms joined by corridors.
##
## Produces the same node shape as an authored map (Ground / Walls /
## SpawnPoints / Player + interactables), so SceneRouter, GameMap and the camera
## can't tell a generated floor from a hand-built one.
##
## Determinism is the point: the seed comes from (world_seed, floor_number), so
## floor 37 is always the same floor 37 within a save. Quests can reference it,
## NPCs can describe it, and bug reports reproduce.

const TILE := 16
const SOURCE_ID := 0
const CORRIDOR_WIDTH := 3
## Decor never lands within this many tiles of a room edge, which keeps it clear
## of corridor mouths. The flood fill below is the belt-and-braces check.
const DECOR_MARGIN := 2

const GAME_MAP_SCRIPT := preload("res://scripts/world/game_map.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const BOSS_GATE_SCENE := preload("res://scenes/world/boss_gate.tscn")
const STAIRS_SCENE := preload("res://scenes/world/floor_stairs.tscn")
const MONSTER_SCENE := preload("res://scenes/world/monster.tscn")

## What a floor cache can hold. Consumables are the staple -- they are what makes
## walking off the main line worth the monsters in the way. Gear is the rarer
## payoff, and the same few pieces recur because the roster is small; a chest is
## a supply drop, not a loot table.
const CHEST_CONSUMABLES: Array[StringName] = [
	&"small_potion", &"health_potion", &"antidote", &"whetstone",
]
const CHEST_GEAR: Array[StringName] = [
	&"bronze_sword", &"kobold_blade", &"leather_coat",
	&"guard_ring", &"swift_charm", &"blackwyrm_coat",
]
## How often a chest holds gear rather than supplies.
const CHEST_GEAR_CHANCE := 0.3

var _rng := RandomNumberGenerator.new()
var _definition: FloorDefinition
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
## Every carved (walkable) cell, minus whatever decor later blocks.
var _open: Dictionary[Vector2i, bool] = {}
var _decor: Array[Vector2i] = []


static func generate(definition: FloorDefinition, generation_seed: int) -> Node2D:
	return FloorGenerator.new()._build(definition, generation_seed)


func _build(definition: FloorDefinition, generation_seed: int) -> Node2D:
	_definition = definition
	_biome = definition.biome
	_rng.seed = generation_seed

	var map := Node2D.new()
	map.name = "Floor%02d" % definition.floor_number
	map.set_script(GAME_MAP_SCRIPT)
	map.set(&"map_id", StringName("floor_%d" % definition.floor_number))
	map.set(&"display_name", definition.label())
	map.set(&"floor_number", definition.floor_number)
	if _biome:
		map.modulate = _biome.ambient_tint

	_ground = _new_layer(map, "Ground", false)
	_walls = _new_layer(map, "Walls", true)

	var size := definition.size
	for y in size.y:
		for x in size.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)

	var rooms := _place_rooms(size)
	for room in rooms:
		_carve(room, _biome.floor_tile)
	for i in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))

	var entry := rooms[0]
	var boss_room := _farthest_room(rooms, _center(entry))
	_carve(boss_room, _biome.special_tile)

	var chest_cells := _pick_chest_cells(rooms, entry, boss_room)
	_scatter_decor(rooms, entry, boss_room)

	var must_reach: Array[Vector2i] = chest_cells.duplicate()
	must_reach.append(_center(boss_room))
	_ensure_reachable(_center(entry), must_reach)

	_add_spawns(map, _center(entry))
	for index in chest_cells.size():
		_add_chest(map, chest_cells[index], index)
	_add_monsters(map, rooms, entry, boss_room)
	_add_boss_gate(map, _center(boss_room))
	if _definition.floor_number > 1:
		_add_stairs(map, _center(entry) + Vector2i(-2, 0))

	var player := PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.position = _world(_center(entry))
	map.add_child(player)

	return map


# --- layout ----------------------------------------------------------------

func _place_rooms(size: Vector2i) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var attempts := _definition.room_count * 20
	while rooms.size() < _definition.room_count and attempts > 0:
		attempts -= 1
		var w := _rng.randi_range(7, 12)
		var h := _rng.randi_range(6, 9)
		if size.x - w - 3 < 2 or size.y - h - 3 < 2:
			continue
		var candidate := Rect2i(
			_rng.randi_range(2, size.x - w - 3),
			_rng.randi_range(2, size.y - h - 3),
			w, h)
		var blocked := false
		for existing in rooms:
			if existing.grow(3).intersects(candidate):
				blocked = true
				break
		if not blocked:
			rooms.append(candidate)

	# A floor with one room has no dungeon in it. Only reachable if the size
	# curve is misconfigured, but a boss with no approach is worse than ugly.
	if rooms.size() < 2:
		rooms = [
			Rect2i(2, 2, 8, 6),
			Rect2i(size.x - 11, size.y - 9, 8, 6),
		]
	return rooms


func _carve(room: Rect2i, tile: int) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			_walls.erase_cell(cell)
			var painted := tile
			if tile == _biome.floor_tile and _rng.randf() < 0.08:
				painted = _biome.floor_alt_tile
			_paint(_ground, cell, painted)
			_open[cell] = true


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	# L-shaped, with the elbow order chosen by the seed so floors don't all
	# share the same silhouette.
	var horizontal_first := _rng.randi() % 2 == 0
	var elbow := Vector2i(to.x, from.y) if horizontal_first else Vector2i(from.x, to.y)
	_carve_line(from, elbow)
	_carve_line(elbow, to)


func _carve_line(from: Vector2i, to: Vector2i) -> void:
	var half := CORRIDOR_WIDTH / 2
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell := from
	while true:
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var target := cell + Vector2i(dx, dy)
				if target.x < 1 or target.y < 1:
					continue
				if target.x >= _definition.size.x - 1 or target.y >= _definition.size.y - 1:
					continue
				if not _open.has(target):
					_walls.erase_cell(target)
					_paint(_ground, target, _biome.path_tile)
					_open[target] = true
		if cell == to:
			break
		# Axis-aligned: only one of the two components is ever non-zero here.
		cell += Vector2i(step.x, 0) if cell.x != to.x else Vector2i(0, step.y)


func _farthest_room(rooms: Array[Rect2i], from: Vector2i) -> Rect2i:
	var best := rooms[rooms.size() - 1]
	var best_distance := -1.0
	for room in rooms:
		var distance := Vector2(_center(room) - from).length()
		if distance > best_distance:
			best_distance = distance
			best = room
	return best


# --- contents --------------------------------------------------------------

func _pick_chest_cells(rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i) -> Array[Vector2i]:
	var candidates: Array[Rect2i] = []
	for room in rooms:
		if room != entry and room != boss_room:
			candidates.append(room)
	if candidates.is_empty():
		return []

	var cells: Array[Vector2i] = []
	for i in mini(_definition.chest_count, candidates.size()):
		var room: Rect2i = candidates[_rng.randi() % candidates.size()]
		var cell := Vector2i(
			_rng.randi_range(room.position.x + 1, room.end.x - 2),
			_rng.randi_range(room.position.y + 1, room.end.y - 2))
		if cell not in cells:
			cells.append(cell)
	return cells


func _scatter_decor(rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i) -> void:
	for room in rooms:
		if room == entry or room == boss_room:
			continue
		var inner := room.grow(-DECOR_MARGIN)
		if inner.size.x <= 0 or inner.size.y <= 0:
			continue
		for y in range(inner.position.y, inner.end.y):
			for x in range(inner.position.x, inner.end.x):
				var roll := _rng.randf()
				var tile := -1
				if roll < _definition.obstacle_density:
					tile = _biome.obstacle_tile
				elif roll < _definition.obstacle_density + _definition.liquid_density * 0.12:
					tile = _biome.liquid_tile
				if tile >= 0:
					var cell := Vector2i(x, y)
					_paint(_walls, cell, tile)
					_open.erase(cell)
					_decor.append(cell)


## Belt and braces: rooms and corridors are connected by construction, so if
## decor ever severs the floor we drop all of it rather than ship an
## unfinishable dungeon.
func _ensure_reachable(from: Vector2i, required: Array[Vector2i]) -> void:
	if _reaches_all(from, required):
		return
	for cell in _decor:
		_walls.erase_cell(cell)
		_paint(_ground, cell, _biome.floor_tile)
		_open[cell] = true
	_decor.clear()


func _reaches_all(from: Vector2i, required: Array[Vector2i]) -> bool:
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next) or not _open.has(next):
				continue
			seen[next] = true
			queue.append(next)
	for cell in required:
		if not seen.has(cell):
			return false
	return true


func _add_spawns(map: Node2D, entry: Vector2i) -> void:
	var holder := Node2D.new()
	holder.name = "SpawnPoints"
	map.add_child(holder)
	for spawn_name in ["default", "from_below", "from_above"]:
		var marker := Marker2D.new()
		marker.name = spawn_name
		marker.position = _world(entry)
		holder.add_child(marker)


func _add_chest(map: Node2D, cell: Vector2i, index: int) -> void:
	var chest := CHEST_SCENE.instantiate()
	chest.name = "Chest%d" % index
	chest.position = _world(cell)
	# Drawn from the floor's own seeded rng, so floor 37's second chest holds the
	# same thing every time it is generated -- same rule as everything else here.
	if _rng.randf() < CHEST_GEAR_CHANCE:
		chest.set(&"item_id", CHEST_GEAR[_rng.randi() % CHEST_GEAR.size()])
		chest.set(&"amount", 1)
	else:
		chest.set(&"item_id", CHEST_CONSUMABLES[_rng.randi() % CHEST_CONSUMABLES.size()])
		chest.set(&"amount", _rng.randi_range(1, 3))
	chest.set(&"opened_flag", StringName("floor_%d_chest_%d" % [_definition.floor_number, index]))
	map.add_child(chest)


## Scatters the floor's monsters through the rooms between the entrance and the
## boss. They have no collision, so this cannot make a floor unreachable -- the
## flood fill in test/floor_test.gd never sees them.
func _add_monsters(map: Node2D, rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i) -> void:
	var pool := Bestiary.pool_for_floor(_definition.floor_number)
	if pool.is_empty():
		return

	var candidates: Array[Rect2i] = []
	for room in rooms:
		if room != entry and room != boss_room:
			candidates.append(room)
	# A two-room floor still has to be levellable, so fall back to the entrance.
	if candidates.is_empty():
		candidates.append(entry)

	var placed: Array[Vector2i] = []
	for index in FloorTuning.monster_count(_definition.floor_number):
		var room: Rect2i = candidates[_rng.randi() % candidates.size()]
		var cell := Vector2i(
			_rng.randi_range(room.position.x + 1, room.end.x - 2),
			_rng.randi_range(room.position.y + 1, room.end.y - 2))
		if cell in placed or not _open.has(cell):
			continue
		placed.append(cell)

		var monster := MONSTER_SCENE.instantiate()
		monster.name = "Monster%d" % index
		monster.position = _world(cell)
		monster.set(&"enemy", pool[_rng.randi() % pool.size()])
		monster.set(&"level", _definition.enemy_level)
		monster.set(&"floor_number", _definition.floor_number)
		map.add_child(monster)


func _add_boss_gate(map: Node2D, cell: Vector2i) -> void:
	var gate := BOSS_GATE_SCENE.instantiate()
	gate.name = "BossGate"
	gate.position = _world(cell)
	gate.set(&"floor_number", _definition.floor_number)
	gate.set(&"boss_name", _definition.boss_name)
	gate.set(&"display_name", "the labyrinth door")
	map.add_child(gate)


func _add_stairs(map: Node2D, cell: Vector2i) -> void:
	var stairs := STAIRS_SCENE.instantiate()
	stairs.name = "StairsDown"
	stairs.position = _world(cell)
	stairs.set(&"target_floor", _definition.floor_number - 1)
	stairs.set(&"display_name", "the stairs down")
	map.add_child(stairs)


# --- plumbing --------------------------------------------------------------

func _new_layer(map: Node2D, layer_name: String, collides: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _biome.tile_set
	layer.collision_enabled = collides
	map.add_child(layer)
	return layer


func _paint(layer: TileMapLayer, cell: Vector2i, tile: int) -> void:
	layer.set_cell(cell, SOURCE_ID, Vector2i(tile, 0))


func _center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
