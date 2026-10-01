extends CanvasLayer
## The map (M): the map you are standing on, as far as you have seen it.
##
## A view like the journal and the bag -- it reads [GameState]'s explored cells
## through [MapView] and changes nothing. It holds the input lock while open, so
## nothing on the floor moves while you study it.

var _open := false

@onready var _view: MapView = $Window/Column/Inset/View
@onready var _title: Label = $Window/Column/Header/Title
@onready var _status: Label = $Window/Column/Header/Status


func _ready() -> void:
	visible = false
	CombatManager.combat_began.connect(_on_combat_began)


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
