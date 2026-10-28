class_name MenuList
extends VBoxContainer
## A column of plates with one cursor over it: the title's main menu, the game
## menu's System page, the settings.
##
## A row is a plate with a line of text on it and, optionally, a dimmer line under
## it, or a value with [code]<[/code] [code]>[/code] either side that left and
## right change ([signal stepped]). The cursor is the pack's arrow beside the row
## it is on, and that row's plate lights up in SAO's orange. A row that can't be
## chosen now is a greyed plate, and [signal chosen] still
## reports it, so the screen can say why. [code]danger[/code] tints a plate red:
## the one row that destroys something.
##
## The mouse drives the same cursor, as everywhere: hovering a row selects it,
## clicking it chooses it (or, on a value, steps it). Rows are rebuilt only when
## their number changes and repainted otherwise, so the row under the pointer
## stays the row under it. Input from the keyboard is the screen's to read; it
## calls [method move], [method choose] and [method step].

signal chosen(index: int)
signal moved(index: int)
signal stepped(index: int, by: int)

const ARROW := "res://assets/ninja_adventure/Ui/Arrow.png"
const DANGER_TINT := Color(1.0, 0.66, 0.66)

## Centre each row's text on its plate (the title's menu) rather than start it at
## the left edge.
@export var centered := false

## [code]text[/code], and optionally [code]sub[/code], [code]value[/code],
## [code]danger[/code] and [code]enabled[/code] (default true).
var _rows: Array[Dictionary] = []
var _nodes: Array[Control] = []
var index := 0

static var _pointer: Texture2D


func _init() -> void:
	add_theme_constant_override(&"separation", 4)


## The pack's arrow, turned to point right: the cursor in every list.
static func pointer() -> Texture2D:
	if _pointer == null:
		var image := (load(ARROW) as Texture2D).get_image()
		image.rotate_90(COUNTERCLOCKWISE)
		_pointer = ImageTexture.create_from_image(image)
	return _pointer


## Replaces what the rows say. [param keep_cursor] leaves the cursor where it
## was; otherwise it goes to the first row.
func set_rows(rows: Array[Dictionary], keep_cursor := false) -> void:
	_rows = rows
	if _nodes.size() != rows.size():
		_rebuild()
	index = clampi(index if keep_cursor else 0, 0, maxi(0, rows.size() - 1))
	_paint()


func row_count() -> int:
	return _rows.size()


func is_enabled(at: int) -> bool:
	return at >= 0 and at < _rows.size() and bool(_rows[at].get("enabled", true))


## What row [param at] says -- its text, value and the line under it: for tests
## and tools.
func text_of(at: int) -> String:
	if at < 0 or at >= _rows.size():
		return ""
	var row := _rows[at]
	var said := str(row.get("text", ""))
	if row.has("value"):
		said += " < %s >" % row["value"]
	if not str(row.get("sub", "")).is_empty():
		said += "\n" + str(row["sub"])
	return said


## The cursor moved by the player -- a key, the wheel, the mouse -- which is
## heard; [method select] is the page putting it somewhere, which isn't.
func move(by: int) -> void:
	_moved_to(index + by)


func _moved_to(at: int) -> void:
	var was := index
	select(at)
	if index != was:
		Audio.play(&"move")


func select(at: int) -> void:
	if _rows.is_empty():
		return
	at = clampi(at, 0, _rows.size() - 1)
	if at == index:
		return
	index = at
	_paint()
	moved.emit(index)


func choose() -> void:
	if index >= 0 and index < _rows.size():
		Audio.play(&"accept" if is_enabled(index) else &"refuse")
		chosen.emit(index)


## Left and right on a row with a value; nothing on one without.
func step(by: int) -> void:
	if index >= 0 and index < _rows.size() and _rows[index].has("value"):
		Audio.play(&"move" if is_enabled(index) else &"refuse")
		stepped.emit(index, by)


func _rebuild() -> void:
	for node in _nodes:
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	for i in _rows.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override(&"separation", 3)
		row.mouse_entered.connect(_moved_to.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))

		var cursor := TextureRect.new()
		cursor.name = "Cursor"
		cursor.texture = pointer()
		cursor.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cursor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cursor)

		var plate := PanelContainer.new()
		plate.name = "Plate"
		plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(plate)

		var line := HBoxContainer.new()
		line.name = "Line"
		line.add_theme_constant_override(&"separation", 6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(line)

		var words := VBoxContainer.new()
		words.name = "Words"
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override(&"separation", 0)
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(words)
		for part in ["Main", "Sub"]:
			var label := Label.new()
			label.name = part
			label.clip_text = true
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if centered:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			words.add_child(label)

		var value := Label.new()
		value.name = "Value"
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(value)

		add_child(row)
		_nodes.append(row)


func _paint() -> void:
	for i in _rows.size():
		var row := _rows[i]
		var node := _nodes[i]
		var enabled := bool(row.get("enabled", true))
		var here := i == index
		(node.get_node("Cursor") as CanvasItem).modulate.a = 1.0 if here else 0.0

		var plate := node.get_node("Plate") as PanelContainer
		var variation := &"MenuRowLocked"
		if enabled:
			variation = &"MenuRowFocus" if here else &"MenuRow"
		if plate.theme_type_variation != variation:
			plate.theme_type_variation = variation
		plate.self_modulate = DANGER_TINT if bool(row.get("danger", false)) else Color.WHITE

		# The lit plate is orange, and the writing on it a shade darker than ink.
		var ink := UiPalette.ON_ACCENT if here and enabled else UiPalette.TEXT
		if not enabled:
			ink = UiPalette.LOCKED
		var main := node.get_node("Plate/Line/Words/Main") as Label
		main.text = str(row.get("text", ""))
		main.add_theme_color_override(&"font_color", ink)
		var sub := node.get_node("Plate/Line/Words/Sub") as Label
		var below := str(row.get("sub", ""))
		sub.visible = not below.is_empty()
		sub.text = below
		sub.add_theme_color_override(&"font_color", Color(ink, 0.7))
		var value := node.get_node("Plate/Line/Value") as Label
		value.visible = row.has("value")
		value.text = "< %s >" % row.get("value", "")
		value.add_theme_color_override(&"font_color", ink)


## Clicking a row is the confirm key -- or, on a row with a value, steps it
## (right-click steps back). The wheel moves the cursor.
func _on_row_input(event: InputEvent, at: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			select(at)
			if _rows[at].has("value"):
				step(1)
			else:
				choose()
		MOUSE_BUTTON_RIGHT:
			select(at)
			step(-1)
		MOUSE_BUTTON_WHEEL_UP:
			move(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			move(1)
