class_name Statue
extends Interactable
## One stone figure of a [StatueRing]. It only knows which way it faces: what
## turning it means -- its neighbours turning with it, the ring solved -- is the
## ring's, which listens for [signal Interactable.interacted].

## Facings, clockwise from north. [b]interact[/b] turns a statue one step on.
enum Facing { NORTH, EAST, SOUTH, WEST }

## The pack's walk sheet draws down, up, left, right across its columns.
const COLUMN: Array[int] = [1, 3, 0, 2]
## How long a quarter turn takes to draw: a shudder, then the new face.
const TURN_TIME := 0.18

## Which of its ring's statues this is.
@export var index := 0
@export var facing := Facing.NORTH

var _turning: Tween

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_sprite.frame = COLUMN[facing]


func face(to: int, animate := true) -> void:
	facing = posmod(to, 4) as Facing
	if _sprite == null:
		return
	if not animate:
		_sprite.frame = COLUMN[facing]
		return
	if _turning:
		_turning.kill()
	_turning = create_tween()
	_turning.tween_property(_sprite, "position:x", 1.0, TURN_TIME / 4.0)
	_turning.tween_property(_sprite, "position:x", -1.0, TURN_TIME / 4.0)
	_turning.tween_callback(func() -> void: _sprite.frame = COLUMN[facing])
	_turning.tween_property(_sprite, "position:x", 0.0, TURN_TIME / 2.0)
