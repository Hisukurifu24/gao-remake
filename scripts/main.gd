extends Node
## Persistent shell around the game: HUD and the fade overlay live here, maps
## come and go inside WorldRoot. This is the project's main scene.

@export var start_floor := 1

@onready var _world_root: Node2D = $WorldRoot


func _ready() -> void:
	SceneRouter.register_world_root(_world_root)
	SceneRouter.enter_floor(start_floor)
