extends Node
## The player's preferences: the window, how fast text types, whether the camera
## shakes, how loud the music and the sounds are. Not part of any save -- they
## belong to the machine, not the run -- so they live in their own file and apply
## to every slot.
##
## The views read them ([method chars_per_second], [member screen_shake]) and the
## settings page writes them through [method set_value], which applies and saves
## at once: there is no "apply" button to forget. A run with no settings file
## changes nothing about the window, so the project's own settings stand; the
## volumes are set from their defaults either way.
##
## The keys work the same way through [method bind], on top of the project's
## input map. Each action in [constant BINDINGS] has one key the player can move;
## the actions' other keys (the arrows, Space, Enter, Tab) never move, and neither
## does Esc, so no choice here can leave a player unable to walk or get out of a
## menu. Giving an action a key another one has swaps the two, so no action is ever
## left with nothing. Everything else in the game reads actions, and whatever names
## a key on screen asks [method key_name].

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
const KEYS_SECTION := "keys"
## [action, what the settings page calls it], in the order it lists them.
const BINDINGS := [
	[&"move_up", "Move up"], [&"move_down", "Move down"],
	[&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"interact", "Interact"], [&"inventory", "Items"], [&"journal", "Quests"],
	[&"map", "Map"], [&"quick_save", "Quick save"], [&"quick_load", "Back to the save"],
]
## Keys that keep the one job they have, whatever the page says.
const FIXED_KEYS: Array[Key] = [KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_TAB,
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
## [label, characters a second]; 0 is instant.
const TEXT_SPEEDS := [["Slow", 25.0], ["Normal", 45.0], ["Fast", 90.0], ["Instant", 0.0]]
## How many screen pixels to a world pixel, windowed. The camera shows 320x180 of
## the world (the 640x360 viewport at [constant UiLayout.WORLD_ZOOM]), so these
## are the sizes it stays crisp at.
const SCALES: Array[int] = [2, 3, 4, 5, 6]
const BASE := Vector2i(320, 180)
## Volumes are steps of a tenth, 0 (off) to [constant VOLUME_STEPS] (full).
const VOLUME_STEPS := 10
const MUSIC_VOLUME := 5
const SOUND_VOLUME := 8
## The Music bus at full. The pack masters its tracks 10 dB over its sounds (median
## RMS -19 against -29, measured off the files), which is music on top of the game
## rather than under it: at this ceiling, a full slider is level with the sounds.
const MUSIC_CEILING_DB := -14.0

## Where the file is. Tests point this elsewhere so they never touch the player's.
var path := PATH
var fullscreen := false
var window_scale := 4
var text_speed := 1
var screen_shake := true
var music_volume := MUSIC_VOLUME
var sound_volume := SOUND_VOLUME
## Action -> the physical key it is on now, and what the project ships.
var _keys := {}
var _default_keys := {}


func _ready() -> void:
	for binding: Array in BINDINGS:
		_default_keys[binding[0]] = _shipped_key(binding[0])
	_keys = _default_keys.duplicate()
	if load_settings():
		apply_window()
	apply_audio()


## Every key [method set_value] takes, with what it is now -- for the page that lists them.
func keys() -> Array[StringName]:
	return [&"fullscreen", &"window_scale", &"text_speed", &"screen_shake",
			&"music_volume", &"sound_volume"]


## Sets one preference, applies it and writes the file. Out-of-range values are
## clamped rather than refused: the page steps through them and wraps.
func set_value(key: StringName, value: Variant) -> void:
	match key:
		&"fullscreen":
			fullscreen = bool(value)
		&"window_scale":
			window_scale = int(value) if SCALES.has(int(value)) else 4
		&"text_speed":
			text_speed = clampi(int(value), 0, TEXT_SPEEDS.size() - 1)
		&"screen_shake":
			screen_shake = bool(value)
		&"music_volume":
			music_volume = clampi(int(value), 0, VOLUME_STEPS)
		&"sound_volume":
			sound_volume = clampi(int(value), 0, VOLUME_STEPS)
		_:
			push_warning("Settings: no setting called '%s'" % key)
			return
	if key == &"fullscreen" or key == &"window_scale":
		apply_window()
	if key == &"music_volume" or key == &"sound_volume":
		apply_audio()
	save_settings()
	changed.emit()


## Characters a second the dialogue box types at; 0 for all at once.
func chars_per_second() -> float:
	return TEXT_SPEEDS[text_speed][1]


func text_speed_name() -> String:
	return TEXT_SPEEDS[text_speed][0]


## Puts the window in the mode and size the settings say. Does nothing without a
## real window (headless tests and tools).
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := BASE * window_scale
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## Sets the Music and Sounds buses to the volumes. A slider's share is squared on
## the way to the bus, since an ear hears ratios: taken straight, its top two thirds
## are the last 10 dB and it only turns anything down near the bottom. A volume of 0
## mutes its bus rather than turning it down to nearly nothing. Works headless as
## anywhere.
func apply_audio() -> void:
	for level in [[&"Music", music_volume, MUSIC_CEILING_DB], [&"Sounds", sound_volume, 0.0]]:
		var bus := AudioServer.get_bus_index(level[0])
		if bus < 0:
			continue
		var share := float(level[1]) / VOLUME_STEPS
		AudioServer.set_bus_mute(bus, share <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(share * share, 0.0001)) + level[2])


# --- the keys --------------------------------------------------------------

## The physical key [param action] is on now.
func key_of(action: StringName) -> Key:
	return _keys.get(action, KEY_NONE)


## [param action]'s key as [KeyHints] spells it. A key stays where it is on the
## board whatever the layout, so what it is called comes from the layout.
func key_name(action: StringName) -> String:
	return label_of(key_of(action))


static func label_of(key: Key) -> String:
	if DisplayServer.get_name() != "headless":
		key = DisplayServer.keyboard_get_keycode_from_physical(key)
	return OS.get_keycode_string(key)


## Why [param key] can't be given to an action, or empty if it can. Only a key the
## pack draws a keycap for will do: every key on screen is shown as one.
func refusal(key: Key) -> String:
	if FIXED_KEYS.has(key):
		return "Esc, Enter, Space, Tab and the arrows keep the jobs they have."
	if not KeyHints.has_cap(label_of(key)):
		return "That key can't be used."
	return ""


## Puts [param action] on [param key] and saves it. Returns the action that had the
## key, which now has [param action]'s old one, or empty if none did -- or if the
## key was refused, which changes nothing.
func bind(action: StringName, key: Key) -> StringName:
	if not _keys.has(action) or not refusal(key).is_empty() or _keys[action] == key:
		return &""
	var swapped: StringName = _keys.find_key(key) if _keys.values().has(key) else &""
	if not swapped.is_empty():
		_keys[swapped] = _keys[action]
	_keys[action] = key
	apply_keys()
	save_settings()
	changed.emit()
	return swapped


func keys_are_default() -> bool:
	return _keys == _default_keys


func reset_keys() -> void:
	_keys = _default_keys.duplicate()
	apply_keys()
	save_settings()
	changed.emit()


## Writes the keys into the input map. Only each action's first key moves.
func apply_keys() -> void:
	for action: StringName in _keys:
		var events := InputMap.action_get_events(action)
		var first := events.find_custom(func(e: InputEvent) -> bool: return e is InputEventKey)
		var moved := InputEventKey.new()
		moved.physical_keycode = _keys[action]
		events[first] = moved
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


func _shipped_key(action: StringName) -> Key:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


## A file's keys, usable as they are: all of them keys an action may have, and
## none of them twice. Anything else, from a hand-edited file, is ignored whole.
func _keys_hold(keys: Dictionary) -> bool:
	for key: int in keys.values():
		if not refusal(key as Key).is_empty() or keys.values().count(key) > 1:
			return false
	return true


## Back to how a new install has them, without writing anything.
func reset() -> void:
	fullscreen = false
	window_scale = 4
	text_speed = 1
	screen_shake = true
	music_volume = MUSIC_VOLUME
	sound_volume = SOUND_VOLUME
	_keys = _default_keys.duplicate()
	apply_keys()
	apply_audio()
	changed.emit()


func save_settings() -> bool:
	var file := ConfigFile.new()
	file.set_value(SECTION, "fullscreen", fullscreen)
	file.set_value(SECTION, "window_scale", window_scale)
	file.set_value(SECTION, "text_speed", text_speed)
	file.set_value(SECTION, "screen_shake", screen_shake)
	file.set_value(SECTION, "music_volume", music_volume)
	file.set_value(SECTION, "sound_volume", sound_volume)
	# Only what was moved, so a key the game changes reaches whoever left it alone.
	for action: StringName in _keys:
		if _keys[action] != _default_keys[action]:
			file.set_value(KEYS_SECTION, action, int(_keys[action]))
	return file.save(path) == OK


## Reads the file; false if there is none, which leaves the defaults. A value
## out of range or of the wrong type is the default.
func load_settings() -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	fullscreen = bool(file.get_value(SECTION, "fullscreen", false))
	var scale := int(file.get_value(SECTION, "window_scale", 4))
	window_scale = scale if SCALES.has(scale) else 4
	text_speed = clampi(int(file.get_value(SECTION, "text_speed", 1)), 0, TEXT_SPEEDS.size() - 1)
	screen_shake = bool(file.get_value(SECTION, "screen_shake", true))
	music_volume = clampi(int(file.get_value(SECTION, "music_volume", MUSIC_VOLUME)), 0, VOLUME_STEPS)
	sound_volume = clampi(int(file.get_value(SECTION, "sound_volume", SOUND_VOLUME)), 0, VOLUME_STEPS)
	var keys := _default_keys.duplicate()
	for action: StringName in keys:
		keys[action] = int(file.get_value(KEYS_SECTION, action, keys[action]))
	_keys = keys if _keys_hold(keys) else _default_keys.duplicate()
	apply_keys()
	changed.emit()
	return true
