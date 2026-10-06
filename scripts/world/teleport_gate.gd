class_name TeleportGate
extends Interactable
## A floor's teleport gate: touch it and go to any floor you have stood on.
##
## One stands where each floor is arrived at -- a generated floor's entrance, a
## settlement's square -- and one in the Town of Beginnings' plaza, which is how
## the town stays the hub for the whole climb. Arriving through one puts you at
## its map's [code]gate[/code] spawn, in front of it.
##
## The gate only asks: [signal EventBus.teleport_requested] is answered by the
## gate menu, which knows the floors and does the sending. The gate knows its own
## floor and nothing else.

## How long one slow breath of the crystal's glow takes, in seconds.
const PULSE_TIME := 2.4
## How far above plain the glow brightens at the top of a breath.
const PULSE_GLOW := 0.25

@export var floor_number := 1

var _time := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _process(delta: float) -> void:
	_time += delta
	var breath := 0.5 - 0.5 * cos(TAU * _time / PULSE_TIME)
	_sprite.self_modulate = Color(1, 1, 1).lerp(Color(1.0 + PULSE_GLOW, 1.0 + PULSE_GLOW,
			1.0 + PULSE_GLOW), breath)


func interact(by: Node) -> void:
	super.interact(by)
	if GameState.visited_floors().size() <= 1:
		EventBus.message_requested.emit("", PackedStringArray([
			"The crystal hums under your hand. It knows no floor but this one -- yet.",
		]))
		return
	EventBus.teleport_requested.emit(floor_number)
