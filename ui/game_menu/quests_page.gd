extends MenuPage
## Quests: what has been asked of the player, and how far along it is -- the
## journal.
##
## Purely a view: it reads [QuestLog] and calls [method QuestLog.track] back.
## [code]test/quest_test.tscn[/code] runs the whole system with this page never built.
##
## One cursor over one list -- live quests first (ready ones at the top, because
## those are the ones with something to do about them), finished ones below. The
## mouse drives that same cursor: hovering a row selects it.
##
## [b]Two cues, two meanings, and they never share one.[/b] The pack's arrow is
## where the player is -- the same cursor as every list -- and colour plus a glyph
## is what the quest *is*. The colours are [UiPalette]'s, shared with the tracker.

## The most of a quest's summary the page has room for; the longest shipped
## takes nine.
const SUMMARY_LINES := 9
const COIN := "res://assets/ninja_adventure/Items/Treasure/GoldCoin.png"

var _index := 0
## The list as it was last drawn: quest ids, live ones first.
var _entries: Array[StringName] = []
## Rows for [member _entries], rebuilt only when the list itself changes. Moving
## the cursor repaints them instead: a row rebuilt under the pointer fires
## [signal Control.mouse_entered] again, and hovering is what moves the cursor.
var _rows: Array[HBoxContainer] = []

var _list: VBoxContainer
var _empty: Label
var _counts: Label
var _name: Label
var _giver: Label
var _summary: Label
var _objectives: VBoxContainer
var _reward_row: HBoxContainer
var _reward: Label


func title() -> String:
	return "Quests"


func _init() -> void:
	var row := box(false, 8, self)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)

	var left := panel(&"InsetPanel", row)
	# Narrow, so the quest itself gets the room -- a long title wraps -- but no
	# narrower than the legend.
	left.custom_minimum_size = Vector2(220, 0)
	var column := box(true, 4, left)
	_counts = label("", &"HintLabel", column)
	_list = box(true, 4, column) as VBoxContainer
	_empty = label("Nobody has asked you for anything yet.", &"HintLabel", column)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spacer(column)
	label("* tracked  ! ready  x done", &"HintLabel", column)

	var right := panel(&"InsetPanel", row)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := box(true, 2, right)
	# Who it is for sits on the title's row when both fit -- a line the summary
	# can have instead -- and drops under it when they don't.
	var heading := HFlowContainer.new()
	heading.add_theme_constant_override(&"h_separation", 12)
	heading.add_theme_constant_override(&"v_separation", 2)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(heading)
	_name = label("", &"HeaderLabel", heading)
	_giver = label("", &"HintLabel", heading)
	_giver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_giver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary = label("", &"", detail)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.max_lines_visible = SUMMARY_LINES
	# The objectives' own glyphs mark them; a gap, not a heading, sets them off
	# -- the heading's line is the summary's eighth.
	_objectives = box(true, 0, detail) as VBoxContainer
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(gap)
	detail.move_child(gap, _objectives.get_index())
	spacer(detail)
	# The purse's coin says "reward", in the width the word took.
	_reward_row = box(false, 6, detail)
	var coin := icon_rect(load(COIN) as Texture2D, Vector2(7, 15), _reward_row)
	coin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_reward = label("", &"", _reward_row)
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward.add_theme_color_override(&"font_color", UiPalette.READY)


func _ready() -> void:
	EventBus.quest_log_changed.connect(func() -> void:
		if visible:
			_refresh())


func shown() -> void:
	_index = 0
	_refresh()


func handle(event: InputEvent) -> bool:
	if is_up(event):
		_select(_index - 1)
	elif is_down(event):
		_select(_index + 1)
	elif is_confirm(event):
		_track_selected()
	else:
		return false
	return true


func hints() -> Array:
	return [["Space", "track"]] if not _entries.is_empty() else []


## Draws [param id]'s page whatever the cursor is on, for tests -- measure it
## with [method fits] once it has been laid out.
func show_quest(id: StringName) -> void:
	_draw_quest(id)


## Whether the page shows every line of the summary without growing taller
## than the window.
func fits() -> bool:
	var row := get_child(0) as Control
	return _summary.get_line_count() <= _summary.max_lines_visible \
			and row.get_combined_minimum_size().y <= size.y


## The cursor's row, for tests and tools.
func selected() -> StringName:
	return _selected_id()


## Moves the cursor without touching the list. The keyboard and the mouse both
## come through here, which is what keeps them from being two cursors.
func _select(index: int) -> void:
	if _entries.is_empty():
		return
	index = clampi(index, 0, _entries.size() - 1)
	if index == _index:
		return
	_index = index
	_paint_rows()
	_draw_detail()


## Points the tracker at whatever the cursor is on. [method QuestLog.track] refuses
## anything that is not a live quest, so a finished one simply does nothing.
func _track_selected() -> void:
	if _selected_id() != &"":
		QuestLog.track(_selected_id())


func _selected_id() -> StringName:
	return _entries[_index] if _index >= 0 and _index < _entries.size() else &""


func _refresh() -> void:
	var previous := _entries.duplicate()
	_entries.clear()
	for progress in QuestLog.active_quests():
		_entries.append(progress.quest.id)
	for quest in QuestLog.completed_quests():
		_entries.append(quest.id)
	_index = clampi(_index, 0, maxi(0, _entries.size() - 1))
	_counts.text = "%d active   %d done" % [QuestLog.active_count(), QuestLog.completed_count()]
	_empty.visible = _entries.is_empty()
	if previous != _entries:
		_build_rows()
	_paint_rows()
	_draw_detail()
	hints_changed.emit()


func _build_rows() -> void:
	for row in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()
	for i in _entries.size():
		var row := box(false, 2, _list) as HBoxContainer
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(_select.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		var cursor := icon_rect(MenuList.pointer(), Vector2(13, 15), row)
		cursor.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cursor.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var text := label("", &"", row)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.append(row)


func _paint_rows() -> void:
	var tracked := QuestLog.tracked()
	var tracked_id: StringName = tracked.quest.id if tracked != null else &""
	for i in _rows.size():
		var id := _entries[i]
		var quest := QuestLibrary.get_quest(id)
		var color := UiPalette.TEXT
		var mark := " "
		match QuestLog.state_of(id):
			QuestLog.State.READY:
				color = UiPalette.READY
				mark = "!"
			QuestLog.State.COMPLETED:
				color = UiPalette.DIM
				mark = "x"
			_:
				if id == tracked_id:
					color = UiPalette.TRACKED
					mark = "*"
		(_rows[i].get_child(0) as CanvasItem).modulate.a = 1.0 if i == _index else 0.0
		var text := _rows[i].get_child(1) as Label
		text.add_theme_color_override(&"font_color", color)
		text.text = "%s %s" % [mark, quest.label() if quest != null else String(id)]


func _draw_detail() -> void:
	_draw_quest(_selected_id())


func _draw_quest(id: StringName) -> void:
	for row in _objectives.get_children():
		_objectives.remove_child(row)
		row.queue_free()
	var quest := QuestLibrary.get_quest(id) if id != &"" else null
	if quest == null:
		_name.text = "Journal"
		_giver.text = ""
		_summary.text = "Talk to the people standing around and somebody will want something."
		_reward.text = ""
		_reward_row.visible = false
		return

	_name.text = quest.label()
	_name.add_theme_color_override(&"font_color",
			UiPalette.DONE if QuestLog.is_completed(id) else UiPalette.HEADER)
	_giver.text = _state_line(id, quest)
	_summary.text = quest.summary
	var progress := QuestLog.progress_for(id)
	for objective in quest.listed_objectives():
		var row := label("", &"", _objectives)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A finished quest keeps no progress object -- everything in it is done by
		# definition, which is why this reads the log's verdict and not a counter.
		var current := objective.required if progress == null else progress.of(objective)
		var done := current >= objective.required
		row.add_theme_color_override(&"font_color", UiPalette.DONE if done else UiPalette.TEXT)
		row.text = "%s %s" % ["x" if done else "-", objective.progress_text(current)]
	var rewards := quest.reward_summary()
	_reward.text = rewards
	_reward_row.visible = not rewards.is_empty()


## The line under the title: who wants it and what the log thinks of it.
func _state_line(id: StringName, quest: Quest) -> String:
	var who := "" if quest.giver.is_empty() else quest.giver
	var state := ""
	match QuestLog.state_of(id):
		QuestLog.State.READY:
			state = "ready to hand in" if who.is_empty() else "go back to %s" % who
			who = ""
		QuestLog.State.COMPLETED:
			state = "finished"
		QuestLog.State.ACTIVE:
			state = "in progress"
	if who.is_empty():
		return state
	return "%s -- %s" % [who, state] if not state.is_empty() else who


## Clicking a row is the confirm key: it selects and tracks in one press.
func _on_row_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_select(index)
	_track_selected()
