class_name Landmark
extends Interactable
## A floor's set piece ([FloorLandmarks]): a great tree, a memorial, a ruined arch,
## or the sign by a lake -- read (or looked at) with [b]interact[/b].
##
## Only the drawing and the words live here. What makes it solid is its footprint,
## painted on the map's [code]Walls[/code] in the biome's invisible
## [member BiomeKit.wall_alt_tile] as a house's is, so the floor test's flood fills see
## it like any rock. Its pieces are sprites cut from the pack's sheets, each standing
## on the bottom edge of the cells it covers and sorted from there, so you walk
## behind a crown or an arch as you do behind a roof.

## What it says when read: its words, in [method EventBus.message_requested]'s lines.
@export_multiline var lines: PackedStringArray = PackedStringArray()
## Which [enum FloorLandmarks.Kind] it is.
@export var kind := 0
## The cells its pieces are drawn over, in tiles: whoever stands there is drawn behind
## it, so no place to stage a fight ([method GameMap.is_covered]).
@export var cover: Array[Rect2i] = []

const TILE := 16


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	y_sort_enabled = true
	prompt_verb = "Read"


func interact(by: Node) -> void:
	super.interact(by)
	EventBus.message_requested.emit("", lines)


## Where the prompt is offered from: [param area] in tiles, round [member position].
func reach(area: Rect2i) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(area.size * TILE) + Vector2(6, 6)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(area.position * TILE) + Vector2(area.size * TILE) / 2.0 - position
	add_child(collision)


## Stands [param region] of [param sheet], drawn [param scale] times over, on the
## cells of [param rect] (in tiles): centred across it and standing on its bottom
## edge, which is where it sorts from. [param covers] adds the cells it is drawn over
## to [member cover]; a flat piece of scatter doesn't.
func add_piece(sheet: Texture2D, region: Rect2i, rect: Rect2i, scale := 1, covers := true) -> Sprite2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(region)
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.scale = Vector2(scale, scale)
	sprite.offset = Vector2(-region.size.x / 2.0, -region.size.y)
	sprite.position = Vector2((rect.position.x + rect.size.x / 2.0) * TILE, rect.end.y * TILE) - position
	add_child(sprite)
	if covers:
		var drawn := region.size * scale
		var cells := Vector2i(ceili(drawn.x / float(TILE)), ceili(drawn.y / float(TILE)))
		cover.append(Rect2i(Vector2i(rect.position.x + (rect.size.x - cells.x) / 2,
				rect.end.y - cells.y), cells))
	return sprite
