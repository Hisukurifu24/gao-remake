extends CanvasLayer
## The conversation box: typewriter text, speaker, portrait, choice menu.
##
## Purely a view. It never decides what comes next -- it draws whatever
## [code]DialogueRunner[/code] announces and reports the player's input back
## through [code]advance()[/code] / [code]choose()[/code]. Swapping this scene for
## a fancier one (or none at all, as the headless tests do) changes nothing about
## how dialogue runs.

const CHARS_PER_SECOND := 45.0

const COLOR_CHOICE := Color(0.76, 0.79, 0.88)
const COLOR_SELECTED := Color(1.0, 0.94, 0.7)
const COLOR_LOCKED := Color(0.44, 0.45, 0.52)

var _choices: Array[DialogueChoice] = []
var _selected := 0
## Choices arrive with their line but are held back until the text finishes
## typing, so the menu does not appear before the question does.
var _choices_pending := false
var _typing: Tween = null

@onready var _box: Control = $Box
@onready var _portrait: TextureRect = $Box/Margin/Row/Portrait
@onready var _speaker: Label = $Box/Margin/Row/Lines/Speaker
@onready var _text: Label = $Box/Margin/Row/Lines/Text
@onready var _continue: Label = $Box/Margin/Row/Continue
@onready var _menu: Control = $Choices
@onready var _list: VBoxContainer = $Choices/Margin/List


func _ready() -> void:
	_box.hide()
	_menu.hide()
	DialogueRunner.line_shown.connect(_on_line_shown)
	DialogueRunner.choices_shown.connect(_on_choices_shown)
	DialogueRunner.closed.connect(_on_closed)


func _unhandled_input(event: InputEvent) -> void:
	if not _box.visible:
		return

	if _menu.visible:
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			get_viewport().set_input_as_handled()
			_move_selection(-1)
		elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			get_viewport().set_input_as_handled()
			_move_selection(1)
		elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
			get_viewport().set_input_as_handled()
			DialogueRunner.choose(_selected)
		return

	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		# First press completes the typewriter, the next one moves on.
		if _is_typing():
			_finish_typing()
		else:
			DialogueRunner.advance()


func _on_line_shown(speaker: String, text: String, portrait: Texture2D) -> void:
	_hide_menu()
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_continue.hide()
	_box.show()

	_text.text = text
	_text.visible_ratio = 0.0
	if _typing != null:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, text.length() / CHARS_PER_SECOND)
	_typing.finished.connect(_on_typing_finished)


func _on_choices_shown(choices: Array[DialogueChoice]) -> void:
	_choices = choices
	_choices_pending = true
	if not _is_typing():
		_show_menu()


func _on_closed() -> void:
	if _typing != null:
		_typing.kill()
		_typing = null
	_hide_menu()
	_box.hide()


func _is_typing() -> bool:
	return _typing != null and _typing.is_running()


func _finish_typing() -> void:
	_typing.kill()
	_typing = null
	_text.visible_ratio = 1.0
	_on_typing_finished()


func _on_typing_finished() -> void:
	if _choices_pending:
		_show_menu()
	else:
		_continue.show()


func _show_menu() -> void:
	_choices_pending = false
	_continue.hide()
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()

	_selected = -1
	for i in _choices.size():
		var row := Label.new()
		row.add_theme_font_size_override(&"font_size", 12)
		_list.add_child(row)
		if _selected < 0 and _choices[i].is_unlocked():
			_selected = i

	_selected = maxi(_selected, 0)
	_paint_selection()
	_menu.show()


func _hide_menu() -> void:
	_choices = []
	_choices_pending = false
	_menu.hide()


## Steps to the next selectable choice, skipping locked ones and wrapping.
func _move_selection(step: int) -> void:
	var count := _choices.size()
	if count == 0:
		return
	for i in range(1, count + 1):
		var candidate := (_selected + step * i + count * count) % count
		if _choices[candidate].is_unlocked():
			_selected = candidate
			break
	_paint_selection()


func _paint_selection() -> void:
	for i in _list.get_child_count():
		var row := _list.get_child(i) as Label
		var choice := _choices[i]
		var color := COLOR_CHOICE
		if not choice.is_unlocked():
			color = COLOR_LOCKED
		elif i == _selected:
			color = COLOR_SELECTED
		row.add_theme_color_override(&"font_color", color)
		var cursor := "> " if i == _selected else "  "
		row.text = cursor + choice.label()
