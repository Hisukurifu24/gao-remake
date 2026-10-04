class_name Campfire
extends Interactable
## The fire at the heart of a safe zone: rest by it and you are whole again.
##
## The zone itself -- monsters don't come in, or notice you while you are in it --
## is the map's ([member GameMap.safe_zones]); this is only what you do there.
## As often as you like: a safe zone in the labyrinth is where the front line
## camps between pushes, and that is what it is for.

const FPS := 10.0

var _time := 0.0

@onready var _flame: Sprite2D = $Flame


func _process(delta: float) -> void:
	_time += delta
	_flame.frame = int(_time * FPS) % _flame.hframes


func interact(by: Node) -> void:
	super.interact(by)
	if GameState.hp >= GameState.total_max_hp():
		_say("You warm your hands at the fire. You are already rested.")
		return
	GameState.heal_to_full()
	_say("You sit by the fire a while. Your wounds close.")


func _say(text: String) -> void:
	EventBus.message_requested.emit("", PackedStringArray([text]))
