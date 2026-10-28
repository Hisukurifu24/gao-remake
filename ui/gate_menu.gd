extends CanvasLayer
## The teleport gate's floor picker: every floor you have stood on, and a way to
## any of them.
##
## A view like the journal: [GameState] says which floors are visited and
## [SceneRouter] does the travelling; this only asks which one. It opens on
## [signal EventBus.teleport_requested], which a [TeleportGate] emits when
## touched, and holds the input lock while open.
##
## One cursor over one list, lowest floor first. The list can run to a hundred
## floors, so it shows a window of [constant ROWS_SHOWN] that follows the cursor;
## left and right jump ten at a time, a band of Aincrad. The mouse drives the same
## cursor -- hovering a row selects it, clicking it travels -- and the rows are
## built once and repainted, never rebuilt, so the row under the pointer stays the
## row under the pointer.

## Twelve, so the window ends above the key line under it.
const ROWS_SHOWN := 12
const PAGE := 10

var _open := false
## The floor the gate was touched on: listed, but going there is staying put.
var _here := 0
var _index := 0
## The top of the window: which entry the first row shows.
var _top := 0
var _entries: Array[int] = []
var _row_nodes: Array[Label] = []

@onready var _counts: Label = $Panel/Column/Counts
@onready var _rows: VBoxContainer = $Panel/Column/Rows
@onready var _more: Label = $Panel/Column/More
@onready var _detail: Label = $Panel/Column/Detail


func _ready() -> void:
	visible = false
	EventBus.teleport_requested.connect(_on_teleport_requested)
	CombatManager.combat_began.connect(_on_combat_began)
	EventBus.screens_close_requested.connect(close)
	for i in ROWS_SHOWN:
		var row := Label.new()
		row.clip_text = true
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		_rows.add_child(row)
		_row_nodes.append(row)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


## Opens on [param here], the floor whose gate was touched. Starts on the highest
## floor you could go to -- from the town, that is the front line.
func open(here: int) -> void:
	if _open:
		return
	_open = true
	visible = true
	_here = here
	_entries = GameState.visited_floors()
	_index = _entries.size() - 1
	if _index > 0 and _entries[_index] == _here:
		_index -= 1
	_top = 0
	_scroll_to(_index)
	GameState.push_input_lock()
	_counts.text = "%d floor%s reached" % [_entries.size(), "" if _entries.size() == 1 else "s"]
	Audio.play(&"open")
	_paint()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	GameState.pop_input_lock()


## The selected floor, or 0 for none.
func selected_floor() -> int:
	return _entries[_index] if _index >= 0 and _index < _entries.size() else 0


## Sends the player to the selected floor, arriving in front of its gate. The
## floor the gate stands on is refused: the detail line says why.
func travel() -> void:
	var floor_number := selected_floor()
	if floor_number <= 0 or floor_number == _here:
		Audio.play(&"refuse")
		return
	close()
	Audio.play(&"warp")
	SceneRouter.enter_floor(floor_number, &"gate")


## Same rule as the journal and the bag: from the overworld and nowhere else.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_teleport_requested(floor_number: int) -> void:
	if _can_open():
		open(floor_number)


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	close()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"ui_cancel"):
		Audio.play(&"close")
		close()
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_select(_index - 1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_select(_index + 1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_select(_index - PAGE)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_select(_index + PAGE)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		travel()


## Moves the cursor, scrolling the window to keep it in view. The keyboard and the
## mouse both come through here, which is what keeps them one cursor.
func _select(index: int) -> void:
	index = clampi(index, 0, _entries.size() - 1)
	if index == _index:
		return
	Audio.play(&"move")
	_index = index
	_scroll_to(index)
	_paint()


func _scroll_to(index: int) -> void:
	if index < _top:
		_top = index
	elif index >= _top + ROWS_SHOWN:
		_top = index - ROWS_SHOWN + 1
	_top = clampi(_top, 0, maxi(0, _entries.size() - ROWS_SHOWN))


func _on_row_hovered(row: int) -> void:
	if _top + row < _entries.size():
		_select(_top + row)


## Clicking a row is the confirm key; the wheel moves the cursor.
func _on_row_input(event: InputEvent, row: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			if _top + row < _entries.size():
				_select(_top + row)
				travel()
		MOUSE_BUTTON_WHEEL_UP:
			_select(_index - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_select(_index + 1)


# --- drawing ---------------------------------------------------------------

func _paint() -> void:
	for i in _row_nodes.size():
		var row := _row_nodes[i]
		var entry := _top + i
		if entry >= _entries.size():
			row.text = " "
			continue
		var floor_number := _entries[entry]
		row.add_theme_color_override(&"font_color",
				UiPalette.LOCKED if floor_number == _here else UiPalette.TEXT)
		row.text = "%s Floor %d  %s" % [">" if entry == _index else " ", floor_number,
				floor_name(floor_number)]

	var above := _top
	var below := maxi(0, _entries.size() - _top - ROWS_SHOWN)
	var more := PackedStringArray()
	if above > 0:
		more.append("^ %d more" % above)
	if below > 0:
		more.append("v %d more" % below)
	_more.text = "   ".join(more) if not more.is_empty() else " "
	_detail.text = _state_line(selected_floor())


## What a floor is called on the list: its own name if it has one, else its land.
static func floor_name(floor_number: int) -> String:
	var definition := FloorRegistry.get_floor(floor_number)
	if not definition.display_name.is_empty():
		return definition.display_name
	var biome := FloorRegistry.get_biome(floor_number)
	return biome.display_name if biome != null else ""


func _state_line(floor_number: int) -> String:
	if floor_number <= 0:
		return " "
	var state := "The front line: its boss stands."
	if floor_number == _here:
		state = "You are standing on it."
	elif GameState.is_floor_cleared(floor_number):
		state = "Cleared."
	var twist := FloorModifier.name_of(floor_number)
	return state if twist.is_empty() else "%s  %s." % [state, twist]
