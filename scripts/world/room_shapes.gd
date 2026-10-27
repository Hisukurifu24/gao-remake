class_name RoomShapes
extends RefCounted
## The shapes of a generated floor's rooms (plan.md, M6 "Floor variety"): a field
## of rectangles reads as a template by the fourth floor, so most rooms are given a
## shape -- by putting rock back into the rectangle the generator carved, never by
## carving more.
##
## - [b]CAVERN[/b]: the rectangle's corners and edges taken back by a wobbling
##   ellipse -- a glade in the woods, a cavern underground, an island in the sky.
## - [b]L_HALL[/b]: one corner of the room filled in.
## - [b]CROSS_HALL[/b]: all four corners filled in, leaving its arms.
## - [b]PILLARS[/b]: a grid of 2x2 pillars standing in the room -- columns in the
##   Ruby Palace, mesas in the desert, a stand of trees in a glade.
##
## Every rock cell it puts back is part of a 2x2 of rock and every floor cell it
## leaves beside one is part of a 2x2 of floor, as a maze's are, because that is
## what every biome's walls can draw. A shape keeps off every corridor's sweep and
## anything kept, and cuts nothing off; a room whose shape can't do all three stays
## a rectangle.
##
## Planned after everything else on the floor and before dressing, so the walls join
## round it. It never takes the arrival's room or the camp's, a boss's, a safe zone,
## the event's, the landmark's, or one a rite or a ring of statues stands in -- a
## timed rite's fire is measured against the walk round the room as it was, and a
## ring wants its room whole -- and in the rest it keeps a cell clear round
## everything standing there (the floor's chests, a wisp and its shrine, a vault's or
## a crack's doorway, a waystone) and off a wisp's way. Each room's shape is drawn from a stream of its own
## ([code]hash("<seed>:room:<x>,<y>")[/code]), so whether one room is shaped never
## changes another's. A floor with its rooms shaped is the floor without, plus the
## rock, with the monsters that stood on it stepped off and the dressing redrawn.
## [member FloorGenerator.with_room_shapes] turns it off and
## [member FloorGenerator.room_shape_override] forces a kind, for the tests and tools.

enum Kind { RECT, CAVERN, L_HALL, CROSS_HALL, PILLARS }
const KIND_NAMES: PackedStringArray = ["rectangle", "cavern", "L hall", "cross hall", "pillared hall"]

## The share of the rooms that may take a shape that do.
const CHANCE := 0.7
## How often each band draws each shape: cavern, L, cross, pillars. Natural bands
## lean to caverns, built ones to halls; the sky has no pillars, since a pillar of
## its rock is a hole onto the void.
const WEIGHTS := {
	&"meadow": [5, 2, 1, 2], &"forest": [5, 2, 1, 2], &"cave": [7, 1, 1, 2],
	&"ruins": [2, 3, 2, 3], &"swamp": [6, 2, 1, 1], &"desert": [4, 2, 1, 3],
	&"ice": [5, 2, 1, 2], &"volcanic": [6, 2, 1, 1], &"sky": [6, 3, 1, 0],
	&"castle": [0, 3, 3, 4],
}
const DEFAULT_WEIGHTS := [4, 2, 1, 2]
## The least rock a shape puts back, in cells: less reads as a mistake, not a shape.
const LEAST := 4
## A cavern's wobble, as a share of its radius, and how many lobes it has.
const WOBBLE := Vector2(0.12, 0.3)
const LOBES := Vector2i(2, 5)
## The narrowest an L's or a cross's arm is, in cells.
const ARM := 3
## A pillar's side, the gap between pillars and how far they keep from the walls.
const PILLAR := 2
const PILLAR_GAP := Vector2i(2, 3)
const PILLAR_MARGIN := 2
## How many times the thickening pass may take a sliver of floor into the rock before
## it may only let rock go. See [method _settle].
const TAKE_PASSES := 2

const SQUARES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const TILE := 16

## Every room given a shape, by its rect: its [enum Kind].
var shaped: Dictionary[Rect2i, int] = {}
## Every cell put back to rock.
var filled: Dictionary[Vector2i, bool] = {}

var _seed := 0
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool]
## Cells a shape must leave as they are: the floor's chests and the ring round them,
## a wisp's way.
var _keep: Dictionary[Vector2i, bool] = {}
## Every corridor's sweep. Rock taken back from a room's edges keeps off it, or it
## would close a corridor's mouth; a pillar may stand on it, since in the middle of
## a room a corridor's sweep is only floor, and the walk round is checked.
var _lanes: Dictionary[Vector2i, bool] = {}


## [param open] is the generator's carved cells with decor taken out; a shape takes
## its rock out of it.
func _init(generation_seed: int, biome: BiomeKit, ground: TileMapLayer, walls: TileMapLayer,
		open: Dictionary[Vector2i, bool]) -> void:
	_seed = generation_seed
	_biome = biome
	_ground = ground
	_walls = walls
	_open = open


## Shapes [param rooms] but those in [param keep_out] or touching [param plot]; every
## shape keeps off [param lanes], [param ways] and the cell round each of
## [param kept], and cuts off nothing walkable from [param arrival]. [param forced] is
## a [enum Kind] every room tries, or -1 for the band's draw. Before dressing.
func plan(rooms: Array[Rect2i], keep_out: Array[Rect2i], plot: Rect2i,
		lanes: Dictionary[Vector2i, bool], ways: Array[Vector2i], kept: Array[Vector2i],
		arrival: Vector2i, forced := -1) -> void:
	_lanes = lanes
	for cell in ways:
		_keep[cell] = true
	for cell in kept:
		for y in range(-1, 2):
			for x in range(-1, 2):
				_keep[cell + Vector2i(x, y)] = true
	var weights: Array = WEIGHTS.get(_biome.id if _biome != null else &"", DEFAULT_WEIGHTS)
	var reached := _reach(arrival)
	for room in rooms:
		if room in keep_out or (plot.has_area() and room.grow(1).intersects(plot)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:room:%d,%d" % [_seed, room.position.x, room.position.y])
		if forced < 0 and rng.randf() >= CHANCE:
			continue
		# Two pillars want a room ten across or down: a smaller one draws again, from
		# the band's other shapes.
		var drawn := weights.duplicate()
		if not _holds_pillars(room.size):
			drawn[Kind.PILLARS - 1] = 0
		var kind: int = forced if forced >= 0 else _pick(drawn, rng)
		var cells := _rock_for(kind, room, rng)
		cells = _settle(cells, room, kind != Kind.PILLARS)
		if cells.size() < LEAST or not _cuts_nothing(cells, arrival, reached):
			continue
		for cell: Vector2i in cells:
			_walls.set_cell(cell, 0, Vector2i(_biome.wall_tile, 0))
			_ground.erase_cell(cell)
			_open.erase(cell)
			filled[cell] = true
		shaped[room] = kind


## Steps every monster standing on rock it put back to the nearest floor in its
## room -- moved, not dropped: the monster count is the boss's balance.
func step_monsters_off(map: Node2D) -> void:
	if filled.is_empty():
		return
	for child in map.get_children():
		var monster := child as Monster
		if monster == null:
			continue
		var at := Vector2i(monster.position / TILE)
		if not filled.has(at):
			continue
		var seen: Dictionary[Vector2i, bool] = {at: true}
		var queue: Array[Vector2i] = [at]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			if _open.has(cell):
				monster.position = _world(cell)
				break
			for step in STEPS:
				if not seen.has(cell + step) and (_open.has(cell + step) or filled.has(cell + step)):
					seen[cell + step] = true
					queue.append(cell + step)


func _pick(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for weight: int in weights:
		total += weight
	if total == 0:
		return Kind.CAVERN
	var roll := rng.randi() % total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0:
			return i + 1
	return Kind.CAVERN


# --- the shapes ------------------------------------------------------------

## The cells of [param room] that [param kind] wants back as rock, before
## [method _settle] makes it drawable.
func _rock_for(kind: int, room: Rect2i, rng: RandomNumberGenerator) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	match kind:
		Kind.CAVERN:
			var wobble := rng.randf_range(WOBBLE.x, WOBBLE.y)
			var lobes := rng.randi_range(LOBES.x, LOBES.y)
			var phase := rng.randf() * TAU
			var centre := Vector2(room.position) + Vector2(room.size) / 2.0
			var radius := Vector2(room.size) / 2.0
			for y in range(room.position.y, room.end.y):
				for x in range(room.position.x, room.end.x):
					var offset := (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / radius
					var reach := 1.0 - wobble * (0.5 + 0.5 * sin(lobes * offset.angle() + phase))
					if offset.length() > reach:
						cells[Vector2i(x, y)] = true
		Kind.L_HALL:
			var cut := _corner_cut(room.size, rng, 1)
			var corner := rng.randi() % 4
			_fill_corner(cells, room, cut, corner)
		Kind.CROSS_HALL:
			if room.size.x < ARM + 4 or room.size.y < ARM + 4:
				# No room for two corners and an arm: an L.
				_fill_corner(cells, room, _corner_cut(room.size, rng, 1), rng.randi() % 4)
			else:
				var cut := _corner_cut(room.size, rng, 2)
				for corner in 4:
					_fill_corner(cells, room, cut, corner)
		Kind.PILLARS:
			var gap := rng.randi_range(PILLAR_GAP.x, PILLAR_GAP.y)
			if _pillars_along(room.size.x, gap).size() * _pillars_along(room.size.y, gap).size() < 2:
				gap = PILLAR_GAP.x
			var columns := _pillars_along(room.size.x, gap)
			var rows := _pillars_along(room.size.y, gap)
			var standing := 0
			for row in rows:
				for column in columns:
					var at := room.position + Vector2i(column, row)
					var pillar := Rect2i(at, Vector2i(PILLAR, PILLAR))
					if _clear_for(pillar):
						standing += 1
						for y in range(pillar.position.y, pillar.end.y):
							for x in range(pillar.position.x, pillar.end.x):
								cells[Vector2i(x, y)] = true
			# One pillar is a boulder, not a hall.
			if standing < 2:
				cells.clear()
	return cells


## How much of a room [param size] an L takes from one corner ([param corners] 1)
## or a cross from each of four (2): two cells at least, and never so much that an
## arm comes out narrower than [constant ARM].
func _corner_cut(size: Vector2i, rng: RandomNumberGenerator, corners: int) -> Vector2i:
	var most := (size - Vector2i(ARM, ARM)) / corners
	var least := Vector2i(maxi(2, ceili(size.x * 0.35)), maxi(2, ceili(size.y * 0.35))) \
			if corners == 1 else Vector2i(2, 2)
	least = least.min(most)
	return Vector2i(rng.randi_range(least.x, maxi(least.x, most.x)),
			rng.randi_range(least.y, maxi(least.y, most.y)))


func _fill_corner(cells: Dictionary[Vector2i, bool], room: Rect2i, cut: Vector2i, corner: int) -> void:
	var at := room.position
	if corner == 1 or corner == 2:
		at.x = room.end.x - cut.x
	if corner >= 2:
		at.y = room.end.y - cut.y
	for y in range(at.y, at.y + cut.y):
		for x in range(at.x, at.x + cut.x):
			cells[Vector2i(x, y)] = true


## Whether a room [param size] has room for two pillars at the closest they stand.
func _holds_pillars(size: Vector2i) -> bool:
	return _pillars_along(size.x, PILLAR_GAP.x).size() * _pillars_along(size.y, PILLAR_GAP.x).size() >= 2


## Where pillars stand along a side [param length] long, from its start: as many as
## fit [param gap] apart and [constant PILLAR_MARGIN] from either wall, centred.
func _pillars_along(length: int, gap: int) -> Array[int]:
	var inside := length - PILLAR_MARGIN * 2
	var count := (inside + gap) / (PILLAR + gap)
	var spots: Array[int] = []
	if count < 1:
		return spots
	var spare := inside - (count * PILLAR + (count - 1) * gap)
	for i in count:
		spots.append(PILLAR_MARGIN + spare / 2 + i * (PILLAR + gap))
	return spots


## Whether a pillar may stand on [param rect]: nothing on it kept. A boulder or a
## pool on it becomes pillar; one beside it is left standing.
func _clear_for(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _keep.has(Vector2i(x, y)):
				return false
	return true


# --- making it drawable ----------------------------------------------------

## [param cells] cut down to what the walls can draw: nothing kept (nor, with
## [param off_lanes], on a corridor's sweep), every rock cell
## in a 2x2 of rock (the room's own walls count), every floor cell beside it in a
## 2x2 of floor (a boulder or a pool counts as floor: it is scenery, not the mass).
## For the first [constant TAKE_PASSES] a sliver of floor is taken in; after that
## only rock is let go, so it always settles -- on nothing, at worst.
func _settle(cells: Dictionary[Vector2i, bool], room: Rect2i, off_lanes: bool) -> Dictionary[Vector2i, bool]:
	var keep := _keep.duplicate()
	if off_lanes:
		keep.merge(_lanes)
	var rock: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		if room.has_point(cell) and not keep.has(cell):
			rock[cell] = true
	var near := room.grow(1)
	var pass_index := 0
	while true:
		var changed := false
		for cell: Vector2i in rock.keys():
			if not _in_square(cell, rock, true):
				rock.erase(cell)
				changed = true
		for y in range(near.position.y, near.end.y):
			for x in range(near.position.x, near.end.x):
				var cell := Vector2i(x, y)
				if not _is_floor(cell, rock) or not _beside(cell, rock) or _in_square(cell, rock, false):
					continue
				if pass_index < TAKE_PASSES and room.has_point(cell) and not keep.has(cell):
					rock[cell] = true
				else:
					for step in AROUND:
						rock.erase(cell + step)
				changed = true
		if not changed:
			return rock
		pass_index += 1
	return rock


## Whether [param cell] is in a 2x2 of rock ([param solid]) or of floor, with
## [param rock] put back.
func _in_square(cell: Vector2i, rock: Dictionary[Vector2i, bool], solid: bool) -> bool:
	for corner in SQUARES:
		var whole := true
		for y in 2:
			for x in 2:
				var at := cell + corner + Vector2i(x, y)
				if (_is_rock(at, rock) if solid else _is_floor(at, rock)) == false:
					whole = false
		if whole:
			return true
	return false


func _is_rock(cell: Vector2i, rock: Dictionary[Vector2i, bool]) -> bool:
	if rock.has(cell):
		return true
	return not _open.has(cell) and _walls.get_cell_atlas_coords(cell) == Vector2i(_biome.wall_tile, 0)


func _is_floor(cell: Vector2i, rock: Dictionary[Vector2i, bool]) -> bool:
	if rock.has(cell):
		return false
	return _open.has(cell) or (_walls.get_cell_source_id(cell) != -1
			and _walls.get_cell_atlas_coords(cell) != Vector2i(_biome.wall_tile, 0))


func _beside(cell: Vector2i, rock: Dictionary[Vector2i, bool]) -> bool:
	for step in AROUND:
		if rock.has(cell + step):
			return true
	return false


# --- cutting nothing off ---------------------------------------------------

## Whether, with [param cells] and everything already put back as rock, everything
## in [param reached] is still walkable from [param arrival].
func _cuts_nothing(cells: Dictionary[Vector2i, bool], arrival: Vector2i,
		reached: Dictionary[Vector2i, bool]) -> bool:
	var blocked := filled.duplicate()
	blocked.merge(cells)
	var now := _reach(arrival, blocked)
	for cell: Vector2i in reached:
		if not blocked.has(cell) and not now.has(cell):
			return false
	return true


func _reach(from: Vector2i, blocked: Dictionary[Vector2i, bool] = {}) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in STEPS:
			var next := cell + step
			if seen.has(next) or blocked.has(next) or not _open.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


static func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
