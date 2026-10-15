extends Node
## Persistent shell around the game: HUD and the fade overlay live here, maps
## come and go inside WorldRoot. This is the project's main scene.
##
## Until the title screen exists, the game plays in save slot 1: it carries on
## from the save there, or starts a new game in it if there is none.
##     "$GODOT" --path .                           # continue slot 1
##     "$GODOT" --path . -- --slot=2               # continue slot 2
##     "$GODOT" --path . -- --slot=2 --new         # a new game, over slot 2's save
##
## Debug builds take a shortcut to any floor, for trying authored floors without
## climbing to them. A run started that way is never saved:
##     "$GODOT" --path . -- --floor=25             # at FloorTuning.enemy_level(25)
##     "$GODOT" --path . -- --floor=25 --level=30

@export var start_floor := 1

@onready var _world_root: Node2D = $WorldRoot


func _ready() -> void:
	SceneRouter.register_world_root(_world_root)
	var args := _user_args()
	var floor_number := start_floor
	if OS.is_debug_build() and args.has("floor"):
		floor_number = _apply_debug_start(args)
	elif get_tree().current_scene == self:
		if await _continue(args):
			return
	SceneRouter.enter_floor(floor_number)


## Picks the slot this game saves into and loads it if there is a save there.
## Returns whether it did. Only for the game proper -- a test or tool that
## instances this scene is not [member SceneTree.current_scene], and plays a run
## that saves nowhere, so the suite can never overwrite a player's save.
func _continue(args: Dictionary) -> bool:
	var chosen := clampi(int(args.get("slot", "1")), 1, SaveGame.SLOTS)
	if args.has("new") or not SaveGame.exists(chosen):
		SaveGame.slot = chosen
		return false
	if await SaveGame.load_slot(chosen):
		return true
	# Unreadable. Play, but not into that slot: the first autosave would destroy
	# whatever is left of it.
	push_error("Slot %d could not be loaded; this run will not be saved." % chosen)
	return false


## [code]--key=value[/code] user args as key -> value, and a bare
## [code]--key[/code] as key -> "".
func _user_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var pair := arg.substr(2).split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else ""
	return args


## Reads [code]--floor=N[/code] and [code]--level=L[/code] from the user args.
## Clears every floor below N, since that is the only thing that unlocks it, and
## levels the player through [method GameState.grant_xp] so stats grow exactly as
## they would have on the way up. Returns the floor to enter.
func _apply_debug_start(args: Dictionary) -> int:
	var floor_number := clampi(int(args["floor"]), 1, FloorTuning.TOP_FLOOR)
	for below in range(1, floor_number):
		GameState.clear_floor(below)
	var target_level := int(args.get("level", FloorTuning.enemy_level(floor_number)))
	while GameState.level < target_level:
		GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp)
	GameState.heal_to_full()
	print("Debug start: floor %d at level %d" % [floor_number, GameState.level])
	return floor_number
