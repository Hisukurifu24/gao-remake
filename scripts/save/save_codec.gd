class_name SaveCodec
extends RefCounted
## How the save writes the things JSON has no word for.
##
## The save is JSON so that it stays readable and survives an engine upgrade, and
## JSON knows numbers, strings, lists and maps. The one thing the game keeps a lot
## of that is none of those is a set of cells -- what fog of war has seen and
## walked on every map -- and written as a list of pairs, a hundred explored floors
## come to megabytes. As a bitmap over the set's bounding rect, base64'd, a floor is
## a kilobyte or two.

## Past this many cells in one rect a bitmap is refused on the way in: a corrupt
## width is not allowed to allocate the machine. The biggest generated floor is a
## few hundred cells a side.
const MAX_AREA := 4_000_000


## [param cells] (cell -> anything, as [GameState] keeps them) as a bitmap: an
## empty dictionary for an empty set.
static func encode_cells(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for cell: Vector2i in cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	var size := hi - lo + Vector2i.ONE
	var bits := PackedByteArray()
	bits.resize((size.x * size.y + 7) >> 3)
	for cell: Vector2i in cells:
		var i := (cell.y - lo.y) * size.x + (cell.x - lo.x)
		bits[i >> 3] |= 1 << (i & 7)
	return {"x": lo.x, "y": lo.y, "w": size.x, "h": size.y,
			"bits": Marshalls.raw_to_base64(bits)}


## The inverse of [method encode_cells]. Anything malformed decodes to an empty
## set rather than half a map.
static func decode_cells(data: Variant) -> Dictionary:
	var cells := {}
	if not data is Dictionary or (data as Dictionary).is_empty():
		return cells
	var origin := Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
	var width := int(data.get("w", 0))
	var height := int(data.get("h", 0))
	if width <= 0 or height <= 0 or width * height > MAX_AREA:
		return cells
	var bits := Marshalls.base64_to_raw(str(data.get("bits", "")))
	if bits.size() < (width * height + 7) >> 3:
		return cells
	for i in width * height:
		if bits[i >> 3] & (1 << (i & 7)):
			@warning_ignore("integer_division")
			cells[origin + Vector2i(i % width, i / width)] = true
	return cells


## A JSON number back as the int it was written as. [JSON] reads every number as
## a float; an id or a count that comes back 3.0 compares unequal to 3 in a
## [Dictionary] key.
static func whole(value: Variant, fallback := 0) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


## Flags are bools today, but [method GameState.set_flag] takes any value, and a
## number written as 2 must not come back 2.0.
static func plain(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 9.0e15:
		return int(value)
	return value
