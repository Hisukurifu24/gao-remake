extends CanvasLayer
## The bag, drawn.
##
## Purely a view, exactly like [code]ui/dialogue_box.gd[/code] and
## [code]ui/combat_screen.gd[/code]: it shows what [Inventory] holds and answers
## with [method Inventory.use] / [method Inventory.equip] / [method
## Inventory.move_stack] / [method Inventory.drop_stack]. It decides nothing --
## an action greyed out here is also refused there, because the autoload is the
## one place a rule cannot be talked around. [code]test/inventory_test.tscn[/code]
## exercises the whole system with this scene never instantiated.
##
## One cursor covers both panels: the bag grid, and the three equipment slots
## above it. Pressing up off the top row of the grid steps into the gear list and
## down off the bottom of the gear list steps back, so there is no second "which
## panel am I in" key to learn.
##
## [b]The mouse drives that same cursor.[/b] Hovering a slot selects it, so the
## detail panel follows the pointer and there is no separate "moused-over" state
## to keep in step with the keyboard one. Clicking selects, double- or
## right-clicking is the [code]Confirm[/code] key, and dragging is a fourth verb
## the keyboard has no equivalent for:
##
## [codeblock]
## bag  -> bag    reorder; same item merges, anything else swaps
## bag  -> gear   equip, if the slot takes that kind
## gear -> bag    unequip; onto a compatible item, swap with it
## any  -> trash  drop the stack (never a key item)
## [/codeblock]
##
## Drag-and-drop goes through Godot's own drag system via [method
## Control.set_drag_forwarding], so the slots stay plain [Panel]s and every rule
## lives here rather than in a per-slot script.

const COLUMNS := 6
## A 16px icon at its own size inside a 2px lip of the pack's cell -- the UI is
## laid out at the map's pixel scale, so an icon is exactly as big as a tile.
const SLOT_SIZE := Vector2(20, 20)
const ICON_INSET := 2.0
const GEAR_ICON_SIZE := Vector2(16, 16)
## Unused slots sit a shade under the lit ones, so the end of the bag reads.
const EMPTY_TINT := Color(0.72, 0.72, 0.72)

## The pack's own highlight frame: the cursor, on a slot or a gear row.
const FOCUS_FRAME := preload("res://assets/ninja_adventure/Ui/Theme/Theme Wood/nine_path_focus.png")

## Which panel the cursor is in.
enum Focus { BAG, GEAR }

var _open := false
var _focus := Focus.BAG
var _bag_index := 0
var _gear_index := 0
## The bag as it was when last drawn. Held so the cursor indexes something
## stable even if a signal repaints mid-frame.
var _stacks: Array[ItemStack] = []
var _slots: Array[Panel] = []
var _gear_rows_list: Array[PanelContainer] = []
## What is currently in hand, or empty. Written by [method _begin_drag] and
## cleared when the viewport says the drag is over -- see [method _process].
var _drag: Dictionary = {}
var _was_dragging := false

@onready var _grid: GridContainer = $Bag/Column/Grid
@onready var _bag_header: Label = $Bag/Column/Header
@onready var _gear_rows: VBoxContainer = $Gear/Rows
@onready var _gear_header: Label = $Gear/Rows/Header
@onready var _totals: Label = $Gear/Rows/Totals
@onready var _detail_name: Label = $Details/Rows/Name
@onready var _detail_kind: Label = $Details/Rows/Kind
@onready var _detail_stats: Label = $Details/Rows/Stats
@onready var _detail_text: Label = $Details/Rows/Description
@onready var _hints: Label = $Hints
@onready var _footer: HBoxContainer = $Footer
var _trash: Button


func _ready() -> void:
	_grid.columns = COLUMNS
	_build_slots()
	_build_gear_rows()
	_build_footer()
	visible = false
	set_process(false)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	CombatManager.combat_began.connect(_on_combat_began)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_focus = Focus.BAG
	_bag_index = 0
	_gear_index = 0
	_drag = {}
	_was_dragging = false
	set_process(true)
	GameState.push_input_lock()
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_drag = {}
	set_process(false)
	GameState.pop_input_lock()


## The bag opens from the overworld and nowhere else: not mid-conversation, not
## mid-fight (the combat screen has its own Item command), not during a map fade.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	close()


func _on_inventory_changed() -> void:
	if _open:
		_refresh()


## Godot has no "a drag ended" signal, and a stack let go over nothing still has
## to put the highlights back. One bool compare a frame, only while the bag is up.
func _process(_delta: float) -> void:
	var dragging := get_viewport().gui_is_dragging()
	if dragging == _was_dragging:
		return
	_was_dragging = dragging
	if not dragging:
		_drag = {}
	_refresh()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed(&"inventory") and _can_open():
			get_viewport().set_input_as_handled()
			open()
		return

	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_move(0, -1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_move(0, 1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_move(-1, 0)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_move(1, 0)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif _is_key(event, KEY_Q):
		_drop()
	elif _is_key(event, KEY_R):
		Inventory.sort()


## Drop and Sort are read straight off the keyboard rather than through the input
## map: they exist only on this screen, and two more project-wide actions for two
## keys nothing else will ever use is a worse trade than this line.
func _is_key(event: InputEvent, key: Key) -> bool:
	var pressed := event as InputEventKey
	return pressed != null and pressed.pressed and not pressed.echo \
			and pressed.physical_keycode == key


func _move(dx: int, dy: int) -> void:
	if _focus == Focus.GEAR:
		# Down off the last gear row is how you get back into the bag.
		if _gear_index + dy >= Inventory.SLOTS.size():
			_focus = Focus.BAG
			_bag_index = 0
		else:
			_gear_index = maxi(0, _gear_index + dy)
	elif _stacks.is_empty() or (dy < 0 and _bag_index < COLUMNS):
		# Up off the top row of the grid -- or up out of an empty bag.
		if dy < 0:
			_focus = Focus.GEAR
			_gear_index = Inventory.SLOTS.size() - 1
	else:
		_bag_index = clampi(_bag_index + dx + dy * COLUMNS, 0, _stacks.size() - 1)
	_refresh()


func _confirm() -> void:
	if _focus == Focus.GEAR:
		Inventory.unequip(Inventory.SLOTS[_gear_index])
		return
	var stack := _selected_stack()
	if stack == null:
		return
	if stack.item.is_equipment():
		Inventory.equip(stack.item)
	elif stack.item.is_consumable():
		Inventory.use(stack.item.id)


func _drop() -> void:
	if _focus != Focus.BAG:
		return
	var stack := _selected_stack()
	if stack != null:
		Inventory.drop_stack(stack)


func _selected_stack() -> ItemStack:
	if _focus != Focus.BAG or _bag_index < 0 or _bag_index >= _stacks.size():
		return null
	return _stacks[_bag_index]


# --- the mouse -------------------------------------------------------------
## Hovering *is* selecting, so the pointer and the arrow keys drive one cursor
## rather than two states that have to agree. A hover over an empty slot is
## ignored: sweeping the mouse across the blank half of the grid should not
## blank the details panel.

func _on_bag_hovered(index: int) -> void:
	if get_viewport().gui_is_dragging() or index >= _stacks.size():
		return
	_focus = Focus.BAG
	_bag_index = index
	_refresh()


func _on_gear_hovered(index: int) -> void:
	if get_viewport().gui_is_dragging():
		return
	_focus = Focus.GEAR
	_gear_index = index
	_refresh()


func _on_bag_clicked(event: InputEvent, index: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or index >= _stacks.size():
		return
	_focus = Focus.BAG
	_bag_index = index
	if button.button_index == MOUSE_BUTTON_RIGHT \
			or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		_confirm()
	_refresh()


func _on_gear_clicked(event: InputEvent, index: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	_focus = Focus.GEAR
	_gear_index = index
	if button.button_index == MOUSE_BUTTON_RIGHT \
			or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		_confirm()
	_refresh()


# --- drag and drop ---------------------------------------------------------
## Godot calls the three forwarded callbacks in order: [code]_bag_drag[/code]
## once when a stack leaves its slot, [code]*_can_drop[/code] on every frame the
## pointer is over a target, and [code]*_drop[/code] once when it is let go.
## The rules live in [method _accepts_bag] / [method _accepts_gear] /
## [method _accepts_trash], which painting also reads -- so what lights up green
## and what a drop actually does can never disagree.

func _bag_drag(_at: Vector2, index: int) -> Variant:
	if index >= _stacks.size():
		return null
	return _begin_drag(_slots[index], {
		&"source": &"bag",
		&"index": index,
		&"slot": &"",
		&"item": _stacks[index].item,
	})


func _gear_drag(_at: Vector2, index: int) -> Variant:
	var slot: StringName = Inventory.SLOTS[index]
	var item := Inventory.equipped(slot)
	if item == null:
		return null
	return _begin_drag(_gear_rows_list[index], {
		&"source": &"gear",
		&"index": index,
		&"slot": slot,
		&"item": item,
	})


## What rides the pointer is a slot with the item in it, not a bare icon: over a
## grid of slots an icon alone is just another one of them, and a floating
## 16-pixel picture on a dark panel is easy to lose.
##
## Godot puts the preview's *top-left* at the cursor, so it hangs off the
## bottom-right and reads as pointing at the slot below the one you mean. The
## wrapper is what lets it be offset back onto the pointer.
func _begin_drag(source: Control, data: Dictionary) -> Variant:
	var item := data[&"item"] as Item

	var holder := Control.new()
	var chip := Panel.new()
	chip.size = SLOT_SIZE
	chip.position = -chip.size * 0.5
	chip.add_theme_stylebox_override(&"panel", _slot_style(item))
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inset(icon)
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.add_child(icon)
	holder.add_child(chip)
	holder.modulate = Color(1.0, 1.0, 1.0, 0.9)
	source.set_drag_preview(holder)

	_drag = data
	_was_dragging = true
	_refresh()
	return data


func _bag_can_drop(_at: Vector2, data: Variant, index: int) -> bool:
	return _accepts_bag(data, index)


func _gear_can_drop(_at: Vector2, data: Variant, index: int) -> bool:
	return _accepts_gear(data, index)


func _trash_can_drop(_at: Vector2, data: Variant) -> bool:
	return _accepts_trash(data)


func _bag_drop(_at: Vector2, data: Variant, index: int) -> void:
	if not _accepts_bag(data, index):
		return
	var payload := data as Dictionary
	if payload[&"source"] == &"bag":
		Inventory.move_stack(payload[&"index"], index)
	elif index < _stacks.size():
		# Onto a compatible piece of gear: equipping it is the swap, and it is
		# one operation, so the player is never briefly holding neither.
		Inventory.equip(_stacks[index].item)
	else:
		Inventory.unequip(payload[&"slot"])
	_end_drag()


func _gear_drop(_at: Vector2, data: Variant, index: int) -> void:
	if not _accepts_gear(data, index):
		return
	Inventory.equip((data as Dictionary)[&"item"] as Item)
	_end_drag()


func _trash_drop(_at: Vector2, data: Variant) -> void:
	if not _accepts_trash(data):
		return
	Inventory.drop_stack(_stacks[(data as Dictionary)[&"index"]])
	_end_drag()


func _end_drag() -> void:
	_drag = {}
	_was_dragging = false
	_refresh()


func _accepts_bag(data: Variant, index: int) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or index >= Inventory.CAPACITY:
		return false
	if payload[&"source"] == &"bag":
		# Mirrors move_stack's own answer, down to "the last stack dropped past
		# the end of the bag has nowhere to go".
		var from: int = payload[&"index"]
		if index == from:
			return false
		return index < _stacks.size() or from < _stacks.size() - 1
	if index >= _stacks.size():
		return true  # Unequip into empty space. There is always room, or no slot.
	return _stacks[index].item.slot() == payload[&"slot"]


func _accepts_gear(data: Variant, index: int) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or payload[&"source"] != &"bag":
		return false
	var item := payload[&"item"] as Item
	return item.is_equipment() and item.slot() == Inventory.SLOTS[index]


func _accepts_trash(data: Variant) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or payload[&"source"] != &"bag":
		return false
	return (payload[&"item"] as Item).kind != Item.Kind.KEY


## The drag payload, if it is one of ours and still describes something real.
## The bag can change under a held stack -- a repaint, a merge, loot arriving --
## and acting on a stale index would move whatever moved into its place.
func _payload(data: Variant) -> Dictionary:
	# Anything can be dropped on a Control -- another UI's payload, a file path.
	if not (data is Dictionary):
		return {}
	var payload: Dictionary = data
	if payload.get(&"item") == null or payload.get(&"source") == null:
		return {}
	var index: int = payload.get(&"index", -1)
	if payload.get(&"source") == &"gear":
		if Inventory.equipped(payload.get(&"slot", &"")) != payload[&"item"]:
			return {}
	elif index < 0 or index >= _stacks.size() or _stacks[index].item != payload[&"item"]:
		return {}
	return payload


# --- building --------------------------------------------------------------

func _build_slots() -> void:
	for i in Inventory.CAPACITY:
		var slot := Panel.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_inset(icon)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		# Full-rect and aligned into the corner rather than offset into it: the
		# badge sits on top of the icon, so it needs an outline more than it
		# needs a precise box.
		var count := Label.new()
		count.name = "Count"
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.offset_right = -3.0
		count.offset_bottom = -1.0
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.theme_type_variation = &"FieldLabel"
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count)

		# Over the icon, so the cursor is never hidden by what it is pointing at.
		var frame := Panel.new()
		frame.name = "Frame"
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override(&"panel", _frame_style(Color.WHITE))
		slot.add_child(frame)

		slot.mouse_entered.connect(_on_bag_hovered.bind(i))
		slot.gui_input.connect(_on_bag_clicked.bind(i))
		slot.set_drag_forwarding(
				_bag_drag.bind(i), _bag_can_drop.bind(i), _bag_drop.bind(i))

		_grid.add_child(slot)
		_slots.append(slot)


## The equipment rows are hand-built in the scene, because they are labels with
## a fixed layout. What they gain here is an icon, and the mouse: the whole row
## is the target, not the 16 pixels of picture in it. Each is a [PanelContainer]
## so it can light up the same way a bag slot does -- a green *word* would be
## competing with a green rarity.
func _build_gear_rows() -> void:
	for i in Inventory.SLOTS.size():
		var panel := _gear_rows.get_node(String(Inventory.SLOTS[i]).capitalize()) as PanelContainer
		var row := panel.get_node("Row") as HBoxContainer
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in row.get_children():
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = GEAR_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		row.move_child(icon, 0)

		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_entered.connect(_on_gear_hovered.bind(i))
		panel.gui_input.connect(_on_gear_clicked.bind(i))
		panel.set_drag_forwarding(
				_gear_drag.bind(i), _gear_can_drop.bind(i), _gear_drop.bind(i))
		_gear_rows_list.append(panel)


## Sort and Close are on the keyboard already; the buttons are so that a player
## who opened the bag with the mouse never has to guess a letter. Discard is a
## button too, for the hover and pressed states, but it is the one control that
## does two jobs: clicked it throws away the selected stack, exactly as
## [kbd]Q[/kbd] does, and dragged onto it throws away whatever was carried there.
func _build_footer() -> void:
	_trash = _make_button("Discard", _drop)
	_trash.set_drag_forwarding(Callable(), _trash_can_drop, _trash_drop)
	_footer.add_child(_trash)

	_footer.add_child(_make_button("Sort", func() -> void: Inventory.sort()))
	_footer.add_child(_make_button("Close", close))


func _make_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 16)
	# No focus, or the button eats the arrow keys the grid cursor runs on.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button


## Pulls a full-rect child in off the cell's lip.
func _inset(control: Control) -> void:
	control.offset_left = ICON_INSET
	control.offset_top = ICON_INSET
	control.offset_right = -ICON_INSET
	control.offset_bottom = -ICON_INSET


## A slot is the pack's cell, tinted by what is in it. The tint carries rarity,
## so the grid reads at a glance without every icon needing its own colour scheme.
func _slot_style(item: Item, droppable := false) -> StyleBoxTexture:
	var style := (get_theme_stylebox_for(&"CellPanel")).duplicate() as StyleBoxTexture
	if droppable:
		style.modulate_color = UiPalette.DROP
	elif item != null:
		style.modulate_color = item.rarity_color().lerp(Color.WHITE, 0.3)
	else:
		style.modulate_color = EMPTY_TINT
	return style


## The highlight frame, drawn a pixel outside whatever it is on. With no content
## margins, so nothing inside shifts when it appears.
func _frame_style(tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = FOCUS_FRAME
	style.set_texture_margin_all(3.0)
	style.set_content_margin_all(0.0)
	style.set_expand_margin_all(1.0)
	style.modulate_color = tint
	return style


func get_theme_stylebox_for(variation: StringName) -> StyleBox:
	return ThemeDB.get_project_theme().get_stylebox(&"panel", variation)


# --- drawing ---------------------------------------------------------------

func _refresh() -> void:
	_stacks = Inventory.stacks()
	_bag_index = clampi(_bag_index, 0, maxi(0, _stacks.size() - 1))
	# The bag can empty under the cursor -- drinking the last potion, say.
	if _stacks.is_empty() and _focus == Focus.BAG:
		_bag_index = 0

	_bag_header.text = "Bag   %d / %d" % [Inventory.used_slots(), Inventory.CAPACITY]
	_paint_slots()
	_paint_gear()
	_paint_details()
	_paint_footer()


func _paint_slots() -> void:
	for i in _slots.size():
		var slot := _slots[i]
		var icon := slot.get_node("Icon") as TextureRect
		var count := slot.get_node("Count") as Label
		var stack: ItemStack = _stacks[i] if i < _stacks.size() else null

		icon.texture = stack.item.icon if stack != null else null
		count.text = str(stack.count) if stack != null and stack.count > 1 else ""

		# The stack in hand is drawn faded in the slot it came from, so a drag in
		# progress reads as "this is the one you are moving".
		var lifted := _dragging_from_bag(i)
		icon.modulate = Color(1.0, 1.0, 1.0, 0.35 if lifted else 1.0)

		var selected := _focus == Focus.BAG and i == _bag_index and stack != null
		var droppable := not lifted and _accepts_bag(_drag, i)
		slot.add_theme_stylebox_override(&"panel",
				_slot_style(stack.item if stack != null else null, droppable))
		# The frame is the cursor and only the cursor; where a drop may land is
		# the green cell underneath, so the two never have to share one cue.
		(slot.get_node("Frame") as Panel).visible = selected


func _dragging_from_bag(index: int) -> bool:
	return not _drag.is_empty() and _drag[&"source"] == &"bag" and _drag[&"index"] == index


## An equipment row's box: invisible until it means something, and with no
## content margins either way, so nothing shifts a pixel when it appears.
func _gear_style(selected: bool, droppable: bool) -> StyleBox:
	if droppable:
		# The same green cell a bag slot lights up with, stretched under the row.
		var cell := _slot_style(null, true)
		cell.set_content_margin_all(0.0)
		cell.set_expand_margin_all(1.0)
		return cell
	if selected:
		return _frame_style(Color.WHITE)
	return StyleBoxEmpty.new()


func _paint_gear() -> void:
	_gear_header.add_theme_color_override(&"font_color", UiPalette.HEADER)
	# Two labels per row rather than one padded string: the UI font is
	# proportional, so "%-10s" lines nothing up.
	for i in Inventory.SLOTS.size():
		var slot: StringName = Inventory.SLOTS[i]
		var panel := _gear_rows_list[i]
		var row := panel.get_node("Row")
		var item := Inventory.equipped(slot)
		var droppable := _accepts_gear(_drag, i)
		var lifted: bool = not _drag.is_empty() and _drag[&"source"] == &"gear" \
				and _drag[&"slot"] == slot
		# Dimmed while something is in hand that cannot go here, so "where does
		# this fit" is answered by what is still bright.
		var color := item.rarity_color() if item != null else UiPalette.LOCKED
		if not _drag.is_empty() and not droppable:
			color = color.darkened(0.5)

		var icon := row.get_node("Icon") as TextureRect
		icon.texture = item.icon if item != null else null
		icon.modulate = Color(1.0, 1.0, 1.0, 0.35 if lifted else 1.0)

		var name_label := row.get_node("Slot") as Label
		var value_label := row.get_node("Value") as Label
		name_label.text = String(slot).capitalize()
		name_label.add_theme_color_override(&"font_color", color)
		value_label.text = item.label() if item != null else "--"
		value_label.add_theme_color_override(&"font_color", color)

		var selected := _focus == Focus.GEAR and i == _gear_index
		panel.add_theme_stylebox_override(&"panel", _gear_style(selected, droppable))

	_totals.text = "ATK %d DEF %d SPD %d HP %d" % [
			GameState.total_attack(), GameState.total_defense(),
			GameState.total_speed(), GameState.total_max_hp()]
	_totals.add_theme_color_override(&"font_color", UiPalette.DIM)


func _paint_details() -> void:
	var item := _detail_item()
	if item == null:
		_detail_name.text = "--"
		_detail_name.add_theme_color_override(&"font_color", UiPalette.LOCKED)
		_detail_kind.text = ""
		_detail_stats.text = ""
		_detail_text.text = "Nothing here." if _focus == Focus.BAG else "Nothing equipped."
		_detail_text.add_theme_color_override(&"font_color", UiPalette.DIM)
		return

	_detail_name.text = item.label()
	_detail_name.add_theme_color_override(&"font_color", item.rarity_color())
	_detail_kind.text = "%s %s" % [item.rarity_name(), item.kind_name()]
	_detail_kind.add_theme_color_override(&"font_color", UiPalette.DIM)
	_detail_stats.text = item.summary()
	_detail_stats.add_theme_color_override(&"font_color",
			UiPalette.BAD if item.summary().contains("-") else UiPalette.GOOD)
	_detail_text.text = item.description
	_detail_text.add_theme_color_override(&"font_color", UiPalette.TEXT)


func _detail_item() -> Item:
	# What is in hand outranks what is under the pointer: during a drag the
	# details panel should describe the thing being moved.
	if not _drag.is_empty():
		return _drag[&"item"] as Item
	if _focus == Focus.GEAR:
		return Inventory.equipped(Inventory.SLOTS[_gear_index])
	var stack := _selected_stack()
	return stack.item if stack != null else null


func _paint_footer() -> void:
	# Lit while something that can be thrown away is in hand -- and pointedly
	# faded while a key item is, which is the only warning the player gets that
	# the drop is going to be refused.
	var live := _accepts_trash(_drag)
	if live:
		_trash.add_theme_stylebox_override(&"normal", _trash.get_theme_stylebox(&"hover"))
		_trash.add_theme_color_override(&"font_color", UiPalette.INK)
	else:
		_trash.remove_theme_stylebox_override(&"normal")
		_trash.remove_theme_color_override(&"font_color")
	_trash.modulate.a = 1.0 if live or _drag.is_empty() else 0.45

	_hints.text = _hint_text()


func _hint_text() -> String:
	if not _drag.is_empty():
		return "release on a slot to move, or on Discard to throw away"

	var parts := PackedStringArray()
	if _focus == Focus.GEAR:
		if Inventory.equipped(Inventory.SLOTS[_gear_index]) != null:
			parts.append("[E] / right-click: unequip")
		parts.append("drag into the bag")
		return "   ".join(parts)

	# The two keys and the mouse do the same thing to the same item, so they are
	# named together rather than listed as separate features.
	var item := _detail_item()
	if item != null and item.is_equipment():
		parts.append("[E] / right-click: equip")
	elif item != null and item.is_consumable():
		parts.append("[E] / right-click: use" if item.usable_in_field else "[E] battle only")
	if item != null:
		parts.append("[Q] drop")
	parts.append("drag to move")
	return "   ".join(parts)
