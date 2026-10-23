extends MenuPage
## System: save, go back to the save, the settings, and back to the title -- with
## the run itself beside them, as its slot shows it.
##
## A view: [SaveGame] says what can be done and does it. A choice that can't be
## made now stays listed and greyed, and the line under the list says why: a
## marathon has no Save, a hardcore game no going back. Every choice that acts
## closes the menu first, so the save it makes is one with nothing open -- the
## only kind [method SaveGame.can_save] allows.

enum Choice { RESUME, SAVE, LOAD, SETTINGS, QUIT }

const MODE_LINES := {
	GameState.Mode.STANDARD: "Standard: save anywhere, and it autosaves as you go.",
	GameState.Mode.HARDCORE: "Hardcore: lose a fight and this save is deleted.",
	GameState.Mode.MARATHON: "Marathon: nothing is ever saved.",
}

## Quit was pressed once on a run that isn't saved; the second press ends it.
var _confirm_quit := false
var _in_settings := false

var _list: MenuList
var _settings: SettingsList
var _detail: Label
var _card: SaveCard
var _unsaved: Label
var _mode: Label


func title() -> String:
	return "System"


func _init() -> void:
	var row := box(false, 12, self)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The one page drawn straight on the window, so it pads itself off the frame.
	row.offset_left = 6.0
	row.offset_right = -6.0

	var left := box(true, 8, row)
	left.custom_minimum_size = Vector2(272, 0)
	_list = MenuList.new()
	_list.chosen.connect(_on_chosen)
	_list.moved.connect(_on_moved)
	left.add_child(_list)
	_settings = SettingsList.new()
	_settings.visible = false
	_settings.back.connect(_leave_settings)
	_settings.moved.connect(func(_at: int) -> void: _paint_detail())
	left.add_child(_settings)
	_detail = label(" ", &"", left)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var right := box(true, 6, row)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label("This run", &"HeaderLabel", right)
	_card = SaveCard.new()
	right.add_child(_card)
	_unsaved = label("", &"HintLabel", right)
	_unsaved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode = label("", &"", right)
	_mode.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func shown() -> void:
	_confirm_quit = false
	_in_settings = false
	_list.visible = true
	_settings.visible = false
	_list.set_rows(_rows())
	_paint_run()
	_paint_detail()


func handle(event: InputEvent) -> bool:
	var menu := _settings if _in_settings else _list
	if is_up(event):
		menu.move(-1)
	elif is_down(event):
		menu.move(1)
	elif is_left(event):
		menu.step(-1)
	elif is_right(event):
		menu.step(1)
	elif is_confirm(event):
		menu.choose()
	else:
		return false
	return true


func back() -> bool:
	if _in_settings:
		_leave_settings()
		return true
	return false


func hints() -> Array:
	if _in_settings:
		return [[["Left", "Right"], "change"], ["Space", "choose"]]
	return [["Space", "choose"]]


## The list the page is showing -- the system rows, or the settings -- for tests.
func list() -> MenuList:
	return _settings if _in_settings else _list


func _rows() -> Array[Dictionary]:
	var unsaved := not SaveGame.why_unsaved().is_empty()
	var quit := "Quit to title" if unsaved else "Save and quit to title"
	if _confirm_quit:
		quit = "Quit -- press again to end the run"
	return [
		{"text": "Resume"},
		{"text": "Save", "enabled": not unsaved},
		{"text": "Back to the last save", "enabled": SaveGame.can_go_back()},
		{"text": "Settings"},
		{"text": quit, "danger": _confirm_quit},
	]


func _paint_run() -> void:
	var slot := SaveGame.slot
	var meta := SaveGame.summary(slot) if slot > 0 else {}
	_card.visible = slot > 0
	if slot > 0:
		_card.show_slot(slot, meta)
	_unsaved.text = SaveGame.why_unsaved()
	_unsaved.visible = not _unsaved.text.is_empty()
	_mode.text = MODE_LINES[GameState.mode]


func _paint_detail() -> void:
	var text := " "
	if _in_settings:
		text = _settings.describe(_settings.index)
	else:
		match _list.index:
			Choice.RESUME:
				text = "Back to the game."
			Choice.SAVE:
				text = SaveGame.why_unsaved() if not SaveGame.why_unsaved().is_empty() \
						else "Into slot %d." % SaveGame.slot
			Choice.LOAD:
				if GameState.mode == GameState.Mode.HARDCORE:
					text = "There is no going back in a hardcore game."
				elif not SaveGame.why_unsaved().is_empty():
					text = "There is no save to go back to."
				else:
					text = "Anything since the last save is lost."
			Choice.SETTINGS:
				text = "The window, the text, the camera."
			Choice.QUIT:
				if not SaveGame.why_unsaved().is_empty():
					text = "This run is never saved: quitting ends it."
				else:
					text = "Saves into slot %d first." % SaveGame.slot
	_detail.text = text
	_detail.add_theme_color_override(&"font_color", UiPalette.BAD if _confirm_quit else UiPalette.DIM)


func _on_moved(at: int) -> void:
	if _confirm_quit and at != Choice.QUIT:
		_confirm_quit = false
		_list.set_rows(_rows(), true)
	_paint_detail()


func _on_chosen(at: int) -> void:
	if not _list.is_enabled(at):
		return
	match at:
		Choice.RESUME:
			menu.call(&"close")
		Choice.SAVE:
			menu.call(&"close")
			SaveGame.save_game(SaveGame.slot)
		Choice.LOAD:
			menu.call(&"close")
			SaveGame.load_slot(SaveGame.slot)
		Choice.SETTINGS:
			_in_settings = true
			_list.visible = false
			_settings.visible = true
			_settings.refresh()
			_settings.select(0)
			_paint_detail()
			hints_changed.emit()
		Choice.QUIT:
			if not SaveGame.why_unsaved().is_empty() and not _confirm_quit:
				_confirm_quit = true
				_list.set_rows(_rows(), true)
				_paint_detail()
				return
			menu.call(&"close")
			SaveGame.quit_to_title()


func _leave_settings() -> void:
	_in_settings = false
	_settings.visible = false
	_list.visible = true
	_list.select(Choice.SETTINGS)
	_paint_detail()
	hints_changed.emit()
