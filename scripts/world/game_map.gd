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

@export var map_id: StringName = &""
@export var display_name := ""
@export var default_spawn: StringName = &"default"
## Which floor of Aincrad this map belongs to. 0 for maps outside the tower.
@export var floor_number := 0

var _player: Player = null
var _walls: TileMapLayer = null
## Tells water from wall for [method blocks_sight]; null off the tower.
var _biome: BiomeKit = null
## The cell the player was last seen from, so fog only works when they move.
var _seen_from := Vector2i(1 << 30, 1 << 30)


func _ready() -> void:
	if floor_number > 0:
		GameState.current_floor = floor_number
	_resolve_layers()
	_player = get_node_or_null("Player") as Player
	if _player:
		_player.global_position = _resolve_spawn(SceneRouter.consume_spawn())
		_apply_camera_limits(_player)
	set_physics_process(_player != null and _walls != null and map_id != &"")


## Fog of war: whatever the player can see from the cell they are standing in is
## explored. Cheap -- a couple of hundred short lines, and only on a new cell.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var cell := _walls.local_to_map(_walls.to_local(_player.global_position))
	if cell == _seen_from:
		return
	_seen_from = cell
	GameState.explore(map_id, FogOfWar.visible_from(cell, FogOfWar.RADIUS, blocks_sight))


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
