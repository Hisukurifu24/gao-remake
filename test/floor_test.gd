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
## Safe zones with a peddler by the fire, of the generated floors walked.
var _merchants := 0
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
## Floors whose teleport gate passed [method _audit_teleport_gate].
var _teleport_gates := 0
## Gathered by [method _audit_camp] across every generated floor.
var _camps := 0
var _whole_camps := 0
var _full_plots := 0
## Gathered by [method _audit_village] across every floor that settles.
var _settling := 0
var _villages := 0
var _whole_villages := 0
## Villages with [constant FloorCamp.MIN_HOUSES] houses or more.
var _streets := 0
## Villages with a trader at the band's counter.
var _traders := 0
var _lost_jobs := 0
var _lost_players := 0
## Gathered by [method _audit_arena] across every open field.
var _arenas := 0
var _whole_arenas := 0
var _open_safe_zones := 0
## Gathered by [method _audit_dungeon] across every dungeon floor.
var _dungeons := 0
var _dungeon_levels := 0
## Seals on dungeon levels, by [enum DungeonGenerator.Seal].
var _seals: Dictionary[int, int] = {}
var _landings := 0
var _tightest_seal_burn := INF
## Floor events (see [FloorEvents]): each kind's floors, and those it stands whole
## on; an ambush room's cells, and how many a fight for two can be staged on; the
## sides a duellist can be walked up to from, each of which must stage a duel.
var _events: Dictionary[int, int] = {}
var _whole_events: Dictionary[int, int] = {}
var _ambush_cells := 0
var _ambush_staged := 0
var _duel_sides := 0
## Gathered by [method _audit_landmark]: the landmarks built, by kind, and with a chest.
var _landmarks: Dictionary[int, int] = {}
var _landmark_chests := 0
## Gathered by [method _audit_room_shapes]: the rooms shaped, by kind, the rooms
## there were, and the monsters stepped off the rock.
var _room_shapes: Dictionary[int, int] = {}
var _shapeable_rooms := 0
var _stepped_monsters := 0


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
	GameState.visit_floor(12)
	GameState.visit_floor(3)
	GameState.visit_floor(12)
	_check(GameState.visited_floors() == ([3, 12] as Array[int]) and GameState.has_visited(3)
			and not GameState.has_visited(2) and GameState.has_flag(&"floor_12_visited"),
			"visited floors are a set, listed lowest first, each with its world flag")

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
		# The obstacle is solid and drawn as itself, wherever the generator scatters
		# one: a slot cut from an empty cell of its sheet is an invisible wall in the
		# middle of a room, which no flood fill and no tile check can see.
		var drawn := _opaque_pixels(sample_biome, sample_biome.obstacle_tile)
		_check(drawn >= 64, "%s's obstacle draws something (%d px)" % [label, drawn])
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
		if FloorRegistry.shape_of(floor_number) == FloorDefinition.Shape.DUNGEON:
			var climbed := _audit_dungeon(floor_number)
			if not climbed.is_empty():
				broken.append(climbed)
			continue
		var map := FloorGenerator.generate(definition, FloorRegistry.seed_for(floor_number))
		# Before the audit breaks its cracked wall and opens its vault.
		var unsettled := _outside(map, map.get_meta(&"camp", Rect2i()))
		var problem := _audit(map, definition)
		if not problem.is_empty():
			broken.append(problem)
		elif LocalQuests.settles(floor_number):
			# And again once it has settled, beside the camp it grew from.
			FloorCamp.settle_override = 1
			var settled := FloorGenerator.generate(definition, FloorRegistry.seed_for(floor_number))
			FloorCamp.settle_override = -1
			problem = _audit_village(settled as GameMap, map.get_meta(&"camp"), unsettled, floor_number)
			if not problem.is_empty():
				broken.append(problem)
			settled.free()
		map.free()
	_check(broken.is_empty(), "all %d generated floors are completable, settled or not%s" % [generated,
			"" if broken.is_empty() else " -- " + ", ".join(broken)])
	# The door is somewhere in the far third of the maze, not in its farthest corner
	# every time -- or the labyrinth is a corridor with a known end.
	_check(_lab_floors + _arenas + _dungeons == generated and _lab_not_farthest * 4 >= _lab_floors,
			"the boss room is not always the labyrinth's farthest point (%d of %d floors aren't)" % [
				_lab_not_farthest, _lab_floors])
	# Some floors, not all and not one in ten: the peddler is a stroke of luck.
	_check(_merchants * 5 >= _lab_floors and _merchants * 5 <= _lab_floors * 3,
			"a peddler keeps shop in %d of %d labyrinths' safe zones" % [_merchants, _lab_floors])
	# Open fields: some, not most -- the classic floor is still the climb's shape --
	# each arena sealed by its full set of waystones and a safe zone by a fire on
	# nearly every one. Measured at 14 of 97 floors on this seed.
	_check(_arenas * 10 >= generated and _arenas * 2 <= generated,
			"%d of %d generated floors are open fields, the rest classic" % [_arenas, generated])
	_check(_whole_arenas * 10 >= _arenas * 9 and _open_safe_zones * 10 >= _arenas * 9,
			"%d of %d arenas are sealed by all %d waystones, %d with a safe zone in the field" % [
				_whole_arenas, _arenas, FloorGenerator.WAYSTONES, _open_safe_zones])
	# Dungeons: about as many as open fields, each climbed level by level through
	# sealed stairs (every level walked in the sweep above). Every kind of seal turns
	# up, the warden -- who stands in for a seal with no room -- not the most of them,
	# and nearly every dungeon rests you halfway up.
	var wardens: int = _seals.get(DungeonGenerator.Seal.WARDEN, 0)
	var sealed := 0
	var by_kind := PackedStringArray()
	for kind in DungeonGenerator.SEAL_NAMES.size():
		sealed += _seals.get(kind, 0)
		by_kind.append("%d %s" % [_seals.get(kind, 0), DungeonGenerator.SEAL_NAMES[kind]])
	_check(_dungeons * 10 >= generated and _dungeons * 2 <= generated,
			"%d of %d generated floors are dungeons, %d levels in all" % [_dungeons, generated, _dungeon_levels])
	_check(_seals.size() == DungeonGenerator.SEAL_NAMES.size() and wardens * 2 <= sealed,
			"every kind of seal holds a dungeon's stairs (%s)" % ", ".join(by_kind))
	_check(_landings * 10 >= _dungeons * 8,
			"%d of %d dungeons have a landing with a fire halfway up" % [_landings, _dungeons])
	_check(_tightest_seal_burn >= 1.25,
			"a timed rite on the stairs burns long enough to walk round (tightest: %.2fx the walk)" % _tightest_seal_burn)
	var shortest := 1 << 30
	for walk in _lab_walks:
		shortest = mini(shortest, walk)
	# Measured at 70 over four world seeds, 64 on this one since the safe zone joined
	# the reasons a maze is regrown. It was 28 when the maze fitted on about a
	# screen, which is what made it read as a corridor -- see M5.5 §5 in plan.md.
	_check(shortest >= 60, "the labyrinth always stands in front of the door (shortest walk in: %d tiles)" % shortest)
	# Every generated floor has its camp, and most have the whole of it: a fire, both
	# tents and two people. Measured at 175 of 194 over two world seeds; what falls
	# short is an arrival room whose neighbours crowd the plot.
	_check(_camps == generated and _whole_camps * 100 >= _camps * 80,
			"every generated floor has an adventurers' camp, and %d of %d are whole (%d at full size)" % [
				_whole_camps, _camps, _full_plots])
	# Every floor that can settle grows a village, and most grow the whole of one:
	# a house at least and both its settlers with their jobs. What falls short is
	# the plot a crowded arrival room left the camp. Measured at 83 of 94 on this
	# seed, 60 of them with two houses or more.
	_check(_villages == _settling and _whole_villages * 100 >= _villages * 80
			and _lost_players == _lost_jobs,
			"%d of %d settling floors grow a whole village (%d with %d houses or more), and all %d lost players wait in a dead end" % [
				_whole_villages, _settling, _streets, FloorCamp.MIN_HOUSES, _lost_jobs])
	# And most keep a counter: the trader stands on a camper's old cell, so a plot
	# the village's houses fill has none. Measured at 76 of 94 on this seed.
	_check(_traders * 100 >= _villages * 75,
			"%d of %d villages keep their band's counter" % [_traders, _villages])
	# A gilded chest is a gamble only if all three outcomes turn up somewhere.
	var plain: int = _gilded.get(Chest.Trap.NONE, 0)
	var alarms: int = _gilded.get(Chest.Trap.ALARM, 0)
	var teleports: int = _gilded.get(Chest.Trap.TELEPORT, 0)
	_check(plain > 0 and alarms > 0 and teleports > 0,
			"gilded chests are sometimes safe, sometimes alarms, sometimes teleports (%d / %d / %d)" % [
				plain, alarms, teleports])
	# Puzzles: solvable wherever they are (in the audit above), and on nearly every
	# floor -- a puzzle that only turns up on a third of them is a rumour.
	# Not on a dungeon, whose puzzles are its seals (above).
	var fields := generated - _dungeons
	var timed: int = _rites.get(BrazierRite.Mode.TIMED, 0)
	var ordered: int = _rites.get(BrazierRite.Mode.ORDERED, 0)
	_check(_wisps * 10 >= fields * 9 and _shortest_wisp >= 12,
			"a wisp leads somewhere on %d of %d floors (shortest lead: %d cells)" % [
				_wisps, fields, _shortest_wisp])
	_check((timed + ordered) * 10 >= fields * 9 and timed > 0 and ordered > 0,
			"braziers wait on %d of %d floors (%d timed, %d ordered)" % [
				timed + ordered, fields, timed, ordered])
	_check(_tightest_burn >= 1.25,
			"a timed rite always burns long enough to walk round (tightest: %.2fx the walk)" % _tightest_burn)
	_check(_rings * 10 >= fields * 9 and _fewest_ring_turns >= FloorPuzzles.RING_TURNS_MIN,
			"statues turn on %d of %d floors, %d to %d turns from facing in" % [
				_rings, fields, _fewest_ring_turns, _most_ring_turns])
	_check(_vaults * 4 >= fields * 3 and _gilded_sigils > 0,
			"a sealed vault stands on %d of %d floors (a sigil under a gilded chest on %d)" % [
				_vaults, fields, _gilded_sigils])
	_check(_cracks * 4 >= fields * 3 and _cracks_in_trees > 0,
			"a cracked wall hides a hollow on %d of %d floors (%d of them in a forest)" % [
				_cracks, fields, _cracks_in_trees])
	print("       (%d of them in a north wall, facing you; the rest in a side wall)" % _cracks_facing)
	# Puzzles draw on a stream of their own: the floor without them is the same
	# floor -- the same chests, the same monsters, the same door.
	# Without the floor's event, its landmark or its rooms' shapes, which are planned
	# round whatever the puzzles took.
	var moved: PackedStringArray = PackedStringArray()
	FloorGenerator.event_override = FloorEvents.Kind.NONE
	FloorGenerator.landmark_override = FloorLandmarks.Kind.NONE
	FloorGenerator.with_room_shapes = false
	for sample: int in [2, 23, 37, 58, 76, 99]:
		var with := FloorGenerator.generate(FloorRegistry.get_floor(sample), FloorRegistry.seed_for(sample))
		FloorGenerator.with_puzzles = false
		var without := FloorGenerator.generate(FloorRegistry.get_floor(sample), FloorRegistry.seed_for(sample))
		FloorGenerator.with_puzzles = true
		if _floor_contents(with) != _floor_contents(without) or not _monsters_stay(with, without):
			moved.append(str(sample))
		with.free()
		without.free()
	FloorGenerator.event_override = -1
	FloorGenerator.landmark_override = -1
	FloorGenerator.with_room_shapes = true
	_check(moved.is_empty(), "a floor's puzzles move nothing its own seed put down%s" % (
			"" if moved.is_empty() else " -- they do on " + ", ".join(moved)))

	# --- modifiers ---
	# About one generated floor in five carries a twist, on a stream of its own:
	# never an authored floor, floor 2 or the top, and a storm only under a sky.
	var modified := 0
	var by_modifier: Dictionary[int, int] = {}
	var misplaced := PackedStringArray()
	var picks_here := PackedStringArray()
	var picks_there := PackedStringArray()
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		var kind := FloorRegistry.modifier_of(floor_number)
		picks_here.append(str(kind))
		picks_there.append(str(FloorRegistry.modifier_in(999, floor_number)))
		if kind == FloorModifier.Kind.NONE:
			continue
		modified += 1
		by_modifier[kind] = by_modifier.get(kind, 0) + 1
		if FloorRegistry.get_floor(floor_number).is_authored() or floor_number <= 2 \
				or floor_number >= FloorTuning.TOP_FLOOR:
			misplaced.append("%d" % floor_number)
		elif kind == FloorModifier.Kind.STORM and (
				FloorModifier.weather_for(FloorRegistry.biome_id(floor_number)) == &""
				or FloorRegistry.shape_of(floor_number) == FloorDefinition.Shape.DUNGEON):
			misplaced.append("%d (a storm with no sky)" % floor_number)
	var infested: int = by_modifier.get(FloorModifier.Kind.INFESTED, 0)
	var storms: int = by_modifier.get(FloorModifier.Kind.STORM, 0)
	_check(misplaced.is_empty() and modified * 10 >= generated and modified * 10 <= generated * 3
			and infested > 0 and storms > 0,
			"%d of %d generated floors carry a modifier (%d infested, %d storms), where they may%s" % [
				modified, generated, infested, storms,
				"" if misplaced.is_empty() else " -- not on " + ", ".join(misplaced)])
	_check(picks_here != picks_there, "another world puts its modifiers on other floors")
	# And a modifier moves nothing the floor puts down: the floor without it, plus
	# its swarm or its storm, and the scout in its camp saying so.
	var twisted := PackedStringArray()
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		if FloorRegistry.modifier_of(floor_number) != FloorModifier.Kind.NONE:
			var problem := _audit_modifier(floor_number)
			if not problem.is_empty():
				twisted.append(problem)
	_check(twisted.is_empty(),
			"every modified floor is the floor it would be without, plus its swarm or its storm%s" % (
				"" if twisted.is_empty() else " -- " + ", ".join(twisted)))

	# --- events ---
	# About half the floors that may have one: never an authored floor, floor 2,
	# the top or a dungeon, and never the same kind
	# two floors running. On a stream of their own, like the modifiers.
	var eligible := 0
	var happening := 0
	var by_event: Dictionary[int, int] = {}
	var misplaced_events := PackedStringArray()
	var events_here := PackedStringArray()
	var events_there := PackedStringArray()
	var last_event := FloorEvents.Kind.NONE
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		var kind := FloorRegistry.event_of(floor_number)
		var shape := FloorRegistry.shape_of(floor_number)
		events_here.append(str(kind))
		events_there.append(str(FloorRegistry.event_in(999, floor_number)))
		var may := not (FloorRegistry.get_floor(floor_number).is_authored() or floor_number <= 2
				or floor_number >= FloorTuning.TOP_FLOOR or shape == FloorDefinition.Shape.DUNGEON)
		if may:
			eligible += 1
		if kind != FloorEvents.Kind.NONE:
			happening += 1
			by_event[kind] = by_event.get(kind, 0) + 1
			if not may:
				misplaced_events.append("%d" % floor_number)
			elif kind == last_event:
				misplaced_events.append("%d (the same as the floor below)" % floor_number)
		last_event = kind
	var event_counts := PackedStringArray()
	for kind in range(1, FloorEvents.Kind.size()):
		event_counts.append("%d %s" % [by_event.get(kind, 0), FloorEvents.KIND_NAMES[kind]])
	_check(misplaced_events.is_empty() and happening * 10 >= eligible * 3 and happening * 10 <= eligible * 7
			and by_event.size() == FloorEvents.Kind.size() - 1,
			"%d of %d floors that may have one have an event (%s), where they may%s" % [
				happening, eligible, ", ".join(event_counts),
				"" if misplaced_events.is_empty() else " -- not on " + ", ".join(misplaced_events)])
	_check(events_here != events_there, "another world has its events on other floors")
	# Each is the floor without it, plus the event -- and the event sound: a hoard
	# shut until its keeper falls, a stranded player with a way home, an ambush
	# that can spring, a duel that can be staged in the camp.
	var unsound := PackedStringArray()
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		if FloorRegistry.event_of(floor_number) != FloorEvents.Kind.NONE:
			var problem := _audit_event(floor_number)
			if not problem.is_empty():
				unsound.append(problem)
	var whole_counts := PackedStringArray()
	var mostly_whole := true
	for kind in range(1, FloorEvents.Kind.size()):
		whole_counts.append("%d of %d %s" % [_whole_events.get(kind, 0), _events.get(kind, 0),
				FloorEvents.KIND_NAMES[kind]])
		mostly_whole = mostly_whole and _whole_events.get(kind, 0) * 10 >= _events.get(kind, 0) * 8
	_check(unsound.is_empty() and mostly_whole,
			"every event is the floor without it plus the event, and sound (%s)%s" % [
				", ".join(whole_counts), "" if unsound.is_empty() else " -- " + ", ".join(unsound)])
	_check(_ambush_staged * 10 >= _ambush_cells * 9,
			"an ambush can spring on %d of the %d cells of its rooms" % [_ambush_staged, _ambush_cells])
	print("       (a duel can be staged from all %d sides a duellist can be walked up to from)" % _duel_sides)

	# --- landmarks ---
	# About half the floors that may have one: never an authored floor, floor 2, the
	# top or a dungeon; never the same kind two floors running, and only a kind its
	# band can draw. On a stream of their own, like the events.
	var may_landmark := 0
	var picked_landmarks := 0
	var by_pick: Dictionary[int, int] = {}
	var misplaced_landmarks := PackedStringArray()
	var landmarks_here := PackedStringArray()
	var landmarks_there := PackedStringArray()
	var last_landmark := FloorLandmarks.Kind.NONE
	for floor_number in range(1, FloorTuning.TOP_FLOOR + 1):
		var kind := FloorRegistry.landmark_of(floor_number)
		landmarks_here.append(str(kind))
		landmarks_there.append(str(FloorRegistry.landmark_in(999, floor_number)))
		var may := not (FloorRegistry.get_floor(floor_number).is_authored() or floor_number <= 2
				or floor_number >= FloorTuning.TOP_FLOOR
				or FloorRegistry.shape_of(floor_number) == FloorDefinition.Shape.DUNGEON)
		if may:
			may_landmark += 1
		if kind != FloorLandmarks.Kind.NONE:
			picked_landmarks += 1
			by_pick[kind] = by_pick.get(kind, 0) + 1
			if not may:
				misplaced_landmarks.append("%d" % floor_number)
			elif kind == last_landmark:
				misplaced_landmarks.append("%d (the same as the floor below)" % floor_number)
			elif not kind in FloorLandmarks.kinds_for(FloorRegistry.biome_id(floor_number)):
				misplaced_landmarks.append("%d (a %s in the %s)" % [floor_number,
						FloorLandmarks.KIND_NAMES[kind], FloorRegistry.biome_id(floor_number)])
		last_landmark = kind
	var pick_counts := PackedStringArray()
	for kind in range(1, FloorLandmarks.Kind.size()):
		pick_counts.append("%d %s" % [by_pick.get(kind, 0), FloorLandmarks.KIND_NAMES[kind]])
	_check(misplaced_landmarks.is_empty() and picked_landmarks * 10 >= may_landmark * 3
			and picked_landmarks * 10 <= may_landmark * 7 and by_pick.size() == FloorLandmarks.Kind.size() - 1,
			"%d of %d floors that may have one pick a landmark (%s), where they may%s" % [
				picked_landmarks, may_landmark, ", ".join(pick_counts),
				"" if misplaced_landmarks.is_empty() else " -- not on " + ", ".join(misplaced_landmarks)])
	_check(landmarks_here != landmarks_there, "another world has its landmarks on other floors")
	# Each is the floor without it, plus the landmark -- dressed the same outside its
	# room, down to the flowers -- and sound: named on M, read, cutting nothing off,
	# its chest reachable, nobody standing in it, and the camp saying so.
	var unsound_landmarks := PackedStringArray()
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		if FloorRegistry.landmark_of(floor_number) != FloorLandmarks.Kind.NONE:
			var problem := _audit_landmark(floor_number)
			if not problem.is_empty():
				unsound_landmarks.append(problem)
	var built := 0
	var built_counts := PackedStringArray()
	for kind in range(1, FloorLandmarks.Kind.size()):
		built += _landmarks.get(kind, 0)
		built_counts.append("%d %s" % [_landmarks.get(kind, 0), FloorLandmarks.KIND_NAMES[kind]])
	_check(unsound_landmarks.is_empty() and built * 10 >= picked_landmarks * 8
			and _landmarks.size() == FloorLandmarks.Kind.size() - 1,
			"every landmark is the floor without it plus the landmark, and sound (%d of %d built: %s; %d keep a chest)%s" % [
				built, picked_landmarks, ", ".join(built_counts), _landmark_chests,
				"" if unsound_landmarks.is_empty() else " -- " + ", ".join(unsound_landmarks)])

	# --- room shapes ---
	# Most rooms that nothing else has a use for are given a shape -- rock put back
	# into the rectangle, never carved out of it. Each floor is the floor without its
	# shapes plus the rock: every node where it was, but monsters stepped off the rock
	# onto the floor of their room; every tile as solid as before outside the rooms it
	# shaped; the rock and the floor beside it two thick, as the walls can draw. Every
	# floor above was built shaped, so it is already proven completable, staged and
	# dressed right with them.
	var unshaped := PackedStringArray()
	var shaped_floors := 0
	for floor_number in range(2, FloorTuning.TOP_FLOOR + 1):
		if FloorRegistry.get_floor(floor_number).is_authored():
			continue
		var before := _room_shapes.duplicate()
		var problem := _audit_room_shapes(floor_number)
		if not problem.is_empty():
			unshaped.append(problem)
		if _room_shapes != before:
			shaped_floors += 1
	var shape_counts := PackedStringArray()
	var shaped_rooms := 0
	for kind in range(1, RoomShapes.Kind.size()):
		shaped_rooms += _room_shapes.get(kind, 0)
		shape_counts.append("%d %s" % [_room_shapes.get(kind, 0), RoomShapes.KIND_NAMES[kind]])
	_check(unshaped.is_empty(),
			"every shaped floor is the floor without its shapes plus the rock, two thick%s" % (
			"" if unshaped.is_empty() else " -- " + ", ".join(unshaped)))
	_check(shaped_floors * 10 >= 97 * 9 and _room_shapes.size() == RoomShapes.Kind.size() - 1
			and _room_shapes.get(RoomShapes.Kind.PILLARS, 0) >= 10,
			"rooms take shapes on %d of 97 generated floors (%d rooms: %s; %d monsters stepped off the rock)" % [
				shaped_floors, shaped_rooms, ", ".join(shape_counts), _stepped_monsters])

	# --- and so is every authored one ---
	var broken_authored: PackedStringArray = PackedStringArray()
	for floor_number in FloorRegistry.AUTHORED:
		var problem := _audit_authored(floor_number)
		if not problem.is_empty():
			broken_authored.append(problem)
	_check(broken_authored.is_empty(),
			"every authored floor is completable, ends in a labyrinth and has its puzzles solvable%s" % (
			"" if broken_authored.is_empty() else " -- " + ", ".join(broken_authored)))

	# Every floor, authored or generated, can be gone back to: a gate where it is
	# entered, an arrival in front of it, and nothing walled off by its base.
	_check(_teleport_gates == FloorTuning.TOP_FLOOR,
			"every floor has a teleport gate where it is entered (%d of %d)" % [
				_teleport_gates, FloorTuning.TOP_FLOOR])

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
	var gated := _audit_teleport_gate(map as GameMap, walls, start, floor_number,
			"floor %d" % floor_number)
	if not gated.is_empty():
		return gated
	var camped := _audit_camp(map as GameMap, walls, start, floor_number)
	if not camped.is_empty():
		return camped

	# Autotiling rewrites every wall on the floor. Dropping one instead of
	# replacing it would open the map onto the void, and the flood fill above
	# would quietly reach further rather than fail -- so the sealed outer ring,
	# which nothing is ever allowed to carve, is checked directly.
	# The map is the field plus the labyrinth's strip, side by side, so its ring is
	# the used rect's, not the field's -- which the doorstep corridor does cut through.
	# An open field is its bigger field plus the arena's strip, the same way.
	var open_field := map.has_meta(&"arena")
	var bounds := walls.get_used_rect()
	var strip := definition.labyrinth * FloorGenerator.LAB_PITCH \
			+ Vector2i(FloorGenerator.LAB_WALL, FloorGenerator.LAB_WALL)
	var field := definition.size
	if open_field:
		strip = FloorGenerator.ARENA_ROOM + Vector2i(FloorGenerator.LAB_WALL, FloorGenerator.LAB_WALL) * 2
		field = FloorTuning.open_field_size(floor_number)
	if bounds.position != Vector2i.ZERO or not (bounds.size in [
			Vector2i(field.x + strip.x, maxi(field.y, strip.y)),
			Vector2i(maxi(field.x, strip.x), field.y + strip.y)]):
		return "floor %d is %s, not its field plus a%s" % [floor_number, bounds.size,
				"n arena" if open_field else " labyrinth"]
	for x in bounds.size.x:
		if not _sealed(walls, Vector2i(x, 0)) or not _sealed(walls, Vector2i(x, bounds.size.y - 1)):
			return "floor %d has a hole in its outer wall" % floor_number
	for y in bounds.size.y:
		if not _sealed(walls, Vector2i(0, y)) or not _sealed(walls, Vector2i(bounds.size.x - 1, y)):
			return "floor %d has a hole in its outer wall" % floor_number
	var lost := _audit_arena(map as GameMap, walls, gate, start, floor_number) if open_field \
			else _audit_labyrinth(map, walls, gate, start, reachable)
	if lost.is_empty():
		# The puzzles are walked with the arena open, as the door is once you can
		# fight what is behind it; shut, it is the arena audit's.
		_open_seal(map, "ArenaSeal")
		lost = _audit_puzzles(map as GameMap, walls, start, reachable, floor_number)
	if lost.is_empty():
		# With the vault open: a monster can follow you into it, so a fight has to
		# be stageable in there too -- and outside, an open doorway is only more room.
		_open_seal(map, "SealedDoor")
		# And the hoard's, a fight following you into it as into the vault.
		_open_seal(map, "HoardSeal")
		# And with the cracked wall broken, which the puzzle audit has done: its
		# hollow is floor now, and somewhere a fight can follow you into.
		reachable = _flood(walls, start)
		_audit_formations(map, walls, start, reachable, "floor %d" % floor_number)
		_audit_boss_formations(map, walls, gate, reachable, floor_number, "floor %d" % floor_number)
	return lost


## Takes the solid out of [param map]'s [SealedDoor] called [param seal_name], as
## opening it does.
func _open_seal(map: Node2D, seal_name: String) -> void:
	var seal := map.get_node_or_null(seal_name)
	if seal != null:
		for shape in seal.get_node("Solid").get_children():
			(shape as CollisionShape2D).disabled = true


## An open field's arena stands in plain sight with its door in it, walled all
## round but for its gate; the gate's seal keeps you out until every waystone is
## woken, and each of them can be walked up to while it does. And the field has a
## safe zone: the fire's room, which no monster starts in.
##
## The open field's half of what [method _audit_labyrinth] is to a classic floor:
## a sealed door the waystones cannot open, or a stone behind the seal, is the
## dead end a flood fill of the walls never sees.
func _audit_arena(map: GameMap, walls: TileMapLayer, gate: Node, start: Vector2i,
		floor_number: int) -> String:
	var label := "floor %d" % floor_number
	if not (map.has_meta(&"arena_room") and map.has_meta(&"arena_door")):
		return "%s is an open field with no arena" % label
	var arena: Rect2i = map.get_meta(&"arena")
	var room: Rect2i = map.get_meta(&"arena_room")
	var door: Rect2i = map.get_meta(&"arena_door")
	var gate_cell := walls.local_to_map((gate as Node2D).position)
	if not room.has_point(gate_cell) or not arena.encloses(room):
		return "%s's door is not in its arena" % label
	if (gate.get(&"reveal_area") as Rect2).has_area() or map.dark_area.has_area():
		return "%s hides its door or darkens its field, and it is an open field" % label

	# Walled all round but for its gate, and the gate is the way in.
	for y in range(arena.position.y, arena.end.y):
		for x in range(arena.position.x, arena.end.x):
			var cell := Vector2i(x, y)
			var open := walls.get_cell_source_id(cell) == -1
			if door.has_point(cell) and not open:
				return "%s's arena gate is walled up at %s" % [label, cell]
			if open and not room.has_point(cell) and not door.has_point(cell):
				return "%s's arena wall is open at %s" % [label, cell]
	if _flood_except(walls, start, door).has(gate_cell):
		return "%s's door can be reached without going through the arena gate" % label

	# The seal stands in the gate, and its hollows are the waystones'.
	var seal := map.get_node_or_null("ArenaSeal") as SealedDoor
	if seal == null or not door.has_point(walls.local_to_map(seal.position)):
		return "%s's arena gate has no seal in it" % label
	var stones: Array[Waystone] = []
	var flags: Array[StringName] = []
	for child in map.get_children():
		if child is Waystone:
			var stone := child as Waystone
			if stone.flag == &"" or flags.has(stone.flag) or stone.all_flags != seal.sigils:
				return "%s's %s is not one of the seal's hollows" % [label, stone.name]
			stones.append(stone)
			flags.append(stone.flag)
	if flags.size() != seal.sigils.size():
		return "%s's seal wants %d waystones and the field has %d" % [label, seal.sigils.size(), flags.size()]
	if not seal.opens_itself or not seal.also_sets.has(BossGate.found_flag(floor_number)):
		return "%s's seal does not open itself and mark the door found" % label
	_arenas += 1
	if stones.size() == FloorGenerator.WAYSTONES:
		_whole_arenas += 1

	# Shut, it keeps you out and every stone can be walked up to; open, it lets you in.
	map.refresh_solids()
	var shut := _flood_standable(map, start)
	for stone in stones:
		if not _approachable(walls, stone, shut):
			return "%s's %s cannot be walked up to with the arena shut" % [label, stone.name]
		if arena.has_point(walls.local_to_map(stone.position)):
			return "%s's %s stands in the arena" % [label, stone.name]
	if not _approachable(walls, seal, shut):
		return "%s's arena gate cannot be walked up to" % label
	if _approachable(walls, gate as Node2D, shut):
		return "%s's arena can be walked into with its gate shut" % label
	_open_seal(map, "ArenaSeal")
	map.refresh_solids()
	if not _approachable(walls, gate as Node2D, _flood_standable(map, start)):
		return "%s's door cannot be walked up to with the arena open" % label

	# A safe zone in the field, where there is one: the fire in it, nothing that
	# fights starting in it.
	if not map.has_meta(&"safe_zone"):
		return ""
	var camp: Rect2i = map.get_meta(&"safe_zone")
	if not map.safe_zones.has(camp) or camp.intersects(arena) \
			or camp.intersects(map.get_meta(&"camp", Rect2i())):
		return "%s's safe zone %s is not a clearing of its own the map keeps monsters out of" % [label, camp]
	var fire := map.get_node_or_null("Campfire") as Campfire
	if fire == null or not fire.rests or not camp.has_point(walls.local_to_map(fire.position - Vector2(0, 8))):
		return "%s's safe zone has no fire in it" % label
	for child in map.get_children():
		if child is Monster and camp.has_point(walls.local_to_map((child as Node2D).position)):
			return "%s has %s starting in its safe zone" % [label, child.name]
	_open_safe_zones += 1
	return ""


## A dungeon floor is its levels, and each is held to what a classic floor is held
## to on its own map -- sealed ring, reachable chests, a fight stageable wherever
## one can start -- plus the one thing a level adds: its ladder up stands in a
## chamber walled all round but for a doorway, the seal in the doorway keeps you
## out until whatever this level hides opens it, every piece of that can be walked
## up to with the seal shut, and the ladder can be walked up to with it open. The
## first level is the entrance hall, with the camp and the gate; the top is the boss
## hall, lit, with its door found as you arrive. Across the levels the floor carries
## its full count of monsters, so the boss's balance is the floor's.
func _audit_dungeon(floor_number: int) -> String:
	var floor_label := "dungeon floor %d" % floor_number
	var levels := FloorRegistry.levels_of(floor_number)
	if levels != FloorTuning.dungeon_levels(floor_number) or levels < 3:
		return "%s has %d levels" % [floor_label, levels]
	var monsters := 0
	var unsettled := ""
	var camp := Rect2i()
	for level in range(1, levels + 1):
		var map := FloorRegistry.build_floor(floor_number, level) as GameMap
		if level == 1:
			camp = map.get_meta(&"camp", Rect2i())
			unsettled = _outside(map, camp)
		var problem := _audit_level(map, floor_number, level, levels)
		for child in map.get_children():
			if child is Monster and (child as Monster).defeat_flag == &"":
				monsters += 1
		map.free()
		if not problem.is_empty():
			return problem
		_dungeon_levels += 1
	if monsters < FloorTuning.monster_count(floor_number):
		return "%s carries %d monsters across its levels, not %d" % [floor_label, monsters,
				FloorTuning.monster_count(floor_number)]
	if LocalQuests.settles(floor_number):
		FloorCamp.settle_override = 1
		var settled := FloorRegistry.build_floor(floor_number, 1) as GameMap
		FloorCamp.settle_override = -1
		var problem := _audit_village(settled, camp, unsettled, floor_number)
		settled.free()
		if not problem.is_empty():
			return problem
	_dungeons += 1
	return ""


## One of a dungeon's levels -- see [method _audit_dungeon].
func _audit_level(map: GameMap, floor_number: int, level: int, levels: int) -> String:
	var label := "floor %d level %d" % [floor_number, level]
	var walls := map.get_node_or_null("Walls") as TileMapLayer
	var spawns := map.get_node_or_null("SpawnPoints")
	if walls == null or spawns == null:
		return "%s is missing Walls/SpawnPoints" % label
	if map.map_id != DungeonGenerator.map_id_for(floor_number, level) \
			or map.get_meta(&"dungeon_level", 0) != level or map.floor_number != floor_number:
		return "%s calls itself %s" % [label, map.map_id]
	var start: Vector2i = walls.local_to_map((spawns.get_node("default") as Node2D).position)
	if walls.get_cell_source_id(start) != -1:
		return "%s spawns inside a wall" % label
	for spawn_name in ["stairs_down", "stairs_up", "from_below", "from_above"]:
		if spawns.get_node_or_null(spawn_name) == null:
			return "%s has no %s spawn" % [label, spawn_name]

	# Sealed all round and dark all over, as a labyrinth is.
	var bounds := walls.get_used_rect()
	if bounds.position != Vector2i.ZERO:
		return "%s does not start at the origin" % label
	for cell in _ring(bounds):
		if not _sealed(walls, cell):
			return "%s has a hole in its outer wall at %s" % [label, cell]
	if map.dark_area != bounds:
		return "%s is dark over %s, not all of its %s" % [label, map.dark_area, bounds]

	var reachable := _flood(walls, start)
	var trapped := _audit_chests(map, walls, reachable, label, true)
	if not trapped.is_empty():
		return trapped
	var down := map.get_node_or_null("StairsDown") as Node2D
	if down == null or not reachable.has(walls.local_to_map(down.position)):
		return "%s's stairs down can't be reached" % label
	if level == 1:
		if down.get(&"target_floor") != floor_number - 1 or down.get(&"target_level") != 0:
			return "%s's stairs down don't go to floor %d" % [label, floor_number - 1]
		var gated := _audit_teleport_gate(map, walls, start, floor_number, label)
		if not gated.is_empty():
			return gated
		var camped := _audit_camp(map, walls, start, floor_number)
		if not camped.is_empty():
			return camped.replace("floor %d" % floor_number, label)
		if not map.lit_areas.has(map.get_meta(&"camp")):
			return "%s's entrance hall is in the dark" % label
	elif down.get(&"target_floor") != floor_number or down.get(&"target_level") != level - 1 \
			or down.get(&"target_spawn") != &"stairs_up":
		return "%s's stairs down don't go to level %d's ladder" % [label, level - 1]

	var chamber: Rect2i = map.get_meta(&"chamber", Rect2i())
	var room: Rect2i = map.get_meta(&"chamber_room", Rect2i())
	var door: Rect2i = map.get_meta(&"chamber_door", Rect2i())
	if not chamber.encloses(room) or not door.has_area() or not chamber.intersects(door):
		return "%s has no chamber" % label
	# Walled all round but for its doorway, and the doorway is the way in.
	for y in range(chamber.position.y, chamber.end.y):
		for x in range(chamber.position.x, chamber.end.x):
			var cell := Vector2i(x, y)
			var open := walls.get_cell_source_id(cell) == -1
			if door.has_point(cell) and not open:
				return "%s's chamber doorway is walled up at %s" % [label, cell]
			if open and not room.has_point(cell) and not door.has_point(cell):
				return "%s's chamber wall is open at %s" % [label, cell]
	for child in map.get_children():
		if (child is Monster or child is Chest) and chamber.has_point(walls.local_to_map((child as Node2D).position)):
			return "%s has %s in its chamber" % [label, child.name]

	if level == levels:
		return _audit_top(map, walls, start, reachable, room, label, floor_number)

	var ladder := map.get_node_or_null("LadderUp") as Node2D
	var ladder_cell := walls.local_to_map(ladder.position) if ladder != null else Vector2i(-1, -1)
	if ladder == null or not room.has_point(ladder_cell) or ladder.get(&"target_level") != level + 1 \
			or ladder.get(&"target_spawn") != &"stairs_down" or not ladder.get(&"going_up"):
		return "%s's ladder up is not in its chamber, or doesn't go to level %d" % [label, level + 1]
	var arrives := walls.local_to_map((spawns.get_node("stairs_up") as Node2D).position)
	if not room.has_point(arrives) or (arrives - ladder_cell).length() > 1.5:
		return "%s's stairs_up spawn is not in front of its ladder" % label
	if _flood_except(walls, start, door).has(ladder_cell):
		return "%s's ladder can be reached without going through the chamber doorway" % label
	var seal := map.get_node_or_null("StairsSeal") as SealedDoor
	if seal == null or not door.has_point(walls.local_to_map(seal.position)):
		return "%s's chamber doorway has no seal in it" % label
	if not seal.opens_itself or seal.sigils.is_empty() \
			or seal.opened_flag != DungeonGenerator.stairs_flag(floor_number, level):
		return "%s's seal does not open itself on its pieces" % label
	var kind := DungeonGenerator.SEAL_NAMES.find(str(map.get_meta(&"seal", "")))
	if kind < 0:
		return "%s has no seal kind" % label

	# Shut: the ladder is out of reach, and the seal and every piece can be walked up to.
	map.refresh_solids()
	var shut := _flood_standable(map, start)
	if shut.has(ladder_cell) or shut.has(arrives):
		return "%s's ladder can be walked up to with the seal shut" % label
	if not _beside_rect(door, shut):
		return "%s's seal cannot be walked up to" % label
	var piece_problem := _audit_seal_pieces(map, walls, kind, seal, shut, chamber, label)
	if not piece_problem.is_empty():
		return piece_problem
	_seals[kind] = _seals.get(kind, 0) + 1

	# A landing, where there is one: the middle level, a fire in a room no monster
	# starts in.
	if map.has_meta(&"safe_zone"):
		var landing: Rect2i = map.get_meta(&"safe_zone")
		if level != DungeonGenerator.landing_level(levels):
			return "%s has a landing, and it is not the middle level" % label
		var fire := map.get_node_or_null("Campfire") as Campfire
		if not map.safe_zones.has(landing) or fire == null or not fire.rests \
				or not landing.has_point(walls.local_to_map(fire.position - Vector2(0, 8))):
			return "%s's landing has no fire in it" % label
		if not _approachable(walls, fire, shut):
			return "%s's landing fire cannot be walked up to" % label
		for child in map.get_children():
			if child is Monster and landing.has_point(walls.local_to_map((child as Node2D).position)):
				return "%s has %s starting on its landing" % [label, child.name]
		_landings += 1

	# Open: the ladder can be walked up to, and a fight staged anywhere on the level.
	_open_seal(map, "StairsSeal")
	map.refresh_solids()
	var open := _flood_standable(map, start)
	if not open.has(arrives) or not _approachable(walls, ladder, open):
		return "%s's ladder cannot be walked up to with the seal open" % label
	_audit_formations(map, walls, start, _flood(walls, start), label)
	return ""


## The pieces of a level's seal: what each is, that each answers to one of the
## seal's hollows, and that each can be walked up to -- [param shut] is every cell a
## body can stand on with the seal shut -- outside the chamber.
func _audit_seal_pieces(map: GameMap, walls: TileMapLayer, kind: int, seal: SealedDoor,
		shut: Dictionary, chamber: Rect2i, label: String) -> String:
	var pieces: Array[Node2D] = []
	match kind:
		DungeonGenerator.Seal.WARDEN:
			var warden := map.get_node_or_null("Warden") as Monster
			if warden == null or seal.sigils != ([warden.defeat_flag] as Array[StringName]):
				return "%s's seal wants a warden's key and has no warden" % label
			if warden.level <= FloorTuning.enemy_level(map.floor_number):
				return "%s's warden is no stronger than its monsters" % label
			if not shut.has(walls.local_to_map(warden.position)):
				return "%s's warden stands where you can't walk" % label
			if map.is_safe(warden.position):
				return "%s's warden stands in a safe zone" % label
		DungeonGenerator.Seal.LEVERS:
			var flags: Array[StringName] = []
			for child in map.get_children():
				if child is Waystone:
					var lever := child as Waystone
					if lever.all_flags != seal.sigils or flags.has(lever.flag):
						return "%s's %s is not one of the seal's hollows" % [label, lever.name]
					flags.append(lever.flag)
					pieces.append(lever)
			if flags.size() != seal.sigils.size() or flags.size() != DungeonGenerator.LEVERS:
				return "%s's seal wants %d levers and the level has %d" % [label, seal.sigils.size(), flags.size()]
		DungeonGenerator.Seal.BRAZIERS:
			var rite := map.get_node_or_null("BrazierRite") as BrazierRite
			var tablet := map.get_node_or_null("Tablet") as Tablet
			if rite == null or tablet == null or seal.sigils != ([rite.solved_flag] as Array[StringName]):
				return "%s's seal wants its fires and has no rite" % label
			if map.get_node_or_null("ChestRite") != null:
				return "%s's rite pays in a chest as well as the stairs" % label
			var approaches: Array = []
			for brazier in rite.braziers:
				pieces.append(brazier)
				approaches.append(_beside(walls, brazier, shut))
			pieces.append(tablet)
			if rite.mode == BrazierRite.Mode.TIMED:
				map.refresh_solids()
				var seconds := _shortest_round(map, approaches) / FloorPuzzles.WALK_TILES_PER_SECOND
				_tightest_seal_burn = minf(_tightest_seal_burn, rite.burn / maxf(seconds, 0.01))
				if rite.burn < seconds * 1.25:
					return "%s's fires burn %.1fs, and walking round them takes %.1fs" % [label, rite.burn, seconds]
			elif tablet.lines[0].count(" the ") < rite.braziers.size():
				return "%s's tablet does not name every fire" % label
		DungeonGenerator.Seal.STATUES:
			var ring := map.get_node_or_null("StatueRing") as StatueRing
			var altar := map.get_node_or_null("StatueAltar") as StatueAltar
			if ring == null or altar == null or seal.sigils != ([ring.solved_flag] as Array[StringName]):
				return "%s's seal wants its statues turned and has no ring" % label
			if map.get_node_or_null("ChestStatues") != null:
				return "%s's ring pays in a chest as well as the stairs" % label
			var facings: Array[int] = []
			for statue in ring.statues:
				pieces.append(statue)
				facings.append(statue.facing)
			pieces.append(altar)
			var turns := StatueRing.turns_to_solve(facings, ring.targets)
			var total := 0
			for count in turns:
				total += count
			if turns.is_empty() or total < FloorPuzzles.RING_TURNS_MIN:
				return "%s's statues are %d turns from facing in" % [label, total]
	for piece in pieces:
		if not _approachable(walls, piece, shut):
			return "%s's %s cannot be walked up to with the seal shut" % [label, piece.name]
		if chamber.has_point(walls.local_to_map(piece.position)):
			return "%s's %s stands in the chamber it opens" % [label, piece.name]
	return ""


## A dungeon's top level: the boss hall, lit, its doorway open and its door in the
## middle, found the moment the level is entered -- and the boss can be fought from
## every cell the door can be challenged from.
func _audit_top(map: GameMap, walls: TileMapLayer, start: Vector2i, reachable: Dictionary,
		hall: Rect2i, label: String, floor_number: int) -> String:
	var gate := map.get_node_or_null("BossGate") as BossGate
	if gate == null or not hall.has_point(walls.local_to_map(gate.position)):
		return "%s has no boss door in its hall" % label
	if gate.reveal_area.has_area() or not gate.found_on_arrival:
		return "%s hides its boss door" % label
	if not reachable.has(walls.local_to_map(gate.position)):
		return "%s's boss door can't be reached" % label
	if not map.lit_areas.has(map.get_meta(&"chamber")):
		return "%s's boss hall is in the dark" % label
	if map.get_node_or_null("StairsSeal") != null or map.get_node_or_null("LadderUp") != null:
		return "%s has a way further up" % label
	map.refresh_solids()
	if not _approachable(walls, gate, _flood_standable(map, start)):
		return "%s's boss door cannot be walked up to" % label
	_audit_boss_formations(map, walls, gate, reachable, floor_number, label)
	return ""


## Whether any cell next to [param rect] -- a doorway two cells square -- is in
## [param walkable].
func _beside_rect(rect: Rect2i, walkable: Dictionary) -> bool:
	for cell in _ring(rect.grow(1)):
		if walkable.has(cell):
			return true
	return false


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
	var peddled := _audit_merchant(map as GameMap, walls, camp, gate, start, floor_number)
	if not peddled.is_empty():
		return peddled

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


## The peddler, where there is one: by the fire in the safe zone, keeping a listed
## shop, walkable up to -- and, with them and the fire both solid, every cell of
## the room and the door still reachable. The walls-only flood fills can't see a
## body standing in a doorway; this is the walk that can.
func _audit_merchant(map: GameMap, walls: TileMapLayer, camp: Rect2i, gate: Node, start: Vector2i,
		floor_number: int) -> String:
	var merchant := map.get_node_or_null("Merchant") as Npc
	if merchant == null:
		return ""
	_merchants += 1
	if not camp.has_point(walls.local_to_map(merchant.position)):
		return "floor %d's peddler stands outside its safe zone" % floor_number
	if merchant.shop == null or not String(merchant.shop.id) in ShopLibrary.SHOPS:
		return "floor %d's peddler keeps no listed shop" % floor_number
	map.refresh_solids()
	var standable := _flood_standable(map, start)
	if not _approachable(walls, merchant, standable):
		return "floor %d's peddler can't be walked up to" % floor_number
	if not _approachable(walls, gate as Node2D, standable):
		return "floor %d's peddler cuts the door off" % floor_number
	for y in range(camp.position.y, camp.end.y):
		for x in range(camp.position.x, camp.end.x):
			var cell := Vector2i(x, y)
			if map.is_standable(cell) and not standable.has(cell):
				return "floor %d's peddler walls off %s in the safe zone" % [floor_number, cell]
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
		label: String, within: Array[Rect2i] = []) -> void:
	var problem := _formation_problem(map, walls, start, reachable, label, within)
	if not problem.is_empty():
		_unstaged.append(problem)


## [param within], when given, sweeps only the cells inside those rects.
func _formation_problem(map: Node2D, walls: TileMapLayer, start: Vector2i, reachable: Dictionary,
		label: String, within: Array[Rect2i] = []) -> String:
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
		if not within.is_empty() and not within.any(func(rect: Rect2i) -> bool: return rect.has_point(cell)):
			continue
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
	# The first map is the one the floor is entered at, and where its teleport
	# gate has to be: arriving through any gate builds the floor and asks for it.
	var entry_map := true
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
		if problem.is_empty() and entry_map:
			problem = _audit_teleport_gate(map as GameMap, walls, start, floor_number, label)
		entry_map = false
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


## A floor's teleport gate stands on the map the floor is entered at and answers
## for that floor; its map's [code]gate[/code] spawn, where you arrive through it,
## is in front of it and can be stood on from the entrance; and its base, which is
## solid, cuts nothing off -- every cell a body could walk to without it, it can
## walk to with it, bar the cells the base stands in. The walls-only flood fills
## never see the gate, so they would not notice it closing a corridor.
func _audit_teleport_gate(map: GameMap, walls: TileMapLayer, start: Vector2i,
		floor_number: int, label: String) -> String:
	var gate := map.get_node_or_null("TeleportGate") as TeleportGate
	if gate == null:
		return "%s has no teleport gate" % label
	if gate.floor_number != floor_number:
		return "%s's teleport gate answers for floor %d" % [label, gate.floor_number]
	var marker := map.get_node_or_null("SpawnPoints/gate") as Node2D
	if marker == null:
		return "%s has no gate spawn" % label
	if marker.position.distance_to(gate.position) > TILE * 1.5:
		return "%s's gate spawn is not in front of its gate" % label

	var base := gate.get_node("Solid/CollisionShape2D") as CollisionShape2D
	base.disabled = true
	map.refresh_solids()
	var without := _flood_standable(map, start)
	base.disabled = false
	map.refresh_solids()
	var with := _flood_standable(map, start)
	var arrival := walls.local_to_map(marker.position)
	if not with.has(arrival) or not map.is_standable(arrival):
		return "%s's gate spawn can't be stood on from the entrance" % label
	for cell: Vector2i in without:
		if not with.has(cell) and map.is_standable(cell):
			return "%s's teleport gate cuts off %d,%d" % [label, cell.x, cell.y]
	_teleport_gates += 1
	return ""


## A generated floor's camp stands round where you arrive, with its gate; has
## nothing of the floor's in it (the plot was carved by rule, so a chest or a
## monster there means the floor moved); its fire doesn't rest you; its people
## have something to say and can be walked up to; and it cuts nothing off -- every
## cell a body could walk to with the camp gone, it can walk to with it there, bar
## the cells the camp stands in. Nothing of the camp stands against anything solid
## but its own plot's rock, so it narrows no corridor either.
func _audit_camp(map: GameMap, walls: TileMapLayer, start: Vector2i, floor_number: int) -> String:
	var label := "floor %d" % floor_number
	if not map.has_meta(&"camp"):
		return "%s has no camp" % label
	var plot: Rect2i = map.get_meta(&"camp")
	if not plot.has_point(start):
		return "%s's camp is not where you arrive" % label
	var gate := map.get_node_or_null("TeleportGate") as Node2D
	if gate == null or not plot.has_point(walls.local_to_map(gate.position)):
		return "%s's teleport gate is not in its camp" % label
	if plot.intersects(map.get_meta(&"labyrinth", Rect2i())):
		return "%s's camp runs into the labyrinth" % label
	if not walls.get_used_rect().grow(-1).encloses(plot):
		return "%s's camp runs into the outer wall" % label
	if map.landmarks.get("Village" if map.has_meta(&"village") else "Camp", Rect2i()) != plot:
		return "%s's camp is not named on the map" % label

	var fire := map.get_node_or_null("Cookfire") as Campfire
	var campers: Array[Npc] = []
	# A village's settlers stand in the camp too, and are held to what campers are.
	var settlers: Array[Npc] = []
	# And its trader, solid like them, with a counter rather than a conversation.
	var traders: Array[Npc] = []
	for child in map.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if (node is Chest or node is Monster) and plot.has_point(walls.local_to_map(node.position)):
			return "%s has %s in its camp" % [label, node.name]
		if node is Npc and String(node.name).begins_with("Camper"):
			campers.append(node)
		if node is Npc and String(node.name).begins_with("Settler"):
			settlers.append(node)
		if node is Npc and node.name == &"Trader":
			traders.append(node)
	if fire != null and fire.rests:
		return "%s's cookfire rests you" % label
	# The plot was carved whole, so anything on the walls in it is a tent's or a
	# house's footprint.
	var tent_cells: Array[Vector2i] = []
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			var cell := Vector2i(x, y)
			if walls.get_cell_source_id(cell) != -1:
				tent_cells.append(cell)

	# Everything solid the camp put down, gone and back.
	var shapes: Array[CollisionShape2D] = []
	for node: Node2D in ([fire] if fire != null else []) + campers + settlers + traders:
		shapes.append(node.get_node("Solid/CollisionShape2D") as CollisionShape2D)
	var atlas: Array[Vector2i] = []
	for cell in tent_cells:
		atlas.append(walls.get_cell_atlas_coords(cell))
		walls.erase_cell(cell)
	for shape in shapes:
		shape.disabled = true
	map.refresh_solids()
	var without := _flood_standable(map, start)
	for i in tent_cells.size():
		walls.set_cell(tent_cells[i], 0, atlas[i])
	for shape in shapes:
		shape.disabled = false
	map.refresh_solids()
	var with := _flood_standable(map, start)
	var stands: Dictionary[Vector2i, bool] = {}
	for cell in tent_cells:
		stands[cell] = true
	for cell: Vector2i in without:
		if not with.has(cell) and map.is_standable(cell):
			return "%s's camp cuts off %d,%d" % [label, cell.x, cell.y]
		if not map.is_standable(cell) and not stands.has(cell):
			stands[cell] = true
	# Beside anything the camp stands in: floor, more of the same thing, or rock
	# beyond the plot -- never a squeeze between two solid things inside it.
	for cell: Vector2i in stands:
		if not plot.has_point(cell):
			continue
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if stands.has(next) or map.is_standable(next) or not plot.has_point(next):
				continue
			return "%s's camp has something solid against %d,%d" % [label, next.x, next.y]

	for camper in campers + settlers:
		var at := walls.local_to_map(camper.position)
		if not plot.has_point(at):
			return "%s's %s stands outside the camp" % [label, camper.name]
		var talk := camper.dialogue
		if talk == null or talk.entry_index() < 0 or talk.default_speaker.is_empty():
			return "%s's %s has nothing to say" % [label, camper.name]
		for line in talk.lines:
			if line.text.is_empty() or "{" in line.text:
				return "%s's %s says \"%s\"" % [label, camper.name, line.text]
		var reached := false
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			reached = reached or with.has(at + step)
		if not reached:
			return "%s's %s can't be walked up to" % [label, camper.name]
	var biome := FloorRegistry.get_floor(floor_number).biome
	for trader in traders:
		var at := walls.local_to_map(trader.position)
		if not map.has_meta(&"village"):
			return "%s has a trader before it has settled" % label
		if not plot.has_point(at):
			return "%s's trader stands outside the camp" % label
		var counter := ShopLibrary.village_shop(biome.id)
		if trader.shop == null or counter == null or trader.shop.id != counter.id \
				or trader.shop.wares != counter.wares:
			return "%s's trader doesn't keep the %s villages' counter" % [label, biome.id]
		if trader.shop.keeper.is_empty() or trader.shop.keeper != trader.display_name:
			return "%s's trader is nobody" % label
		var reached := false
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			reached = reached or with.has(at + step)
		if not reached:
			return "%s's trader can't be walked up to" % label

	# A footprint with no tent or house drawn over it is an invisible wall -- and a
	# house drawn where nothing stands is one you walk through.
	var props := map.get_node_or_null("Props") as TileMapLayer
	var source := biome.tile_set.get_source(0) as TileSetAtlasSource
	var tents := 0
	var houses := 0
	var drawn: Dictionary[Vector2i, bool] = {}
	if props != null:
		for anchor in props.get_used_cells():
			var coords := props.get_cell_atlas_coords(anchor)
			if not (coords in biome.camp_tiles or coords in biome.village_tiles):
				continue
			if coords in biome.camp_tiles:
				tents += 1
			else:
				houses += 1
			var rect := MapDresser.footprint(anchor, source.get_tile_size_in_atlas(coords))
			for y in range(rect.position.y + 1, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					drawn[Vector2i(x, y)] = true
	var planned: Array = map.get_meta(&"village", [])
	if houses != planned.size():
		return "%s's camp has %d houses drawn for %d planned" % [label, houses, planned.size()]
	if drawn.size() != tent_cells.size():
		return "%s's camp has %d cells of tent and house drawn over %d cells of footprint" % [
				label, drawn.size(), tent_cells.size()]
	for cell in tent_cells:
		if not drawn.has(cell):
			return "%s's camp has an invisible wall at %d,%d" % [label, cell.x, cell.y]

	if map.has_meta(&"village"):
		return ""
	_camps += 1
	if fire != null and tents >= FloorCamp.TENTS and campers.size() >= 2:
		_whole_camps += 1
	if plot.size == FloorCamp.PLOT:
		_full_plots += 1
	return ""


## A settled floor is the camp tier's floor with a village in its plot: nothing
## outside the plot moved -- no wall, chest, monster, door or puzzle piece -- the
## houses and settlers cut nothing off ([method _audit_camp] again, on this map),
## every settler offers the job [LocalQuests] says they have, and the lost player
## waits in a free dead end of the labyrinth with the conversation the job asks
## for. A fight can be staged round all of it.
func _audit_village(map: GameMap, camp_plot: Rect2i, unsettled: String, floor_number: int) -> String:
	var label := "settled floor %d" % floor_number
	_settling += 1
	var walls := map.get_node("Walls") as TileMapLayer
	var plot: Rect2i = map.get_meta(&"camp")
	if not map.has_meta(&"village") or plot != camp_plot:
		return "%s grows no village in its camp's plot" % label
	if _outside(map, plot) != unsettled:
		return "%s moved something outside its camp" % label
	var start: Vector2i = walls.local_to_map((map.get_node("SpawnPoints").get_child(0) as Node2D).position)
	var problem := _audit_camp(map, walls, start, floor_number)
	if not problem.is_empty():
		return problem.replace("floor %d" % floor_number, label)
	_villages += 1

	var jobs := LocalQuests.ids_for(floor_number)
	var settlers := 0
	for i in jobs.size():
		var settler := map.get_node_or_null("Settler%d" % i) as Npc
		if settler == null:
			continue
		settlers += 1
		var quest := QuestLibrary.get_quest(jobs[i])
		if quest == null or not settler.display_name.begins_with(quest.giver):
			return "%s's %s is not the giver of %s" % [label, settler.name, jobs[i]]
		var offers := false
		for line in settler.dialogue.lines:
			for choice in line.choices:
				for effect in choice.effects:
					offers = offers or (effect.kind == DialogueEffect.Kind.START_QUEST and effect.id == jobs[i])
		if not offers:
			return "%s's %s never offers %s" % [label, settler.name, jobs[i]]
	var houses: Array = map.get_meta(&"village")
	if not houses.is_empty() and settlers == jobs.size():
		_whole_villages += 1
	# Kept by someone nobody else on the floor is.
	var trader := map.get_node_or_null("Trader") as Npc
	if trader != null:
		for i in jobs.size():
			if LocalQuests.giver(jobs[i]).get("name", "") == trader.display_name:
				return "%s's trader is also %s's giver" % [label, jobs[i]]
		if LocalQuests.lost_person(floor_number).get("name", "") == trader.display_name:
			return "%s's trader is the player lost in its labyrinth" % label
		_traders += 1
	if houses.size() >= FloorCamp.MIN_HOUSES:
		_streets += 1

	var job := LocalQuests.talk_quest(floor_number)
	if not jobs.has(job):
		return ""
	_lost_jobs += 1
	var lost := map.get_node_or_null("LostPlayer") as Npc
	if lost == null:
		return "%s's lost player is nowhere" % label
	var at := walls.local_to_map(lost.position)
	var lab: Rect2i = map.get_meta(&"labyrinth")
	if not lab.has_point(at) or at != map.get_meta(&"lost_player", Vector2i(-1, -1)):
		return "%s's lost player is not in the labyrinth" % label
	var talk: StringName = QuestLibrary.get_quest(job).objectives[0].target
	if lost.dialogue == null or lost.dialogue.id != talk or lost.hidden_until != QuestLog.flag_for(job, "started"):
		return "%s's lost player is not the one their job asks for" % label
	for child in map.get_children():
		if child is Chest and walls.local_to_map((child as Chest).trap_target) == at:
			return "%s teleports you onto its lost player" % label
	# In a dead end: one way out of the passage it stands in, and the rest of the
	# passage still reachable round it.
	map.refresh_solids()
	var standing := _flood_standable(map, start)
	var beside := 0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if standing.has(at + step):
			beside += 1
	if beside == 0:
		return "%s's lost player can't be walked up to" % label
	_lost_players += 1
	var reachable := _flood(walls, start)
	_audit_formations(map, walls, start, reachable, label,
			[plot.grow(2), Rect2i(at, Vector2i.ONE).grow(4)] as Array[Rect2i])
	return ""


## Everything on [param map] outside [param plot], as one string: the walls and
## where every node but the people stands.
func _outside(map: Node2D, plot: Rect2i) -> String:
	var walls := map.get_node("Walls") as TileMapLayer
	var parts := PackedStringArray()
	for cell in walls.get_used_cells():
		if not plot.has_point(cell):
			parts.append("%s=%s" % [cell, walls.get_cell_atlas_coords(cell)])
	for child in map.get_children():
		var node := child as Node2D
		# People are the village's to change: the campers leave, settlers arrive.
		if node == null or node is TileMapLayer or node is Npc:
			continue
		var script := node.get_script() as Script
		parts.append("%s@%s" % [script.get_global_name() if script else node.get_class(), node.position])
	parts.sort()
	return ",".join(parts)


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


## A floor with a modifier against the same floor without one (see [FloorModifier]),
## level by level: everything the floor puts down where it was, and on top only what
## the modifier adds -- [method FloorTuning.infested_count] more monsters, or the
## storm's weather, tint and late noticing. Empty if so.
func _audit_modifier(floor_number: int) -> String:
	var kind := FloorRegistry.modifier_of(floor_number)
	var weather := FloorModifier.weather_for(FloorRegistry.biome_id(floor_number)) \
			if kind == FloorModifier.Kind.STORM else &""
	var title := FloorModifier.title(kind, weather)
	var label := "floor %d (%s)" % [floor_number, title]
	var swarm := 0
	for level in range(1, FloorRegistry.levels_of(floor_number) + 1):
		var with := FloorRegistry.build_floor(floor_number, level) as GameMap
		FloorGenerator.modifier_override = FloorModifier.Kind.NONE
		var without := FloorRegistry.build_floor(floor_number, level) as GameMap
		FloorGenerator.modifier_override = -1
		var problem := ""
		var storm := with.get_node_or_null("Weather") as Weather
		if _plain_signature(with) != _plain_signature(without):
			problem = "%s level %d moved what the floor put down" % [label, level]
		elif with.modifier != kind or not with.region.ends_with(" - " + title):
			problem = "%s level %d is not named for it (%s)" % [label, level, with.region]
		elif kind == FloorModifier.Kind.STORM and (storm == null or storm.kind != weather
				or with.weather != weather or with.notice_scale != FloorTuning.STORM_NOTICE
				or not with.modulate.is_equal_approx(without.modulate * Weather.tint(weather))):
			problem = "%s level %d has no storm over it" % [label, level]
		elif kind != FloorModifier.Kind.STORM and (storm != null or with.notice_scale != 1.0):
			problem = "%s level %d has a storm it shouldn't" % [label, level]
		elif level == 1 and with.get_node_or_null("Camper0") is Npc \
				and not _says(with.get_node("Camper0") as Npc, FloorModifier.camp_line(kind, weather)):
			problem = "%s's scout says nothing about it" % label
		for child in with.get_children():
			if child is Monster and String(child.name).begins_with("Swarm"):
				swarm += 1
		with.free()
		without.free()
		if not problem.is_empty():
			return problem
	var wanted := FloorTuning.infested_count(floor_number) if kind == FloorModifier.Kind.INFESTED else 0
	if swarm != wanted:
		return "%s carries %d monsters more, not %d" % [label, swarm, wanted]
	return ""


## A floor's event ([FloorEvents]) against the same floor without one: everything
## the floor puts down where it was, and on top only the event -- and the event
## itself sound. Empty if so. A floor whose event found no room is the plain floor.
func _audit_event(floor_number: int) -> String:
	var kind := FloorRegistry.event_of(floor_number)
	var label := "floor %d (%s)" % [floor_number, FloorEvents.KIND_NAMES[kind]]
	# Without the landmark or the rooms' shapes, both: they are planned round the
	# event's room.
	FloorGenerator.landmark_override = FloorLandmarks.Kind.NONE
	FloorGenerator.with_room_shapes = false
	var with := FloorRegistry.build_floor(floor_number) as GameMap
	FloorGenerator.event_override = FloorEvents.Kind.NONE
	var without := FloorRegistry.build_floor(floor_number) as GameMap
	FloorGenerator.event_override = -1
	FloorGenerator.landmark_override = -1
	FloorGenerator.with_room_shapes = true
	_events[kind] = _events.get(kind, 0) + 1
	var carved: Rect2i = with.get_meta(&"hoard", Rect2i())
	if carved.has_area():
		carved = carved.merge(with.get_meta(&"hoard_door"))
	var problem := ""
	if _event_signature(with, carved) != _event_signature(without, carved):
		problem = "%s moved what the floor put down" % label
	elif with.has_meta(&"event"):
		problem = _event_problem(with, kind, floor_number, label)
		if problem.is_empty():
			_whole_events[kind] = _whole_events.get(kind, 0) + 1
	with.free()
	without.free()
	return problem


## A floor's landmark ([FloorLandmarks]) against the same floor without one:
## everything the floor puts down where it was, dressed the same outside the room the
## landmark takes, and on top only the landmark -- and the landmark sound. Empty if
## so. A floor whose landmark found no room is the plain floor.
func _audit_landmark(floor_number: int) -> String:
	# Without the rooms' shapes, both: they are planned round the landmark's room.
	FloorGenerator.with_room_shapes = false
	var with := FloorRegistry.build_floor(floor_number) as GameMap
	FloorGenerator.landmark_override = FloorLandmarks.Kind.NONE
	var without := FloorRegistry.build_floor(floor_number) as GameMap
	FloorGenerator.landmark_override = -1
	FloorGenerator.with_room_shapes = true
	var kind: int = with.get_meta(&"landmark", FloorLandmarks.Kind.NONE)
	var room: Rect2i = with.get_meta(&"landmark_room", Rect2i())
	var label := "floor %d (%s)" % [floor_number, FloorLandmarks.KIND_NAMES[kind]]
	var problem := ""
	if _landmark_signature(with, room) != _landmark_signature(without, room):
		problem = "%s moved what the floor put down" % label
	elif kind != FloorLandmarks.Kind.NONE:
		problem = _landmark_problem(with, without, kind, floor_number, label)
		if problem.is_empty():
			_landmarks[kind] = _landmarks.get(kind, 0) + 1
			if with.has_meta(&"landmark_chest"):
				_landmark_chests += 1
	with.free()
	without.free()
	return problem


## A floor with its rooms shaped ([RoomShapes]) against the same floor without, level
## by level: every node where it was -- a monster that stood on the new rock stepped
## to the floor of its room -- the map's settings the same, every cell solid where it
## was and solid now only in a room it shaped, and the rock it put back and the floor
## beside it each two thick. Empty if so.
func _audit_room_shapes(floor_number: int) -> String:
	for level in range(1, FloorRegistry.levels_of(floor_number) + 1):
		var with := FloorRegistry.build_floor(floor_number, level) as GameMap
		FloorGenerator.with_room_shapes = false
		var without := FloorRegistry.build_floor(floor_number, level) as GameMap
		FloorGenerator.with_room_shapes = true
		var problem := _room_shape_problem(with, without, "floor %d level %d" % [floor_number, level])
		with.free()
		without.free()
		if not problem.is_empty():
			return problem
	return ""


func _room_shape_problem(with: GameMap, without: GameMap, label: String) -> String:
	var shaped: Dictionary = with.get_meta(&"room_shapes", {})
	var rock: Dictionary = with.get_meta(&"room_rock", {})
	if without.has_meta(&"room_shapes"):
		return "%s has shapes with them off" % label
	var walls := with.get_node("Walls") as TileMapLayer
	var plain := without.get_node("Walls") as TileMapLayer
	var in_shaped := func(cell: Vector2i) -> bool:
		return shaped.keys().any(func(room: Rect2i) -> bool: return room.has_point(cell))
	for cell in walls.get_used_cells():
		if plain.get_cell_source_id(cell) == -1 and not rock.has(cell):
			return "%s is solid at %s, which no shape put back" % [label, cell]
	for cell in plain.get_used_cells():
		if walls.get_cell_source_id(cell) == -1:
			return "%s opened %s" % [label, cell]
	for cell: Vector2i in rock:
		if walls.get_cell_source_id(cell) == -1 or not in_shaped.call(cell):
			return "%s's rock at %s is not solid in a room it shaped" % [label, cell]
	if not shaped.is_empty() and rock.is_empty():
		return "%s names shaped rooms but put no rock back" % label
	# Floor, for whether it is two wide: open, or a boulder or a pool left in a room.
	var floorish := func(cell: Vector2i) -> bool:
		if rock.has(cell):
			return false
		return walls.get_cell_source_id(cell) == -1 or in_shaped.call(cell)
	for room: Rect2i in shaped:
		var kind: int = shaped[room]
		_room_shapes[kind] = _room_shapes.get(kind, 0) + 1
		var near := room.grow(1)
		for y in range(near.position.y, near.end.y):
			for x in range(near.position.x, near.end.x):
				var cell := Vector2i(x, y)
				if rock.has(cell) and not _two_thick(cell, func(at: Vector2i) -> bool:
						return walls.get_cell_source_id(at) != -1):
					return "%s's %s at %s has a sliver of rock at %s" % [label,
							RoomShapes.KIND_NAMES[kind], room, cell]
				var beside := false
				for step: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
						Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
					beside = beside or rock.has(cell + step)
				if beside and floorish.call(cell) and not _two_thick(cell, floorish):
					return "%s's %s at %s has a sliver of floor at %s" % [label,
							RoomShapes.KIND_NAMES[kind], room, cell]
	# Everything else where it was; monsters stepped off the rock, onto open floor,
	# in the room they stood in.
	var parts := PackedStringArray()
	var plain_parts := PackedStringArray()
	for pair: Array in [[with, parts], [without, plain_parts]]:
		for child in (pair[0] as Node).get_children():
			if child is TileMapLayer or child is Monster:
				continue
			var line := "%s %s" % [child.name, child.get_class()]
			if child is Node2D:
				line += " %s" % (child as Node2D).position
			(pair[1] as PackedStringArray).append(line)
	if parts != plain_parts:
		return "%s moved something other than a monster" % label
	for child in without.get_children():
		if not child is Monster:
			continue
		var twin := with.get_node_or_null(NodePath(child.name)) as Monster
		if twin == null or twin.enemy != (child as Monster).enemy:
			return "%s lost or changed %s" % [label, child.name]
		if twin.position == (child as Node2D).position:
			continue
		var was := Vector2i((child as Node2D).position / TILE)
		var now := Vector2i(twin.position / TILE)
		if not rock.has(was) or walls.get_cell_source_id(now) != -1 \
				or not shaped.keys().any(func(room: Rect2i) -> bool: return room.has_point(was)):
			return "%s moved %s from %s to %s" % [label, child.name, was, now]
		_stepped_monsters += 1
	for meta in without.get_meta_list():
		if without.get_meta(meta) != with.get_meta(meta, null):
			return "%s changed its %s" % [label, meta]
	return ""


## Whether [param cell] is in a 2x2 of cells [param kind] says yes to.
func _two_thick(cell: Vector2i, kind: Callable) -> bool:
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var whole := true
		for y in 2:
			for x in 2:
				whole = whole and kind.call(cell + corner + Vector2i(x, y))
		if whole:
			return true
	return false


## What a landmark's floor shares with the plain one: every tile of every layer,
## exactly, outside [param room] and the cell round it (a paved square's edge is
## re-picked against it); every node bar the landmark's and the monsters, where it
## stands; the map's settings bar the landmark's name. Which monsters stand where is
## [method _landmark_problem]'s.
func _landmark_signature(map: GameMap, room: Rect2i) -> String:
	var parts := PackedStringArray()
	var near := room.grow(1)
	for layer_name in ["Ground", "Walls", MapDresser.PROPS, MapDresser.DECOR]:
		var layer := map.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		var cells := PackedStringArray()
		for cell in layer.get_used_cells():
			if not near.has_point(cell):
				cells.append("%s=%s" % [cell, layer.get_cell_atlas_coords(cell)])
		cells.sort()
		parts.append(",".join(cells))
	for child in map.get_children():
		if child is Landmark or child.name == "ChestLandmark" or child is Monster:
			continue
		var line := "%s %s" % [child.name, child.get_class()]
		if child is Node2D:
			line += " %s" % (child as Node2D).position
		parts.append(line)
	var places := map.landmarks.duplicate()
	for place: String in map.landmarks:
		if map.landmarks[place] == room and room.has_area():
			places.erase(place)
	parts.append("%s %s %s %s %s" % [map.map_id, map.dark_area, places, map.safe_zones, map.lit_areas])
	for meta in map.get_meta_list():
		if not String(meta).begins_with("landmark"):
			parts.append("%s=%s" % [meta, map.get_meta(meta)])
	return "\n".join(parts)


func _landmark_problem(map: GameMap, plain: GameMap, kind: int, floor_number: int,
		label: String) -> String:
	var landmark := map.get_node_or_null("Landmark") as Landmark
	var room: Rect2i = map.get_meta(&"landmark_room")
	if landmark == null or landmark.kind != kind:
		return "%s has no landmark standing" % label
	if not kind in FloorLandmarks.kinds_for(FloorRegistry.biome_id(floor_number)):
		return "%s is a kind its band doesn't draw" % label
	if not map.landmarks.values().has(room):
		return "%s isn't named on the map" % label
	if landmark.lines.is_empty() or landmark.display_name.is_empty() \
			or Array(landmark.lines).any(func(line: String) -> bool: return "{" in line or line.is_empty()):
		return "%s has nothing to read (%s)" % [label, landmark.lines]
	var plot: Rect2i = map.get_meta(&"camp")
	if room.intersects(plot) or map.safe_zones.any(func(zone: Rect2i) -> bool: return zone.intersects(room)):
		return "%s stands in the camp or a safe zone" % label
	var walls := map.get_node("Walls") as TileMapLayer
	var cells: Array[Vector2i] = []
	cells.assign(map.get_meta(&"landmark_cells"))
	for cell in cells:
		if walls.get_cell_source_id(cell) == -1 or not room.has_point(cell):
			return "%s's %s isn't solid in its room" % [label, cell]
	if kind == FloorLandmarks.Kind.LAKE:
		var water := 0
		for cell in cells:
			if map.is_water(cell):
				water += 1
		if water < FloorLandmarks.LAKE_LEAST.x * FloorLandmarks.LAKE_LEAST.y - 4:
			return "%s is a puddle (%d cells of water)" % [label, water]
	# Nothing cut off: what the plain floor reaches, this one does, bar its own cells.
	var start: Vector2i = walls.local_to_map((map.get_node("SpawnPoints").get_child(0) as Node2D).position)
	var reached := _flood(walls, start)
	var chest_at: Vector2i = map.get_meta(&"landmark_chest", Vector2i(-1, -1))
	for cell: Vector2i in _flood(plain.get_node("Walls") as TileMapLayer, start):
		if not reached.has(cell) and not cell in cells and cell != chest_at:
			return "%s cuts %s off" % [label, cell]
	if chest_at.x >= 0:
		var chest := map.get_node_or_null("ChestLandmark") as Chest
		if chest == null or walls.local_to_map(chest.position) != chest_at \
				or chest.opened_flag != FloorLandmarks.chest_flag(floor_number) or chest.gilded or chest.sealed:
			return "%s's chest isn't a plain chest where it says" % label
		if not reached.has(chest_at):
			return "%s's chest can't be walked up to" % label
	# It can be read from somewhere you can stand.
	var at := walls.local_to_map(landmark.position - Vector2(0, 4))
	var readable := false
	for y in range(-1, 2):
		for x in range(-1, 2):
			var beside := at + Vector2i(x, y)
			readable = readable or (reached.has(beside) and walls.get_cell_source_id(beside) == -1)
	if not readable:
		return "%s can't be walked up to" % label
	# Its monsters are the plain floor's, moved off it where they stood on it.
	for child in plain.get_children():
		if not child is Monster:
			continue
		var twin := map.get_node_or_null(NodePath(child.name)) as Monster
		if twin == null or twin.enemy != (child as Monster).enemy:
			return "%s lost %s" % [label, child.name]
		var cell := walls.local_to_map(twin.position)
		if cell in cells or cell == chest_at:
			return "%s's %s stands in it" % [label, child.name]
		if twin.position != (child as Node2D).position and not room.grow(1).has_point(cell):
			return "%s's %s was moved out of its room" % [label, child.name]
	# Someone in the camp says so.
	var opening: String = (FloorLandmarks.CAMP_LINES[kind] as String).get_slice("{", 0)
	var told := false
	var campers := 0
	for child in map.get_children():
		if child is Npc and String(child.name).begins_with("Camper"):
			campers += 1
			told = told or (child as Npc).dialogue.lines.any(func(line: DialogueLine) -> bool:
				return line.text.begins_with(opening) and not "{" in line.text)
	if campers > 0 and not told:
		return "%s's camp says nothing about it" % label
	return ""


## What an event's floor shares with the plain one: where every cell is wall or
## floor -- bar [param carved], the hoard -- and every node bar the event's, where
## it stands. Dressing may differ round a hoard; collision may not.
func _event_signature(map: GameMap, carved: Rect2i) -> String:
	var parts := PackedStringArray()
	for layer_name in ["Ground", "Walls"]:
		var cells := PackedStringArray()
		for cell in (map.get_node(layer_name) as TileMapLayer).get_used_cells():
			if not carved.has_point(cell):
				cells.append("%d,%d" % [cell.x, cell.y])
		cells.sort()
		parts.append(",".join(cells))
	var event_nodes := ["FieldBoss", "HoardSeal", "ChestHoard", "Stranded", "Ambush", "Duellist"]
	for child in map.get_children():
		if child.name in event_nodes or String(child.name).begins_with("Besieger"):
			continue
		var line := "%s %s" % [child.name, child.get_class()]
		if child is Node2D:
			line += " %s" % (child as Node2D).position
		if child is Monster:
			line += " %s %d" % [(child as Monster).enemy.id, (child as Monster).level]
		parts.append(line)
	var places := map.landmarks.duplicate()
	places.erase("The Hoard")
	parts.append("%s %s %s %s %s" % [map.map_id, map.dark_area, places, map.safe_zones, map.lit_areas])
	for meta in map.get_meta_list():
		if not meta in [&"event", &"hoard", &"hoard_door", &"stranded", &"ambush", &"duellist"]:
			parts.append("%s=%s" % [meta, map.get_meta(meta)])
	return "\n".join(parts)


func _event_problem(map: GameMap, kind: int, floor_number: int, label: String) -> String:
	var walls := map.get_node("Walls") as TileMapLayer
	var start: Vector2i = walls.local_to_map((map.get_node("SpawnPoints").get_child(0) as Node2D).position)
	var reachable := _flood(walls, start)
	var plot: Rect2i = map.get_meta(&"camp")
	var veteran := map.get_node_or_null("Camper1") as Npc
	var opening: String = (FloorEvents.CAMP_LINES[kind] as String).get_slice("{", 0)
	if veteran != null and not veteran.dialogue.lines.any(func(line: DialogueLine) -> bool:
			return line.text.begins_with(opening) and not "{" in line.text):
		return "%s's camp says nothing about it" % label
	map.refresh_solids()
	var walkable := _flood_standable(map, start)
	match kind:
		FloorEvents.Kind.FIELD_BOSS:
			var seal := map.get_node_or_null("HoardSeal") as SealedDoor
			var keeper := map.get_node_or_null("FieldBoss") as Monster
			var chest := map.get_node_or_null("ChestHoard") as Chest
			if seal == null or keeper == null or chest == null:
				return "%s has no hoard, keeper or chest" % label
			if seal.sigils != ([keeper.defeat_flag] as Array[StringName]) or not seal.opens_itself \
					or not keeper.boss or keeper.level != FloorTuning.field_boss_level(floor_number):
				return "%s's hoard is not keyed to a boss's fall" % label
			var hoard: Rect2i = map.get_meta(&"hoard")
			var door: Rect2i = map.get_meta(&"hoard_door")
			var at := walls.local_to_map(chest.position)
			if not hoard.has_point(at) or not reachable.has(at) or not chest.sealed:
				return "%s's hoard chest is not a sealed chest in it" % label
			if _flood_except(walls, start, door).has(at):
				return "%s's hoard can be got into round its door" % label
			if walkable.has(at):
				return "%s's hoard can be walked into shut" % label
			if not walkable.has(walls.local_to_map(keeper.position)):
				return "%s's keeper stands where it can't be walked up to" % label
		FloorEvents.Kind.ESCORT:
			var stranded := map.get_node_or_null("Stranded") as Escortee
			var cell: Vector2i = map.get_meta(&"stranded")
			if stranded == null or walls.local_to_map(stranded.position) != cell:
				return "%s has nobody stranded" % label
			var home := false
			for y in range(plot.position.y, plot.end.y):
				for x in range(plot.position.x, plot.end.x):
					home = home or walkable.has(Vector2i(x, y))
			if not walkable.has(cell) or not home:
				return "%s's stranded player has no way home" % label
			if stranded.home != plot or stranded.dialogue == null:
				return "%s's stranded player doesn't know where home is" % label
			var quest := FloorEvents.build(FloorEvents.escort_quest(floor_number))
			if quest == null or not quest.objectives[0].target_is_valid() \
					or not FloorEvents.is_conversation(FloorEvents.escort_talk(floor_number)):
				return "%s's escort job names nothing" % label
			var besiegers := 0
			for child in map.get_children():
				if child is Monster and String(child.name).begins_with("Besieger"):
					besiegers += 1
					if not walkable.has(walls.local_to_map((child as Node2D).position)):
						return "%s's %s stands off the floor" % [label, child.name]
			if besiegers != FloorEvents.BESIEGERS:
				return "%s's stranded player has %d monsters round them" % [label, besiegers]
		FloorEvents.Kind.AMBUSH:
			var ambush := map.get_node_or_null("Ambush") as Ambush
			if ambush == null or ambush.area != map.get_meta(&"ambush"):
				return "%s has nobody in hiding" % label
			if ambush.area.intersects(plot) or map.safe_zones.any(func(zone: Rect2i) -> bool:
					return zone.intersects(ambush.area)):
				return "%s's ambush waits in the camp or a safe zone" % label
			var sides: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
			var staged := 0
			for y in range(ambush.area.position.y, ambush.area.end.y):
				for x in range(ambush.area.position.x, ambush.area.end.x):
					var cell := Vector2i(x, y)
					if not walkable.has(cell):
						continue
					_ambush_cells += 1
					var field := map.formation(cell, sides[posmod(x + y, 4)], 2)
					if field != null and field.enemy_cells.size() == 2 \
							and field.enemy_cells.all(func(at: Vector2i) -> bool: return walkable.has(at)):
						staged += 1
			_ambush_staged += staged
			if staged == 0:
				return "%s's ambush can spring nowhere" % label
		FloorEvents.Kind.DUEL:
			var duellist := map.get_node_or_null("Duellist") as Duellist
			if duellist == null or duellist.dialogue == null:
				return "%s has no duellist" % label
			var cell := walls.local_to_map(duellist.position)
			if not plot.has_point(cell) or cell != map.get_meta(&"duellist") or not walkable.has(cell):
				return "%s's duellist doesn't stand in the camp" % label
			# Walked up to from any side, they can stake out a duel where you stand.
			var sides := 0
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var at := cell + step
				if not walkable.has(at):
					continue
				sides += 1
				var field := map.formation(at, -step, 1)
				if field == null or field.enemy_cells.size() != 1 or not walkable.has(field.enemy_cells[0]):
					return "%s's duel can't be staged from %s" % [label, at]
			if sides == 0:
				return "%s's duellist can't be walked up to" % label
			_duel_sides += sides
	return ""


## Everything on [param map] but what a modifier adds or changes: its tiles, every
## node but the swarm and the weather where it stands, and the map's own settings
## bar its tint and its region.
func _plain_signature(map: GameMap) -> String:
	var parts := PackedStringArray()
	for layer_name in ["Ground", "Walls", MapDresser.PROPS, MapDresser.DECOR]:
		parts.append(_layer_signature(map, layer_name))
	for child in map.get_children():
		if String(child.name).begins_with("Swarm") or child is Weather:
			continue
		var line := "%s %s" % [child.name, child.get_class()]
		if child is Node2D:
			line += " %s" % (child as Node2D).position
		if child is Monster:
			line += " %s %d" % [(child as Monster).enemy.id, (child as Monster).level]
		parts.append(line)
	parts.append("%s %s %s %s %s" % [map.map_id, map.dark_area, map.landmarks, map.safe_zones, map.lit_areas])
	for meta in map.get_meta_list():
		if meta != &"modifier":
			parts.append("%s=%s" % [meta, map.get_meta(meta)])
	return "\n".join(parts)


## Whether [param npc]'s conversation has a line saying [param text].
func _says(npc: Npc, text: String) -> bool:
	if npc.dialogue == null:
		return false
	for line in npc.dialogue.lines:
		if line.text == text:
			return true
	return false


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


## How many pixels of [param biome]'s row-0 [param slot] are not see-through.
func _opaque_pixels(biome: BiomeKit, slot: int) -> int:
	var source := biome.tile_set.get_source(0) as TileSetAtlasSource
	var region := source.get_tile_texture_region(Vector2i(slot, 0))
	var image := source.texture.get_image().get_region(region)
	image.convert(Image.FORMAT_RGBA8)
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	return opaque


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
