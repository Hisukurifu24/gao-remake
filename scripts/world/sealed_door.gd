class_name SealedDoor
extends Interactable
## A vault's door: fitted stone across a doorway, with a hollow in it for each
## sigil the floor hides. Collect them all -- each is a flag a chest sets as it
## opens -- and [b]interact[/b] opens it for good.
##
## Solid while shut, which is all that keeps you out: the doorway behind it is
## open floor, so the floor test's flood fill reaches the vault and the chest in it
## either way, and walls round the vault are joined like any other.

const SIGIL_HELD := Rect2(32, 32, 16, 16)
const SIGIL_EMPTY := Rect2(96, 32, 16, 16)
const LOGIC := preload("res://assets/ninja_adventure/Backgrounds/Tilesets/TilesetLogic.png")
const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")

## The flags of the sigils that open it, one hollow each.
@export var sigils: Array[StringName] = []
@export var opened_flag: StringName = &""

var _marks: Array[Sprite2D] = []

@onready var _stone: Node2D = $Stone


func _ready() -> void:
	for i in sigils.size():
		var mark := Sprite2D.new()
		var region := AtlasTexture.new()
		region.atlas = LOGIC
		mark.texture = region
		# Half size: a texel is still whole screen pixels at the map's zoom.
		mark.scale = Vector2(0.5, 0.5)
		# Four hollows close up a pixel, to stay on the door's 32.
		var pitch := 9.0 if sigils.size() <= 3 else 8.0
		mark.position = Vector2((i - (sigils.size() - 1) / 2.0) * pitch, 2.0)
		_stone.add_child(mark)
		_marks.append(mark)
	_refresh()
	if is_opened():
		_show_open()
	else:
		# A hollow lights the moment its sigil is picked up, wherever that was.
		EventBus.flag_changed.connect(_on_flag_changed)


func is_opened() -> bool:
	return opened_flag != &"" and GameState.has_flag(opened_flag)


func is_available() -> bool:
	return not is_opened()


func held() -> int:
	var count := 0
	for sigil in sigils:
		if GameState.has_flag(sigil):
			count += 1
	return count


func interact(by: Node) -> void:
	super.interact(by)
	_refresh()
	var have := held()
	if have < sigils.size():
		var hollows := "all of them empty" if have == 0 else "%d of them glowing" % have
		_say("A door of fitted stone, sealed. %s hollows are cut into it, %s." % [
				_count_word(sigils.size()).capitalize(), hollows],
				"Somewhere on this floor are the sigils that fit them.")
		return
	if opened_flag != &"":
		GameState.set_flag(opened_flag)
	_say("The sigils sink into the stone one by one, and the seal breaks.")
	var tween := create_tween()
	tween.tween_property(_stone, ^"modulate:a", 0.0, 0.5)
	_puff()
	await tween.finished
	_show_open()


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag in sigils:
		_refresh()


func _show_open() -> void:
	_stone.visible = false
	for shape in $Solid.get_children():
		(shape as CollisionShape2D).set_deferred(&"disabled", true)


func _refresh() -> void:
	for i in _marks.size():
		(_marks[i].texture as AtlasTexture).region = \
				SIGIL_HELD if GameState.has_flag(sigils[i]) else SIGIL_EMPTY


func _puff() -> void:
	var smoke := Sprite2D.new()
	smoke.texture = SMOKE
	smoke.hframes = SMOKE.get_width() / SMOKE.get_height()
	add_child(smoke)
	var tween := smoke.create_tween()
	tween.tween_property(smoke, ^"frame", smoke.hframes - 1, 0.5)
	tween.tween_callback(smoke.queue_free)


func _say(text: String, more := "") -> void:
	var lines := PackedStringArray([text])
	if not more.is_empty():
		lines.append(more)
	EventBus.message_requested.emit("", lines)


static func _count_word(count: int) -> String:
	return ["no", "one", "two", "three", "four", "five"][clampi(count, 0, 5)]
