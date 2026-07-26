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


func _ready() -> void:
	if floor_number > 0:
		GameState.current_floor = floor_number
	var player := get_node_or_null("Player") as Player
	if player:
		player.global_position = _resolve_spawn(SceneRouter.consume_spawn())
		_apply_camera_limits(player)


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
## Merges every tile layer: a generated floor's Ground only covers carved cells,
## while its Walls cover the whole rectangle.
func _apply_camera_limits(player: Player) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	var rect := Rect2i()
	var tile := Vector2i(16, 16)
	for child in get_children():
		var layer := child as TileMapLayer
		if layer == null or layer.tile_set == null:
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
