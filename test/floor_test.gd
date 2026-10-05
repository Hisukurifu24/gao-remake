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
## A tile's size in pixels, on every biome.
const TILE := 16

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
## Gathered by [method _audit_labyrinth] across every generated floor.
var _lab_floors := 0
var _lab_not_farthest := 0
var _lab_walks: Array[int] = []
## Gilded chests across every generated floor, by [enum Chest.Trap].
var _gilded: Dictionary[int, int] = {}
## Gathered by [method _audit_formations] across every map with monsters on it.
var _formations := 0
var _hidden_formations := 0
var _slid_formations := 0
## Monster fights too tall for [constant BattleStage.ZOOM], framed at 1 instead.
var _wide_formations := 0
var _unstaged: PackedStringArray = PackedStringArray()
## Gathered by [method _audit_boss_formations] across every floor's door.
var _boss_formations := 0
var _boss_doors := 0
var _boss_from_behind := 0
var _boss_close := 0
## Gathered by [method _audit_puzzles] across every generated floor.
var _wisps := 0
var _shortest_wisp := 1 << 30
var _rites: Dictionary[int, int] = {}
## The tightest a timed rite's burn is against walking its shortest way round.
var _tightest_burn := INF
var _rings := 0
var _fewest_ring_turns := 1 << 30
var _most_ring_turns := 0
var _vaults := 0
var _gilded_sigils := 0
var _cracks := 0
var _cracks_in_trees := 0
## Cracked walls in a room's north wall, facing you; the rest are in a side wall.
var _cracks_facing := 0


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

	# --- fog of war ---
	# A wall five cells to your east, nine tall: the wall is seen, what is behind it
	# is not, and open ground is seen out to the radius and no further.
	var solid := {}
	for y in range(-4, 5):
		solid[Vector2i(2, y)] = true
	var seen := FogOfWar.visible_from(Vector2i.ZERO, FogOfWar.RADIUS, func(cell: Vector2i) -> bool:
		return solid.has(cell))
	_check(Vector2i(2, 0) in seen and Vector2i(2, 3) in seen, "fog of war sees the wall in front of you")
	_check(not (Vector2i(4, 0) in seen) and not (Vector2i(6, 2) in seen), "and not what is behind it")
	_check(Vector2i(-FogOfWar.RADIUS, 0) in seen and not (Vector2i(-FogOfWar.RADIUS - 1, 0) in seen),
			"open ground is seen out to the radius and no further")
	_check(GameState.explore(&"fog_test", seen) == seen.size() and GameState.explore(&"fog_test", seen) == 0,
			"explored cells are remembered, each once")
	_check(GameState.is_explored(&"fog_test", Vector2i(2, 0)) and not GameState.is_explored(&"fog_test", Vector2i(4, 0))
			and not GameState.is_explored(&"elsewhere", Vector2i.ZERO), "and remembered per map")

	# On real floors: water is seen across, the wall mass is not. Water shares the
	# Walls layer with the rock, and after dressing it is told apart only by its
	# terrain -- get that wrong and the far shore of every pond stays unexplored.
	var misread: PackedStringArray = PackedStringArray()
	var bands_with_water := 0
	for sample: int in [5, 15, 24, 37, 45, 55, 65, 75, 85, 95]:
		var fog_floor := FloorGenerator.generate(FloorRegistry.get_floor(sample), FloorRegistry.seed_for(sample))
		var fog_walls := fog_floor.get_node("Walls") as TileMapLayer
		var water := 0
		var rock_seen_through := 0
		for cell in fog_walls.get_used_cells():
			if fog_floor.call(&"is_water", cell):
				water += 1
				if fog_floor.call(&"blocks_sight", cell):
					rock_seen_through += 1
			elif not fog_floor.call(&"blocks_sight", cell):
				rock_seen_through += 1
		if rock_seen_through > 0:
			misread.append("%d (%d wrong)" % [sample, rock_seen_through])
		if water > 0:
			bands_with_water += 1
		fog_floor.free()
	# Not every floor draws a pool (55's seed draws none), but most bands must, or
	# the water half of this check is passing on nothing.
	_check(misread.is_empty() and bands_with_water >= 7,
			"fog of war sees across water and not through rock (water on %d of 10 bands)%s" % [
				bands_with_water, "" if misread.is_empty() else " -- not on " + ", ".join(misread)])

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
		if biome != null and biome.wall_terrain_set < 0 \
				and biome.wall_style != BiomeKit.WallStyle.TREES:
			without_terrain.append(String(biome.id))
	_check(without_terrain.is_empty(),
			"every biome dresses its wall mass, as a blob or as forest%s" % (
				"" if without_terrain.is_empty() else " -- missing on " + ", ".join(without_terrain)))

	# Floors 24, 37, 55 and 75 are the cave's, the ruins', the desert's and the volcanic
	# band's blobs, put together from the pack's cliffs; 85 the sky's, rims and earth
	# undersides round open sky; 95 the castle's, dressed stone drawn a pixel at a time
	# from the pack's interior walls -- all on a Walls layer they share with pools that
	# carry a terrain of their own. No band draws placeholder walls any more.
	for sample: int in [24, 37, 55, 75, 85, 95]:
		var sample_floor := FloorRegistry.get_floor(sample)
		var wall_set := sample_floor.biome.wall_terrain_set
		var label := "floor %d (%s)" % [sample, sample_floor.biome.id]
		var tiled := FloorGenerator.generate(sample_floor, FloorRegistry.seed_for(sample))
		var tiled_walls := tiled.get_node("Walls") as TileMapLayer
		var mismatched := _mismatched_wall_tiles(tiled_walls, wall_set)
		var edges := _edge_tile_count(tiled_walls, wall_set)
		var uncollidable := _uncollidable_wall_tiles(tiled_walls, wall_set)
		_check(wall_set >= 0, "%s has a wall terrain to join" % label)
		_check(mismatched == 0, "every wall tile on %s matches its neighbours (%d wrong)" % [label, mismatched])
		_check(edges > 0, "%s's wall mass is joined up rather than left flat (%d edge tiles)" % [label, edges])
		_check(uncollidable == 0, "every autotiled wall on %s still collides (%d that don't)" % [label, uncollidable])
		# The sky's wall mass is a window onto the backdrop, rimmed and hung with earth where it
		# meets the floor. Got wrong, a lawn runs straight off into the sky -- a tile
		# that describes its neighbours perfectly, and so is invisible to the check above.
		if sample_floor.biome.id == &"sky":
			var sky_biome := sample_floor.biome
			var open := _see_through_edges(tiled_walls, sky_biome)
			_check(open == 0, "every lawn edge on %s is rimmed or faced, not open to the sky (%d open)" % [
					label, open])
			var slot := _tile_image(sky_biome, Vector2i(sky_biome.wall_tile, 0))
			_check(sky_biome.backdrop != null and slot.get_pixel(8, 8).a == 0.0
					and tiled.get_node_or_null(MapDresser.BACKDROP) is Parallax2D,
					"%s's wall mass is see-through, over its backdrop" % label)
		# The castle's masonry is a band along every floor it faces, drawn by whichever
		# floor is nearest each pixel. Got wrong, a hall runs straight into the dark of
		# the wall's top with no wall there -- again a tile whose neighbours are right.
		if sample_floor.biome.id == &"castle":
			var bare := _bare_masonry_edges(tiled_walls, sample_floor.biome)
			_check(bare == 0, "every wall facing a hall on %s is faced with masonry (%d bare)" % [label, bare])
		tiled.free()

	# --- dressing: forest, ground and water ---
	# Floors 5, 15, 24, 37, 45, 55, 65, 75, 85 and 95 are the meadow, the forest, the
	# cave, the ruins, the swamp, the desert, the ice, the volcanic band, the sky and the
	# castle -- every band, all on the pack: the cave, the ruins, the desert and the
	# volcanic band wall with cliffs, the sky with a drop, the castle with masonry, the
	# rest with trees, and all ten join their ground and water into edges. None of that
	# may touch collision, and all of it has to come out the same from the same seed.
	var styles := {5: BiomeKit.WallStyle.TREES, 15: BiomeKit.WallStyle.TREES,
			24: BiomeKit.WallStyle.BLOB, 37: BiomeKit.WallStyle.BLOB,
			45: BiomeKit.WallStyle.TREES, 55: BiomeKit.WallStyle.BLOB,
			65: BiomeKit.WallStyle.TREES, 75: BiomeKit.WallStyle.BLOB,
			85: BiomeKit.WallStyle.BLOB, 95: BiomeKit.WallStyle.BLOB}
	for sample: int in styles:
		var sample_floor := FloorRegistry.get_floor(sample)
		var sample_biome := sample_floor.biome
		var label := "floor %d (%s)" % [sample, sample_biome.id]
		var trees: bool = styles[sample] == BiomeKit.WallStyle.TREES
		_check(sample_biome.wall_style == styles[sample] and sample_biome.ground_terrain_set >= 0,
				"%s is a pack biome walling with %s" % [label, "trees" if trees else "a blob"])
		var dressed := FloorGenerator.generate(sample_floor, FloorRegistry.seed_for(sample))
		var props := dressed.get_node_or_null(MapDresser.PROPS) as TileMapLayer
		var decor := dressed.get_node_or_null(MapDresser.DECOR) as TileMapLayer
		if trees:
			_check(dressed.y_sort_enabled and props != null and props.y_sort_enabled,
					"%s sorts its props with the player" % label)
		_check((props == null or not props.collision_enabled) and decor != null and not decor.collision_enabled,
				"on %s no dressing layer collides" % label)
		if trees and props != null:
			# Bar the cracked boulder's own doorway, which the boulder stands on.
			var bare := _bare_forest_edges(dressed.get_node("Walls") as TileMapLayer, props, sample_biome,
					_crack_door(dressed))
			_check(bare == 0, "every edge of %s's forest has a tree standing on it (%d bare)" % [label, bare])
		var ground_layer := dressed.get_node("Ground") as TileMapLayer
		var off := _ground_mismatches(ground_layer, sample_biome)
		var ground_cells := ground_layer.get_used_cells().size()
		_check(off == 0, "%s's ground edges match their neighbours (%d of %d cells off)" % [
				label, off, ground_cells])
		# The pack draws no one-cell pond; the nearest tile it has is a strip's cut-off
		# end, so build_biomes.gd composes one. Nearest match would never say it's gone.
		var lone := MapDresser.TerrainMatcher.new(sample_biome.tile_set, sample_biome.liquid_terrain_set,
				sample_biome.liquid_terrain).pick(Vector2i.ZERO, {Vector2i.ZERO: true}, sample_biome.liquid_terrain)
		var lone_source := sample_biome.tile_set.get_source(MapDresser.SOURCE_ID) as TileSetAtlasSource
		_check(lone.x >= 0 and MapDresser.tile_flags(lone_source.get_tile_data(lone, 0),
				sample_biome.liquid_terrain) == 0,
				"a lone pool on %s draws a whole pond, not a strip's end" % label)
		# The matcher cannot tell a real lone pond from a pond cell misread as linking
		# to nothing: both claim no links, and a lone pool picks between them by hash.
		# Only the art can: a tile that links nowhere draws no water on its edges.
		var stray := _unlinked_water_on_edges(lone_source, sample_biome)
		_check(stray.is_empty(), "every pool tile on %s that links nowhere keeps its water off its edges%s" % [
				label, "" if stray.is_empty() else " -- not " + ", ".join(stray)])
		var again := FloorGenerator.generate(sample_floor, FloorRegistry.seed_for(sample))
		_check(_layer_signature(dressed, MapDresser.PROPS) == _layer_signature(again, MapDresser.PROPS)
				and _layer_signature(dressed, "Ground") == _layer_signature(again, "Ground")
				and _layer_signature(dressed, MapDresser.DECOR) == _layer_signature(again, MapDresser.DECOR),
				"dressing %s is deterministic: one seed, one look" % label)
		dressed.free()
		again.free()

	# --- every generated floor is completable ---
	var broken: PackedStringArray = PackedStringArray()
	var generated := 0
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		var definition := FloorRegistry.get_floor(floor_number)
		if definition.is_authored():
			continue
		generated += 1
		var map := FloorGenerator.generate(definition, FloorRegistry.seed_for(floor_number))
		var problem := _audit(map, definition)
		if not problem.is_empty():
			broken.append(problem)
		map.free()
	_check(broken.is_empty(), "all %d generated floors are completable%s" % [generated,
			"" if broken.is_empty() else " -- " + ", ".join(broken)])
	# The door is somewhere in the far third of the maze, not in its farthest corner
	# every time -- or the labyrinth is a corridor with a known end.
	_check(_lab_floors == generated and _lab_not_farthest * 4 >= _lab_floors,
			"the boss room is not always the labyrinth's farthest point (%d of %d floors aren't)" % [
				_lab_not_farthest, _lab_floors])
	var shortest := 1 << 30
	for walk in _lab_walks:
		shortest = mini(shortest, walk)
	# Measured at 70 over four world seeds, 64 on this one since the safe zone joined
	# the reasons a maze is regrown. It was 28 when the maze fitted on about a
	# screen, which is what made it read as a corridor -- see M5.5 §5 in plan.md.
	_check(shortest >= 60, "the labyrinth always stands in front of the door (shortest walk in: %d tiles)" % shortest)
	# A gilded chest is a gamble only if all three outcomes turn up somewhere.
	var plain: int = _gilded.get(Chest.Trap.NONE, 0)
	var alarms: int = _gilded.get(Chest.Trap.ALARM, 0)
	var teleports: int = _gilded.get(Chest.Trap.TELEPORT, 0)
	_check(plain > 0 and alarms > 0 and teleports > 0,
			"gilded chests are sometimes safe, sometimes alarms, sometimes teleports (%d / %d / %d)" % [
				plain, alarms, teleports])
	# Puzzles: solvable wherever they are (in the audit above), and on nearly every
	# floor -- a puzzle that only turns up on a third of them is a rumour.
	var timed: int = _rites.get(BrazierRite.Mode.TIMED, 0)
	var ordered: int = _rites.get(BrazierRite.Mode.ORDERED, 0)
	_check(_wisps * 10 >= generated * 9 and _shortest_wisp >= 12,
			"a wisp leads somewhere on %d of %d floors (shortest lead: %d cells)" % [
				_wisps, generated, _shortest_wisp])
	_check((timed + ordered) * 10 >= generated * 9 and timed > 0 and ordered > 0,
			"braziers wait on %d of %d floors (%d timed, %d ordered)" % [
				timed + ordered, generated, timed, ordered])
	_check(_tightest_burn >= 1.25,
			"a timed rite always burns long enough to walk round (tightest: %.2fx the walk)" % _tightest_burn)
	_check(_rings * 10 >= generated * 9 and _fewest_ring_turns >= FloorPuzzles.RING_TURNS_MIN,
			"statues turn on %d of %d floors, %d to %d turns from facing in" % [
				_rings, generated, _fewest_ring_turns, _most_ring_turns])
	_check(_vaults * 4 >= generated * 3 and _gilded_sigils > 0,
			"a sealed vault stands on %d of %d floors (a sigil under a gilded chest on %d)" % [
				_vaults, generated, _gilded_sigils])
	_check(_cracks * 4 >= generated * 3 and _cracks_in_trees > 0,
			"a cracked wall hides a hollow on %d of %d floors (%d of them in a forest)" % [
				_cracks, generated, _cracks_in_trees])
	print("       (%d of them in a north wall, facing you; the rest in a side wall)" % _cracks_facing)
	# Puzzles draw on a stream of their own: the floor without them is the same
	# floor -- the same chests, the same monsters, the same door.
	var moved: PackedStringArray = PackedStringArray()
	for sample: int in [2, 23, 37, 58, 76, 99]:
		var with := FloorGenerator.generate(FloorRegistry.get_floor(sample), FloorRegistry.seed_for(sample))
		FloorGenerator.with_puzzles = false
		var without := FloorGenerator.generate(FloorRegistry.get_floor(sample), FloorRegistry.seed_for(sample))
		FloorGenerator.with_puzzles = true
		if _floor_contents(with) != _floor_contents(without) or not _monsters_stay(with, without):
			moved.append(str(sample))
		with.free()
		without.free()
	_check(moved.is_empty(), "a floor's puzzles move nothing its own seed put down%s" % (
			"" if moved.is_empty() else " -- they do on " + ", ".join(moved)))

	# --- and so is every authored one ---
	var broken_authored: PackedStringArray = PackedStringArray()
	for floor_number in FloorRegistry.AUTHORED:
		var problem := _audit_authored(floor_number)
		if not problem.is_empty():
			broken_authored.append(problem)
	_check(broken_authored.is_empty(),
			"every authored floor is completable, ends in a labyrinth and has its puzzles solvable%s" % (
			"" if broken_authored.is_empty() else " -- " + ", ".join(broken_authored)))

	# --- a fight can be staged wherever one can start ---
	# Swept by both audits above, over every cell a monster can reach you on. A
	# formation drawn behind a crown is allowed -- the solver would rather that than
	# no fight on the map -- but it must stay rare, or fights read as half-hidden.
	_check(_unstaged.is_empty() and _formations > 10000,
			"a fight can be staged on every cell of every map with monsters (%d cells)%s" % [
				_formations, "" if _unstaged.is_empty() else " -- " + ", ".join(_unstaged)])
	_check(_hidden_formations * 100 <= _formations,
			"a staged fight is hidden behind a prop on at most 1%% of cells (%d of %d)" % [
				_hidden_formations, _formations])
	print("       (%d of those had to slide the player off the cell they stood on, %d are framed at x1)" % [
			_slid_formations, _wide_formations])
	# The boss steps out of its door to fight where you challenged it. Swept from
	# every cell the door can be challenged from, on every floor: a door with
	# nowhere for its boss to stand is fought with nobody on the map, on one floor
	# out of a hundred.
	_check(_unstaged.is_empty() and _boss_doors == FloorTuning.TOP_FLOOR and _boss_formations > 1000,
			"a boss fight can be staged from every cell of every door (%d doors, %d cells)" % [
				_boss_doors, _boss_formations])
	# Not a limit: the door has faded aside by then, so a fight with your back to
	# it reads fine. It is what the solver settles for when a boss room's near
	# side has no room, and a count that jumps means the rooms have changed shape.
	print("       (%d of those close in to x%d, the rest are framed at x1; %d face the boss with their back to its door)" % [
			_boss_close, int(BattleStage.ZOOM), _boss_from_behind])


# --- helpers ---------------------------------------------------------------

## True when a cell is part of the wall mass. Decor -- the boulders scattered inside
## rooms -- also lives on this layer but carries no terrain, and a pack biome's
## pools carry the water's, so the mass is correct to draw an edge against either.
func _is_wall(walls: TileMapLayer, cell: Vector2i, wall_set: int) -> bool:
	var data := walls.get_cell_tile_data(cell)
	return data != null and data.terrain_set == wall_set


## Wall cells with a see-through pixel on an edge they share with anything that
## isn't wall -- where the backdrop would show against the floor.
func _see_through_edges(walls: TileMapLayer, biome: BiomeKit) -> int:
	var last := TILE - 1
	var edges := {Vector2i.UP: [Vector2i(0, 0), Vector2i(1, 0)], Vector2i.RIGHT: [Vector2i(last, 0), Vector2i(0, 1)],
			Vector2i.DOWN: [Vector2i(0, last), Vector2i(1, 0)], Vector2i.LEFT: [Vector2i(0, 0), Vector2i(0, 1)]}
	# The map's outer ring faces the void past the map, not floor.
	var inside := walls.get_used_rect()
	var open := 0
	for cell in walls.get_used_cells():
		if not _is_wall(walls, cell, biome.wall_terrain_set):
			continue
		var image := _tile_image(biome, walls.get_cell_atlas_coords(cell))
		for side: Vector2i in edges:
			if _is_wall(walls, cell + side, biome.wall_terrain_set) or not inside.has_point(cell + side):
				continue
			var edge: Array = edges[side]
			for step in TILE:
				if image.get_pixelv(edge[0] + edge[1] * step).a == 0.0:
					open += 1
					break
	return open


## Wall cells showing the dark of the wall's top, not masonry, just inside an edge
## they share with anything that isn't wall. The edge's own row is the band's shadow,
## which is that dark too, so the three rows behind it are read, away from the corners.
func _bare_masonry_edges(walls: TileMapLayer, biome: BiomeKit) -> int:
	var dark := _tile_image(biome, Vector2i(biome.wall_tile, 0)).get_pixel(TILE / 2, TILE / 2)
	var last := TILE - 1
	# Per side: the edge's first pixel, the step along it, and the step inwards.
	var edges := {Vector2i.UP: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
			Vector2i.RIGHT: [Vector2i(last, 0), Vector2i(0, 1), Vector2i(-1, 0)],
			Vector2i.DOWN: [Vector2i(0, last), Vector2i(1, 0), Vector2i(0, -1)],
			Vector2i.LEFT: [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]}
	var inside := walls.get_used_rect()
	var bare := 0
	for cell in walls.get_used_cells():
		if not _is_wall(walls, cell, biome.wall_terrain_set):
			continue
		var image := _tile_image(biome, walls.get_cell_atlas_coords(cell))
		for side: Vector2i in edges:
			if _is_wall(walls, cell + side, biome.wall_terrain_set) or not inside.has_point(cell + side):
				continue
			var edge: Array = edges[side]
			var dark_pixels := 0
			var read := 0
			for step in range(3, TILE - 3):
				for depth in range(1, 4):
					read += 1
					if image.get_pixelv(edge[0] + edge[1] * step + edge[2] * depth).is_equal_approx(dark):
						dark_pixels += 1
			if dark_pixels * 2 > read:
				bare += 1
	return bare


## The pixels of the tile at [param coords] of [param biome]'s atlas.
func _tile_image(biome: BiomeKit, coords: Vector2i) -> Image:
	var source := biome.tile_set.get_source(MapDresser.SOURCE_ID) as TileSetAtlasSource
	var image := source.texture.get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_region(Rect2i(coords * TILE, Vector2i(TILE, TILE)))


## Counts wall cells whose chosen tile describes neighbours it doesn't have.
##
## This is the check that catches the art and the terrain data drifting apart --
## a mis-paired blob leaves the floor perfectly completable and merely wrong to
## look at, so nothing else in the suite would say a word about it.
## Liquid tiles that claim no links but draw water on their outer ring of pixels.
func _unlinked_water_on_edges(source: TileSetAtlasSource, biome: BiomeKit) -> PackedStringArray:
	var image := source.texture.get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var size := source.texture_region_size
	var stray := PackedStringArray()
	for index in source.get_tiles_count():
		var coords := source.get_tile_id(index)
		var data := source.get_tile_data(coords, 0)
		if data.terrain_set != biome.liquid_terrain_set \
				or MapDresser.tile_flags(data, biome.liquid_terrain) != 0:
			continue
		var origin := coords * size
		var wet := 0
		for step in size.x:
			for pixel: Vector2i in [Vector2i(step, 0), Vector2i(step, size.y - 1),
					Vector2i(0, step), Vector2i(size.x - 1, step)]:
				var colour := image.get_pixelv(origin + pixel)
				# Water, the swamp's bog and the volcanic band's lava; never foam, which can
				# be the white of land. Lava is told from the desert's sand, which is nearly
				# as orange, by how much redder than green it is.
				if colour.a > 0.0 and ((colour.b > colour.r + 0.08 and colour.b > colour.g - 0.04)
						or (colour.g < colour.r - 0.1 and colour.g < colour.b - 0.05)
						or (colour.r > 0.85 and colour.b < 0.35 and colour.r - colour.g > 0.4)):
					wet += 1
		if wet > 0:
			stray.append("%s (%d px)" % [coords, wet])
	return stray


func _mismatched_wall_tiles(walls: TileMapLayer, wall_set: int) -> int:
	var bad := 0
	for cell in walls.get_used_cells():
		if not _is_wall(walls, cell, wall_set):
			continue
		var data := walls.get_cell_tile_data(cell)
		var wrong := false
		for bit in SIDES:
			if (data.get_terrain_peering_bit(bit) >= 0) != _is_wall(walls, cell + SIDES[bit], wall_set):
				wrong = true
		for bit in CORNERS:
			var corner: Array = CORNERS[bit]
			if not (_is_wall(walls, cell + corner[1], wall_set) and _is_wall(walls, cell + corner[2], wall_set)):
				continue
			if (data.get_terrain_peering_bit(bit) >= 0) != _is_wall(walls, cell + corner[0], wall_set):
				wrong = true
		if wrong:
			bad += 1
	return bad


## Wall cells that border something other than wall -- i.e. the ones autotiling
## exists to draw. Zero of them means the pass silently did nothing.
func _edge_tile_count(walls: TileMapLayer, wall_set: int) -> int:
	var edges := 0
	for cell in walls.get_used_cells():
		var data := walls.get_cell_tile_data(cell)
		if not _is_wall(walls, cell, wall_set):
			continue
		for bit in SIDES:
			if data.get_terrain_peering_bit(bit) < 0:
				edges += 1
				break
	return edges


func _uncollidable_wall_tiles(walls: TileMapLayer, wall_set: int) -> int:
	var open := 0
	for cell in walls.get_used_cells():
		var data := walls.get_cell_tile_data(cell)
		if not _is_wall(walls, cell, wall_set):
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

	var trapped := _audit_chests(map, walls, reachable, "floor %d" % floor_number, true)
	if not trapped.is_empty():
		return trapped

	# Autotiling rewrites every wall on the floor. Dropping one instead of
	# replacing it would open the map onto the void, and the flood fill above
	# would quietly reach further rather than fail -- so the sealed outer ring,
	# which nothing is ever allowed to carve, is checked directly.
	# The map is the field plus the labyrinth's strip, side by side, so its ring is
	# the used rect's, not the field's -- which the doorstep corridor does cut through.
	var bounds := walls.get_used_rect()
	var strip := definition.labyrinth * FloorGenerator.LAB_PITCH \
			+ Vector2i(FloorGenerator.LAB_WALL, FloorGenerator.LAB_WALL)
	var field := definition.size
	if bounds.position != Vector2i.ZERO or not (bounds.size in [
			Vector2i(field.x + strip.x, maxi(field.y, strip.y)),
			Vector2i(maxi(field.x, strip.x), field.y + strip.y)]):
		return "floor %d is %s, not its field plus a labyrinth" % [floor_number, bounds.size]
	for x in bounds.size.x:
		if not _sealed(walls, Vector2i(x, 0)) or not _sealed(walls, Vector2i(x, bounds.size.y - 1)):
			return "floor %d has a hole in its outer wall" % floor_number
	for y in bounds.size.y:
		if not _sealed(walls, Vector2i(0, y)) or not _sealed(walls, Vector2i(bounds.size.x - 1, y)):
			return "floor %d has a hole in its outer wall" % floor_number
	var lost := _audit_labyrinth(map, walls, gate, start, reachable)
	if lost.is_empty():
		lost = _audit_puzzles(map as GameMap, walls, start, reachable, floor_number)
	if lost.is_empty():
		# With the vault open: a monster can follow you into it, so a fight has to
		# be stageable in there too -- and outside, an open doorway is only more room.
		var seal := map.get_node_or_null("SealedDoor")
		if seal != null:
			for shape in seal.get_node("Solid").get_children():
				(shape as CollisionShape2D).disabled = true
		# And with the cracked wall broken, which the puzzle audit has done: its
		# hollow is floor now, and somewhere a fight can follow you into.
		reachable = _flood(walls, start)
		_audit_formations(map, walls, start, reachable, "floor %d" % floor_number)
		_audit_boss_formations(map, walls, gate, reachable, floor_number, "floor %d" % floor_number)
	return lost


## Every chest can be reached -- but the one behind a cracked wall, which is rock
## until [method _audit_puzzles] breaks it -- and a trap is always a gilded chest,
## a teleport always landing on open labyrinth floor. [param tally] counts the
## gilded ones for the climb's trap split, which is the generated floors'.
func _audit_chests(map: Node2D, walls: TileMapLayer, reachable: Dictionary, label: String,
		tally: bool) -> String:
	var crack := map.get_node_or_null("CrackedWall") as CrackedWall
	for child in map.get_children():
		var chest := child as Chest
		if chest == null:
			continue
		if crack != null and chest.hidden_until == crack.opened_flag:
			continue
		if not reachable.has(walls.local_to_map(chest.position)):
			return "%s has an unreachable chest" % label
		if chest.trap != Chest.Trap.NONE and not chest.gilded:
			return "%s's %s is trapped and looks like any other chest" % [label, chest.name]
		if chest.gilded and tally:
			_gilded[chest.trap] = _gilded.get(chest.trap, 0) + 1
		if chest.trap == Chest.Trap.TELEPORT:
			# Somewhere you can stand, in the labyrinth, and walk out of.
			var lands := walls.local_to_map(chest.trap_target)
			var lab_rect: Rect2i = map.get_meta(&"labyrinth", Rect2i())
			if not reachable.has(lands) or not lab_rect.has_point(lands):
				return "%s's %s teleports to %s, not to open labyrinth floor" % [label, chest.name, lands]
			for other in map.get_children():
				if other is Chest and walls.local_to_map((other as Node2D).position) == lands:
					return "%s's %s teleports onto a chest" % [label, chest.name]
	return ""


## The labyrinth stands between the field and the door, the door hides in a room
## with one way in, and finding that room is all it takes to see the door.
##
## The hidden-door half of the floor test: the flood fill above proves the door can
## be reached, and this proves it can be *found* -- the failure mode a hidden door
## adds is an unfindable one, which no flood fill sees.
func _audit_labyrinth(map: Node2D, walls: TileMapLayer, gate: Node, start: Vector2i,
		reachable: Dictionary) -> String:
	var floor_number := int(gate.get(&"floor_number"))
	if not (map.has_meta(&"labyrinth") and map.has_meta(&"labyrinth_mouth") and map.has_meta(&"boss_room")):
		return "floor %d has no labyrinth" % floor_number
	var lab: Rect2i = map.get_meta(&"labyrinth")
	var mouth: Rect2i = map.get_meta(&"labyrinth_mouth")
	var room: Rect2i = map.get_meta(&"boss_room")
	var gate_cell := walls.local_to_map((gate as Node2D).position)

	if not room.has_point(gate_cell) or not lab.encloses(room):
		return "floor %d's door is not in a boss room inside its labyrinth" % floor_number
	var hides: Rect2 = gate.get(&"reveal_area")
	if hides != Rect2(room.position * 16, room.size * 16):
		return "floor %d's door does not hide in its boss room (%s)" % [floor_number, hides]

	# One way into the labyrinth: the mouth, and nothing else through its outer wall.
	var openings := 0
	for cell in _ring(lab):
		if walls.get_cell_source_id(cell) == -1:
			if not mouth.has_point(cell):
				return "floor %d's labyrinth is open at %s, not only at its mouth" % [floor_number, cell]
			openings += 1
	if openings == 0:
		return "floor %d's labyrinth has no way in" % floor_number
	# And it is the way in: wall the mouth up and the door is out of reach.
	var sealed := _flood_except(walls, start, mouth)
	if sealed.has(gate_cell):
		return "floor %d's door can be reached without going through the labyrinth" % floor_number

	# One way into the boss room, so being in it means having found it.
	var doorways := 0
	for cell in _ring(room.grow(1)):
		if walls.get_cell_source_id(cell) == -1:
			doorways += 1
	if doorways != FloorGenerator.LAB_PASSAGE:
		return "floor %d's boss room has %d open cells round it, not one doorway" % [floor_number, doorways]
	if not reachable.has(room.position):
		return "floor %d's boss room cannot be walked into" % floor_number

	# A safe zone on the way: the one way to the door runs through it, its fire
	# stands in it, and nothing that fights starts out in it.
	if not map.has_meta(&"safe_zone"):
		return "floor %d's labyrinth has no safe zone" % floor_number
	var camp: Rect2i = map.get_meta(&"safe_zone")
	if not lab.encloses(camp) or camp.intersects(room.grow(1)):
		return "floor %d's safe zone %s is not in its labyrinth, clear of the boss room" % [floor_number, camp]
	if not (map as GameMap).safe_zones.has(camp):
		return "floor %d's safe zone is not one the map keeps monsters out of" % floor_number
	if _flood_except(walls, start, camp).has(gate_cell):
		return "floor %d's door can be reached without passing its safe zone" % floor_number
	var fire := map.get_node_or_null("Campfire") as Node2D
	if fire == null or not camp.has_point(walls.local_to_map(fire.position - Vector2(0, 8))):
		return "floor %d's safe zone has no fire in it" % floor_number
	for child in map.get_children():
		if child is Monster and camp.has_point(walls.local_to_map((child as Node2D).position)):
			return "floor %d has %s starting in its safe zone" % [floor_number, child.name]

	# What the labyrinth is like to walk: its dead ends, and how far the door is
	# along it against the farthest cell it has.
	var dead_ends := 0
	for j in range((lab.size.y - FloorGenerator.LAB_WALL) / FloorGenerator.LAB_PITCH):
		for i in range((lab.size.x - FloorGenerator.LAB_WALL) / FloorGenerator.LAB_PITCH):
			var cell := lab.position + Vector2i(FloorGenerator.LAB_WALL, FloorGenerator.LAB_WALL) \
					+ Vector2i(i, j) * FloorGenerator.LAB_PITCH
			if room.has_point(cell):
				continue
			var exits := 0
			for side in [Vector2i(-1, 0), Vector2i(FloorGenerator.LAB_PASSAGE, 0),
					Vector2i(0, -1), Vector2i(0, FloorGenerator.LAB_PASSAGE)]:
				if walls.get_cell_source_id(cell + side) == -1:
					exits += 1
			if exits == 1:
				dead_ends += 1
	if dead_ends < 2:
		return "floor %d's labyrinth has %d dead ends -- a corridor, not a maze" % [floor_number, dead_ends]
	var steps := _distances_within(walls, mouth.position, lab)
	var farthest := 0
	for cell: Vector2i in steps:
		farthest = maxi(farthest, steps[cell])
	var to_door: int = steps.get(gate_cell, -1)
	_lab_floors += 1
	_lab_walks.append(to_door)
	if to_door < farthest * 9 / 10:
		_lab_not_farthest += 1
	return ""


## Every puzzle on the floor can be solved and pays out where it can be reached --
## the way [method _audit_labyrinth] proves the door findable. An unsolvable
## puzzle on floor 73 is the dead end playtest never finds.
##
## Walked with every piece solid, the sealed chests included (the state after
## they appear, and the stricter one): each piece must have a cell beside it a body
## can walk to from the spawn, or it cannot be used.
func _audit_puzzles(map: GameMap, walls: TileMapLayer, start: Vector2i, reachable: Dictionary,
		floor_number: int) -> String:
	var label := "floor %d" % floor_number
	map.refresh_solids()
	var walkable := _flood_standable(map, start)
	var by_sigil: Dictionary[StringName, Chest] = {}
	for child in map.get_children():
		var chest := child as Chest
		if chest == null:
			continue
		if chest.sealed and (chest.gilded or chest.trap != Chest.Trap.NONE):
			return "%s's %s is sealed and gilded or trapped" % [label, chest.name]
		if chest.sigil_flag != &"":
			if by_sigil.has(chest.sigil_flag):
				return "%s hides sigil %s in two chests" % [label, chest.sigil_flag]
			by_sigil[chest.sigil_flag] = chest

	# The wisp: a way to its shrine over floor, step by step, through the field, and
	# the chest it pays out beside the shrine, hidden until it arrives.
	var wisp := map.get_node_or_null("Wisp") as Wisp
	if wisp != null:
		var shrine := map.get_node_or_null("WispShrine") as WispShrine
		var chest := map.get_node_or_null("ChestWisp") as Chest
		if shrine == null or chest == null:
			return "%s has a wisp with no shrine or no chest" % label
		var path := wisp.path
		if path.size() < 2 or path[0] != wisp.position or path[path.size() - 1] != shrine.position:
			return "%s's wisp does not lead from where it idles to its shrine" % label
		for i in path.size():
			var cell := walls.local_to_map(path[i])
			if walls.get_cell_source_id(cell) != -1 or not reachable.has(cell):
				return "%s's wisp floats through rock at %s" % [label, cell]
			if i > 0 and absf(path[i].x - path[i - 1].x) + absf(path[i].y - path[i - 1].y) != TILE:
				return "%s's wisp jumps between %s and %s" % [label, path[i - 1], path[i]]
		if not walkable.has(walls.local_to_map(wisp.position)):
			return "%s's wisp idles where you cannot walk up to it" % label
		if chest.hidden_until != wisp.solved_flag or shrine.solved_flag != wisp.solved_flag \
				or walls.local_to_map(chest.position) != walls.local_to_map(shrine.position) + Vector2i.DOWN:
			return "%s's wisp chest is not hidden by its shrine until it arrives" % label
		for piece: Node2D in [shrine, chest]:
			if not _approachable(walls, piece, walkable):
				return "%s's %s cannot be walked up to" % [label, piece.name]
		_wisps += 1
		_shortest_wisp = mini(_shortest_wisp, path.size())

	# The braziers: each can be walked up to; ordered, the order names each once;
	# timed, the fire burns longer than walking the shortest way round them takes.
	var rite := map.get_node_or_null("BrazierRite") as BrazierRite
	if rite != null:
		var chest := map.get_node_or_null("ChestRite") as Chest
		var tablet := map.get_node_or_null("Tablet") as Tablet
		var count := rite.braziers.size()
		if chest == null or tablet == null or tablet.lines.is_empty() or count < 3 or count > 4:
			return "%s has a rite of %d braziers with no chest or no tablet" % [label, count]
		if chest.hidden_until != rite.solved_flag:
			return "%s's brazier chest is not hidden until the rite is done" % label
		var approaches: Array = []
		for i in count:
			var brazier := rite.braziers[i]
			if brazier.index != i or not _approachable(walls, brazier, walkable):
				return "%s's %s cannot be walked up to" % [label, brazier.name]
			approaches.append(_beside(walls, brazier, walkable))
		for piece: Node2D in [chest, tablet]:
			if not _approachable(walls, piece, walkable):
				return "%s's %s cannot be walked up to" % [label, piece.name]
		if rite.mode == BrazierRite.Mode.ORDERED:
			var sorted := rite.order.duplicate()
			sorted.sort()
			var expected: Array[int] = []
			for i in count:
				expected.append(i)
			if sorted != expected:
				return "%s's rite asks for the order %s" % [label, rite.order]
			if tablet.lines[0].count(" the ") < count:
				return "%s's tablet does not name every fire: %s" % [label, tablet.lines[0]]
		else:
			var seconds := _shortest_round(map, approaches) / FloorPuzzles.WALK_TILES_PER_SECOND
			_tightest_burn = minf(_tightest_burn, rite.burn / maxf(seconds, 0.01))
			if rite.burn < seconds * 1.25:
				return "%s's fires burn %.1fs, and walking round them takes %.1fs" % [label, rite.burn, seconds]
		_rites[rite.mode] = _rites.get(rite.mode, 0) + 1

	# The statues: four round the altar, each looking at it once solved, each one
	# walkable up to; scrambled into an arrangement the turns can solve, and not
	# one a couple of idle turns would.
	var ring := map.get_node_or_null("StatueRing") as StatueRing
	if ring != null:
		var chest := map.get_node_or_null("ChestStatues") as Chest
		var altar := map.get_node_or_null("StatueAltar") as StatueAltar
		if chest == null or altar == null or ring.statues.size() != FloorPuzzles.RING.size():
			return "%s has a ring of %d statues with no chest or no altar" % [label, ring.statues.size()]
		if chest.hidden_until != ring.solved_flag or altar.solved_flag != ring.solved_flag:
			return "%s's statue chest is not hidden until the statues face in" % label
		var facings: Array[int] = []
		var looks: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
		for i in ring.statues.size():
			var statue := ring.statues[i]
			if statue.index != i or statue.position != altar.position + Vector2(FloorPuzzles.RING[i] * TILE):
				return "%s's %s does not stand in its place round the altar" % [label, statue.name]
			if statue.position + looks[ring.targets[i]] * 2.0 * TILE != altar.position:
				return "%s's %s is solved facing away from the altar" % [label, statue.name]
			if not _approachable(walls, statue, walkable):
				return "%s's %s cannot be walked up to" % [label, statue.name]
			facings.append(statue.facing)
		for piece: Node2D in [chest, altar]:
			if not _approachable(walls, piece, walkable):
				return "%s's %s cannot be walked up to" % [label, piece.name]
		var turns := StatueRing.turns_to_solve(facings, ring.targets)
		if turns.is_empty():
			return "%s's statues cannot all be turned to face the altar from %s" % [label, facings]
		var total := 0
		for count in turns:
			total += count
		if total < FloorPuzzles.RING_TURNS_MIN:
			return "%s's statues are %d turns from solved" % [label, total]
		_rings += 1
		_fewest_ring_turns = mini(_fewest_ring_turns, total)
		_most_ring_turns = maxi(_most_ring_turns, total)

	# The vault: shut, the door is the only way to its chest; open, the chest can be
	# walked up to; and every sigil the door wants is in a chest you can reach
	# without it -- under a puzzle's reward, or the floor's own loot.
	var seal := map.get_node_or_null("SealedDoor") as SealedDoor
	if seal != null:
		var vault: Rect2i = map.get_meta(&"vault", Rect2i())
		var chest := map.get_node_or_null("ChestVault") as Chest
		if chest == null or not vault.has_point(walls.local_to_map(chest.position)) or chest.hidden_until != &"":
			return "%s's vault has no chest in it" % label
		if seal.sigils.size() < 2:
			return "%s's vault wants %d sigils" % [label, seal.sigils.size()]
		for sigil in seal.sigils:
			var holder: Chest = by_sigil.get(sigil)
			if holder == null:
				return "%s's vault wants sigil %s, which no chest holds" % [label, sigil]
			if vault.has_point(walls.local_to_map(holder.position)) or not _approachable(walls, holder, walkable):
				return "%s's sigil %s is somewhere you cannot reach with the vault shut" % [label, sigil]
			if holder.hidden_until != &"" and not (holder.hidden_until in [
					wisp.solved_flag if wisp else &"-", rite.solved_flag if rite else &"-",
					ring.solved_flag if ring else &"-"]):
				return "%s's sigil %s waits on a puzzle the floor does not have" % [label, sigil]
			if holder.gilded:
				_gilded_sigils += 1
		if by_sigil.size() != seal.sigils.size():
			return "%s hides %d sigils for a door that wants %d" % [label, by_sigil.size(), seal.sigils.size()]
		if not _approachable(walls, seal, walkable):
			return "%s's sealed door cannot be walked up to" % label
		if _approachable(walls, chest, walkable):
			return "%s's vault can be walked into with its door shut" % label
		for shape in seal.get_node("Solid").get_children():
			(shape as CollisionShape2D).disabled = true
		map.refresh_solids()
		var opened := _flood_standable(map, start)
		for shape in seal.get_node("Solid").get_children():
			(shape as CollisionShape2D).disabled = false
		if not _approachable(walls, chest, opened):
			return "%s's vault chest cannot be reached with the door open" % label
		_vaults += 1
	elif not by_sigil.is_empty():
		return "%s hides sigils for a vault it does not have" % label

	# The cracked wall: a secret until it breaks -- the hollow is rock, its chest is
	# hidden, the crack faces floor you can walk to -- and broken the way the game
	# breaks it, the hollow opens onto that room and nothing else, its chest can be
	# walked up to, and the rock, the forest and the ground round it are dressed as
	# if it had been carved from the start.
	var crack := map.get_node_or_null("CrackedWall") as CrackedWall
	if crack != null:
		var hollow := crack.hollow
		var chest := map.get_node_or_null("ChestCrack") as Chest
		if chest == null or not chest.sealed or chest.hidden_until != crack.opened_flag \
				or not hollow.has_point(walls.local_to_map(chest.position)):
			return "%s's cracked wall has no chest hidden behind it" % label
		for rect: Rect2i in [crack.door, hollow]:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if walls.get_cell_source_id(Vector2i(x, y)) == -1:
						return "%s's cracked wall is open at %s before it is broken" % [label, Vector2i(x, y)]
		var face := walls.local_to_map(crack.position)
		if not crack.door.has_point(face) or not walkable.has(face - crack.side):
			return "%s's crack does not face floor you can walk to" % label
		crack.break_open()
		map.refresh_solids()
		var broken := _flood_standable(map, start)
		if not _approachable(walls, chest, broken):
			return "%s's hollow chest cannot be reached once the wall breaks" % label
		for cell in _ring(hollow.grow(1)):
			if walls.get_cell_source_id(cell) == -1 and not crack.door.has_point(cell):
				return "%s's hollow is open at %s, not only at its crack" % [label, cell]
		var biome := FloorRegistry.get_biome(floor_number)
		var props := map.get_node_or_null(MapDresser.PROPS) as TileMapLayer
		if biome.wall_style == BiomeKit.WallStyle.TREES:
			var bare := _bare_forest_edges(walls, props, biome)
			if bare > 0:
				return "%s's forest is bare in %d places round its broken wall" % [label, bare]
			_cracks_in_trees += 1
		else:
			var wrong := _mismatched_wall_tiles(walls, biome.wall_terrain_set)
			if wrong > 0:
				return "%s's broken wall leaves %d wall tiles not matching their neighbours" % [label, wrong]
		var off := _ground_mismatches(map.get_node("Ground") as TileMapLayer, biome)
		if off > 0:
			return "%s's broken wall leaves %d ground cells drawing the wrong edge" % [label, off]
		_cracks += 1
		if crack.side == Vector2i.UP:
			_cracks_facing += 1

	# And the pieces stand in nobody's way: with every one of them solid, the floor's
	# own chests, its fire and its door can still be walked up to.
	for child in map.get_children():
		if (child is Chest and not (child as Chest).sealed) or child is BossGate or child is Campfire:
			if not _approachable(walls, child, walkable):
				return "%s's puzzles stand between you and %s" % [label, child.name]
	return ""


## The walkable cells beside [param piece]'s cell, from which it can be used.
func _beside(walls: TileMapLayer, piece: Node2D, walkable: Dictionary) -> Array[Vector2i]:
	var cell := walls.local_to_map(piece.position - Vector2(0, 1))
	var near: Array[Vector2i] = []
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if walkable.has(cell + step):
			near.append(cell + step)
	if piece is SealedDoor:
		# Two cells square: beside any of them.
		var door: Rect2i = piece.get_parent().get_meta(&"vault_door", Rect2i())
		for y in range(door.position.y - 1, door.end.y + 1):
			for x in range(door.position.x - 1, door.end.x + 1):
				if walkable.has(Vector2i(x, y)) and not door.has_point(Vector2i(x, y)):
					near.append(Vector2i(x, y))
	return near


func _approachable(walls: TileMapLayer, piece: Node2D, walkable: Dictionary) -> bool:
	return not _beside(walls, piece, walkable).is_empty()


## The fewest steps that visit one cell beside each brazier, in any order, walking
## round whatever stands in the room.
func _shortest_round(map: GameMap, approaches: Array) -> int:
	var count := approaches.size()
	var steps: Array = []
	for i in count:
		var row: Array[int] = []
		for j in count:
			row.append(_steps_between(map, approaches[i], approaches[j]))
		steps.append(row)
	var best := 1 << 30
	for order in FloorPuzzles._orders(count):
		var total := 0
		for k in range(1, count):
			total += steps[order[k - 1]][order[k]]
		best = mini(best, total)
	return best


func _steps_between(map: GameMap, from: Array[Vector2i], to: Array[Vector2i]) -> int:
	var seen := {}
	var queue: Array[Vector2i] = []
	for cell in from:
		seen[cell] = 0
		queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if cell in to:
			return seen[cell]
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if not seen.has(next) and map.is_standable(next):
				seen[next] = seen[cell] + 1
				queue.append(next)
	return 1 << 20


## A fight can be staged on every cell a body can walk to from [param start], and
## every formation stands where it claims to: on floor in [param reachable], the
## player no further from where they stood than a short walk inside the slide
## box, the enemies at the end of a clear lane. The in-place version of an
## unreachable door: a fight with nowhere to stand is a menu with nobody on the
## map, in one corner of one floor out of a hundred, and never where anyone playtests.
##
## The contact side rotates with the cell, so every axis gets asked first
## somewhere; existence doesn't depend on it, since the solver tries all four.
func _audit_formations(map: Node2D, walls: TileMapLayer, start: Vector2i, reachable: Dictionary,
		label: String) -> void:
	var problem := _formation_problem(map, walls, start, reachable, label)
	if not problem.is_empty():
		_unstaged.append(problem)


func _formation_problem(map: Node2D, walls: TileMapLayer, start: Vector2i, reachable: Dictionary,
		label: String) -> String:
	var game_map := map as GameMap
	if game_map == null:
		return "%s is not a GameMap" % label
	game_map.refresh_solids()
	# Where you can stand and walk to, not just what isn't wall: a chest is solid,
	# and four of them by a boulder can box in a cell no body ever gets into.
	if not game_map.is_standable(start):
		return "%s spawns somewhere nobody can stand, at %s" % [label, start]
	var standing := _flood_standable(game_map, start)
	var sides: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var slide := GameMap.FORMATION_SLIDE
	for cell: Vector2i in standing:
		var field := game_map.formation(cell, sides[posmod(cell.x + cell.y, 4)], 1)
		if field == null:
			return "%s cannot stage a fight at %s" % [label, cell]
		_formations += 1
		if not BattleStage.fits(field.bodies.size, BattleStage.ZOOM):
			_wide_formations += 1
		var fighters: Array[Vector2i] = field.enemy_cells.duplicate()
		fighters.append(field.player_cell)
		for fighter in fighters:
			if walls.get_cell_source_id(fighter) != -1 or not reachable.has(fighter) \
					or not game_map.is_standable(fighter):
				return "%s stages a fight at %s with someone off the floor at %s" % [label, cell, fighter]
			if game_map.is_covered(fighter):
				_hidden_formations += 1
				break
		if field.player_cell != cell:
			_slid_formations += 1
			var box := Rect2i(cell - Vector2i.ONE * slide, Vector2i.ONE * (slide * 2 + 1))
			if not _flood_within(walls, cell, box).has(field.player_cell):
				return "%s moves the player at %s through a wall to %s" % [label, cell, field.player_cell]
		var lane := field.enemy_cells[0] - field.player_cell
		if lane.x != 0 and lane.y != 0:
			return "%s stages a fight at %s off the axis" % [label, cell]
		var step := lane.sign()
		for i in range(1, absi(lane.x + lane.y)):
			if walls.get_cell_source_id(field.player_cell + step * i) != -1:
				return "%s stages a fight at %s across a wall" % [label, cell]
	return ""


## A boss fight can be staged from every cell [param gate] can be challenged
## from -- every standable cell within two of it, which is further than the
## interact sensor reaches -- and every formation stands where it claims to: the
## boss out of its door and on floor, the player walked back no further than
## [constant GameMap.BOSS_WALK] steps without crossing anything, a clear lane
## between them, the escort beside the boss with floor all the way, and no two
## of them drawn over each other. The last is what the solver's body-sized gaps
## are for, and a 60 px boss standing on the player's head is how they fail.
func _audit_boss_formations(map: Node2D, walls: TileMapLayer, gate: Node2D, reachable: Dictionary,
		floor_number: int, label: String) -> void:
	var game_map := map as GameMap
	var encounter := Bestiary.boss_encounter(floor_number)
	if game_map == null or encounter == null:
		_unstaged.append("%s has no boss to stage" % label)
		return
	_boss_doors += 1
	var bodies: Array[Vector2] = []
	for i in encounter.enemies.size():
		bodies.append(FoeFigure.body_of(encounter.enemies[i], i == 0))
	game_map.refresh_solids()
	var door: Vector2i = walls.local_to_map(gate.position)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := door + Vector2i(dx, dy)
			if not reachable.has(cell) or not game_map.is_standable(cell):
				continue
			var problem := _boss_formation_problem(game_map, walls, door, cell, bodies, reachable)
			if not problem.is_empty():
				_unstaged.append("%s %s" % [label, problem])
				return


func _boss_formation_problem(map: GameMap, walls: TileMapLayer, door: Vector2i, cell: Vector2i,
		bodies: Array[Vector2], reachable: Dictionary) -> String:
	var field := map.boss_formation(cell, door, bodies)
	if field == null:
		return "cannot stage its boss fight from %s" % cell
	_boss_formations += 1
	if field.enemy_cells.size() != bodies.size():
		return "stages %d of its %d enemies from %s" % [field.enemy_cells.size(), bodies.size(), cell]
	var fighters: Array[Vector2i] = field.enemy_cells.duplicate()
	fighters.append(field.player_cell)
	for fighter in fighters:
		if walls.get_cell_source_id(fighter) != -1 or not reachable.has(fighter) \
				or not map.is_standable(fighter):
			return "stages its boss fight from %s with someone off the floor at %s" % [cell, fighter]
	var walked := _flood_standable_within(map, cell, GameMap.BOSS_WALK)
	if not walked.has(field.player_cell):
		return "walks the player from %s to %s, further than %d steps or through something" % [
				cell, field.player_cell, GameMap.BOSS_WALK]
	var boss := field.enemy_cells[0]
	var lane := boss - field.player_cell
	if lane.x != 0 and lane.y != 0:
		return "stages its boss fight from %s off the axis" % cell
	# The way out of the door towards where you challenged it; facing the boss
	# along it means standing with your back to the door.
	if lane.sign() == GameMap._axis_of(Vector2(cell - door)):
		_boss_from_behind += 1
	for i in range(1, absi(lane.x + lane.y)):
		if not map.is_standable(field.player_cell + lane.sign() * i):
			return "stages its boss fight from %s across something" % cell
	if field.enemy_cells.size() > 1:
		var aside := field.enemy_cells[1] - boss
		if aside.x != 0 and aside.y != 0:
			return "puts the escort off the boss's line from %s" % cell
		for i in range(1, absi(aside.x + aside.y) + 1):
			if not map.is_standable(boss + aside.sign() * i):
				return "puts the escort across something from %s" % cell
	var rects: Array[Rect2] = [Rect2(field.player_spot - Vector2(8, 16), GameMap.STANDING)]
	for i in field.enemy_spots.size():
		rects.append(Rect2(field.enemy_spots[i] - Vector2(bodies[i].x / 2.0, bodies[i].y), bodies[i]))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return "draws two of its fighters over each other from %s" % cell
	if BattleStage.fits(field.bodies.size, BattleStage.ZOOM):
		_boss_close += 1
	return ""


## The standable cells within [param limit] steps of [param from].
func _flood_standable_within(map: GameMap, from: Vector2i, limit: int) -> Dictionary:
	var seen := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if seen[cell] >= limit:
			continue
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if not seen.has(next) and map.is_standable(next):
				seen[next] = seen[cell] + 1
				queue.append(next)
	return seen


## The cells a body can walk to from [param from] without passing through
## anything solid -- walls, water, chests, people.
func _flood_standable(map: GameMap, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if not seen.has(next) and map.is_standable(next):
				seen[next] = true
				queue.append(next)
	return seen


func _ring(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		cells.append(Vector2i(x, rect.position.y))
		cells.append(Vector2i(x, rect.end.y - 1))
	for y in range(rect.position.y + 1, rect.end.y - 1):
		cells.append(Vector2i(rect.position.x, y))
		cells.append(Vector2i(rect.end.x - 1, y))
	return cells


## [method _flood], treating [param blocked] as wall.
## [method _flood] with [param blocked] walled up. Kept to the walls' used rect,
## like [method _flood_within]: an authored map has holes in its border where its
## exits are, and a fill that leaves through one never stops.
func _flood_except(walls: TileMapLayer, from: Vector2i, blocked: Rect2i) -> Dictionary:
	var bounds := walls.get_used_rect()
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next) or blocked.has_point(next) or not bounds.has_point(next) \
					or walls.get_cell_source_id(next) != -1:
				continue
			seen[next] = true
			queue.append(next)
	return seen


## Walking distance from [param from] to every open cell inside [param bounds].
func _distances_within(walls: TileMapLayer, from: Vector2i, bounds: Rect2i) -> Dictionary:
	var steps := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if steps.has(next) or not bounds.has_point(next) or walls.get_cell_source_id(next) != -1:
				continue
			steps[next] = steps[cell] + 1
			queue.append(next)
	return steps


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
	var monsters := 0
	var counted := {}
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

		# The camera clamps to the painted area, and a map smaller than one view
		# leaves it nowhere legal to stand: Camera2D resolves the conflict by
		# pinning the right/bottom limits, so the void shows on the left and top.
		var view := _view_size(map)
		var painted := _painted_rect(map)
		if painted.size.x * 16 < view.x or painted.size.y * 16 < view.y:
			problem = "%s is %dx%d px, smaller than the %dx%d view" % [
					label, painted.size.x * 16, painted.size.y * 16, view.x, view.y]
			map.free()
			break

		# Bounded, unlike the generated-floor fill: an authored map is allowed
		# holes in its border where a MapExit sits in them, and an unbounded fill
		# walks out through one of those and expands across empty space forever.
		var reachable := _flood_within(walls, start, walls.get_used_rect())
		var stranded: PackedStringArray = PackedStringArray()
		var leaves := false
		# The lift walks Lanternfall twice; its monsters are only there once.
		var first_visit := not counted.has(map.scene_file_path)
		counted[map.scene_file_path] = true
		for child in map.get_children():
			var node := child as Node2D
			if node == null or node is TileMapLayer:
				continue
			if node.name == "SpawnPoints" or node.name == "Player":
				continue
			# A cracked wall stands in rock and its chest behind it, until the
			# puzzle audit below breaks it open.
			if node is CrackedWall or (node is Chest and (node as Chest).hidden_until.ends_with("_crack")):
				continue
			if not reachable.has(walls.local_to_map(node.position)):
				stranded.append(node.name)
				continue
			if first_visit and node.name.begins_with("Monster"):
				monsters += 1
			if node.name == "BossGate" and int(node.get(&"floor_number")) == floor_number:
				found_gate = true
			if "target_map" in node and not str(node.get(&"target_map")).is_empty():
				var target := str(node.get(&"target_map"))
				# An exit back into the map it stands in -- Lanternfall's lift -- is
				# a shortcut across the map, not a way off it.
				if target != map.scene_file_path:
					leaves = true
				var spawn: StringName = node.get(&"target_spawn")
				var key := "%s|%s" % [target, spawn]
				if not visited.has(key) and ResourceLoader.exists(target):
					visited[key] = true
					pending.append([(load(target) as PackedScene).instantiate(), spawn, target])

		if not stranded.is_empty():
			problem = "%s strands %s" % [label, ", ".join(stranded)]
			map.free()
			break

		# The door's map ends the way a generated floor does: in a labyrinth that
		# hides the door until you are in its room, with a safe zone on the way --
		# and whatever puzzles the floor has are solvable. Proved by the same
		# audits, since hand-placing them fails the same ways.
		var door := map.get_node_or_null("BossGate") as BossGate
		var own_door := first_visit and door != null and door.floor_number == floor_number
		if first_visit:
			problem = _audit_chests(map, walls, reachable, label, false)
		if problem.is_empty() and own_door:
			problem = _audit_labyrinth(map, walls, door, start, reachable)
		if problem.is_empty() and own_door:
			# An authored boss is drawn at full size and its fight framed at x1, half
			# a view either side of it. A map edge nearer than that pins the camera,
			# and the player stands under the menu -- the first Illfang and Nerith
			# in their mazes, against the map's east edge.
			var half := Vector2(_view_size(map)) / 2.0
			var room := Rect2(_painted_rect(map).position * 16, _painted_rect(map).size * 16)
			if not room.encloses(Rect2(door.position - half, half * 2.0)):
				problem = "%s's door is nearer the map's edge than half a view" % label
		if problem.is_empty() and first_visit:
			problem = _audit_puzzles(map as GameMap, walls, start, reachable, floor_number)
			# With the vault open and the cracked wall broken (the puzzle audit
			# broke it), as a generated floor is swept: a fight can follow you in.
			var seal := map.get_node_or_null("SealedDoor")
			if seal != null:
				for shape in seal.get_node("Solid").get_children():
					(shape as CollisionShape2D).disabled = true
			reachable = _flood_within(walls, start, walls.get_used_rect())
		if not problem.is_empty():
			map.free()
			break

		var hunted := false
		for child in map.get_children():
			hunted = hunted or child is Monster
		if first_visit and hunted:
			_audit_formations(map, walls, start, reachable, label)
		if own_door:
			_audit_boss_formations(map, walls, door, reachable, floor_number, label)

		# A map with no way off it is a map whose walls are all there is between
		# the player and the void, so the outer ring has to hold -- the same check
		# the generated floors get, and for the same reason: autotiling rewrote
		# every one of those walls. A map with an exit to *another* map has
		# legitimate holes in its border (Floor 1's town opens onto its field
		# through one), and they are its exits rather than mistakes. Decided per
		# map, and not excused by an exit that leads back into the same map: a lift
		# needs no hole, so one appearing next to it would be a real one.
		if not leaves:
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
	# Authored does not mean exempt from the curve. The monster count is the
	# measured number of kills that levels a player for the floor's boss; what an
	# authored floor gets to choose is where they stand, not how many there are.
	if monsters < FloorTuning.monster_count(floor_number):
		return "floor %d carries %d monsters where the curve wants %d" % [
				floor_number, monsters, FloorTuning.monster_count(floor_number)]
	return ""


## What the player's camera shows, in world pixels.
func _view_size(map: Node2D) -> Vector2i:
	var viewport := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	var camera := map.get_node_or_null("Player/Camera2D") as Camera2D
	var zoom := camera.zoom if camera else Vector2.ONE
	return Vector2i((viewport / zoom).ceil())


## Ground and Walls merged, the same area GameMap hands the camera as its limits.
func _painted_rect(map: Node2D) -> Rect2i:
	var rect := Rect2i()
	for child in map.get_children():
		var layer := child as TileMapLayer
		if layer == null or layer.get_used_rect().size == Vector2i.ZERO \
				or not (layer.name in [&"Ground", &"Walls"]):
			continue
		rect = layer.get_used_rect() if rect.size == Vector2i.ZERO else rect.merge(layer.get_used_rect())
	return rect


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


## [method _flood], kept inside [param bounds]: an authored map's border has
## exits in it, and a formation's slide is a box round the player.
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


## What a floor's own rng put on it: its chests and what is in them, its monsters,
## its door. Where the monsters stand is [method _monsters_stay]'s.
func _floor_contents(map: Node2D) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for child in map.get_children():
		if child is Chest and not (child as Chest).sealed:
			var chest := child as Chest
			parts.append("%s %s %s x%d %s %d" % [chest.name, chest.position, chest.item_id,
					chest.amount, chest.gilded, chest.trap])
		elif child is Monster:
			parts.append("%s %s" % [child.name, (child as Monster).enemy.id])
		elif child is BossGate:
			parts.append("door %s" % (child as Node2D).position)
	return "\n".join(parts)


## Every monster on [param with] stands where it does on [param without], or a cell
## off it -- a puzzle piece steps a monster off the cell it would stand in.
func _monsters_stay(with: Node2D, without: Node2D) -> bool:
	for child in without.get_children():
		if child is Monster:
			var twin := with.get_node_or_null(NodePath(child.name)) as Node2D
			if twin == null or twin.position.distance_to((child as Node2D).position) > TILE + 0.5:
				return false
	return true


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


## The doorway an unbroken cracked wall stands in, or an empty rect.
func _crack_door(map: Node2D) -> Rect2i:
	var crack := map.get_node_or_null("CrackedWall") as CrackedWall
	return crack.door if crack != null and crack.is_available() else Rect2i()


## Wall-mass cells beside open ground that no tree or bush stands over. A bare one
## shows the flat floor under the canopy: the forest's version of a mis-paired
## blob tile, and just as invisible to every other check.
func _bare_forest_edges(walls: TileMapLayer, props: TileMapLayer, biome: BiomeKit,
		standing_on := Rect2i()) -> int:
	var covered := {}
	var source := props.tile_set.get_source(0) as TileSetAtlasSource
	for cell in props.get_used_cells():
		var size := source.get_tile_size_in_atlas(props.get_cell_atlas_coords(cell))
		var rect := MapDresser.footprint(cell, size)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				covered[Vector2i(x, y)] = true
	var bare := 0
	var wall_atlas := Vector2i(biome.wall_tile, 0)
	for cell in walls.get_used_cells():
		if walls.get_cell_atlas_coords(cell) != wall_atlas or covered.has(cell) \
				or standing_on.has_point(cell):
			continue
		for side: Vector2i in SIDES.values():
			if walls.get_cell_source_id(cell + side) == -1:
				bare += 1
				break
	return bare


## Ground cells drawing the wrong edge. A dirt cell's tile has to describe the
## neighbourhood it actually has; a grass cell has to be plain grass, because the
## pack draws every transition inside the path's own cells.
func _ground_mismatches(ground: TileMapLayer, biome: BiomeKit) -> int:
	var dirt := {}
	for cell in ground.get_used_cells():
		var data := ground.get_cell_tile_data(cell)
		if data != null and data.terrain_set == biome.ground_terrain_set and data.terrain == biome.ground_dirt:
			dirt[cell] = true
	var off := 0
	for cell in ground.get_used_cells():
		var data := ground.get_cell_tile_data(cell)
		if data == null or data.terrain_set != biome.ground_terrain_set:
			off += 1
		elif data.terrain == biome.ground_dirt:
			if MapDresser.tile_flags(data, biome.ground_dirt) != MapDresser.expected_flags(cell, dirt):
				off += 1
		elif MapDresser.tile_flags(data, biome.ground_dirt) != 0:
			off += 1
	return off


func _layer_signature(map: Node2D, layer_name: String) -> String:
	var layer := map.get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		return ""
	var parts := PackedStringArray()
	for cell in layer.get_used_cells():
		parts.append("%s=%s" % [cell, layer.get_cell_atlas_coords(cell)])
	parts.sort()
	return ",".join(parts)
