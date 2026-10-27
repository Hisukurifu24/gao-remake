class_name DungeonGenerator
extends FloorGenerator
## A dungeon floor ([enum FloorDefinition.Shape]): no field and no labyrinth, but
## [b]levels[/b] -- small dark maps of rooms and corridors, climbed by ladders, with
## the boss on the top one.
##
## - [b]Level 1[/b] opens on the entrance hall: the camp (later the village), the
##   teleport gate and the stairs down, lamplit. Past it the dark begins.
## - Every level below the top has a [b]stair chamber[/b] on a strip of its own, as an
##   open field's arena has: walled round, one doorway, and the ladder up against its
##   back wall. A [SealedDoor] stands in the doorway, and something on that level
##   opens it -- a [b]warden[/b] whose fall is the key, two [b]levers[/b], a
##   [b]brazier rite[/b] or a [b]statue ring[/b] ([enum Seal]). On a dungeon the
##   puzzles are the way through, not a side room's loot.
## - A middle level has a [b]landing[/b]: a room with a fire, a safe zone.
## - The [b]top[/b] is a short walk to the boss hall, lit, its door in plain view and
##   found as you arrive.
##
## A level is its own map, [code]floor://n/s[/code] ([method SceneRouter.floor_path]);
## level 1 is [code]floor://n[/code], so every gate, defeat and save that knew the
## floor finds its entrance where it was. Each level grows from its own seed
## ([method level_seed]), so it is the same level however it is reached. Monsters and
## chests are the floor's, shared out between the levels below the top, so the boss's
## balance is the floor's whatever shape it is.
##
## Built on [FloorGenerator]'s helpers -- rooms, corridors, the strip, chests,
## monsters -- and on [FloorPuzzles]' rite and ring, pinned into a room.

## What seals a level's stairs up.
enum Seal { WARDEN, LEVERS, BRAZIERS, STATUES }
const SEAL_NAMES: PackedStringArray = ["warden", "levers", "braziers", "statues"]

## The stair chamber inside its wall: room for the ladder against the back wall, a
## doorway's walk in front of it, and a fight.
const STAIR_ROOM := Vector2i(6, 6)
## A level's rooms: a little smaller than a field's, since a level is small.
const ROOM_W := Vector2i(7, 11)
const ROOM_H := Vector2i(6, 8)
## Level 1's rooms and corridors are bigger by this: the entrance hall's camp
## ([constant FloorCamp.PLOT]) is carved round its arrival room.
const HALL_EXTRA := Vector2i(10, 6)
## The top level: two rooms and the boss hall -- a short walk, not a level to search.
const TOP_FIELD := Vector2i(30, 20)
const TOP_ROOMS := 2
const TOP_ROOM_W := Vector2i(7, 9)
const TOP_ROOM_H := Vector2i(6, 7)
## How many levels a warden stands above the floor's monsters.
const WARDEN_LEVELS := 2
const LEVERS := 2

const LADDER_SCENE := preload("res://scenes/world/ladder.tscn")
const LEVER_SCENE := preload("res://scenes/world/lever.tscn")

## What this level is: its number, the floor's count, and whether it is the top.
var _level := 1
var _levels := 1
var _top := false
## The seal planned for this level, and what it needs.
var _seal := -1
var _lever_cells: Array[Vector2i] = []
var _warden_cell := Vector2i(-1, -1)
var _puzzles: FloorPuzzles = null


## The seed level [param level] of a floor grows from. Level 1's is the floor's
## own, so the camp, which only stands there, reads the streams it does on any floor.
static func level_seed(floor_seed: int, level: int) -> int:
	if level <= 1:
		return floor_seed
	return hash("%d:level:%d" % [floor_seed, level])


## [member GameMap.map_id] of [param floor_number]'s [param level]: the floor's own
## for the first, as [method level_seed] is.
static func map_id_for(floor_number: int, level: int) -> StringName:
	if level <= 1:
		return StringName("floor_%d" % floor_number)
	return StringName("floor_%d_%d" % [floor_number, level])


## Which level of [param levels] has the landing: the middle one, never the first
## (the entrance hall is where you start) or the top (the boss is there).
static func landing_level(levels: int) -> int:
	return maxi(2, (levels + 1) / 2)


## What seals each level's stairs, indexed by level (index 0 and the top are -1):
## from the floor's own stream, [code]hash("<seed>:seals")[/code], never the same
## twice running. Where a level has no room for its seal, a warden stands in for
## it -- see [method _plan_seal].
static func seal_kinds(floor_seed: int, levels: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:seals" % floor_seed)
	var kinds: Array[int] = [-1]
	for level in range(1, levels + 1):
		if level == levels:
			kinds.append(-1)
			continue
		var kind := rng.randi() % SEAL_NAMES.size()
		if kind == kinds[level - 1]:
			kind = (kind + 1 + rng.randi() % (SEAL_NAMES.size() - 1)) % SEAL_NAMES.size()
		kinds.append(kind)
	return kinds


## [param total] shared between [param shares] as evenly as it goes, the first
## ones taking the remainder: the [param index]th share (0-based).
static func share_of(total: int, shares: int, index: int) -> int:
	if shares <= 0:
		return 0
	return total / shares + (1 if index < total % shares else 0)


## The flag a level's seal sets on its stairs once it breaks.
static func stairs_flag(floor_number: int, level: int) -> StringName:
	return StringName("stairs_%d_%d_open" % [floor_number, level])


func _build_level(definition: FloorDefinition, generation_seed: int, level: int) -> Node2D:
	_definition = definition
	_biome = definition.biome
	var n := definition.floor_number
	_levels = FloorTuning.dungeon_levels(n)
	_level = clampi(level, 1, _levels)
	_top = _level == _levels
	var own_seed := level_seed(generation_seed, _level)
	_rng.seed = own_seed

	var map := Node2D.new()
	map.name = "Floor%02d" % n if _level == 1 else "Floor%02dLevel%d" % [n, _level]
	map.set_script(GAME_MAP_SCRIPT)
	map.set(&"map_id", map_id_for(n, _level))
	map.set(&"display_name", definition.label())
	map.set(&"floor_number", n)
	if _biome:
		map.modulate = _biome.ambient_tint
		map.set(&"region", "%s - Level %d of %d" % [_biome.display_name, _level, _levels])

	_ground = _new_layer(map, "Ground", false)
	_walls = _new_layer(map, "Walls", true)

	# The chamber -- the stairs up, or the boss hall -- on a strip of its own, as an
	# open field's arena stands: no corridor between two rooms can cut into it.
	var chamber := Arena.new()
	var field_size := TOP_FIELD
	if not _top:
		field_size = FloorTuning.dungeon_level_size(n) + (HALL_EXTRA if _level == 1 else Vector2i.ZERO)
	var tiles := (ARENA_ROOM if _top else STAIR_ROOM) + Vector2i(LAB_WALL, LAB_WALL) * 2
	chamber.side = _rng.randi() % 4
	var at := _place_strip(field_size, tiles, chamber.side)
	chamber.rect = Rect2i(at[1], tiles)
	chamber.room = chamber.rect.grow(-LAB_WALL)
	var field := Rect2i(at[0], field_size)
	_size = field.end.max(chamber.rect.end)
	for y in _size.y:
		for x in _size.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)

	var rooms: Array[Rect2i]
	if _top:
		rooms = _place_rooms(field, TOP_ROOMS, TOP_ROOM_W, TOP_ROOM_H)
	else:
		rooms = _place_rooms(field, FloorTuning.dungeon_room_count(n) + (1 if _level == 1 else 0),
				ROOM_W, ROOM_H)
	for room in rooms:
		_carve(room, _biome.floor_tile)
	for i in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))
	_carve_arena(chamber)
	var entry := _connect_to(chamber.doorstep, chamber.side, rooms)
	var arrival := _center(entry)

	var camp: FloorCamp = null
	if _level == 1:
		camp = FloorCamp.new(n, generation_seed, _biome, _ground, _walls, _open)
		camp.reserve(field, rooms, entry)

	# The floor's chests and monsters, shared out between the levels below the top.
	var chest_cells: Array[Vector2i] = []
	if not _top:
		chest_cells = _pick_chest_cells(rooms, entry, Rect2i(),
				share_of(definition.chest_count, _levels - 1, _level - 1))
	_scatter_decor(rooms, entry, Rect2i())
	var ladder := _ladder_cell(chamber)
	var must_reach: Array[Vector2i] = chest_cells.duplicate()
	must_reach.append(_center(chamber.room) if _top else ladder)
	_ensure_reachable(arrival, must_reach)
	if camp != null:
		camp.plan(arrival, _lanes, [
			Rect2i(arrival - Vector2i.ONE, Vector2i(3, 3)),
			Rect2i(arrival + GATE_OFFSET - Vector2i(1, 2), Vector2i(3, 3)),
			Rect2i(arrival + GATE_ARRIVAL, Vector2i.ONE),
			Rect2i(arrival + STAIRS_OFFSET, Vector2i.ONE),
		] as Array[Rect2i])

	# The landing, then the seal: the seal's pieces keep clear of the fire.
	var candidates: Array[Rect2i] = []
	for room in _by_distance(rooms, arrival):
		if room != entry:
			candidates.push_front(room)
	var landing := Rect2i()
	var fire := Rect2i()
	var taken: Dictionary[Vector2i, bool] = {}
	for cell in chest_cells:
		taken[cell] = true
	if not _top and _level == landing_level(_levels) and candidates.size() >= 2:
		for room in _by_distance(candidates, chamber.doorstep):
			fire = _landing_fire(room, taken)
			if fire.has_area():
				landing = room
				_open.erase(fire.end - Vector2i.ONE)
				_open.erase(fire.end - Vector2i(2, 1))
				candidates.erase(room)
				break
	if not _top:
		_plan_seal(seal_kinds(generation_seed, _levels)[_level], candidates, entry, chest_cells,
				fire, camp.plot if camp != null else Rect2i(), field, own_seed)

	MapDresser.dress(map, _biome, _ground, _walls, own_seed)

	_add_level_spawns(map, arrival, ladder)
	if _level == 1:
		_add_teleport_gate(map, arrival)
		_add_stairs(map, arrival + STAIRS_OFFSET)
	else:
		var down := STAIRS_SCENE.instantiate()
		down.name = "StairsDown"
		down.position = _world(arrival + STAIRS_OFFSET)
		down.set(&"target_floor", n)
		down.set(&"target_level", _level - 1)
		down.set(&"target_spawn", &"stairs_up")
		down.set(&"display_name", "the stairs down")
		map.add_child(down)
	for index in chest_cells.size():
		_add_chest(map, chest_cells[index], index, true, [] as Array[Vector2i])
		var chest := map.get_node("Chest%d" % index)
		chest.set(&"opened_flag", StringName("floor_%d_%d_chest_%d" % [n, _level, index]))
	if not _top:
		_add_level_monsters(map, rooms, entry, landing, chest_cells,
				share_of(FloorTuning.monster_count(n), _levels - 1, _level - 1))
	if fire.has_area():
		var hearth := CAMPFIRE_SCENE.instantiate()
		hearth.name = "Campfire"
		hearth.position = Vector2((fire.position.x + 1) * TILE, fire.end.y * TILE)
		map.add_child(hearth)
		map.set(&"safe_zones", [landing] as Array[Rect2i])
		map.set_meta(&"safe_zone", landing)
	if _top:
		_add_boss_gate(map, _center(chamber.room), Rect2i())
		var gate := map.get_node("BossGate")
		gate.set(&"display_name", "the boss door")
		gate.set(&"found_on_arrival", true)
	else:
		_add_seal(map, chamber)
		var up := LADDER_SCENE.instantiate()
		up.name = "LadderUp"
		up.position = _world(ladder)
		up.set(&"target_floor", n)
		up.set(&"target_level", _level + 1)
		map.add_child(up)
	if camp != null:
		camp.dungeon = true
		camp.place(map, chamber.side, definition.boss_name)

	# Dark everywhere, as a labyrinth is -- but for the lamplit hall and the boss's.
	map.set(&"dark_area", Rect2i(Vector2i.ZERO, _size))
	var lit: Array[Rect2i] = []
	var places: Dictionary[String, Rect2i] = {}
	if camp != null:
		lit.append(camp.plot)
		places["Village" if camp.village else "Camp"] = camp.plot
		map.set_meta(&"camp", camp.plot)
		if camp.village:
			map.set_meta(&"village", camp.houses)
	if _top:
		lit.append(chamber.rect)
		places["The Boss Hall"] = chamber.rect
	else:
		places["The Stairs Up"] = chamber.rect
	if landing.has_area():
		places["Safe Zone"] = landing
	map.set(&"lit_areas", lit)
	map.set(&"landmarks", places)
	# For the tests, as a labyrinth's and an arena's are.
	map.set_meta(&"dungeon_level", _level)
	map.set_meta(&"dungeon_levels", _levels)
	map.set_meta(&"chamber", chamber.rect)
	map.set_meta(&"chamber_room", chamber.room)
	map.set_meta(&"chamber_door", chamber.door)
	if not _top:
		map.set_meta(&"seal", SEAL_NAMES[_seal])

	var player := PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.position = _world(arrival)
	map.add_child(player)
	return map


## A 2x2 for the landing's fire in [param room] (the pit along its bottom row),
## nearest the middle: off every corridor's sweep, with open ground all round it --
## a corridor's will do, since the fire stands beside the lane, never in it, and a
## level's rooms are too small for the clear ring an open field's clearing gives
## its fire. Empty if the room has none.
func _landing_fire(room: Rect2i, taken: Dictionary[Vector2i, bool]) -> Rect2i:
	var best := Rect2i()
	var best_off := INF
	for y in range(room.position.y + 1, room.end.y - 2):
		for x in range(room.position.x + 1, room.end.x - 2):
			var spot := Rect2i(x, y, 2, 2)
			var off := (Vector2(spot.get_center()) - Vector2(room.get_center())).length()
			if off >= best_off or not _clear_round(spot, taken):
				continue
			var ringed := true
			for cell in _ring_of(spot.grow(1)):
				if not _open.has(cell) or taken.has(cell):
					ringed = false
					break
			if ringed:
				best = spot
				best_off = off
	return best


static func _ring_of(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		cells.append(Vector2i(x, rect.position.y))
		cells.append(Vector2i(x, rect.end.y - 1))
	for y in range(rect.position.y + 1, rect.end.y - 1):
		cells.append(Vector2i(rect.position.x, y))
		cells.append(Vector2i(rect.end.x - 1, y))
	return cells


## This level's share of the floor's monsters, through its rooms but the arrival's
## and the landing's: [method FloorGenerator._add_monsters]' way, but a cell already
## taken or not open is drawn again rather than dropped -- a level is small, and a
## monster lost here is a kill the boss's balance counts on.
func _add_level_monsters(map: Node2D, rooms: Array[Rect2i], entry: Rect2i, landing: Rect2i,
		chest_cells: Array[Vector2i], count: int) -> void:
	var pool := Bestiary.pool_for_floor(_definition.floor_number)
	if pool.is_empty():
		return
	var candidates: Array[Rect2i] = []
	for room in rooms:
		if room != entry and room != landing:
			candidates.append(room)
	if candidates.is_empty():
		candidates.append(entry)
	var placed: Array[Vector2i] = chest_cells.duplicate()
	var tries := count * 20
	var index := 0
	while index < count and tries > 0:
		tries -= 1
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
		index += 1


# --- the chamber -----------------------------------------------------------

## Where the ladder up stands: against the stair chamber's north wall, in the
## middle -- or, when the doorway is in that wall, at its west end, out of the way in.
func _ladder_cell(chamber: Arena) -> Vector2i:
	var room := chamber.room
	if chamber.side == Side.SOUTH:
		return room.position
	return room.position + Vector2i(room.size.x / 2 - 1, 0)


func _add_level_spawns(map: Node2D, arrival: Vector2i, ladder: Vector2i) -> void:
	var holder := Node2D.new()
	holder.name = "SpawnPoints"
	map.add_child(holder)
	var spots := {
		"default": arrival, "from_below": arrival, "from_above": arrival,
		"stairs_down": arrival, "stairs_up": ladder + Vector2i.DOWN,
	}
	if _level == 1:
		spots["gate"] = arrival + GATE_ARRIVAL
	for spawn_name: String in spots:
		var marker := Marker2D.new()
		marker.name = spawn_name
		marker.position = _world(spots[spawn_name])
		holder.add_child(marker)


## The slab across the stair chamber's doorway, its hollows the seal's pieces.
func _add_seal(map: Node2D, chamber: Arena) -> void:
	var n := _definition.floor_number
	var sigils: Array[StringName] = []
	var described := "A slab of stone across the way to the ladder, fitted to the wall."
	var hint := ""
	var first := ""
	match _seal:
		Seal.WARDEN:
			sigils.append(StringName("warden_%d_%d" % [n, _level]))
			hint = "There's a keyhole in it. Something on this level carries the key -- the warden."
			first = "Far off, a lock turns over by itself."
			var warden := MONSTER_SCENE.instantiate()
			var pool := Bestiary.pool_for_floor(n)
			var enemy: EnemyType = pool[_rng.randi() % pool.size()]
			warden.name = "Warden"
			warden.position = _world(_warden_cell)
			warden.set(&"enemy", enemy)
			warden.set(&"level", _definition.enemy_level + WARDEN_LEVELS)
			warden.set(&"floor_number", n)
			warden.set(&"defeat_flag", sigils[0])
			warden.set(&"display_name", "%s Warden" % enemy.label())
			(warden.get_node("Sprite2D") as Sprite2D).self_modulate = Color(1.0, 0.72, 0.72)
			map.add_child(warden)
		Seal.LEVERS:
			for i in _lever_cells.size():
				sigils.append(StringName("lever_%d_%d_%d" % [n, _level, i]))
			hint = "%s hollows, and a lever for each somewhere on this level." % \
					SealedDoor._count_word(sigils.size()).capitalize()
			first = "Somewhere ahead, the last weight drops into place."
			for i in _lever_cells.size():
				var lever := LEVER_SCENE.instantiate()
				lever.name = "Lever%d" % i
				lever.position = _world(_lever_cells[i])
				lever.set(&"flag", sigils[i])
				lever.set(&"all_flags", sigils)
				map.add_child(lever)
		Seal.BRAZIERS:
			sigils.append(_puzzles.flag("braziers"))
			hint = "Soot rings the hollow. The fires on this level are the key -- the tablet beside them says how."
			first = "As the last fire takes, stone grinds somewhere ahead."
		Seal.STATUES:
			sigils.append(_puzzles.flag("statues"))
			hint = "Carved on it: four figures, all looking in. Somewhere on this level, statues stand round an altar."
			first = "As the last statue turns, stone grinds somewhere ahead."
	if _puzzles != null:
		_puzzles.place(map)
	var seal := SEAL_SCENE.instantiate()
	seal.name = "StairsSeal"
	seal.position = Vector2(chamber.door.position * TILE) + Vector2(chamber.door.size * TILE) / 2.0
	seal.set(&"display_name", "the sealed stairs")
	seal.set(&"sigils", sigils)
	seal.set(&"opened_flag", stairs_flag(n, _level))
	seal.set(&"opens_itself", true)
	seal.set(&"described", described)
	seal.set(&"hint", hint)
	seal.set(&"opening_lines", PackedStringArray([first, "The way up to level %d is open." % (_level + 1)]))
	map.add_child(seal)


# --- the seal --------------------------------------------------------------

## Decides what seals this level's stairs and where its pieces stand, in
## [param candidates] (the rooms but the arrival's and the landing's, farthest
## first). [param kind] is the floor's pick ([method seal_kinds]); a pick with no
## room for it falls back -- braziers to statues, statues to levers, levers to the
## warden, who needs only a room to stand in.
func _plan_seal(kind: int, candidates: Array[Rect2i], entry: Rect2i, chest_cells: Array[Vector2i],
		fire: Rect2i, plot: Rect2i, field: Rect2i, own_seed: int) -> void:
	var taken: Dictionary[Vector2i, bool] = {}
	for cell in chest_cells:
		taken[cell] = true
	if fire.has_area():
		for y in range(fire.position.y - 2, fire.end.y + 2):
			for x in range(fire.position.x - 2, fire.end.x + 2):
				taken[Vector2i(x, y)] = true
	var order: Array[int] = [kind]
	if kind == Seal.BRAZIERS:
		order.append(Seal.STATUES)
	if kind in [Seal.BRAZIERS, Seal.STATUES]:
		order.append(Seal.LEVERS)
	order.append(Seal.WARDEN)
	for pick in order:
		match pick:
			Seal.BRAZIERS, Seal.STATUES:
				var puzzles := FloorPuzzles.new(_definition.floor_number, own_seed, _biome,
						_ground, _walls, _open, field)
				puzzles.flag_prefix = "dungeon_%d_%d" % [_definition.floor_number, _level]
				puzzles.with_chests = false
				var keep_out: Array[Rect2i] = [entry]
				if plot.has_area():
					keep_out.append(plot)
				if fire.has_area():
					keep_out.append(fire.grow(2))
				puzzles.hold(chest_cells, keep_out)
				var mode := BrazierRite.Mode.TIMED if _rng.randf() < 0.5 else BrazierRite.Mode.ORDERED
				for room in candidates:
					var placed := puzzles.pin_rite(room, mode) if pick == Seal.BRAZIERS \
							else puzzles.pin_statues(room)
					if placed:
						_puzzles = puzzles
						_seal = pick
						return
			Seal.LEVERS:
				var spots: Dictionary[Rect2i, Vector2i] = {}
				for room in candidates:
					var cell := _stone_spot(room, taken)
					if cell.x >= 0:
						spots[room] = cell
				if spots.size() >= LEVERS:
					_take_levers(spots, entry)
					_seal = pick
					return
			Seal.WARDEN:
				_warden_cell = _warden_spot(candidates if not candidates.is_empty() else [entry], taken)
				_seal = pick
				return


## Where the warden stands: in the farthest of [param rooms] with a cell clear all
## round -- or, failing every one, on the open cell of the farthest nearest its
## middle. Never on decor: it walks by asking whether it fits.
func _warden_spot(rooms: Array[Rect2i], taken: Dictionary[Vector2i, bool]) -> Vector2i:
	for room in rooms:
		var cell := _stone_spot(room, taken)
		if cell.x >= 0:
			return cell
	var best := _center(rooms[0])
	var best_off := 1 << 30
	for y in range(rooms[0].position.y, rooms[0].end.y):
		for x in range(rooms[0].position.x, rooms[0].end.x):
			var cell := Vector2i(x, y)
			var off := (cell - _center(rooms[0])).length_squared()
			if _open.has(cell) and not taken.has(cell) and off < best_off:
				best = cell
				best_off = off
	return best


## Two of [param spots] (room -> the cell a lever could stand on) for the levers: the
## rooms farthest from the arrival and from each other, as an open field's
## waystones are, so pulling them is a walk round the level.
func _take_levers(spots: Dictionary[Rect2i, Vector2i], entry: Rect2i) -> void:
	var anchors: Array[Vector2i] = [_center(entry)]
	while _lever_cells.size() < LEVERS:
		var best := Rect2i()
		var best_gap := -1.0
		for room: Rect2i in spots:
			var gap := INF
			for anchor in anchors:
				gap = minf(gap, Vector2(_center(room) - anchor).length())
			if gap > best_gap:
				best_gap = gap
				best = room
		_lever_cells.append(spots[best])
		_open.erase(spots[best])
		anchors.append(_center(best))
		spots.erase(best)
