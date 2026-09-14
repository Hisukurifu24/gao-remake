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
}

var floor_number := 0
var size := Vector2i.ZERO
var biome_path := ""
var out_path := ""

var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool] = {}


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


## A building, as a roof block with a wall course along the bottom -- the same
## trick the Town of Beginnings uses. The course is plain wall, so it joins the
## terrain and draws a facade; the roof carries no terrain and stays a flat block.
func _house(rect: Rect2i) -> void:
	var roof := Rect2i(rect.position, Vector2i(rect.size.x, rect.size.y - 1))
	_block(roof, _biome.wall_alt_tile)
	_block(Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1), _biome.wall_tile)


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
	monster.set(&"level", FloorTuning.enemy_level(floor_number))
	monster.set(&"floor_number", floor_number)
	_add(map, monster)


func _add_exit(map: Node2D, node_name: String, cell: Vector2i, target_map: String,
		target_spawn: StringName, verb: String, label: String) -> void:
	var exit := (load(EXIT_SCENE) as PackedScene).instantiate()
	exit.name = node_name
	exit.position = _world(cell)
	exit.set(&"target_map", target_map)
	exit.set(&"target_spawn", target_spawn)
	exit.set(&"prompt_verb", verb)
	exit.set(&"display_name", label)
	_add(map, exit)


func _add_boss_gate(map: Node2D, cell: Vector2i, boss_name: String, label: String) -> void:
	var gate := (load(BOSS_GATE_SCENE) as PackedScene).instantiate()
	gate.name = "BossGate"
	gate.position = _world(cell)
	gate.set(&"floor_number", floor_number)
	gate.set(&"boss_name", boss_name)
	gate.set(&"display_name", label)
	_add(map, gate)


# --- checks ----------------------------------------------------------------

## Refuses a floor the player cannot finish: there has to be a door, and every
## entity and spawn point on the map has to be walkable-to from the default
## spawn. test/floor_test.gd checks the packed scene the same way; doing it here
## too means a bad edit to a layout table fails at the tool rather than a test
## run later. Entities are read off the map rather than out of the tables, so a
## new kind of thing on a floor is checked without anybody remembering to list it.
func _verify(map: Node2D) -> String:
	var spawns := map.get_node_or_null("SpawnPoints")
	if spawns == null or spawns.get_child_count() == 0:
		return "there are no spawn points"
	if map.get_node_or_null("BossGate") == null:
		return "there is no boss gate"

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
		var cell := _cell_of(node)
		if not reachable.has(cell):
			stranded.append("%s at %d,%d" % [node.name, cell.x, cell.y])
	if not stranded.is_empty():
		return "unreachable from the spawn: " + ", ".join(stranded)
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


func _cell_of(node: Node2D) -> Vector2i:
	return Vector2i(floori(node.position.x / TILE), floori(node.position.y / TILE))


func _save(node: Node, path: String) -> bool:
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
