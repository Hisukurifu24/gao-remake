extends CanvasLayer
## A smith's forge: pick a piece of gear, put materials in, and see if it takes.
##
## A view like the shop screen: [Smith] decides the cost, the materials and the
## odds, [Inventory] holds the gear and does the enhancing; this only asks which
## piece and how many extra materials. It opens on [signal EventBus.forge_requested]
## -- from Nezha's menu, so it waits for the conversation to close -- and holds the
## input lock while open.
##
## One cursor over the player's gear, worn first. Left and right put extra
## materials in or take them out, each one [constant Smith.EXTRA_ODDS] percent. A
## piece the forge would refuse is drawn locked and the detail line says why,
## asked of [method Smith.refusal] -- the rule [method Smith.attempt] enforces.

const ROWS_SHOWN := 6

var _open := false
var _smith: Smith = null
var _index := 0
var _top := 0
var _extra := 0
var _entries: Array[ItemStack] = []
var _row_nodes: Array[HBoxContainer] = []
## The last attempt, said once on the detail line until the cursor moves.
var _news := ""
var _news_good := true
## Seconds until E works: the press that closed Nezha's box is still being
## mashed when the forge comes up, and E here spends Col.
var _deaf_until := 0.0

@onready var _title: Label = $Panel/Column/Header/Title
@onready var _purse: Label = $Panel/Column/Header/Purse
@onready var _greeting: Label = $Panel/Column/Greeting
@onready var _rows: VBoxContainer = $Panel/Column/Rows
@onready var _more: Label = $Panel/Column/More
@onready var _need: Label = $Panel/Column/Need
@onready var _detail: Label = $Panel/Column/Detail


func _ready() -> void:
	visible = false
	EventBus.forge_requested.connect(_on_forge_requested)
	EventBus.col_changed.connect(func(_col: int) -> void:
		if _open:
			_paint())
	CombatManager.combat_began.connect(func(_e: Encounter, _p: Array[Combatant],
			_en: Array[Combatant]) -> void: close())
	for i in ROWS_SHOWN:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override(&"separation", 4)
		var piece := Label.new()
		piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece.clip_text = true
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var price := Label.new()
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(piece)
		row.add_child(price)
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		_rows.add_child(row)
		_row_nodes.append(row)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


func open(smith: Smith) -> void:
	if _open or smith == null:
		return
	_open = true
	visible = true
	_smith = smith
	_title.text = smith.label()
	_greeting.text = "%s: \"%s\"" % [smith.keeper, smith.greeting] if not smith.keeper.is_empty() \
			else smith.greeting
	GameState.push_input_lock()
	_deaf_until = _seconds() + Player.INTERACT_GRACE
	_index = 0
	_top = 0
	_extra = 0
	_news = ""
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_smith = null
	GameState.pop_input_lock()


## The selected piece, or null.
func selected() -> ItemStack:
	return _entries[_index] if _index >= 0 and _index < _entries.size() else null


## Extra materials going in on the next attempt.
func extra() -> int:
	return _extra


func set_extra(value: int) -> void:
	var stack := selected()
	_extra = clampi(value, 0, Smith.max_extra(stack) if stack != null else 0)
	_news = ""
	_paint()


## Works the selected piece once. Returns what happened.
func work(roll := -1.0) -> Smith.Outcome:
	var stack := selected()
	if stack == null:
		return Smith.Outcome.REFUSED
	var outcome := Smith.attempt(stack, _extra, roll)
	match outcome:
		Smith.Outcome.SUCCEEDED:
			_news = "It took: %s!" % stack.item.label_at(stack.plus)
			_news_good = true
		Smith.Outcome.FAILED:
			_news = "It didn't take. Still +%d." % stack.plus
			_news_good = false
	_refresh()
	return outcome


## Re-reads the gear -- a success changes a row, a failure the bag's materials.
func _refresh() -> void:
	_entries = Inventory.gear()
	_index = clampi(_index, 0, maxi(0, _entries.size() - 1))
	var stack := selected()
	_extra = clampi(_extra, 0, Smith.max_extra(stack) if stack != null else 0)
	_scroll_to(_index)
	_paint()


## Same rule as the shop: from the overworld and nowhere else.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_forge_requested(smith: Smith) -> void:
	if DialogueRunner.is_running():
		# Asked for from a conversation's menu: the box is still up, holding the
		# lock. Open once it has closed.
		await EventBus.dialogue_finished
		await get_tree().process_frame
	if _can_open():
		open(smith)


func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


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
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		set_extra(_extra - 1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		set_extra(_extra + 1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		if _seconds() >= _deaf_until:
			work()


func _select(index: int) -> void:
	index = clampi(index, 0, maxi(0, _entries.size() - 1))
	if index == _index:
		return
	_index = index
	_extra = 0
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
				work()
		MOUSE_BUTTON_WHEEL_UP:
			_select(_index - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_select(_index + 1)


# --- drawing ---------------------------------------------------------------

func _paint() -> void:
	if _smith == null:
		return
	_purse.text = "%d col" % GameState.col()
	for i in _row_nodes.size():
		var row := _row_nodes[i]
		var piece := row.get_child(0) as Label
		var price := row.get_child(1) as Label
		var entry := _top + i
		if entry >= _entries.size():
			piece.text = "  You have no gear to work on." if entry == 0 else " "
			piece.add_theme_color_override(&"font_color", UiPalette.LOCKED)
			price.text = ""
			continue
		var stack := _entries[entry]
		var maxed := stack.plus >= stack.item.max_plus()
		var refused := not Smith.refusal(stack, 0).is_empty()
		var tone := UiPalette.LOCKED if refused else stack.item.rarity_color()
		piece.add_theme_color_override(&"font_color", tone)
		price.add_theme_color_override(&"font_color", UiPalette.LOCKED if refused else UiPalette.TEXT)
		var worn := Inventory.worn(stack.item.slot()) == stack
		piece.text = "%s %s%s" % [">" if entry == _index else " ", stack.item.label_at(stack.plus),
				" (worn)" if worn else ""]
		price.text = "max" if maxed else str(Smith.cost(stack))

	var above := _top
	var below := maxi(0, _entries.size() - _top - ROWS_SHOWN)
	var more := PackedStringArray()
	if above > 0:
		more.append("^ %d more" % above)
	if below > 0:
		more.append("v %d more" % below)
	_more.text = "   ".join(more) if not more.is_empty() else " "
	_need.text = _need_line()
	_detail.text = _detail_line()
	_detail.add_theme_color_override(&"font_color", _detail_color())


## What the attempt takes: which materials, and the extras going in.
func _need_line() -> String:
	var stack := selected()
	if stack == null or stack.plus >= stack.item.max_plus():
		return " "
	var parts := PackedStringArray()
	var spend := Smith.materials_for(stack, _extra)
	for id in spend:
		parts.append("%dx %s" % [spend[id], ItemLibrary.get_item(id).label()])
	if parts.is_empty():
		var rank := Item.RARITY_NAMES[Smith.tier(stack)].to_lower()
		return "Wants %d %s materials" % [Smith.materials_needed(stack), rank]
	var line := ", ".join(parts)
	return "%s  < +%d >" % [line, _extra] if Smith.max_extra(stack) > 0 or _extra > 0 else line


## The attempt just made; else why the piece is refused; else what a success does.
func _detail_line() -> String:
	if not _news.is_empty():
		return _news
	var stack := selected()
	if stack == null:
		return " "
	var why := Smith.refusal(stack, _extra)
	if not why.is_empty():
		return why
	var stat := stack.item.enhanced_stat()
	var short: String = {&"attack": "ATK", &"defense": "DEF", &"max_hp": "HP"}.get(stat, "")
	var now := stack.item.base_bonus(stat) + stack.item.plus_bonus(stat, stack.plus)
	var then := now + stack.item.plus_step()
	return "+%d > +%d   %s %d > %d   %d%%" % [stack.plus, stack.plus + 1, short, now, then,
			Smith.odds(stack, _extra)]


func _detail_color() -> Color:
	if not _news.is_empty():
		return UiPalette.GOOD if _news_good else UiPalette.BAD
	var stack := selected()
	if stack != null and not Smith.refusal(stack, _extra).is_empty():
		return UiPalette.LOCKED
	return UiPalette.TEXT
