class_name Brazier
extends Interactable
## One fire of a [BrazierRite]. It only knows whether it is lit: what lighting it
## means -- in time, in order, solved -- is the rite's, which listens for
## [signal Interactable.interacted].

const FPS := 10.0

## Which of its rite's braziers this is, for the order a tablet gives.
@export var index := 0

var lit := false

var _time := 0.0

@onready var _flame: Sprite2D = $Flame


func _ready() -> void:
	_flame.visible = lit


func _process(delta: float) -> void:
	if lit:
		_time += delta
		_flame.frame = int(_time * FPS) % _flame.hframes


func is_available() -> bool:
	return not lit


func set_lit(on: bool) -> void:
	lit = on
	if _flame:
		_flame.visible = on
		_flame.scale = Vector2.ONE


## How much of a timed rite's burn is left, 1 to 0: the flame sinks as it runs out.
func set_fuel(left: float) -> void:
	if _flame:
		_flame.scale = Vector2(1.0, lerpf(0.4, 1.0, clampf(left, 0.0, 1.0)))
