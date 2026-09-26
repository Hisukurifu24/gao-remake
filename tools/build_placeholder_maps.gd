extends SceneTree
## Builds Floor 1's two authored maps: the Town of Beginnings and the West Field.
##
##     "$GODOT" --headless --path . --script res://tools/build_placeholder_maps.gd
##
## Tile data is a binary blob inside .tscn, so these maps are authored by the
## engine rather than by hand. The output is ordinary scenes -- open them in the
## editor and paint over them; just don't re-run this or it overwrites your work.
##
## The layout is painted in the biome's semantic slots -- grass, path, wall -- and
## then handed to [MapDresser], the same pass a generated floor gets: the wall
## mass grows into forest, the roads and the pond join into edges, flowers come up.
## This script decides where things are, never which tile draws them.

const BIOME_PATH := "res://resources/biomes/meadow.tres"
const TOWN_PATH := "res://scenes/world/town.tscn"
const FIELD_PATH := "res://scenes/world/field.tscn"

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const NPC_SCENE := "res://scenes/world/npc.tscn"
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const EXIT_SCENE := "res://scenes/world/map_exit.tscn"
const BOSS_GATE_SCENE := "res://scenes/world/boss_gate.tscn"
const MONSTER_SCENE := "res://scenes/world/monster.tscn"
const CHARACTER_SHEET := "res://assets/ninja_adventure/Actor/Character/%s/SpriteSheet.png"

## Floor 1's monsters are placed by hand rather than by the curve in
## [FloorTuning], but the count is the same one: ten kills is what puts a new
## player at the level Illfang is tuned for.
const FIELD_MONSTERS := [
	[Vector2i(12, 5), &"frenzy_boar"],
	[Vector2i(18, 12), &"little_nepent"],
	[Vector2i(30, 6), &"frenzy_boar"],
	[Vector2i(44, 9), &"little_nepent"],
	[Vector2i(6, 22), &"frenzy_boar"],
	[Vector2i(28, 18), &"little_nepent"],
	[Vector2i(38, 20), &"frenzy_boar"],
	[Vector2i(50, 20), &"little_nepent"],
	[Vector2i(36, 30), &"frenzy_boar"],
	[Vector2i(22, 33), &"frenzy_boar"],
]

const TILE := 16
const SOURCE_ID := 0

# Both maps are deliberately larger than the 320x180 viewport so the camera
# actually scrolls instead of sitting on limits.
const TOWN_W := 50
const TOWN_H := 36
const FIELD_W := 60
const FIELD_H := 44
## How deep the forest round each map is. Two rows, so the outer row's crowns have
## a row of trunks in front of them rather than the edge of the world.
const BORDER := 2

## Each the size of its art. Only the bottom two rows are solid: the roof's top
## row stays walkable, and the y-sorted roof draws over you when you pass behind.
const TOWN_HOUSES: Array[Rect2i] = [
	Rect2i(5, 5, 4, 3), Rect2i(14, 9, 4, 3), Rect2i(36, 5, 4, 3),
	Rect2i(6, 25, 4, 3), Rect2i(34, 24, 4, 3),
]
## Stands of trees inside the town, clear of the roads, the plaza and everyone on them.
const TOWN_GROVES: Array[Rect2i] = [
	Rect2i(42, 11, 5, 3), Rect2i(12, 29, 4, 3), Rect2i(2, 12, 3, 4),
]
const FIELD_GROVES: Array[Vector2i] = [
	Vector2i(9, 6), Vector2i(13, 9), Vector2i(6, 16), Vector2i(17, 19),
	Vector2i(34, 8), Vector2i(41, 15), Vector2i(52, 11), Vector2i(44, 33),
	Vector2i(30, 36), Vector2i(20, 40), Vector2i(53, 27),
]

## Fixed, so rebuilding the maps never reshuffles their trees and flowers.
const TOWN_SEED := 1001
const FIELD_SEED := 1002


func _initialize() -> void:
	if not ResourceLoader.exists(BIOME_PATH):
		push_error("missing %s -- run tools/build_biomes.gd first" % BIOME_PATH)
		quit(1)
		return
	var biome: BiomeKit = load(BIOME_PATH)
	_save(_build_town(biome), TOWN_PATH)
	_save(_build_field(biome), FIELD_PATH)
	quit()


# --- maps ------------------------------------------------------------------

func _build_town(biome: BiomeKit) -> Node2D:
	var map := _new_map("Town", &"town", "Town of Beginnings", biome)
	var ground: TileMapLayer = map.get_node("Ground")
	var walls: TileMapLayer = map.get_node("Walls")

	_fill(ground, Rect2i(0, 0, TOWN_W, TOWN_H), biome.floor_tile)
	_fill(ground, Rect2i(23, 1, 3, TOWN_H - 2), biome.path_tile)   # north-south road
	_fill(ground, Rect2i(1, 17, TOWN_W - 2, 3), biome.path_tile)   # east-west road
	_fill(ground, Rect2i(21, 15, 8, 6), biome.special_tile)        # central plaza

	_border(walls, Rect2i(0, 0, TOWN_W, TOWN_H), biome.wall_tile)
	_erase(walls, Rect2i(23, TOWN_H - BORDER, 3, BORDER))           # south gate
	for grove in TOWN_GROVES:
		_fill(walls, grove, biome.wall_tile)
	for house in TOWN_HOUSES:
		_fill(walls, _house_footprint(house), biome.wall_alt_tile)

	MapDresser.dress(map, biome, ground, walls, TOWN_SEED)
	var props := MapDresser.props_layer(map, biome)
	for index in TOWN_HOUSES.size():
		props.set_cell(MapDresser.anchor_for(TOWN_HOUSES[index]), SOURCE_ID,
				biome.house_tiles[index % biome.house_tiles.size()])

	_add_spawns(map, {
		"default": Vector2(392, 296),
		"from_field": Vector2(392, 536),
	})

	_add(map, _npc(
		Vector2(328, 216), "Argo", "Argo the Rat", [], &"met_argo", "NinjaYellow",
		"res://resources/dialogue/argo.tres"
	))
	_add(map, _npc(
		Vector2(504, 344), "Nezha", "Nezha the smith", [], &"met_nezha", "Hunter",
		"res://resources/dialogue/nezha.tres"
	))
	_add(map, _chest(Vector2(648, 472), &"small_potion", 3, &"chest_town_square"))
	_add(map, _exit(Vector2(392, TOWN_H * TILE - 8), Vector2(2, 1), FIELD_PATH, &"from_town", true))

	_add(map, _player(Vector2(392, 296)))
	return map


func _build_field(biome: BiomeKit) -> Node2D:
	var map := _new_map("Field", &"field_f1", "West Field", biome)
	var ground: TileMapLayer = map.get_node("Ground")
	var walls: TileMapLayer = map.get_node("Walls")

	_fill(ground, Rect2i(0, 0, FIELD_W, FIELD_H), biome.floor_tile)
	_fill(ground, Rect2i(23, 0, 3, 26), biome.path_tile)
	_fill(ground, Rect2i(26, 23, 22, 3), biome.path_tile)
	_fill(ground, Rect2i(47, 23, 3, 15), biome.path_tile)        # approach to the labyrinth door

	_border(walls, Rect2i(0, 0, FIELD_W, FIELD_H), biome.wall_tile)
	_erase(walls, Rect2i(23, 0, 3, BORDER))                         # gate back to town
	_fill(walls, Rect2i(8, 28, 10, 7), biome.liquid_tile)          # pond
	for spot in FIELD_GROVES:
		_fill(walls, Rect2i(spot, Vector2i(2, 2)), biome.wall_tile)

	MapDresser.dress(map, biome, ground, walls, FIELD_SEED)

	_add_spawns(map, {
		"default": Vector2(392, 40),
		"from_town": Vector2(392, 40),
	})

	_add(map, _npc(
		Vector2(488, 264), "Scout", "a nervous scout",
		[
			"You're heading further out? Watch the treeline.",
			"Frenzy Boars charge the moment you turn your back.",
			"The labyrinth door is south-east, past the pond.",
			"Illfang is behind it. Nobody's come back through yet.",
		],
		&"", "CamouflageGreen"
	))
	_add(map, _chest(Vector2(744, 168), &"bronze_sword", 1, &"chest_field_north"))
	_add(map, _exit(Vector2(392, 8), Vector2(2, 1), TOWN_PATH, &"from_field", true))

	for index in FIELD_MONSTERS.size():
		var spot: Vector2i = FIELD_MONSTERS[index][0]
		_add(map, _monster(index, Vector2(spot.x * TILE + 8, spot.y * TILE + 8),
				FIELD_MONSTERS[index][1]))

	var gate := (load(BOSS_GATE_SCENE) as PackedScene).instantiate()
	gate.name = "BossGate"
	gate.position = Vector2(792, 600)
	gate.set(&"floor_number", 1)
	gate.set(&"boss_name", "Illfang the Kobold Lord")
	_add(map, gate)

	_add(map, _player(Vector2(392, 40)))
	return map


## The solid part of a house: everything but the roof's top row.
func _house_footprint(house: Rect2i) -> Rect2i:
	return Rect2i(house.position.x, house.position.y + 1, house.size.x, house.size.y - 1)


# --- scene assembly --------------------------------------------------------

func _new_map(node_name: String, id: StringName, display: String, biome: BiomeKit) -> Node2D:
	var map := Node2D.new()
	map.name = node_name
	map.set_script(load("res://scripts/world/game_map.gd"))
	map.set(&"map_id", id)
	map.set(&"display_name", display)
	map.set(&"floor_number", 1)  # both authored maps are Floor 1
	map.modulate = biome.ambient_tint

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = biome.tile_set
	ground.collision_enabled = false
	map.add_child(ground)
	ground.owner = map

	var walls := TileMapLayer.new()
	walls.name = "Walls"
	walls.tile_set = biome.tile_set
	map.add_child(walls)
	walls.owner = map

	return map


func _add_spawns(map: Node2D, spawns: Dictionary) -> void:
	var holder := Node2D.new()
	holder.name = "SpawnPoints"
	map.add_child(holder)
	holder.owner = map
	for spawn_name in spawns:
		var marker := Marker2D.new()
		marker.name = spawn_name
		marker.position = spawns[spawn_name]
		holder.add_child(marker)
		marker.owner = map


func _add(map: Node2D, node: Node) -> void:
	map.add_child(node)
	node.owner = map


func _player(at: Vector2) -> Node:
	var node := (load(PLAYER_SCENE) as PackedScene).instantiate()
	node.name = "Player"
	node.position = at
	return node


## Named characters get a Dialogue resource; [param lines] is the quick path for
## extras who only ever say one thing. [param look] names a character folder in
## the Ninja Adventure pack.
func _npc(at: Vector2, speaker: String, display: String, lines: Array, flag: StringName,
		look: String, dialogue_path := "") -> Node:
	var node := (load(NPC_SCENE) as PackedScene).instantiate()
	node.name = speaker
	node.position = at
	node.set(&"speaker", speaker)
	node.set(&"display_name", display)
	node.set(&"prompt_verb", "Talk to")
	node.set(&"lines", PackedStringArray(lines))
	node.set(&"met_flag", flag)
	node.set(&"sprite_sheet", load(CHARACTER_SHEET % look))
	if not dialogue_path.is_empty():
		node.set(&"dialogue", load(dialogue_path))
	return node


func _monster(index: int, at: Vector2, enemy_id: StringName) -> Node:
	var node := (load(MONSTER_SCENE) as PackedScene).instantiate()
	node.name = "Monster%d" % index
	node.position = at
	node.set(&"enemy", load("res://resources/enemies/%s.tres" % enemy_id))
	node.set(&"level", 2)  # matches resources/floors/floor_01.tres
	node.set(&"floor_number", 1)
	return node


func _chest(at: Vector2, item_id: StringName, amount: int, flag: StringName) -> Node:
	var node := (load(CHEST_SCENE) as PackedScene).instantiate()
	node.position = at
	node.set(&"item_id", item_id)
	node.set(&"amount", amount)
	node.set(&"opened_flag", flag)
	return node


func _exit(at: Vector2, zone_scale: Vector2, target: String, spawn: StringName, auto: bool) -> Node:
	var node := (load(EXIT_SCENE) as PackedScene).instantiate()
	node.name = "ExitTo" + spawn.capitalize().replace(" ", "")
	node.position = at
	node.scale = zone_scale
	node.set(&"target_map", target)
	node.set(&"target_spawn", spawn)
	node.set(&"auto_trigger", auto)
	return node


# --- painting helpers ------------------------------------------------------

func _fill(layer: TileMapLayer, rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(tile, 0))


func _erase(layer: TileMapLayer, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			layer.erase_cell(Vector2i(x, y))


## A ring [constant BORDER] cells deep round [param rect].
func _border(layer: TileMapLayer, rect: Rect2i, tile: int) -> void:
	_fill(layer, Rect2i(rect.position.x, rect.position.y, rect.size.x, BORDER), tile)
	_fill(layer, Rect2i(rect.position.x, rect.end.y - BORDER, rect.size.x, BORDER), tile)
	_fill(layer, Rect2i(rect.position.x, rect.position.y, BORDER, rect.size.y), tile)
	_fill(layer, Rect2i(rect.end.x - BORDER, rect.position.y, BORDER, rect.size.y), tile)


func _save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return
	node.free()
	print("wrote ", path)
