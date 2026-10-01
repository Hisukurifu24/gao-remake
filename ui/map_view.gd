class_name MapView
extends Control
## One map, as far as the player has explored it: a few pixels a cell, and a
## marker for you, the boss door once found, the ways out and unopened chests.
##
## Purely a view. [GameState] says which cells have been seen and the map says
## what is in them; this only decides how big a cell is and what colour.

## Cells are drawn in half-unit steps, the smallest a 320x180 layout can draw
## crisply (half a unit is one whole screen pixel), up to four units.
const MAX_CELL := 4.0
const MIN_CELL := 0.5
const BLINK := 0.4

var _map: GameMap = null
var _blink_on := true
var _blink_time := 0.0


func show_map(map: GameMap) -> void:
	_map = map
	_blink_on = true
	_blink_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _map == null or not is_visible_in_tree():
		return
	_blink_time += delta
	if _blink_time >= BLINK:
		_blink_time = 0.0
		_blink_on = not _blink_on
		queue_redraw()


func _draw() -> void:
	if _map == null or not is_instance_valid(_map):
		return
	var ground := _map.get_node_or_null("Ground") as TileMapLayer
	var walls := _map.get_node_or_null("Walls") as TileMapLayer
	if ground == null or walls == null:
		return
	var bounds := ground.get_used_rect().merge(walls.get_used_rect())
	if not bounds.has_area():
		return
	var fit := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	var cell := clampf(floorf(fit * 2.0) / 2.0, MIN_CELL, MAX_CELL)
	var origin := (((size - Vector2(bounds.size) * cell) / 2.0) * 2.0).floor() / 2.0
	var seen := GameState.explored_cells(_map.map_id)
	draw_rect(Rect2(origin, Vector2(bounds.size) * cell), UiPalette.MAP_UNSEEN)

	for at: Vector2i in seen:
		var colour: Color
		if walls.get_cell_source_id(at) != -1:
			colour = UiPalette.MAP_WATER if _map.is_water(at) else UiPalette.MAP_WALL
		elif ground.get_cell_source_id(at) != -1:
			colour = UiPalette.MAP_FLOOR
		else:
			continue
		draw_rect(Rect2(origin + Vector2(at - bounds.position) * cell, Vector2(cell, cell)), colour)

	var player: Node2D = null
	for child in _map.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if node is Player:
			player = node
			continue
		var at := _cell_of(walls, node)
		if not seen.has(at):
			continue
		if node is BossGate:
			if (node as BossGate).revealed:
				_marker(origin, bounds, cell, at, UiPalette.MAP_DOOR)
		elif node is Interactable and ("target_floor" in node or "target_map" in node):
			if (node as Interactable).is_available():
				_marker(origin, bounds, cell, at, UiPalette.MAP_EXIT)
		elif node is Interactable and "opened_flag" in node:
			if (node as Interactable).is_available():
				_marker(origin, bounds, cell, at, UiPalette.MAP_CHEST)
	if player != null and _blink_on:
		_marker(origin, bounds, cell, _cell_of(walls, player), UiPalette.MAP_YOU)


func _cell_of(walls: TileMapLayer, node: Node2D) -> Vector2i:
	return walls.local_to_map(walls.to_local(node.global_position))


## A square a little bigger than a cell, outlined in ink, centred on [param at].
func _marker(origin: Vector2, bounds: Rect2i, cell: float, at: Vector2i, colour: Color) -> void:
	var side := maxf(cell + 2.0, 3.0)
	var centre := origin + (Vector2(at - bounds.position) + Vector2(0.5, 0.5)) * cell
	var box := Rect2(((centre - Vector2(side, side) / 2.0) * 2.0).round() / 2.0, Vector2(side, side))
	draw_rect(box, UiPalette.MAP_OUTLINE)
	draw_rect(box.grow(-0.5), colour)
