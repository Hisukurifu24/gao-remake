extends MenuPage
## Items: the player in their gear on the left, the bag in the middle, and what
## the cursor is on, up close, on the right.
##
## Purely a view: it shows what [Inventory] holds and answers with [method
## Inventory.use] / [method Inventory.equip_stack] / [method Inventory.unequip] /
## [method Inventory.move_stack] / [method Inventory.drop_stack]. An action greyed
## out here is also refused there. [code]test/inventory_test.tscn[/code] runs the
## whole system with this page never built.
##
## [b]One cursor[/b] covers the three places: the category tabs above the bag
## (left and right filter it at once), the bag, and the three slots beside the
## player. Up off the bag's top row is the tabs; left off its first column is the
## slot on that row, and right off a slot is the bag again.
##
## [b]Picking a piece of gear shows what wearing it would do[/b]: the stats under
## the player grow a green or red difference ([method Inventory.change_if_worn]).
##
## [b]The mouse drives the same cursor[/b]: hovering selects, double- or right-click
## is the confirm key, and dragging is a verb the keys don't have --
##
## [codeblock]
## bag  -> bag    reorder; same item merges, anything else swaps
## bag  -> slot   equip, if the slot takes that kind
## slot -> bag    unequip; onto a compatible item, swap with it
## any  -> X      drop the stack (never a key item)
## [/codeblock]
##
## Drag-and-drop goes through Godot's own drag system via [method
## Control.set_drag_forwarding], so the cells stay plain [Panel]s and every rule
## lives here.

enum Focus { BAG, DOLL, TABS }

const COLUMNS := 6
## A bag cell: a 16 px icon drawn twice its size -- a world texel's size on the
## map -- inset off the cell's lip.
const CELL := Vector2(36, 36)
const ICON_INSET := 2.0
## The most of a description the details have room for; the longest one shipped
## takes eight.
const DETAIL_LINES := 9
const SHEET := "res://assets/ninja_adventure/Actor/Character/SamuraiBlue/SpriteSheet.png"
const TRASH := "res://assets/ninja_adventure/Ui/Theme/Theme Wood/checked.png"
## [name, tab icon, the kinds it shows -- none for all].
const CATEGORIES := [
	["All items", "res://assets/ninja_adventure/Items/Object/Bag.png", []],
	["Consumables", "res://assets/icons/items/health_potion.png", [Item.Kind.CONSUMABLE]],
	["Equipment", "res://assets/icons/items/bronze_sword.png",
			[Item.Kind.WEAPON, Item.Kind.ARMOR, Item.Kind.ACCESSORY]],
	["Materials", "res://assets/icons/items/lizard_scale.png", [Item.Kind.MATERIAL]],
	["Key items", "res://assets/ninja_adventure/Items/Treasure/GoldKey.png", [Item.Kind.KEY]],
]
## What an empty slot shows, faint: the kind of thing that goes there.
const GHOSTS := [&"bronze_sword", &"leather_coat", &"guard_ring"]
const STATS := [["ATK", &"attack", &"total_attack"], ["DEF", &"defense", &"total_defense"],
		["SPD", &"speed", &"total_speed"], ["HP", &"max_hp", &"total_max_hp"]]

var _focus := Focus.BAG
var _bag_index := 0
var _doll_index := 0
var _category := 0
## The bag as it was when last drawn, and which of its stacks the grid shows, in
## order -- every one, or one category's.
var _stacks: Array[ItemStack] = []
var _view: Array[int] = []
var _cells: Array[Panel] = []
var _doll: Array[Panel] = []
var _tabs: Array[Panel] = []
var _trash: Panel
## What is in hand, or empty. Written by [method _begin_drag], cleared when the
## viewport says the drag is over -- see [method _process].
var _drag: Dictionary = {}
var _was_dragging := false

var _category_name: Label
var _count: Label
var _stat_values: Array[Label] = []
var _stat_deltas: Array[Label] = []
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_stats: Label
var _detail_text: Label
var _detail_price: Label


func title() -> String:
	return "Items"


func _init() -> void:
	set_process(false)
	var row := box(false, 6, self)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_doll(row)
	_build_bag(row)
	_build_detail(row)


func _ready() -> void:
	EventBus.inventory_changed.connect(func() -> void:
		if visible:
			_refresh())


func shown() -> void:
	_focus = Focus.BAG
	_bag_index = 0
	_drag = {}
	_was_dragging = false
	set_process(true)
	_refresh()


func hidden() -> void:
	_drag = {}
	set_process(false)


## Godot has no "a drag ended" signal, and a stack let go over nothing still has
## to put the highlights back. One bool compare a frame, only while the page is up.
func _process(_delta: float) -> void:
	var dragging := get_viewport().gui_is_dragging()
	if dragging == _was_dragging:
		return
	_was_dragging = dragging
	if not dragging:
		_drag = {}
	_refresh()


# --- the keys --------------------------------------------------------------

func handle(event: InputEvent) -> bool:
	if is_up(event):
		_move(0, -1)
	elif is_down(event):
		_move(0, 1)
	elif is_left(event):
		_move(-1, 0)
	elif is_right(event):
		_move(1, 0)
	elif is_confirm(event):
		_confirm()
	elif is_key(event, KEY_X):
		_drop()
	elif is_key(event, KEY_R):
		Audio.play(&"tab")
		Inventory.sort()
	else:
		return false
	return true


func hints() -> Array:
	var said: Array = []
	match _focus:
		Focus.TABS:
			said.append([["Left", "Right"], "filter"])
		Focus.DOLL:
			if Inventory.equipped(Inventory.SLOTS[_doll_index]) != null:
				said.append(["Space", "take off"])
		Focus.BAG:
			var stack := _selected_stack()
			if stack != null and stack.item.is_equipment():
				said.append(["Space", "equip"])
			elif stack != null and stack.item.is_consumable() and stack.item.usable_in_field:
				said.append(["Space", "use"])
			if stack != null and stack.item.kind != Item.Kind.KEY:
				said.append(["X", "drop"])
	said.append(["R", "sort"])
	return said


func _move(dx: int, dy: int) -> void:
	var was := _cursor()
	_step(dx, dy)
	if _cursor() != was:
		Audio.play(&"move")


## Where the cursor is, all of it: what the page is on, and where in each part.
func _cursor() -> Vector4i:
	return Vector4i(_focus, _bag_index, _doll_index, _category)


func _step(dx: int, dy: int) -> void:
	match _focus:
		Focus.TABS:
			if dy > 0:
				_focus = Focus.BAG
				_bag_index = 0
			elif dx != 0:
				set_category(clampi(_category + dx, 0, CATEGORIES.size() - 1))
				return
		Focus.DOLL:
			if dy < 0 and _doll_index == 0:
				_focus = Focus.TABS
			elif dx > 0:
				_focus = Focus.BAG
				_bag_index = clampi(_doll_index * COLUMNS, 0, maxi(0, _view.size() - 1))
			elif dy != 0:
				_doll_index = clampi(_doll_index + dy, 0, Inventory.SLOTS.size() - 1)
		Focus.BAG:
			if dy < 0 and _bag_index < COLUMNS:
				_focus = Focus.TABS
			elif dx < 0 and _bag_index % COLUMNS == 0:
				_focus = Focus.DOLL
				_doll_index = mini(_bag_index / COLUMNS, Inventory.SLOTS.size() - 1)
			elif not _view.is_empty():
				_bag_index = clampi(_bag_index + dx + dy * COLUMNS, 0, _view.size() - 1)
	_refresh()


func _confirm() -> void:
	match _focus:
		Focus.TABS:
			_move(0, 1)
		Focus.DOLL:
			if Inventory.equipped(Inventory.SLOTS[_doll_index]) != null:
				Audio.play(&"equip" if Inventory.unequip(Inventory.SLOTS[_doll_index]) else &"refuse")
		Focus.BAG:
			var stack := _selected_stack()
			if stack == null:
				return
			if stack.item.is_equipment():
				Audio.play(&"equip" if Inventory.equip_stack(stack) else &"refuse")
			elif stack.item.is_consumable() and not Inventory.use(stack.item.id):
				# A potion that worked is heard by [Audio] off the bus.
				Audio.play(&"refuse")


func _drop() -> void:
	var stack := _selected_stack()
	if stack != null:
		Audio.play(&"drop" if Inventory.drop_stack(stack) else &"refuse")


## Shows one category's stacks, or all of them. The tabs above the bag, or
## left and right while the cursor is on them.
func set_category(at: int) -> void:
	_category = clampi(at, 0, CATEGORIES.size() - 1)
	_bag_index = 0
	_refresh()


func category() -> int:
	return _category


func _selected_stack() -> ItemStack:
	if _focus != Focus.BAG or _bag_index < 0 or _bag_index >= _view.size():
		return null
	return _stacks[_view[_bag_index]]


## The bag index of the stack in grid cell [param cell], or -1 for an empty one.
func _real(cell: int) -> int:
	return _view[cell] if cell >= 0 and cell < _view.size() else -1


func _shows(item: Item) -> bool:
	var kinds: Array = CATEGORIES[_category][2]
	return kinds.is_empty() or item.kind in kinds


# --- the mouse -------------------------------------------------------------
## Hovering *is* selecting. A hover over an empty cell is ignored: sweeping the
## pointer across the blank half of the bag should not blank the details.

func _on_cell_hovered(cell: int) -> void:
	if get_viewport().gui_is_dragging() or cell >= _view.size():
		return
	_focus = Focus.BAG
	_bag_index = cell
	_refresh()


func _on_doll_hovered(at: int) -> void:
	if get_viewport().gui_is_dragging():
		return
	_focus = Focus.DOLL
	_doll_index = at
	_refresh()


func _on_cell_clicked(event: InputEvent, cell: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or cell >= _view.size():
		return
	_focus = Focus.BAG
	_bag_index = cell
	if button.button_index == MOUSE_BUTTON_RIGHT \
			or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		_confirm()
	_refresh()


func _on_doll_clicked(event: InputEvent, at: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	_focus = Focus.DOLL
	_doll_index = at
	if button.button_index == MOUSE_BUTTON_RIGHT \
			or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		_confirm()
	_refresh()


func _on_tab_clicked(event: InputEvent, at: int) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_focus = Focus.TABS
		set_category(at)


# --- drag and drop ---------------------------------------------------------
## Godot calls the forwarded callbacks in order: [code]_*_drag[/code] once when a
## stack leaves its cell, [code]_*_can_drop[/code] every frame the pointer is
## over a target, [code]_*_drop[/code] once when it is let go. The rules live in
## [method _accepts_bag] / [method _accepts_doll] / [method _accepts_trash],
## which painting reads too -- so what lights up green and what a drop does can
## never disagree.

func _cell_drag(_at: Vector2, cell: int) -> Variant:
	var index := _real(cell)
	if index < 0:
		return null
	return _begin_drag(_cells[cell], {&"source": &"bag", &"index": index, &"slot": &"",
			&"item": _stacks[index].item})


func _doll_drag(_at: Vector2, at: int) -> Variant:
	var slot: StringName = Inventory.SLOTS[at]
	var item := Inventory.equipped(slot)
	if item == null:
		return null
	return _begin_drag(_doll[at], {&"source": &"gear", &"index": at, &"slot": slot, &"item": item})


## What rides the pointer is a cell with the item in it, centred on the pointer:
## Godot puts a preview's top-left at the cursor, which reads as pointing at the
## cell below the one you mean.
func _begin_drag(source: Control, data: Dictionary) -> Variant:
	var item := data[&"item"] as Item
	var holder := Control.new()
	var chip := _new_cell()
	chip.position = -CELL * 0.5
	chip.size = CELL
	chip.self_modulate = _tint(item)
	(chip.get_node("Icon") as TextureRect).texture = item.icon
	holder.add_child(chip)
	holder.modulate = Color(1.0, 1.0, 1.0, 0.9)
	source.set_drag_preview(holder)
	_drag = data
	_was_dragging = true
	_refresh()
	return data


func _cell_can_drop(_at: Vector2, data: Variant, cell: int) -> bool:
	return _accepts_bag(data, cell)


func _doll_can_drop(_at: Vector2, data: Variant, at: int) -> bool:
	return _accepts_doll(data, at)


func _trash_can_drop(_at: Vector2, data: Variant) -> bool:
	return _accepts_trash(data)


func _cell_drop(_at: Vector2, data: Variant, cell: int) -> void:
	if not _accepts_bag(data, cell):
		return
	var payload := data as Dictionary
	var target := _real(cell)
	if payload[&"source"] == &"bag":
		Inventory.move_stack(payload[&"index"], target if target >= 0 else _stacks.size())
	elif target >= 0:
		# Onto a compatible piece: equipping it is the swap, in one operation, so
		# the player is never briefly holding neither.
		Inventory.equip_stack(_stacks[target])
	else:
		Inventory.unequip(payload[&"slot"])
	_end_drag()


func _doll_drop(_at: Vector2, data: Variant, at: int) -> void:
	if not _accepts_doll(data, at):
		return
	Inventory.equip_stack(_stacks[(data as Dictionary)[&"index"]])
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


func _accepts_bag(data: Variant, cell: int) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or cell >= Inventory.CAPACITY:
		return false
	var target := _real(cell)
	if payload[&"source"] == &"bag":
		var from: int = payload[&"index"]
		if target == from:
			return false
		if target >= 0:
			return true
		# An empty cell is "the back of the bag" -- move_stack's own answer, down
		# to the last stack having nowhere further back to go, and a full bag
		# (whose empty cells only a filter shows) having no back at all.
		return from < _stacks.size() - 1 and _stacks.size() < Inventory.CAPACITY
	if target < 0:
		return not Inventory.is_full()
	return _stacks[target].item.slot() == payload[&"slot"]


func _accepts_doll(data: Variant, at: int) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or payload[&"source"] != &"bag":
		return false
	var item := payload[&"item"] as Item
	return item.is_equipment() and item.slot() == Inventory.SLOTS[at]


func _accepts_trash(data: Variant) -> bool:
	var payload := _payload(data)
	if payload.is_empty() or payload[&"source"] != &"bag":
		return false
	return (payload[&"item"] as Item).kind != Item.Kind.KEY


## The drag payload, if it is one of ours and still describes something real.
## The bag can change under a held stack -- a repaint, a merge, loot arriving --
## and acting on a stale index would move whatever moved into its place.
func _payload(data: Variant) -> Dictionary:
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

func _build_doll(row: Control) -> void:
	var card := panel(&"InsetPanel", row)
	var column := box(true, 8, card)

	# The player, and the three slots in a column beside them -- one per bag row,
	# so left off the bag lands on the slot level with the cursor.
	var dressed := box(false, 4, column)
	dressed.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sheet := AtlasTexture.new()
	sheet.atlas = load(SHEET) as Texture2D
	sheet.region = Rect2(0, 0, 16, 16)
	var figure := icon_rect(sheet, Vector2(64, 64), dressed)
	figure.stretch_mode = TextureRect.STRETCH_SCALE
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var slots := box(true, 4, dressed)
	for i in Inventory.SLOTS.size():
		var cell := _new_cell()
		cell.mouse_entered.connect(_on_doll_hovered.bind(i))
		cell.gui_input.connect(_on_doll_clicked.bind(i))
		cell.set_drag_forwarding(_doll_drag.bind(i), _doll_can_drop.bind(i), _doll_drop.bind(i))
		slots.add_child(cell)
		_doll.append(cell)

	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override(&"h_separation", 4)
	stats.add_theme_constant_override(&"v_separation", 0)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(stats)
	for stat: Array in STATS:
		label(stat[0], &"HeaderLabel", stats).custom_minimum_size = Vector2(32, 0)
		var value := label("", &"", stats)
		value.custom_minimum_size = Vector2(36, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stat_values.append(value)
		var delta := label("", &"", stats)
		delta.custom_minimum_size = Vector2(32, 0)
		_stat_deltas.append(delta)


func _build_bag(row: Control) -> void:
	var card := panel(&"InsetPanel", row)
	var column := box(true, 4, card)

	var tabs := box(false, 0, column)
	for i in CATEGORIES.size():
		var tab := _new_cell(load(CATEGORIES[i][1]) as Texture2D)
		tab.gui_input.connect(_on_tab_clicked.bind(i))
		tabs.add_child(tab)
		_tabs.append(tab)
	spacer(tabs)
	_trash = _new_cell(load(TRASH) as Texture2D)
	_trash.tooltip_text = "Drop here to throw away"
	_trash.set_drag_forwarding(Callable(), _trash_can_drop, _trash_drop)
	tabs.add_child(_trash)

	var header := box(false, 6, column)
	_category_name = label("", &"HeaderLabel", header)
	spacer(header)
	var sort := Button.new()
	sort.text = "Sort"
	sort.focus_mode = Control.FOCUS_NONE
	sort.pressed.connect(func() -> void: Inventory.sort())
	header.add_child(sort)
	_count = label("", &"HintLabel", header)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(grid)
	for i in Inventory.CAPACITY:
		var cell := _new_cell()
		cell.mouse_entered.connect(_on_cell_hovered.bind(i))
		cell.gui_input.connect(_on_cell_clicked.bind(i))
		cell.set_drag_forwarding(_cell_drag.bind(i), _cell_can_drop.bind(i), _cell_drop.bind(i))
		grid.add_child(cell)
		_cells.append(cell)


func _build_detail(row: Control) -> void:
	var card := panel(&"InsetPanel", row)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := box(true, 2, card)
	# The icon in a cell beside its name, at the bag's own size: the column's
	# height goes to the description, which is the part that runs long.
	var header := box(false, 6, column)
	var frame := Panel.new()
	frame.theme_type_variation = &"CellPanel"
	frame.custom_minimum_size = CELL
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(frame)
	_detail_icon = icon_rect(null, CELL - Vector2(ICON_INSET, ICON_INSET) * 2.0, frame)
	_detail_icon.position = Vector2(ICON_INSET, ICON_INSET)
	# Two lines of name sit level with the cell; the kind goes under both.
	_detail_name = label("", &"", header)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_kind = label("", &"HintLabel", column)
	_detail_stats = label("", &"", column)
	_detail_text = label("", &"", column)
	_detail_text.max_lines_visible = DETAIL_LINES
	spacer(column)
	_detail_price = label("", &"HintLabel", column)
	for text: Label in [_detail_name, _detail_kind, _detail_stats, _detail_text, _detail_price]:
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A cell: the pack's slot, an icon inset off its lip, a count in its corner, and
## the pack's focus frame over the lot -- so the cursor is never hidden by what it
## is pointing at.
func _new_cell(texture: Texture2D = null) -> Panel:
	var cell := Panel.new()
	cell.theme_type_variation = &"CellPanel"
	cell.custom_minimum_size = CELL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = ICON_INSET
	icon.offset_top = ICON_INSET
	icon.offset_right = -ICON_INSET
	icon.offset_bottom = -ICON_INSET
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)

	var count := Label.new()
	count.name = "Count"
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.offset_right = -4.0
	count.offset_bottom = 2.0
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.theme_type_variation = &"CountLabel"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(count)

	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme_type_variation = &"FocusFrame"
	frame.visible = false
	cell.add_child(frame)
	return cell


## A cell's tint is the rarity of what is in it, or the green of a place a dragged
## stack may land -- [member CanvasItem.self_modulate], which reaches the cell and
## not the icon on it.
func _tint(item: Item, droppable := false) -> Color:
	if droppable:
		return UiPalette.DROP
	if item != null:
		return item.rarity_color().lerp(Color.WHITE, 0.3)
	return UiPalette.EMPTY_SLOT


# --- drawing ---------------------------------------------------------------

func _refresh() -> void:
	_stacks = Inventory.stacks()
	_view.clear()
	for i in _stacks.size():
		if _shows(_stacks[i].item):
			_view.append(i)
	_bag_index = clampi(_bag_index, 0, maxi(0, _view.size() - 1))

	_category_name.text = CATEGORIES[_category][0]
	_count.text = "%d/%d" % [Inventory.used_slots(), Inventory.CAPACITY]
	_paint_tabs()
	_paint_cells()
	_paint_doll()
	_paint_detail()
	hints_changed.emit()


func _paint_tabs() -> void:
	for i in _tabs.size():
		var on := i == _category
		_tabs[i].self_modulate = Color.WHITE if on else UiPalette.EMPTY_SLOT
		(_tabs[i].get_node("Icon") as CanvasItem).modulate.a = 1.0 if on else 0.55
		(_tabs[i].get_node("Frame") as CanvasItem).visible = on and _focus == Focus.TABS
	var live := _accepts_trash(_drag)
	_trash.self_modulate = UiPalette.DROP if live else UiPalette.EMPTY_SLOT
	(_trash.get_node("Icon") as CanvasItem).modulate.a = 1.0 if live or _drag.is_empty() else 0.35


func _paint_cells() -> void:
	for i in _cells.size():
		var cell := _cells[i]
		var index := _real(i)
		var stack: ItemStack = _stacks[index] if index >= 0 else null
		var icon := cell.get_node("Icon") as TextureRect
		icon.texture = stack.item.icon if stack != null else null
		(cell.get_node("Count") as Label).text = \
				str(stack.count) if stack != null and stack.count > 1 else ""
		# The stack in hand is drawn faded where it came from.
		var lifted: bool = not _drag.is_empty() and _drag[&"source"] == &"bag" \
				and _drag[&"index"] == index and index >= 0
		icon.modulate.a = 0.35 if lifted else 1.0
		var droppable: bool = not lifted and _accepts_bag(_drag, i)
		cell.self_modulate = _tint(stack.item if stack != null else null, droppable)
		(cell.get_node("Frame") as CanvasItem).visible = \
				_focus == Focus.BAG and i == _bag_index and stack != null


func _paint_doll() -> void:
	for i in _doll.size():
		var slot: StringName = Inventory.SLOTS[i]
		var stack := Inventory.worn(slot)
		var cell := _doll[i]
		var icon := cell.get_node("Icon") as TextureRect
		var lifted: bool = not _drag.is_empty() and _drag[&"source"] == &"gear" and _drag[&"slot"] == slot
		if stack != null:
			icon.texture = stack.item.icon
			icon.modulate = Color(1, 1, 1, 0.35 if lifted else 1.0)
		else:
			# A faint outline of what goes here.
			var ghost := ItemLibrary.get_item(GHOSTS[i])
			icon.texture = ghost.icon if ghost != null else null
			icon.modulate = Color(0, 0, 0, 0.3)
		(cell.get_node("Count") as Label).text = "+%d" % stack.plus if stack != null and stack.plus > 0 else ""
		var droppable := _accepts_doll(_drag, i)
		cell.self_modulate = _tint(stack.item if stack != null else null, droppable)
		if not _drag.is_empty() and not droppable and not lifted:
			cell.self_modulate = cell.self_modulate.darkened(0.4)
		(cell.get_node("Frame") as CanvasItem).visible = _focus == Focus.DOLL and i == _doll_index

	# What the gear in hand, or under the cursor, would change.
	var trying := _trying_on()
	for i in STATS.size():
		var stat: Array = STATS[i]
		_stat_values[i].text = str(GameState.call(stat[2]))
		var change := Inventory.change_if_worn(trying, stat[1])
		_stat_deltas[i].text = "" if change == 0 else "%+d" % change
		_stat_deltas[i].add_theme_color_override(&"font_color", UiPalette.GOOD if change > 0 else UiPalette.BAD)


## The piece of gear the stats are compared against: the one being dragged from
## the bag, or the one the bag's cursor is on.
func _trying_on() -> ItemStack:
	if not _drag.is_empty():
		if _drag[&"source"] != &"bag":
			return null
		return _stacks[_drag[&"index"]] if _drag[&"index"] < _stacks.size() else null
	var stack := _selected_stack()
	return stack if stack != null and stack.item.is_equipment() else null


func _paint_detail() -> void:
	var stack := _detail_stack()
	if _focus == Focus.TABS and _drag.is_empty():
		_show_nothing(CATEGORIES[_category][0],
				"%d of %d stacks." % [_view.size(), _stacks.size()] if not _stacks.is_empty() else "The bag is empty.")
		return
	if stack == null:
		if _focus == Focus.DOLL:
			_show_nothing(String(Inventory.SLOTS[_doll_index]).capitalize(), "Nothing worn.")
		else:
			_show_nothing("--", "Nothing here.")
		return

	var item := stack.item
	_detail_icon.texture = item.icon
	_detail_icon.modulate = Color.WHITE
	_detail_name.text = item.label_at(stack.plus)
	_detail_name.add_theme_color_override(&"font_color", UiPalette.rarity_ink(item.rarity))
	var worn := _focus == Focus.DOLL and _drag.is_empty()
	# A consumable that only works in a fight says so where its kind goes.
	var battle_only := item.is_consumable() and not item.usable_in_field
	_detail_kind.text = "%s %s%s" % [item.rarity_name(),
			"Battle item" if battle_only else item.kind_name(), " -- worn" if worn else ""]
	var summary := item.summary(stack.plus)
	# Two terms to a line, so a wrap never splits "HP +20" across two.
	var terms := summary.split("  ")
	var lines := PackedStringArray()
	for i in range(0, terms.size(), 2):
		lines.append("  ".join(terms.slice(i, i + 2)))
	_detail_stats.text = "\n".join(lines)
	_detail_stats.visible = not summary.is_empty()
	# Green for a piece that only adds, red for one that only costs, and plain for
	# a trade -- a coat that slows you is not a bad coat.
	var gains := summary.contains("+") or summary.begins_with("Heals") or summary.begins_with("Cures")
	var costs := summary.contains("-")
	_detail_stats.add_theme_color_override(&"font_color",
			UiPalette.TEXT if gains and costs else (UiPalette.BAD if costs else UiPalette.GOOD))
	# The description's line breaks are the dialogue box's; in this narrower
	# column a forced break wastes half a line.
	_detail_text.text = item.description.replace("\n", " ")
	_detail_text.add_theme_color_override(&"font_color", UiPalette.TEXT)
	_detail_price.text = "Sells for %d col" % item.sell_price() if item.is_sellable() \
			else ("Key item" if item.kind == Item.Kind.KEY else "Worth nothing to a shop")


func _show_nothing(heading: String, line: String) -> void:
	_detail_icon.texture = null
	_detail_name.text = heading
	_detail_name.add_theme_color_override(&"font_color", UiPalette.HEADER)
	_detail_kind.text = ""
	_detail_stats.text = ""
	_detail_stats.visible = false
	_detail_text.text = line
	_detail_text.add_theme_color_override(&"font_color", UiPalette.DIM)
	_detail_price.text = ""


## The copy the details describe: the one in hand, the worn one, or the one
## under the cursor.
func _detail_stack() -> ItemStack:
	if not _drag.is_empty():
		if _drag[&"source"] == &"gear":
			return Inventory.worn(_drag[&"slot"])
		var index: int = _drag[&"index"]
		return _stacks[index] if index < _stacks.size() else null
	if _focus == Focus.DOLL:
		return Inventory.worn(Inventory.SLOTS[_doll_index])
	return _selected_stack()


# --- for tests and tools -----------------------------------------------------

## The stacks the grid shows, in order: every one, or one category's.
func shown_stacks() -> Array[ItemStack]:
	var shown: Array[ItemStack] = []
	for index in _view:
		shown.append(_stacks[index])
	return shown


## Whether the details of what the cursor is on fit the page: every line of the
## description shown, and nothing pushing the page taller than the window.
func details_fit() -> bool:
	var row := get_child(0) as Control
	return _detail_text.get_line_count() <= _detail_text.max_lines_visible \
			and row.get_combined_minimum_size().y <= size.y


## Puts the cursor on grid cell [param at], as hovering it would.
func select_cell(at: int) -> void:
	_on_cell_hovered(at)


## The stack under the cursor, or null.
func selected_stack() -> ItemStack:
	return _selected_stack()


func cell(at: int) -> Control:
	return _cells[at]


func doll_slot(at: int) -> Control:
	return _doll[at]


func stat_delta(at: int) -> String:
	return _stat_deltas[at].text
