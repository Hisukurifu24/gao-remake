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

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
## [label, characters a second]; 0 is instant.
const TEXT_SPEEDS := [["Slow", 25.0], ["Normal", 45.0], ["Fast", 90.0], ["Instant", 0.0]]
## How many screen pixels to a world pixel, windowed. The camera shows 320x180 of
## the world (the 640x360 viewport at [constant UiLayout.WORLD_ZOOM]), so these
## are the sizes it stays crisp at.
const SCALES: Array[int] = [2, 3, 4, 5, 6]
const BASE := Vector2i(320, 180)
## Volumes are steps of a tenth, 0 (off) to [constant VOLUME_STEPS] (full).
const VOLUME_STEPS := 10
const MUSIC_VOLUME := 7
const SOUND_VOLUME := 8

## Where the file is. Tests point this elsewhere so they never touch the player's.
var path := PATH
var fullscreen := false
var window_scale := 4
var text_speed := 1
var screen_shake := true
var music_volume := MUSIC_VOLUME
var sound_volume := SOUND_VOLUME


func _ready() -> void:
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


## Sets the Music and Sounds buses to the volumes. A volume of 0 mutes its bus
## rather than turning it down to nearly nothing. Works headless as anywhere.
func apply_audio() -> void:
	for pair in [[&"Music", music_volume], [&"Sounds", sound_volume]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus < 0:
			continue
		var share := float(pair[1]) / VOLUME_STEPS
		AudioServer.set_bus_mute(bus, share <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(share, 0.0001)))


## Back to how a new install has them, without writing anything.
func reset() -> void:
	fullscreen = false
	window_scale = 4
	text_speed = 1
	screen_shake = true
	music_volume = MUSIC_VOLUME
	sound_volume = SOUND_VOLUME
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
	changed.emit()
	return true
