class_name TownBackdrop
extends Control
## The Town of Beginnings behind the title, dimmed and drifting: where every run
## starts, seen before it does.
##
## Only the town's tiles and its people's sprites are borrowed. The scene is
## instanced and taken apart before it ever enters the tree, so nothing in it --
## the map, the NPCs, the player -- runs a [code]_ready[/code] and nothing about the
## game is touched: no flags, no fog, no router. The rest is freed unused, and the
## borrowed layers are made unsolid -- see [method _ready].

const TOWN := "res://scenes/world/town.tscn"
## World pixels a second the view drifts along the town.
const DRIFT := 7.0
## How dark the town is drawn: enough for the menu to read over it.
const DIM := Color(0.42, 0.42, 0.5)

var _world: Node2D
var _span := Vector2.ZERO
var _from := Vector2.ZERO
var _time := 0.0
var _started := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node2D.new()
	_world.y_sort_enabled = true
	_world.modulate = DIM
	# Drawn as the map is, each world pixel UiLayout.WORLD_ZOOM units across.
	_world.scale = Vector2.ONE * UiLayout.WORLD_ZOOM
	add_child(_world)
	var town := (load(TOWN) as PackedScene).instantiate()
	var bounds := Rect2()
	for child in town.get_children():
		if child is TileMapLayer:
			var layer := child as TileMapLayer
			# A tile layer is solid wherever it is drawn: in the world's one
			# physics space, a CanvasLayer or not. Left on, the town's walls drift
			# through every map under the title, shoving the player about.
			layer.collision_enabled = false
			layer.navigation_enabled = false
			layer.occlusion_enabled = false
			town.remove_child(layer)
			layer.owner = null
			_world.add_child(layer)
			if layer.name == &"Ground":
				var used := layer.get_used_rect()
				bounds = Rect2(Vector2(used.position * 16), Vector2(used.size * 16))
		elif child.get(&"sprite_sheet") is Texture2D:
			_world.add_child(_figure(child as Node2D))
	town.free()
	_from = bounds.position
	_span = bounds.size


## A villager where they stand, facing down.
func _figure(npc: Node2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = npc.get(&"sprite_sheet")
	sprite.hframes = 4
	sprite.vframes = 7
	sprite.position = npc.position
	sprite.offset = Vector2(0, -8)
	return sprite


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var room := (_span - size / UiLayout.WORLD_ZOOM).max(Vector2.ZERO)
	if room == Vector2.ZERO:
		return
	# Out and back along the town, easing at either end, a slow sway up and down.
	var length := room.x / DRIFT
	# Start in the middle of the town rather than against its western trees.
	if not _started:
		_started = true
		_time = length * 0.5
	var phase := fmod(_time, length * 2.0) / length
	var along := phase if phase <= 1.0 else 2.0 - phase
	along = smoothstep(0.0, 1.0, along)
	var sway := 0.5 + 0.5 * sin(_time * 0.05)
	_world.position = -((_from + Vector2(room.x * along, room.y * (0.3 + 0.4 * sway))).round()
			* UiLayout.WORLD_ZOOM)
