class_name MapView
extends Control
## One map, as far as the player has explored it, drawn in ink on parchment: the
## floor you have walked, the passages you have only glimpsed, the rock round
## them, the names of places, and a symbol for you, the boss door once found, the
## ways out, unopened chests, the people you have come across and whoever your tracked
## quest wants you to see.
##
## Purely a view. [GameState] says which cells have been seen and walked, the map
## says what is in them, [QuestLog] says what the tracked quest is after; this only
## decides how big a cell is and how it is drawn.

## Cells are drawn in half-unit steps, the smallest a 320x180 layout can draw
## crisply (half a unit is one whole screen pixel), up to four units.
const MAX_CELL := 4.0
const MIN_CELL := 0.5
const BLINK := 0.4
## Graph-paper dots across the unexplored extent, every this many cells.
const GRID_STEP := 4
## The ink line where rock meets floor, in units.
const EDGE := 0.5

var _map: GameMap = null
var _blink_on := true
var _blink_time := 0.0

## The current drawing's placement, set at the top of [method _draw].
var _origin := Vector2.ZERO
var _bounds := Rect2i()
var _cell := 1.0


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
	_bounds = ground.get_used_rect().merge(walls.get_used_rect())
	if not _bounds.has_area():
		return
	var fit := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	_cell = clampf(floorf(fit * 2.0) / 2.0, MIN_CELL, MAX_CELL)
	_origin = (((size - Vector2(_bounds.size) * _cell) / 2.0) * 2.0).floor() / 2.0
	var seen := GameState.explored_cells(_map.map_id)
	var walked := GameState.walked_cells(_map.map_id)

	_draw_sheet()
	_draw_cells(ground, walls, seen, walked)
	_draw_landmarks(seen)
	_draw_markers(walls, seen)


## The floor's extent as a darker wash, dotted like graph paper.
func _draw_sheet() -> void:
	draw_rect(Rect2(_origin, Vector2(_bounds.size) * _cell), UiPalette.MAP_UNSEEN)
	var dot := Vector2(MIN_CELL, MIN_CELL)
	for y in range(GRID_STEP / 2, _bounds.size.y, GRID_STEP):
		for x in range(GRID_STEP / 2, _bounds.size.x, GRID_STEP):
			draw_rect(Rect2(_corner(_bounds.position + Vector2i(x, y)), dot), UiPalette.MAP_GRID)


## Seen cells -- glimpsed floor stippled every other cell -- then the ink where
## rock meets anything open -- a line on the rock's
## side of the shared edge, so a passage keeps its full width.
func _draw_cells(ground: TileMapLayer, walls: TileMapLayer, seen: Dictionary,
		walked: Dictionary) -> void:
	var solid: Dictionary[Vector2i, bool] = {}
	var stipple: Array[Vector2i] = []
	for at: Vector2i in seen:
		var colour: Color
		if walls.get_cell_source_id(at) != -1:
			var water := _map.is_water(at)
			solid[at] = not water
			colour = UiPalette.MAP_WATER if water else UiPalette.MAP_WALL
		elif ground.get_cell_source_id(at) != -1:
			colour = UiPalette.MAP_FLOOR if walked.has(at) else UiPalette.MAP_GLIMPSED
			if not walked.has(at) and at.x % 2 == 0 and at.y % 2 == 0:
				stipple.append(at)
		else:
			continue
		draw_rect(Rect2(_corner(at), Vector2(_cell, _cell)), colour)
	if _cell >= 1.5:
		var dot := Vector2(MIN_CELL, MIN_CELL)
		for at in stipple:
			draw_rect(Rect2(_corner(at) + ((Vector2(_cell, _cell) - dot) / 2.0 / MIN_CELL).floor()
					* MIN_CELL, dot), UiPalette.MAP_GRID)
	var line := minf(EDGE, _cell / 2.0)
	for at: Vector2i in solid:
		if not solid[at]:
			continue
		var box := Rect2(_corner(at), Vector2(_cell, _cell))
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := at + side
			if not seen.has(next) or solid.get(next, false):
				continue
			if walls.get_cell_source_id(next) == -1 and ground.get_cell_source_id(next) == -1:
				continue
			match side:
				Vector2i.UP: draw_rect(Rect2(box.position, Vector2(_cell, line)), UiPalette.MAP_EDGE)
				Vector2i.DOWN: draw_rect(Rect2(box.position + Vector2(0, _cell - line),
						Vector2(_cell, line)), UiPalette.MAP_EDGE)
				Vector2i.LEFT: draw_rect(Rect2(box.position, Vector2(line, _cell)), UiPalette.MAP_EDGE)
				Vector2i.RIGHT: draw_rect(Rect2(box.position + Vector2(_cell - line, 0),
						Vector2(line, _cell)), UiPalette.MAP_EDGE)


## A place's name just above it, once any of it has been seen -- beside the place
## rather than on it, so it never sits on a passage or a symbol. Where the sheet
## ends first it goes just inside the place's top edge instead: below would put it
## on whatever is next door. Ink with a parchment halo, for when it crosses rock.
func _draw_landmarks(seen: Dictionary) -> void:
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	for place: String in _map.landmarks:
		var rect: Rect2i = _map.landmarks[place]
		if not _any_seen(rect, seen):
			continue
		var width := font.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var top := _corner(rect.position)
		var middle := top.x + rect.size.x * _cell / 2.0
		var left := clampf(middle - width / 2.0, 1.0, size.x - width - 1.0)
		var baseline_y := top.y - descent - 1.0
		if baseline_y - ascent < 1.0:
			baseline_y = top.y + ascent + 1.0
		var baseline := Vector2(roundf(left), roundf(baseline_y))
		for halo: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
				Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(font, baseline + halo, place, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size, UiPalette.MAP_FLOOR)
		draw_string(font, baseline, place, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				UiPalette.INK)


func _draw_markers(walls: TileMapLayer, seen: Dictionary) -> void:
	var wanted := _quest_targets()
	var player: Player = null
	var quest_marks: Array[Vector2i] = []
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
				_mark(at, MapGlyph.Kind.DOOR, UiPalette.MAP_DOOR)
				if wanted.has(node):
					quest_marks.append(at)
		elif node is Npc:
			_mark(at, MapGlyph.Kind.PERSON, UiPalette.MAP_PERSON)
			if wanted.has(node):
				quest_marks.append(at)
		elif node is Interactable and ("target_floor" in node or "target_map" in node):
			if (node as Interactable).is_available():
				_mark(at, MapGlyph.Kind.EXIT, UiPalette.MAP_EXIT)
		elif node is Interactable and "opened_flag" in node:
			if (node as Interactable).is_available():
				_mark(at, MapGlyph.Kind.CHEST, UiPalette.MAP_CHEST)
	# Over everything else, so a crowded square can't bury them.
	var lift := Vector2(0, -(MapGlyph.measure(MapGlyph.Kind.PERSON).y
			+ MapGlyph.measure(MapGlyph.Kind.QUEST).y) / 2.0)
	for at in quest_marks:
		MapGlyph.paint(self, MapGlyph.Kind.QUEST, _centre(at) + lift, UiPalette.MAP_QUEST)
	if player != null and _blink_on:
		MapGlyph.paint(self, MapGlyph.Kind.YOU, _centre(_cell_of(walls, player)),
				UiPalette.MAP_YOU, Vector2i(player.facing))


## What the tracked quest wants the player to go and see on this map: its giver
## once it is ready to hand in, a conversation it asks for, or this floor's door
## when it asks for the floor cleared.
func _quest_targets() -> Array[Node]:
	var targets: Array[Node] = []
	var progress := QuestLog.tracked()
	if progress == null:
		return targets
	var quest := progress.quest
	var talk_to: Array[StringName] = []
	var clear_floor := false
	var hand_in := quest.needs_turn_in and QuestLog.is_ready(quest.id)
	if not hand_in:
		for objective in quest.objectives:
			if progress.is_objective_complete(objective):
				continue
			if objective.kind == QuestObjective.Kind.TALK:
				talk_to.append(objective.target)
			elif objective.kind == QuestObjective.Kind.REACH and objective.number == _map.floor_number:
				clear_floor = true
	for child in _map.get_children():
		if child is Npc:
			var npc := child as Npc
			if hand_in and not quest.giver.is_empty() and npc.display_name.begins_with(quest.giver):
				targets.append(npc)
			elif npc.dialogue != null and talk_to.has(npc.dialogue.id):
				targets.append(npc)
		elif child is BossGate and clear_floor:
			targets.append(child)
	return targets


func _any_seen(rect: Rect2i, seen: Dictionary) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if seen.has(Vector2i(x, y)):
				return true
	return false


func _mark(at: Vector2i, glyph: MapGlyph.Kind, colour: Color) -> void:
	MapGlyph.paint(self, glyph, _centre(at), colour)


func _corner(at: Vector2i) -> Vector2:
	return _origin + Vector2(at - _bounds.position) * _cell


func _centre(at: Vector2i) -> Vector2:
	return _corner(at) + Vector2(_cell, _cell) / 2.0


func _cell_of(walls: TileMapLayer, node: Node2D) -> Vector2i:
	return walls.local_to_map(walls.to_local(node.global_position))
