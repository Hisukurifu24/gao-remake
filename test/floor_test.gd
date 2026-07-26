extends Node
## Checks the 100-floor spine: registry, generator, and progression gating.
##
##     "$GODOT" --headless --path . res://test/floor_test.tscn
##
## The expensive check is the last one: it generates every floor from 2 to 100
## and asserts each is actually completable. A dungeon whose boss door is walled
## off is the one bug procedural generation reliably ships, and it can't be
## caught by playing.

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

	# --- every generated floor is completable ---
	var broken: PackedStringArray = PackedStringArray()
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		var definition := FloorRegistry.get_floor(floor_number)
		if definition.is_authored():
			continue
		var map := FloorGenerator.generate(definition, FloorRegistry.seed_for(floor_number))
		var problem := _audit(map, floor_number)
		if not problem.is_empty():
			broken.append(problem)
		map.free()
	_check(broken.is_empty(), "all 99 generated floors are completable%s" % (
			"" if broken.is_empty() else " -- " + ", ".join(broken)))


# --- helpers ---------------------------------------------------------------

## Walks the walls layer to confirm the player can actually reach the boss door
## and every chest from the spawn point.
func _audit(map: Node2D, floor_number: int) -> String:
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
