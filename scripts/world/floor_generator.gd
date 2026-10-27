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
const TELEPORT_GATE_SCENE := preload("res://scenes/world/teleport_gate.tscn")
const NPC_SCENE := preload("res://scenes/world/npc.tscn")
const WAYSTONE_SCENE := preload("res://scenes/world/waystone.tscn")
const SEAL_SCENE := preload("res://scenes/world/sealed_door.tscn")
const DUNGEON_SCRIPT := "res://scripts/world/dungeon_generator.gd"
## Where the teleport gate stands from the entrance room's centre, and where you
## arrive through it: off the centre's row and column, which is where the room's
## three-wide corridors run, so the gate's base never narrows one below two.
const GATE_OFFSET := Vector2i(2, -2)
const GATE_ARRIVAL := Vector2i(2, -1)
## Where the stairs down stand from the entrance room's centre.
const STAIRS_OFFSET := Vector2i(-2, 0)

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
## How often the safe zone has a peddler by its fire, what they sell and who they
## might be. See [method _add_merchant].
const MERCHANT_CHANCE := 0.4
const MERCHANT_SHOP := "res://resources/shops/travelling_merchant.tres"
const MERCHANT_SHEETS: PackedStringArray = ["OldMan2", "Monk", "Sultan", "Villager4"]
const CHARACTERS := "res://assets/ninja_adventure/Actor/Character/%s/%s.png"
## The middle of each side of the 6x6 safe zone: the cells against the pillar
## where the maze's wall lines cross, which no passage can come in through.
const MERCHANT_SPOTS: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 2), Vector2i(5, 2),
	Vector2i(0, 3), Vector2i(5, 3), Vector2i(2, 5), Vector2i(3, 5),
]

## An open field's arena ([enum FloorDefinition.Shape]), inside its wall: square,
## so it needs no turning, and roomier than a boss room -- it is seen from the field
## before it is walked into. Its gate is a [SealedDoor]'s 2x2 through the
## [constant LAB_WALL] facing the field, in the middle of that side.
const ARENA_ROOM := Vector2i(12, 12)
## The waystones sealing it, one to a clearing.
const WAYSTONES := 3
## An open field's clearings, bigger than a classic field's rooms.
const CLEARING_W := Vector2i(9, 16)
const CLEARING_H := Vector2i(8, 12)

## Builds every generated floor as this [enum FloorDefinition.Shape] when set, for
## the tests; -1 leaves it to [method FloorRegistry.shape_of].
static var shape_override := -1

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
## Every cell a corridor's width swept, open already or not: what the camp keeps
## clear of, since a corridor through a room is invisible in [member _open].
var _lanes: Dictionary[Vector2i, bool] = {}


## [param level] is which of a dungeon's maps ([DungeonGenerator]); every other
## shape is one map and ignores it.
static func generate(definition: FloorDefinition, generation_seed: int, level := 1) -> Node2D:
	if FloorRegistry.shape_of(definition.floor_number) == FloorDefinition.Shape.DUNGEON:
		# By path: DungeonGenerator extends this script, and naming it here would be a cycle.
		return load(DUNGEON_SCRIPT).new()._build_level(definition, generation_seed, level)
	return FloorGenerator.new()._build(definition, generation_seed)


## An authored floor's labyrinth, grown by the same code as a generated floor's:
## a [param cells] maze whose top-left corner is [param at] (in tiles), standing on
## the [param facing] side of the rest of the floor ([enum Side]), its mouth
## [param along] cells down the wall that faces back. Carved into [param ground] and
## [param walls], recorded in [param open], from [param maze_seed] -- an authored
## floor fixes that, so the maze is the same every time the tool is run. The
## corridor up to [member Labyrinth.doorstep] is the floor's to carve.
static func grow_into(biome: BiomeKit, ground: TileMapLayer, walls: TileMapLayer,
		open: Dictionary[Vector2i, bool], map_size: Vector2i, at: Vector2i, cells: Vector2i,
		facing: int, along: int, maze_seed: int, boss_block := BOSS_BLOCK) -> Labyrinth:
	var builder := FloorGenerator.new()
	builder._biome = biome
	builder._ground = ground
	builder._walls = walls
	builder._open = open
	builder._size = map_size
	builder._rng.seed = maze_seed
	var lab := Labyrinth.new()
	lab.cells = cells
	lab.side = facing
	lab.boss_block = boss_block
	lab.rect = Rect2i(at, cells * LAB_PITCH + Vector2i(LAB_WALL, LAB_WALL))
	lab.start = Labyrinth.start_cell(cells, facing, along)
	builder._grow_labyrinth(lab)
	builder._open_mouth(lab)
	return lab


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
	var arena: Arena = null
	if FloorRegistry.shape_of(definition.floor_number) == FloorDefinition.Shape.OPEN_FIELD:
		arena = Arena.new()
	var field: Rect2i
	if arena == null:
		field = Rect2i(Vector2i.ZERO, definition.size)
		_lay_out(field, lab)
		field = lab.field
	else:
		field = _lay_out_arena(arena)
	for y in _size.y:
		for x in _size.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)

	var rooms := _place_rooms(field) if arena == null else _place_rooms(field,
			FloorTuning.open_room_count(definition.floor_number), CLEARING_W, CLEARING_H)
	for room in rooms:
		_carve(room, _biome.floor_tile)
	for i in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))

	var entry: Rect2i
	var boss_room: Rect2i
	var gate_cell: Vector2i
	if arena != null:
		_carve_arena(arena)
		entry = _connect_to(arena.doorstep, arena.side, rooms)
		boss_room = Rect2i()
		gate_cell = _center(arena.room)
	elif lab.has_maze():
		_carve_labyrinth(lab)
		entry = _connect_labyrinth(lab, rooms)
		boss_room = Rect2i()
		gate_cell = _center(lab.boss_room)
	else:
		entry = rooms[0]
		boss_room = _farthest_room(rooms, _center(entry))
		_carve(boss_room, _biome.special_tile)
		gate_cell = _center(boss_room)
	# The adventurers' camp, round the room you arrive in. By rule: no rng.
	var camp := FloorCamp.new(_definition.floor_number, generation_seed, _biome,
			_ground, _walls, _open)
	camp.reserve(field, rooms, entry)

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
	var free_ends := lab.dead_ends.duplicate()
	if lab_chest:
		var pick := _rng.randi() % lab.dead_ends.size()
		chest_cells.append(_cell_rect(lab, lab.dead_ends[pick]).position)
		deep.remove_at(pick)
		free_ends.remove_at(pick)
	_scatter_decor(rooms, entry, boss_room)

	var must_reach: Array[Vector2i] = chest_cells.duplicate()
	must_reach.append(gate_cell)
	_ensure_reachable(_center(entry), must_reach)
	var arrival := _center(entry)
	camp.plan(arrival, _lanes, [
		Rect2i(arrival - Vector2i.ONE, Vector2i(3, 3)),
		Rect2i(arrival + GATE_OFFSET - Vector2i(1, 2), Vector2i(3, 3)),
		Rect2i(arrival + GATE_ARRIVAL, Vector2i.ONE),
		Rect2i(arrival + STAIRS_OFFSET, Vector2i.ONE),
	] as Array[Rect2i])
	if arena != null:
		_plan_arena_field(arena, rooms, entry, chest_cells)
	# Before dressing: the vault is carved out of the rock, and its walls join like any.
	var puzzles: FloorPuzzles = null
	if with_puzzles and (lab.has_maze() or arena != null):
		puzzles = FloorPuzzles.new(_definition.floor_number, generation_seed, _biome,
				_ground, _walls, _open, field)
		if arena != null:
			for cell in arena.waystones:
				puzzles.keep_clear(cell, 1)
			if arena.fire.has_area():
				puzzles.keep_clear(arena.fire.position, 2)
		puzzles.plan(rooms, entry, chest_cells, field_chests)
	MapDresser.dress(map, _biome, _ground, _walls, generation_seed)

	_add_spawns(map, _center(entry))
	_add_teleport_gate(map, _center(entry))
	for index in chest_cells.size():
		_add_chest(map, chest_cells[index], index, index < field_chests, deep)
	_add_monsters(map, rooms, entry, arena.safe_room if arena != null else boss_room, lab)
	if puzzles != null:
		puzzles.place(map)
	_add_boss_gate(map, gate_cell, lab.boss_room)
	if lab.camp_room.has_area():
		_add_campfire(map, lab.camp_room)
		_add_merchant(map, lab.camp_room, generation_seed)
	if arena != null:
		_add_arena(map, arena)
	if _definition.floor_number > 1:
		_add_stairs(map, _center(entry) + STAIRS_OFFSET)
	camp.open_field = arena != null
	camp.place(map, arena.side if arena != null else lab.side if lab.has_maze() else -1,
			_definition.boss_name, _lost_spots(lab, free_ends))

	if lab.has_maze():
		# Inside the labyrinth you see only what is in line of sight.
		map.set(&"dark_area", lab.rect)
		var places: Dictionary[String, Rect2i] = {"The Labyrinth": lab.rect,
				"Village" if camp.village else "Camp": camp.plot}
		if lab.camp_room.has_area():
			places["Safe Zone"] = lab.camp_room
			map.set(&"safe_zones", [lab.camp_room] as Array[Rect2i])
			map.set_meta(&"safe_zone", lab.camp_room)
		map.set(&"landmarks", places)
		# What the tests (and nothing in the game) need to find the labyrinth again.
		map.set_meta(&"labyrinth", lab.rect)
		map.set_meta(&"labyrinth_mouth", lab.mouth)
		map.set_meta(&"boss_room", lab.boss_room)
	elif arena != null:
		# No dark anywhere: an open field is seen as you walk it, arena and all.
		var places: Dictionary[String, Rect2i] = {"The Arena": arena.rect,
				"Village" if camp.village else "Camp": camp.plot}
		if arena.fire.has_area():
			places["Safe Zone"] = arena.safe_room
			map.set(&"safe_zones", [arena.safe_room] as Array[Rect2i])
			map.set_meta(&"safe_zone", arena.safe_room)
		map.set(&"landmarks", places)
		# For the tests, as the labyrinth's are.
		map.set_meta(&"arena", arena.rect)
		map.set_meta(&"arena_room", arena.room)
		map.set_meta(&"arena_door", arena.door)
		map.set_meta(&"waystones", arena.waystones)
	map.set_meta(&"camp", camp.plot)
	if camp.village:
		map.set_meta(&"village", camp.houses)
	if camp.lost_cell.x >= 0:
		map.set_meta(&"lost_player", camp.lost_cell)

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
	var at := _place_strip(field.size, tiles, lab.side)
	lab.field.position = at[0]
	lab.rect = Rect2i(at[1], tiles)
	_size = lab.field.end.max(lab.rect.end)


## Where the field and a strip of [param tiles] built onto its [param side] go,
## as [code][the field's corner, the strip's corner][/code]. Along the side they
## share, whichever is shorter is slid along the longer one; what neither covers is
## rock. A labyrinth longer than the field is the usual case -- it is meant to be the
## bigger half of the floor -- and an arena is always the shorter.
func _place_strip(field: Vector2i, tiles: Vector2i, side: int) -> Array[Vector2i]:
	var shared := 1 if side == Side.EAST or side == Side.WEST else 0
	var span := maxi(field[shared], tiles[shared])
	var field_along := _rng.randi_range(0, span - field[shared])
	var strip_along := _rng.randi_range(0, span - tiles[shared])
	var field_at := Vector2i.ZERO
	var strip_at := Vector2i.ZERO
	field_at[shared] = field_along
	strip_at[shared] = strip_along
	match side:
		Side.EAST:
			strip_at.x = field.x
		Side.WEST:
			field_at.x = tiles.x
		Side.SOUTH:
			strip_at.y = field.y
		Side.NORTH:
			field_at.y = tiles.y
	return [field_at, strip_at]


## An open field's layout: the field, bigger than a classic one, and the arena's
## strip on a seeded side of it, laid out as the labyrinth's is. Returns the field.
func _lay_out_arena(arena: Arena) -> Rect2i:
	var size := FloorTuning.open_field_size(_definition.floor_number)
	var tiles := ARENA_ROOM + Vector2i(LAB_WALL, LAB_WALL) * 2
	arena.side = _rng.randi() % 4
	var at := _place_strip(size, tiles, arena.side)
	arena.rect = Rect2i(at[1], tiles)
	arena.room = arena.rect.grow(-LAB_WALL)
	var field := Rect2i(at[0], size)
	_size = field.end.max(arena.rect.end)
	return field


func _place_rooms(field: Rect2i, count := -1, widths := Vector2i(7, 12),
		heights := Vector2i(6, 9)) -> Array[Rect2i]:
	if count < 0:
		count = _definition.room_count
	var rooms: Array[Rect2i] = []
	var size := field.size
	var attempts := count * 20
	while rooms.size() < count and attempts > 0:
		attempts -= 1
		var w := _rng.randi_range(widths.x, widths.y)
		var h := _rng.randi_range(heights.x, heights.y)
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
				_lanes[target] = true
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
	var along := _rng.randi_range(0, (cells.y if lab.side in [Side.EAST, Side.WEST] else cells.x) - 1)
	lab.start = Labyrinth.start_cell(cells, lab.side, along)
	_grow_labyrinth(lab)


## The maze itself, once [param lab] knows its cells, its side and its start:
## grown, measured, regrown, and carved with its boss room and safe zone. Shared
## by a generated floor and an authored one ([method grow_into]).
func _grow_labyrinth(lab: Labyrinth) -> void:
	var cells := lab.cells
	# Distance on the grid is a poor guess at distance through a maze: a room two
	# cells from the mouth can be forty tiles' walk or six. So the maze is grown,
	# measured, and grown again until the walk to the door is at least the grid's
	# width plus its height -- every attempt from the same seeded stream.
	var wanted := cells.x + cells.y - 2
	var best_score := -1
	for _attempt in MAZE_ATTEMPTS:
		var block_size := lab.boss_block if _rng.randf() < 0.5 \
				else Vector2i(lab.boss_block.y, lab.boss_block.x)
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
	_open_mouth(lab)
	return _connect_to(lab.doorstep, lab.side, rooms)


## Runs a corridor to [param doorstep] -- a strip's way in, on the field's
## [param side] -- from the nearest room, and returns the room the player arrives
## in: a seeded pick from the rooms in the far half from it, so the walk crosses
## the field first.
func _connect_to(doorstep: Vector2i, side: int, rooms: Array[Rect2i]) -> Rect2i:
	var by_distance := _by_distance(rooms, doorstep)
	# Across the field first, then along its edge to the doorstep: the strip
	# stands beyond that edge, so neither leg can cut into it.
	_carve_elbow(_center(by_distance[0]), doorstep, side == Side.EAST or side == Side.WEST)

	var far_half := by_distance.slice(by_distance.size() / 2)
	return far_half[_rng.randi() % far_half.size()]


## [param rooms], nearest [param to] first.
func _by_distance(rooms: Array[Rect2i], to: Vector2i) -> Array[Rect2i]:
	var by_distance := rooms.duplicate()
	by_distance.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return (_center(a) - to).length_squared() < (_center(b) - to).length_squared())
	return by_distance


## The gap through the labyrinth's own wall, from its first cell to the field;
## then a doorstep two cells out from it and square to it, where a corridor's
## three-cell width touches both of the mouth's rows (or columns).
func _open_mouth(lab: Labyrinth) -> void:
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
	lab.doorstep = doorstep


## Where a lost player may wait in each of [param ends]: as
## [code][cell, the way out][/code], in tiles, the cell against the dead end's back
## wall that leaves the other three of its passage joined -- and never the corner
## a teleport trap lands you in, which is the passage's bottom right.
func _lost_spots(lab: Labyrinth, ends: Array[Vector2i]) -> Array:
	var spots: Array = []
	for end in ends:
		if lab.links.get(end, []).size() != 1:
			continue
		var out: Vector2i = lab.links[end][0] - end
		var at := _cell_rect(lab, end).position
		if out == Vector2i.LEFT:
			at += Vector2i.RIGHT
		elif out == Vector2i.UP:
			at += Vector2i.DOWN
		spots.append([at, out])
	return spots


func _cell_rect(lab: Labyrinth, cell: Vector2i) -> Rect2i:
	return lab.cell_rect(cell)


## The wall between two neighbouring cells.
func _gap_rect(lab: Labyrinth, a: Vector2i, b: Vector2i) -> Rect2i:
	var low := _cell_rect(lab, Vector2i(mini(a.x, b.x), mini(a.y, b.y)))
	if a.y == b.y:
		return Rect2i(low.position + Vector2i(LAB_PASSAGE, 0), Vector2i(LAB_WALL, LAB_PASSAGE))
	return Rect2i(low.position + Vector2i(0, LAB_PASSAGE), Vector2i(LAB_PASSAGE, LAB_WALL))


# --- the arena -------------------------------------------------------------

## The arena's floor, and its gate through the middle of the wall facing the field
## (a dungeon's stair chamber and boss hall are carved the same way):
## a [SealedDoor]'s 2x2, carved as floor -- the door is a solid node, not wall, so
## the flood fill reaches the arena either way. The doorstep is two out from it,
## square to it, as the labyrinth's mouth's is.
func _carve_arena(arena: Arena) -> void:
	_carve(arena.room, _biome.special_tile)
	var middle := arena.room.size / 2 - Vector2i.ONE
	var across := Vector2i(LAB_WALL, 2)
	var down := Vector2i(2, LAB_WALL)
	match arena.side:
		Side.EAST:
			arena.door = Rect2i(Vector2i(arena.rect.position.x, arena.room.position.y + middle.y), across)
			arena.doorstep = Vector2i(arena.door.position.x - 2, arena.door.position.y)
		Side.WEST:
			arena.door = Rect2i(Vector2i(arena.room.end.x, arena.room.position.y + middle.y), across)
			arena.doorstep = Vector2i(arena.door.end.x + 1, arena.door.position.y)
		Side.SOUTH:
			arena.door = Rect2i(Vector2i(arena.room.position.x + middle.x, arena.rect.position.y), down)
			arena.doorstep = Vector2i(arena.door.position.x, arena.door.position.y - 2)
		Side.NORTH:
			arena.door = Rect2i(Vector2i(arena.room.position.x + middle.x, arena.room.end.y), down)
			arena.doorstep = Vector2i(arena.door.position.x, arena.door.end.y + 1)
	_carve(arena.door, _biome.floor_tile)


## What an open field puts in its clearings, by rule rather than by the rng: a
## safe zone in the clearing nearest the arena's gate (the corridor to the gate
## leaves from it), and the waystones in the clearings farthest from the arrival
## and from each other -- so waking them is a walk round the whole field. Each
## stands on the clearing's cell nearest its middle that is off every corridor's
## sweep with open ground all round it, and comes out of [member _open]: it is solid.
func _plan_arena_field(arena: Arena, rooms: Array[Rect2i], entry: Rect2i,
		chest_cells: Array[Vector2i]) -> void:
	var taken: Dictionary[Vector2i, bool] = {}
	for cell in chest_cells:
		taken[cell] = true
	for room in _by_distance(rooms, arena.doorstep):
		if room == entry:
			continue
		var fire := _fire_spot(room, taken)
		if fire.has_area():
			arena.safe_room = room
			arena.fire = fire
			_open.erase(fire.end - Vector2i.ONE)
			_open.erase(fire.end - Vector2i(2, 1))
			break

	var spots: Dictionary[Rect2i, Vector2i] = {}
	for room in rooms:
		if room == entry or room == arena.safe_room:
			continue
		var cell := _stone_spot(room, taken)
		if cell.x >= 0:
			spots[room] = cell
	var anchors: Array[Vector2i] = [_center(entry)]
	while arena.waystones.size() < WAYSTONES and not spots.is_empty():
		var best := Rect2i()
		var best_gap := -1.0
		for room: Rect2i in spots:
			var gap := INF
			for anchor in anchors:
				gap = minf(gap, Vector2(_center(room) - anchor).length())
			if gap > best_gap:
				best_gap = gap
				best = room
		arena.waystones.append(spots[best])
		_open.erase(spots[best])
		anchors.append(_center(best))
		spots.erase(best)


## A 2x2 for a safe zone's fire in [param room] (the pit along its bottom row),
## nearest the middle, with a cell of open ground all round it and none of it in a
## corridor's sweep. Empty if the clearing has none.
func _fire_spot(room: Rect2i, taken: Dictionary[Vector2i, bool]) -> Rect2i:
	var best := Rect2i()
	var best_off := INF
	for y in range(room.position.y + 1, room.end.y - 2):
		for x in range(room.position.x + 1, room.end.x - 2):
			var spot := Rect2i(x, y, 2, 2)
			var off := (Vector2(spot.get_center()) - Vector2(room.get_center())).length()
			if off < best_off and _clear_round(spot.grow(1), taken):
				best = spot
				best_off = off
	return best


## The cell in [param room] nearest its middle for a waystone: off every corridor's
## sweep, with open ground all round it. (-1, -1) if there is none.
func _stone_spot(room: Rect2i, taken: Dictionary[Vector2i, bool]) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_off := INF
	for y in range(room.position.y + 1, room.end.y - 1):
		for x in range(room.position.x + 1, room.end.x - 1):
			var cell := Vector2i(x, y)
			var off := (Vector2(cell) + Vector2(0.5, 0.5) - Vector2(room.get_center())).length()
			if off < best_off and _clear_round(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)), taken):
				best = cell
				best_off = off
	return best


## Whether every cell of [param rect] is open, clear of corridors and not
## [param taken].
func _clear_round(rect: Rect2i, taken: Dictionary[Vector2i, bool]) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not _open.has(cell) or _lanes.has(cell) or taken.has(cell):
				return false
	return true


## The arena's waystones, its sealed gate and the safe zone's fire. Waking a
## stone sets [code]waystone_<n>_<i>[/code]; the gate opens itself on the last,
## setting [code]arena_<n>_open[/code] and the floor's
## [method BossGate.found_flag] -- the door was never hidden, but until now it
## could not be walked to.
func _add_arena(map: Node2D, arena: Arena) -> void:
	var n := _definition.floor_number
	var flags: Array[StringName] = []
	for i in arena.waystones.size():
		flags.append(StringName("waystone_%d_%d" % [n, i]))
	for i in arena.waystones.size():
		var stone := WAYSTONE_SCENE.instantiate()
		stone.name = "Waystone%d" % i
		stone.position = _world(arena.waystones[i])
		stone.set(&"flag", flags[i])
		stone.set(&"all_flags", flags)
		map.add_child(stone)
	var seal := SEAL_SCENE.instantiate()
	seal.name = "ArenaSeal"
	seal.position = Vector2(arena.door.position * TILE) + Vector2(arena.door.size * TILE) / 2.0
	seal.set(&"display_name", "the arena gate")
	seal.set(&"sigils", flags)
	seal.set(&"opened_flag", StringName("arena_%d_open" % n))
	seal.set(&"opens_itself", true)
	seal.set(&"also_sets", [BossGate.found_flag(n)] as Array[StringName])
	seal.set(&"described", "The arena's gate: one slab of stone, fitted to the wall.")
	seal.set(&"hint", "Waystones stand out in the far clearings. Wake them all and it opens.")
	seal.set(&"opening_lines", PackedStringArray([
		"Far across the field, stone grinds on stone.",
		"The arena's gate is open.",
	]))
	map.add_child(seal)
	var gate := map.get_node_or_null("BossGate")
	if gate != null:
		gate.set(&"display_name", "the arena door")
	if arena.fire.has_area():
		var fire := CAMPFIRE_SCENE.instantiate()
		fire.name = "Campfire"
		fire.position = Vector2((arena.fire.position.x + 1) * TILE, arena.fire.end.y * TILE)
		map.add_child(fire)


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
	var gate := Marker2D.new()
	gate.name = "gate"
	gate.position = _world(entry + GATE_ARRIVAL)
	holder.add_child(gate)


## The floor's teleport gate, beside where you arrive. Placed by rule rather than
## by the rng, so adding it moved nothing else on any floor.
func _add_teleport_gate(map: Node2D, entry: Vector2i) -> void:
	var gate := TELEPORT_GATE_SCENE.instantiate()
	gate.name = "TeleportGate"
	gate.position = _world(entry + GATE_OFFSET)
	gate.set(&"floor_number", _definition.floor_number)
	map.add_child(gate)


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
## [param count] is how many; -1 is the floor's [method FloorTuning.monster_count].
func _add_monsters(map: Node2D, rooms: Array[Rect2i], entry: Rect2i, boss_room: Rect2i,
		lab: Labyrinth, count := -1) -> void:
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
		passages = lab.passages()

	if count < 0:
		count = FloorTuning.monster_count(_definition.floor_number)
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


## A peddler by the safe zone's fire, on some floors: potions at town prices,
## halfway to the door. Whether there is one, and who, comes from the floor's own
## [code]hash("<seed>:merchant")[/code] stream, never the floor's rng, so adding
## them moved nothing; where they stand is rule -- the middle of one of the room's
## sides, against the pillar the maze always leaves there, never in a doorway, so
## the fire's room stays open all round and the floor test's safe-zone walk holds.
func _add_merchant(map: Node2D, room: Rect2i, generation_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:merchant" % generation_seed)
	if rng.randf() >= MERCHANT_CHANCE:
		return
	var spots: Array[Vector2i] = []
	for offset in MERCHANT_SPOTS:
		var cell := room.position + offset
		if not _open.has(cell):
			continue
		var against_rock := true
		for step in MAZE_STEPS:
			if not room.has_point(cell + step) and _open.has(cell + step):
				against_rock = false
		if against_rock:
			spots.append(cell)
	if spots.is_empty():
		return
	var spot := spots[rng.randi() % spots.size()]
	var sheet: String = MERCHANT_SHEETS[rng.randi() % MERCHANT_SHEETS.size()]
	var npc := NPC_SCENE.instantiate()
	npc.name = "Merchant"
	npc.position = _world(spot)
	npc.set(&"sprite_sheet", load(CHARACTERS % [sheet, "SpriteSheet"]))
	npc.set(&"display_name", "the peddler")
	npc.set(&"prompt_verb", "Trade with")
	npc.set(&"shop", load(MERCHANT_SHOP))
	# Facing the fire, in the middle of the room: down, up, left, right.
	var to_fire := Vector2(room.get_center()) - Vector2(spot) - Vector2(0.5, 0.5)
	(npc.get_node("Sprite2D") as Sprite2D).frame = \
			(0 if to_fire.y > 0 else 1) if absf(to_fire.y) >= absf(to_fire.x) \
			else (3 if to_fire.x > 0 else 2)
	map.add_child(npc)


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
	## The boss room's size in cells, one way round or the other.
	var boss_block := BOSS_BLOCK
	## Where a corridor from the field meets the mouth, in tiles: two out from it,
	## square to it.
	var doorstep := Vector2i.ZERO

	func has_maze() -> bool:
		return rect.has_area()

	## The cell [param along] the wall facing the field: the maze is grown from it,
	## and the mouth opens beside it.
	static func start_cell(maze: Vector2i, facing: int, along: int) -> Vector2i:
		match facing:
			Side.EAST:
				return Vector2i(0, along)
			Side.WEST:
				return Vector2i(maze.x - 1, along)
			Side.SOUTH:
				return Vector2i(along, 0)
		return Vector2i(along, maze.y - 1)

	## A cell's passage, in tiles.
	func cell_rect(cell: Vector2i) -> Rect2i:
		return Rect2i(rect.position + Vector2i(LAB_WALL, LAB_WALL) + cell * LAB_PITCH,
				Vector2i(LAB_PASSAGE, LAB_PASSAGE))

	## Every passage cell but the mouth's, the boss room's and the safe zone's, in
	## tiles and in reading order -- where a monster may walk the maze from.
	func passages() -> Array[Rect2i]:
		var found: Array[Rect2i] = []
		for cell: Vector2i in links:
			if cell != start and not block.has_point(cell) and not camp.has_point(cell):
				found.append(cell_rect(cell))
		found.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
			return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
		return found

	static func join(into: Dictionary[Vector2i, Array], a: Vector2i, b: Vector2i) -> void:
		if not into.has(a):
			into[a] = []
		if not into.has(b):
			into[b] = []
		into[a].append(b)
		into[b].append(a)


## Everything an open field's arena is, while it is being built.
class Arena:
	## The arena in tiles, its wall included, and inside it.
	var rect := Rect2i()
	var room := Rect2i()
	## Which side of the field it stands on ([enum Side]).
	var side := 0
	## The gate through its wall, in tiles: the only way in.
	var door := Rect2i()
	## Where the corridor from the field meets the gate: two out from it, square to it.
	var doorstep := Vector2i.ZERO
	## Each waystone's cell, in tiles.
	var waystones: Array[Vector2i] = []
	## The clearing that is the field's safe zone, and its fire's 2x2. Empty when no
	## clearing had room for one.
	var safe_room := Rect2i()
	var fire := Rect2i()
