class_name BattleStage
extends Node2D
## A fight drawn on the map it happens on.
##
## Added to the map by the combat view when a [BattleField] is staged, and gone
## when the fight is: it steps the fighters into formation, eases a camera onto
## them, and plays every blow on the real sprites -- the lunge, the flash, the
## numbers, the shake. A view like the battle screen it replaces: it listens to
## [CombatManager] and decides nothing.
##
## SPIKE (M5.5 §6.1): deliberately rough. The menus are still the old screen's.

const ARROW := preload("res://assets/ninja_adventure/Ui/Arrow.png")
const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")
const SMOKE_FRAMES := 6
const SMOKE_FRAME_TIME := 0.07
## The pointer hangs this far over the enemy's spot and bobs this much.
const POINTER_LIFT := 17.0
const POINTER_BOB := 1.0

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
## framed this many screen units above centre.
const FRAME_LIFT := 12.0
## How far round each fighter the dark lifts, in cells.
const LIGHT_RADIUS := 4
## Anyone else in frame stands back to this, so a frozen boar at the edge of the
## fight doesn't read as a second enemy.
const BYSTANDER_ALPHA := 0.25

## How far the camera closes in. The spike's open question: 1 keeps the UI's
## pixel scale, 2 frames 160x90 of world.
static var zoom := 2.0

var field: BattleField

var _camera: Camera2D
var _player_camera: Camera2D
## Enemy [Combatant] to the map node standing in for it.
var _nodes: Dictionary[Combatant, Node2D] = {}
var _bars: Dictionary[Combatant, ProgressBar] = {}
var _shake: Tween = null
var _bystanders: Array[Sprite2D] = []
var _pointer: Sprite2D
var _bob: Tween = null


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


func _on_combat_began(_encounter: Encounter, _party: Array[Combatant],
		enemies: Array[Combatant]) -> void:
	for i in mini(enemies.size(), field.enemy_nodes.size()):
		_nodes[enemies[i]] = field.enemy_nodes[i]
	_step_into_formation()
	_fade_bystanders()
	_build_bars()
	_close_in()
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
		if node is Monster:
			(node as Monster).face(-axis)
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
	# Lifted in screen units, so the same at either zoom.
	var target := field.arena.get_center() + Vector2(0, FRAME_LIFT / zoom)
	if CombatManager.step_delay <= 0.0:
		_camera.position = target
		_camera.zoom = Vector2.ONE * zoom
		return
	var glide := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glide.tween_property(_camera, "position", target, INTRO_TIME)
	glide.tween_property(_camera, "zoom", Vector2.ONE * zoom, INTRO_TIME)


## Small bars under each enemy -- the screen's panels are gone, and an enemy's
## health has to be read off the field.
func _build_bars() -> void:
	for enemy in _nodes:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(16, 3)
		bar.size = Vector2(16, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		bar.position = field.enemy_spots[field.enemy_nodes.find(_nodes[enemy])] + Vector2(-8, 2)
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
	for hit in report.hits:
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
	puff.position = _spot_of(enemy) + Vector2(0, -4)
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
	var over := node.position + Vector2(0, -POINTER_LIFT)
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
	label.position = _spot_of(hit.target) + Vector2(-16, -26)
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


func _sprite_of(who: Combatant) -> Node2D:
	if who == null:
		return null
	if who.is_player:
		return field.player.get_node("Sprite2D") as Node2D
	var node := _nodes.get(who) as Node2D
	if node is Monster:
		return (node as Monster).sprite()
	return node


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
