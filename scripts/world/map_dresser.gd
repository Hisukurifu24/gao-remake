class_name MapDresser
extends RefCounted
## Dresses a finished layout: joins the ground, the water and the wall mass, and
## scatters the small things that make a map look lived in.
##
## It is a pass over a finished layout, never a step in building one. Carving,
## decor that blocks and the reachability check all happen first, against plain
## slot tiles, so no layout can depend on which tile a cell ended up drawing.
## [FloorGenerator] and the authored-floor tools call [method dress] at the same
## point, which is why a generated floor and a built one cannot drift apart in how
## they look.
##
## Everything it adds is visual. Walls keeps every collision it had and gains none;
## the canopy and the decor live on their own layers with collision off, so the
## floor test's flood fill -- which only ever reads Walls -- cannot tell it ran.
##
## Deterministic: every choice comes from [param dress_seed] or the cell itself,
## never the global RNG.

const SOURCE_ID := 0
## Things that stand up off the ground -- trees, bushes, houses. Y-sorted with the
## player, so you can walk behind a canopy or a roof.
const PROPS := "Props"
## Flat scatter -- flowers, tufts, twigs. Under everything that stands.
const DECOR := "Decor"
## What a see-through wall mass shows: the biome's backdrop, under everything.
const BACKDROP := "Backdrop"

## A cell's eight neighbours in the order its zones are read: the four sides, then
## the four corners, each corner after the two sides it sits between.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
## The TileSet peering bit for each entry of [constant NEIGHBOURS].
const PEERING_BITS: Array[int] = [
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
]
## For corners 4..7 of [constant NEIGHBOURS], the indices of the two sides beside it.
const CORNER_SIDES := [[0, 1], [2, 1], [2, 3], [0, 3]]
## A wrong side shows as a hard seam; a wrong corner as a notch.
const SIDE_WEIGHT := 4
const CORNER_WEIGHT := 1


static func dress(map: Node2D, biome: BiomeKit, ground: TileMapLayer, walls: TileMapLayer,
		dress_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = dress_seed
	map.y_sort_enabled = true
	ground.z_index = -2
	walls.z_index = -2

	if biome.ground_terrain_set >= 0:
		join_ground(biome, ground)
	if biome.liquid_terrain_set >= 0:
		join_liquid(biome, walls)
	if biome.wall_style == BiomeKit.WallStyle.TREES:
		plant_trees(props_layer(map, biome), biome, walls, rng)
	else:
		join_blob(biome, walls)
	if not biome.decor_tiles.is_empty():
		scatter_decor(_layer(map, biome, DECOR, false), biome, ground, walls, rng)
	if biome.backdrop != null:
		add_backdrop(map, biome)


## The biome's backdrop, repeating behind the whole map and scrolling slower than it.
static func add_backdrop(map: Node2D, biome: BiomeKit) -> Parallax2D:
	var parallax := map.get_node_or_null(BACKDROP) as Parallax2D
	if parallax != null:
		return parallax
	parallax = Parallax2D.new()
	parallax.name = BACKDROP
	parallax.z_index = -3
	parallax.scroll_scale = biome.backdrop_scroll
	parallax.autoscroll = biome.backdrop_drift
	parallax.repeat_size = biome.backdrop.get_size()
	var sprite := Sprite2D.new()
	sprite.texture = biome.backdrop
	sprite.centered = false
	parallax.add_child(sprite)
	map.add_child(parallax)
	map.move_child(parallax, 0)
	parallax.owner = map
	sprite.owner = map
	return parallax


## The layer standing props go on, created on first use. Authored tools place
## houses on it after [method dress] has planted the forest.
static func props_layer(map: Node2D, biome: BiomeKit) -> TileMapLayer:
	return _layer(map, biome, PROPS, true)


## The cells a standing tile covers when placed at [param anchor]: its bottom row,
## centred, an even width nudged half a cell right. The inverse of how
## tools/build_biomes.gd sets a standing tile's texture origin; the two must agree.
static func footprint(anchor: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(anchor.x - (size.x - 1) / 2, anchor.y - (size.y - 1), size.x, size.y)


## Where to place a standing tile so it covers exactly [param rect].
static func anchor_for(rect: Rect2i) -> Vector2i:
	return Vector2i(rect.position.x + (rect.size.x - 1) / 2, rect.end.y - 1)


# --- the wall mass -----------------------------------------------------------

## Autotiles a BLOB wall mass. Only cells still holding the plain wall tile join:
## boulders and pools live on this layer too, and they are scenery rather than
## part of the mass, so the mass draws an edge against them.
static func join_blob(biome: BiomeKit, walls: TileMapLayer) -> void:
	if biome.wall_terrain_set < 0:
		return
	var cells := _wall_mass(biome, walls).keys()
	if cells.is_empty():
		return
	# ignore_empty_terrains must be false: a carved cell has no terrain, and it is
	# exactly those neighbours that an edge tile has to be chosen against.
	walls.set_cells_terrain_connect(cells, biome.wall_terrain_set, biome.wall_terrain, false)


## Stands a forest over a TREES wall mass. The mass itself is untouched -- it
## still draws the floor under the canopy and still collides -- and the trees go
## on the props layer, trunks on the mass, crowns hanging a row over whatever is
## north of it.
static func plant_trees(props: TileMapLayer, biome: BiomeKit, walls: TileMapLayer,
		rng: RandomNumberGenerator) -> void:
	if biome.tree_tiles.is_empty():
		return
	var mass := _wall_mass(biome, walls)
	var cells := _sorted(mass.keys())
	var covered := {}
	# A staggered lattice -- every other column, shifted a column each row -- packs
	# the crowns the way the pack's own forests are drawn.
	for cell: Vector2i in cells:
		if posmod(cell.x + cell.y, 2) == 0 and mass.has(cell + Vector2i.RIGHT):
			_plant(props, biome, cell, covered, rng)
	_fill_bare(props, biome, cells, mass, covered, rng)


## Whatever the lattice missed: a tree if there is room beside it, else a bush,
## so no edge of the mass is ever left showing bare floor. A tree whose crown
## would hang over a cell of [param keep] is a bush instead.
static func _fill_bare(props: TileMapLayer, biome: BiomeKit, cells: Array, mass: Dictionary,
		covered: Dictionary, rng: RandomNumberGenerator, keep := {}) -> void:
	for cell: Vector2i in cells:
		if covered.has(cell):
			continue
		if mass.has(cell + Vector2i.RIGHT) and not _overhangs(cell, keep):
			_plant(props, biome, cell, covered, rng)
		elif mass.has(cell + Vector2i.LEFT) and not _overhangs(cell + Vector2i.LEFT, keep):
			_plant(props, biome, cell + Vector2i.LEFT, covered, rng)
		else:
			props.set_cell(cell, SOURCE_ID, Vector2i(biome.obstacle_tile, 0))
			covered[cell] = true


static func _overhangs(anchor: Vector2i, keep: Dictionary) -> bool:
	if keep.is_empty():
		return false
	var rect := footprint(anchor, Vector2i(2, 2))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if keep.has(Vector2i(x, y)):
				return true
	return false


static func _plant(props: TileMapLayer, biome: BiomeKit, cell: Vector2i, covered: Dictionary,
		rng: RandomNumberGenerator) -> void:
	props.set_cell(cell, SOURCE_ID, biome.tree_tiles[rng.randi() % biome.tree_tiles.size()])
	var rect := footprint(cell, Vector2i(2, 2))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			covered[Vector2i(x, y)] = true


static func _wall_mass(biome: BiomeKit, walls: TileMapLayer) -> Dictionary:
	var wall_atlas := Vector2i(biome.wall_tile, 0)
	var mass := {}
	for cell in walls.get_used_cells():
		if walls.get_cell_atlas_coords(cell) == wall_atlas:
			mass[cell] = true
	return mass


# --- reshaping a dressed map ---------------------------------------------------

## Opens [param cells] in a map that has already been dressed -- a cracked wall
## broken while you watch -- and dresses round them as [method dress] would have
## had they been carved from the start: plain floor in them, the wall mass beside
## them drawing its new edges, a forest's trees stepping back from them. Nothing
## further off than the cells' own neighbours changes.
##
## Only for ground that was solid rock: no water, decor or path beside it, which
## is what a cracked wall's planner guarantees.
static func open_cells(map: Node2D, biome: BiomeKit, ground: TileMapLayer, walls: TileMapLayer,
		cells: Array[Vector2i]) -> void:
	var opened := {}
	for cell in cells:
		opened[cell] = true
		walls.erase_cell(cell)
	var near := _around(opened, 1)
	if biome.ground_terrain_set >= 0:
		# Grass is always drawn plain -- the pack draws every edge inside the dirt's
		# own cells -- so the new floor is plain grass and no path beside it changes.
		var dirt := {}
		for cell: Vector2i in near:
			var data := ground.get_cell_tile_data(cell)
			if data != null and data.terrain_set == biome.ground_terrain_set \
					and data.terrain == biome.ground_dirt:
				dirt[cell] = true
		var matcher := TerrainMatcher.new(biome.tile_set, biome.ground_terrain_set, biome.ground_dirt)
		for cell: Vector2i in _sorted(opened.keys()):
			var tile := matcher.pick(cell, dirt, biome.ground_grass)
			ground.set_cell(cell, SOURCE_ID, tile if tile.x >= 0 else Vector2i(biome.floor_tile, 0))
	else:
		for cell: Vector2i in opened:
			ground.set_cell(cell, SOURCE_ID, Vector2i(biome.floor_tile, 0))
	if biome.wall_style == BiomeKit.WallStyle.TREES:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_sorted(opened.keys())[0])
		step_trees_back(map, biome, walls, opened, rng)
	elif biome.wall_terrain_set >= 0:
		# Nearest match, not Godot's solver: the blob is a complete 47, so every
		# cell finds its exact tile, and nothing beyond the ring is touched.
		var mass := {}
		for cell: Vector2i in _around(opened, 2):
			var data := walls.get_cell_tile_data(cell)
			if data != null and data.terrain_set == biome.wall_terrain_set \
					and data.terrain == biome.wall_terrain:
				mass[cell] = true
		var matcher := TerrainMatcher.new(biome.tile_set, biome.wall_terrain_set, biome.wall_terrain)
		for cell: Vector2i in _sorted(near.keys()):
			if mass.has(cell):
				var tile := matcher.pick(cell, mass, biome.wall_terrain)
				if tile.x >= 0:
					walls.set_cell(cell, SOURCE_ID, tile)


## Lays something into a room of a map that has already been dressed -- a
## landmark ([FloorLandmarks]) -- and dresses round it as [method dress] would have:
## [param clear] taken off the walls (a room's boulders and pools), [param water]
## painted in the liquid slot, [param dirt] made path, [param solid] painted in the
## invisible [member BiomeKit.wall_alt_tile]; then only the water and ground within a
## cell of what changed re-picked by nearest match, and the flowers taken off
## anything now water, path or solid, and off [param bare] -- what is drawn over, or
## stood on. Nothing further off changes, so a floor with
## a landmark is dressed exactly as the floor without, outside its room.
##
## Never beside the wall mass: what it paints keeps a cell of floor between it and
## the rock, as a room's decor does, so no wall's edge changes.
static func lay_into(map: Node2D, biome: BiomeKit, ground: TileMapLayer, walls: TileMapLayer,
		clear: Array[Vector2i], water: Array[Vector2i], dirt: Array[Vector2i],
		solid: Array[Vector2i], bare: Array[Vector2i] = []) -> void:
	var changed := {}
	for cell in clear:
		walls.erase_cell(cell)
		changed[cell] = true
	for cell in water:
		walls.set_cell(cell, SOURCE_ID, Vector2i(biome.liquid_tile, 0))
		changed[cell] = true
	for cell in solid:
		walls.set_cell(cell, SOURCE_ID, Vector2i(biome.wall_alt_tile, 0))
	var near := _around(changed, 1)
	if biome.liquid_terrain_set >= 0:
		var pool := {}
		for cell: Vector2i in near:
			var data := walls.get_cell_tile_data(cell)
			if walls.get_cell_atlas_coords(cell) == Vector2i(biome.liquid_tile, 0) or (data != null
					and data.terrain_set == biome.liquid_terrain_set and data.terrain == biome.liquid_terrain):
				pool[cell] = true
		var matcher := TerrainMatcher.new(biome.tile_set, biome.liquid_terrain_set, biome.liquid_terrain)
		for cell: Vector2i in _sorted(pool.keys()):
			var tile := matcher.pick(cell, pool, biome.liquid_terrain)
			if tile.x >= 0:
				walls.set_cell(cell, SOURCE_ID, tile)
	var paved := {}
	for cell in dirt:
		paved[cell] = true
	if biome.ground_terrain_set >= 0:
		var near_dirt := _around(paved, 1)
		var path := paved.duplicate()
		for cell: Vector2i in _around(near_dirt, 1):
			var data := ground.get_cell_tile_data(cell)
			if data != null and data.terrain_set == biome.ground_terrain_set \
					and data.terrain == biome.ground_dirt:
				path[cell] = true
		var matcher := TerrainMatcher.new(biome.tile_set, biome.ground_terrain_set, biome.ground_dirt)
		for cell: Vector2i in _sorted(near_dirt.keys()):
			if ground.get_cell_source_id(cell) == -1:
				continue
			var tile := matcher.pick(cell, path, biome.ground_dirt if path.has(cell) else biome.ground_grass)
			if tile.x >= 0:
				ground.set_cell(cell, SOURCE_ID, tile)
	else:
		for cell: Vector2i in paved:
			ground.set_cell(cell, SOURCE_ID, Vector2i(biome.path_tile, 0))
	var decor := map.get_node_or_null(DECOR) as TileMapLayer
	if decor != null:
		for cell: Vector2i in water + dirt + solid + bare:
			decor.erase_cell(cell)


## Takes away every tree or bush standing on a cell of [param clear], and covers
## whatever of the forest's edge that leaves bare -- never [param clear] itself,
## which is either floor now or kept for something else to stand on.
static func step_trees_back(map: Node2D, biome: BiomeKit, walls: TileMapLayer, clear: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var props := map.get_node_or_null(PROPS) as TileMapLayer
	if props == null:
		return
	var source := props.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	var covered := {}
	for anchor in props.get_used_cells():
		var rect := footprint(anchor, source.get_tile_size_in_atlas(props.get_cell_atlas_coords(anchor)))
		var hits := false
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				hits = hits or clear.has(Vector2i(x, y))
		if hits:
			props.erase_cell(anchor)
			continue
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				covered[Vector2i(x, y)] = true
	var mass := _wall_mass(biome, walls)
	for cell: Vector2i in clear:
		mass.erase(cell)
	var bare: Array = []
	for cell: Vector2i in _sorted(_around(clear, 1).keys()):
		if mass.has(cell) and not covered.has(cell):
			bare.append(cell)
	_fill_bare(props, biome, bare, mass, covered, rng, clear)


## Every cell within [param reach] of one of [param cells], those included.
static func _around(cells: Dictionary, reach: int) -> Dictionary:
	var near := {}
	for cell: Vector2i in cells:
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				near[cell + Vector2i(x, y)] = true
	return near


# --- ground and water --------------------------------------------------------

## Joins grass and dirt. Path and special cells are dirt, everything else grass;
## every cell is repainted with the transition tile nearest its neighbourhood.
static func join_ground(biome: BiomeKit, ground: TileMapLayer) -> void:
	var dirt_slots := [Vector2i(biome.path_tile, 0), Vector2i(biome.special_tile, 0)]
	var cells := _sorted(ground.get_used_cells())
	var dirt := {}
	for cell: Vector2i in cells:
		if ground.get_cell_atlas_coords(cell) in dirt_slots:
			dirt[cell] = true
	var matcher := TerrainMatcher.new(biome.tile_set, biome.ground_terrain_set, biome.ground_dirt)
	for cell: Vector2i in cells:
		var centre := biome.ground_dirt if dirt.has(cell) else biome.ground_grass
		var tile := matcher.pick(cell, dirt, centre)
		if tile.x >= 0:
			ground.set_cell(cell, SOURCE_ID, tile)


## Joins pools into a shoreline. The shore is drawn inside the water's own cells,
## so the collision a pool had is exactly the collision it keeps.
static func join_liquid(biome: BiomeKit, walls: TileMapLayer) -> void:
	var liquid_atlas := Vector2i(biome.liquid_tile, 0)
	var water := {}
	for cell in walls.get_used_cells():
		if walls.get_cell_atlas_coords(cell) == liquid_atlas:
			water[cell] = true
	var matcher := TerrainMatcher.new(biome.tile_set, biome.liquid_terrain_set, biome.liquid_terrain)
	for cell: Vector2i in _sorted(water.keys()):
		var tile := matcher.pick(cell, water, biome.liquid_terrain)
		if tile.x >= 0:
			walls.set_cell(cell, SOURCE_ID, tile)


## Which of a cell's eight zones should show the terrain of [param members], as
## bits in [constant NEIGHBOURS] order.
static func expected_flags(cell: Vector2i, members: Dictionary) -> int:
	var inside := members.has(cell)
	var flags := 0
	for side in 4:
		if members.has(cell + NEIGHBOURS[side]):
			flags |= 1 << side
	for corner in 4:
		var index := 4 + corner
		var a: bool = (flags & (1 << CORNER_SIDES[corner][0])) != 0
		var b: bool = (flags & (1 << CORNER_SIDES[corner][1])) != 0
		var diagonal := members.has(cell + NEIGHBOURS[index])
		# Inside the terrain a corner is its own only when both sides beside it are
		# too; otherwise the edge along that side has already claimed it. Outside, a
		# corner shows the terrain when either side does -- or when only the diagonal
		# does, which is the inner-corner tile.
		var on := (a and b and diagonal) if inside else (a or b or diagonal)
		if on:
			flags |= 1 << index
	return flags


## A tile's zones that show terrain [param member], in the same bit layout.
static func tile_flags(data: TileData, member: int) -> int:
	var flags := 0
	for index in 8:
		if data.get_terrain_peering_bit(PEERING_BITS[index]) == member:
			flags |= 1 << index
	return flags


static func flag_distance(a: int, b: int) -> int:
	var diff := a ^ b
	var score := 0
	for index in 8:
		if diff & (1 << index):
			score += SIDE_WEIGHT if index < 4 else CORNER_WEIGHT
	return score


## Picks transition tiles by nearest match rather than through
## [method TileMapLayer.set_cells_terrain_connect], because the pack's sets are
## not complete 47s: Godot's solver treats a missing arrangement as a constraint to
## propagate into the neighbours, where this settles for the closest tile and
## leaves every other cell alone.
class TerrainMatcher:
	## centre terrain -> [[atlas coords, zone flags, probability], ...]
	var _tiles := {}

	func _init(tile_set: TileSet, terrain_set: int, member: int) -> void:
		var source := tile_set.get_source(MapDresser.SOURCE_ID) as TileSetAtlasSource
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if data.terrain_set != terrain_set or data.terrain < 0:
				continue
			if not _tiles.has(data.terrain):
				_tiles[data.terrain] = []
			_tiles[data.terrain].append([coords, MapDresser.tile_flags(data, member), data.probability])

	func pick(cell: Vector2i, members: Dictionary, centre: int) -> Vector2i:
		var want := MapDresser.expected_flags(cell, members)
		var best: Array = []
		var best_score := 1 << 20
		var total := 0.0
		for entry: Array in _tiles.get(centre, []):
			var score := MapDresser.flag_distance(want, entry[1])
			if score < best_score:
				best_score = score
				best = [entry]
				total = entry[2]
			elif score == best_score:
				best.append(entry)
				total += entry[2]
		if best.is_empty():
			return Vector2i(-1, -1)
		# Equal matches are variants of one tile. Chosen by the cell rather than an
		# rng, so repainting part of a map never reshuffles the rest of its grass.
		var roll := float(absi(hash(cell)) % 10007) / 10007.0 * total
		for entry: Array in best:
			roll -= entry[2]
			if roll <= 0.0:
				return entry[0]
		return best[best.size() - 1][0]


# --- decor -------------------------------------------------------------------

static func scatter_decor(decor: TileMapLayer, biome: BiomeKit, ground: TileMapLayer,
		walls: TileMapLayer, rng: RandomNumberGenerator) -> void:
	for cell: Vector2i in _sorted(ground.get_used_cells()):
		if walls.get_cell_source_id(cell) != -1:
			continue
		if biome.ground_terrain_set >= 0:
			var data := ground.get_cell_tile_data(cell)
			# Plain grass only: a flower on the lip of a path reads as a mistake.
			if data == null or data.terrain_set != biome.ground_terrain_set \
					or data.terrain != biome.ground_grass \
					or tile_flags(data, biome.ground_dirt) != 0:
				continue
		if rng.randf() < biome.decor_density:
			decor.set_cell(cell, SOURCE_ID, biome.decor_tiles[rng.randi() % biome.decor_tiles.size()])


# --- plumbing ----------------------------------------------------------------

static func _layer(map: Node2D, biome: BiomeKit, layer_name: String, y_sorted: bool) -> TileMapLayer:
	var layer := map.get_node_or_null(layer_name) as TileMapLayer
	if layer != null:
		return layer
	layer = TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = biome.tile_set
	layer.collision_enabled = false
	layer.y_sort_enabled = y_sorted
	layer.z_index = 0 if y_sorted else -1
	map.add_child(layer)
	layer.owner = map
	return layer


## Cells in reading order. Used-cell order is a hash map's, and a seeded rng only
## reproduces a floor if it is asked in the same order every time.
static func _sorted(cells: Array) -> Array:
	var copy := cells.duplicate()
	copy.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return copy
