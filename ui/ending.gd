class_name Ending
extends CanvasLayer
## The game cleared: the world goes white, the epilogue, the credits, the title.
##
## Started by [BossGate] once Hisukurifu's last bar is gone, he has said his
## piece ([method FinalBoss.farewell]), broken into light, and the system has
## announced it ([method FinalBoss.announcement]); from then on it runs itself -- the
## gate is on floor 100's map, which this takes the player off. Under the white
## the player is moved to the Town of Beginnings, so the save written on the way
## out (and Continue, later) puts them back there with every floor behind them:
## the castle is theirs to walk. A marathon has no save, and ends here.
##
## Built in code: a sheet of light, a line of text and a column of credits. Above
## the router's fade (128), so moving maps under it never shows.

## Over everything else, the router's fade included.
const LAYER := 129
const COVER_TIME := 2.4
const LINE_FADE := 0.8
## How long each epilogue line holds before the next, unless a key moves it on.
const LINE_HOLD := 5.0
## The credits' climb, in 640x360 units a second.
const ROLL_SPEED := 22.0
const LAST_HOLD := 6.0
const CLEAR_TIME := 1.2
## The title's own credits, rolled.
const TITLE := preload("res://ui/title_screen.gd")

signal _pressed

## Every duration's multiplier. The save test runs the whole ending at a
## hundredth of its pace.
static var pace := 1.0

var _sheet: ColorRect
var _line: Label
var _roll: VBoxContainer
var _waiting := false
## Counts holds, so a hold cut short by a key doesn't end the next one when its
## timer runs out.
var _beat := 0


## Puts an ending up over [param tree] and runs it to the title. Fire and forget.
static func begin(tree: SceneTree) -> void:
	var ending := Ending.new()
	tree.root.add_child(ending)
	ending._run()


func _ready() -> void:
	layer = LAYER
	name = "Ending"
	_sheet = ColorRect.new()
	_sheet.color = Color(UiPalette.FIELD, 0.0)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)

	_line = Label.new()
	_line.theme_type_variation = &"InkLabel"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_line.offset_left = 120.0
	_line.offset_right = -120.0
	_line.modulate.a = 0.0
	add_child(_line)

	_roll = VBoxContainer.new()
	_roll.add_theme_constant_override(&"separation", 3)
	_roll.alignment = BoxContainer.ALIGNMENT_CENTER
	_roll.position = Vector2(170.0, 360.0)
	_roll.custom_minimum_size = Vector2(300.0, 0.0)
	_roll.visible = false
	add_child(_roll)
	for entry: Array in TITLE.CREDITS:
		_credit(entry[0], entry[1], &"HeaderLabel")
	_credit("", "", &"")
	_credit("And you", GameState.player_name, &"HeaderLabel")


func _credit(what: String, who: String, style: StringName) -> void:
	for text: String in [what, who]:
		var label := Label.new()
		label.text = text
		label.theme_type_variation = style if text == what else &"InkLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(300.0, 0.0)
		_roll.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if not _waiting or event.is_echo():
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept") \
			or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_pressed.emit()


func _run() -> void:
	GameState.push_input_lock()
	EventBus.screens_close_requested.emit()
	Audio.play(&"game_clear")
	await _tween(_sheet, "color:a", 1.0, COVER_TIME * pace)

	# Home, under the light: the save on the way out is a save in the town.
	await SceneRouter.enter_floor(1, &"gate", 0.0)
	Audio.play_over(&"ending")

	for text in FinalBoss.epilogue():
		_line.text = text
		await _tween(_line, "modulate:a", 1.0, LINE_FADE * pace)
		await _hold(LINE_HOLD * pace)
		await _tween(_line, "modulate:a", 0.0, LINE_FADE * pace)

	_roll.visible = true
	var climb := _roll.position.y + _roll.size.y + 40.0
	var rolling := create_tween()
	rolling.tween_property(_roll, "position:y", -_roll.size.y - 40.0, climb / ROLL_SPEED * pace)
	await rolling.finished

	_line.text = "Thank you for playing."
	await _tween(_line, "modulate:a", 1.0, LINE_FADE * pace)
	await _hold(LAST_HOLD * pace)

	GameState.pop_input_lock()
	# Saved here rather than by quit_to_title(), so the notice can say whether it
	# was: a run with no slot (a debug start) clears the game and keeps nothing,
	# and promising Continue would send the player back to a save from before it.
	var who := GameState.player_name
	var notice := "%s cleared the game. Continue to go back to Aincrad." % who
	if GameState.mode == GameState.Mode.MARATHON:
		notice = "%s cleared the game in a single sitting. The marathon is over." % who
	elif SaveGame.slot <= 0:
		notice = "%s cleared the game -- in a run with no save slot, so none of it was kept." % who
	elif not SaveGame.save_game(SaveGame.slot):
		notice = "%s cleared the game, but it could not be saved." % who
	await SaveGame.quit_to_title(notice, false)
	var fade := create_tween().set_parallel()
	fade.tween_property(_sheet, "color:a", 0.0, CLEAR_TIME * pace)
	fade.tween_property(_line, "modulate:a", 0.0, CLEAR_TIME * pace)
	await fade.finished
	queue_free()


## Waits [param seconds], or until a key is pressed.
func _hold(seconds: float) -> void:
	_beat += 1
	var mine := _beat
	_waiting = true
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if _beat == mine:
			_pressed.emit())
	await _pressed
	_waiting = false
	_beat += 1


func _tween(node: Object, property: String, to: Variant, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, property, to, seconds)
	await tween.finished
