extends CanvasLayer
## The journal: what has been asked of the player, and how far along it is.
##
## Purely a view, exactly like [code]ui/inventory_screen.gd[/code]: it reads
## [QuestLog] and calls [method QuestLog.track] back. It decides nothing, which is
## why [code]test/quest_test.tscn[/code] can run the whole system with this scene
## never instantiated.
##
## One cursor over one list -- live quests first (ready ones at the top, because
## those are the ones with something to do about them), finished ones below. The
## mouse drives that same cursor rather than a second one: hovering a row selects
## it, so the detail panel follows the pointer and there is no "moused-over" state
## to keep in step with the keyboard's.

## [b]Two cues, two meanings, and they never share one.[/b] The [code]>[/code]
## cursor is where the player is -- the same cue the dialogue menu uses -- and
## colour plus a glyph is what the quest *is*. Painting the selected row amber as
## well as the ready one made two rows identical and neither of them the answer.
const COLOR_TEXT := Color(0.82, 0.85, 0.92)
const COLOR_DIM := Color(0.55, 0.57, 0.66)
const COLOR_DONE := Color(0.52, 0.84, 0.56)
const COLOR_READY := Color(1.0, 0.86, 0.45)
const COLOR_TRACKED := Color(0.78, 0.72, 0.98)

var _open := false
var _index := 0
## The list as it was last drawn: quest ids, live ones first. Held so the cursor
## indexes something stable even if a signal repaints mid-frame.
var _entries: Array[StringName] = []
## The row Labels for [member _entries], rebuilt only when the list itself
## changes. Moving the cursor repaints them instead: a row that is freed and
## rebuilt under the pointer fires [signal Control.mouse_entered] again, and
## since hovering is what moves the cursor, that is a loop.
var _row_nodes: Array[Label] = []

@onready var _rows: VBoxContainer = $List/Margin/Column/Rows
@onready var _empty: Label = $List/Margin/Column/Empty
@onready var _counts: Label = $Counts
@onready var _name: Label = $Detail/Margin/Rows/Name
@onready var _giver: Label = $Detail/Margin/Rows/Giver
@onready var _summary: Label = $Detail/Margin/Rows/Summary
@onready var _objective_header: Label = $Detail/Margin/Rows/ObjectiveHeader
@onready var _objectives: VBoxContainer = $Detail/Margin/Rows/Objectives
@onready var _reward: Label = $Detail/Margin/Rows/Reward


func _ready() -> void:
	visible = false
	EventBus.quest_log_changed.connect(_on_quest_log_changed)
	CombatManager.combat_began.connect(_on_combat_began)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_index = 0
	GameState.push_input_lock()
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	GameState.pop_input_lock()


## Opens from the overworld and nowhere else: not mid-conversation, not mid-fight,
## not during a map fade. Same rule as the bag, and for the same reason.
func _can_open() -> bool:
	return not GameState.is_input_locked() \
			and not DialogueRunner.is_running() \
			and not CombatManager.is_running()


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	close()


func _on_quest_log_changed() -> void:
	if _open:
		_refresh()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed(&"journal") and _can_open():
			get_viewport().set_input_as_handled()
			open()
		return

	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"journal") or event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_track_selected()


func _move(step: int) -> void:
	if _entries.is_empty():
		return
	_select(clampi(_index + step, 0, _entries.size() - 1))


## Moves the cursor without touching the list. The keyboard and the mouse both
## come through here, which is what keeps them from being two cursors.
func _select(index: int) -> void:
	if index == _index:
		return
	_index = index
	_paint_rows()
	_draw_detail()


## Points the tracker at whatever the cursor is on. [method QuestLog.track] refuses
## anything that is not a live quest, so a finished one simply does nothing here --
## the greyed row is the explanation.
func _track_selected() -> void:
	if _selected_id() == &"":
		return
	QuestLog.track(_selected_id())


func _selected_id() -> StringName:
	if _index < 0 or _index >= _entries.size():
		return &""
	return _entries[_index]


# --- drawing ---------------------------------------------------------------

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


func _build_rows() -> void:
	for row in _row_nodes:
		_rows.remove_child(row)
		row.queue_free()
	_row_nodes.clear()

	for i in _entries.size():
		var row := Label.new()
		row.add_theme_font_size_override(&"font_size", 11)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		# Hovering a row *is* selecting it, so the pointer is always safe and the
		# detail panel follows it without a second cursor to keep in step.
		row.mouse_entered.connect(_select.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		_rows.add_child(row)
		_row_nodes.append(row)


func _paint_rows() -> void:
	var tracked := QuestLog.tracked()
	var tracked_id: StringName = tracked.quest.id if tracked != null else &""

	for i in _row_nodes.size():
		var id := _entries[i]
		var quest := QuestLibrary.get_quest(id)
		var row := _row_nodes[i]

		var color := COLOR_TEXT
		var mark := " "
		match QuestLog.state_of(id):
			QuestLog.State.READY:
				color = COLOR_READY
				mark = "!"
			QuestLog.State.COMPLETED:
				color = COLOR_DIM
				mark = "x"
			_:
				if id == tracked_id:
					color = COLOR_TRACKED
					mark = "*"
		row.add_theme_color_override(&"font_color", color)

		var progress := QuestLog.progress_for(id)
		var tail := "" if progress == null else "   %s" % progress.summary()
		row.text = "%s %s %s%s" % [
			">" if i == _index else " ", mark,
			quest.label() if quest != null else String(id), tail]


func _draw_detail() -> void:
	for row in _objectives.get_children():
		_objectives.remove_child(row)
		row.queue_free()

	var id := _selected_id()
	var quest := QuestLibrary.get_quest(id) if id != &"" else null
	if quest == null:
		_name.text = "--"
		_giver.text = " "
		_summary.text = "Talk to the people standing around and somebody will want something."
		_objective_header.hide()
		_reward.text = " "
		return

	_name.text = quest.label()
	_name.add_theme_color_override(&"font_color",
			COLOR_DONE if QuestLog.is_completed(id) else COLOR_TEXT)
	_giver.text = _state_line(id, quest)
	_summary.text = quest.summary
	_objective_header.show()

	var progress := QuestLog.progress_for(id)
	for objective in quest.listed_objectives():
		var row := Label.new()
		row.add_theme_font_size_override(&"font_size", 10)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objectives.add_child(row)
		# A finished quest keeps no progress object -- everything in it is done by
		# definition, which is why this reads the log's verdict and not a counter.
		var current := objective.required if progress == null else progress.of(objective)
		var done := current >= objective.required
		row.add_theme_color_override(&"font_color", COLOR_DONE if done else COLOR_TEXT)
		row.text = "%s %s" % ["x" if done else "-", objective.progress_text(current)]

	var rewards := quest.reward_summary()
	_reward.text = "" if rewards.is_empty() else "Reward: %s" % rewards


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


## Clicking a row is the [code]Confirm[/code] key: it selects and tracks in one
## press, the same shorthand the bag gives a double-click.
func _on_row_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_select(index)
	_track_selected()
