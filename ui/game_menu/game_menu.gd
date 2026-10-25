extends CanvasLayer
## The game menu: one window over the dimmed map with a tab for each thing a
## player stops to look at -- Status, Items, Quests, Map, System.
##
## [kbd]Esc[/kbd] opens it on Status, [kbd]I[/kbd] on Items, [kbd]J[/kbd] on Quests,
## [kbd]M[/kbd] on the Map; inside, [kbd]Q[/kbd] / [kbd]E[/kbd] (or [kbd]Shift+Tab[/kbd] /
## [kbd]Tab[/kbd], or a click) change tab, the tab's own key closes it again, and
## [kbd]Esc[/kbd] closes it. E is the interact key on the map, so in here the pages
## confirm on [kbd]Space[/kbd] / [kbd]Enter[/kbd] instead.
##
## The menu owns everything the pages share: when it may open (from the overworld
## and nowhere else -- not over a conversation, a fight, a fade or the title), the
## input lock while it is up (which is what stops the monsters and a brazier's
## clock), the tabs, and the key line. The pages are views of [GameState],
## [Inventory], [QuestLog] and [SaveGame] and decide nothing.

enum Tab { STATUS, ITEMS, QUESTS, MAP, SYSTEM }

const PAGES := {
	Tab.STATUS: preload("res://ui/game_menu/status_page.gd"),
	Tab.ITEMS: preload("res://ui/game_menu/items_page.gd"),
	Tab.QUESTS: preload("res://ui/game_menu/quests_page.gd"),
	Tab.MAP: preload("res://ui/game_menu/map_page.gd"),
	Tab.SYSTEM: preload("res://ui/game_menu/system_page.gd"),
}
## The action that opens each tab straight from the map, and closes it again.
const HOTKEYS := {&"pause": Tab.STATUS, &"inventory": Tab.ITEMS, &"journal": Tab.QUESTS,
		&"map": Tab.MAP}
const COIN := "res://assets/ninja_adventure/Items/Treasure/GoldCoin.png"
## Where the tabs and the purse stand, and how tall both are: a line of text and
## the tab's padding. The window starts just under them.
const STRIP_TOP := 4.0
const STRIP_HEIGHT := 22.0

var _open := false
var _tab := Tab.STATUS
var _pages: Array[MenuPage] = []
var _tabs: Array[PanelContainer] = []
var _hovered := -1

var _col: Label
var _hints: KeyHints


func _ready() -> void:
	visible = false
	_build()
	CombatManager.combat_began.connect(
			func(_e: Encounter, _p: Array[Combatant], _en: Array[Combatant]) -> void: close())
	EventBus.col_changed.connect(func(_amount: int) -> void: _paint_col())
	EventBus.screens_close_requested.connect(close)


# --- opening and closing ---------------------------------------------------

func is_open() -> bool:
	return _open


func tab() -> Tab:
	return _tab


func page(of_tab: Tab) -> MenuPage:
	return _pages[of_tab]


## Opens on [param on_tab], unless something else is up -- see [method can_open].
## [param force] skips that check, for a tool that is holding the lock itself.
func open(on_tab := Tab.STATUS, force := false) -> void:
	if _open:
		show_tab(on_tab)
		return
	if not force and not can_open():
		return
	_open = true
	visible = true
	GameState.push_input_lock()
	EventBus.game_menu_toggled.emit(true)
	_paint_col()
	_tab = on_tab
	_show_current()


func close() -> void:
	if not _open:
		return
	_pages[_tab].hidden()
	_open = false
	visible = false
	GameState.pop_input_lock()
	EventBus.game_menu_toggled.emit(false)


## From the overworld and nowhere else: not over a conversation, a fight or a
## fade, and only with a player on a map -- which the title screen has not.
func can_open() -> bool:
	return not GameState.is_input_locked() and not DialogueRunner.is_running() \
			and not CombatManager.is_running() and SceneRouter.current_map() != null


func show_tab(next: Tab) -> void:
	if not _open:
		return
	if next == _tab:
		return
	_pages[_tab].hidden()
	_tab = next
	_show_current()


func _show_current() -> void:
	for i in _pages.size():
		_pages[i].visible = i == _tab
	_pages[_tab].shown()
	_paint_tabs()
	_paint_hints()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		for action: StringName in HOTKEYS:
			if event.is_action_pressed(action) and can_open():
				get_viewport().set_input_as_handled()
				open(HOTKEYS[action])
				return
		return

	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		if not _pages[_tab].back():
			close()
		return
	for action: StringName in HOTKEYS:
		if action != &"pause" and event.is_action_pressed(action):
			if HOTKEYS[action] == _tab:
				close()
			else:
				show_tab(HOTKEYS[action])
			return
	_pages[_tab].handle(event)


## The tab keys are read before anything else sees them: left to
## [code]_unhandled_input[/code], Godot spends Tab on moving keyboard focus
## ([code]ui_focus_next[/code]), and E would reach a page as [code]interact[/code],
## which every page takes for confirm.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	var by := 0
	if MenuPage.is_key(event, KEY_TAB):
		by = -1 if (event as InputEventKey).shift_pressed else 1
	elif MenuPage.is_key(event, KEY_Q):
		by = -1
	elif MenuPage.is_key(event, KEY_E):
		by = 1
	if by != 0:
		get_viewport().set_input_as_handled()
		show_tab(wrapi(_tab + by, 0, _pages.size()) as Tab)


# --- drawing ---------------------------------------------------------------

func _paint_tabs() -> void:
	for i in _tabs.size():
		var on := i == _tab
		var variation := &"TabOn" if on else (&"TabHover" if i == _hovered else &"TabOff")
		if _tabs[i].theme_type_variation != variation:
			_tabs[i].theme_type_variation = variation
		var label := _tabs[i].get_child(0) as Label
		label.add_theme_color_override(&"font_color", UiPalette.ON_ACCENT if on else UiPalette.TEXT)


func _paint_hints() -> void:
	var hints := _pages[_tab].hints()
	hints.append([["Q", "E"], "tab"])
	hints.append(["Esc", "close"])
	_hints.show_hints(hints)


func _paint_col() -> void:
	_col.text = "%d col" % GameState.col()


## What the key line says now, for tests and tools.
func hint_text() -> String:
	return _hints.text()


# --- building --------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.09, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	# The window's sides only meet the pages' own framed panels, which pad themselves.
	window.theme_type_variation = &"MenuWindow"
	# Below the tab strip and the purse, never under them: their frames and the
	# window's are each drawn whole.
	window.position = Vector2(4, STRIP_TOP + STRIP_HEIGHT + 2)
	window.size = Vector2(632, 332 - window.position.y)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(stack)

	var strip := MenuPage.box(false, 2)
	strip.position = Vector2(14, STRIP_TOP)
	add_child(strip)
	for i in PAGES.size():
		var made: MenuPage = PAGES[i].new()
		made.menu = self
		made.set_anchors_preset(Control.PRESET_FULL_RECT)
		made.visible = false
		made.hints_changed.connect(_on_hints_changed.bind(made))
		stack.add_child(made)
		_pages.append(made)

		var tab_panel := PanelContainer.new()
		tab_panel.theme_type_variation = &"TabOff"
		tab_panel.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
		tab_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tab_panel.mouse_entered.connect(_on_tab_hovered.bind(i))
		tab_panel.mouse_exited.connect(_on_tab_hovered.bind(-1))
		tab_panel.gui_input.connect(_on_tab_input.bind(i))
		MenuPage.label(made.title(), &"", tab_panel)
		strip.add_child(tab_panel)
		_tabs.append(tab_panel)

	# The purse, on a glass plate of its own, as tall as the tabs beside it.
	var plate := MenuPage.panel(&"HudPanel")
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.offset_left = -9.0
	plate.offset_right = -8.0
	plate.offset_top = STRIP_TOP
	plate.offset_bottom = STRIP_TOP + STRIP_HEIGHT
	add_child(plate)
	var purse := MenuPage.box(false, 4, plate)
	MenuPage.icon_rect(load(COIN) as Texture2D, Vector2(14, 14), purse)
	_col = MenuPage.label("", &"", purse)
	_col.add_theme_color_override(&"font_color", UiPalette.GLASS_READY)

	_hints = KeyHints.new()
	_hints.position = Vector2(12, 336)
	_hints.size = Vector2(620, 20)
	add_child(_hints)


func _on_hints_changed(from: MenuPage) -> void:
	if _open and from == _pages[_tab]:
		_paint_hints()


func _on_tab_hovered(at: int) -> void:
	_hovered = at
	_paint_tabs()


func _on_tab_input(event: InputEvent, at: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		show_tab(at as Tab)
