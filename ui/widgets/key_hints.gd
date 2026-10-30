class_name KeyHints
extends HBoxContainer
## The line along the bottom of a menu saying which key does what, drawn with the
## pack's keycaps rather than "[E]" in brackets.
##
## A hint is [code][keys, what][/code]: [code]["E", "choose"][/code], or
## [code][["Left", "Right"], "change"][/code] for two keys that share a verb.
## A key is a name from the pack's keyboard set ([code]Key<name>.png[/code]),
## with the few the pack spells differently in [constant SPELLED], and the
## mouse's buttons in [constant MOUSE]. A key the pack doesn't draw but which types
## a character is that character on a blank cap ([GlyphCap]).

const KEYBOARD := "res://assets/ninja_adventure/Ui/Input/Keyboard/Key%s.png"
const MOUSE := {
	"Click": "res://assets/ninja_adventure/Ui/Input/Mouse/MouseButtonLeft.png",
	"RClick": "res://assets/ninja_adventure/Ui/Input/Mouse/MouseButtonRight.png",
	"Wheel": "res://assets/ninja_adventure/Ui/Input/Mouse/MouseWheelUp.png",
}
const SPELLED := {"Esc": "Escape", "Del": "Delete"}

## Character -> its [GlyphCap], so a repaint gets back the same texture.
static var _glyph_caps := {}

var _text := ""


func _init() -> void:
	add_theme_constant_override(&"separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Replaces the hints. Rebuilt every time: a hint line is a handful of nodes,
## and it changes when the page does, not every frame.
func show_hints(hints: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var words := PackedStringArray()
	for i in hints.size():
		var keys: Variant = hints[i][0]
		var what: String = hints[i][1]
		var names: Array = keys if keys is Array else [keys]
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(12, 0)
			add_child(gap)
		for key: String in names:
			add_child(_cap(key))
		var label := Label.new()
		label.text = what
		label.theme_type_variation = &"FieldLabel"
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(label)
		words.append("%s %s" % [" ".join(names.map(func(k: String) -> String: return "[%s]" % k)), what])
	_text = "   ".join(words)


## What the hints say, as text: for tests and tools.
func text() -> String:
	return _text


func _cap(key: String) -> TextureRect:
	var cap := TextureRect.new()
	cap.texture = texture_for(key)
	cap.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap


## Whether [param key] can be drawn: the pack has it, or it types a character the
## font has. The bindings hold to this and [method Settings.key_name] falls back on
## it, so a key name from there always has a cap.
static func has_cap(key: String) -> bool:
	return ResourceLoader.exists(_path(key)) or _glyph(key) != 0


static func texture_for(key: String) -> Texture2D:
	if MOUSE.has(key):
		return load(MOUSE[key]) as Texture2D
	if ResourceLoader.exists(_path(key)):
		return load(_path(key)) as Texture2D
	var glyph := _glyph(key)
	if glyph == 0:
		push_warning("KeyHints: no cap can show key '%s'" % key)
		return null
	if not _glyph_caps.has(glyph):
		_glyph_caps[glyph] = GlyphCap.new(char(glyph))
	return _glyph_caps[glyph]


static func _path(key: String) -> String:
	return KEYBOARD % SPELLED.get(key, key)


## The character [param key] types, or 0. A key name is the character itself for an
## accented letter and a word for punctuation ("Period").
static func _glyph(key: String) -> int:
	var code := key.unicode_at(0) if key.length() == 1 else int(OS.find_keycode_from_string(key))
	if code <= KEY_SPACE or code >= KEY_SPECIAL:
		return 0
	return code if GlyphCap.FONT.has_char(code) else 0
