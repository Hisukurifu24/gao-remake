extends CanvasLayer
## The tracked quest, in the corner of the screen.
##
## The quest system's only always-on surface. Without it a quest is invisible
## between the conversation that gave it and the journal the player has to
## remember to open -- which is the same reason the HP bar is on screen and not
## behind a menu.
##
## Purely a view, like everything else in [code]ui/[/code]: it reads
## [method QuestLog.tracked] and draws it. It never decides which quest is
## tracked; [QuestLog] owns that, so the journal and this agree without either
## knowing about the other.
##
## It steps aside for anything that takes over the screen, on the same signals
## [code]ui/hud.gd[/code] uses. The journal and the bag do not need a signal --
## both draw an opaque backdrop on a higher [member CanvasLayer.layer].

## How long an "accepted" / "ready" / "completed" line stays up. Timed from when
## it is *shown*, which for a quest taken mid-conversation is when the box closes
## -- a notice nobody could see should not be spending its own clock.
const NOTICE_SECONDS := 4.0

var _notice_timer: Timer

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Rows/Title
@onready var _objectives: VBoxContainer = $Panel/Rows/Objectives
@onready var _notice: Label = $Panel/Rows/Notice


func _ready() -> void:
	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = NOTICE_SECONDS
	_notice_timer.timeout.connect(_clear_notice)
	_notice.add_theme_color_override(&"font_color", UiPalette.READY)
	add_child(_notice_timer)

	EventBus.quest_log_changed.connect(_refresh)
	EventBus.quest_accepted.connect(_on_quest_accepted)
	EventBus.quest_ready.connect(_on_quest_ready)
	EventBus.quest_completed.connect(_on_quest_completed)
	# Only to know *when* to look again -- what the answer is comes from
	# [method _is_suppressed], which asks the runners directly.
	EventBus.dialogue_started.connect(_on_dialogue_changed)
	EventBus.dialogue_finished.connect(_on_dialogue_changed)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.combat_finished.connect(_on_combat_finished)
	_clear_notice()


func _on_quest_accepted(id: StringName) -> void:
	_show_notice("New quest: %s" % _title_of(id))


func _on_quest_ready(id: StringName) -> void:
	var quest := QuestLibrary.get_quest(id)
	if quest == null or not quest.needs_turn_in:
		return
	if quest.giver.is_empty():
		_show_notice("%s -- ready to report" % quest.label())
	else:
		_show_notice("%s -- report to %s" % [quest.label(), quest.giver])


func _on_quest_completed(id: StringName) -> void:
	_show_notice("Quest complete: %s" % _title_of(id))


func _on_dialogue_changed(_id: StringName) -> void:
	_refresh()


func _on_combat_began(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void:
	_refresh()


func _on_combat_finished(_result: CombatResult) -> void:
	_refresh()


## Whether something else owns the screen. Asked live rather than tracked in a
## bool, exactly as [code]ui/hud.gd[/code] does it: both runners set their state
## before they emit, so this is never a frame behind, and there is no second copy
## of "is a fight on" to drift out of step with the first.
##
## The notice is *suppressed*, not lost -- accepting a quest always happens inside
## a conversation, so a notice that spent its clock behind the box would never be
## seen at all.
func _is_suppressed() -> bool:
	return DialogueRunner.is_running() or CombatManager.is_running()


## Repaints from scratch. Cheap enough at one quest and a handful of objectives,
## and it means there is no partial-update path that can disagree with the log.
func _refresh() -> void:
	if _is_suppressed():
		_panel.hide()
		return

	var progress := QuestLog.tracked()
	var notice_up := not _notice.text.strip_edges().is_empty()
	if notice_up and _notice_timer.is_stopped():
		_notice_timer.start()
	if progress == null:
		# A notice with no quest behind it still has to be readable -- "Quest
		# complete" arrives exactly when there is nothing left to track.
		_panel.visible = notice_up
		_title.text = ""
		_title.visible = false
		_clear_objectives()
		return

	_panel.show()
	_title.visible = true
	_title.text = progress.quest.label()
	_title.add_theme_color_override(&"font_color",
			UiPalette.READY if progress.is_complete() else UiPalette.HEADER)

	_clear_objectives()
	for objective in progress.quest.listed_objectives():
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var done := progress.is_objective_complete(objective)
		row.add_theme_color_override(&"font_color", UiPalette.DONE if done else UiPalette.DIM)
		row.text = "%s %s" % [
			"x" if done else "-", objective.progress_text(progress.of(objective))]
		_objectives.add_child(row)


func _clear_objectives() -> void:
	for row in _objectives.get_children():
		_objectives.remove_child(row)
		row.queue_free()


## The timer is started by [method _refresh] rather than here, so a notice raised
## behind a conversation gets its four seconds once the box is out of the way.
func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.show()
	_notice_timer.stop()
	_refresh()


func _clear_notice() -> void:
	_notice.text = " "
	_notice.hide()
	_refresh()


func _title_of(id: StringName) -> String:
	var quest := QuestLibrary.get_quest(id)
	return quest.label() if quest != null else String(id)
