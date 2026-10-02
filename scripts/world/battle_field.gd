class_name BattleField
extends RefCounted
## Where a fight on the map stands: a spot for the player and one per enemy,
## which way each side faces, and the rect the camera frames.
##
## Built by [method GameMap.stage_battle] -- where everyone can stand is a map
## question -- and handed to the view through [signal EventBus.battle_staged] by
## whoever starts the fight. [CombatManager] never sees one: it still fights an
## [Encounter], and the view pairs [member enemy_nodes] with the enemies of
## [signal CombatManager.combat_began] by index, the order the encounter lists them.

## The map the fight is on. Spots and the arena are in its local coordinates.
var map: GameMap
var player: Player
## The map nodes standing in for each enemy, in the encounter's order.
var enemy_nodes: Array[Node2D] = []

## Feet positions, map-local.
var player_spot := Vector2.ZERO
var enemy_spots: Array[Vector2] = []
## The cells those spots stand on.
var player_cell := Vector2i.ZERO
var enemy_cells: Array[Vector2i] = []
## From the player towards the enemies, one of the four axis directions.
var axis := Vector2i.RIGHT
## What the camera frames, map-local.
var arena := Rect2()
## What the fighters themselves cover, standing on their spots: the tightest
## rect the camera may close in on. Map-local.
var bodies := Rect2()


## The rect of cells the fight covers, for lighting it in the dark.
func arena_cells(tile_size: Vector2i) -> Rect2i:
	var from := Vector2i((arena.position / Vector2(tile_size)).floor())
	var to := Vector2i((arena.end / Vector2(tile_size)).ceil())
	return Rect2i(from, to - from)
