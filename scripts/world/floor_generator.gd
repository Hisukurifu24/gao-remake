class_name FloorGenerator
extends RefCounted
## Deterministic floor generator: a field of rooms joined by corridors, and a
## labyrinth built onto one side of it with the boss room somewhere inside.
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

## The labyrinth is a perfect maze on a grid of cells, each [constant LAB_PASSAGE]
## tiles square, with [constant LAB_WALL] tiles of wall between them. Two and two
## is what every biome can draw: a cliff gets a top and a face, the forest a row
## of 2x2 trees, the castle a band of masonry from each side. The player is 12 px
## wide, so two tiles is a passage, not a squeeze.
const LAB_PASSAGE := 2
const LAB_WALL := 2
const LAB_PITCH := LAB_PASSAGE + LAB_WALL
## The boss room, in maze cells -- 10x6 tiles, the size of a field room. Turned
## on its side half the time.
const BOSS_BLOCK := Vector2i(3, 2)
## The safe zone, in maze cells -- 6x6 tiles. Four cells the maze already joins
## to each other, opened into one room, so it adds no loop.
const CAMP_BLOCK := Vector2i(2, 2)
## How far along the way to the door the safe zone may stand, as a share of it:
## somewhere in the middle, so it is a rest on the way rather than at either end.
const CAMP_FROM := 0.3
const CAMP_TO := 0.7
## A third of the floor's monsters stand in the labyrinth: being chased into a
## dead end is what makes it a labyrinth rather than a long corridor. A third, not
## a quarter, since it grew to be the bigger half of the floor.
const LAB_MONSTER_SHARE := 3

## How often the maze carries on from its newest cell rather than branching off
## an older one. See [method _grow_maze]. With the regrowth in
## [method _carve_labyrinth], measured over 97 floors on four world seeds: the
## walk from the mouth to the door is never under 70 tiles and its median is
## about 124. At 0.5 a maze this size grew a third more dead ends, most of them
## a cell or two deep -- wrong turns you read from the junction -- and at 0.9 the
## walk ran to 368 tiles.
const MAZE_RUN := 0.75
## How many mazes may be grown looking for one with a long enough walk to the
## door and enough wrong turns, before settling for the best of them.
const MAZE_ATTEMPTS := 12
const MIN_DEAD_ENDS := 2

enum Side { EAST, WEST, SOUTH, NORTH }
const MAZE_STEPS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

const GAME_MAP_SCRIPT := preload("res://scripts/world/game_map.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const BOSS_GATE_SCENE := preload("res://scenes/world/boss_gate.tscn")
const STAIRS_SCENE := preload("res://scenes/world/floor_stairs.tscn")
const MONSTER_SCENE := preload("res://scenes/world/monster.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")

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
## How often a chest in the field is the big red one, which always holds gear and
## is trapped more often than not. The labyrinth's dead-end chest never is: the
## dead end is the price already.
const GILDED_CHANCE := 0.35
const GILDED_TRAP_CHANCE := 0.65

## Whether floors get their puzzles ([FloorPuzzles]). Off only for the floor test,
## which proves a floor without them is the same floor: they draw on a stream of
## their own and must never move anything the floor's rng put down.
static var with_puzzles := true

var _rng := RandomNumberGenerator.new()
var _definition: FloorDefinition
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
## The whole map: the field plus the labyrinth's side of it.
var _size := Vector2i.ZERO
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
		map.set(&"region", _biome.display_name)

	_ground = _new_layer(map, "Ground", false)
	_walls = _new_layer(map, "Walls", true)

	var lab := Labyrinth.new()
	var field := Rect2i(Vector2i.ZERO, definition.size)
	_lay_out(field, lab)
	field = lab.field
	for y in _size.y:
		for x in _size.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)

	var rooms := _place_rooms(field)
	for room in rooms:
		_carve(room, _biome.floor_tile)
	for i in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))

	var entry: Rect2i
	var boss_room: Rect2i
	var gate_cell: Vector2i
	if lab.has_maze():
		_carve_labyrinth(lab)
		entry = _connect_labyrinth(lab, rooms)
		boss_room = Rect2i()
		gate_cell = _center(lab.boss_room)
	else:
		entry = rooms[0]
		boss_room = _farthest_room(rooms, _center(entry))
		_carve(boss_room, _biome.special_tile)
		gate_cell = _center(boss_room)

	# One cache waits at a dead end of the labyrinth, for whoever took the wrong turn.
	var lab_chest := lab.dead_ends.size() > 0 and _definition.chest_count > 1
	var chest_cells := _pick_chest_cells(rooms, entry, boss_room,
			_definition.chest_count - (1 if lab_chest else 0))
	var field_chests := chest_cells.size()
	# Where a teleport trap sends you: a dead end deep in the labyrinth, never the
	# one with the chest in it.
	var deep: Array[Vector2i] = []
	for dead_end in lab.dead_ends:
		deep.append(_cell_rect(lab, dead_end).end - Vector2i.ONE)
	if lab_chest:
		var pick := _rng.randi() % lab.dead_ends.size()
		chest_cells.append(_cell_rect(lab, lab.dead_ends[pick]).position)
		deep.remove_at(pick)
	_scatter_decor(rooms, entry, boss_room)

	var must_reach: Array[Vector2i] = chest_cells.duplicate()
	must_reach.append(gate_cell)
	_ensure_reachable(_center(entry), must_reach)
	# Before dressing: the vault is carved out of the rock, and its walls join like any.
	var puzzles: FloorPuzzles = null
	if with_puzzles and lab.has_maze():
		puzzles = FloorPuzzles.new(_definition.floor_number, generation_seed, _biome,
				_ground, _walls, _open, field)
		puzzles.plan(rooms, entry, chest_cells, field_chests)
	MapDresser.dress(map, _biome, _ground, _walls, generation_seed)

	_add_spawns(map, _center(entry))
	for index in chest_cells.size():
		_add_chest(map, chest_cells[index], index, index < field_chests, deep)
	_add_monsters(map, rooms, entry, boss_room, lab)
	if puzzles != null:
		puzzles.place(map)
	_add_boss_gate(map, gate_cell, lab.boss_room)
	if lab.camp_room.has_area():
		_add_campfire(map, lab.camp_room)
	if _definition.floor_number > 1:
		_add_stairs(map, _center(entry) + Vector2i(-2, 0))

	if lab.has_maze():
		# Inside the labyrinth you see only what is in line of sight.
		map.set(&"dark_area", lab.rect)
		var places: Dictionary[String, Rect2i] = {"The Labyrinth": lab.rect}
		if lab.camp_room.has_area():
			places["Safe Zone"] = lab.camp_room
			map.set(&"safe_zones", [lab.camp_room] as Array[Rect2i])
			map.set_meta(&"safe_zone", lab.camp_room)
		map.set(&"landmarks", places)
		# What the tests (and nothing in the game) need to find the labyrinth again.
		map.set_meta(&"labyrinth", lab.rect)
		map.set_meta(&"labyrinth_mouth", lab.mouth)
		map.set_meta(&"boss_room", lab.boss_room)

	var player := PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.position = _world(_center(entry))
	map.add_child(player)

	return map


# --- layout ----------------------------------------------------------------

## Decides which side of the field the labyrinth stands on and how big the map is.
## The labyrinth gets a strip of its own rather than a corner of the field, so no
## corridor between two field rooms can ever cut through it: an L between two
## points stays inside their bounding box, and the field is a rectangle.
func _lay_out(field: Rect2i, lab: Labyrinth) -> void:
	lab.field = field
	_size = field.size
	var cells := _definition.labyrinth
	# The boss room may lie either way round, and must never span the maze.
	var longest := maxi(BOSS_BLOCK.x, BOSS_BLOCK.y)
	if cells.x <= longest or cells.y <= longest:
		return
	var tiles := cells * LAB_PITCH + Vector2i(LAB_WALL, LAB_WALL)
	lab.cells = cells
	lab.side = _rng.randi() % 4
	# Along the side they share, whichever is shorter is slid along the longer one;
	# what neither covers is rock. A labyrinth longer than the field is the usual
	# case -- it is meant to be the bigger half of the floor.
	var shared := 1 if lab.side == Side.EAST or lab.side == Side.WEST else 0
	var span := maxi(field.size[shared], tiles[shared])
	var field_along := _rng.randi_range(0, span - field.size[shared])
	var lab_along := _rng.randi_range(0, span - tiles[shared])
	var field_at := Vector2i.ZERO
	var lab_at := Vector2i.ZERO
	field_at[shared] = field_along
	lab_at[shared] = lab_along
	match lab.side:
		Side.EAST:
			lab_at.x = field.size.x
		Side.WEST:
			field_at.x = tiles.x
		Side.SOUTH:
			lab_at.y = field.size.y
		Side.NORTH:
			field_at.y = tiles.y
	lab.field.position = field_at
	lab.rect = Rect2i(lab_at, tiles)
	_size = lab.field.end.max(lab.rect.end)


func _place_rooms(field: Rect2i) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var size := field.size
	var attempts := _definition.room_count * 20
	while rooms.size() < _definition.room_count and attempts > 0:
		attempts -= 1
		var w := _rng.randi_range(7, 12)
		var h := _rng.randi_range(6, 9)
		if size.x - w - 3 < 2 or size.y - h - 3 < 2:
			continue
		var candidate := Rect2i(
			field.position.x + _rng.randi_range(2, size.x - w - 3),
			field.position.y + _rng.randi_range(2, size.y - h - 3),
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
			Rect2i(field.position + Vector2i(2, 2), Vector2i(8, 6)),
			Rect2i(field.end - Vector2i(11, 9), Vector2i(8, 6)),
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
	_carve_elbow(from, to, _rng.randi() % 2 == 0)


func _carve_elbow(from: Vector2i, to: Vector2i, horizontal_first: bool) -> void:
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
				if target.x >= _size.x - 1 or target.y >= _size.y - 1:
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


# --- the labyrinth ---------------------------------------------------------

## Grows a perfect maze from the mouth and carves it, the boss room included.
## Perfect -- every cell joined, no loops -- so there is exactly one way to the door.
##
## The boss room is a block of cells the maze treats as one: the first time the
## walk steps into it, every cell of it is marked visited and the walk backs out.
## So the room is a leaf of the maze's tree -- exactly one way in, nothing beyond
## it -- which is what lets the door show only once you are inside: being in the
## room means having solved the maze. It is placed before the maze is grown, among
## the positions in the *far third* from the mouth, so it is not always the far
## corner; the maze makes the walk long wherever it lands.
##
## Partway along the one way to the door there is a safe zone (see
## [method _place_camp]), so the walk always passes through it.
func _carve_labyrinth(lab: Labyrinth) -> void:
	var cells := lab.cells
	match lab.side:
		Side.EAST:
			lab.start = Vector2i(0, _rng.randi_range(0, cells.y - 1))
		Side.WEST:
			lab.start = Vector2i(cells.x - 1, _rng.randi_range(0, cells.y - 1))
		Side.SOUTH:
			lab.start = Vector2i(_rng.randi_range(0, cells.x - 1), 0)
		Side.NORTH:
			lab.start = Vector2i(_rng.randi_range(0, cells.x - 1), cells.y - 1)

	# Distance on the grid is a poor guess at distance through a maze: a room two
	# cells from the mouth can be forty tiles' walk or six. So the maze is grown,
	# measured, and grown again until the walk to the door is at least the grid's
	# width plus its height -- every attempt from the same seeded stream.
	var wanted := cells.x + cells.y - 2
	var best_score := -1
	for _attempt in MAZE_ATTEMPTS:
		var block_size := BOSS_BLOCK if _rng.randf() < 0.5 else Vector2i(BOSS_BLOCK.y, BOSS_BLOCK.x)
		var block := _place_block(cells, lab.start, block_size)
		var links := _grow_maze(cells, lab.start, block)
		var steps := _steps_to(links, lab.start, block)
		var camp := _place_camp(links, lab.start, block, cells)
		var branchy := _dead_ends(links, lab.start, block, camp).size() >= MIN_DEAD_ENDS
		# A safe zone beats branchy beats long: a long maze with no wrong turns
		# is a corridor, and one with nowhere to rest is a war of attrition.
		var score := steps + (1000 if branchy else 0) + (2000 if camp.has_area() else 0)
		if score > best_score:
			best_score = score
			lab.block = block
			lab.links = links
			lab.camp = camp
		if branchy and steps >= wanted and camp.has_area():
			break

	for y in cells.y:
		for x in cells.x:
			var cell := Vector2i(x, y)
			if lab.block.has_point(cell):
				continue
			_carve(_cell_rect(lab, cell), _biome.floor_tile)
			for other: Vector2i in lab.links.get(cell, []):
				# Each passage once, from its top-left end.
				if other.x > cell.x or other.y > cell.y or lab.block.has_point(other):
					_carve(_gap_rect(lab, cell, other), _biome.floor_tile)
	lab.dead_ends = _dead_ends(lab.links, lab.start, lab.block, lab.camp)
	var corner := _cell_rect(lab, lab.block.position)
	lab.boss_room = Rect2i(corner.position,
			lab.block.size * LAB_PITCH - Vector2i(LAB_WALL, LAB_WALL))
	_carve(lab.boss_room, _biome.special_tile)
	if lab.camp.has_area():
		lab.camp_room = Rect2i(_cell_rect(lab, lab.camp.position).position,
				lab.camp.size * LAB_PITCH - Vector2i(LAB_WALL, LAB_WALL))
		_carve(lab.camp_room, _biome.floor_tile)


## A growing tree: mostly carry on from the newest cell, sometimes branch off an
## older one. Newest-only is a depth-first maze -- one long winding path with a
## dead end or two, a corridor with corners; branching is what gives the
## labyrinth its wrong turns, and too much of it makes the way to the door short.
func _grow_maze(cells: Vector2i, start: Vector2i, block: Rect2i) -> Dictionary[Vector2i, Array]:
	var links: Dictionary[Vector2i, Array] = {}
	var visited: Dictionary[Vector2i, bool] = {start: true}
	var active: Array[Vector2i] = [start]
	while not active.is_empty():
		var index := active.size() - 1 if _rng.randf() < MAZE_RUN else _rng.randi() % active.size()
		var cell: Vector2i = active[index]
		var options: Array[Vector2i] = []
		for step in MAZE_STEPS:
			var next := cell + step
			if Rect2i(Vector2i.ZERO, cells).has_point(next) and not visited.has(next):
				options.append(next)
		if options.is_empty():
			active.remove_at(index)
			continue
		var next: Vector2i = options[_rng.randi() % options.size()]
		Labyrinth.join(links, cell, next)
		if block.has_point(next):
			for y in range(block.position.y, block.end.y):
				for x in range(block.position.x, block.end.x):
					visited[Vector2i(x, y)] = true
		else:
			visited[next] = true
			active.append(next)
	return links


## How many cells you walk from [param start] to step into [param block].
func _steps_to(links: Dictionary[Vector2i, Array], start: Vector2i, block: Rect2i) -> int:
	var steps: Dictionary[Vector2i, int] = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if block.has_point(cell):
			return steps[cell]
		for next: Vector2i in links.get(cell, []):
			if not steps.has(next):
				steps[next] = steps[cell] + 1
				queue.append(next)
	return 0


## The cells with one way in and no way on, in reading order. The mouth's cell,
## the boss room and the safe zone don't count: one has the field behind it, the
## other is the point, and the last is one room once it is opened up.
func _dead_ends(links: Dictionary[Vector2i, Array], start: Vector2i, block: Rect2i,
		camp: Rect2i) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	for cell: Vector2i in links:
		if cell != start and not block.has_point(cell) and not camp.has_point(cell) \
				and links[cell].size() == 1:
			ends.append(cell)
	ends.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return ends


## Where the safe zone goes, in cells: a [constant CAMP_BLOCK] the one way from
## [param start] to the boss room walks through, nearest the middle of it. Only
## blocks whose four cells the maze already joins to each other qualify -- three
## links inside the block -- since opening any other into one room would join two
## branches of the tree and the maze would stop being perfect. Empty if no block
## on the way qualifies; [method _carve_labyrinth] grows another maze.
##
## Takes nothing from the rng: the maze decides it.
func _place_camp(links: Dictionary[Vector2i, Array], start: Vector2i, block: Rect2i,
		cells: Vector2i) -> Rect2i:
	var path := _path_to(links, start, block)
	var lowest := ceili(path.size() * CAMP_FROM)
	var highest := floori(path.size() * CAMP_TO)
	var middle := path.size() / 2.0
	var best := Rect2i()
	var best_off := INF
	for i in range(lowest, highest + 1):
		if i >= path.size() or absf(i - middle) >= best_off:
			continue
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var camp := Rect2i(path[i] + corner, CAMP_BLOCK)
			if not Rect2i(Vector2i.ZERO, cells).encloses(camp) or camp.has_point(start):
				continue
			# Never beside the boss room: its doorway must not open into the camp.
			if camp.grow(1).intersects(block) or _links_inside(links, camp) != 3:
				continue
			best = camp
			best_off = absf(i - middle)
			break
	return best


## The cells from [param start] up to (not into) [param block], in walking order.
func _path_to(links: Dictionary[Vector2i, Array], start: Vector2i, block: Rect2i) -> Array[Vector2i]:
	var parent: Dictionary[Vector2i, Vector2i] = {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var last := start
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if block.has_point(cell):
			last = parent[cell]
			break
		for next: Vector2i in links.get(cell, []):
			if not parent.has(next):
				parent[next] = cell
				queue.append(next)
	var path: Array[Vector2i] = [last]
	while path[0] != start:
		path.push_front(parent[path[0]])
	return path


## How many links join the cells of [param rect] to each other.
func _links_inside(links: Dictionary[Vector2i, Array], rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			for next: Vector2i in links.get(cell, []):
				if rect.has_point(next) and (next.x > cell.x or next.y > cell.y):
					count += 1
	return count


## Where the boss room goes: a seeded pick among the positions in the far third
## by distance from the mouth. Never spans the whole maze in either
## direction, so the cells round it always stay connected.
func _place_block(cells: Vector2i, start: Vector2i, block_size: Vector2i) -> Rect2i:
	var candidates: Array[Rect2i] = []
	var distances: Array[int] = []
	for y in range(0, cells.y - block_size.y + 1):
		for x in range(0, cells.x - block_size.x + 1):
			var block := Rect2i(Vector2i(x, y), block_size)
			var nearest := Vector2i(clampi(start.x, block.position.x, block.end.x - 1),
					clampi(start.y, block.position.y, block.end.y - 1))
			candidates.append(block)
			distances.append(absi(nearest.x - start.x) + absi(nearest.y - start.y))
	var sorted := distances.duplicate()
	sorted.sort()
	var threshold: int = maxi(1, sorted[sorted.size() * 2 / 3])
	var far: Array[Rect2i] = []
	for i in candidates.size():
		if distances[i] >= threshold:
			far.append(candidates[i])
	return far[_rng.randi() % far.size()]


## Opens the labyrinth's mouth onto the field and runs a corridor to it from the
## nearest room. Returns the room the player arrives in: a seeded pick from the
## rooms in the far half from the mouth, so the walk crosses the field first.
func _connect_labyrinth(lab: Labyrinth, rooms: Array[Rect2i]) -> Rect2i:
	# The gap through the labyrinth's own wall, from its first cell to the field;
	# then a doorstep two cells out from it and square to it, where a corridor's
	# three-cell width touches both of the mouth's rows (or columns).
	var first := _cell_rect(lab, lab.start)
	var across := Vector2i(LAB_WALL, LAB_PASSAGE)
	var down := Vector2i(LAB_PASSAGE, LAB_WALL)
	var doorstep: Vector2i
	match lab.side:
		Side.EAST:
			lab.mouth = Rect2i(first.position - Vector2i(LAB_WALL, 0), across)
			doorstep = Vector2i(lab.mouth.position.x - 2, lab.mouth.position.y)
		Side.WEST:
			lab.mouth = Rect2i(first.position + Vector2i(LAB_PASSAGE, 0), across)
			doorstep = Vector2i(lab.mouth.end.x + 1, lab.mouth.position.y)
		Side.SOUTH:
			lab.mouth = Rect2i(first.position - Vector2i(0, LAB_WALL), down)
			doorstep = Vector2i(lab.mouth.position.x, lab.mouth.position.y - 2)
		Side.NORTH:
			lab.mouth = Rect2i(first.position + Vector2i(0, LAB_PASSAGE), down)
			doorstep = Vector2i(lab.mouth.position.x, lab.mouth.end.y + 1)
	_carve(lab.mouth, _biome.floor_tile)

	var by_distance := rooms.duplicate()
	by_distance.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return (_center(a) - doorstep).length_squared() < (_center(b) - doorstep).length_squared())
	# Across the field first, then along its edge to the doorstep: the labyrinth
	# stands beyond that edge, so neither leg can cut into it.
	_carve_elbow(_center(by_distance[0]), doorstep, lab.side == Side.EAST or lab.side == Side.WEST)

	var far_half := by_distance.slice(by_distance.size() / 2)
	return far_half[_rng.randi() % far_half.size()]


func _cell_rect(lab: Labyrinth, cell: Vector2i) -> Rect2i:
	return Rect2i(lab.rect.position + Vector2i(LAB_WALL, LAB_WALL) + cell * LAB_PITCH,
			Vector2i(LAB_PASSAGE, LAB_PASSAGE))


## The wall between two neighbouring cells.
func _gap_rect(lab: Labyrinth, a: Vector2i, b: Vector2i) -> Rect2i:
	var low := _cell_rect(lab, Vector2i(mini(a.x, b.x), mini(a.y, b.y)))
	if a.y == b.y:
		return Rect2i(low.position + Vector2i(LAB_PASSAGE, 0), Vector2i(LAB_WALL, LAB_PASSAGE))
	return Rect2i(low.position + Vector2i(0, LAB_PASSAGE), Vector2i(LAB_PASSAGE, LAB_WALL))


# --- contents --------------------------------------------------------------

func _pick_chest_cells(rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i,
		count: int) -> Array[Vector2i]:
	var candidates: Array[Rect2i] = []
	for room in rooms:
		if room != entry and room != boss_room:
			candidates.append(room)
	if candidates.is_empty():
		return []

	var cells: Array[Vector2i] = []
	for i in mini(count, candidates.size()):
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


## [param may_gild] for a chest in the field; [param deep] is where a teleport
## trap may send you, in cells -- empty for none, and the trap is an alarm.
func _add_chest(map: Node2D, cell: Vector2i, index: int, may_gild: bool,
		deep: Array[Vector2i]) -> void:
	var chest := CHEST_SCENE.instantiate()
	chest.name = "Chest%d" % index
	chest.position = _world(cell)
	chest.set(&"floor_number", _definition.floor_number)
	# Drawn from the floor's own seeded rng, so floor 37's second chest holds the
	# same thing every time it is generated -- same rule as everything else here.
	if may_gild and _rng.randf() < GILDED_CHANCE:
		chest.set(&"gilded", true)
		chest.set(&"item_id", CHEST_GEAR[_rng.randi() % CHEST_GEAR.size()])
		chest.set(&"amount", 1)
		if _rng.randf() < GILDED_TRAP_CHANCE:
			if not deep.is_empty() and _rng.randf() < 0.5:
				chest.set(&"trap", Chest.Trap.TELEPORT)
				chest.set(&"trap_target", _world(deep[_rng.randi() % deep.size()]))
			else:
				chest.set(&"trap", Chest.Trap.ALARM)
	elif _rng.randf() < CHEST_GEAR_CHANCE:
		chest.set(&"item_id", CHEST_GEAR[_rng.randi() % CHEST_GEAR.size()])
		chest.set(&"amount", 1)
	else:
		chest.set(&"item_id", CHEST_CONSUMABLES[_rng.randi() % CHEST_CONSUMABLES.size()])
		chest.set(&"amount", _rng.randi_range(1, 3))
	chest.set(&"opened_flag", StringName("floor_%d_chest_%d" % [_definition.floor_number, index]))
	map.add_child(chest)


## Scatters the floor's monsters through the rooms between the entrance and the
## boss, and a share of them through the labyrinth's passages. They have no
## collision, so this cannot make a floor unreachable -- the flood fill in
## test/floor_test.gd never sees them.
func _add_monsters(map: Node2D, rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i,
		lab: Labyrinth) -> void:
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
	var passages: Array[Rect2i] = []
	if lab.has_maze():
		for cell: Vector2i in lab.links:
			if cell != lab.start and not lab.block.has_point(cell) and not lab.camp.has_point(cell):
				passages.append(_cell_rect(lab, cell))
		passages.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
			return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))

	var count := FloorTuning.monster_count(_definition.floor_number)
	var in_lab := count / LAB_MONSTER_SHARE if not passages.is_empty() else 0
	var placed: Array[Vector2i] = []
	for index in count:
		var cell: Vector2i
		if index < in_lab:
			var passage: Rect2i = passages[_rng.randi() % passages.size()]
			cell = passage.position + Vector2i(_rng.randi_range(0, 1), _rng.randi_range(0, 1))
		else:
			var room: Rect2i = candidates[_rng.randi() % candidates.size()]
			cell = Vector2i(
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


## [param hidden_in] is the boss room the door hides in, in cells; empty puts it
## in plain view.
func _add_boss_gate(map: Node2D, cell: Vector2i, hidden_in: Rect2i) -> void:
	var gate := BOSS_GATE_SCENE.instantiate()
	gate.name = "BossGate"
	gate.position = _world(cell)
	gate.set(&"floor_number", _definition.floor_number)
	gate.set(&"boss_name", _definition.boss_name)
	gate.set(&"display_name", "the labyrinth door")
	if hidden_in.has_area():
		gate.set(&"reveal_area", Rect2(hidden_in.position * TILE, hidden_in.size * TILE))
	map.add_child(gate)


## The fire at the heart of the safe zone, on the room's middle -- where the
## pillar between its four cells stood.
func _add_campfire(map: Node2D, room: Rect2i) -> void:
	var fire := CAMPFIRE_SCENE.instantiate()
	fire.name = "Campfire"
	fire.position = Vector2((room.position.x + room.size.x / 2) * TILE,
			(room.position.y + room.size.y / 2 + 1) * TILE)
	map.add_child(fire)


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


## Everything one floor's labyrinth is, while it is being built.
class Labyrinth:
	## Where the rooms go -- the map minus the labyrinth's strip.
	var field := Rect2i()
	## The labyrinth in tiles, its outer wall included. Empty when the floor has none.
	var rect := Rect2i()
	var cells := Vector2i.ZERO
	var side := 0
	## The cell the maze is grown from, beside the mouth.
	var start := Vector2i.ZERO
	## The gap through the outer wall, in tiles: the only way in.
	var mouth := Rect2i()
	## The boss room in cells, and in tiles.
	var block := Rect2i()
	var boss_room := Rect2i()
	## The safe zone in cells, and in tiles. Empty when no maze grown had room for one.
	var camp := Rect2i()
	var camp_room := Rect2i()
	## cell -> the cells it is joined to.
	var links: Dictionary[Vector2i, Array] = {}
	var dead_ends: Array[Vector2i] = []

	func has_maze() -> bool:
		return rect.has_area()

	static func join(into: Dictionary[Vector2i, Array], a: Vector2i, b: Vector2i) -> void:
		if not into.has(a):
			into[a] = []
		if not into.has(b):
			into[b] = []
		into[a].append(b)
		into[b].append(a)
