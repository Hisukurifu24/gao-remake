class_name GlyphCap
extends Texture2D
## A keycap the pack doesn't draw: its blank cap with a character written on it.
## The pack has letters, digits and the function keys, and a layout can put
## anything on a key -- Dvorak's physical E types a full stop. Being a texture, it
## goes wherever a pack cap does and nothing that shows one has to know.

## A cap to take the letter off, and the two colours that does it with.
const BLANK_FROM := "res://assets/ninja_adventure/Ui/Input/Keyboard/KeyE.png"
const LETTER := Color.WHITE
const FACE := Color("8d977f")
const FONT := preload("res://ui/theme/ui_font_strong.tres")
const FONT_SIZE := 10
## Where the cap's raised face is, inside its frame and above its lip.
const FACE_RECT := Rect2(1, 1, 11, 9)

static var _blank: Texture2D

var _text := ""


func _init(text := "") -> void:
	_text = text


static func _blank_cap() -> Texture2D:
	if _blank == null:
		var image := (load(BLANK_FROM) as Texture2D).get_image()
		image.decompress()
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).is_equal_approx(LETTER):
					image.set_pixel(x, y, FACE)
		_blank = ImageTexture.create_from_image(image)
	return _blank


func _get_width() -> int:
	return _blank_cap().get_width()


func _get_height() -> int:
	return _blank_cap().get_height()


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	_draw_rect(to_canvas_item, Rect2(pos, get_size()), false, modulate, transpose)


func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	_blank_cap().draw_rect(to_canvas_item, rect, tile, modulate, transpose)
	var scale := rect.size / get_size()
	var face := Rect2(rect.position + FACE_RECT.position * scale, FACE_RECT.size * scale)
	var size := roundi(FONT_SIZE * scale.y)
	var drawn := FONT.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := face.position + Vector2((face.size.x - drawn.x) / 2.0,
			(face.size.y - drawn.y) / 2.0 + FONT.get_ascent(size))
	FONT.draw_string(to_canvas_item, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LETTER * modulate)
