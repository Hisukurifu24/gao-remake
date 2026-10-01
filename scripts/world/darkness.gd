class_name Darkness
extends Sprite2D
## The dark over a labyrinth: what you cannot see from where you stand, drawn.
##
## Everywhere else fog of war decides only what is *explored*; the camera sees
## over walls. That is fine in a field and fatal in a maze -- a maze you can read
## from outside is a corridor with extra steps. So inside [member area] the cells
## out of line of sight are covered: black where you have never looked, dimmed
## where you have, clear where you can see now.
##
## One texel a cell, scaled up and filtered linearly, so the edge of what you see
## is a soft torchlit falloff rather than a staircase of squares, and the light
## follows you by fading rather than jumping a cell at a time.

const SHADE := Color(0.02, 0.02, 0.05)
## Never seen: as good as black, with a breath of the wall mass left showing.
const UNSEEN := 0.97
## Seen before, out of sight now: the map you remember, not the one in front of you.
const REMEMBERED := 0.62
## Alpha per second. Fast enough that the light keeps up with a walking player.
const FADE_RATE := 5.0

## The cells covered, in map cells. The texture is one cell bigger all round and
## that border stays clear, so the dark softens off where it meets the field --
## except off the map's edge, where a clear border would light the edge row.
var area := Rect2i()

var _image: Image
var _texture: ImageTexture
var _target := PackedFloat32Array()
var _current := PackedFloat32Array()
## Texel indices still fading towards their target.
var _moving: Dictionary[int, bool] = {}
## Inner texel -> the border texels off the map's edge that copy it.
var _mirrors: Dictionary[int, PackedInt32Array] = {}
var _width := 0


## [param map_bounds] is the whole map in cells, to tell the area's edges that
## meet the field from the ones that meet nothing.
func setup(cells: Rect2i, tile_size: Vector2i, map_bounds: Rect2i) -> void:
	area = cells
	var texels := cells.size + Vector2i(2, 2)
	_width = texels.x
	_image = Image.create(texels.x, texels.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(SHADE, 0.0))
	_target.resize(texels.x * texels.y)
	_target.fill(0.0)
	_current = _target.duplicate()
	for y in range(-1, cells.size.y + 1):
		for x in range(-1, cells.size.x + 1):
			var local := Vector2i(x, y)
			if map_bounds.has_point(cells.position + local):
				continue
			var inner := _index(local.clamp(Vector2i.ZERO, cells.size - Vector2i.ONE))
			# Packed arrays come out of a Dictionary by value: append, then put back.
			var borders: PackedInt32Array = _mirrors.get(inner, PackedInt32Array())
			borders.append(_index(local))
			_mirrors[inner] = borders
	for y in cells.size.y:
		for x in cells.size.x:
			_set_now(_index(Vector2i(x, y)), UNSEEN)
	_texture = ImageTexture.create_from_image(_image)
	texture = _texture
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(tile_size)
	position = Vector2((cells.position - Vector2i.ONE) * tile_size)
	# Over everything on the map -- props, monsters, the door -- and under the UI.
	z_index = 10


## [param lit] is what the player sees now, [param explored] everything they
## have seen on this map. [param snap] skips the fade, for the first look on arrival.
func light(lit: Array[Vector2i], explored: Dictionary, snap := false) -> void:
	var now: Dictionary[int, bool] = {}
	for cell in lit:
		if area.has_point(cell):
			now[_index(cell - area.position)] = true
	for y in area.size.y:
		for x in area.size.x:
			var index := _index(Vector2i(x, y))
			var alpha := 0.0
			if not now.has(index):
				alpha = REMEMBERED if explored.has(area.position + Vector2i(x, y)) else UNSEEN
			if snap:
				_set_now(index, alpha)
			elif _target[index] != alpha or _current[index] != alpha:
				_target[index] = alpha
				_moving[index] = true
	if snap:
		_texture.update(_image)


## How lit a cell is, 0 (dark, or only remembered) to 1 (in plain sight) -- what a
## monster standing there should be drawn at. Outside [member area], always 1.
func light_at(cell: Vector2i) -> float:
	if not area.has_point(cell):
		return 1.0
	return clampf(1.0 - _current[_index(cell - area.position)] / REMEMBERED, 0.0, 1.0)


func _process(delta: float) -> void:
	if _moving.is_empty():
		return
	var step := FADE_RATE * delta
	for index: int in _moving.keys():
		var alpha := move_toward(_current[index], _target[index], step)
		_set_now(index, alpha, false)
		if alpha == _target[index]:
			_moving.erase(index)
	_texture.update(_image)


## Texel index of a cell given relative to [member area]'s corner.
func _index(local: Vector2i) -> int:
	return (local.y + 1) * _width + local.x + 1


func _set_now(index: int, alpha: float, retarget := true) -> void:
	_current[index] = alpha
	if retarget:
		_target[index] = alpha
		_moving.erase(index)
	_image.set_pixel(index % _width, index / _width, Color(SHADE, alpha))
	for border in _mirrors.get(index, PackedInt32Array()):
		_image.set_pixel(border % _width, border / _width, Color(SHADE, alpha))
