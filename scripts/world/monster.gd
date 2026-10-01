class_name Monster
extends Interactable
## A monster living on the map: it drifts round where it spawned, notices you,
## gives chase, and starts the fight when it reaches you.
##
## Still avoidable, which is the rule M4 built monsters on: it is slower than the
## player, it gives up past a leash, and it has no solid body. It collides with
## walls by asking the physics space where it may step, but nothing can collide
## with *it*, so a monster can never wall off a corridor and the floor test's
## flood fill never has to know it exists.
##
## Pressing [b]interact[/b] on one is still a way in, and doing it before it has
## noticed you wins the first round. Being caught facing the other way loses it.
## That is all decided here and handed over as [member Encounter.opening] --
## [CombatManager] never learns what a map is.
##
## Beaten monsters are gone for the rest of the visit and back on the next one.
## Deliberately *not* a [GameState] flag like a chest: a chest holds one reward
## and a monster holds levels, and a player who has hit a wall needs somewhere
## to earn them.
##
## Wandering uses the global RNG on purpose: this is behaviour, not generation,
## and nothing about a floor's layout or save depends on where a boar drifted.

enum State { WANDER, CHASE, RETURN, STUNNED }

const WANDER_SPEED := 22.0
## Below [member Player.speed] (90), so a chase can always be outrun.
const CHASE_SPEED := 62.0
const RETURN_SPEED := 40.0
## How far from its spawn point it drifts while nothing is going on.
const WANDER_RADIUS := 40.0
const AGGRO_RADIUS := 72.0
## A chase ends when the player is this far away...
const LOSE_RADIUS := 120.0
## ...or the monster is this far from home...
const LEASH_RADIUS := 176.0
## ...or it has not seen the player for this long.
const LOSE_SIGHT_SECONDS := 1.0
## After a fight it survived (you fled, or it knocked you flat): stunned in
## place, then walks home without looking at you.
const GRACE_SECONDS := 3.0
## After *any* fight ends, every monster ignores the player briefly, so winning
## one fight never drops you straight into the next. Longer than the combat
## screen's outro (1.1s), which covers the map while the player can already move:
## a calm that ran out under it let you walk blind into a fight.
const CALM_SECONDS := 2.0
const ALERT_SECONDS := 0.6
## The probe it steps with. Smaller than a tile so it fits the one-wide gaps an
## authored floor is allowed to have.
const BODY_RADIUS := 5.0
## Where its feet are relative to its origin; walls are tested from here.
const FOOT := Vector2(0, -4)
const WALK_FPS := 8.0

@export var enemy: EnemyType
## The level it fights at. 0 means "whatever this floor's monsters are".
@export var level := 0
@export var floor_number := 0

var state := State.WANDER
var home := Vector2.ZERO

var _goal := Vector2.ZERO
var _leg_time := 0.0
var _rest := 0.0
var _unseen := 0.0
var _stun := 0.0
var _calm := 0.0
var _alert := 0.0
var _walk_time := 0.0
var _fighting := false
var _probe := CircleShape2D.new()
var _facing_column := 0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _contact: Area2D = $Contact
@onready var _alert_label: Label = $Alert
@onready var _sprite_rest := _sprite.position


func _ready() -> void:
	if enemy == null:
		push_error("Monster at %s has no EnemyType." % global_position)
		queue_free()
		return
	_show_sprite()
	if display_name.is_empty():
		display_name = enemy.label()
	_probe.radius = BODY_RADIUS
	home = global_position
	_goal = home
	_rest = randf_range(0.0, 2.0)
	CombatManager.combat_finished.connect(_on_any_combat_finished)


func _physics_process(delta: float) -> void:
	# Nothing moves or engages through the lock: not in dialogue, a menu, a fade,
	# or while a fight -- this one's or any other -- is running.
	if _fighting or GameState.is_input_locked():
		return
	_calm = maxf(0.0, _calm - delta)
	_tick_alert(delta)

	var player := _player()
	var start := global_position
	match state:
		State.STUNNED:
			_stun -= delta
			_sprite.visible = int(_stun * 10.0) % 2 == 0
			if _stun <= 0.0:
				_sprite.visible = true
				_set_state(State.RETURN)
		State.RETURN:
			_leg_time += delta
			if _step_toward(home, RETURN_SPEED, delta) or _leg_time > 6.0:
				_set_state(State.WANDER)
		State.WANDER:
			if _notices(player):
				_set_state(State.CHASE)
			else:
				_wander(delta)
		State.CHASE:
			if _loses(player, delta):
				_set_state(State.RETURN)
			else:
				_step_toward(player.global_position, CHASE_SPEED, delta)
	_animate(global_position - start, delta)

	if _touching(player):
		_engage(_contact_opening(player))


func interact(by: Node) -> void:
	super.interact(by)
	# Struck before it noticed you: yours is the first round.
	var opening := Encounter.Opening.NORMAL
	if state != State.CHASE:
		opening = Encounter.Opening.PARTY_FIRST
	_engage(opening)


func is_available() -> bool:
	return not _fighting and state != State.STUNNED


func get_prompt() -> String:
	var verb := "Fight" if state == State.CHASE else "Ambush"
	return "%s %s (Lv %d)" % [verb, display_name, _level()]


## Starts the fight and settles the monster's side of how it went.
func _engage(opening: Encounter.Opening) -> void:
	if _fighting or CombatManager.is_running():
		return
	_fighting = true
	var encounter := Bestiary.single_encounter(enemy, _level(), floor_number)
	encounter.opening = opening
	_stage(encounter)
	var result: CombatResult = await CombatManager.start(encounter)
	_fighting = false
	if result == null:
		return

	if result.victory:
		queue_free()
		return
	if not result.fled:
		_knock_out()
	# Either way you are standing on it. Give you the room to leave.
	_stun = GRACE_SECONDS
	_set_state(State.STUNNED)


## Asks the map where the fight can stand and announces it, so the view fights
## it where you are. Nowhere to stand leaves it to the battle screen.
func _stage(encounter: Encounter) -> void:
	var map := get_parent() as GameMap
	var player := _player()
	if map == null or player == null:
		return
	var field := map.stage_battle(map.to_local(player.global_position),
			map.to_local(global_position), encounter.enemies.size())
	if field == null:
		return
	field.enemy_nodes = [self]
	EventBus.battle_staged.emit(field)


## The sprite a fight on the map lunges and flashes.
func sprite() -> Sprite2D:
	return _sprite


## Turns to look along [param direction] -- a fight on the map facing you.
func face(direction: Vector2) -> void:
	if enemy.sheet == null:
		return
	if enemy.sheet_frames.y == 1:
		if absf(direction.x) > 0.01:
			_sprite.flip_h = direction.x < 0.0
		_sprite.frame = 0
		return
	_facing_column = _column_for(direction)
	_sprite.frame = _facing_column


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


# --- behaviour -------------------------------------------------------------

func _set_state(next: State) -> void:
	state = next
	_leg_time = 0.0
	_unseen = 0.0
	if next == State.CHASE:
		_alert = ALERT_SECONDS
	elif next == State.WANDER:
		_goal = global_position
		_rest = randf_range(0.5, 1.5)


func _wander(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta
		return
	_leg_time += delta
	var arrived := _step_toward(_goal, WANDER_SPEED, delta)
	# A leg that runs into a wall is given up on rather than pushed at forever.
	if arrived or _leg_time > 3.0:
		_goal = home + Vector2.from_angle(randf() * TAU) * randf() * WANDER_RADIUS
		_leg_time = 0.0
		_rest = randf_range(1.0, 3.0)


func _notices(player: Player) -> bool:
	if player == null or _calm > 0.0:
		return false
	var offset := player.global_position - global_position
	return offset.length() <= AGGRO_RADIUS and _can_see(player)


func _loses(player: Player, delta: float) -> bool:
	if player == null:
		return true
	if global_position.distance_to(player.global_position) > LOSE_RADIUS:
		return true
	if global_position.distance_to(home) > LEASH_RADIUS:
		return true
	_unseen = 0.0 if _can_see(player) else _unseen + delta
	return _unseen > LOSE_SIGHT_SECONDS


func _touching(player: Player) -> bool:
	if player == null or _calm > 0.0:
		return false
	if state != State.WANDER and state != State.CHASE:
		return false
	return _contact.overlaps_body(player)


## Walking into its face is an even fight; being run down from behind is not.
func _contact_opening(player: Player) -> Encounter.Opening:
	if state != State.CHASE:
		return Encounter.Opening.NORMAL
	var toward := global_position - player.global_position
	if toward.length() > 0.001 and player.facing.dot(toward.normalized()) < 0.0:
		return Encounter.Opening.ENEMIES_FIRST
	return Encounter.Opening.NORMAL


func _on_any_combat_finished(_result: CombatResult) -> void:
	_calm = CALM_SECONDS


# --- movement --------------------------------------------------------------

## Moves toward [param target]. Returns true once it is there.
func _step_toward(target: Vector2, speed: float, delta: float) -> bool:
	var offset := target - global_position
	if offset.length() <= 2.0:
		return true
	_move(offset.limit_length(speed * delta))
	return false


## Tries the whole step, then each axis alone, so it slides along a wall
## rather than sticking to it.
func _move(motion: Vector2) -> void:
	for step: Vector2 in [motion, Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]:
		if step != Vector2.ZERO and _free_at(global_position + step):
			global_position += step
			return


func _free_at(point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _probe
	query.transform = Transform2D(0.0, point + FOOT)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _can_see(player: Player) -> bool:
	var query := PhysicsRayQueryParameters2D.create(
			global_position + FOOT, player.global_position + FOOT, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _player() -> Player:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.is_queued_for_deletion():
		return null
	return player


# --- presentation ----------------------------------------------------------

## Pack art arrives drawn at map scale with its feet at the bottom of the frame;
## a lone battler is the old 64px placeholder, halved.
func _show_sprite() -> void:
	if enemy.sheet == null:
		_sprite.texture = enemy.battler
		return
	_sprite.texture = enemy.sheet
	_sprite.hframes = enemy.sheet_frames.x
	_sprite.vframes = enemy.sheet_frames.y
	_sprite.scale = Vector2.ONE
	_sprite.position = Vector2(0.0, -enemy.sheet.get_height() / (2.0 * enemy.sheet_frames.y))
	_sprite_rest = _sprite.position


## A walk sheet animates by facing; a lone battler just hops.
func _animate(motion: Vector2, delta: float) -> void:
	var moving := motion != Vector2.ZERO
	_walk_time = _walk_time + delta if moving else 0.0
	if enemy.sheet == null:
		var hop := absf(sin(_walk_time * 12.0)) * 2.0
		_sprite.position = _sprite_rest - Vector2(0.0, hop)
		return
	var step := int(_walk_time * WALK_FPS) if moving else 0
	if enemy.sheet_frames.y == 1:
		# A side view: drawn facing right, mirrored to walk left.
		if absf(motion.x) > 0.01:
			_sprite.flip_h = motion.x < 0.0
		_sprite.frame = step % enemy.sheet_frames.x
		return
	if moving:
		_facing_column = _column_for(motion)
	_sprite.frame = (step % enemy.sheet_frames.y) * enemy.sheet_frames.x + _facing_column


## down, up, left, right -- the pack's column order.
func _column_for(motion: Vector2) -> int:
	if absf(motion.x) > absf(motion.y):
		return 2 if motion.x < 0.0 else 3
	return 1 if motion.y < 0.0 else 0


func _tick_alert(delta: float) -> void:
	_alert = maxf(0.0, _alert - delta)
	_alert_label.visible = _alert > 0.0
