extends SceneTree
## Builds Floor 10 -- Ashlow Wood -- the second authored floor.
##
##     "$GODOT" --headless --path . --script res://tools/build_floor_10.gd
##
## Tile data is a binary blob inside a .tscn, so an authored floor is authored in
## code and packed by the engine, exactly like the two Floor 1 maps. The output is
## an ordinary scene; open it in the editor and paint over it if you like, but
## then stop running this, because it overwrites.
##
## [b]One map, not two.[/b] Floor 1 splits its town and its field across a
## MapExit, which is fine there because the boss is a one-way trip you take once.
## Floor 10 has a quest that sends you to the boss and then back to the village to
## report, so the walk home has to exist -- and a single map is the version of that
## walk which costs no fade, no second scene and no second set of spawn points.
##
## The shape is the shape [FloorGenerator] produces (Ground / Walls / SpawnPoints /
## Player + interactables), because [GameMap], the camera and [SceneRouter] depend
## on that and on nothing else. What is authored here is the *layout*: a village
## the generator has no concept of, three glades, and a hollow at the end.

const BIOME_PATH := "res://resources/biomes/forest.tres"
const OUT_PATH := "res://scenes/world/floor_10.tscn"

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const NPC_SCENE := "res://scenes/world/npc.tscn"
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const BOSS_GATE_SCENE := "res://scenes/world/boss_gate.tscn"
const STAIRS_SCENE := "res://scenes/world/floor_stairs.tscn"
const MONSTER_SCENE := "res://scenes/world/monster.tscn"

const FLOOR_NUMBER := 10
const TILE := 16
const SOURCE_ID := 0
const CORRIDOR_WIDTH := 3

const SIZE := Vector2i(78, 58)

# --- regions, in tiles -----------------------------------------------------
#
# Ashlow sits in the north-west, the three glades run diagonally across the
# middle, and the hollow with the labyrinth door is as far from the stairs as the
# map gets. Corridors join them in a loop rather than a chain, so a player who
# does not want to fight their way back the way they came doesn't have to.

const VILLAGE := Rect2i(3, 3, 26, 20)
const GLADE_A := Rect2i(36, 5, 12, 9)
const GLADE_B := Rect2i(33, 24, 13, 10)
const GLADE_C := Rect2i(14, 34, 14, 10)
const HOLLOW := Rect2i(56, 38, 16, 13)

## Where the cut paths leave Ashlow. Taken from the village edge rather than its
## centre, so a corridor can never carve a street through a building.
const GATE_EAST := Vector2i(29, 12)
const GATE_SOUTH := Vector2i(15, 23)

const CORRIDORS := [
	[GATE_EAST, Vector2i(42, 9)],
	[Vector2i(42, 9), Vector2i(39, 28)],
	[GATE_SOUTH, Vector2i(21, 39)],
	[Vector2i(21, 39), Vector2i(39, 28)],
	[Vector2i(39, 28), Vector2i(58, 44)],
]

const SPAWN_CELL := Vector2i(16, 20)
const STAIRS_CELL := Vector2i(12, 20)
const GATE_CELL := Vector2i(67, 44)

## Buildings, as roof blocks with a wall course along the bottom -- the same trick
## the Town of Beginnings uses. The course is plain wall, so it joins the terrain
## and draws a facade; the roof carries no terrain and stays a flat block.
const BUILDINGS := [
	Rect2i(5, 5, 6, 4),
	Rect2i(20, 5, 7, 4),
	Rect2i(5, 16, 6, 4),
	Rect2i(21, 16, 6, 4),
]

const NPCS := [
	{"at": Vector2i(12, 10), "name": "Rue", "display": "Rue the forester",
		"flag": &"met_rue", "dialogue": "res://resources/dialogue/rue.tres"},
	{"at": Vector2i(20, 15), "name": "Sable", "display": "Sable the cartographer",
		"flag": &"met_sable", "dialogue": "res://resources/dialogue/sable.tres"},
	{"at": Vector2i(8, 14), "name": "Logger", "display": "a logger", "flag": &"",
		"lines": [
			"Nine floors up and the trees still win.",
			"Rue says four wolves. Rue has said four wolves since spring.",
		]},
	{"at": Vector2i(24, 10), "name": "Runner", "display": "a courier", "flag": &"",
		"lines": [
			"I carry mail down to Floor Nine and back. Twice a week, when the path holds.",
			"Last month it stopped holding. The wood grew over the road overnight.",
		]},
]

const CHESTS := [
	{"at": Vector2i(39, 8), "item": &"health_potion", "amount": 2,
		"flag": &"chest_ashlow_glade_north"},
	{"at": Vector2i(36, 26), "item": &"swift_charm", "amount": 1,
		"flag": &"chest_ashlow_glade_deep"},
	{"at": Vector2i(18, 37), "item": &"whetstone", "amount": 2,
		"flag": &"chest_ashlow_glade_south"},
]

## Nine, which is [method FloorTuning.monster_count] for this floor -- authored
## does not mean exempt from the curve, it means the placement is chosen. Six of
## them are wolves because "Past the Tree Line" asks for four.
const MONSTERS := [
	[Vector2i(38, 6), &"dire_wolf"],
	[Vector2i(44, 6), &"dire_wolf"],
	[Vector2i(45, 11), &"little_nepent"],
	[Vector2i(35, 26), &"dire_wolf"],
	[Vector2i(43, 31), &"dire_wolf"],
	[Vector2i(37, 32), &"little_nepent"],
	[Vector2i(16, 36), &"dire_wolf"],
	[Vector2i(22, 42), &"dire_wolf"],
	[Vector2i(25, 41), &"little_nepent"],
]

## Boulders and standing water, placed rather than scattered. Every one is at
## least two tiles inside its glade and clear of the corridor mouths; the flood
## fill at the end of [method _build] is what actually holds that to it.
const BOULDERS := [
	Vector2i(40, 12), Vector2i(46, 7), Vector2i(41, 26),
	Vector2i(19, 36), Vector2i(24, 38), Vector2i(60, 41), Vector2i(69, 48),
]
const POOL := Rect2i(35, 29, 3, 2)

var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool] = {}


func _initialize() -> void:
	if not ResourceLoader.exists(BIOME_PATH):
		push_error("missing %s -- run tools/build_biomes.gd first" % BIOME_PATH)
		quit(1)
		return
	_biome = load(BIOME_PATH)

	var map := _build()
	if map == null:
		quit(1)
		return
	_save(map, OUT_PATH)
	quit()


# --- the floor -------------------------------------------------------------

func _build() -> Node2D:
	var map := Node2D.new()
	map.name = "Floor10"
	map.set_script(load("res://scripts/world/game_map.gd"))
	map.set(&"map_id", &"floor_10")
	map.set(&"display_name", "Floor 10 - Ashlow Wood")
	map.set(&"floor_number", FLOOR_NUMBER)
	map.modulate = _biome.ambient_tint

	_ground = _new_layer(map, "Ground", false)
	_walls = _new_layer(map, "Walls", true)

	# Solid to begin with, then carved -- same as a generated floor, and the
	# reason the outer ring is sealed without anyone having to remember to seal it.
	for y in SIZE.y:
		for x in SIZE.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)

	_carve_village()
	for glade in [GLADE_A, GLADE_B, GLADE_C]:
		_carve(glade, _biome.floor_tile)
	_carve(HOLLOW, _biome.special_tile)
	for run in CORRIDORS:
		_carve_corridor(run[0], run[1])

	_decorate()
	_join_walls()

	_add_spawns(map)
	_add_stairs(map)
	for entry in NPCS:
		_add_npc(map, entry)
	for index in CHESTS.size():
		_add_chest(map, index, CHESTS[index])
	for index in MONSTERS.size():
		_add_monster(map, index, MONSTERS[index][0], MONSTERS[index][1])
	_add_boss_gate(map)

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.name = "Player"
	player.position = _world(SPAWN_CELL)
	_add(map, player)

	if not _verify():
		map.free()
		return null
	return map


## Ashlow: two streets crossing at a stone square, four roofs, and floor
## everywhere else. Carved as one rectangle first so the buildings are put *back*
## rather than left standing -- a building is a thing inside the village, not a
## piece of the wood the village failed to clear.
func _carve_village() -> void:
	_carve(VILLAGE, _biome.floor_tile)
	_fill(_ground, Rect2i(VILLAGE.position.x, 12, VILLAGE.size.x, 2), _biome.path_tile)
	_fill(_ground, Rect2i(15, VILLAGE.position.y, 2, VILLAGE.size.y), _biome.path_tile)
	_fill(_ground, Rect2i(14, 11, 5, 5), _biome.special_tile)
	for building in BUILDINGS:
		_build_house(building)


func _build_house(rect: Rect2i) -> void:
	var roof := Rect2i(rect.position, Vector2i(rect.size.x, rect.size.y - 1))
	_block(roof, _biome.wall_alt_tile)
	_block(Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1), _biome.wall_tile)


func _decorate() -> void:
	for cell in BOULDERS:
		_block(Rect2i(cell, Vector2i.ONE), _biome.obstacle_tile)
	_block(POOL, _biome.liquid_tile)


# --- painting --------------------------------------------------------------

func _carve(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			_walls.erase_cell(cell)
			_paint(_ground, cell, tile)
			_open[cell] = true


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	# L-shaped with a fixed elbow. A generated floor picks the elbow from its
	# seed; an authored one has no seed and no need of one.
	var elbow := Vector2i(to.x, from.y)
	_carve_line(from, elbow)
	_carve_line(elbow, to)


func _carve_line(from: Vector2i, to: Vector2i) -> void:
	var half := CORRIDOR_WIDTH / 2
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell := from
	while true:
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var target := cell + Vector2i(dx, dy)
				# The outer ring is never carved, so the map never opens onto the void.
				if target.x < 1 or target.y < 1:
					continue
				if target.x >= SIZE.x - 1 or target.y >= SIZE.y - 1:
					continue
				if not _open.has(target):
					_walls.erase_cell(target)
					_paint(_ground, target, _biome.path_tile)
					_open[target] = true
		if cell == to:
			break
		cell += Vector2i(step.x, 0) if cell.x != to.x else Vector2i(0, step.y)


## Puts something solid back on a carved cell: a roof, a boulder, a pool.
func _block(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			_paint(_walls, cell, tile)
			_open.erase(cell)


func _fill(layer: TileMapLayer, rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_paint(layer, Vector2i(x, y), tile)


## Autotiles the wall mass, last, as a pass over the finished layout -- the same
## rule [method FloorGenerator._join_walls] follows and for the same reason.
## Only cells still holding the plain wall tile join: roofs, boulders and pools
## live on this layer too and are scenery, so the mass draws an edge against them.
func _join_walls() -> void:
	if _biome.wall_terrain_set < 0:
		return
	var wall_atlas := Vector2i(_biome.wall_tile, 0)
	var cells: Array[Vector2i] = []
	for cell in _walls.get_used_cells():
		if _walls.get_cell_atlas_coords(cell) == wall_atlas:
			cells.append(cell)
	_walls.set_cells_terrain_connect(cells, _biome.wall_terrain_set, _biome.wall_terrain, false)


# --- contents --------------------------------------------------------------

func _add_spawns(map: Node2D) -> void:
	var holder := Node2D.new()
	holder.name = "SpawnPoints"
	map.add_child(holder)
	holder.owner = map
	# All three land on the village square: you arrive in Ashlow whether you came
	# up the stairs, back down them, or woke up here after losing to the Warden.
	for spawn_name in ["default", "from_below", "from_above"]:
		var marker := Marker2D.new()
		marker.name = spawn_name
		marker.position = _world(SPAWN_CELL)
		holder.add_child(marker)
		marker.owner = map


func _add_stairs(map: Node2D) -> void:
	var stairs := (load(STAIRS_SCENE) as PackedScene).instantiate()
	stairs.name = "StairsDown"
	stairs.position = _world(STAIRS_CELL)
	stairs.set(&"target_floor", FLOOR_NUMBER - 1)
	stairs.set(&"display_name", "the stairs down")
	_add(map, stairs)


func _add_npc(map: Node2D, entry: Dictionary) -> void:
	var node := (load(NPC_SCENE) as PackedScene).instantiate()
	node.name = entry["name"]
	node.position = _world(entry["at"])
	node.set(&"speaker", entry["name"])
	node.set(&"display_name", entry["display"])
	node.set(&"prompt_verb", "Talk to")
	node.set(&"lines", PackedStringArray(entry.get("lines", [])))
	node.set(&"met_flag", entry["flag"])
	if entry.has("dialogue"):
		node.set(&"dialogue", load(entry["dialogue"]))
	_add(map, node)


func _add_chest(map: Node2D, index: int, entry: Dictionary) -> void:
	var chest := (load(CHEST_SCENE) as PackedScene).instantiate()
	chest.name = "Chest%d" % index
	chest.position = _world(entry["at"])
	chest.set(&"item_id", entry["item"])
	chest.set(&"amount", entry["amount"])
	chest.set(&"opened_flag", entry["flag"])
	_add(map, chest)


func _add_monster(map: Node2D, index: int, cell: Vector2i, enemy_id: StringName) -> void:
	var monster := (load(MONSTER_SCENE) as PackedScene).instantiate()
	monster.name = "Monster%d" % index
	monster.position = _world(cell)
	monster.set(&"enemy", load("res://resources/enemies/%s.tres" % enemy_id))
	monster.set(&"level", FloorTuning.enemy_level(FLOOR_NUMBER))
	monster.set(&"floor_number", FLOOR_NUMBER)
	_add(map, monster)


func _add_boss_gate(map: Node2D) -> void:
	var gate := (load(BOSS_GATE_SCENE) as PackedScene).instantiate()
	gate.name = "BossGate"
	gate.position = _world(GATE_CELL)
	gate.set(&"floor_number", FLOOR_NUMBER)
	gate.set(&"boss_name", "Nerith the Hollow Warden")
	gate.set(&"display_name", "the hollow door")
	_add(map, gate)


# --- checks ----------------------------------------------------------------

## Refuses to write a floor the player cannot finish. test/floor_test.gd checks
## this too, from the packed scene; doing it here as well means a bad edit to the
## tables above fails at the tool rather than one test run later.
func _verify() -> bool:
	var reachable := _flood(SPAWN_CELL)
	var required: Array[Vector2i] = [STAIRS_CELL, GATE_CELL]
	for entry in NPCS:
		required.append(entry["at"])
	for entry in CHESTS:
		required.append(entry["at"])
	for entry in MONSTERS:
		required.append(entry[0])

	var unreachable: PackedStringArray = PackedStringArray()
	for cell in required:
		if not reachable.has(cell):
			unreachable.append("%d,%d" % [cell.x, cell.y])
	if not unreachable.is_empty():
		push_error("floor 10: unreachable from the spawn: %s" % ", ".join(unreachable))
		return false
	return true


func _flood(from: Vector2i) -> Dictionary:
	if not _open.has(from):
		push_error("floor 10: the spawn point at %s is inside a wall" % from)
		return {}
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next) or not _open.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


# --- plumbing --------------------------------------------------------------

func _new_layer(map: Node2D, layer_name: String, collides: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _biome.tile_set
	layer.collision_enabled = collides
	map.add_child(layer)
	layer.owner = map
	return layer


func _add(map: Node2D, node: Node) -> void:
	map.add_child(node)
	node.owner = map


func _paint(layer: TileMapLayer, cell: Vector2i, tile: int) -> void:
	layer.set_cell(cell, SOURCE_ID, Vector2i(tile, 0))


func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


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
