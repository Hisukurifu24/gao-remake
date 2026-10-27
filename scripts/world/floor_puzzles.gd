class_name FloorPuzzles
extends RefCounted
## A generated floor's puzzles: the curiosities in its field rooms, each paid in a
## sealed chest.
##
## - a [b]wisp[/b] idles in a room near the entrance and, once you walk up, leads
##   you through the fog to its shrine in a room far off;
## - a ring of [b]braziers[/b] in another room wants lighting, against the clock or
##   in the order a tablet beside them gives;
## - four [b]statues[/b] stand round an altar in a third, looking away from it:
##   turning one turns its neighbours, and all four must face in;
## - a [b]sigil vault[/b] -- a sealed door off a room, opened by the sigils the
##   others hold and one more in an ordinary chest. It is what chains them;
## - a [b]cracked wall[/b] in a room's north wall, with a hollow behind it that is
##   solid rock until you break in. A secret, not a puzzle: it pays whoever looks.
##
## Two passes, because the generator has two moments that matter: [method plan]
## runs on the finished layout before it is dressed, and carves the vault, so the
## walls round it are joined like any other; [method place] runs once the chests
## are on the map and puts the pieces down.
##
## Everything here draws on its own seeded stream, never the floor's: asking the
## floor's rng for anything new would reshuffle every generated floor and every
## number measured on them -- the walk to the door, the trap split, where the
## monsters the balance assumes are standing. So a floor with its puzzles left
## off ([member FloorGenerator.with_puzzles]) is the same floor, minus the vault.

const TILE := 16
## The vault's room, in tiles, lying across the door's way (turned for a door in
## a side wall). Room for a chest at the back and a fight in front of it.
const VAULT_ROOM := Vector2i(6, 4)
## A cracked wall's hollow: smaller, since it is a cave rather than a room, and
## has to fit in the rock behind a north wall -- but room to fight in all the same.
const HOLLOW := Vector2i(4, 3)
## Two tiles of wall round it, what every biome can draw, and a doorway through
## the wall as wide.
const VAULT_WALL := 2
## How fast the player walks, in tiles a second; how much longer than that a timed
## rite's fire burns for; and what each fire after the first adds, for turning to
## face it and pressing. The floor test holds every rite to 1.25x a real walk.
const WALK_TILES_PER_SECOND := 90.0 / 16.0
const BURN_SLACK := 1.3
const BURN_PER_FIRE := 0.6
## Where a ring's statues stand round its altar, in ring order (so neighbours in
## this list turn together), and how far from solved a scramble may leave it:
## at least this many turns -- fewer is solved by fiddling -- and at most this.
const RING: Array[Vector2i] = [Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0)]
const RING_TURNS_MIN := 4
const RING_TURNS_MAX := 8
## What a sealed chest holds: the best of what the floor can give. Until there is
## more gear than this, that is these -- and Col, once M5.6 lands.
const SEALED_LOOT: Array[StringName] = [
	&"blackwyrm_coat", &"swift_charm", &"kobold_blade", &"guard_ring",
]

const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const WISP_SCENE := preload("res://scenes/world/wisp.tscn")
const SHRINE_SCENE := preload("res://scenes/world/wisp_shrine.tscn")
const BRAZIER_SCENE := preload("res://scenes/world/brazier.tscn")
const TABLET_SCENE := preload("res://scenes/world/tablet.tscn")
const STATUE_SCENE := preload("res://scenes/world/statue.tscn")
const ALTAR_SCENE := preload("res://scenes/world/statue_altar.tscn")
const SEAL_SCENE := preload("res://scenes/world/sealed_door.tscn")
const CRACK_SCENE := preload("res://scenes/world/cracked_wall.tscn")
## Biomes whose wall cannot crack: the sky's is open air.
const UNCRACKABLE: Array[StringName] = [&"sky"]

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var floor_number := 0
## What every flag here starts with; empty is [code]puzzle_<n>[/code]. A dungeon's
## level names its own ([DungeonGenerator]), since its pieces are that level's seal.
var flag_prefix := ""
## Whether a solved rite or ring pays in a sealed chest. Off on a dungeon, where
## what it pays is the stairs.
var with_chests := true
## The wisp's room and cell, the shrine it leads to, and the way there in cells.
var wisp_room := Rect2i()
var wisp_cell := Vector2i(-1, -1)
var shrine_cell := Vector2i(-1, -1)
var wisp_path: Array[Vector2i] = []
## The braziers' room, their cells, and how they are to be lit.
var rite_room := Rect2i()
var braziers: Array[Vector2i] = []
var rite_mode := BrazierRite.Mode.TIMED
var rite_order: Array[int] = []
var rite_burn := 0.0
var tablet_cell := Vector2i(-1, -1)
var rite_chest := Vector2i(-1, -1)
## The statues' room, their altar, where each stands (in [constant RING] order),
## which way each starts out facing, and the fewest turns that solve them.
var statue_room := Rect2i()
var altar_cell := Vector2i(-1, -1)
var statue_cells: Array[Vector2i] = []
var statue_facings: Array[int] = []
var statue_turns := 0
var statue_chest := Vector2i(-1, -1)
## The vault's room and doorway, in tiles, and its chest.
var vault := Rect2i()
var vault_door := Rect2i()
var vault_chest := Vector2i(-1, -1)
## The cracked wall's doorway and hollow, in tiles -- rock until it is broken --
## and the chest in the hollow.
var crack_door := Rect2i()
## Which way the doorway goes from the room.
var crack_side := Vector2i.UP
var crack_hollow := Rect2i()
var crack_chest := Vector2i(-1, -1)

var _rng := RandomNumberGenerator.new()
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool]
var _field := Rect2i()
## Cells a piece stands in or keeps clear round it.
var _taken: Dictionary[Vector2i, bool] = {}
var _field_chests := 0


## [param open] is the generator's carved cells with decor taken out -- read,
## never written. [param field] is where the rooms are; nothing here leaves it.
func _init(number: int, generation_seed: int, biome: BiomeKit, ground: TileMapLayer,
		walls: TileMapLayer, open: Dictionary[Vector2i, bool], field: Rect2i) -> void:
	floor_number = number
	_rng.seed = hash("%d:puzzles" % generation_seed)
	_biome = biome
	_ground = ground
	_walls = walls
	_open = open
	_field = field


## Decides where everything goes, and carves the vault. [param chest_cells] are the
## floor's chests, the first [param field_chests] of them in the field.
func plan(rooms: Array[Rect2i], entry: Rect2i, chest_cells: Array[Vector2i],
		field_chests: int) -> void:
	_field_chests = field_chests
	for cell in chest_cells:
		_reserve(cell, 1)
	var candidates: Array[Rect2i] = []
	for room in rooms:
		if room != entry:
			candidates.append(room)
	if candidates.size() < 2:
		return
	_plan_wisp(candidates, entry, chest_cells)
	_plan_rite(candidates, chest_cells)
	_plan_statues(candidates, chest_cells)
	var sources := (1 if has_wisp() else 0) + (1 if has_rite() else 0) \
			+ (1 if has_statues() else 0) + (1 if field_chests > 0 else 0)
	if sources >= 2:
		_plan_vault(candidates)
	if not _biome.id in UNCRACKABLE:
		_plan_crack(candidates)


func has_wisp() -> bool:
	return not wisp_path.is_empty()


func has_rite() -> bool:
	return not braziers.is_empty()


func has_statues() -> bool:
	return not statue_cells.is_empty()


## The way each of a ring's statues faces once solved: at the altar in the middle.
static func ring_targets() -> Array[int]:
	var targets: Array[int] = []
	for i in RING.size():
		targets.append(posmod(i + 2, 4))
	return targets


func has_vault() -> bool:
	return vault.has_area()


func has_crack() -> bool:
	return crack_hollow.has_area()


## The flag a puzzle sets once solved, as an opened chest sets its own.
func flag(puzzle: String) -> StringName:
	var prefix := flag_prefix if not flag_prefix.is_empty() else "puzzle_%d" % floor_number
	return StringName("%s_%s" % [prefix, puzzle])


# --- an authored floor's -------------------------------------------------------

## An authored floor's puzzles are chosen, not rolled: its script names the room
## each one goes in, in place of [method plan], and the pieces are put down where
## a generated floor's would be in that room. What is left to the stream -- a
## rite's corners and order, a ring's scramble, the sealed loot -- is fixed by the
## floor's own seed, so the tool writes the same floor every time it is run.
## [param chest_cells] are the floor's chests, every one a field chest here.
func hold(chest_cells: Array[Vector2i], keep_out: Array[Rect2i]) -> void:
	_field_chests = chest_cells.size()
	for cell in chest_cells:
		_reserve(cell, 1)
	for rect in keep_out:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_taken[Vector2i(x, y)] = true


## A wisp idling in [param start_room] that leads to a shrine in [param shrine_room].
func pin_wisp(start_room: Rect2i, shrine_room: Rect2i) -> bool:
	var start := _spot(start_room, func(cell: Vector2i) -> bool: return _clear(cell, 1))
	return start.x >= 0 and _lead(start_room, start, shrine_room)


## [param count] braziers round [param room], lit by [param mode].
func pin_rite(room: Rect2i, mode: BrazierRite.Mode, count := 3) -> bool:
	return _rite_in(room, count, _rng.randi() % 4, mode)


func pin_statues(room: Rect2i) -> bool:
	return _statues_in(room)


## The vault off [param room]'s [param side] wall, nearest the middle of it.
func pin_vault(room: Rect2i, side: Vector2i) -> bool:
	for offset in _wall_offsets(room, side):
		var pocket := _pocket(room, side, offset, VAULT_ROOM)
		if not pocket.is_empty():
			_carve_vault(pocket)
			return true
	return false


## A cracked wall in [param room]'s [param side] wall, nearest the middle of it.
## Never the south: see [method _plan_crack].
func pin_crack(room: Rect2i, side: Vector2i) -> bool:
	if side == Vector2i.DOWN or _biome.id in UNCRACKABLE:
		return false
	for offset in _wall_offsets(room, side):
		var pocket := _pocket(room, side, offset, HOLLOW)
		if not pocket.is_empty():
			_take_crack(pocket, side)
			return true
	return false


# --- the wisp ---------------------------------------------------------------

## The wisp waits in a room in the near half of the field from the entrance -- you
## should meet it early -- and its shrine is in whichever room is the longest walk
## from there: it is a guide, so it should take you somewhere.
func _plan_wisp(candidates: Array[Rect2i], entry: Rect2i, chest_cells: Array[Vector2i]) -> void:
	var from_entry := _walk_from(_center(entry))
	var near := candidates.duplicate()
	near.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return _room_steps(from_entry, a) < _room_steps(from_entry, b))
	near = near.slice(0, maxi(1, near.size() / 2))
	var start_room: Rect2i = near[_rng.randi() % near.size()]
	var start := _spot(start_room, func(cell: Vector2i) -> bool: return _clear(cell, 1))
	if start.x < 0:
		return
	var from_start := _walk_from(start)
	var best := Rect2i()
	var best_steps := -1
	for room in candidates:
		if room == start_room:
			continue
		var steps := _room_steps(from_start, room)
		if steps < (1 << 20) and steps > best_steps:
			best_steps = steps
			best = room
	if best_steps < 0:
		return
	_lead(start_room, start, best)


## The wisp idling at [param start] in [param start_room], and its shrine in
## [param shrine_room]. False if the shrine has no room or there is no way there.
func _lead(start_room: Rect2i, start: Vector2i, best: Rect2i) -> bool:
	# The shrine stands with its chest a cell below it, both clear all round.
	var shrine := _spot(best, func(cell: Vector2i) -> bool:
		return _clear(cell, 1) and _clear(cell + Vector2i.DOWN, 1))
	if shrine.x < 0:
		return false
	var path := _guided_path(start, shrine)
	if path.is_empty():
		return false
	wisp_room = start_room
	wisp_cell = start
	shrine_cell = shrine
	wisp_path = path
	_reserve(shrine, 1)
	_reserve(shrine + Vector2i.DOWN, 1)
	return true


## The way from [param from] to [param to] through the field, keeping off the
## walls where it can: a cell beside one costs more, so the wisp drifts down the
## middle of a corridor rather than hugging its corners.
func _guided_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cost: Dictionary[Vector2i, int] = {from: 0}
	var parent: Dictionary[Vector2i, Vector2i] = {from: from}
	var frontier: Array = [[0, from]]
	while not frontier.is_empty():
		var lowest := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[lowest][0]:
				lowest = i
		var entry: Array = frontier[lowest]
		frontier.remove_at(lowest)
		var cell: Vector2i = entry[1]
		if entry[0] > cost[cell]:
			continue
		if cell == to:
			break
		for step in STEPS:
			var next := cell + step
			if not _open.has(next) or not _field.has_point(next):
				continue
			var price: int = cost[cell] + (1 if _clear(next, 1, false) else 3)
			if price < cost.get(next, 1 << 30):
				cost[next] = price
				parent[next] = cell
				frontier.append([price, next])
	if not parent.has(to):
		return []
	var path: Array[Vector2i] = [to]
	while path[0] != from:
		path.push_front(parent[path[0]])
	return path


# --- the braziers -------------------------------------------------------------

## Three braziers in three corners of a room with no chest in it, and the tablet
## in the fourth -- or, in a room nine wide, four braziers and the tablet beside
## the first. Corners a cell in: the ring round a room's edge is never decor, so
## every brazier can be walked up to, and the centre lines a corridor comes in by
## stay clear.
func _plan_rite(candidates: Array[Rect2i], chest_cells: Array[Vector2i]) -> void:
	var eligible: Array[Rect2i] = []
	for room in candidates:
		if room == wisp_room or room.has_point(shrine_cell):
			continue
		var has_chest := false
		for cell in chest_cells:
			if room.grow(1).has_point(cell):
				has_chest = true
		if not has_chest:
			eligible.append(room)
	if eligible.is_empty():
		return
	var room: Rect2i = eligible[_rng.randi() % eligible.size()]
	var count := 4 if room.size.x >= 9 and _rng.randf() < 0.5 else 3
	_rite_in(room, count, _rng.randi() % 4, -1)


## [param count] braziers in the corners of [param room] but corner [param spare],
## lit by [param mode] -- or, at -1, whichever the stream says. False if a corner
## is not free floor or the chest has nowhere to stand.
func _rite_in(room: Rect2i, count: int, spare: int, mode: int) -> bool:
	var corners: Array[Vector2i] = [
		room.position + Vector2i(1, 1), Vector2i(room.end.x - 2, room.position.y + 1),
		Vector2i(room.end.x - 2, room.end.y - 2), Vector2i(room.position.x + 1, room.end.y - 2),
	]
	var cells: Array[Vector2i] = []
	for i in count:
		cells.append(corners[(spare + 1 + i) % 4])
	var tablet := corners[spare] if count == 3 else room.position + Vector2i(2, 1)
	for cell in cells + [tablet]:
		if not _open.has(cell) or _taken.has(cell):
			return false
	for cell in cells + [tablet]:
		_reserve(cell, 0)
	var chest := _spot(room, func(cell: Vector2i) -> bool: return _clear(cell, 1))
	if chest.x < 0:
		for cell in cells + [tablet]:
			_taken.erase(cell)
		return false
	rite_room = room
	braziers = cells
	tablet_cell = tablet
	rite_chest = chest
	if mode < 0:
		rite_mode = BrazierRite.Mode.TIMED if _rng.randf() < 0.5 else BrazierRite.Mode.ORDERED
	else:
		rite_mode = mode as BrazierRite.Mode
	rite_order.clear()
	for i in cells.size():
		rite_order.append(i)
	if rite_mode == BrazierRite.Mode.ORDERED:
		for i in range(rite_order.size() - 1, 0, -1):
			var j := _rng.randi() % (i + 1)
			var swap := rite_order[i]
			rite_order[i] = rite_order[j]
			rite_order[j] = swap
	else:
		# Long enough to walk the shortest way round them, with slack for the
		# turning: the floor test walks it for real and holds the fire to it.
		rite_burn = BURN_PER_FIRE * (cells.size() - 1) \
				+ _tour_tiles(cells) / WALK_TILES_PER_SECOND * BURN_SLACK
	_reserve(chest, 1)
	return true


## The shortest walk that visits every one of [param cells], from any of them,
## counted in tiles corner to corner -- the braziers stand round one room's edge,
## and nothing stands in the ring between them.
static func _tour_tiles(cells: Array[Vector2i]) -> int:
	var best := 1 << 30
	for order in _orders(cells.size()):
		var tiles := 0
		for i in range(1, order.size()):
			var step: Vector2i = (cells[order[i]] - cells[order[i - 1]]).abs()
			tiles += step.x + step.y
		best = mini(best, tiles)
	return best


static func _orders(count: int) -> Array:
	if count <= 1:
		return [[0]]
	var orders: Array = []
	for order: Array in _orders(count - 1):
		for at in count:
			var longer := order.duplicate()
			longer.insert(at, count - 1)
			orders.append(longer)
	return orders


# --- the statues ---------------------------------------------------------------

## Four statues round an altar, two cells out on each side, in a room with no
## chest and no other puzzle in it. A statue stands a cell in from the room's
## edge, or on it with rock at its back -- never in a corridor's mouth -- and the
## sealed chest stands clear of every piece, a corner of the ring at the nearest.
func _plan_statues(candidates: Array[Rect2i], chest_cells: Array[Vector2i]) -> void:
	var eligible: Array[Rect2i] = []
	for room in candidates:
		if room == wisp_room or room.has_point(shrine_cell) or room == rite_room:
			continue
		var has_chest := false
		for cell in chest_cells:
			if room.grow(1).has_point(cell):
				has_chest = true
		if not has_chest:
			eligible.append(room)
	if eligible.is_empty():
		return
	var shift := _rng.randi() % eligible.size()
	for i in eligible.size():
		if _statues_in(eligible[(i + shift) % eligible.size()]):
			return


## A ring round an altar in [param room], nearest its middle, and its chest clear
## of every piece. False if the room has no place for one.
func _statues_in(room: Rect2i) -> bool:
	var altar := _spot(room, func(cell: Vector2i) -> bool: return _ring_fits(room, cell))
	if altar.x < 0:
		return false
	var pieces: Array[Vector2i] = [altar]
	for offset in RING:
		pieces.append(altar + offset)
	var chest := _spot(room, func(cell: Vector2i) -> bool:
		if not _clear(cell, 1, false) or _taken.has(cell):
			return false
		for piece in pieces:
			var off := (cell - piece).abs()
			if maxi(off.x, off.y) < 2:
				return false
		return true)
	if chest.x < 0:
		return false
	statue_room = room
	altar_cell = altar
	statue_chest = chest
	statue_cells = pieces.slice(1)
	for piece in pieces:
		_reserve(piece, 0)
	_reserve(chest, 1)
	_scramble_statues()
	return true


## Whether a ring round [param altar] fits in [param room]: the five cells carved,
## unclaimed and free of decor, with the cells between them, and each statue
## inside the room's edge or backed onto rock.
func _ring_fits(room: Rect2i, altar: Vector2i) -> bool:
	if not _clear(altar, 1):
		return false
	var inner := room.grow(-1)
	for offset in RING:
		var cell := altar + offset
		if not room.has_point(cell) or not _open.has(cell) or _taken.has(cell):
			return false
		if not inner.has_point(cell) and _open.has(cell + offset / 2):
			return false
	return true


## Turns the solved ring backwards a seeded number of times, so whatever it shows
## is solvable by construction -- by turning each statue as many more times as
## makes four. Tried until it lands between [constant RING_TURNS_MIN] and
## [constant RING_TURNS_MAX] turns from solved, with more than one statue to turn.
func _scramble_statues() -> void:
	var count := RING.size()
	var targets := ring_targets()
	var turns: Array[int] = []
	for _try in 64:
		turns.clear()
		var total := 0
		var moving := 0
		for i in count:
			turns.append(_rng.randi() % 4)
			total += turns[i]
			moving += 1 if turns[i] > 0 else 0
		if total >= RING_TURNS_MIN and total <= RING_TURNS_MAX and moving >= 2:
			break
	statue_facings.clear()
	statue_turns = 0
	for i in count:
		var moved := 0
		for j in StatueRing.turned_by(i, count):
			moved += turns[j]
		statue_facings.append(posmod(targets[i] - moved, 4))
		statue_turns += turns[i]


# --- the vault ----------------------------------------------------------------

## A room carved out of the solid rock beside a field room, behind a sealed
## door through the wall between them. Off the north wall where any room has the
## rock for it, so the door faces you as you walk up; failing that, any wall.
## The rock round it must be untouched -- no corridor through it, no other room
## in it -- and inside the field, so the labyrinth's wall and the map's are never
## cut.
func _plan_vault(candidates: Array[Rect2i]) -> void:
	var ordered := _quiet_first(candidates)
	for side in STEPS:
		for room in ordered:
			for offset in _wall_offsets(room, side):
				var pocket := _pocket(room, side, offset, VAULT_ROOM)
				if not pocket.is_empty():
					_carve_vault(pocket)
					return


## The rooms with nothing else in them first, then the rest; a seeded start
## within each, so it is not always the first room the generator placed.
func _quiet_first(candidates: Array[Rect2i]) -> Array[Rect2i]:
	var shift := _rng.randi() % candidates.size()
	var ordered: Array[Rect2i] = []
	for busy in [false, true]:
		for i in candidates.size():
			var room: Rect2i = candidates[(i + shift) % candidates.size()]
			var used := room == wisp_room or room.has_point(shrine_cell) or room == rite_room \
					or room == statue_room or room.grow(VAULT_WALL).intersects(vault_door)
			if used == busy:
				ordered.append(room)
	return ordered


## Where along [param room]'s [param side] wall a two-wide doorway may go,
## nearest the middle of the wall first.
func _wall_offsets(room: Rect2i, side: Vector2i) -> Array[int]:
	var along := room.size.x if side.y != 0 else room.size.y
	var offsets: Array[int] = []
	for offset in range(1, along - 2):
		offsets.append(offset)
	offsets.sort_custom(func(a: int, b: int) -> bool:
		return absi(2 * a + 2 - along) < absi(2 * b + 2 - along))
	return offsets


func _carve_vault(pocket: Array) -> void:
	vault_door = pocket[0]
	vault = pocket[1]
	vault_chest = pocket[2]
	for rect: Rect2i in [vault, vault_door]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				_walls.erase_cell(cell)
				_ground.set_cell(cell, FloorGenerator.SOURCE_ID, Vector2i(_biome.floor_tile, 0))
	_claim(pocket)


## A hollow behind a crack in a room's wall: the north wall where any room has
## the rock for it, so the crack faces you as you walk up, then the sides. Never
## the south, where the crack would be on the rock's top, under your feet.
## Left as rock: [CrackedWall] carves it when it breaks.
func _plan_crack(candidates: Array[Rect2i]) -> void:
	var ordered := _quiet_first(candidates)
	for side: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		for room in ordered:
			for offset in _wall_offsets(room, side):
				var pocket := _pocket(room, side, offset, HOLLOW)
				if not pocket.is_empty():
					_take_crack(pocket, side)
					return


func _take_crack(pocket: Array, side: Vector2i) -> void:
	crack_side = side
	crack_door = pocket[0]
	crack_hollow = pocket[1]
	crack_chest = pocket[2]
	_claim(pocket)


## Keeps the rock round a pocket for it, and the cells in front of its doorway.
func _claim(pocket: Array) -> void:
	var rock := (pocket[1] as Rect2i).grow(VAULT_WALL)
	for y in range(rock.position.y, rock.end.y):
		for x in range(rock.position.x, rock.end.x):
			_taken[Vector2i(x, y)] = true
	for cell: Vector2i in pocket[3]:
		_taken[cell] = true


## A pocket of [param size] in untouched rock off [param room]'s [param side] wall,
## [param offset] cells along it, behind a two-wide doorway through the wall:
## [code][doorway, room, chest cell, cells in front][/code], or empty where the
## rock is cut or claimed, or would take the field's own wall.
func _pocket(room: Rect2i, side: Vector2i, offset: int, size: Vector2i) -> Array:
	var door: Rect2i
	var inside: Rect2i
	var chest: Vector2i
	var w := size.x
	var h := size.y
	match side:
		Vector2i.UP:
			door = Rect2i(room.position.x + offset, room.position.y - VAULT_WALL, 2, VAULT_WALL)
			inside = Rect2i(door.position.x - (w - 2) / 2, door.position.y - h, w, h)
			chest = Vector2i(door.position.x, inside.position.y)
		Vector2i.DOWN:
			door = Rect2i(room.position.x + offset, room.end.y, 2, VAULT_WALL)
			inside = Rect2i(door.position.x - (w - 2) / 2, door.end.y, w, h)
			chest = Vector2i(door.position.x, inside.end.y - 1)
		Vector2i.LEFT:
			door = Rect2i(room.position.x - VAULT_WALL, room.position.y + offset, VAULT_WALL, 2)
			inside = Rect2i(door.position.x - h, door.position.y - (w - 2) / 2, h, w)
			chest = Vector2i(inside.position.x, door.position.y)
		_:
			door = Rect2i(room.end.x, room.position.y + offset, VAULT_WALL, 2)
			inside = Rect2i(door.end.x, door.position.y - (w - 2) / 2, h, w)
			chest = Vector2i(inside.end.x - 1, door.position.y)
	var rock := inside.grow(VAULT_WALL)
	if not _field.encloses(rock):
		return []
	for y in range(rock.position.y, rock.end.y):
		for x in range(rock.position.x, rock.end.x):
			var cell := Vector2i(x, y)
			if _open.has(cell) or _taken.has(cell) or _walls.get_cell_source_id(cell) == -1:
				return []
	# The room's own cells in front of the door: open, or it is a door into a wall.
	var fronts: Array[Vector2i] = []
	for along in 2:
		var front: Vector2i
		match side:
			Vector2i.UP: front = Vector2i(door.position.x + along, room.position.y)
			Vector2i.DOWN: front = Vector2i(door.position.x + along, room.end.y - 1)
			Vector2i.LEFT: front = Vector2i(room.position.x, door.position.y + along)
			_: front = Vector2i(room.end.x - 1, door.position.y + along)
		if not _open.has(front) or _taken.has(front):
			return []
		fronts.append(front)
	return [door, inside, chest, fronts]


# --- putting it down ------------------------------------------------------------

## Adds the pieces to [param map], once the floor's own chests are on it.
func place(map: Node2D) -> void:
	var sigils: Array[StringName] = []
	if has_wisp():
		var chest := _add_sealed_chest(map, "ChestWisp", shrine_cell + Vector2i.DOWN, flag("wisp"))
		var shrine := SHRINE_SCENE.instantiate()
		shrine.name = "WispShrine"
		shrine.position = _world(shrine_cell)
		shrine.set(&"solved_flag", flag("wisp"))
		map.add_child(shrine)
		var wisp := WISP_SCENE.instantiate()
		wisp.name = "Wisp"
		wisp.position = _world(wisp_cell)
		var points := PackedVector2Array()
		for cell in wisp_path:
			points.append(_world(cell))
		wisp.set(&"path", points)
		wisp.set(&"solved_flag", flag("wisp"))
		map.add_child(wisp)
		if has_vault():
			sigils.append(_sigil(chest, sigils.size()))
	if has_rite():
		var chest: Chest = _add_sealed_chest(map, "ChestRite", rite_chest, flag("braziers")) \
				if with_chests else null
		var rite := BrazierRite.new()
		rite.name = "BrazierRite"
		rite.mode = rite_mode
		rite.order = rite_order
		rite.burn = rite_burn
		rite.solved_flag = flag("braziers")
		map.add_child(rite)
		for i in braziers.size():
			var brazier := BRAZIER_SCENE.instantiate()
			brazier.name = "Brazier%d" % i
			brazier.position = _world(braziers[i])
			brazier.set(&"index", i)
			map.add_child(brazier)
			rite.braziers.append(brazier)
		var tablet := TABLET_SCENE.instantiate()
		tablet.name = "Tablet"
		tablet.position = _world(tablet_cell)
		tablet.set(&"lines", _tablet_lines())
		map.add_child(tablet)
		if has_vault():
			sigils.append(_sigil(chest, sigils.size()))
	if has_statues():
		var chest: Chest = _add_sealed_chest(map, "ChestStatues", statue_chest, flag("statues")) \
				if with_chests else null
		var ring := StatueRing.new()
		ring.name = "StatueRing"
		ring.targets = ring_targets()
		ring.solved_flag = flag("statues")
		map.add_child(ring)
		var altar := ALTAR_SCENE.instantiate()
		altar.name = "StatueAltar"
		altar.position = _world(altar_cell)
		altar.set(&"solved_flag", flag("statues"))
		map.add_child(altar)
		for i in statue_cells.size():
			var statue := STATUE_SCENE.instantiate() as Statue
			statue.name = "Statue%d" % i
			statue.position = _world(statue_cells[i])
			statue.index = i
			statue.facing = statue_facings[i] as Statue.Facing
			map.add_child(statue)
			ring.statues.append(statue)
		if has_vault():
			sigils.append(_sigil(chest, sigils.size()))
	if has_vault():
		# One more in the field, under the floor's own loot -- a gilded chest's, if it
		# has one: the gamble is what the third sigil costs.
		var plain: Array[Chest] = []
		var gilded: Array[Chest] = []
		for i in _field_chests:
			var found := map.get_node_or_null("Chest%d" % i) as Chest
			if found != null:
				(gilded if found.gilded else plain).append(found)
		var pool := gilded if not gilded.is_empty() else plain
		if not pool.is_empty():
			sigils.append(_sigil(pool[_rng.randi() % pool.size()], sigils.size()))
		var seal := SEAL_SCENE.instantiate()
		seal.name = "SealedDoor"
		seal.position = Vector2(vault_door.position * TILE) + Vector2(vault_door.size * TILE) / 2.0
		seal.set(&"sigils", sigils)
		seal.set(&"opened_flag", flag("vault"))
		map.add_child(seal)
		_add_sealed_chest(map, "ChestVault", vault_chest, &"")
		map.set_meta(&"vault", vault)
		map.set_meta(&"vault_door", vault_door)
	if has_crack():
		_add_sealed_chest(map, "ChestCrack", crack_chest, flag("crack"))
		var crack := CRACK_SCENE.instantiate() as CrackedWall
		crack.name = "CrackedWall"
		crack.door = crack_door
		crack.hollow = crack_hollow
		crack.opened_flag = flag("crack")
		crack.side = crack_side
		crack.in_trees = _biome.wall_style == BiomeKit.WallStyle.TREES
		crack.position = CrackedWall.face_of(crack_door, crack_side)
		map.add_child(crack)
		if crack.in_trees:
			# The trees on the doorway make way for the boulder.
			var clear := {}
			for y in range(crack_door.position.y, crack_door.end.y):
				for x in range(crack_door.position.x, crack_door.end.x):
					clear[Vector2i(x, y)] = true
			var rng := RandomNumberGenerator.new()
			rng.seed = _rng.randi()
			MapDresser.step_trees_back(map, _biome, _walls, clear, rng)
	_clear_monsters(map)


## A monster the floor put down where a piece now stands is stepped off it. The
## pieces are solid and a monster walks by asking whether it fits, so one that
## starts inside a brazier never leaves it. Moved, not dropped: dropping one would
## leave the floor short of the kills its boss is balanced for.
func _clear_monsters(map: Node2D) -> void:
	var solid: Dictionary[Vector2i, bool] = {}
	for cell in braziers + statue_cells + [tablet_cell, rite_chest, shrine_cell,
			shrine_cell + Vector2i.DOWN, altar_cell, statue_chest]:
		solid[cell] = true
	for child in map.get_children():
		var monster := child as Monster
		if monster == null:
			continue
		var at := Vector2i(monster.position / TILE)
		if not solid.has(at):
			continue
		for step in STEPS:
			if _open.has(at + step) and not solid.has(at + step):
				monster.position = _world(at + step)
				break


func _add_sealed_chest(map: Node2D, chest_name: String, cell: Vector2i, hidden_until: StringName) -> Chest:
	var chest := CHEST_SCENE.instantiate() as Chest
	chest.name = chest_name
	chest.position = _world(cell)
	chest.sealed = true
	chest.hidden_until = hidden_until
	chest.item_id = SEALED_LOOT[_rng.randi() % SEALED_LOOT.size()]
	chest.amount = 1
	chest.floor_number = floor_number
	chest.opened_flag = StringName("floor_%d_%s" % [floor_number, chest_name.to_snake_case()])
	map.add_child(chest)
	return chest


func _sigil(chest: Chest, index: int) -> StringName:
	chest.sigil_flag = flag("sigil_%d" % index)
	return chest.sigil_flag


## What the stone beside the braziers says: the rule, and for an ordered rite the
## order, by the corner each brazier stands in.
func _tablet_lines() -> PackedStringArray:
	var count: String = ["", "one", "two", "three", "four"][braziers.size()]
	if rite_mode == BrazierRite.Mode.TIMED:
		return PackedStringArray([
			"Words cut into the stone: \"Wake all %s fires while the first still burns.\"" % count,
		])
	var names: PackedStringArray = PackedStringArray()
	for i in rite_order:
		names.append(_corner_name(braziers[i]))
	var said := "First the %s fire" % names[0]
	for i in range(1, names.size()):
		said += ", %s the %s" % ["then" if i < names.size() - 1 else "and last", names[i]]
	return PackedStringArray([
		"Words cut into the stone: \"%s.\"" % said,
		"\"The fire walks. Wake it out of turn and it sleeps again.\"",
	])


func _corner_name(cell: Vector2i) -> String:
	var middle := rite_room.position + rite_room.size / 2
	return ("north" if cell.y < middle.y else "south") + ("-west" if cell.x < middle.x else "-east")


# --- plumbing ---------------------------------------------------------------

## Walking distance over carved floor from [param from], within the field.
func _walk_from(from: Vector2i) -> Dictionary[Vector2i, int]:
	var steps: Dictionary[Vector2i, int] = {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in STEPS:
			var next := cell + step
			if not steps.has(next) and _open.has(next) and _field.has_point(next):
				steps[next] = steps[cell] + 1
				queue.append(next)
	return steps


## The fewest steps in [param steps] to any cell of [param room]; 1 << 20 if none.
static func _room_steps(steps: Dictionary[Vector2i, int], room: Rect2i) -> int:
	var best := 1 << 20
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			best = mini(best, steps.get(Vector2i(x, y), 1 << 20))
	return best


## The cell of [param room] nearest its middle that [param fits] -- or (-1, -1).
## Rooms only; the scan is in reading order, so ties go the same way every time.
func _spot(room: Rect2i, fits: Callable) -> Vector2i:
	var middle := _center(room)
	var best := Vector2i(-1, -1)
	var best_off := 1 << 30
	for y in range(room.position.y + 1, room.end.y - 1):
		for x in range(room.position.x + 1, room.end.x - 1):
			var cell := Vector2i(x, y)
			var off := (cell - middle).abs()
			if off.x + off.y < best_off and fits.call(cell):
				best_off = off.x + off.y
				best = cell
	return best


## Whether every cell within [param radius] of [param cell] is carved floor --
## and, with [param free], that nothing else has claimed it.
func _clear(cell: Vector2i, radius: int, free := true) -> bool:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var at := cell + Vector2i(x, y)
			if not _open.has(at) or (free and _taken.has(at)):
				return false
	return true


## Keeps the puzzles off [param cell] and the [param radius] round it -- something the
## floor stands there that they must not crowd (an open field's waystones and fire).
## Before [method plan].
func keep_clear(cell: Vector2i, radius: int) -> void:
	_reserve(cell, radius)


func _reserve(cell: Vector2i, radius: int) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			_taken[cell + Vector2i(x, y)] = true


func _center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)

