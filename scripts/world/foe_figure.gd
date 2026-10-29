class_name FoeFigure
extends Node2D
## An enemy standing on the map for one fight, with no life of its own there --
## a boss stepping out of its door, and the escort behind it.
##
## A roaming [Monster] is its own figure; a boss lives behind a door and has
## nothing on the map until the fight starts, so [BossGate] makes one of these
## for each enemy in the encounter and frees them when it ends. It answers the
## same two questions a [BattleStage] asks a monster -- [method sprite] and
## [method face] -- and nothing else: no physics, no wandering, no fog alpha.
##
## Drawn from the type's walk sheet, treading in place down its front column, or
## from its battler, breathing through [member EnemyType.idle_frames]. A boss
## built from a 16 px trash template stands twice its size, so the thing at the
## end of the labyrinth reads as the thing at the end of the labyrinth.

## A boss whose art is this small or smaller is drawn doubled.
const SMALL_ART := 24.0
const IDLE_FRAME_TIME := 0.18
## A slow change ([method transfigure]): the share of it spent washing out to
## white, and the share held there before coming back.
const WASH_IN := 0.35
const WASH_HELD := 0.2
const FLARE := Color(4.0, 4.0, 4.0)
## Breaking into light ([method shatter]).
const SHARDS := 60
const SHARD_TIME := 2.0
const SHATTER_FLARE := 0.6

var enemy: EnemyType
var _sprite := Sprite2D.new()
var _boss := false
## The shape it is in now: [member enemy], or a phase's form.
var _look: EnemyType
var _facing := Vector2.DOWN
## Idle frames stepped through [member _art]'s region; 0 for none.
var _frames := 0
var _art: AtlasTexture = null
var _base := Rect2()
var _step := Vector2.ZERO
var _idle_time := 0.0


func _init(type: EnemyType, boss: bool) -> void:
	enemy = type
	_boss = boss
	name = "Foe_%s" % type.id
	_sprite.name = "Sprite2D"
	add_child(_sprite)
	_dress(type)


## Takes the shape of [param form] mid-fight -- a boss's next bar ([BossPhase]):
## its art, and how it stands. Where it stands doesn't move; the formation made
## room for its biggest shape before the fight began ([method body_of]).
func become(form: EnemyType) -> void:
	if form != null:
		_dress(form)


## Flickers, faster and fainter, for [param time] -- a shape failing -- and
## stands whole again at the end of it. Returns the tween, to wait on.
func falter(time: float) -> Tween:
	var flicker := _sprite.create_tween()
	var left := time
	var beat := 0.16
	while left > beat:
		flicker.tween_property(_sprite, "modulate:a", 0.35, 0.0)
		flicker.tween_interval(beat * 0.4)
		flicker.tween_property(_sprite, "modulate:a", 1.0, 0.0)
		flicker.tween_interval(beat * 0.6)
		left -= beat
		beat = maxf(0.06, beat * 0.85)
	flicker.tween_property(_sprite, "modulate:a", 1.0, 0.0)
	return flicker


## Washes out to white, [method become]s [param form] under it, and comes back
## out of it, over [param time]. Returns the tween, to wait on.
func transfigure(form: EnemyType, time: float) -> Tween:
	_sprite.modulate.a = 1.0
	var wash := _sprite.create_tween()
	wash.tween_property(_sprite, "self_modulate", FLARE, time * WASH_IN).set_ease(Tween.EASE_IN)
	wash.tween_callback(become.bind(form))
	wash.tween_interval(time * WASH_HELD)
	wash.tween_property(_sprite, "self_modulate", Color.WHITE, time * (1.0 - WASH_IN - WASH_HELD)) \
			.set_ease(Tween.EASE_OUT)
	return wash


## Flares and breaks into shards of light where it stands, as SAO draws a death.
## Returns the tween, to wait on; the figure is left drawn as nothing.
func shatter() -> Tween:
	var flare := _sprite.create_tween()
	flare.tween_property(_sprite, "self_modulate", Color(2.2, 2.6, 3.0, 1.0), SHATTER_FLARE)
	flare.tween_callback(func() -> void:
		var parent := get_parent() as Node2D
		if parent != null:
			Shards.burst(_sprite, parent, SHARDS, SHARD_TIME))
	flare.tween_interval(SHARD_TIME)
	return flare


func _dress(type: EnemyType) -> void:
	_look = type
	_frames = 0
	_art = null
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.frame = 0
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE
	var size := Vector2.ZERO
	if type.sheet != null:
		_sprite.texture = type.sheet
		_sprite.hframes = type.sheet_frames.x
		_sprite.vframes = type.sheet_frames.y
		size = type.sheet.get_size() / Vector2(type.sheet_frames)
		_frames = type.sheet_frames.y if type.sheet_frames.y > 1 else type.sheet_frames.x
	else:
		var art := type.battler as AtlasTexture
		if art != null and type.idle_frames > 1:
			_art = art.duplicate() as AtlasTexture
			_base = art.region
			_step = Vector2(art.atlas.get_width() / float(type.idle_frames), 0.0)
			_frames = type.idle_frames
			_sprite.texture = _art
		else:
			_sprite.texture = type.battler
		size = _sprite.texture.get_size() if _sprite.texture != null else Vector2(16, 16)
	if _boss and maxf(size.x, size.y) <= SMALL_ART:
		_sprite.scale = Vector2(2, 2)
	# Feet at the node, so the map's y-sort stands it where it stands.
	_sprite.position = Vector2(0.0, -size.y * _sprite.scale.y / 2.0)
	face(_facing)


func _process(delta: float) -> void:
	if _frames <= 1:
		return
	_idle_time += delta
	var frame := int(_idle_time / IDLE_FRAME_TIME) % _frames
	if _art != null:
		_art.region = Rect2(_base.position + _step * frame, _base.size)
	elif _look.sheet_frames.y > 1:
		_sprite.frame = frame * _look.sheet_frames.x + _sprite.frame % _look.sheet_frames.x
	else:
		_sprite.frame = frame


## How much of the map it covers, standing, at its biggest: width, and height
## above its feet.
func body() -> Vector2:
	return body_of(enemy, _boss)


## [method body] before there is a figure -- what the formation has to make room
## for: the biggest of every shape it takes ([method EnemyType.forms]), so a boss
## that grows on its next bar doesn't grow into you.
static func body_of(type: EnemyType, boss: bool) -> Vector2:
	var biggest := Vector2.ZERO
	for form in type.forms():
		biggest = biggest.max(_drawn_size(form, boss))
	return biggest


static func _drawn_size(type: EnemyType, boss: bool) -> Vector2:
	var size := Vector2(16, 16)
	if type.sheet != null:
		size = type.sheet.get_size() / Vector2(type.sheet_frames)
	elif type.battler != null:
		size = type.battler.get_size()
	if boss and maxf(size.x, size.y) <= SMALL_ART:
		size *= 2.0
	return size


func sprite() -> Sprite2D:
	return _sprite


## Turns to look along [param direction]. A side view mirrors; a battler -- drawn
## facing you -- has no other way to look.
func face(direction: Vector2) -> void:
	_facing = direction
	if _look.sheet == null:
		return
	if _look.sheet_frames.y == 1:
		if absf(direction.x) > 0.01:
			_sprite.flip_h = direction.x < 0.0
		return
	# down, up, left, right -- the pack's column order.
	var column := 0
	if absf(direction.x) > absf(direction.y):
		column = 2 if direction.x < 0.0 else 3
	elif direction.y < 0.0:
		column = 1
	_sprite.frame = column
