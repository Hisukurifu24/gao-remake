class_name Duellist
extends Npc
## A player in the camp calling out anyone who'll cross blades ([FloorEvents]): a
## first-strike duel, their gear against your Col.
##
## Accept, and once the box is closed they stake it out where you stand: the duel
## is fought on the map like any fight ([method GameMap.stage_battle]), the
## duellist stepping up to their mark as a boss steps out of its door. It ends the
## moment either of you is down to half what you came in with
## ([member Encounter.first_strike]) -- nobody dies in a duel, and nothing is won
## in one but the wager. Lose and the stake is theirs; ask again and they'll take
## another. Win and their wager is yours, and they won't ask again.
##
## Unless it is rigged ([method FloorEvents.is_rigged]): decided either way, they
## won't yield, and a paralysis pick turns it into a fight to the end
## ([member Encounter.betrayal]). Beaten, they crush a crystal and are gone; beat
## you, and you are robbed as player killers rob you, or worse, in a hardcore game.
## Either way they are gone for good -- an orange cursor doesn't hang about a camp.
##
## Not solid, as nobody an event puts down is.

## How long they take to walk up to their mark.
const STEP_UP_TIME := 0.45
const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")

@export var floor_number := 0

var _figure: FoeFigure = null


func _ready() -> void:
	super._ready()
	for shape in $Solid.get_children():
		(shape as CollisionShape2D).disabled = true
	# Accepted, then saved before the duel began: nothing was staked yet.
	GameState.set_flag(FloorEvents.flag(floor_number, "duel_accepted"), false)


func is_available() -> bool:
	return super.is_available() and _figure == null


func interact(by: Node) -> void:
	await super.interact(by)
	var accepted := FloorEvents.flag(floor_number, "duel_accepted")
	if not GameState.has_flag(accepted):
		return
	GameState.set_flag(accepted, false)
	var who := FloorEvents.duellist(floor_number)
	var wager := ItemLibrary.get_item(who["wager"])
	var refusal := ""
	if GameState.hp * 2 < GameState.total_max_hp():
		refusal = "Not like that. You're half-dead already -- rest up, and come back when you can make a fight of it."
	elif wager != null and not Inventory.fits(wager):
		refusal = "Make room in your pack first. I'm not having my %s left lying in the dirt." % wager.label()
	elif not GameState.can_afford(FloorEvents.stake(floor_number)):
		refusal = "That's not %d col. Come back when it is." % FloorEvents.stake(floor_number)
	if not refusal.is_empty():
		EventBus.message_requested.emit(display_name, PackedStringArray([refusal]))
		return
	GameState.spend_col(FloorEvents.stake(floor_number))
	await _duel(by as Player)


func _duel(player: Player) -> void:
	var map := get_parent() as GameMap
	if map == null or player == null:
		return
	var rigged := FloorEvents.is_rigged(floor_number)
	var encounter := Bestiary.duel_encounter(floor_number, display_name, sprite_sheet, rigged)
	_figure = FoeFigure.new(encounter.enemies[0], false)
	_figure.position = position
	visible = false
	map.add_child(_figure)
	var field := map.stage_battle(map.to_local(player.global_position), position, 1)
	if field != null:
		field.enemy_nodes.append(_figure)
		_figure.face(field.player_spot - field.enemy_spots[0])
		if CombatManager.step_delay > 0.0:
			GameState.push_input_lock()
			var step := create_tween()
			step.tween_property(_figure, ^"position", field.enemy_spots[0], STEP_UP_TIME) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await step.finished
			GameState.pop_input_lock()
		else:
			_figure.position = field.enemy_spots[0]
		EventBus.battle_staged.emit(field)
	var result: CombatResult = await CombatManager.start(encounter)
	if is_instance_valid(_figure):
		_figure.queue_free()
	_figure = null
	if result == null:
		visible = true
		return
	if result.betrayed:
		_betrayed(map, result)
	else:
		_settled(result)


## An honest duel, decided -- or, fifty rounds on, not.
func _settled(result: CombatResult) -> void:
	visible = true
	var stake := FloorEvents.stake(floor_number)
	if result.victory:
		var who := FloorEvents.duellist(floor_number)
		var wager := ItemLibrary.get_item(who["wager"])
		GameState.set_flag(FloorEvents.flag(floor_number, "duel"))
		EventBus.col_granted.emit(stake)
		EventBus.item_granted.emit(who["wager"], 1)
		EventBus.message_requested.emit(display_name, PackedStringArray([
			"...Fair's fair. A good duel -- the %s is yours, and your col back with it." % (
					wager.label() if wager != null else String(who["wager"])),
		]))
	elif result.yielded:
		EventBus.message_requested.emit(display_name, PackedStringArray([
			"Good fight. Your col's mine, though. Come back whenever you want it back.",
		]))
	else:
		EventBus.col_granted.emit(stake)
		EventBus.message_requested.emit(display_name, PackedStringArray([
			"We'd be here all day. Call it a draw -- keep your col.",
		]))


## They turned on you; win or lose, they are gone.
func _betrayed(map: GameMap, result: CombatResult) -> void:
	GameState.set_flag(FloorEvents.flag(floor_number, "duel"))
	_puff()
	queue_free()
	if result.victory:
		var who := FloorEvents.duellist(floor_number)
		EventBus.col_granted.emit(FloorEvents.stake(floor_number))
		EventBus.item_granted.emit(who["wager"], 1)
		EventBus.message_requested.emit("", PackedStringArray([
			"%s crushes a teleport crystal and is gone, cursor orange and all." % display_name,
			"What they staked lies where they stood -- and your col with it.",
		]))
		return
	if result.fled or result.stalemate:
		EventBus.message_requested.emit("", PackedStringArray([
			"Behind you, %s laughs, crushes a teleport crystal, and is gone -- with your col." % display_name,
		]))
		return
	if SaveGame.end_if_fatal():
		return
	GameState.set_hp(maxi(1, roundi(GameState.total_max_hp() * 0.35)))
	var lines := PackedStringArray([
		"%s leaves you lying there, still twitching, and walks off laughing with your col." % display_name,
	])
	var spilled := map.player_fell()
	if spilled > 0:
		lines.append("Your purse spills as you go down -- %d col lies where you fell." % spilled)
	EventBus.message_requested.emit("", lines)


func _puff() -> void:
	if CombatManager.step_delay <= 0.0 or get_parent() == null:
		return
	var smoke := Sprite2D.new()
	smoke.texture = SMOKE
	smoke.hframes = SMOKE.get_width() / SMOKE.get_height()
	smoke.position = position + Vector2(0, -8)
	get_parent().add_child(smoke)
	var tween := smoke.create_tween()
	tween.tween_property(smoke, ^"frame", smoke.hframes - 1, 0.5)
	tween.tween_callback(smoke.queue_free)
