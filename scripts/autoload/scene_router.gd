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
## How [member GameState.current_map_path] names a floor built by
## [FloorRegistry] rather than loaded from a scene: [code]floor://25[/code] -- and a
## dungeon's level above the first, [code]floor://25/3[/code].
const FLOOR_SCHEME := "floor://"

var _world_root: Node = null
var _fade: ColorRect
var _pending_spawn: StringName = &""
## Where a loaded game puts the player instead of a spawn point: see [method resume].
var _pending_place: Dictionary = {}
var _busy := false


func _ready() -> void:
	# Physics interpolation is on for what walks on ticks (monsters, a wisp, whoever
	# you are escorting) and off for everything else: the player and every camera
	# move on drawn frames, and an interpolated Camera2D is forced onto ticks. Here,
	# because the first camera (the title's backdrop) is up before the main scene is.
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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


## Whether a fade is under way: a map change, a blink or leaving for the title.
func is_busy() -> bool:
	return _busy


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
## [FloorRegistry] decides, and nothing here needs to know which it got. On a
## dungeon, [param level] is which of its maps; everywhere else there is one.
func enter_floor(floor_number: int, spawn: StringName = &"", fade_time := FADE_TIME,
		level := 1) -> void:
	floor_number = clampi(floor_number, 1, FloorTuning.TOP_FLOOR)
	if not GameState.is_floor_unlocked(floor_number):
		push_warning("SceneRouter: floor %d is still locked." % floor_number)
		return
	level = clampi(level, 1, FloorRegistry.levels_of(floor_number))
	await _transition(func() -> Node:
		return FloorRegistry.build_floor(floor_number, level)
	, spawn, floor_path(floor_number, level), fade_time)
	GameState.current_floor = floor_number
	floor_entered.emit(floor_number)


## How a floor's [param level] is named in [member GameState.current_map_path]: the
## first level is the floor itself, so a floor that became a dungeon is still
## [code]floor://n[/code] to every gate, defeat and save that knew it before.
static func floor_path(floor_number: int, level := 1) -> String:
	if level <= 1:
		return FLOOR_SCHEME + str(floor_number)
	return "%s%d/%d" % [FLOOR_SCHEME, floor_number, level]


## [method floor_path] read back: (floor, level).
static func floor_at(path: String) -> Vector2i:
	var parts := path.trim_prefix(FLOOR_SCHEME).split("/")
	return Vector2i(int(parts[0]), int(parts[1]) if parts.size() > 1 else 1)


## Goes back to [param map_path] -- a scene, or a [constant FLOOR_SCHEME] floor --
## and puts the player at [param position] (map-local) facing [param facing]
## rather than on a spawn point. A loaded game's way in. If the map has changed
## under the spot since, [GameMap] falls back to its default spawn; if the path
## names nothing, the player goes to the current floor's entrance.
func resume(map_path: String, position: Vector2, facing: Vector2, fade_time := FADE_TIME) -> void:
	_pending_place = {"position": position, "facing": facing}
	if map_path.begins_with(FLOOR_SCHEME):
		var at := floor_at(map_path)
		await enter_floor(at.x, &"", fade_time, at.y)
	elif map_path != "" and ResourceLoader.exists(map_path):
		await change_map(map_path, &"", fade_time)
	else:
		push_warning("SceneRouter: no map at '%s'; resuming at floor %d's entrance"
				% [map_path, GameState.current_floor])
		_pending_place = {}
		await enter_floor(GameState.current_floor, &"", fade_time)
	# Taken by the map, normally. Cleared anyway, so a resume refused mid-transition
	# never leaks into the next map change.
	_pending_place = {}


## Fades out, runs [param action], fades back in -- a move within a map that
## should not be watched, such as a trap's teleport. Holds the input lock.
func blink(action: Callable, fade_time := FADE_TIME) -> void:
	if _busy:
		action.call()
		return
	_busy = true
	GameState.push_input_lock()
	await _fade_to(1.0, fade_time)
	action.call()
	await get_tree().process_frame
	await _fade_to(0.0, fade_time)
	GameState.pop_input_lock()
	_busy = false


## Fades out of the map onto nothing: the way back to the title. [param action]
## runs in the dark once the map is gone -- the title putting itself up -- so the
## fade back in shows it. Holds the input lock throughout.
func leave(action := Callable(), fade_time := FADE_TIME) -> void:
	if _busy:
		return
	_busy = true
	GameState.push_input_lock()
	await _fade_to(1.0, fade_time)
	if _world_root != null:
		for child in _world_root.get_children():
			_world_root.remove_child(child)
			child.queue_free()
	if action.is_valid():
		action.call()
	await get_tree().process_frame
	await _fade_to(0.0, fade_time)
	GameState.pop_input_lock()
	_busy = false


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


## Maps call this in _ready() after [method consume_spawn]: where a loaded game
## stood ([code]position[/code], [code]facing[/code]), or empty for any other
## arrival.
func consume_placement() -> Dictionary:
	var place := _pending_place
	_pending_place = {}
	return place


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
