class_name BattleStage
extends Node2D
## A fight drawn on the map it happens on.
##
## Added to the map by the combat view when a [BattleField] is staged, and gone
## when the fight is: it steps the fighters into formation, eases a camera onto
## them, and plays every blow on the real sprites -- the lunge, the flash, the
## numbers, the shake. A view like every other: it listens to [CombatManager]
## and decides nothing.
##
## Who stands in for an enemy is the caller's business: a roaming [Monster], or
## a [FoeFigure] a [BossGate] stepped out of its door. Either answers
## [code]sprite()[/code] and [code]face()[/code], and that is all this asks.

const ARROW := preload("res://assets/ninja_adventure/Ui/Arrow.png")
const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")
const SMOKE_FRAMES := 6
const SMOKE_FRAME_TIME := 0.07
## Over whoever sits out round 1: the side the other caught off guard.
const ALARM := preload("res://assets/ninja_adventure/Ui/Emote/emote22.png")
const ALARM_TIME := 1.2
## Each status a fighter wears shows this long before the next takes its turn.
const EMOTE_HOLD := 0.9
## Anything drunk or eaten mid-fight lands like a heal.
const ITEM_FX := preload("res://resources/fx/sparkle.tres")
## The pointer hangs this far over the top of the enemy's sprite and bobs this much.
const POINTER_LIFT := 1.0
const POINTER_BOB := 1.0
## A number pops this far over the top of whoever it lands on.
const FLOATER_LIFT := 10.0

const FLOATER_RISE := 10.0
const FLOATER_TIME := 0.7
## Whoever acts steps this far towards the other side and back.
const LUNGE := 6.0
const LUNGE_TIME := 0.09
const FLASH := Color(2.4, 2.4, 2.4)
const FLASH_TIME := 0.12
const SHAKE := 2.0
const SHAKE_TIME := 0.24
## Stepping into formation and the camera easing onto it. Inside the runner's
## opening pause (one step_delay, 0.55s), which nothing waits for.
const INTRO_TIME := 0.35
const OUTRO_EASE := 0.45
## Over the labyrinth's dark (z 10), so a number never pops behind it.
const OVER_DARK := 20
## The menu and the message line take the bottom of the screen, so the fight is
## framed this many screen units above centre -- half the band they cover.
const FRAME_LIFT := 12.0
## What the camera keeps clear over the tallest head, in world units: the
## pointer, and the bob it hangs with.
const HEADROOM := 12.0
## How far round each fighter the dark lifts, in cells.
const LIGHT_RADIUS := 4
## Anyone else in frame stands back to this, so a frozen boar at the edge of the
## fight doesn't read as a second enemy.
const BYSTANDER_ALPHA := 0.25

## How far the camera closes in on a fight that fits: 2 frames 160x90 of world.
## A fight that doesn't is drawn at 1, the UI's own scale (see [method fits]).
const ZOOM := 2.0
## The screen the fighters may cover, in screen units: all of it across, and
## above the band the menus take.
const CLOSE_ROOM := Vector2(320, 180.0 - FRAME_LIFT * 2.0)

var field: BattleField

var _camera: Camera2D
var _player_camera: Camera2D
## Enemy [Combatant] to the map node standing in for it.
var _nodes: Dictionary[Combatant, Node2D] = {}
var _bars: Dictionary[Combatant, ProgressBar] = {}
var _player: Combatant = null
## The bubble over each fighter's head, and who is showing the opening's alarm.
var _emotes: Dictionary[Combatant, Sprite2D] = {}
var _alarmed: Array[Combatant] = []
## Counts [constant EMOTE_HOLD]s, so a fighter wearing two statuses shows each in turn.
var _emote_beat := 0
var _shake: Tween = null
var _bystanders: Array[Sprite2D] = []
var _pointer: Sprite2D
var _bob: Tween = null
## The zoom this fight is framed at: [constant ZOOM], or 1 if it doesn't fit.
var _zoom := 1.0


func _init(staged: BattleField) -> void:
	field = staged
	name = "BattleStage"
	z_index = OVER_DARK


func _ready() -> void:
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.action_resolved.connect(_on_action_resolved)
	CombatManager.combat_finished.connect(_on_combat_finished)
	_pointer = Sprite2D.new()
	_pointer.texture = ARROW
	_pointer.visible = false
	add_child(_pointer)


func _on_combat_began(_encounter: Encounter, party: Array[Combatant],
		enemies: Array[Combatant]) -> void:
	_player = party[0] if not party.is_empty() else null
	for i in mini(enemies.size(), field.enemy_nodes.size()):
		_nodes[enemies[i]] = field.enemy_nodes[i]
	_step_into_formation()
	_fade_bystanders()
	_build_bars()
	_close_in()
	_build_emotes()
	var dark := field.map.darkness()
	if dark != null:
		dark.light_arena(_pool_of_light())


## What the fighters can see from where they stand, a little way round each.
func _pool_of_light() -> Array[Vector2i]:
	var lit: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in field.enemy_cells + [field.player_cell]:
		for seen in FogOfWar.visible_from(cell, LIGHT_RADIUS, field.map.blocks_sight):
			lit[seen] = true
	var cells: Array[Vector2i] = []
	cells.assign(lit.keys())
	return cells


## Every other monster within a screen of the fight. Its sprite, not the node:
## the map sets a monster's own alpha from the dark.
func _fade_bystanders() -> void:
	var frame := field.arena.grow(160.0)
	for child in field.map.get_children():
		var monster := child as Monster
		if monster == null or monster in field.enemy_nodes or not frame.has_point(monster.position):
			continue
		var sprite := monster.sprite()
		_bystanders.append(sprite)
		sprite.create_tween().tween_property(sprite, "modulate:a", BYSTANDER_ALPHA, INTRO_TIME)


func _step_into_formation() -> void:
	var axis := Vector2(field.axis)
	var player := field.player
	player.facing = axis
	var paced := CombatManager.step_delay > 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if paced:
		tween.tween_property(player, "position", field.player_spot, INTRO_TIME)
	else:
		player.position = field.player_spot
	for i in field.enemy_nodes.size():
		var node := field.enemy_nodes[i]
		if node.has_method(&"face"):
			node.call(&"face", -axis)
		if paced:
			tween.tween_property(node, "position", field.enemy_spots[i], INTRO_TIME)
		else:
			node.position = field.enemy_spots[i]
	if not paced:
		tween.kill()


func _close_in() -> void:
	_player_camera = field.player.get_node_or_null("Camera2D") as Camera2D
	_camera = Camera2D.new()
	_camera.name = "BattleCamera"
	if _player_camera != null:
		_camera.limit_left = _player_camera.limit_left
		_camera.limit_top = _player_camera.limit_top
		_camera.limit_right = _player_camera.limit_right
		_camera.limit_bottom = _player_camera.limit_bottom
		_camera.position = field.map.to_local(_player_camera.get_screen_center_position())
	field.map.add_child(_camera)
	_camera.make_current()
	_zoom = ZOOM if fits(field.bodies.size, ZOOM) else 1.0
	# The box fits was asked about, centred in the room above the menus: lifted
	# in screen units, so the same at either zoom.
	var framed := field.bodies.grow_side(SIDE_TOP, HEADROOM)
	var target := framed.get_center() + Vector2(0, FRAME_LIFT / _zoom)
	if CombatManager.step_delay <= 0.0:
		_camera.position = target
		_camera.zoom = Vector2.ONE * _zoom
		return
	var glide := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glide.tween_property(_camera, "position", target, INTRO_TIME)
	glide.tween_property(_camera, "zoom", Vector2.ONE * _zoom, INTRO_TIME)


## Whether fighters covering [param bodies] of the world, with the pointer's
## [constant HEADROOM] over them, can be framed at [param at_zoom] without
## anyone leaving the screen or standing under the menus. Every monster fight
## three cells apart fits at 2; one stood four apart one above the other does
## not, nor does a boss a cell taller than you faced up or down the screen.
static func fits(bodies: Vector2, at_zoom: float) -> bool:
	var drawn := (bodies + Vector2(0, HEADROOM)) * at_zoom
	return drawn.x <= CLOSE_ROOM.x and drawn.y <= CLOSE_ROOM.y


## Small bars under each enemy -- the screen's panels are gone, and an enemy's
## health has to be read off the field.
func _build_bars() -> void:
	for enemy in _nodes:
		# A boss's bar is as long as it is big, within reason.
		var width := 32.0 if _width_of(_nodes[enemy]) > 24.0 else 16.0
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(width, 3)
		bar.size = Vector2(width, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		bar.position = field.enemy_spots[field.enemy_nodes.find(_nodes[enemy])] + Vector2(-width / 2.0, 2)
		_bars[enemy] = bar
		_refresh_bar(enemy)


func _refresh_bar(enemy: Combatant) -> void:
	var bar := _bars.get(enemy) as ProgressBar
	if bar == null:
		return
	bar.value = enemy.hp_ratio() * 100.0
	UiPalette.paint_bar(bar, UiPalette.hp_color(enemy.hp_ratio()))
	bar.visible = enemy.is_alive()


func _on_action_resolved(report: CombatReport) -> void:
	if report.kind == CombatReport.Kind.OPENING:
		_alarm(report.actor)
	var striker := _sprite_of(report.actor)
	var strikes := report.kind == CombatReport.Kind.SKILL and report.hits.any(
			func(hit: CombatReport.Hit) -> bool: return hit.target.is_player != report.actor.is_player)
	if striker == null or not strikes or CombatManager.step_delay <= 0.0:
		_land(report)
		return
	var toward := Vector2(field.axis) * LUNGE * (1.0 if report.actor.is_player else -1.0)
	if report.actor.is_player:
		field.player.pose_row = Player.ATTACK_ROW
	var home := striker.position
	var step := striker.create_tween()
	step.tween_property(striker, "position", home + toward, LUNGE_TIME)
	step.tween_callback(_land.bind(report))
	step.tween_property(striker, "position", home, LUNGE_TIME * 1.5)
	if report.actor.is_player:
		step.tween_callback(func() -> void: field.player.pose_row = -1)


func _land(report: CombatReport) -> void:
	var heavy := false
	var fx := _fx_of(report)
	var swing := Vector2(field.axis) * (1.0 if report.actor != null and report.actor.is_player else -1.0)
	for hit in report.hits:
		if fx != null and not hit.missed:
			_play_fx(fx, hit.target, swing)
		_float_number(hit)
		if hit.amount < 0:
			_flash(hit.target)
			heavy = heavy or hit.crit or hit.staggered
	if heavy:
		_shake_camera()
	for touched in report.touched():
		if not touched.is_player:
			_refresh_bar(touched)
			if not touched.is_alive():
				_fall(touched)
	_refresh_emotes()


## What [param report]'s blow looks like where it lands, or null. A monster's
## plain attack is its own -- a boar claws, it doesn't cut.
func _fx_of(report: CombatReport) -> SkillFx:
	if report.kind == CombatReport.Kind.ITEM:
		return ITEM_FX
	if report.kind != CombatReport.Kind.SKILL or report.skill == null:
		return null
	var source := report.actor.source if report.actor != null else null
	if report.skill == SkillLibrary.basic_attack() and source != null and source.strike_fx != null:
		return source.strike_fx
	return report.skill.fx


## Plays [param fx] once over [param target]'s body. A cut is mirrored or turned
## a quarter to follow [param swing] -- by whole quarters, so no texel is
## resampled -- and a boss's is drawn bigger, by a whole number.
func _play_fx(fx: SkillFx, target: Combatant, swing: Vector2) -> void:
	if fx.sheet == null or CombatManager.step_delay <= 0.0:
		return
	var over := _node_of(target)
	var burst := Sprite2D.new()
	burst.texture = fx.sheet
	burst.hframes = maxi(1, fx.frames)
	var size := maxf(1.0, floorf(_width_of(over) / 24.0))
	burst.scale = Vector2(size, size)
	if fx.follows_swing:
		if field.axis.x != 0:
			burst.flip_h = swing.x < 0.0
		else:
			burst.rotation = PI / 2.0 * signf(swing.y)
	burst.position = _spot_of(target) + Vector2(0, -roundf(_height_of(over) / 2.0))
	add_child(burst)
	var play := burst.create_tween()
	play.tween_property(burst, "frame", burst.hframes - 1, fx.frame_time * burst.hframes).from(0)
	play.tween_callback(burst.queue_free)


# --- emotes ------------------------------------------------------------------

## A bubble over every fighter's head, hidden until it has something to say,
## and the beat that turns a second status's bubble over.
func _build_emotes() -> void:
	var fighters: Array[Combatant] = []
	fighters.assign(_nodes.keys())
	if _player != null:
		fighters.append(_player)
	for fighter in fighters:
		var bubble := Sprite2D.new()
		bubble.centered = false
		bubble.visible = false
		add_child(bubble)
		_emotes[fighter] = bubble
	if CombatManager.step_delay > 0.0:
		var beat := Timer.new()
		beat.wait_time = EMOTE_HOLD
		beat.autostart = true
		beat.timeout.connect(func() -> void:
			_emote_beat += 1
			_refresh_emotes())
		add_child(beat)
	CombatManager.turn_began.connect(_on_turn_began)


## Statuses age at the start of a turn, sometimes without a report to say so.
func _on_turn_began(_actor: Combatant) -> void:
	_refresh_emotes()


## [param striker]'s side struck first: the other side gets the alarm.
func _alarm(striker: Combatant) -> void:
	if striker == null or CombatManager.step_delay <= 0.0:
		return
	for fighter in _emotes:
		if fighter.is_player != striker.is_player:
			_alarmed.append(fighter)
	_refresh_emotes()
	create_tween().tween_callback(func() -> void:
		_alarmed.clear()
		_refresh_emotes()).set_delay(ALARM_TIME)


func _refresh_emotes() -> void:
	for fighter in _emotes:
		var bubble := _emotes[fighter]
		var shown: Texture2D = null
		if fighter.is_alive():
			if fighter in _alarmed:
				shown = ALARM
			else:
				var worn: Array[Texture2D] = []
				for active in fighter.statuses:
					if active.effect.emote != null:
						worn.append(active.effect.emote)
				if not worn.is_empty():
					shown = worn[_emote_beat % worn.size()]
		bubble.visible = shown != null
		if shown == null:
			continue
		bubble.texture = shown
		# The bubble's tail at the top corner of the head, clear of the pointer
		# and the numbers over its middle.
		var over := _node_of(fighter)
		bubble.position = (_spot_of(fighter) + Vector2(
				roundf(_width_of(over) / 4.0), -_height_of(over) - shown.get_height())).round()


## A felled monster goes out in the pack's puff of smoke where it stands; the
## node frees itself when the fight returns. The puff is the stage's, so it
## outlives the monster.
func _fall(enemy: Combatant) -> void:
	var sprite := _sprite_of(enemy)
	if sprite == null:
		return
	if CombatManager.step_delay <= 0.0:
		sprite.modulate.a = 0.0
		return
	var fade := sprite.create_tween()
	fade.tween_interval(FLASH_TIME)
	fade.tween_property(sprite, "modulate:a", 0.0, SMOKE_FRAME_TIME * 2)
	var puff := Sprite2D.new()
	puff.texture = SMOKE
	puff.hframes = SMOKE_FRAMES
	# A boss goes up in a bigger puff, by a whole number so it stays crisp.
	var size := maxf(1.0, floorf(_width_of(_nodes.get(enemy)) / 24.0))
	puff.scale = Vector2(size, size)
	puff.position = _spot_of(enemy) + Vector2(0, -4 * size)
	puff.visible = false
	add_child(puff)
	var play := puff.create_tween()
	play.tween_interval(FLASH_TIME)
	play.tween_callback(puff.show)
	play.tween_property(puff, "frame", SMOKE_FRAMES - 1, SMOKE_FRAME_TIME * SMOKE_FRAMES).from(0)
	play.tween_callback(puff.queue_free)


## Hangs the pointer over [param target], or takes it away for null -- answering
## [signal BattleHud.aimed].
func aim(target: Combatant) -> void:
	if _bob != null:
		_bob.kill()
		_bob = null
	var node := _nodes.get(target) as Node2D if target != null else null
	_pointer.visible = node != null
	if node == null:
		return
	var over := node.position + Vector2(0, -_height_of(node) - POINTER_LIFT)
	_pointer.position = over
	if CombatManager.step_delay <= 0.0:
		return
	# Stepped, not slid: a whole unit up and back, so it never lands between texels.
	_bob = _pointer.create_tween().set_loops()
	_bob.tween_interval(0.3)
	_bob.tween_callback(_pointer.set_position.bind(over + Vector2(0, -POINTER_BOB)))
	_bob.tween_interval(0.3)
	_bob.tween_callback(_pointer.set_position.bind(over))


func _on_combat_finished(_result: CombatResult) -> void:
	# This stage was for one fight. The camera still has to ease home, and the
	# next fight -- the door, straight after a monster -- may start before it does.
	CombatManager.combat_began.disconnect(_on_combat_began)
	CombatManager.action_resolved.disconnect(_on_action_resolved)
	CombatManager.combat_finished.disconnect(_on_combat_finished)
	if CombatManager.turn_began.is_connected(_on_turn_began):
		CombatManager.turn_began.disconnect(_on_turn_began)
	for bubble in _emotes.values():
		bubble.hide()
	field.player.pose_row = -1
	aim(null)
	var dark := field.map.darkness()
	if dark != null:
		dark.light_arena([] as Array[Vector2i])
	if _camera == null or CombatManager.step_delay <= 0.0:
		_hand_back()
		return
	var from := _camera.position
	var glide := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Aimed at wherever the player's camera is looking *now*: the lock is off
	# and they may already be walking.
	glide.tween_method(func(t: float) -> void:
		var to := field.map.to_local(_player_camera.get_screen_center_position()) \
				if _player_camera != null else from
		_camera.position = from.lerp(to, t), 0.0, 1.0, OUTRO_EASE)
	glide.tween_property(_camera, "zoom", Vector2.ONE, OUTRO_EASE)
	glide.chain().tween_callback(_hand_back)


func _hand_back() -> void:
	for sprite in _bystanders:
		if is_instance_valid(sprite):
			sprite.modulate.a = 1.0
	if _player_camera != null and is_instance_valid(_player_camera):
		_player_camera.make_current()
		_player_camera.reset_smoothing()
	if _camera != null:
		_camera.queue_free()
	queue_free()


func _float_number(hit: CombatReport.Hit) -> void:
	var text := ""
	var color := UiPalette.DAMAGE
	if hit.missed:
		text = "miss"
		color = UiPalette.MISS
	elif hit.amount > 0:
		text = "+%d" % hit.amount
		color = UiPalette.HEAL
	elif hit.amount < 0:
		text = str(-hit.amount)
		color = UiPalette.CRIT if hit.crit else UiPalette.DAMAGE
	else:
		return
	var label := Label.new()
	label.text = text + ("!" if hit.crit else "")
	label.theme_type_variation = &"FieldLabel"
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.size = Vector2(32, 8)
	var over := _node_of(hit.target)
	label.position = _spot_of(hit.target) + Vector2(-16, -_height_of(over) - FLOATER_LIFT)
	if CombatManager.step_delay <= 0.0:
		label.queue_free()
		return
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - FLOATER_RISE, FLOATER_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FLOATER_TIME).set_delay(FLOATER_TIME * 0.4)
	tween.chain().tween_callback(label.queue_free)


func _spot_of(who: Combatant) -> Vector2:
	if who.is_player:
		return field.player.position
	var node := _nodes.get(who) as Node2D
	return node.position if node != null else field.player.position


## The map node standing in for [param who].
func _node_of(who: Combatant) -> Node2D:
	return field.player if who.is_player else _nodes.get(who) as Node2D


func _sprite_of(who: Combatant) -> Node2D:
	if who == null:
		return null
	if who.is_player:
		return field.player.get_node("Sprite2D") as Node2D
	var node := _nodes.get(who) as Node2D
	if node != null and node.has_method(&"sprite"):
		return node.call(&"sprite") as Node2D
	return node


## How far [param node]'s sprite stands above its feet -- where a pointer or a
## number goes over it. A 16 px monster's when there is no sprite to ask.
func _height_of(node: Node2D) -> float:
	var sprite := _drawn(node)
	if sprite == null:
		return 16.0
	return -(sprite.position.y + sprite.get_rect().position.y * sprite.scale.y)


func _width_of(node: Node2D) -> float:
	var sprite := _drawn(node)
	return sprite.get_rect().size.x * sprite.scale.x if sprite != null else 16.0


func _drawn(node: Node2D) -> Sprite2D:
	if node == null:
		return null
	if node == field.player:
		return field.player.get_node_or_null("Sprite2D") as Sprite2D
	if node.has_method(&"sprite"):
		return node.call(&"sprite") as Sprite2D
	return node as Sprite2D


func _flash(who: Combatant) -> void:
	var sprite := _sprite_of(who)
	if sprite == null:
		return
	sprite.self_modulate = FLASH
	sprite.create_tween().tween_property(sprite, "self_modulate", Color.WHITE, FLASH_TIME)


## Whole units, so the pixel grid never smears.
func _shake_camera() -> void:
	if _camera == null:
		return
	if _shake != null:
		_shake.kill()
	_shake = create_tween()
	var steps := 6
	for i in steps:
		var strength := SHAKE * (1.0 - float(i) / steps)
		var kick := Vector2(strength if i % 2 == 0 else -strength, roundf(strength * 0.5) * (1 if i % 3 == 0 else -1))
		_shake.tween_property(_camera, "offset", kick.round(), SHAKE_TIME / steps)
	_shake.tween_property(_camera, "offset", Vector2.ZERO, SHAKE_TIME / steps)
