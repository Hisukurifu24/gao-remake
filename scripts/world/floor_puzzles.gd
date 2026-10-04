class_name FloorPuzzles
extends RefCounted
## A generated floor's puzzles: the curiosities in its field rooms, each paid in a
## sealed chest.
##
## - a [b]wisp[/b] idles in a room near the entrance and, once you walk up, leads
##   you through the fog to its shrine in a room far off;
## - a ring of [b]braziers[/b] in another room wants lighting, against the clock or
##   in the order a tablet beside them gives;
## - a [b]sigil vault[/b] -- a sealed door off a room, opened by the sigils the
##   other two hold and one more in an ordinary chest. It is what chains them.
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
## Two tiles of wall round it, what every biome can draw, and a doorway through
## the wall as wide.
const VAULT_WALL := 2
## How fast the player walks, in tiles a second; how much longer than that a timed
## rite's fire burns for; and what each fire after the first adds, for turning to
## face it and pressing. The floor test holds every rite to 1.25x a real walk.
const WALK_TILES_PER_SECOND := 90.0 / 16.0
const BURN_SLACK := 1.3
const BURN_PER_FIRE := 0.6
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
const SEAL_SCENE := preload("res://scenes/world/sealed_door.tscn")

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var floor_number := 0
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
## The vault's room and doorway, in tiles, and its chest.
var vault := Rect2i()
var vault_door := Rect2i()
var vault_chest := Vector2i(-1, -1)

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
	var sources := (1 if has_wisp() else 0) + (1 if has_rite() else 0) + (1 if field_chests > 0 else 0)
	if sources >= 2:
		_plan_vault(candidates)


func has_wisp() -> bool:
	return not wisp_path.is_empty()


func has_rite() -> bool:
	return not braziers.is_empty()


func has_vault() -> bool:
	return vault.has_area()


## The flag a puzzle sets once solved, as an opened chest sets its own.
func flag(puzzle: String) -> StringName:
	return StringName("puzzle_%d_%s" % [floor_number, puzzle])


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
	# The shrine stands with its chest a cell below it, both clear all round.
	var shrine := _spot(best, func(cell: Vector2i) -> bool:
		return _clear(cell, 1) and _clear(cell + Vector2i.DOWN, 1))
	if shrine.x < 0:
		return
	var path := _guided_path(start, shrine)
	if path.is_empty():
		return
	wisp_room = start_room
	wisp_cell = start
	shrine_cell = shrine
	wisp_path = path
	_reserve(shrine, 1)
	_reserve(shrine + Vector2i.DOWN, 1)


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
	var corners: Array[Vector2i] = [
		room.position + Vector2i(1, 1), Vector2i(room.end.x - 2, room.position.y + 1),
		Vector2i(room.end.x - 2, room.end.y - 2), Vector2i(room.position.x + 1, room.end.y - 2),
	]
	var count := 4 if room.size.x >= 9 and _rng.randf() < 0.5 else 3
	var spare := _rng.randi() % 4
	var cells: Array[Vector2i] = []
	for i in count:
		cells.append(corners[(spare + 1 + i) % 4])
	var tablet := corners[spare] if count == 3 else room.position + Vector2i(2, 1)
	for cell in cells + [tablet]:
		if not _open.has(cell) or _taken.has(cell):
			return
	for cell in cells + [tablet]:
		_reserve(cell, 0)
	var chest := _spot(room, func(cell: Vector2i) -> bool: return _clear(cell, 1))
	if chest.x < 0:
		for cell in cells + [tablet]:
			_taken.erase(cell)
		return
	rite_room = room
	braziers = cells
	tablet_cell = tablet
	rite_chest = chest
	rite_mode = BrazierRite.Mode.TIMED if _rng.randf() < 0.5 else BrazierRite.Mode.ORDERED
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


# --- the vault ----------------------------------------------------------------

## A room carved out of the solid rock beside a field room, behind a sealed
## door through the wall between them. Off the north wall where any room has the
## rock for it, so the door faces you as you walk up; failing that, any wall.
## The rock round it must be untouched -- no corridor through it, no other room
## in it -- and inside the field, so the labyrinth's wall and the map's are never
## cut.
func _plan_vault(candidates: Array[Rect2i]) -> void:
	var rooms := candidates.duplicate()
	# The rooms with nothing else in them first, then the rest; a seeded start
	# within each, so it is not always the first room the generator placed.
	var shift := _rng.randi() % rooms.size()
	var ordered: Array[Rect2i] = []
	for busy in [false, true]:
		for i in rooms.size():
			var room: Rect2i = rooms[(i + shift) % rooms.size()]
			var used := room == wisp_room or room.has_point(shrine_cell) or room == rite_room
			if used == busy:
				ordered.append(room)
	for side in STEPS:
		for room in ordered:
			var along := room.size.x if side.y != 0 else room.size.y
			var offsets: Array[int] = []
			for offset in range(1, along - 2):
				offsets.append(offset)
			# Nearest the middle of the wall first.
			offsets.sort_custom(func(a: int, b: int) -> bool:
				return absi(2 * a + 2 - along) < absi(2 * b + 2 - along))
			for offset in offsets:
				if _try_vault(room, side, offset):
					return


func _try_vault(room: Rect2i, side: Vector2i, offset: int) -> bool:
	var door: Rect2i
	var inside: Rect2i
	var chest: Vector2i
	var w := VAULT_ROOM.x
	var h := VAULT_ROOM.y
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
		return false
	for y in range(rock.position.y, rock.end.y):
		for x in range(rock.position.x, rock.end.x):
			var cell := Vector2i(x, y)
			if _open.has(cell) or _taken.has(cell) or _walls.get_cell_source_id(cell) == -1:
				return false
	# The room's own cells in front of the door: open, or it is a door into a wall.
	for along in 2:
		var front: Vector2i
		match side:
			Vector2i.UP: front = Vector2i(door.position.x + along, room.position.y)
			Vector2i.DOWN: front = Vector2i(door.position.x + along, room.end.y - 1)
			Vector2i.LEFT: front = Vector2i(room.position.x, door.position.y + along)
			_: front = Vector2i(room.end.x - 1, door.position.y + along)
		if not _open.has(front) or _taken.has(front):
			return false
	vault = inside
	vault_door = door
	vault_chest = chest
	for rect: Rect2i in [inside, door]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				_walls.erase_cell(cell)
				_ground.set_cell(cell, FloorGenerator.SOURCE_ID, Vector2i(_biome.floor_tile, 0))
	for y in range(rock.position.y, rock.end.y):
		for x in range(rock.position.x, rock.end.x):
			_taken[Vector2i(x, y)] = true
	return true


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
		var chest := _add_sealed_chest(map, "ChestRite", rite_chest, flag("braziers"))
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
	_clear_monsters(map)


## A monster the floor put down where a piece now stands is stepped off it. The
## pieces are solid and a monster walks by asking whether it fits, so one that
## starts inside a brazier never leaves it. Moved, not dropped: dropping one would
## leave the floor short of the kills its boss is balanced for.
func _clear_monsters(map: Node2D) -> void:
	var solid: Dictionary[Vector2i, bool] = {}
	for cell in braziers + [tablet_cell, rite_chest, shrine_cell, shrine_cell + Vector2i.DOWN]:
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


func _reserve(cell: Vector2i, radius: int) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			_taken[cell + Vector2i(x, y)] = true


func _center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)

