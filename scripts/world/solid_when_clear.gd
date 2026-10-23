class_name SolidWhenClear
extends Node
## Turns a body's collision on once the player isn't standing in it.
##
## Something that appears in play -- a sealed chest when its puzzle is solved, a
## settler fading in -- can appear where the player is. Made solid at once it
## closes round them, and where it stands against something else solid there is
## no way out: a wisp's sealed chest appears a cell below its shrine, which is
## exactly where you stood to watch the wisp sink in, and the lantern is above.
## So it is drawn at once and only made solid when the player has stepped off it.
## Until then it can be walked through, which nobody will notice.

## The player's physics layer (2).
const PLAYER_MASK := 1 << 1

var _solid: CollisionObject2D


## Watches [param solid] until no player overlaps it, then enables its shapes.
static func attach(solid: CollisionObject2D) -> void:
	var watcher := SolidWhenClear.new()
	watcher.name = "SolidWhenClear"
	watcher._solid = solid
	solid.add_child(watcher)


func _physics_process(_delta: float) -> void:
	if _player_inside():
		return
	for shape in _solid.get_children():
		if shape is CollisionShape2D:
			(shape as CollisionShape2D).set_deferred(&"disabled", false)
	queue_free()


func _player_inside() -> bool:
	var space := _solid.get_world_2d().direct_space_state
	for shape in _solid.get_children():
		var collider := shape as CollisionShape2D
		if collider == null or collider.shape == null:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = collider.shape
		query.transform = collider.global_transform
		query.collision_mask = PLAYER_MASK
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false
