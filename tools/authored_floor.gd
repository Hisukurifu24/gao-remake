extends SceneTree
## The shared half of every authored-floor tool.
##
## Tile data is a binary blob inside a .tscn, so an authored floor is authored in
## code and packed by the engine. Each milestone floor is one script that extends
## this one -- its layout tables at the top and a [method _build] that carves
## them -- while everything underneath lives here: painting, the wall-joining
## pass, placing entities, the completability check and the save. That split is
## what makes a milestone floor a content job rather than a fresh copy of the
## plumbing.
##
## The output has the node shape [FloorGenerator] produces (Ground / Walls /
## SpawnPoints / Player + interactables), because [GameMap], the camera and
## [SceneRouter] depend on that and on nothing else.
##
## A floor script sets [member floor_number], [member size], [member biome_path]
## and [member out_path] in [code]_init()[/code] and overrides [method _build].
## Run one with [code]-- --preview[/code] to print its layout as text instead of
## writing it: the one way to look at a floor from a headless shell, and safe to
## run after somebody has started painting the real scene in the editor.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const NPC_SCENE := "res://scenes/world/npc.tscn"
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const BOSS_GATE_SCENE := "res://scenes/world/boss_gate.tscn"
const STAIRS_SCENE := "res://scenes/world/floor_stairs.tscn"
const MONSTER_SCENE := "res://scenes/world/monster.tscn"
const EXIT_SCENE := "res://scenes/world/map_exit.tscn"
const CAMPFIRE_SCENE := "res://scenes/world/campfire.tscn"
const TELEPORT_GATE_SCENE := "res://scenes/world/teleport_gate.tscn"
## Loaded when used, never named as a class: naming one compiles it with this
## script, before the autoloads exist, and with it every scene it preloads -- whose
## scripts then fail on [code]EventBus[/code].
const GENERATOR := "res://scripts/world/floor_generator.gd"
const PUZZLES := "res://scripts/world/floor_puzzles.gd"
const CHEST_SCRIPT := "res://scripts/world/chest.gd"

## [enum FloorGenerator.Side], which side of the rest of the floor a labyrinth
## stands on; [method _grow_labyrinth] checks the two agree.
enum Side { EAST, WEST, SOUTH, NORTH }
## An authored floor's boss room, in maze cells: square, 10x10 tiles, where a
## generated one is 3x2. An authored boss is drawn full size -- Illfang is three
## tiles tall -- and in a room six deep you would face it from the bottom row,
## behind the crowns of the wall below.
const AUTHORED_BOSS_BLOCK := Vector2i(3, 3)
## [enum BrazierRite.Mode], how a pinned rite's fires are to be lit.
enum Rite { TIMED, ORDERED }
const CHARACTER_SHEET := "res://assets/ninja_adventure/Actor/Character/%s/SpriteSheet.png"

const TILE := 16
const SOURCE_ID := 0

## How [method _preview] marks what stands on a cell.
const PREVIEW_MARKS := {
	PLAYER_SCENE: "@",
	NPC_SCENE: "N",
	CHEST_SCENE: "c",
	BOSS_GATE_SCENE: "B",
	STAIRS_SCENE: "<",
	MONSTER_SCENE: "m",
	EXIT_SCENE: "E",
	CAMPFIRE_SCENE: "f",
	TELEPORT_GATE_SCENE: "T",
	"res://scenes/world/wisp.tscn": "w",
	"res://scenes/world/wisp_shrine.tscn": "s",
	"res://scenes/world/brazier.tscn": "b",
	"res://scenes/world/tablet.tscn": "t",
	"res://scenes/world/statue.tscn": "S",
	"res://scenes/world/statue_altar.tscn": "a",
	"res://scenes/world/sealed_door.tscn": "D",
	"res://scenes/world/cracked_wall.tscn": "x",
}

var floor_number := 0
var size := Vector2i.ZERO
var biome_path := ""
var out_path := ""
## What the dressing's trees and flowers are scattered by; the floor number unless
## a floor keeps an older seed so rebuilding it doesn't reshuffle its look.
var dress_seed := -1

var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool] = {}
## [rect, house variant] for every pack house, placed once the map is dressed.
var _houses: Array = []
## The floor's labyrinth, once [method _grow_labyrinth] has grown it, and the seed
## it was grown from -- which also places what stands in it.
var _lab = null  # FloorGenerator.Labyrinth -- see GENERATOR
var _lab_seed := 0
## The dead end the labyrinth's chest waits in, in cells of the maze; and the
## others, in tiles, where a teleport trap sets you down.
var _lab_chest_end := Vector2i(-1, -1)
var _deep: Array[Vector2i] = []
var _puzzles = null  # FloorPuzzles
## What the layout asked for and could not have -- a puzzle with no room for it, a
## maze with no camp. [method _verify] refuses the floor on any of them.
var _problems := PackedStringArray()


func _initialize() -> void:
	if not ResourceLoader.exists(biome_path):
		push_error("missing %s -- run tools/build_biomes.gd first" % biome_path)
		quit(1)
		return
	_biome = load(biome_path)

	var map := _build()
	# Printed before the check, so a floor that fails it can still be looked at.
	var preview := "--preview" in OS.get_cmdline_user_args()
	if preview:
		print(_preview(map))

	var problem := _verify(map)
	if not problem.is_empty():
		push_error("floor %d: %s" % [floor_number, problem])
		map.free()
		quit(1)
		return
	if preview:
		map.free()
		quit()
		return
	quit(0 if _save(map, out_path) else 1)


## Carves the layout, places everything on it and returns the map. Override it.
## [method _verify] runs on whatever comes back, so a floor script never has to
## remember to check itself.
func _build() -> Node2D:
	push_error("%s does not override _build()" % get_script().resource_path)
	return Node2D.new()


## The map root, its two tile layers, and every cell solid. A floor is carved out
## of rock rather than walled in, which is why the outer ring is sealed without
## anyone having to remember to seal it.
func _new_map(node_name: String, map_id: StringName, display_name: String) -> Node2D:
	var map := Node2D.new()
	map.name = node_name
	map.set_script(load("res://scripts/world/game_map.gd"))
	map.set(&"map_id", map_id)
	map.set(&"display_name", display_name)
	map.set(&"floor_number", floor_number)
	map.modulate = _biome.ambient_tint

	_ground = _new_layer(map, "Ground", false)
	_walls = _new_layer(map, "Walls", true)
	for y in size.y:
		for x in size.x:
			_paint(_walls, Vector2i(x, y), _biome.wall_tile)
	return map


## Writes [param places] (name -> rect) onto the map's [code]landmarks[/code], for
## the map screen to label.
func _name_places(map: Node2D, places: Dictionary) -> void:
	var named: Dictionary[String, Rect2i] = {}
	for place: String in places:
		named[place] = places[place]
	map.set(&"landmarks", named)


# --- carving ---------------------------------------------------------------


func _carve(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if _inside(cell):
				_open_cell(cell, tile)


## A cavern rather than a room: the ellipse inscribed in [param rect], see
## [method _ellipse] for what the other three do to its edge.
func _carve_cave(rect: Rect2i, tile: int, wobble := 0.12, lobes := 3, phase := 0.0) -> void:
	for cell in _ellipse(rect, wobble, lobes, phase):
		_open_cell(cell, tile)


func _carve_corridor(from: Vector2i, to: Vector2i, width := 3) -> void:
	# L-shaped with a fixed elbow. A generated floor picks the elbow from its
	# seed; an authored one has no seed and no need of one.
	var elbow := Vector2i(to.x, from.y)
	_carve_line(from, elbow, width)
	_carve_line(elbow, to, width)


## A tunnel through [param points] in order. Each leg runs along x and then along
## y, so waypoints that share a row or a column make straight legs, and a tunnel
## can jog round the rock rather than cutting one L across it.
func _carve_path(points: Array, width := 3) -> void:
	for i in range(1, points.size()):
		_carve_line(points[i - 1], points[i], width)


func _carve_line(from: Vector2i, to: Vector2i, width := 3) -> void:
	# An odd brush reaches equally either side of the line; an even one reaches one
	# further right and down, so a two-wide tunnel still has the line inside it.
	var low := -((width - 1) / 2)
	var high := width / 2
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell := from
	while true:
		for dy in range(low, high + 1):
			for dx in range(low, high + 1):
				var target := cell + Vector2i(dx, dy)
				if _inside(target) and not _open.has(target):
					_open_cell(target, _biome.path_tile)
		if cell == to:
			break
		cell += Vector2i(step.x, 0) if cell.x != to.x else Vector2i(0, step.y)


## The cells of the ellipse inscribed in [param rect], its edge pulled inwards by
## up to [param wobble] of the radius in [param lobes] smooth bulges, turned by
## [param phase] so no two caves share a silhouette. The wobble only ever pulls
## inwards, so a cave never spills out of the rect it was given -- which is what
## lets a layout table promise that two caves a few tiles apart stay apart.
func _ellipse(rect: Rect2i, wobble := 0.0, lobes := 3, phase := 0.0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var centre := Vector2(rect.position) + Vector2(rect.size) / 2.0
	var radius := Vector2(rect.size) / 2.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var offset := (Vector2(cell) + Vector2(0.5, 0.5) - centre) / radius
			var reach := 1.0 - wobble * (0.5 + 0.5 * sin(lobes * offset.angle() + phase))
			if offset.length() <= reach and _inside(cell):
				cells.append(cell)
	return cells


## A gap in the map's outer ring, where a [MapExit] to another map stands: the one
## carve allowed to reach the edge. The floor test excuses holes in the ring only
## on a map with a way off it.
func _carve_gap(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_open_cell(Vector2i(x, y), tile)


## Puts something solid back on a carved cell: a roof, a boulder, a pool.
func _block(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_close_cell(Vector2i(x, y), tile)


func _block_cells(cells: Array[Vector2i], tile: int) -> void:
	for cell in cells:
		_close_cell(cell, tile)


func _fill(layer: TileMapLayer, rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_paint(layer, Vector2i(x, y), tile)


## Repaints the ground of cells that are already open -- a street, a worn path
## across a cavern floor. Rock inside the rect is left alone, so a street can be
## laid across a rect that is only partly carved.
func _pave(rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if _open.has(cell):
				_paint(_ground, cell, tile)


## A building. On a biome with pack houses it is the Town of Beginnings' kind: a
## footprint in the invisible wall-alt slot -- every row but the roof's top one, so
## you pass behind it -- and house tile [param variant] stood over it once the map
## is dressed. [param rect] must be that tile's size; [method _verify] holds it to it.
##
## On a biome without them, a roof block with a wall course along the bottom: the
## course is plain wall, so it joins the terrain and draws a facade, and the roof
## carries no terrain and stays a flat block.
func _house(rect: Rect2i, variant := 0) -> void:
	if not _biome.house_tiles.is_empty():
		_block(Rect2i(rect.position.x, rect.position.y + 1, rect.size.x, rect.size.y - 1),
				_biome.wall_alt_tile)
		_houses.append([rect, variant])
		return
	var roof := Rect2i(rect.position, Vector2i(rect.size.x, rect.size.y - 1))
	_block(roof, _biome.wall_alt_tile)
	_block(Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1), _biome.wall_tile)


## Dresses the finished layout, last: joins the wall mass, the ground and the
## water, plants forest and scatters decor. The same [MapDresser] pass a
## generated floor gets, so a built floor and a generated one follow one rule.
## Only cells still holding the plain wall tile join the mass -- roofs, boulders
## and pools live on this layer too and are scenery. Pack houses go up after, on
## the props layer the forest was planted on.
func _join_walls() -> void:
	# The vault is carved by [FloorPuzzles], which never writes to [member _open]:
	# take it from the tiles, so the reachability check walks into it.
	for cell in _ground.get_used_cells():
		if _walls.get_cell_source_id(cell) == -1:
			_open[cell] = true
	var map := _ground.get_parent() as Node2D
	MapDresser.dress(map, _biome, _ground, _walls, floor_number if dress_seed < 0 else dress_seed)
	if _houses.is_empty():
		return
	var props := MapDresser.props_layer(map, _biome)
	for house: Array in _houses:
		if house[1] >= 0 and house[1] < _biome.house_tiles.size():
			props.set_cell(MapDresser.anchor_for(house[0]), SOURCE_ID, _biome.house_tiles[house[1]])


## The outer ring is never carved, so the map never opens onto the void.
func _inside(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.y >= 1 and cell.x < size.x - 1 and cell.y < size.y - 1


func _open_cell(cell: Vector2i, tile: int) -> void:
	_walls.erase_cell(cell)
	_paint(_ground, cell, tile)
	_open[cell] = true


func _close_cell(cell: Vector2i, tile: int) -> void:
	_paint(_walls, cell, tile)
	_open.erase(cell)


# --- the labyrinth ----------------------------------------------------------

## Grows the floor's labyrinth -- the same maze a generated floor ends in, by the
## same code -- into the rect the layout set aside for it: [param cells] of maze
## with its top-left corner at [param at], standing on the [param facing] side of
## the rest of the floor, its mouth [param along] cells down the wall that faces
## back. [param maze_seed] fixes it; a floor whose maze grows no safe zone or too
## few dead ends is refused, and the cure is another seed.
##
## Carve the corridor to [member FloorGenerator.Labyrinth.doorstep] afterwards, and
## call [method _add_labyrinth] once the map is dressed. [param boss_block] is the
## boss room's size in cells; zero for a generated floor's.
func _grow_labyrinth(at: Vector2i, cells: Vector2i, facing: int, along: int,
		maze_seed: int, boss_block := AUTHORED_BOSS_BLOCK) -> void:
	var generator: GDScript = load(GENERATOR)
	assert(generator.Side == Side, "authored_floor.gd's Side has drifted from FloorGenerator's")
	if boss_block == Vector2i.ZERO:
		boss_block = generator.BOSS_BLOCK
	_lab_seed = maze_seed
	_lab = generator.grow_into(_biome, _ground, _walls, _open, size, at, cells, facing,
			along, maze_seed, boss_block)
	var rect: Rect2i = _lab.rect
	if not Rect2i(Vector2i.ZERO, size).encloses(rect):
		_problems.append("the labyrinth %s runs off the %s map" % [rect, size])
	if not (_lab.camp as Rect2i).has_area():
		_problems.append("the labyrinth grown from seed %d has no safe zone" % maze_seed)
	if _lab.dead_ends.size() < int(generator.MIN_DEAD_ENDS) + 1:
		_problems.append("the labyrinth grown from seed %d has %d dead ends" % [
				maze_seed, _lab.dead_ends.size()])
	else:
		# One dead end keeps the labyrinth's chest, the rest are where a teleport
		# trap sets you down -- the generator's split, decided by the maze's seed.
		var rng := _lab_rng("chest")
		var pick: int = rng.randi() % _lab.dead_ends.size()
		_lab_chest_end = _lab.dead_ends[pick]
		for i in _lab.dead_ends.size():
			if i != pick:
				var end: Rect2i = _lab.cell_rect(_lab.dead_ends[i])
				_deep.append(end.end - Vector2i.ONE)


## Everything the labyrinth holds, once the map is dressed: the dark over it, the
## safe zone and its fire, the door's room, [param monsters] (enemy ids) walking
## its passages and [param chest] (a chest table row without [code]at[/code]) in
## one of its dead ends. Named [param place] on the map. [param first_monster] and
## [param chest_index] continue the floor's own numbering.
func _add_labyrinth(map: Node2D, place: String, monsters: Array, first_monster: int,
		chest: Dictionary, chest_index: int) -> void:
	map.set(&"dark_area", _lab.rect)
	map.set(&"safe_zones", [_lab.camp_room] as Array[Rect2i])
	var places: Dictionary[String, Rect2i] = (map.get(&"landmarks") as Dictionary).duplicate()
	places[place] = _lab.rect
	places["Safe Zone"] = _lab.camp_room
	map.set(&"landmarks", places)
	# What the floor test needs to find the labyrinth again, as a generated floor
	# leaves it.
	map.set_meta(&"labyrinth", _lab.rect)
	map.set_meta(&"labyrinth_mouth", _lab.mouth)
	map.set_meta(&"boss_room", _lab.boss_room)
	map.set_meta(&"safe_zone", _lab.camp_room)

	var camp: Rect2i = _lab.camp_room
	var fire := (load(CAMPFIRE_SCENE) as PackedScene).instantiate()
	fire.name = "Campfire"
	# Where the pillar between the camp's four cells stood, as on a generated floor.
	fire.position = Vector2((camp.position.x + camp.size.x / 2) * TILE,
			(camp.position.y + camp.size.y / 2 + 1) * TILE)
	_add(map, fire)

	if not chest.is_empty() and _lab_chest_end.x >= 0:
		var row := chest.duplicate()
		var end: Rect2i = _lab.cell_rect(_lab_chest_end)
		row["at"] = end.position
		_add_chest(map, chest_index, row)

	var passages: Array[Rect2i] = _lab.passages()
	var rng := _lab_rng("monsters")
	var placed: Array[Vector2i] = []
	var index := first_monster
	for enemy_id: StringName in monsters:
		for _try in 32:
			var passage: Rect2i = passages[rng.randi() % passages.size()]
			var cell := passage.position + Vector2i(rng.randi_range(0, 1), rng.randi_range(0, 1))
			if cell in placed or not _open.has(cell):
				continue
			placed.append(cell)
			_add_monster(map, index, cell, enemy_id)
			index += 1
			break


## The door's cell: the middle of the labyrinth's boss room.
func _lab_door() -> Vector2i:
	var room: Rect2i = _lab.boss_room
	return room.position + room.size / 2


func _lab_rng(what: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [_lab_seed, what])
	return rng


# --- puzzles ----------------------------------------------------------------

## Starts the floor's puzzles. [param chest_cells] are its own chests (one of them
## will hold the vault's last sigil -- a gilded one, if any is), [param keep_out]
## every cell a piece must not stand on or crowd: people, stairs, ways out. The
## labyrinth is kept out already. Then pin each puzzle to its room with
## [method _pin] before the map is dressed -- the vault is carved out of the rock,
## and its walls join like any -- and put them down with [method _place_puzzles]
## once the chests are.
func _new_puzzles(chest_cells: Array[Vector2i], keep_out: Array[Vector2i]) -> void:
	_puzzles = load(PUZZLES).new(floor_number, hash("authored:%d" % floor_number), _biome,
			_ground, _walls, _open, Rect2i(Vector2i.ONE, size - Vector2i(2, 2)))
	var rects: Array[Rect2i] = []
	for cell in keep_out:
		rects.append(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)))
	if _lab != null:
		var lab: Rect2i = _lab.rect
		rects.append(lab.grow(1))
	_puzzles.hold(chest_cells, rects)


## Refuses the floor if a puzzle the layout asked for has no room where it asked.
func _pin(done: bool, what: String) -> void:
	assert(load("res://scripts/world/brazier_rite.gd").Mode == Rite,
			"authored_floor.gd's Rite has drifted from BrazierRite's")
	if not done:
		_problems.append("%s does not fit where the layout puts it" % what)


func _place_puzzles(map: Node2D) -> void:
	if _puzzles != null:
		_puzzles.place(map)


# --- contents --------------------------------------------------------------

## [param spawns] maps a spawn name to its cell, in the order they should appear.
func _add_spawns(map: Node2D, spawns: Dictionary) -> void:
	var holder := Node2D.new()
	holder.name = "SpawnPoints"
	map.add_child(holder)
	holder.owner = map
	for spawn_name in spawns:
		var marker := Marker2D.new()
		marker.name = spawn_name
		marker.position = _world(spawns[spawn_name])
		holder.add_child(marker)
		marker.owner = map


func _add_player(map: Node2D, cell: Vector2i) -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.name = "Player"
	player.position = _world(cell)
	_add(map, player)


func _add_stairs(map: Node2D, cell: Vector2i) -> void:
	var stairs := (load(STAIRS_SCENE) as PackedScene).instantiate()
	stairs.name = "StairsDown"
	stairs.position = _world(cell)
	stairs.set(&"target_floor", floor_number - 1)
	stairs.set(&"display_name", "the stairs down")
	_add(map, stairs)


## The floor's teleport gate. Its base is three cells wide, so stand it where a
## street keeps two clear beside it; its map wants a [code]gate[/code] spawn in
## front of it, where you arrive through it.
func _add_teleport_gate(map: Node2D, cell: Vector2i) -> void:
	var gate := (load(TELEPORT_GATE_SCENE) as PackedScene).instantiate()
	gate.name = "TeleportGate"
	gate.position = _world(cell)
	gate.set(&"floor_number", floor_number)
	_add(map, gate)


## [param entry] is one row of a floor's NPC table: [code]at[/code], [code]name[/code],
## [code]display[/code], [code]flag[/code], and either [code]dialogue[/code] (a
## path) or [code]lines[/code].
func _add_npc(map: Node2D, entry: Dictionary) -> void:
	var node := (load(NPC_SCENE) as PackedScene).instantiate()
	node.name = entry["name"]
	node.position = _world(entry["at"])
	node.set(&"speaker", entry["name"])
	node.set(&"display_name", entry["display"])
	node.set(&"prompt_verb", "Talk to")
	node.set(&"lines", PackedStringArray(entry.get("lines", [])))
	node.set(&"met_flag", entry["flag"])
	# [code]look[/code] names a character folder in the Ninja Adventure pack.
	if entry.has("look"):
		node.set(&"sprite_sheet", load(CHARACTER_SHEET % entry["look"]))
	if entry.has("dialogue"):
		node.set(&"dialogue", load(entry["dialogue"]))
	_add(map, node)


## [param entry] is one row of a floor's chest table: [code]at[/code],
## [code]item[/code], [code]amount[/code], [code]flag[/code], and for a gilded one
## [code]gilded[/code] and a [code]trap[/code] -- [code]&"alarm"[/code] or
## [code]&"teleport"[/code], which sets you down in one of the labyrinth's dead ends.
## A trap on a chest that is not gilded is refused: the gilding is the tell.
func _add_chest(map: Node2D, index: int, entry: Dictionary) -> void:
	var chest := (load(CHEST_SCENE) as PackedScene).instantiate()
	chest.name = "Chest%d" % index
	chest.position = _world(entry["at"])
	chest.set(&"item_id", entry["item"])
	chest.set(&"amount", entry["amount"])
	chest.set(&"opened_flag", entry["flag"])
	chest.set(&"floor_number", floor_number)
	var gilded: bool = entry.get("gilded", false)
	chest.set(&"gilded", gilded)
	var trap: StringName = entry.get("trap", &"")
	var traps: Dictionary = load(CHEST_SCRIPT).Trap
	if trap == &"alarm" and gilded:
		chest.set(&"trap", traps["ALARM"])
	elif trap == &"teleport" and gilded and not _deep.is_empty():
		chest.set(&"trap", traps["TELEPORT"])
		chest.set(&"trap_target", _world(_deep[index % _deep.size()]))
	elif trap != &"":
		_problems.append("chest %d's %s trap wants a gilded chest (and a teleport, a labyrinth)" % [
				index, trap])
	_add(map, chest)


func _add_monster(map: Node2D, index: int, cell: Vector2i, enemy_id: StringName) -> void:
	var monster := (load(MONSTER_SCENE) as PackedScene).instantiate()
	monster.name = "Monster%d" % index
	monster.position = _world(cell)
	monster.set(&"enemy", load("res://resources/enemies/%s.tres" % enemy_id))
	monster.set(&"level", FloorTuning.enemy_level(floor_number))
	monster.set(&"floor_number", floor_number)
	_add(map, monster)


## [param zone] stretches the exit's trigger, and [param auto] walks you through it
## without a prompt -- a gap in a map's edge rather than a door.
func _add_exit(map: Node2D, node_name: String, cell: Vector2i, target_map: String,
		target_spawn: StringName, verb: String, label: String, zone := Vector2.ONE,
		auto := false) -> void:
	var exit := (load(EXIT_SCENE) as PackedScene).instantiate()
	exit.name = node_name
	exit.position = _world(cell)
	exit.scale = zone
	exit.set(&"target_map", target_map)
	exit.set(&"target_spawn", target_spawn)
	exit.set(&"prompt_verb", verb)
	exit.set(&"display_name", label)
	exit.set(&"auto_trigger", auto)
	_add(map, exit)


## In the labyrinth's boss room if the floor has one, hidden until you walk into
## it -- the generated floors' rule; [param cell] is ignored then. Otherwise at
## [param cell], in plain view.
func _add_boss_gate(map: Node2D, cell: Vector2i, boss_name: String, label: String) -> void:
	var gate := (load(BOSS_GATE_SCENE) as PackedScene).instantiate()
	gate.name = "BossGate"
	gate.position = _world(_lab_door() if _lab != null else cell)
	gate.set(&"floor_number", floor_number)
	gate.set(&"boss_name", boss_name)
	gate.set(&"display_name", label)
	if _lab != null:
		var room: Rect2i = _lab.boss_room
		gate.set(&"reveal_area", Rect2(room.position * TILE, room.size * TILE))
	_add(map, gate)


# --- checks ----------------------------------------------------------------

## Refuses a floor the player cannot finish: there has to be a door, and every
## entity and spawn point on the map has to be walkable-to from the default
## spawn. test/floor_test.gd checks the packed scene the same way; doing it here
## too means a bad edit to a layout table fails at the tool rather than a test
## run later. Entities are read off the map rather than out of the tables, so a
## new kind of thing on a floor is checked without anybody remembering to list it.
func _verify(map: Node2D) -> String:
	if not _problems.is_empty():
		return "; ".join(_problems)
	var spawns := map.get_node_or_null("SpawnPoints")
	if spawns == null or spawns.get_child_count() == 0:
		return "there are no spawn points"
	if map.get_node_or_null("BossGate") == null:
		return "there is no boss gate"
	var houses := _house_problem()
	if not houses.is_empty():
		return houses

	var arrival := spawns.get_node_or_null("default") as Node2D
	if arrival == null:
		arrival = spawns.get_child(0) as Node2D
	var start := _cell_of(arrival)
	if not _open.has(start):
		return "the spawn point at %d,%d is inside a wall" % [start.x, start.y]

	var reachable := _flood(start)
	var things := map.get_children()
	things.append_array(spawns.get_children())
	var stranded := PackedStringArray()
	for child in things:
		var node := child as Node2D
		if node == null or node is TileMapLayer or node == spawns:
			continue
		# A cracked wall stands in the wall it cracks, and its chest in the rock
		# behind it: the floor test breaks it open and walks in.
		if node.name in [&"CrackedWall", &"ChestCrack"]:
			continue
		var cell := _cell_of(node)
		if not reachable.has(cell):
			stranded.append("%s at %d,%d" % [node.name, cell.x, cell.y])
	if not stranded.is_empty():
		return "unreachable from the spawn: " + ", ".join(stranded)
	return ""


## A house stands on the bottom row of its rect, so a rect that disagrees with its
## tile draws the roof off the footprint: an invisible wall beside a roof you walk
## straight through.
func _house_problem() -> String:
	var source := _biome.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	for house: Array in _houses:
		var rect: Rect2i = house[0]
		var variant: int = house[1]
		if variant < 0 or variant >= _biome.house_tiles.size():
			return "the house at %d,%d asks for house %d of %d" % [
					rect.position.x, rect.position.y, variant, _biome.house_tiles.size()]
		var tile := source.get_tile_size_in_atlas(_biome.house_tiles[variant])
		if tile != rect.size:
			return "the house at %d,%d is %dx%d but house %d is %dx%d" % [
					rect.position.x, rect.position.y, rect.size.x, rect.size.y, variant, tile.x, tile.y]
	return ""


func _flood(from: Vector2i) -> Dictionary:
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


## The floor as text, one character per cell: [code]#[/code] rock, [code]^[/code]
## roofs, [code]o[/code] boulders, [code]~[/code] water, [code].[/code] floor,
## [code]:[/code] alternate floor, [code],[/code] paths, [code]*[/code] special
## ground, and a letter for whatever stands there (see [constant PREVIEW_MARKS]).
func _preview(map: Node2D) -> String:
	var marks := {}
	for child in map.get_children():
		var node := child as Node2D
		if node != null and PREVIEW_MARKS.has(node.scene_file_path):
			marks[_cell_of(node)] = PREVIEW_MARKS[node.scene_file_path]

	var rows := PackedStringArray()
	for y in size.y:
		var row := ""
		for x in size.x:
			var cell := Vector2i(x, y)
			row += marks[cell] if marks.has(cell) else _terrain_mark(cell)
		rows.append(row)
	return "\n".join(rows)


func _terrain_mark(cell: Vector2i) -> String:
	if _walls.get_cell_source_id(cell) != -1:
		var slot := _walls.get_cell_atlas_coords(cell)
		if slot.y > 0 or slot.x == _biome.wall_tile:
			return "#"  # the wall mass, joined or not
		if slot.x == _biome.wall_alt_tile:
			return "^"
		if slot.x == _biome.liquid_tile:
			return "~"
		return "o"
	if _ground.get_cell_source_id(cell) == -1:
		return " "
	var ground := _ground.get_cell_atlas_coords(cell).x
	if ground == _biome.path_tile:
		return ","
	if ground == _biome.special_tile:
		return "*"
	if ground == _biome.floor_alt_tile:
		return ":"
	return "."


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


## Gives [param root] everything under it that nobody owns -- what [FloorPuzzles]
## puts down, built for a generated floor that is never saved -- so it is packed
## with the scene. A node inside an instanced scene is owned by that scene's root
## already, and stays so.
func _adopt(root: Node, node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = root
		if child.scene_file_path.is_empty():
			_adopt(root, child)


func _cell_of(node: Node2D) -> Vector2i:
	return Vector2i(floori(node.position.x / TILE), floori(node.position.y / TILE))


func _save(node: Node, path: String) -> bool:
	_adopt(node, node)
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		return false
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return false
	node.free()
	print("wrote ", path)
	return true
