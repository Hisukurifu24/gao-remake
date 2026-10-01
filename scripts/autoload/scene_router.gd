extends Node
## Map transitions with a fade.
##
## The running scene is always [code]scenes/main.tscn[/code]; maps are swapped
## in and out of its WorldRoot rather than via [method SceneTree.change_scene_to_file],
## so HUD, autoload-driven UI and the fade overlay survive a transition.
##
## A map asks to leave by name of the *spawn point* it wants to arrive at:
##     SceneRouter.change_map("res://scenes/world/field.tscn", &"from_town")

signal map_changed(map_path: String)
signal floor_entered(floor_number: int)

const FADE_TIME := 0.25

var _world_root: Node = null
var _fade: ColorRect
var _pending_spawn: StringName = &""
var _busy := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TransitionLayer"
	layer.layer = 128
	add_child(layer)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called by Main once, so the router knows where maps go.
func register_world_root(node: Node) -> void:
	_world_root = node


func change_map(map_path: String, spawn: StringName = &"", fade_time := FADE_TIME) -> void:
	if not ResourceLoader.exists(map_path):
		push_error("SceneRouter: map does not exist: %s" % map_path)
		return
	await _transition(func() -> Node:
		return (load(map_path) as PackedScene).instantiate()
	, spawn, map_path, fade_time)


## Travels to a floor of Aincrad. The floor may be authored or generated --
## [FloorRegistry] decides, and nothing here needs to know which it got.
func enter_floor(floor_number: int, spawn: StringName = &"", fade_time := FADE_TIME) -> void:
	floor_number = clampi(floor_number, 1, FloorTuning.TOP_FLOOR)
	if not GameState.is_floor_unlocked(floor_number):
		push_warning("SceneRouter: floor %d is still locked." % floor_number)
		return
	await _transition(func() -> Node:
		return FloorRegistry.build_floor(floor_number)
	, spawn, "floor://%d" % floor_number, fade_time)
	GameState.current_floor = floor_number
	floor_entered.emit(floor_number)


## The map the player is on, or null between maps. For views that draw it --
## the map screen -- and nothing that should be changing it.
func current_map() -> Node:
	if _world_root == null or _world_root.get_child_count() == 0:
		return null
	return _world_root.get_child(0)


## Maps call this in _ready() to learn which spawn point to use.
## Returns &"" on a cold boot, meaning "use the map's default".
func consume_spawn() -> StringName:
	var spawn := _pending_spawn
	_pending_spawn = &""
	return spawn


func _transition(build_map: Callable, spawn: StringName, path_hint: String, fade_time: float) -> void:
	if _busy:
		return
	if _world_root == null:
		push_error("SceneRouter: no world root registered; call register_world_root() first.")
		return

	_busy = true
	_pending_spawn = spawn
	GameState.push_input_lock()

	await _fade_to(1.0, fade_time)

	for child in _world_root.get_children():
		_world_root.remove_child(child)
		child.queue_free()

	var map: Node = build_map.call()
	if map == null:
		push_error("SceneRouter: failed to build map for %s" % path_hint)
		GameState.pop_input_lock()
		_busy = false
		return

	_world_root.add_child(map)
	GameState.current_map_path = path_hint
	map_changed.emit(path_hint)

	# Let the new map's _ready() place the player before revealing it.
	await get_tree().process_frame

	await _fade_to(0.0, fade_time)
	GameState.pop_input_lock()
	_busy = false


func _fade_to(alpha: float, duration: float) -> void:
	_fade.visible = true
	_fade.modulate.a = 1.0 - alpha
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, duration)
	await tween.finished
	_fade.visible = alpha > 0.0
