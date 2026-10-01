extends CanvasLayer
## The map (M): the map you are standing on, as far as you have seen it, drawn in
## ink on a sheet of the pack's paper.
##
## A view like the journal and the bag -- it reads [GameState]'s explored cells
## through [MapView] and changes nothing. It holds the input lock while open, so
## nothing on the floor moves while you study it.

## The legend's symbols and their colours -- the same ones [MapView] draws with.
const KEYS := {
	&"You/Key": UiPalette.MAP_YOU,
	&"Door/Key": UiPalette.MAP_DOOR,
	&"Exit/Key": UiPalette.MAP_EXIT,
	&"Chest/Key": UiPalette.MAP_CHEST,
	&"Person/Key": UiPalette.MAP_PERSON,
	&"Quest/Key": UiPalette.MAP_QUEST,
}

var _open := false

@onready var _view: MapView = $Sheet/Column/View
@onready var _title: Label = $Sheet/Column/Header/Title
@onready var _region: Label = $Sheet/Column/Header/Region
@onready var _status: Label = $Sheet/Column/Header/Status
@onready var _legend: Control = $Sheet/Column/Legend


func _ready() -> void:
	visible = false
	CombatManager.combat_began.connect(_on_combat_began)
	# The pack's paper, warmed to parchment.
	($Sheet as CanvasItem).self_modulate = UiPalette.MAP_SHEET
	_region.add_theme_color_override(&"font_color", UiPalette.INK_LOCKED)
	for key: StringName in KEYS:
		(_legend.get_node(NodePath(key)) as MapGlyph).colour = KEYS[key]


func is_open() -> bool:
	return _open


func open() -> void:
	var map := SceneRouter.current_map() as GameMap
	if _open or map == null:
		return
	_open = true
	visible = true
	GameState.push_input_lock()
	_title.text = map.display_name if not map.display_name.is_empty() else "Map"
	_region.text = map.region
	_status.text = _status_line(map)
	_view.show_map(map)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_view.show_map(null)
	GameState.pop_input_lock()


## Same rule as the journal and the bag: from the overworld and nowhere else.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed(&"map") and _can_open():
			get_viewport().set_input_as_handled()
			open()
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"map") or event.is_action_pressed(&"ui_cancel"):
		close()


## How much of the map is explored, and whether the door has been found -- the
## two things a player opens the map to find out.
func _status_line(map: GameMap) -> String:
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
	return "   ".join(parts)
