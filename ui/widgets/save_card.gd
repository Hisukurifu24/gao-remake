class_name SaveCard
extends PanelContainer
## One save slot as a card: the player's face, who and how far, where, and when.
##
## Drawn from [method SaveGame.summary] and nothing else, so listing the slots
## never loads a game. A death game wears a red badge -- the one thing about a
## slot worth seeing before you pick it. [param note] replaces the last line, for
## "press again to delete".

const FACE := "res://assets/ninja_adventure/Actor/Character/SamuraiBlue/Faceset.png"
## The pack's 38 px faceset, halved -- the dialogue box's rule.
const FACE_SIZE := Vector2(38, 38)

var _face: TextureRect
var _name: Label
var _badge: PanelContainer
var _slot: Label
var _where: Label
var _when: Label


func _init() -> void:
	theme_type_variation = &"InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"FacesetFrame"
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	_face = TextureRect.new()
	_face.custom_minimum_size = FACE_SIZE
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_SCALE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_face)

	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override(&"separation", 1)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)

	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(top)
	_name = _label(top, &"")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot = _label(top, &"HintLabel")
	_slot.clip_text = false

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override(&"separation", 8)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(middle)
	_where = _label(middle, &"HintLabel")
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge = PanelContainer.new()
	_badge.theme_type_variation = &"BadgePanel"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_text := _label(_badge, &"BadgeLabel")
	badge_text.text = "Death Game"
	badge_text.clip_text = false
	middle.add_child(_badge)
	_when = _label(lines, &"HintLabel")


## Fills the card for [param n] from its summary; empty [param meta] is an empty slot.
func show_slot(n: int, meta: Dictionary, note := "") -> void:
	_slot.text = "Slot %d" % n
	var empty := meta.is_empty()
	_face.texture = null if empty else load(FACE) as Texture2D
	_face.modulate.a = 1.0
	_badge.visible = not empty \
			and GameState.mode_named(str(meta.get("mode", ""))) == GameState.Mode.DEATH_GAME
	if empty:
		_name.text = "Empty"
		_name.add_theme_color_override(&"font_color", UiPalette.LOCKED)
		_where.text = "No save here yet."
		_when.text = " "
	else:
		_name.text = "%s   Lv %d" % [meta.get("name", "?"), SaveCodec.whole(meta.get("level"), 1)]
		_name.add_theme_color_override(&"font_color", UiPalette.TEXT)
		_where.text = where(meta)
		var played := SaveCodec.whole(meta.get("play_time"), -1)
		_when.text = saved_when(SaveCodec.whole(meta.get("saved_at"), 0)) \
				+ ("   %s played" % play_time(played) if played >= 0 else "")
	_when.remove_theme_color_override(&"font_color")
	if not note.is_empty():
		_when.text = note
		_when.add_theme_color_override(&"font_color", UiPalette.BAD)


## Everything the card says, line by line: for tests and tools.
func text() -> String:
	return "%s %s\n%s%s\n%s" % [_name.text, _slot.text, _where.text,
			"  Death Game" if _badge.visible else "", _when.text]


## "Floor 10, Ashlow Wood": a map's name may start with its floor's number,
## already said.
static func where(meta: Dictionary) -> String:
	var floor_text := "Floor %d" % SaveCodec.whole(meta.get("floor"), 1)
	var place := str(meta.get("place", "")).trim_prefix(floor_text).lstrip(" -,:")
	return floor_text if place.is_empty() else "%s, %s" % [floor_text, place]


## A save's time as a slot shows it: the date and the minute, local time.
static func saved_when(unix_time: int) -> String:
	if unix_time <= 0:
		return "Saved at some point"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var at := Time.get_datetime_dict_from_unix_time(unix_time + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [at["year"], at["month"], at["day"], at["hour"], at["minute"]]


## Seconds played as hours and minutes: "3:07".
static func play_time(seconds: int) -> String:
	var minutes := maxi(0, seconds) / 60
	return "%d:%02d" % [minutes / 60, minutes % 60]


func _label(parent: Control, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
