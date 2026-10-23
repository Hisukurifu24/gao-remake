class_name MapPage
extends MenuPage
## Map: the map you are standing on, as far as you have seen it, lit up on a dark
## sheet the way SAO draws its own.
##
## A view -- it reads [GameState]'s explored cells through [MapView] and changes
## nothing.

## The legend's symbols, their words and their colours -- the ones [MapView] draws with.
const KEYS := [
	[MapGlyph.Kind.YOU, "you", UiPalette.MAP_YOU],
	[MapGlyph.Kind.DOOR, "door", UiPalette.MAP_DOOR],
	[MapGlyph.Kind.EXIT, "way out", UiPalette.MAP_EXIT],
	[MapGlyph.Kind.CHEST, "chest", UiPalette.MAP_CHEST],
	[MapGlyph.Kind.CAMP, "camp", UiPalette.MAP_CAMP],
	[MapGlyph.Kind.PUZZLE, "puzzle", UiPalette.MAP_PUZZLE],
	[MapGlyph.Kind.PERSON, "folk", UiPalette.MAP_PERSON],
	[MapGlyph.Kind.QUEST, "quest", UiPalette.MAP_QUEST],
]

var _view: MapView
var _title: Label
var _region: Label
var _status: Label


func title() -> String:
	return "Map"


func _init() -> void:
	var sheet := panel(&"MapPanel", self)
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := box(true, 4, sheet)

	var header := box(false, 8, column)
	_title = label("Map", &"MapLabel", header)
	_region = label(" ", &"MapLabel", header)
	_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_region.add_theme_color_override(&"font_color", UiPalette.MAP_DIM)
	_status = label(" ", &"MapLabel", header)

	_view = MapView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_view)

	var legend := box(false, 8, column)
	for key: Array in KEYS:
		var entry := box(false, 4, legend)
		var glyph := MapGlyph.new()
		glyph.kind = key[0]
		glyph.colour = key[2]
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(glyph)
		label(key[1], &"MapLabel", entry)


func shown() -> void:
	var map := SceneRouter.current_map() as GameMap
	if map == null:
		return
	_title.text = map.display_name if not map.display_name.is_empty() else "Map"
	_region.text = map.region
	_status.text = status_line(map)
	_view.show_map(map)


func hidden() -> void:
	_view.show_map(null)


## The header's three parts, for tests: the map's name, its region, and the status.
func header() -> PackedStringArray:
	return PackedStringArray([_title.text, _region.text, _status.text])


## How much of the map is explored, and whether the door has been found -- the
## two things a player opens the map to find out.
static func status_line(map: GameMap) -> String:
	var ground := map.get_node_or_null("Ground") as TileMapLayer
	var walls := map.get_node_or_null("Walls") as TileMapLayer
	var parts: PackedStringArray = PackedStringArray()
	if ground != null and walls != null:
		var seen := GameState.explored_cells(map.map_id)
		var open_cells := 0
		var explored := 0
		for cell in ground.get_used_cells():
			if walls.get_cell_source_id(cell) != -1:
				continue
			open_cells += 1
			if seen.has(cell):
				explored += 1
		if open_cells > 0:
			parts.append("%d%% explored" % floori(100.0 * explored / open_cells))
	var gate := map.get_node_or_null("BossGate") as BossGate
	if gate != null:
		if GameState.is_floor_cleared(gate.floor_number):
			parts.append("floor cleared")
		elif gate.revealed:
			parts.append("door found")
		else:
			parts.append("door not found")
	var pile := GameState.dropped_col()
	if not pile.is_empty() and pile["map"] == map.map_id:
		parts.append("%d col dropped" % pile["amount"])
	return "   ".join(parts)
