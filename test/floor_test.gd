extends Node
## Checks the 100-floor spine: registry, generator, and progression gating.
##
##     "$GODOT" --headless --path . res://test/floor_test.tscn
##
## The expensive check is the last one: it generates every floor from 2 to 100
## and asserts each is actually completable. A dungeon whose boss door is walled
## off is the one bug procedural generation reliably ships, and it can't be
## caught by playing.

## Where each peering bit points. Sides are checked strictly; a corner is only
## meaningful when both sides beside it are wall, which is the same reduction
## that takes the blob from 256 arrangements down to 47.
const SIDES := {
	TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i.UP,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i.RIGHT,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i.DOWN,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i.LEFT,
}
## corner bit -> [the diagonal, the two sides it depends on]
const CORNERS := {
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: [Vector2i(1, -1), Vector2i.UP, Vector2i.RIGHT],
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: [Vector2i(1, 1), Vector2i.DOWN, Vector2i.RIGHT],
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: [Vector2i(-1, 1), Vector2i.DOWN, Vector2i.LEFT],
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: [Vector2i(-1, -1), Vector2i.UP, Vector2i.LEFT],
}

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0


func _ready() -> void:
	_run()
	print("")
	if _failures.is_empty():
		print("floor test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("floor test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	GameState.new_world_seed(12345)

	# --- registry ---
	var first := FloorRegistry.get_floor(1)
	_check(first.is_authored(), "floor 1 is authored")
	_check(first.display_name == "Town of Beginnings", "floor 1 keeps its authored name")

	var thirty_seven := FloorRegistry.get_floor(37)
	_check(not thirty_seven.is_authored(), "floor 37 is generated")
	_check(thirty_seven.biome != null and thirty_seven.biome.id == &"ruins",
			"floor 37 lands in the ruins band (got %s)" % thirty_seven.biome.id)
	_check(FloorRegistry.biome_id(9) == &"meadow" and FloorRegistry.biome_id(10) == &"forest",
			"biome bands change on the tens")
	_check(FloorRegistry.biome_id(100) == &"castle", "floor 100 is the Ruby Palace")

	var missing_biome := 0
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		if FloorRegistry.get_biome(floor_number) == null:
			missing_biome += 1
	_check(missing_biome == 0, "every floor 1-100 resolves a biome (%d missing)" % missing_biome)

	# --- determinism ---
	var seed_a := FloorRegistry.seed_for(37)
	var seed_b := FloorRegistry.seed_for(37)
	_check(seed_a == seed_b, "a floor's seed is stable within a save")
	_check(FloorRegistry.seed_for(37) != FloorRegistry.seed_for(38), "floors differ from each other")

	var map_a := FloorGenerator.generate(thirty_seven, seed_a)
	var map_b := FloorGenerator.generate(thirty_seven, seed_a)
	_check(_fingerprint(map_a) == _fingerprint(map_b), "the same seed regenerates the same floor")

	GameState.new_world_seed(999)
	var other_seed := FloorRegistry.seed_for(37)
	var map_c := FloorGenerator.generate(thirty_seven, other_seed)
	_check(_fingerprint(map_a) != _fingerprint(map_c), "a different save gives a different floor 37")
	GameState.new_world_seed(12345)

	for map in [map_a, map_b, map_c]:
		map.free()

	# --- progression gating ---
	_check(GameState.is_floor_unlocked(1), "floor 1 starts unlocked")
	_check(not GameState.is_floor_unlocked(2), "floor 2 starts locked")
	GameState.clear_floor(1)
	_check(GameState.is_floor_unlocked(2), "clearing floor 1 unlocks floor 2")
	_check(not GameState.is_floor_unlocked(3), "clearing floor 1 does not unlock floor 3")
	_check(GameState.highest_floor_reached() == 2, "highest reached tracks the clear")
	_check(GameState.has_flag(&"floor_1_cleared"), "clearing a floor sets its world flag")

	# --- boss naming ---
	_check(FloorTuning.boss_name(37) == FloorTuning.boss_name(37), "boss names are deterministic")
	var unique_names := {}
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		unique_names[FloorTuning.boss_name(floor_number)] = true
	_check(unique_names.size() >= 50,
			"generated boss names are varied (%d distinct over 100 floors)" % unique_names.size())

	# --- wall autotiling ---
	var without_terrain: PackedStringArray = PackedStringArray()
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		var biome := FloorRegistry.get_biome(floor_number)
		if biome != null and biome.wall_terrain_set < 0:
			without_terrain.append(String(biome.id))
	_check(without_terrain.is_empty(),
			"every biome carries a wall terrain%s" % (
				"" if without_terrain.is_empty() else " -- missing on " + ", ".join(without_terrain)))

	var tiled := FloorGenerator.generate(thirty_seven, FloorRegistry.seed_for(37))
	var tiled_walls := tiled.get_node("Walls") as TileMapLayer
	var mismatched := _mismatched_wall_tiles(tiled_walls)
	var edges := _edge_tile_count(tiled_walls)
	var uncollidable := _uncollidable_wall_tiles(tiled_walls)
	_check(mismatched == 0, "every wall tile matches its neighbours (%d wrong)" % mismatched)
	_check(edges > 0, "the wall mass is joined up rather than left flat (%d edge tiles)" % edges)
	_check(uncollidable == 0, "every autotiled wall still collides (%d that don't)" % uncollidable)
	tiled.free()

	# --- every generated floor is completable ---
	var broken: PackedStringArray = PackedStringArray()
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		var definition := FloorRegistry.get_floor(floor_number)
		if definition.is_authored():
			continue
		var map := FloorGenerator.generate(definition, FloorRegistry.seed_for(floor_number))
		var problem := _audit(map, definition)
		if not problem.is_empty():
			broken.append(problem)
		map.free()
	_check(broken.is_empty(), "all 99 generated floors are completable%s" % (
			"" if broken.is_empty() else " -- " + ", ".join(broken)))

	# --- and so is every authored one ---
	var broken_authored: PackedStringArray = PackedStringArray()
	for floor_number in FloorRegistry.AUTHORED:
		var problem := _audit_authored(floor_number)
		if not problem.is_empty():
			broken_authored.append(problem)
	_check(broken_authored.is_empty(), "every authored floor is completable%s" % (
			"" if broken_authored.is_empty() else " -- " + ", ".join(broken_authored)))


# --- helpers ---------------------------------------------------------------

## True when a cell is part of the wall mass. Decor -- the boulders and pools
## scattered inside rooms -- also lives on this layer but carries no terrain, so
## the mass is correct to draw an edge against it.
func _is_wall(walls: TileMapLayer, cell: Vector2i) -> bool:
	var data := walls.get_cell_tile_data(cell)
	return data != null and data.terrain_set >= 0


## Counts wall cells whose chosen tile describes neighbours it doesn't have.
##
## This is the check that catches the art and the terrain data drifting apart --
## a mis-paired blob leaves the floor perfectly completable and merely wrong to
## look at, so nothing else in the suite would say a word about it.
func _mismatched_wall_tiles(walls: TileMapLayer) -> int:
	var bad := 0
	for cell in walls.get_used_cells():
		var data := walls.get_cell_tile_data(cell)
		if data == null or data.terrain_set < 0:
			continue
		var wrong := false
		for bit in SIDES:
			if (data.get_terrain_peering_bit(bit) >= 0) != _is_wall(walls, cell + SIDES[bit]):
				wrong = true
		for bit in CORNERS:
			var corner: Array = CORNERS[bit]
			if not (_is_wall(walls, cell + corner[1]) and _is_wall(walls, cell + corner[2])):
				continue
			if (data.get_terrain_peering_bit(bit) >= 0) != _is_wall(walls, cell + corner[0]):
				wrong = true
		if wrong:
			bad += 1
	return bad


## Wall cells that border something other than wall -- i.e. the ones autotiling
## exists to draw. Zero of them means the pass silently did nothing.
func _edge_tile_count(walls: TileMapLayer) -> int:
	var edges := 0
	for cell in walls.get_used_cells():
		var data := walls.get_cell_tile_data(cell)
		if data == null or data.terrain_set < 0:
			continue
		for bit in SIDES:
			if data.get_terrain_peering_bit(bit) < 0:
				edges += 1
				break
	return edges


func _uncollidable_wall_tiles(walls: TileMapLayer) -> int:
	var open := 0
	for cell in walls.get_used_cells():
		var data := walls.get_cell_tile_data(cell)
		if data == null or data.terrain_set < 0:
			continue
		if data.get_collision_polygons_count(0) == 0:
			open += 1
	return open


## Walks the walls layer to confirm the player can actually reach the boss door
## and every chest from the spawn point.
func _audit(map: Node2D, definition: FloorDefinition) -> String:
	var floor_number := definition.floor_number
	var walls := map.get_node_or_null("Walls") as TileMapLayer
	var spawns := map.get_node_or_null("SpawnPoints")
	var gate := map.get_node_or_null("BossGate")
	if walls == null or spawns == null or gate == null:
		return "floor %d is missing Walls/SpawnPoints/BossGate" % floor_number

	var start: Vector2i = walls.local_to_map((spawns.get_child(0) as Node2D).position)
	if walls.get_cell_source_id(start) != -1:
		return "floor %d spawns inside a wall" % floor_number

	var reachable := _flood(walls, start)
	if not reachable.has(walls.local_to_map(gate.position)):
		return "floor %d boss gate is unreachable" % floor_number

	for child in map.get_children():
		if not child.name.begins_with("Chest"):
			continue
		if not reachable.has(walls.local_to_map((child as Node2D).position)):
			return "floor %d has an unreachable chest" % floor_number

	# Autotiling rewrites every wall on the floor. Dropping one instead of
	# replacing it would open the map onto the void, and the flood fill above
	# would quietly reach further rather than fail -- so the sealed outer ring,
	# which nothing is ever allowed to carve, is checked directly.
	for x in definition.size.x:
		if not _sealed(walls, Vector2i(x, 0)) or not _sealed(walls, Vector2i(x, definition.size.y - 1)):
			return "floor %d has a hole in its outer wall" % floor_number
	for y in definition.size.y:
		if not _sealed(walls, Vector2i(0, y)) or not _sealed(walls, Vector2i(definition.size.x - 1, y)):
			return "floor %d has a hole in its outer wall" % floor_number
	return ""


func _sealed(walls: TileMapLayer, cell: Vector2i) -> bool:
	return walls.get_cell_source_id(cell) != -1


## The same completability guarantee, for the floors a person built by hand.
##
## Hand-authoring fails at this exactly the way generation does -- a door with no
## path to it is invisible until somebody plays that far -- and it is worse here,
## because there is no seed to blame and no second floor that got it right. It
## also has to cope with a shape generation never produces: an authored floor may
## span several maps. Floor 1 is a town and a field joined by a MapExit with the
## labyrinth door in the field, so the walk follows exits instead of stopping at
## the first map it is handed.
func _audit_authored(floor_number: int) -> String:
	# [map, the spawn point it was entered at, a name for error messages]
	var pending: Array = [[FloorRegistry.build_floor(floor_number), &"", "floor %d" % floor_number]]
	var visited := {}
	var found_gate := false
	var found_exit := false
	var problem := ""

	while not pending.is_empty():
		var job: Array = pending.pop_back()
		var map: Node2D = job[0]
		var arrival: StringName = job[1]
		var label: String = job[2]
		if map == null:
			problem = "%s built nothing" % label
			break

		var walls := map.get_node_or_null("Walls") as TileMapLayer
		var spawns := map.get_node_or_null("SpawnPoints")
		if walls == null or spawns == null or spawns.get_child_count() == 0 \
				or map.get_node_or_null("Player") == null:
			problem = "%s is missing Walls/SpawnPoints/Player" % label
			map.free()
			break

		var marker := spawns.get_node_or_null(String(arrival)) as Node2D
		if marker == null:
			marker = spawns.get_child(0) as Node2D
		var start: Vector2i = walls.local_to_map(marker.position)
		if walls.get_cell_source_id(start) != -1:
			problem = "%s spawns inside a wall" % label
			map.free()
			break

		# Bounded, unlike the generated-floor fill: an authored map is allowed
		# holes in its border where a MapExit sits in them, and an unbounded fill
		# walks out through one of those and expands across empty space forever.
		var reachable := _flood_within(walls, start, walls.get_used_rect())
		var stranded: PackedStringArray = PackedStringArray()
		for child in map.get_children():
			var node := child as Node2D
			if node == null or node is TileMapLayer:
				continue
			if node.name == "SpawnPoints" or node.name == "Player":
				continue
			if not reachable.has(walls.local_to_map(node.position)):
				stranded.append(node.name)
				continue
			if node.name == "BossGate" and int(node.get(&"floor_number")) == floor_number:
				found_gate = true
			if "target_map" in node and not str(node.get(&"target_map")).is_empty():
				found_exit = true
				var target := str(node.get(&"target_map"))
				var spawn: StringName = node.get(&"target_spawn")
				var key := "%s|%s" % [target, spawn]
				if not visited.has(key) and ResourceLoader.exists(target):
					visited[key] = true
					pending.append([(load(target) as PackedScene).instantiate(), spawn, target])

		if not stranded.is_empty():
			problem = "%s strands %s" % [label, ", ".join(stranded)]
			map.free()
			break

		# A floor with no way off it is a floor whose walls are all there is
		# between the player and the void, so the outer ring has to hold -- the
		# same check the generated floors get, and for the same reason: autotiling
		# rewrote every one of those walls. A floor that *does* have a MapExit has
		# legitimate holes in its border (Floor 1's town opens onto its field
		# through one), and they are its exits rather than mistakes.
		if not found_exit:
			var used := walls.get_used_rect()
			for x in range(used.position.x, used.end.x):
				if not _sealed(walls, Vector2i(x, used.position.y)) \
						or not _sealed(walls, Vector2i(x, used.end.y - 1)):
					problem = "%s has a hole in its outer wall" % label
					break
			for y in range(used.position.y, used.end.y):
				if not _sealed(walls, Vector2i(used.position.x, y)) \
						or not _sealed(walls, Vector2i(used.end.x - 1, y)):
					problem = "%s has a hole in its outer wall" % label
					break

		map.free()
		if not problem.is_empty():
			break

	for job in pending:
		if job[0] != null:
			(job[0] as Node).free()

	if not problem.is_empty():
		return problem
	if not found_gate:
		return "floor %d has no reachable boss gate" % floor_number
	return ""


func _flood(walls: TileMapLayer, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next) or walls.get_cell_source_id(next) != -1:
				continue
			seen[next] = true
			queue.append(next)
	return seen


## [method _flood], kept inside [param bounds]. See its one caller for why.
func _flood_within(walls: TileMapLayer, from: Vector2i, bounds: Rect2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next) or not bounds.has_point(next):
				continue
			if walls.get_cell_source_id(next) != -1:
				continue
			seen[next] = true
			queue.append(next)
	return seen


## Cheap structural hash of a generated map, for comparing two generations.
func _fingerprint(map: Node2D) -> String:
	var walls := map.get_node("Walls") as TileMapLayer
	var cells := walls.get_used_cells()
	var parts: PackedStringArray = PackedStringArray()
	for cell in cells:
		parts.append("%d,%d" % [cell.x, cell.y])
	parts.append(str(map.get_child_count()))
	return str(hash(",".join(parts)))


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
