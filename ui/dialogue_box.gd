extends CanvasLayer
## The conversation box: typewriter text, speaker, portrait, choice menu.
##
## Purely a view. It never decides what comes next -- it draws whatever
## [code]DialogueRunner[/code] announces and reports the player's input back
## through [code]advance()[/code] / [code]choose()[/code]. Swapping this scene for
## a fancier one (or none at all, as the headless tests do) changes nothing about
## how dialogue runs.
##
## The box is the pack's paper, so everything written on it is ink
## ([code]UiPalette.INK*[/code]), not the light text the wooden panels use.

const CHARS_PER_SECOND := 45.0
## The most face the frame holds, in 320x180 units. A portrait is drawn at its own
## size, or halved until it fits: at the 4x window half a texel is still two whole
## screen pixels, where any other fraction draws some texels wider than others.
## The pack's 38 px facesets land at 19.
const FACE_ROOM := 24.0

var _choices: Array[DialogueChoice] = []
var _selected := 0
## Choices arrive with their line but are held back until the text finishes
## typing, so the menu does not appear before the question does.
var _choices_pending := false
var _typing: Tween = null

@onready var _box: Control = $Box
@onready var _portrait: Control = $Box/Row/Portrait
@onready var _face: TextureRect = $Box/Row/Portrait/Face
@onready var _speaker_tag: Control = $Speaker
@onready var _speaker: Label = $Speaker/Label
@onready var _text: Label = $Box/Row/Text
@onready var _continue: Control = $Box/Row/Continue
@onready var _menu: Control = $Choices
@onready var _list: VBoxContainer = $Choices/List


func _ready() -> void:
	_box.hide()
	_speaker_tag.hide()
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
	_speaker_tag.visible = not speaker.is_empty()
	UiLayout.shrink_wrap(_speaker_tag)
	_face.texture = portrait
	_portrait.visible = portrait != null
	if portrait != null:
		_face.custom_minimum_size = _face_size(portrait)
	# Hidden by alpha rather than visibility, so the text column doesn't widen
	# and re-wrap the moment the arrow appears.
	_continue.modulate.a = 0.0
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
	_speaker_tag.hide()


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
		_continue.modulate.a = 1.0


func _show_menu() -> void:
	_choices_pending = false
	_continue.modulate.a = 0.0
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()

	_selected = -1
	for i in _choices.size():
		var row := Label.new()
		row.theme_type_variation = &"InkLabel"
		_list.add_child(row)
		if _selected < 0 and _choices[i].is_unlocked():
			_selected = i

	_selected = maxi(_selected, 0)
	_paint_selection()
	_menu.show()
	UiLayout.shrink_wrap(_menu)


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
		var color := UiPalette.INK
		if not choice.is_unlocked():
			color = UiPalette.INK_LOCKED
		elif i == _selected:
			color = UiPalette.INK_SELECTED
		row.add_theme_color_override(&"font_color", color)
		var cursor := "> " if i == _selected else "  "
		row.text = cursor + choice.label()


static func _face_size(texture: Texture2D) -> Vector2:
	var size := texture.get_size()
	while maxf(size.x, size.y) > FACE_ROOM:
		size *= 0.5
	return size
