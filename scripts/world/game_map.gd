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
	var start := _walls.local_to_map(_walls.to_local(to_global(player_at) + Vector2(0, -4)))
	var toward := enemy_at - player_at
	var contact := Vector2i.RIGHT
	if absf(toward.y) > absf(toward.x):
		contact = Vector2i(0, signi(roundi(signf(toward.y))))
	elif toward.x != 0.0:
		contact = Vector2i(signi(roundi(signf(toward.x))), 0)
	var axes: Array[Vector2i] = [contact, -contact,
			Vector2i(contact.y, contact.x), -Vector2i(contact.y, contact.x)]

	var best_cost := INF
	var field: BattleField = null
	for dy in range(-FORMATION_SLIDE, FORMATION_SLIDE + 1):
		for dx in range(-FORMATION_SLIDE, FORMATION_SLIDE + 1):
			var cell := start + Vector2i(dx, dy)
			if not is_standable(cell):
				continue
			for a in axes.size():
				for gap in FORMATION_GAPS:
					var cost := absi(dx) + absi(dy) + a * 2 + absi(gap - FORMATION_GAPS[0]) * 1.5
					if cost >= best_cost:
						continue
					var enemies := _enemy_cells(cell, axes[a], gap, enemy_count)
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
					field.axis = axes[a]
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
	return field


## A cell someone can be put on: floor, not wall or water, and nothing solid in
## it -- a chest, a shown door.
func is_standable(cell: Vector2i) -> bool:
	_resolve_layers()
	if _walls.get_cell_source_id(cell) != -1:
		return false
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground != null and ground.get_cell_source_id(cell) == -1:
		return false
	if not is_inside_tree():
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	var body := RectangleShape2D.new()
	body.size = Vector2(12, 8)
	query.shape = body
	query.transform = Transform2D(0.0, to_global(_feet(cell) + Vector2(0, -4)))
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


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


## Where feet stand on [param cell], map-local: low in the cell, so the sprite
## stands on it rather than over the row above.
func _feet(cell: Vector2i) -> Vector2:
	return to_local(_walls.to_global(_walls.map_to_local(cell))) + Vector2(0, 4)


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
