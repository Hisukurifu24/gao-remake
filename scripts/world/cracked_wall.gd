class_name CrackedWall
extends Interactable
## A crack in a field room's wall, with a hollow behind it: [b]interact[/b]
## and the rock gives way. A secret rather than a puzzle -- nothing points at it
## but the crack itself and the grit at its foot -- so it rewards looking.
##
## Until it breaks there is nothing behind it. The hollow is solid rock on the
## map, dressed like any other, so neither the camera seeing over the walls nor a
## gap in a forest gives it away; its chest is [member Chest.hidden_until] the
## wall breaks. Breaking it carves the doorway and the hollow and dresses round
## them ([method MapDresser.open_cells]). Broken stays broken ([member opened_flag]),
## and a map built after carves it again as it arrives, the same way.
##
## Where the wall is a forest the crack is in a boulder wedged among the trees,
## since a crack in a tree is not one.

const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")
const TILE := 16
## A crack across the two cells of rock facing the room, the near edge last
## (drawn for a north wall, and turned for the others):
## [code]#[/code] the split, [code]+[/code] its lit lip.
const CRACK := [
	"................................",
	"................................",
	"................................",
	"................................",
	"..............#.................",
	"...............#................",
	"...............##...............",
	"..........#.....#+..............",
	"...........#...##...............",
	"............#.##+...............",
	".............##+................",
	".............#+#................",
	"............##+.##..............",
	"...........##+....#.............",
	"..........##+......##...........",
	".........###+.......##..........",
]
## Grit fallen out of it, on the floor in front: [code]-[/code] a pebble's lit
## top, [code]o[/code] its body, [code]#[/code] its shadow.
const RUBBLE := [
	"......-o.........--.............",
	".....oo#........ooo#......-.....",
	"......##.......o###.......o#....",
]
const SPLIT := Color(0.09, 0.06, 0.1, 0.85)
const LIP := Color(1.0, 1.0, 1.0, 0.3)
## On rock too dark for a dark split to show -- a cave's or the volcanic band's
## crust seen from above, the castle's black -- the split is a pale seam instead.
const PALE_SPLIT := Color(0.62, 0.58, 0.56)
const PALE_LIP := Color(0.0, 0.0, 0.0, 0.0)
const DARK_ROCK := 0.25
const PEBBLE_LIT := Color(0.72, 0.69, 0.66)
const PEBBLE := Color(0.46, 0.43, 0.43)
const PEBBLE_SHADOW := Color(0.2, 0.17, 0.2)

## The rock between the room and the hollow, two cells square, in cells.
@export var door := Rect2i()
## The hollow behind it, in cells.
@export var hollow := Rect2i()
## Which way the doorway goes from the room: up for a crack in its north wall.
@export var side := Vector2i.UP
@export var opened_flag: StringName = &""
## Whether the wall is a forest, and the crack is in a boulder.
@export var in_trees := false

var _broken := false
var _split := SPLIT
var _lip := LIP


func _ready() -> void:
	z_index = -1
	var boulder := $Boulder as Sprite2D
	boulder.visible = in_trees
	boulder.position = Vector2(door.position * TILE) + Vector2(door.size * TILE) / 2.0 - position
	if is_opened():
		break_open()
	elif not in_trees and _rock_under_crack() < DARK_ROCK:
		_split = PALE_SPLIT
		_lip = PALE_LIP


func is_opened() -> bool:
	return opened_flag != &"" and GameState.has_flag(opened_flag)


func is_available() -> bool:
	return not _broken


func get_prompt() -> String:
	return "Examine the cracked %s" % _noun()


func interact(by: Node) -> void:
	super.interact(by)
	if _broken:
		return
	if opened_flag != &"":
		GameState.set_flag(opened_flag)
	_puff()
	break_open()
	Audio.play(&"crumble")
	Audio.play(&"solved")
	EventBus.message_requested.emit("", PackedStringArray([
		"The cracked %s gives under your hand and falls in." % _noun(),
		"There is a hollow behind it.",
	]))


func _noun() -> String:
	return "boulder" if in_trees else "wall"


## Carves the doorway and the hollow out of the map this stands on, and dresses
## round them. Sets no flag: [method interact] does that, and a map that loads
## already broken calls this from [method _ready].
func break_open() -> void:
	if _broken:
		return
	_broken = true
	var map := get_parent() as Node2D
	var ground := map.get_node("Ground") as TileMapLayer
	var walls := map.get_node("Walls") as TileMapLayer
	var cells: Array[Vector2i] = []
	for rect: Rect2i in [door, hollow]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
	MapDresser.open_cells(map, FloorRegistry.get_biome(int(map.get(&"floor_number"))),
			ground, walls, cells)
	($Boulder as Sprite2D).visible = false
	queue_redraw()
	if map.has_method(&"reshaped"):
		map.call(&"reshaped")


## The middle of the two cells of [param door] that face the room, map-local:
## where a cracked wall stands.
static func face_of(door: Rect2i, from_room: Vector2i) -> Vector2:
	var centre := Vector2(door.position * TILE) + Vector2(door.size * TILE) / 2.0
	return centre - Vector2(from_room) * TILE / 2.0


## The crack across the face, then the grit in front of it on the floor. The node
## stands at the middle of the two cells facing the room. A boulder stands
## upright whichever wall it is in, so its crack is drawn across its lower half.
func _draw() -> void:
	if not _broken:
		if in_trees:
			_paint(CRACK, 0, {"#": _split, "+": _lip}, Vector2i.UP,
					($Boulder as Sprite2D).position + Vector2(0, TILE / 2.0))
		else:
			_paint(CRACK, 0, {"#": _split, "+": _lip}, side, Vector2.ZERO)
	_paint(RUBBLE, CRACK.size(), {"-": PEBBLE_LIT, "o": PEBBLE, "#": PEBBLE_SHADOW}, side, Vector2.ZERO)


## How light the wall is under the crack's split, 0 to 1: the median luminance of
## the tile pixels its [code]#[/code]s land on -- the median, since a rock's lit
## rim runs through the black top a side crack lies on. 1 when it cannot tell.
func _rock_under_crack() -> float:
	var walls := get_parent().get_node_or_null("Walls") as TileMapLayer
	if walls == null:
		return 1.0
	var images := {}
	var lums: Array[float] = []
	for at in _pixels(CRACK, 0, "#", side, Vector2.ZERO):
		var point := position + at
		var cell := walls.local_to_map(point)
		var id := walls.get_cell_source_id(cell)
		if id == -1:
			continue
		var source := walls.tile_set.get_source(id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		if not images.has(source):
			var image := source.texture.get_image()
			if image != null and image.is_compressed():
				image.decompress()
			images[source] = image
		var image: Image = images[source]
		if image == null:
			continue
		var region := source.get_tile_texture_region(walls.get_cell_atlas_coords(cell))
		var inside := Vector2i((point - Vector2(cell * TILE)).floor())
		var colour := image.get_pixelv(region.position + inside.clamp(Vector2i.ZERO, region.size - Vector2i.ONE))
		lums.append(colour.get_luminance())
	if lums.is_empty():
		return 1.0
	lums.sort()
	return lums[lums.size() / 2]


## Where each [param mark] of a table lands -- the table laid out for a north
## wall, across and then towards the room, turned for a wall on [param wall_side]
## -- as pixel centres round [param centre].
func _pixels(rows: Array, first_row: int, mark: String, wall_side: Vector2i,
		centre: Vector2) -> Array[Vector2]:
	var towards := Vector2(-wall_side)
	var across := Vector2(absf(towards.y), absf(towards.x))
	var found: Array[Vector2] = []
	for v in rows.size():
		var row: String = rows[v]
		for u in row.length():
			if row[u] == mark:
				found.append(centre + across * (u - TILE + 0.5) + towards * (first_row + v - TILE / 2.0 + 0.5))
	return found


## Draws a table in [param colours], one per mark, as [method _pixels] lays it out.
func _paint(rows: Array, first_row: int, colours: Dictionary, wall_side: Vector2i,
		centre: Vector2) -> void:
	for mark: String in colours:
		for at in _pixels(rows, first_row, mark, wall_side, centre):
			draw_rect(Rect2(at - Vector2(0.5, 0.5), Vector2.ONE), colours[mark])


func _puff() -> void:
	var map := get_parent() as Node2D
	var across := Vector2(absf(side.y), absf(side.x)) * TILE / 2.0
	for at: Vector2 in [position - across, position + across]:
		var smoke := Sprite2D.new()
		smoke.texture = SMOKE
		smoke.hframes = SMOKE.get_width() / SMOKE.get_height()
		smoke.position = at
		smoke.z_index = 1
		map.add_child(smoke)
		var tween := smoke.create_tween()
		tween.tween_property(smoke, ^"frame", smoke.hframes - 1, 0.5)
		tween.tween_callback(smoke.queue_free)
