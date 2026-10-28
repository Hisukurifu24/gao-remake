extends CanvasLayer
## The title screen: a main menu over the Town of Beginnings, and a page for each
## thing on it -- load a save, start a new game, the settings, the credits.
##
## A view like every other screen. [SaveGame] owns the slots and does the
## loading, the starting and the deleting; this only lists them and asks which.
## It opens on [signal EventBus.title_requested] -- how the game proper boots, and
## where quitting and dying in a hardcore game end up -- and holds the input lock
## while open, so nothing on the map underneath can open over it.
##
## A new game asks how to play first and where to save second, because a marathon
## is never saved and has no slot to ask about. Esc goes back a page.

enum Page { MAIN, LOAD, NEW_MODE, NEW_SLOT, SETTINGS, CREDITS }
enum Main { CONTINUE, NEW, LOAD, SETTINGS, CREDITS, QUIT }

## [mode, name, what it means, what happens to the save].
const MODES := [
	[GameState.Mode.STANDARD, "Standard",
			"Save anywhere; it autosaves as you go.",
			"Saves into a slot you choose."],
	[GameState.Mode.HARDCORE, "Hardcore",
			"Aincrad's rule: lose a fight, lose the save.",
			"Saves into a slot -- until you fall."],
	[GameState.Mode.MARATHON, "Marathon",
			"Nothing is ever saved.",
			"Close the game and the run is over."],
]

const CREDITS := [
	["GAO", "A fan game set in Aincrad, the floating castle of Sword Art Online."],
	["Made by", "Francesco Naletto"],
	["Art and sound", "Ninja Adventure, by Pixel-boy and AAA -- CC0"],
	["Window frames", "Fantasy UI Borders, by Kenney -- CC0"],
	["Font", "Exo 2, by Natanael Gama -- SIL Open Font License"],
	["Engine", "Godot 4"],
]

const WINDOW_WIDTH := 440.0

var _open := false
## Closed, but still drawn until the map it handed over to has arrived in the
## dark, so the fade goes out over the title and comes back in on the map.
var _handing_over := false
var _page := Page.MAIN
## The way to play the NEW_SLOT page is starting.
var _mode := GameState.Mode.STANDARD
## The card the confirm key was pressed on once -- delete, or overwrite -- and
## wants pressing again; -1 for none.
var _confirming := -1

var _logo: Control
var _notice: PanelContainer
var _notice_text: Label
var _menu: MenuList
var _menu_detail: Label
var _window: PanelContainer
var _header: Label
var _cards: CardList
var _settings: SettingsList
var _credits: VBoxContainer
var _detail: Label
var _hints: KeyHints


func _ready() -> void:
	visible = false
	_build()
	EventBus.title_requested.connect(open)
	SceneRouter.map_changed.connect(_on_map_changed)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


## Puts the title up, saying [param notice] -- and any hardcore game that was left
## mid-fight, which is buried before the slots are listed.
func open(notice := "") -> void:
	var notices := PackedStringArray([notice] if not notice.is_empty() else [])
	notices.append_array(SaveGame.bury_fallen())
	_say("\n".join(notices))
	_handing_over = false
	visible = true
	if not _open:
		_open = true
		GameState.push_input_lock()
	_show_page(Page.MAIN)


## Lets go of the lock and hands over to whatever is about to fade in. Stays on
## screen until that map arrives.
func _hand_over() -> void:
	if not _open:
		return
	_open = false
	_handing_over = true
	GameState.pop_input_lock()


func _on_map_changed(_path: String) -> void:
	if _handing_over:
		_handing_over = false
		visible = false


# --- the pages -------------------------------------------------------------

func page() -> Page:
	return _page


## The menu the page shows -- the main menu, or the settings -- for tests and tools.
func list() -> MenuList:
	return _settings if _page == Page.SETTINGS else _menu


## The cards the page shows -- the slots, or the ways to play.
func cards() -> CardList:
	return _cards


func _show_page(next: Page) -> void:
	_page = next
	_confirming = -1
	var main := next == Page.MAIN
	_logo.visible = main
	_menu.visible = main
	_menu_detail.visible = main
	_notice.visible = main and not _notice_text.text.is_empty()
	_window.visible = not main
	_cards.visible = next in [Page.LOAD, Page.NEW_MODE, Page.NEW_SLOT]
	_settings.visible = next == Page.SETTINGS
	_credits.visible = next == Page.CREDITS
	# The credits have a tune of their own; every other page plays the title's.
	Audio.play_over(&"credits" if next == Page.CREDITS else &"")
	match next:
		Page.MAIN:
			_menu.set_rows(_main_rows())
			_menu.select(Main.CONTINUE if _menu.is_enabled(Main.CONTINUE) else Main.NEW)
			_hints.show_hints([["E", "choose"]])
		Page.LOAD:
			_header.text = "Load game"
			_cards.set_cards(_slot_cards())
			_cards.select(maxi(0, latest_slot() - 1))
			_hints.show_hints([["E", "load"], [["Del", "X"], "delete"], ["Esc", "back"]])
		Page.NEW_MODE:
			_header.text = "New game -- how will you play?"
			_cards.set_cards(_mode_cards())
			_hints.show_hints([["E", "choose"], ["Esc", "back"]])
		Page.NEW_SLOT:
			_header.text = "New game -- %s -- choose a slot" % _mode_name(_mode)
			_cards.set_cards(_slot_cards())
			_cards.select(maxi(0, first_empty_slot() - 1))
			_hints.show_hints([["E", "start here"], ["Esc", "back"]])
		Page.SETTINGS:
			_header.text = "Settings"
			_settings.refresh()
			_settings.select(0)
			_hints.show_hints([[["Left", "Right"], "change"], ["E", "choose"], ["Esc", "back"]])
		Page.CREDITS:
			_header.text = "Credits"
			_hints.show_hints([["Esc", "back"]])
	_paint_detail()
	# The window fits its page: collapsed to its top edge, it grows to its rows.
	_window.offset_bottom = _window.offset_top + 1.0


func _main_rows() -> Array[Dictionary]:
	var any := latest_slot() > 0
	return [
		{"text": "Continue", "enabled": any},
		{"text": "New game"},
		{"text": "Load game", "enabled": any},
		{"text": "Settings"},
		{"text": "Credits"},
		{"text": "Quit"},
	]


func _slot_cards() -> Array[PanelContainer]:
	var built: Array[PanelContainer] = []
	for n in range(1, SaveGame.SLOTS + 1):
		var card := SaveCard.new()
		card.show_slot(n, SaveGame.summary(n))
		built.append(card)
	return built


func _mode_cards() -> Array[PanelContainer]:
	var built: Array[PanelContainer] = []
	for mode: Array in MODES:
		var card := PanelContainer.new()
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override(&"separation", 2)
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lines)
		var name_label := Label.new()
		name_label.text = mode[1]
		name_label.theme_type_variation = &"HeaderLabel"
		if mode[0] != GameState.Mode.STANDARD:
			name_label.add_theme_color_override(&"font_color", UiPalette.BAD)
		lines.add_child(name_label)
		var what := Label.new()
		what.text = mode[2]
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(what)
		var saves := Label.new()
		saves.text = mode[3]
		saves.theme_type_variation = &"HintLabel"
		lines.add_child(saves)
		for label: Label in [name_label, what, saves]:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		built.append(card)
	return built


func _mode_name(mode: GameState.Mode) -> String:
	for entry: Array in MODES:
		if entry[0] == mode:
			return entry[1]
	return "?"


## The slot saved most recently, or 0 with none: what Continue continues.
static func latest_slot() -> int:
	var best := 0
	var best_time := -1
	for n in range(1, SaveGame.SLOTS + 1):
		var meta := SaveGame.summary(n)
		if meta.is_empty():
			continue
		var at := SaveCodec.whole(meta.get("saved_at"), 0)
		if at > best_time:
			best = n
			best_time = at
	return best


static func first_empty_slot() -> int:
	for n in range(1, SaveGame.SLOTS + 1):
		if not SaveGame.exists(n):
			return n
	return 1


func _paint_detail() -> void:
	var text := " "
	match _page:
		Page.MAIN:
			match _menu.index:
				Main.CONTINUE:
					var n := latest_slot()
					var meta := SaveGame.summary(n)
					text = "%s, Lv %d -- %s" % [meta.get("name", "?"), SaveCodec.whole(meta.get("level"), 1),
							SaveCard.where(meta)] if n > 0 else "There is no save to continue yet."
				Main.LOAD:
					text = "Pick up any of the three saves." if latest_slot() > 0 else "There are no saves yet."
				Main.NEW:
					text = "Start the climb from the Town of Beginnings."
				Main.SETTINGS:
					text = "The window, the text, the camera."
		Page.LOAD:
			var n := _cards.index + 1
			if _confirming == _cards.index:
				text = "Press Del again to delete slot %d for good." % n
			elif not SaveGame.exists(n):
				text = "An empty slot. Start a new game to fill it."
			else:
				text = "Back to where you saved."
		Page.NEW_SLOT:
			var n := _cards.index + 1
			if _confirming == _cards.index:
				text = "Press E again: slot %d's save will be overwritten." % n
			elif SaveGame.exists(n):
				text = "This slot has a save in it."
			else:
				text = "An empty slot."
		Page.SETTINGS:
			text = _settings.describe(_settings.index)
	_detail.text = text
	_menu_detail.text = text
	_detail.add_theme_color_override(&"font_color",
			UiPalette.BAD if _confirming >= 0 else UiPalette.DIM)


func _repaint_cards() -> void:
	if _page != Page.LOAD and _page != Page.NEW_SLOT:
		return
	for i in _cards.card_count():
		var note := ""
		if i == _confirming:
			note = "Press again to delete" if _page == Page.LOAD else "Press again to overwrite"
		(_cards.card(i) as SaveCard).show_slot(i + 1, SaveGame.summary(i + 1), note)
	_paint_detail()


func _say(notice: String) -> void:
	_notice_text.text = notice
	_notice.visible = _page == Page.MAIN and not notice.is_empty()


# --- choosing --------------------------------------------------------------

func _on_menu_chosen(at: int) -> void:
	if not _menu.is_enabled(at):
		return
	match at:
		Main.CONTINUE:
			continue_slot(latest_slot())
		Main.NEW:
			_show_page(Page.NEW_MODE)
		Main.LOAD:
			_show_page(Page.LOAD)
		Main.SETTINGS:
			_show_page(Page.SETTINGS)
		Main.CREDITS:
			_show_page(Page.CREDITS)
		Main.QUIT:
			get_tree().quit()


func _on_card_chosen(at: int) -> void:
	match _page:
		Page.LOAD:
			if SaveGame.exists(at + 1):
				continue_slot(at + 1)
		Page.NEW_MODE:
			_mode = MODES[at][0]
			if _mode == GameState.Mode.MARATHON:
				begin(0, _mode)
			else:
				_show_page(Page.NEW_SLOT)
		Page.NEW_SLOT:
			if SaveGame.exists(at + 1) and _confirming != at:
				_confirming = at
				_repaint_cards()
				return
			begin(at + 1, _mode)


## Moving off a card takes back a first press on it.
func _on_card_moved(_at: int) -> void:
	if _confirming >= 0:
		_confirming = -1
		_repaint_cards()
	_paint_detail()


## Delete on the load page: the first press asks, the second empties the slot.
func delete_selected() -> void:
	if _page != Page.LOAD:
		return
	var at := _cards.index
	if not SaveGame.exists(at + 1):
		return
	if _confirming != at:
		_confirming = at
		_repaint_cards()
		return
	SaveGame.delete(at + 1)
	_say("Slot %d deleted." % (at + 1))
	_confirming = -1
	_repaint_cards()
	if latest_slot() == 0:
		_show_page(Page.MAIN)


func _back() -> void:
	if _page != Page.MAIN:
		Audio.play(&"cancel")
	match _page:
		Page.NEW_SLOT:
			_show_page(Page.NEW_MODE)
			_cards.select(MODES.map(func(m: Array) -> int: return m[0]).find(_mode))
		Page.MAIN:
			pass
		_:
			var from := _page
			_show_page(Page.MAIN)
			_menu.select({Page.LOAD: Main.LOAD, Page.NEW_MODE: Main.NEW,
					Page.SETTINGS: Main.SETTINGS, Page.CREDITS: Main.CREDITS}.get(from, Main.NEW))


## Loads [param n] and hands over to it. A save that won't load brings the title
## back saying so, with the game untouched.
func continue_slot(n: int) -> void:
	_hand_over()
	var loaded: bool = await SaveGame.load_slot(n)
	if not loaded:
		open("Slot %d could not be loaded." % n)


## Starts a new game in [param n], played as [param mode].
func begin(n: int, mode: GameState.Mode) -> void:
	_hand_over()
	await SaveGame.new_game(n, mode)


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	# Coming back from the game, the title is up before the fade has finished.
	if SceneRouter.is_busy():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		_back()
		return
	var up := event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up")
	var down := event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down")
	var left := event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left")
	var right := event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right")
	var confirm := event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept")
	match _page:
		Page.MAIN, Page.SETTINGS:
			var menu := list()
			if up or down:
				menu.move(-1 if up else 1)
			elif left or right:
				menu.step(-1 if left else 1)
			elif confirm:
				menu.choose()
		Page.CREDITS:
			if confirm:
				_back()
		_:
			if up or down:
				_cards.move(-1 if up else 1)
			elif confirm:
				_cards.choose()
			elif _is_key(event, KEY_DELETE) or _is_key(event, KEY_X):
				delete_selected()


func _is_key(event: InputEvent, key: Key) -> bool:
	var pressed := event as InputEventKey
	return pressed != null and pressed.pressed and not pressed.echo \
			and pressed.physical_keycode == key


# --- building --------------------------------------------------------------

func _build() -> void:
	var ground := ColorRect.new()
	ground.color = Color("2b2824")
	# Under the town, whose ground layers draw at z -2 like on any map.
	ground.z_index = -10
	_fill(ground)
	add_child(ground)
	var town := TownBackdrop.new()
	_fill(town)
	add_child(town)

	_logo = VBoxContainer.new()
	_logo.add_theme_constant_override(&"separation", 0)
	_logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_logo.offset_top = 14.0
	_logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_logo)
	var title := Label.new()
	title.text = "GAO"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override(&"font_size", 64)
	title.add_theme_constant_override(&"shadow_offset_x", 2)
	title.add_theme_constant_override(&"shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A hundred floors of Aincrad"
	subtitle.theme_type_variation = &"FieldLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(subtitle)

	_menu = MenuList.new()
	_menu.centered = true
	_menu.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu.offset_left = -100.0
	_menu.offset_right = 92.0
	_menu.offset_top = 140.0
	_menu.add_theme_constant_override(&"separation", 3)
	_menu.chosen.connect(_on_menu_chosen)
	_menu.moved.connect(func(_at: int) -> void: _paint_detail())
	add_child(_menu)

	_menu_detail = _field_label()
	_menu_detail.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu_detail.offset_left = -300.0
	_menu_detail.offset_right = 300.0
	_menu_detail.offset_top = 296.0
	_menu_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_menu_detail)

	_notice = PanelContainer.new()
	_notice.theme_type_variation = &"HudPanel"
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.offset_top = 106.0
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)
	_notice_text = Label.new()
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_text.add_theme_color_override(&"font_color", UiPalette.GLASS_READY)
	_notice.add_child(_notice_text)

	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_window.offset_left = -WINDOW_WIDTH * 0.5
	_window.offset_right = WINDOW_WIDTH * 0.5
	_window.offset_top = 16.0
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_window.add_child(column)
	_header = Label.new()
	_header.theme_type_variation = &"HeaderLabel"
	column.add_child(_header)

	_cards = CardList.new()
	_cards.chosen.connect(_on_card_chosen)
	_cards.moved.connect(_on_card_moved)
	column.add_child(_cards)

	_settings = SettingsList.new()
	_settings.back.connect(_back)
	_settings.moved.connect(func(_at: int) -> void: _paint_detail())
	column.add_child(_settings)

	_credits = VBoxContainer.new()
	_credits.add_theme_constant_override(&"separation", 3)
	for entry: Array in CREDITS:
		var what := Label.new()
		what.text = entry[0]
		what.theme_type_variation = &"HeaderLabel"
		_credits.add_child(what)
		var who := Label.new()
		who.text = entry[1]
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_credits.add_child(who)
	column.add_child(_credits)

	_detail = Label.new()
	_detail.theme_type_variation = &"HintLabel"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail)

	_hints = KeyHints.new()
	_hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hints.offset_left = 12.0
	_hints.offset_top = -24.0
	_hints.offset_bottom = -4.0
	add_child(_hints)


func _field_label() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"FieldLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fill(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
