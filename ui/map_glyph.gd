class_name MapGlyph
extends Control
## The map's symbols: tiny pixel drawings in ink, one per kind of thing.
##
## A glyph is a table like the font's -- [code]#[/code] its colour, [code]+[/code]
## ink, anything else empty -- and every empty pixel touching a drawn one is inked
## too, so each symbol carries its own outline and reads on any ground. Pixels are
## one unit, half a world pixel: a symbol is 9 units across, a little more than a
## map cell, which is what a map pin should be.
##
## As a Control it draws one glyph, for the legend; [method paint] is the same
## drawing for [MapView], which places many.

enum Kind { YOU, DOOR, EXIT, CHEST, PERSON, QUEST, CAMP, PUZZLE, COL }

const PIXEL := 1.0

## Drawn pointing up; [method paint] turns it to the player's facing.
const YOU := [
	"...#...",
	"..###..",
	".#####.",
	"#######",
	"..###..",
	"..###..",
	"..###..",
]
const DOOR := [
	".#####.",
	"#######",
	"#++#++#",
	"#++#++#",
	".##+##.",
	".#####.",
	".#.#.#.",
]
const EXIT := [
	".....##",
	".....##",
	"...####",
	"...####",
	".######",
	".######",
	"#######",
]
const CHEST := [
	".#####.",
	"#######",
	"+++++++",
	"###+###",
	"#######",
	"#######",
]
const PERSON := [
	"..###..",
	".#####.",
	"..###..",
	"...#...",
	".#####.",
	"#######",
	"#######",
]
## A fire on crossed logs: a safe zone.
const CAMP := [
	"...#...",
	"..##...",
	"..###..",
	".####..",
	".#####.",
	"+.+.+.+",
	".+++++.",
]
## A glint: something here to work out.
const PUZZLE := [
	"...#...",
	"...#...",
	"..###..",
	"#######",
	"..###..",
	"...#...",
	"...#...",
]
## A tied purse: the Col you dropped where you fell. Not in the legend -- it is
## rare, and the map's status line says what it is whenever one is down.
const COL := [
	".+...+.",
	"..+++..",
	"...#...",
	"..###..",
	".##+##.",
	"#######",
	".#####.",
]
const QUEST := [
	"###",
	"###",
	"###",
	"###",
	".#.",
	"...",
	"###",
]

@export var kind := Kind.YOU:
	set(value):
		kind = value
		queue_redraw()
@export var colour := Color.WHITE:
	set(value):
		colour = value
		queue_redraw()


func _get_minimum_size() -> Vector2:
	return measure(kind)


func _draw() -> void:
	paint(self, kind, size / 2.0, colour)


## Size in units, outline included.
static func measure(glyph: Kind) -> Vector2:
	var rows := table(glyph)
	return Vector2(rows[0].length() + 2, rows.size() + 2) * PIXEL


static func table(glyph: Kind) -> Array:
	match glyph:
		Kind.DOOR: return DOOR
		Kind.EXIT: return EXIT
		Kind.CHEST: return CHEST
		Kind.PERSON: return PERSON
		Kind.QUEST: return QUEST
		Kind.CAMP: return CAMP
		Kind.PUZZLE: return PUZZLE
		Kind.COL: return COL
	return YOU


## Draws [param glyph] onto [param canvas] centred on [param centre], snapped to
## the unit grid. [param facing] turns [constant YOU]; the rest ignore it.
static func paint(canvas: CanvasItem, glyph: Kind, centre: Vector2, colour: Color,
		facing := Vector2i.UP) -> void:
	var rows := table(glyph)
	var grid := Vector2i(rows[0].length(), rows.size())
	var cells: Dictionary[Vector2i, bool] = {}  # pixel -> drawn in colour
	for y in grid.y:
		for x in grid.x:
			var mark: String = rows[y][x]
			if mark == "#" or mark == "+":
				cells[_turn(Vector2i(x, y), grid, facing)] = mark == "#"
	if facing.x != 0:
		grid = Vector2i(grid.y, grid.x)
	var corner := ((centre - Vector2(grid + Vector2i(2, 2)) * PIXEL / 2.0) / PIXEL).round() * PIXEL
	for y in range(-1, grid.y + 1):
		for x in range(-1, grid.x + 1):
			var at := Vector2i(x, y)
			var ink := not cells.has(at) and _touches(cells, at)
			if not ink and not cells.has(at):
				continue
			var tone := UiPalette.MAP_OUTLINE if ink or not cells[at] else colour
			canvas.draw_rect(Rect2(corner + Vector2(at + Vector2i.ONE) * PIXEL,
					Vector2(PIXEL, PIXEL)), tone)


static func _turn(at: Vector2i, grid: Vector2i, facing: Vector2i) -> Vector2i:
	match facing:
		Vector2i.DOWN: return Vector2i(at.x, grid.y - 1 - at.y)
		Vector2i.LEFT: return Vector2i(at.y, at.x)
		Vector2i.RIGHT: return Vector2i(grid.y - 1 - at.y, at.x)
	return at


static func _touches(cells: Dictionary[Vector2i, bool], at: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if cells.has(at + Vector2i(dx, dy)):
				return true
	return false
