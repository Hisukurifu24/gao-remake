class_name StatueAltar
extends Interactable
## The orb a [StatueRing] stands round: dark until every statue faces it, lit for
## good once [member solved_flag] is set.

const DARK := Rect2(48, 32, 16, 16)
const LIT := Rect2(80, 32, 16, 16)

@export var solved_flag: StringName = &""

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_show(is_lit())
	if not is_lit():
		EventBus.flag_changed.connect(_on_flag_changed)


func is_lit() -> bool:
	return solved_flag != &"" and GameState.has_flag(solved_flag)


func is_available() -> bool:
	return not is_lit()


func interact(by: Node) -> void:
	super.interact(by)
	EventBus.message_requested.emit("", PackedStringArray([
		"A dark orb on a pedestal. The statues round it look everywhere but at it.",
		"They are heavy, but they turn -- and not one at a time.",
	]))


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag == solved_flag and is_lit():
		EventBus.flag_changed.disconnect(_on_flag_changed)
		_show(true)


func _show(lit: bool) -> void:
	(_sprite.texture as AtlasTexture).region = LIT if lit else DARK
