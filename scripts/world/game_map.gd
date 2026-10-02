class_name GameMap
extends Node2D
## Root of every playable map.
##
## Expected children:
##   Ground       TileMapLayer  -- also defines the camera bounds
##   Walls        TileMapLayer  -- collision
##   SpawnPoints  Node2D        -- Marker2D children named after arrival points
##   Player       (instance of player.tscn)
##
## Placing the player is the map's job, not the router's: the router only says
## *which* spawn point, the map knows where that is.

## How far round the player counts as walked: a two-wide passage is walked end to
## end by walking down it in either lane.
const WALK_REACH := 2
## How far a fighter may be moved to make a formation fit, in cells each way.
const FORMATION_SLIDE := 2
## How far apart the two sides stand, in cells, most wanted first.
const FORMATION_GAPS: Array[int] = [3, 4, 2]
## What a fighter standing behind a tree costs the formation: nearly a refusal,
## but a fight that can only be staged half-hidden is still better than none.
const HIDDEN_COST := 20.0
## The player's body, centred on a cell -- what a spot has to have room for.
const BODY := Vector2(12, 8)
## What the player and a roaming monster cover standing: width, height above the
## feet. A formation keeps bigger bodies -- a boss -- clear of each other by it.
const STANDING := Vector2(16, 16)
## How far a boss steps out of its door, in cells.
const BOSS_STEP := 3
## How far a boss fight may walk the player back from the door, in steps. Further
## than a monster fight's slide: a boss needs more room, and the room is there.
const BOSS_WALK := 6

@export var map_id: StringName = &""
@export var display_name := ""
@export var default_spawn: StringName = &"default"
## Which floor of Aincrad this map belongs to. 0 for maps outside the tower.
@export var floor_number := 0
## Cells drawn only while in line of sight -- a generated floor's labyrinth. Empty
## for none: everywhere else the camera sees over walls. See [Darkness].
@export var dark_area := Rect2i()
## What the map screen calls this place under its title -- a generated floor's
## biome. Empty for none.
@export var region := ""
## Named places, written on the map screen once any of their cells is seen.
@export var landmarks: Dictionary[String, Rect2i] = {}

var _player: Player = null
var _walls: TileMapLayer = null
## Tells water from wall for [method blocks_sight]; null off the tower.
var _biome: BiomeKit = null
## The cell the player was last seen from, so fog only works when they move.
var _seen_from := Vector2i(1 << 30, 1 << 30)
var _darkness: Darkness = null
## Floor cells a standing prop draws over -- the lane a forest's crowns hang
## across. Built on first use; props never move.
var _covered: Dictionary[Vector2i, bool] = {}
var _covered_built := false
## Cells something solid stands in, from [method refresh_solids].
var _solid_cells: Dictionary[Vector2i, bool] = {}
## Every slide, axis and gap the solver may try, cheapest first. See
## [method _formation_candidates].
static var _candidates: Array[Vector4] = []


func _ready() -> void:
	if floor_number > 0:
		GameState.current_floor = floor_number
	_resolve_layers()
	_player = get_node_or_null("Player") as Player
	if _player:
		_player.global_position = _resolve_spawn(SceneRouter.consume_spawn())
		_apply_camera_limits(_player)
	var tracks := _player != null and _walls != null and map_id != &""
	if tracks and dark_area.has_area():
		_darkness = Darkness.new()
		_darkness.name = "Darkness"
		_darkness.setup(dark_area, _walls.tile_set.tile_size, _walls.get_used_rect())
		add_child(_darkness)
	set_physics_process(tracks)
	set_process(_darkness != null)


## Fog of war: whatever the player can see from the cell they are standing in is
## explored. Cheap -- a couple of hundred short lines, and only on a new cell.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var cell := _walls.local_to_map(_walls.to_local(_player.global_position))
	if cell == _seen_from:
		return
	var first := _seen_from.x == 1 << 30
	_seen_from = cell
	var lit := FogOfWar.visible_from(cell, FogOfWar.RADIUS, blocks_sight)
	GameState.explore(map_id, lit)
	var near: Array[Vector2i] = []
	for seen in lit:
		var off := (seen - cell).abs()
		if maxi(off.x, off.y) <= WALK_REACH:
			near.append(seen)
	GameState.walk(map_id, near)
	if _darkness:
		_darkness.light(lit, GameState.explored_cells(map_id), first)


## A monster in the dark is not drawn: the dark covers the ground, but a monster
## in a remembered passage would otherwise show through it -- and what you
## remember is the maze, not who was in it.
func _process(_delta: float) -> void:
	for child in get_children():
		var monster := child as Monster
		if monster:
			monster.modulate.a = _darkness.light_at(
					_walls.local_to_map(_walls.to_local(monster.global_position)))


## The dark over the labyrinth, or null on a map without one.
func darkness() -> Darkness:
	return _darkness


## A wall stops the eye; water does not, or the far shore of a pond would stay
## unexplored until you walked round it. Water lives on Walls (it collides), so
## it is told apart by its terrain -- or, undressed, by its slot.
func blocks_sight(cell: Vector2i) -> bool:
	_resolve_layers()
	if _walls == null or _walls.get_cell_source_id(cell) == -1:
		return false
	return not is_water(cell)


func is_water(cell: Vector2i) -> bool:
	_resolve_layers()
	if _biome == null or _walls == null:
		return false
	var data := _walls.get_cell_tile_data(cell)
	if data == null:
		return false
	if _biome.liquid_terrain_set >= 0 and data.terrain_set == _biome.liquid_terrain_set \
			and data.terrain == _biome.liquid_terrain:
		return true
	return _walls.get_cell_atlas_coords(cell) == Vector2i(_biome.liquid_tile, 0)


## Where a fight started at [param player_at] by something at [param enemy_at]
## can stand: the two sides stepped apart along the line between them, 2-4
## tiles, on floor, nobody further than [constant FORMATION_SLIDE] cells from
## where they were. Null if nothing fits -- the caller falls back to the screen.
##
## Positions are map-local. [param enemy_count] is at most two: escorts are
## capped at one, so a second enemy stands beside the first, across the axis.
func stage_battle(player_at: Vector2, enemy_at: Vector2, enemy_count: int) -> BattleField:
	_resolve_layers()
	if _walls == null:
		return null
	refresh_solids()
	return formation(_cell_at(player_at), _axis_of(enemy_at - player_at), enemy_count)


## Where a boss fight challenged at the door on [param door_at] stands: the boss
## steps out of the door towards the player, its escort beside it, and the
## player walks back to face them -- see [method boss_formation]. [param bodies]
## is what each enemy covers standing ([method FoeFigure.body_of]), boss first.
## Null if nothing fits.
func stage_boss(player_at: Vector2, door_at: Vector2, bodies: Array[Vector2]) -> BattleField:
	_resolve_layers()
	if _walls == null:
		return null
	refresh_solids()
	return boss_formation(_cell_at(player_at), _cell_at(door_at), bodies)


## The formation for a player standing on [param start], struck from along
## [param contact] -- [method stage_battle] without the positions, and against
## the solid things as [method refresh_solids] last found them. The floor test
## sweeps every cell of every floor through this.
##
## Candidates are tried cheapest first (see [method _formation_candidates]), so
## the first that fits in the open is the answer and the usual case asks about
## four cells. The player only slides to cells they could have walked to inside
## the slide box: a cell two along might be across a one-thick wall, and the
## player is moved by position, so the solver is all that stands between them
## and being set down in the next corridor.
func formation(start: Vector2i, contact: Vector2i, enemy_count: int) -> BattleField:
	_resolve_layers()
	if _walls == null:
		return null
	var axes: Array[Vector2i] = [contact, -contact,
			Vector2i(contact.y, contact.x), -Vector2i(contact.y, contact.x)]
	var near := _walkable_near(start)

	var best_cost := INF
	var field: BattleField = null
	for candidate: Vector4 in _formation_candidates():
		var cost := candidate.w
		if cost >= best_cost:
			break
		var cell := start + Vector2i(roundi(candidate.x), roundi(candidate.y))
		if not near.has(cell):
			continue
		var axis := axes[roundi(candidate.z) / FORMATION_GAPS.size()]
		var gap: int = FORMATION_GAPS[roundi(candidate.z) % FORMATION_GAPS.size()]
		var enemies := _enemy_cells(cell, axis, gap, enemy_count)
		if enemies.is_empty():
			continue
		for fighter: Vector2i in enemies + [cell]:
			if is_covered(fighter):
				cost += HIDDEN_COST
		if cost >= best_cost:
			continue
		best_cost = cost
		field = BattleField.new()
		field.player_cell = cell
		field.enemy_cells = enemies
		field.axis = axis
	if field == null:
		return null

	field.map = self
	field.player = _player
	var tile := Vector2(_walls.tile_set.tile_size)
	field.player_spot = _feet(field.player_cell)
	var bounds := Rect2(field.player_spot, Vector2.ZERO)
	for cell in field.enemy_cells:
		var spot := _feet(cell)
		field.enemy_spots.append(spot)
		bounds = bounds.expand(spot)
	field.arena = bounds.grow_individual(tile.x * 1.5, tile.y * 2.5, tile.x * 1.5, tile.y)
	var standing: Array[Vector2] = []
	standing.resize(field.enemy_spots.size())
	standing.fill(STANDING)
	field.bodies = _bodies_of(field, standing)
	return field


## The formation for a boss fight challenged from [param start] at the door on
## [param door] -- [method stage_boss] without the positions. The floor test
## sweeps every cell the door can be challenged from through this.
##
## Unlike a monster, a boss is anchored: it steps out of its door, up to
## [constant BOSS_STEP] cells towards the player and two either side, and the
## player is the one who moves -- back to wherever, within
## [constant BOSS_WALK] steps, they can face it across a clear lane. How far
## apart is set by the bodies, not a constant: a 60 px boss below you would
## stand on your head at a monster's three cells, so the gap is whatever keeps
## the sprites apart plus a cell. Facing the door is wanted, from the side is
## fine, and from behind the boss -- between it and its door -- is a last resort.
func boss_formation(start: Vector2i, door: Vector2i, bodies: Array[Vector2]) -> BattleField:
	_resolve_layers()
	if _walls == null or bodies.is_empty():
		return null
	var out := _axis_of(Vector2(start - door))
	var side := Vector2i(out.y, out.x)
	# From the player towards the boss, most wanted first, and what each costs.
	var axes: Array[Vector2i] = [-out, side, -side, out]
	var axis_costs: Array[float] = [0.0, 2.0, 2.0, 6.0]
	var walk := _walk_distances(start, BOSS_WALK)

	var best_cost := INF
	var field: BattleField = null
	for k in range(1, BOSS_STEP + 1):
		for s in range(-2, 3):
			var boss := door + out * k + side * s
			if not is_standable(boss):
				continue
			for a in axes.size():
				var axis := axes[a]
				var gaps := _boss_gaps(axis, bodies[0])
				for g in gaps.size():
					var player := boss - axis * gaps[g]
					if not walk.has(player):
						continue
					var cost: float = (k - 1) + absi(s) + axis_costs[a] + g * 1.5 + walk[player]
					if cost >= best_cost or not _lane_clear(player, axis, gaps[g]):
						continue
					var cells: Array[Vector2i] = [boss]
					if bodies.size() >= 2:
						var escort := _escort_cell(boss, axis, bodies[0], bodies[1])
						if escort == boss:
							continue
						cells.append(escort)
					for fighter: Vector2i in cells + [player]:
						if is_covered(fighter):
							cost += HIDDEN_COST
					if cost >= best_cost:
						continue
					best_cost = cost
					field = BattleField.new()
					field.player_cell = player
					field.enemy_cells = cells
					field.axis = axis
	if field == null:
		return null

	field.map = self
	field.player = _player
	field.player_spot = _feet(field.player_cell)
	for cell in field.enemy_cells:
		field.enemy_spots.append(_feet(cell))
	field.bodies = _bodies_of(field, bodies)
	var tile := Vector2(_walls.tile_set.tile_size)
	field.arena = field.bodies.grow_individual(tile.x, tile.y, tile.x, tile.y * 0.5)
	return field


## A cell someone can be put on: floor, not wall or water, and nothing solid in
## it -- a chest, an NPC, a shown door -- as of the last [method refresh_solids].
func is_standable(cell: Vector2i) -> bool:
	_resolve_layers()
	if _walls.get_cell_source_id(cell) != -1:
		return false
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground != null and ground.get_cell_source_id(cell) == -1:
		return false
	return not _solid_cells.has(cell)


## Finds the cells something solid stands in: any child's layer-1 body whose
## shape would overlap a body set down in the cell. Read off the nodes rather
## than asked of the physics server, so a map the floor test has built but never
## added to the tree answers the same as one being played. Not cached between
## fights, because a door that has just been found has just become solid.
func refresh_solids() -> void:
	_solid_cells.clear()
	_resolve_layers()
	if _walls == null:
		return
	var to_walls := _walls.transform.affine_inverse()
	for child in get_children():
		var holder := child as Node2D
		if holder == null or holder is TileMapLayer:
			continue
		for body in holder.get_children():
			var solid := body as StaticBody2D
			if solid == null or solid.collision_layer & 1 == 0:
				continue
			for shape_node in solid.get_children():
				var shape := shape_node as CollisionShape2D
				if shape == null or shape.disabled or shape.shape == null:
					continue
				var rect := to_walls * holder.transform * solid.transform * shape.transform \
						* shape.shape.get_rect()
				var from := _walls.local_to_map(rect.position)
				var to := _walls.local_to_map(rect.end)
				for y in range(from.y, to.y + 1):
					for x in range(from.x, to.x + 1):
						var body_rect := Rect2(_walls.map_to_local(Vector2i(x, y)) - BODY / 2.0, BODY)
						if body_rect.intersects(rect):
							_solid_cells[Vector2i(x, y)] = true


## Whether a standing prop is drawn over [param cell]: whoever stands there is
## sorted behind it. Walkable -- you pass behind a roof or a crown -- but no place
## to stage a fight anyone has to watch.
func is_covered(cell: Vector2i) -> bool:
	if not _covered_built:
		_covered_built = true
		var props := get_node_or_null("Props") as TileMapLayer
		if props != null and props.tile_set != null:
			for anchor in props.get_used_cells():
				var source := props.tile_set.get_source(props.get_cell_source_id(anchor)) as TileSetAtlasSource
				if source == null:
					continue
				var size := source.get_tile_size_in_atlas(props.get_cell_atlas_coords(anchor))
				var rect := MapDresser.footprint(anchor, size)
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						_covered[Vector2i(x, y)] = true
	return _covered.has(cell)


## The gaps a player may stand from a boss of [param body] along [param axis]
## (player towards boss), most wanted first: a monster's three if that keeps the
## two apart, else just enough, then one more, then the least that will do.
func _boss_gaps(axis: Vector2i, body: Vector2) -> Array[int]:
	var least := _clearance(axis, STANDING, body) + 1
	var wanted := maxi(FORMATION_GAPS[0], least)
	var gaps: Array[int] = [wanted, wanted + 1]
	if least < wanted:
		gaps.append(least)
	return gaps


## How many cells along [param direction] something of [param far] has to stand
## from something of [param near] for the two sprites not to overlap. Bodies are
## centred on their feet across and stand up from them: side by side it is half
## the width of each; one below the other it is the height of the lower one,
## whose head must not reach up past the upper one's feet.
func _clearance(direction: Vector2i, near: Vector2, far: Vector2) -> int:
	var tile := Vector2(_walls.tile_set.tile_size)
	var cells := 0
	if direction.x != 0:
		cells = ceili((near.x + far.x) / 2.0 / tile.x)
	elif direction.y > 0:
		cells = ceili(far.y / tile.y)
	else:
		cells = ceili(near.y / tile.y)
	return maxi(1, cells)


## Every standable cell from [param from] along [param axis] up to
## [param gap] cells: the lane between two fighters, and the far one's cell.
func _lane_clear(from: Vector2i, axis: Vector2i, gap: int) -> bool:
	for step in range(1, gap + 1):
		if not is_standable(from + axis * step):
			return false
	return true


## Where an escort of [param escort] stands beside a boss of [param boss] on
## [param at], across [param axis]: far enough not to overlap it, on whichever
## side needs less room, with floor all the way -- or [param at] itself if
## neither side has it.
func _escort_cell(at: Vector2i, axis: Vector2i, boss: Vector2, escort: Vector2) -> Vector2i:
	var across := Vector2i(axis.y, axis.x)
	var sides: Array[Vector2i] = [across, -across]
	sides.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return _escort_reach(p, boss, escort) < _escort_reach(q, boss, escort))
	for direction in sides:
		var reach := _escort_reach(direction, boss, escort)
		if _lane_clear(at, direction, reach):
			return at + direction * reach
	return at


## How far along [param direction] an escort stands from its boss: clear of the
## sprite, and one above the other a cell further, for the health bar that hangs
## under the upper one's feet.
func _escort_reach(direction: Vector2i, boss: Vector2, escort: Vector2) -> int:
	return _clearance(direction, boss, escort) + (1 if direction.y != 0 else 0)


## Steps to every standable cell within [param limit] of [param start], walking.
## Walked from the start even when it is not standable itself, as in
## [method _walkable_near].
func _walk_distances(start: Vector2i, limit: int) -> Dictionary[Vector2i, int]:
	var steps: Dictionary[Vector2i, int] = {}
	if is_standable(start):
		steps[start] = 0
	var frontier: Array[Vector2i] = [start]
	for distance in range(1, limit + 1):
		var next_frontier: Array[Vector2i] = []
		for cell in frontier:
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var next := cell + step
				if next != start and not steps.has(next) and is_standable(next):
					steps[next] = distance
					next_frontier.append(next)
		frontier = next_frontier
	return steps


## The rect the fighters cover standing on their spots, enemies drawn as
## [param bodies] and the player as [constant STANDING].
func _bodies_of(field: BattleField, bodies: Array[Vector2]) -> Rect2:
	var covered := Rect2(field.player_spot - Vector2(STANDING.x / 2.0, STANDING.y), STANDING)
	for i in field.enemy_spots.size():
		var body: Vector2 = bodies[mini(i, bodies.size() - 1)]
		covered = covered.merge(Rect2(field.enemy_spots[i] - Vector2(body.x / 2.0, body.y), body))
	return covered


## The cell under feet at [param point], map-local.
func _cell_at(point: Vector2) -> Vector2i:
	return _walls.local_to_map(_walls.transform.affine_inverse() * (point + Vector2(0, -4)))


## The axis direction [param toward] mostly points along; right for none.
static func _axis_of(toward: Vector2) -> Vector2i:
	if absf(toward.y) > absf(toward.x):
		return Vector2i(0, signi(roundi(signf(toward.y))))
	if toward.x != 0.0:
		return Vector2i(signi(roundi(signf(toward.x))), 0)
	return Vector2i.RIGHT


## The enemy cells for a player on [param from] facing along [param axis]
## [param gap] cells away, with clear floor between -- or empty if they don't fit.
func _enemy_cells(from: Vector2i, axis: Vector2i, gap: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step in range(1, gap + 1):
		if not is_standable(from + axis * step):
			return cells
	var front := from + axis * gap
	cells.append(front)
	if count >= 2:
		var side := Vector2i(axis.y, axis.x)
		for beside: Vector2i in [front + side, front - side]:
			if is_standable(beside):
				cells.append(beside)
				break
		if cells.size() < 2:
			cells.clear()
	return cells


## The standable cells a player on [param start] can walk to without leaving
## the slide box -- the only cells a formation may move them to.
func _walkable_near(start: Vector2i) -> Dictionary[Vector2i, bool]:
	var box := Rect2i(start - Vector2i.ONE * FORMATION_SLIDE, Vector2i.ONE * (FORMATION_SLIDE * 2 + 1))
	var near: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = [start]
	if is_standable(start):
		near[start] = true
	# Walked from the start even when it is not standable itself: feet can sit in
	# a cell a chest's corner reaches into, and the cells round it are still yours.
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + step
			if box.has_point(next) and not near.has(next) and is_standable(next):
				near[next] = true
				queue.append(next)
	return near


## (dx, dy, axis * gaps + gap index, cost) for every way the solver may arrange
## a fight, sorted by cost: distance slid, then the axis (contact first), then
## how far the gap is from the one wanted. Built once; the sort is stable on the
## index, so equal costs always come out in the same order.
static func _formation_candidates() -> Array[Vector4]:
	if not _candidates.is_empty():
		return _candidates
	var gaps := FORMATION_GAPS.size()
	var keyed: Array = []
	for dy in range(-FORMATION_SLIDE, FORMATION_SLIDE + 1):
		for dx in range(-FORMATION_SLIDE, FORMATION_SLIDE + 1):
			for a in 4:
				for g in gaps:
					var cost := absi(dx) + absi(dy) + a * 2 + absi(FORMATION_GAPS[g] - FORMATION_GAPS[0]) * 1.5
					keyed.append([cost, keyed.size(), Vector4(dx, dy, a * gaps + g, cost)])
	keyed.sort_custom(func(p: Array, q: Array) -> bool:
		return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
	for entry: Array in keyed:
		_candidates.append(entry[2])
	return _candidates


## Where feet stand on [param cell], map-local: low in the cell, so the sprite
## stands on it rather than over the row above.
func _feet(cell: Vector2i) -> Vector2:
	return _walls.transform * _walls.map_to_local(cell) + Vector2(0, 4)


## Resolved on first use rather than in _ready(), so a map that has not entered
## the tree -- a test inspecting a freshly generated floor -- can still answer.
func _resolve_layers() -> void:
	if _walls == null:
		_walls = get_node_or_null("Walls") as TileMapLayer
	if _biome == null and floor_number > 0:
		_biome = FloorRegistry.get_biome(floor_number)


func _resolve_spawn(requested: StringName) -> Vector2:
	var spawns := get_node_or_null("SpawnPoints")
	if spawns == null or spawns.get_child_count() == 0:
		push_warning("Map '%s' has no SpawnPoints; using origin." % name)
		return Vector2.ZERO

	for candidate in [requested, default_spawn]:
		if candidate == &"":
			continue
		var marker := spawns.get_node_or_null(String(candidate)) as Node2D
		if marker:
			return marker.global_position

	return (spawns.get_child(0) as Node2D).global_position


## Keeps the camera inside the painted area so it never shows the void.
## Merges Ground and Walls: a generated floor's Ground only covers carved cells,
## while its Walls cover the whole rectangle. Not the dressing layers -- a crown
## on the forest's top row hangs a row above the map, and a limit that followed
## it would show that row's void.
func _apply_camera_limits(player: Player) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	var rect := Rect2i()
	var tile := Vector2i(16, 16)
	for child in get_children():
		var layer := child as TileMapLayer
		if layer == null or layer.tile_set == null or not (layer.name in [&"Ground", &"Walls"]):
			continue
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		tile = layer.tile_set.tile_size
		rect = used if rect.size == Vector2i.ZERO else rect.merge(used)

	if rect.size == Vector2i.ZERO:
		return
	camera.limit_left = rect.position.x * tile.x
	camera.limit_top = rect.position.y * tile.y
	camera.limit_right = rect.end.x * tile.x
	camera.limit_bottom = rect.end.y * tile.y
	camera.reset_smoothing()
