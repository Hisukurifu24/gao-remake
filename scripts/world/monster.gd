extends Interactable
## A monster standing on the map, waiting to be picked a fight with.
##
## Visible and avoidable rather than a random encounter: you can see what is on
## the floor, walk around what you don't want, and choose what you do. It has no
## solid body, so a monster can never wall off a corridor -- being unavoidable is
## the one thing a wandering enemy must not be.
##
## Beaten monsters are gone for the rest of the visit and back on the next one.
## Deliberately *not* a [GameState] flag like a chest: a chest holds one reward
## and a monster holds levels, and a player who has hit a wall needs somewhere
## to earn them.

@export var enemy: EnemyType
## The level it fights at. 0 means "whatever this floor's monsters are".
@export var level := 0
@export var floor_number := 0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if enemy == null:
		push_error("Monster at %s has no EnemyType." % global_position)
		queue_free()
		return
	_sprite.texture = enemy.battler
	if display_name.is_empty():
		display_name = enemy.label()


func interact(by: Node) -> void:
	super.interact(by)
	var encounter := Bestiary.single_encounter(enemy, _level(), floor_number)
	var result: CombatResult = await CombatManager.start(encounter)
	if result == null:
		return

	if result.victory:
		queue_free()
		return
	if result.fled:
		# It stays where it is, and so do you. Walk around it this time.
		return
	_knock_out()


func get_prompt() -> String:
	return "Fight %s (Lv %d)" % [display_name, _level()]


func _level() -> int:
	if level > 0:
		return level
	return FloorTuning.enemy_level(maxi(1, floor_number))


## Losing to a roaming monster costs HP and nothing else -- no reload, no lost
## progress. The monster is still standing there, which is punishment enough.
func _knock_out() -> void:
	GameState.set_hp(maxi(1, roundi(GameState.total_max_hp() * 0.35)))
	EventBus.message_requested.emit("", PackedStringArray([
		"%s knocks you flat. You crawl out of reach." % display_name,
	]))
