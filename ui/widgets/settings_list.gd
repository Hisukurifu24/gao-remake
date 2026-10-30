class_name SettingsList
extends MenuList
## The settings, as a menu: one row per preference with its value, the keys, and
## Back. The title and the game menu's System page both show this one list.
##
## Left and right step a value, the confirm key steps it forward (and on Back,
## goes back). The two volumes are sliders: they stop at their ends rather than
## wrapping, and the mouse can drag them, the music changing under it as it goes.
## Every change goes straight through [method Settings.set_value], which applies
## and saves it.
##
## Keys is a second set of rows in the same list, one per [constant Settings.BINDINGS]
## with the key it is on. Choosing one waits for the next key pressed, read in
## [code]_input[/code] so nothing else on screen gets it first -- Q and E change the
## game menu's tab, and that has to be a key like any other here. Esc leaves the
## row as it was. The list keeps this to itself: a screen only asks
## [method leave_keys] on its way back and redraws on [signal view_changed].

signal back
## The rows or what the line under them says changed by something other than the
## cursor: redraw the key line and the detail.
signal view_changed

const ROWS: Array[StringName] = [&"fullscreen", &"window_scale", &"text_speed", &"screen_shake",
		&"music_volume", &"sound_volume", &"keys"]
## What else an action's on, for the line under the keys.
const ALSO := {
	&"move_up": "The arrow keys always move too.", &"move_down": "The arrow keys always move too.",
	&"move_left": "The arrow keys always move too.", &"move_right": "The arrow keys always move too.",
	&"interact": "Space and Enter always work too.", &"inventory": "Tab always opens and closes Items too.",
}
const KEYS_SEPARATION := 2

var _on_keys := false
## The key row waiting for its new key; -1 for none.
var _waiting := -1
## What the last key pressed did, until the cursor moves.
var _said := ""


func _ready() -> void:
	stepped.connect(_on_stepped)
	slid.connect(_on_slid)
	chosen.connect(_on_chosen)
	moved.connect(func(_at: int) -> void: _said = "")
	Settings.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _on_keys:
		set_rows(_key_rows(), true)
		return
	var rows: Array[Dictionary] = [
		{"text": "Fullscreen", "value": "On" if Settings.fullscreen else "Off"},
		{"text": "Window size", "value": "x%d" % Settings.window_scale,
				"enabled": not Settings.fullscreen},
		{"text": "Text speed", "value": Settings.text_speed_name()},
		{"text": "Screen shake", "value": "On" if Settings.screen_shake else "Off"},
		_volume_row("Music", Settings.music_volume),
		_volume_row("Sounds", Settings.sound_volume),
		{"text": "Keys"},
		{"text": "Back"},
	]
	set_rows(rows, true)


func _key_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in Settings.BINDINGS.size():
		var binding: Array = Settings.BINDINGS[i]
		if i == _waiting:
			rows.append({"text": binding[1], "note": "press a key"})
		else:
			rows.append({"text": binding[1], "cap": Settings.key_name(binding[0])})
	rows.append({"text": "Reset keys", "enabled": not Settings.keys_are_default()})
	rows.append({"text": "Back"})
	return rows


## What the line under the list says about the row the cursor is on.
func describe(at: int) -> String:
	if not _said.is_empty():
		return _said
	if _on_keys:
		return _describe_key(at)
	match at:
		0: return "Fill the screen, or play in a window."
		1: return "The window's size: each pixel of the game drawn this many times." \
				if not Settings.fullscreen else "Fullscreen fills the screen."
		2: return "How fast conversations write themselves out."
		3: return "Whether a critical hit or a stagger shakes the camera."
		4: return "How loud the music plays."
		5: return "How loud everything else is: blows, chests, menus, fanfares."
		6: return "Which key does what."
	return "Settings are saved as you change them."


func _describe_key(at: int) -> String:
	if at == _waiting:
		return "Press the new key, or Esc to leave it."
	if at < Settings.BINDINGS.size():
		return ALSO.get(Settings.BINDINGS[at][0], " ")
	return "Back to the keys the game came with." if at == Settings.BINDINGS.size() \
			else "Settings are saved as you change them."


## The key line for the page, in [KeyHints]' form, on a screen that confirms on
## [param confirm].
func hints(confirm: String) -> Array:
	if is_waiting():
		return [["Esc", "leave it"]]
	if _on_keys:
		return [[confirm, "choose"]]
	return [[["Left", "Right"], "change"], [confirm, "choose"]]


func is_waiting() -> bool:
	return _waiting >= 0


func is_on_keys() -> bool:
	return _on_keys


## Out of the keys, if that is where the list is. True if it was.
func leave_keys() -> bool:
	if not _on_keys:
		return false
	_waiting = -1
	_said = ""
	_on_keys = false
	add_theme_constant_override(&"separation", 4)
	refresh()
	select(ROWS.find(&"keys"))
	view_changed.emit()
	return true


func _open_keys() -> void:
	_on_keys = true
	_said = ""
	add_theme_constant_override(&"separation", KEYS_SEPARATION)
	refresh()
	select(0)
	view_changed.emit()


func _on_stepped(at: int, by: int) -> void:
	if _on_keys or at >= ROWS.size() or not is_enabled(at):
		return
	match ROWS[at]:
		&"fullscreen":
			Settings.set_value(&"fullscreen", not Settings.fullscreen)
		&"window_scale":
			var scales := Settings.SCALES
			var next := wrapi(scales.find(Settings.window_scale) + by, 0, scales.size())
			Settings.set_value(&"window_scale", scales[next])
		&"text_speed":
			Settings.set_value(&"text_speed",
					wrapi(Settings.text_speed + by, 0, Settings.TEXT_SPEEDS.size()))
		&"screen_shake":
			Settings.set_value(&"screen_shake", not Settings.screen_shake)
		&"music_volume", &"sound_volume":
			Settings.set_value(ROWS[at], int(Settings.get(ROWS[at])) + by)


## The mouse on a volume's slider. A drag lands on the same steps the keys do, and
## ticks as it crosses each, so the Sounds slider can be heard moving too.
func _on_slid(at: int, share: float) -> void:
	if _on_keys:
		return
	var steps := roundi(share * Settings.VOLUME_STEPS)
	if steps != int(Settings.get(ROWS[at])):
		Audio.play(&"move")
		Settings.set_value(ROWS[at], steps)


## A volume as its row shows it: a slider, and off or how many tenths.
static func _volume_row(text: String, steps: int) -> Dictionary:
	return {"text": text, "value": "Off" if steps <= 0 else str(steps),
			"slider": float(steps) / Settings.VOLUME_STEPS}


func _on_chosen(at: int) -> void:
	if _on_keys:
		_on_key_chosen(at)
	elif at >= ROWS.size():
		back.emit()
	elif ROWS[at] == &"keys":
		_open_keys()
	else:
		_on_stepped(at, 1)


func _on_key_chosen(at: int) -> void:
	_said = ""
	_waiting = -1
	if at < Settings.BINDINGS.size():
		_waiting = at
		refresh()
	elif at > Settings.BINDINGS.size():
		leave_keys()
		return
	elif is_enabled(at):
		Settings.reset_keys()
		_said = "The keys are back as they were."
	view_changed.emit()


func _input(event: InputEvent) -> void:
	if _waiting < 0:
		return
	# Closed under it -- an idle marathon logs out through any screen.
	if not is_visible_in_tree():
		_waiting = -1
		return
	var pressed := event as InputEventKey
	if pressed == null or not pressed.pressed or pressed.echo:
		return
	get_viewport().set_input_as_handled()
	if pressed.physical_keycode == KEY_ESCAPE:
		Audio.play(&"cancel")
		_finish("")
		return
	var why := Settings.refusal(pressed.physical_keycode)
	if not why.is_empty():
		Audio.play(&"refuse")
		_said = why
		view_changed.emit()
		return
	Audio.play(&"accept")
	var action: StringName = Settings.BINDINGS[_waiting][0]
	var swapped := Settings.bind(action, pressed.physical_keycode)
	_finish("Swapped with %s." % _called(swapped) if not swapped.is_empty() else "")


func _finish(said: String) -> void:
	_waiting = -1
	refresh()
	_said = said
	view_changed.emit()


static func _called(action: StringName) -> String:
	for binding: Array in Settings.BINDINGS:
		if binding[0] == action:
			return binding[1]
	return str(action)
