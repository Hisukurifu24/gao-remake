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

var enemy: EnemyType
var _sprite := Sprite2D.new()
## Idle frames stepped through [member _art]'s region; 0 for none.
var _frames := 0
var _art: AtlasTexture = null
var _base := Rect2()
var _step := Vector2.ZERO
var _idle_time := 0.0


func _init(type: EnemyType, boss: bool) -> void:
	enemy = type
	name = "Foe_%s" % type.id
	_sprite.name = "Sprite2D"
	add_child(_sprite)
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
	if boss and maxf(size.x, size.y) <= SMALL_ART:
		_sprite.scale = Vector2(2, 2)
	# Feet at the node, so the map's y-sort stands it where it stands.
	_sprite.position = Vector2(0.0, -size.y * _sprite.scale.y / 2.0)


func _process(delta: float) -> void:
	if _frames <= 1:
		return
	_idle_time += delta
	var frame := int(_idle_time / IDLE_FRAME_TIME) % _frames
	if _art != null:
		_art.region = Rect2(_base.position + _step * frame, _base.size)
	elif enemy.sheet_frames.y > 1:
		_sprite.frame = frame * enemy.sheet_frames.x + _sprite.frame % enemy.sheet_frames.x
	else:
		_sprite.frame = frame


## How much of the map it covers, standing: width, and height above its feet.
func body() -> Vector2:
	return body_of(enemy, _sprite.scale.x > 1.0)


## [method body] before there is a figure -- what the formation has to make room for.
static func body_of(type: EnemyType, boss: bool) -> Vector2:
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
	if enemy.sheet == null:
		return
	if enemy.sheet_frames.y == 1:
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
