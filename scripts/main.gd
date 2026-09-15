extends Node
## Persistent shell around the game: HUD and the fade overlay live here, maps
## come and go inside WorldRoot. This is the project's main scene.
##
## Debug builds take a shortcut to any floor, for trying authored floors without
## climbing to them:
##     "$GODOT" --path . -- --floor=25             # at FloorTuning.enemy_level(25)
##     "$GODOT" --path . -- --floor=25 --level=30

@export var start_floor := 1

@onready var _world_root: Node2D = $WorldRoot


func _ready() -> void:
	SceneRouter.register_world_root(_world_root)
	var floor_number := start_floor
	if OS.is_debug_build():
		floor_number = _apply_debug_start()
	SceneRouter.enter_floor(floor_number)


## Reads [code]--floor=N[/code] and [code]--level=L[/code] from the user args.
## Clears every floor below N, since that is the only thing that unlocks it, and
## levels the player through [method GameState.grant_xp] so stats grow exactly as
## they would have on the way up. Returns the floor to enter.
func _apply_debug_start() -> int:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.substr(2).split("=", true, 1)
			args[pair[0]] = pair[1]
	if not args.has("floor"):
		return start_floor

	var floor_number := clampi(int(args["floor"]), 1, FloorTuning.TOP_FLOOR)
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	var target_level := int(args.get("level", FloorTuning.enemy_level(floor_number)))
	while GameState.level < target_level:
		GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp)
	GameState.heal_to_full()
	print("Debug start: floor %d at level %d" % [floor_number, GameState.level])
	return floor_number
