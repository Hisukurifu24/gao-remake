class_name MenuPage
extends Control
## One tab of the game menu. The menu owns opening, closing, the tabs, the input
## lock and the key line; a page only draws what it shows and answers the keys
## the menu passes it.
##
## Each page is a view like every other screen: it reads the autoloads and calls
## back into them, and never decides a rule they don't.

## The page wants its key line redrawn -- what [kbd]E[/kbd] does has changed.
signal hints_changed

## The menu this page is in, set when the menu builds it.
var menu: Node


## The tab's name.
func title() -> String:
	return ""


## The page has just come up: read everything afresh.
func shown() -> void:
	pass


## The page is going away -- the menu is closing or another tab was picked.
func hidden() -> void:
	pass


## A key the menu didn't want. True if the page used it.
func handle(_event: InputEvent) -> bool:
	return false


## Esc, before the menu closes on it. True if the page used it to step back out
## of something of its own (the settings, say) instead.
func back() -> bool:
	return false


## The page's own keys, as [KeyHints] wants them. The menu adds its own after.
func hints() -> Array:
	return []


static func is_up(event: InputEvent) -> bool:
	return event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up")


static func is_down(event: InputEvent) -> bool:
	return event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down")


static func is_left(event: InputEvent) -> bool:
	return event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left")


static func is_right(event: InputEvent) -> bool:
	return event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right")


## Space and Enter -- and E too, on a screen that isn't the game menu: inside it,
## E changes tab and never reaches a page.
static func is_confirm(event: InputEvent) -> bool:
	return event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept")


## A key read straight off the keyboard, for the few that exist only on one page
## (drop, sort): two more project-wide actions for keys nothing else uses is a
## worse trade than this.
static func is_key(event: InputEvent, key: Key) -> bool:
	var pressed := event as InputEventKey
	return pressed != null and pressed.pressed and not pressed.echo \
			and pressed.physical_keycode == key


## A label in one call: the pages build most of their layout in code.
static func label(text := "", variation := &"", parent: Control = null) -> Label:
	var made := Label.new()
	made.text = text
	made.theme_type_variation = variation
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(made)
	return made


static func box(vertical: bool, separation: int, parent: Control = null) -> BoxContainer:
	var made: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	made.add_theme_constant_override(&"separation", separation)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(made)
	return made


static func panel(variation := &"InsetPanel", parent: Control = null) -> PanelContainer:
	var made := PanelContainer.new()
	made.theme_type_variation = variation
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(made)
	return made


static func icon_rect(texture: Texture2D, size := Vector2(16, 16), parent: Control = null) -> TextureRect:
	var made := TextureRect.new()
	made.texture = texture
	made.custom_minimum_size = size
	made.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	made.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(made)
	return made


static func spacer(parent: Control) -> Control:
	var made := Control.new()
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.size_flags_vertical = Control.SIZE_EXPAND_FILL
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(made)
	return made
