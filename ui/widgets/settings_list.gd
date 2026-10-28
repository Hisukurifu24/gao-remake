class_name SettingsList
extends MenuList
## The settings, as a menu: one row per preference with its value, and Back.
## The title and the game menu's System page both show this one list.
##
## Left and right step a value, the confirm key steps it forward (and on Back,
## goes back). Every change goes straight through [method Settings.set_value],
## which applies and saves it.

signal back

const ROWS: Array[StringName] = [&"fullscreen", &"window_scale", &"text_speed", &"screen_shake",
		&"music_volume", &"sound_volume"]


func _ready() -> void:
	stepped.connect(_on_stepped)
	chosen.connect(_on_chosen)
	Settings.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var rows: Array[Dictionary] = [
		{"text": "Fullscreen", "value": "On" if Settings.fullscreen else "Off"},
		{"text": "Window size", "value": "x%d" % Settings.window_scale,
				"enabled": not Settings.fullscreen},
		{"text": "Text speed", "value": Settings.text_speed_name()},
		{"text": "Screen shake", "value": "On" if Settings.screen_shake else "Off"},
		{"text": "Music", "value": _volume(Settings.music_volume)},
		{"text": "Sounds", "value": _volume(Settings.sound_volume)},
		{"text": "Back"},
	]
	set_rows(rows, true)


## What the line under the list says about the row the cursor is on.
func describe(at: int) -> String:
	match at:
		0: return "Fill the screen, or play in a window."
		1: return "The window's size: each pixel of the game drawn this many times." \
				if not Settings.fullscreen else "Fullscreen fills the screen."
		2: return "How fast conversations write themselves out."
		3: return "Whether a critical hit or a stagger shakes the camera."
		4: return "How loud the music plays."
		5: return "How loud everything else is: blows, chests, menus, fanfares."
	return "Settings are saved as you change them."


func _on_stepped(at: int, by: int) -> void:
	if at >= ROWS.size() or not is_enabled(at):
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
			var now := int(Settings.get(ROWS[at]))
			Settings.set_value(ROWS[at], wrapi(now + by, 0, Settings.VOLUME_STEPS + 1))


## A volume as the row shows it: off, or tenths.
static func _volume(steps: int) -> String:
	return "Off" if steps <= 0 else "%d / %d" % [steps, Settings.VOLUME_STEPS]


func _on_chosen(at: int) -> void:
	if at >= ROWS.size():
		back.emit()
	else:
		_on_stepped(at, 1)
