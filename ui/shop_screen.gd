extends CanvasLayer
## A shop counter: buy off the shelf, sell out of the bag.
##
## A view like the gate menu: the [Shop] decides what is on the shelf and whether
## a trade goes through, [GameState] holds the purse and [Inventory] the bag; this
## only asks which row. It opens on [signal EventBus.shop_requested], which a
## shopkeeper [Npc] emits when talked to, and holds the input lock while open.
##
## One cursor over one list. Left and right switch between buying and selling. A
## row the shop would refuse is drawn locked, and the detail line says why --
## asked of [method Shop.refusal], the same rule [method Shop.buy] enforces, so
## the screen and the counter can't disagree. The mouse drives the same cursor:
## hovering a row selects it, clicking it trades.

enum Mode { BUY, SELL }

const ROWS_SHOWN := 9

var _open := false
var _shop: Shop = null
var _mode := Mode.BUY
var _index := 0
var _top := 0
## What the rows list: [Item]s on the shelf, or the bag's sellable [ItemStack]s.
var _entries: Array = []
var _row_nodes: Array[HBoxContainer] = []
## The last trade, said once on the detail line until the cursor moves.
var _news := ""

@onready var _title: Label = $Panel/Column/Header/Title
@onready var _purse: Label = $Panel/Column/Header/Purse
@onready var _greeting: Label = $Panel/Column/Greeting
@onready var _tabs: Label = $Panel/Column/Tabs
@onready var _rows: VBoxContainer = $Panel/Column/Rows
@onready var _more: Label = $Panel/Column/More
@onready var _detail: Label = $Panel/Column/Detail


func _ready() -> void:
	visible = false
	EventBus.shop_requested.connect(_on_shop_requested)
	EventBus.col_changed.connect(func(_col: int) -> void:
		if _open:
			_paint())
	CombatManager.combat_began.connect(_on_combat_began)
	for i in ROWS_SHOWN:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override(&"separation", 4)
		var item_name := Label.new()
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_name.clip_text = true
		item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var price := Label.new()
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(item_name)
		row.add_child(price)
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		_rows.add_child(row)
		_row_nodes.append(row)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


func open(shop: Shop) -> void:
	if _open or shop == null:
		return
	_open = true
	visible = true
	_shop = shop
	_title.text = shop.label()
	_greeting.text = "%s: \"%s\"" % [shop.keeper, shop.greeting] if not shop.keeper.is_empty() \
			else shop.greeting
	GameState.push_input_lock()
	_set_mode(Mode.BUY)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_shop = null
	GameState.pop_input_lock()


func mode() -> Mode:
	return _mode


## The selected row's item, or null.
func selected_item() -> Item:
	if _index < 0 or _index >= _entries.size():
		return null
	var entry: Variant = _entries[_index]
	return entry.item if entry is ItemStack else entry


## Buys or sells one of the selected row, whichever the screen is doing.
func trade() -> bool:
	var item := selected_item()
	if _shop == null or item == null:
		return false
	var done := _shop.buy(item) if _mode == Mode.BUY else _shop.sell(item)
	if done:
		_news = "Bought %s." % item.label() if _mode == Mode.BUY \
				else "Sold %s for %d col." % [item.label(), item.sell_price()]
	_refresh()
	return done


func _set_mode(next: Mode) -> void:
	_mode = next
	_index = 0
	_top = 0
	_news = ""
	_refresh()


## Re-reads the list -- a sale can empty a stack, a purchase can fill the bag.
func _refresh() -> void:
	_entries = _shop.stock() if _mode == Mode.BUY else _shop.sellable()
	_index = clampi(_index, 0, maxi(0, _entries.size() - 1))
	_scroll_to(_index)
	_paint()


## Same rule as the gate menu: from the overworld and nowhere else.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_shop_requested(shop: Shop) -> void:
	if _can_open():
		open(shop)


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	close()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_select(_index - 1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_select(_index + 1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") \
			or event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_set_mode(Mode.SELL if _mode == Mode.BUY else Mode.BUY)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		trade()


func _select(index: int) -> void:
	index = clampi(index, 0, maxi(0, _entries.size() - 1))
	if index == _index:
		return
	_index = index
	_news = ""
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


func _on_row_input(event: InputEvent, row: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			if _top + row < _entries.size():
				_select(_top + row)
				trade()
		MOUSE_BUTTON_WHEEL_UP:
			_select(_index - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_select(_index + 1)


# --- drawing ---------------------------------------------------------------

func _paint() -> void:
	if _shop == null:
		return
	_purse.text = "%d col" % GameState.col()
	_tabs.text = "> Buy <    Sell" if _mode == Mode.BUY else "  Buy    > Sell <"
	for i in _row_nodes.size():
		var row := _row_nodes[i]
		var item_name := row.get_child(0) as Label
		var price := row.get_child(1) as Label
		var entry := _top + i
		if entry >= _entries.size():
			item_name.text = " " if entry > 0 or i > 0 else _empty_line()
			item_name.add_theme_color_override(&"font_color", UiPalette.LOCKED)
			price.text = ""
			continue
		var item := _item_at(entry)
		var refused := _mode == Mode.BUY and not _shop.refusal(item).is_empty()
		var tone := UiPalette.LOCKED if refused else item.rarity_color()
		item_name.add_theme_color_override(&"font_color", tone)
		price.add_theme_color_override(&"font_color", UiPalette.LOCKED if refused else UiPalette.TEXT)
		var label := item.label()
		if _mode == Mode.SELL:
			var count := Inventory.count(item.id)
			if count > 1:
				label = "%s x%d" % [label, count]
		item_name.text = "%s %s" % [">" if entry == _index else " ", label]
		price.text = str(item.price if _mode == Mode.BUY else item.sell_price())

	var above := _top
	var below := maxi(0, _entries.size() - _top - ROWS_SHOWN)
	var more := PackedStringArray()
	if above > 0:
		more.append("^ %d more" % above)
	if below > 0:
		more.append("v %d more" % below)
	_more.text = "   ".join(more) if not more.is_empty() else " "
	_detail.text = _detail_line()


func _item_at(entry: int) -> Item:
	var value: Variant = _entries[entry]
	return value.item if value is ItemStack else value


func _empty_line() -> String:
	return "  Nothing on the shelf yet." if _mode == Mode.BUY else "  Nothing you carry is worth selling."


## The trade just made; else why the selected row is refused; else what it does.
func _detail_line() -> String:
	if not _news.is_empty():
		return _news
	var item := selected_item()
	if item == null:
		return " "
	if _mode == Mode.BUY:
		var why := _shop.refusal(item)
		if not why.is_empty():
			return why
	var what := item.summary()
	return what if not what.is_empty() else item.kind_name()
