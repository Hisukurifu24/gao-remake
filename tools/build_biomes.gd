extends SceneTree
## Builds a TileSet + BiomeKit for every biome: from the placeholder atlases, or
## cut from the Ninja Adventure pack for the biomes listed in PACK_BIOMES.
##
##     "$GODOT" --headless --path . --script res://tools/build_biomes.gd
##
## Run after tools/gen_placeholder_art.py. Safe to re-run: it only regenerates
## derived resources, never scenes.

const TILE := 16
const SOURCE_ID := 0

const TILESET_DIR := "res://resources/tilesets"
const BIOME_DIR := "res://resources/biomes"

# Semantic atlas slots -- see tools/gen_placeholder_art.py.
const SOLID_TILES := [4, 5, 6, 7]  # liquid, obstacle, wall, wall-alt

# --- the wall blob ---------------------------------------------------------
#
# Rows 1+ of each atlas hold 47 wall tiles, one per legal arrangement of wall
# neighbours. The bit layout and the enumeration order mirror
# tools/gen_placeholder_art.py: both files derive the list from the same rule
# rather than sharing a table, so neither can drift into a silent mis-pairing of
# art and peering bits.
const BIT_N := 1
const BIT_E := 2
const BIT_S := 4
const BIT_W := 8
const BIT_NE := 16
const BIT_SE := 32
const BIT_SW := 64
const BIT_NW := 128

## corner bit, and the two sides that must be wall for it to mean anything.
const CORNERS := [
	[BIT_NE, BIT_N, BIT_E], [BIT_SE, BIT_S, BIT_E],
	[BIT_SW, BIT_S, BIT_W], [BIT_NW, BIT_N, BIT_W],
]

## Which peering bit each neighbour bit drives.
const NEIGHBOR_BITS := {
	BIT_N: TileSet.CELL_NEIGHBOR_TOP_SIDE,
	BIT_E: TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	BIT_S: TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	BIT_W: TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	BIT_NE: TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	BIT_SE: TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	BIT_SW: TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	BIT_NW: TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
}

const BLOB_ROW := 1
const BLOB_COLUMNS := 8
const WALL_TERRAIN_SET := 0
const WALL_TERRAIN := 0

## Ambient tints give each band a mood without per-biome lighting work.
const BIOMES := {
	"meadow": {"name": "Green Meadow", "tint": Color(1.0, 1.0, 1.0)},
	"forest": {"name": "Deep Forest", "tint": Color(0.92, 0.98, 0.92)},
	"cave": {"name": "Winding Caves", "tint": Color(0.82, 0.84, 0.94)},
	"ruins": {"name": "Broken Ruins", "tint": Color(1.0, 0.98, 0.92)},
	"swamp": {"name": "Fetid Swamp", "tint": Color(0.9, 0.96, 0.86)},
	"desert": {"name": "Scorched Waste", "tint": Color(1.0, 0.97, 0.88)},
	"ice": {"name": "Frozen Reach", "tint": Color(0.92, 0.97, 1.0)},
	"volcanic": {"name": "Molten Depths", "tint": Color(1.0, 0.9, 0.86)},
	"sky": {"name": "Cloud Gardens", "tint": Color(0.97, 0.99, 1.0)},
	"castle": {"name": "Ruby Palace", "tint": Color(1.0, 0.94, 0.97)},
}


const PACK_TILESETS := "res://assets/ninja_adventure/Backgrounds/Tilesets/"
const PACK_COLUMNS := 16
## Where each part of a pack atlas lands. Row 0 is the semantic slots.
const ROW_GROUND := 1
const ROW_LIQUID := 8
const ROW_TREES := 13
const ROW_DECOR := 15
const ROW_HOUSES := 16
const PACK_ROWS := 19
const GROUND_GRASS := 0
const GROUND_DIRT := 1
## Variants that should be the exception on a lawn, not half of it.
const RARE := 0.12
## Reading a transition tile's links (see _links): a side connects when at least
## EDGE_RUN pixels of terrain touch that edge, counted away from its corners; the
## tile holds the terrain at all when BODY_PIXELS of it do.
const EDGE_MARGIN := 3
const EDGE_RUN := 3
const BODY_PIXELS := 24

## Biomes cut from the pack. Every entry names a sheet under PACK_TILESETS and a
## 16px cell (or cell rect) in it.
const PACK_BIOMES := {
	"meadow": {
		"walls": "trees",
		"slots": [
			["TilesetFloor.png", Vector2i(0, 12)],   # floor: plain grass
			["TilesetFloor.png", Vector2i(1, 12)],   # floor-alt: grass with a tuft
			["TilesetFloor.png", Vector2i(1, 8)],    # path: dirt
			["TilesetFloor.png", Vector2i(1, 11)],   # special: dirt with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open water
			["TilesetNature.png", Vector2i(0, 10)],  # obstacle: a bush
			# wall: plain grass. Crowns never quite meet, and a darker floor under them
			# shows through the gaps as hard-edged squares round every small grove.
			["TilesetFloor.png", Vector2i(0, 12)],
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# Grass with dirt worn into it. The block's last row -- grass edging onto
		# sand -- is another terrain and is left out.
		"ground": ["TilesetFloor.png", Rect2i(0, 7, 11, 6)],
		# Block-relative: the tufted lawns, and dirt with a stick or a pebble.
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		# Listed twice to plant twice as often.
		"trees": [
			["TilesetNature.png", Vector2i(0, 0)],
			["TilesetNature.png", Vector2i(0, 0)],
			["TilesetNature.png", Vector2i(16, 0)],
			["TilesetNature.png", Vector2i(2, 0)],
		],
		"decor": [
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(1, 2)],
			["TilesetFloorDetail.png", Vector2i(2, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetFloorDetail.png", Vector2i(4, 2)], ["TilesetFloorDetail.png", Vector2i(5, 2)],
			["TilesetFloorDetail.png", Vector2i(6, 2)], ["TilesetFloorDetail.png", Vector2i(7, 2)],
			["TilesetFloorDetail.png", Vector2i(2, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(6, 0)], ["TilesetFloorDetail.png", Vector2i(7, 0)],
			# Tufts twice over: the flowers are loud, and a lawn is mostly grass.
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetNature.png", Vector2i(3, 11)], ["TilesetNature.png", Vector2i(6, 11)],
		],
		"decor_density": 0.05,
		"houses": [
			["TilesetHouse.png", Rect2i(0, 0, 4, 3)],
			["TilesetHouse.png", Rect2i(4, 0, 4, 3)],
		],
	},
}

var _sheets := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TILESET_DIR)
	DirAccess.make_dir_recursive_absolute(BIOME_DIR)
	for id in BIOMES:
		if PACK_BIOMES.has(id):
			_build_pack(id, BIOMES[id], PACK_BIOMES[id])
		else:
			_build(id, BIOMES[id])
	quit()


func _build(id: String, info: Dictionary) -> void:
	var texture_path := "res://assets/placeholder/tiles_%s.png" % id
	if not ResourceLoader.exists(texture_path):
		push_error("missing atlas %s -- run tools/gen_placeholder_art.py" % texture_path)
		return

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)  # "world"

	var source := TileSetAtlasSource.new()
	source.texture = load(texture_path)
	source.texture_region_size = Vector2i(TILE, TILE)
	# Must be attached before tiles are created, or the tiles get no physics
	# layers and every collision polygon call fails.
	tile_set.add_source(source, SOURCE_ID)
	for column in 8:
		source.create_tile(Vector2i(column, 0))

	var masks := _blob_masks()
	for index in masks.size():
		source.create_tile(_blob_coords(index))

	# The terrain set has to exist before any tile can be assigned to it.
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(WALL_TERRAIN_SET, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(WALL_TERRAIN_SET)
	tile_set.set_terrain_name(WALL_TERRAIN_SET, WALL_TERRAIN, "wall")
	tile_set.set_terrain_color(WALL_TERRAIN_SET, WALL_TERRAIN, Color(0.86, 0.42, 0.32))

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for column in SOLID_TILES:
		_add_collision(source.get_tile_data(Vector2i(column, 0), 0), square)

	for index in masks.size():
		var data := source.get_tile_data(_blob_coords(index), 0)
		_add_collision(data, square)
		data.terrain_set = WALL_TERRAIN_SET
		data.terrain = WALL_TERRAIN
		for bit in NEIGHBOR_BITS:
			data.set_terrain_peering_bit(
					NEIGHBOR_BITS[bit],
					WALL_TERRAIN if masks[index] & bit else -1)

	var tileset_path := "%s/%s.tres" % [TILESET_DIR, id]
	ResourceSaver.save(tile_set, tileset_path)

	var biome := BiomeKit.new()
	biome.id = StringName(id)
	biome.display_name = info["name"]
	biome.tile_set = load(tileset_path)  # from disk, so it links instead of embedding
	biome.ambient_tint = info["tint"]
	biome.wall_terrain_set = WALL_TERRAIN_SET
	biome.wall_terrain = WALL_TERRAIN
	ResourceSaver.save(biome, "%s/%s.tres" % [BIOME_DIR, id])
	print("wrote biome %s (%d blob tiles)" % [id, masks.size()])


func _add_collision(data: TileData, square: PackedVector2Array) -> void:
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, square)


## Every legal neighbour arrangement, ascending. Exactly 47 of them: a corner
## only distinguishes anything when both sides beside it are wall, so the other
## 209 combinations can never occur on a map.
func _blob_masks() -> Array[int]:
	var masks: Array[int] = []
	for mask in 256:
		var legal := true
		for corner in CORNERS:
			if mask & corner[0] and not (mask & corner[1] and mask & corner[2]):
				legal = false
				break
		if legal:
			masks.append(mask)
	return masks


func _blob_coords(index: int) -> Vector2i:
	return Vector2i(index % BLOB_COLUMNS, BLOB_ROW + index / BLOB_COLUMNS)


# --- biomes cut from the Ninja Adventure pack ------------------------------
#
# A pack biome is composed rather than drawn: its atlas is cut from the pack's
# sheets here and embedded in the TileSet, so there is no intermediate PNG
# waiting to be re-imported. Row 0 keeps the eight semantic slots every biome
# shares, which is what lets the generator, the authored tools, their previews
# and the tests address a pack biome exactly like a placeholder one. The rows
# under it hold what placeholders never had: transitions, trees, decor, houses.
#
# The transitions' peering bits are read off the pixels (_links) rather than
# typed in, for the reason the wall blob derives its masks from a rule: a
# hand-written table of sixty tiles is sixty chances to mis-pair art and data.

func _build_pack(id: String, info: Dictionary, spec: Dictionary) -> void:
	var atlas := _compose(spec)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)  # "world"

	var texture := PortableCompressedTexture2D.new()
	# Outside the editor the source buffer is dropped once uploaded, and the TileSet
	# would save with an empty texture that no tile fits inside.
	texture.keep_compressed_buffer = true
	texture.create_from_image(atlas, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	# Attached before any tile exists, for the reason _build gives.
	tile_set.add_source(source, SOURCE_ID)

	var square := _square()
	for column in 8:
		source.create_tile(Vector2i(column, 0))
	for column in SOLID_TILES:
		_add_collision(source.get_tile_data(Vector2i(column, 0), 0), square)
	# The obstacle doubles as the bush a forest stands where no tree fits, and
	# there it lives on the y-sorted props layer.
	_stand_up(source.get_tile_data(Vector2i(5, 0), 0), Vector2i.ONE)

	var ground_set := _add_terrain_set(tile_set, ["grass", "dirt"])
	var ground: Rect2i = spec["ground"][1]
	var rare: Array = spec.get("ground_rare", [])
	for y in ground.size.y:
		for x in ground.size.x:
			var coords := Vector2i(x, ROW_GROUND + y)
			if _is_empty(atlas, coords):
				continue
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			var links := _links(atlas, coords, _is_dirt)
			data.terrain_set = ground_set
			data.terrain = GROUND_DIRT if links[8] else GROUND_GRASS
			for index in 8:
				data.set_terrain_peering_bit(MapDresser.PEERING_BITS[index],
						GROUND_DIRT if links[index] else GROUND_GRASS)
			if Vector2i(x, y) in rare:
				data.probability = RARE

	var liquid_set := _add_terrain_set(tile_set, ["water"])
	var liquid: Rect2i = spec["liquid"][1]
	for y in liquid.size.y:
		for x in liquid.size.x:
			var coords := Vector2i(x, ROW_LIQUID + y)
			if _is_empty(atlas, coords):
				continue
			var links := _links(atlas, coords, _is_water)
			# A tile with no water in it is plain land, and the land's business.
			if not links[8]:
				continue
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			_add_collision(data, square)
			data.terrain_set = liquid_set
			data.terrain = 0
			for index in 8:
				data.set_terrain_peering_bit(MapDresser.PEERING_BITS[index],
						0 if links[index] else -1)

	var trees: Array[Vector2i] = []
	for index in spec["trees"].size():
		var coords := Vector2i(index * 2, ROW_TREES)
		source.create_tile(coords, Vector2i(2, 2))
		_stand_up(source.get_tile_data(coords, 0), Vector2i(2, 2))
		trees.append(coords)

	var decor: Array[Vector2i] = []
	for index in spec["decor"].size():
		var coords := Vector2i(index, ROW_DECOR)
		source.create_tile(coords)
		decor.append(coords)

	var houses: Array[Vector2i] = []
	var column := 0
	for entry: Array in spec["houses"]:
		var size: Vector2i = (entry[1] as Rect2i).size
		var coords := Vector2i(column, ROW_HOUSES)
		source.create_tile(coords, size)
		_stand_up(source.get_tile_data(coords, 0), size)
		houses.append(coords)
		column += size.x

	var tileset_path := "%s/%s.tres" % [TILESET_DIR, id]
	ResourceSaver.save(tile_set, tileset_path)

	var biome := BiomeKit.new()
	biome.id = StringName(id)
	biome.display_name = info["name"]
	biome.tile_set = load(tileset_path)  # from disk, so it links instead of embedding
	biome.ambient_tint = info["tint"]
	biome.wall_style = BiomeKit.WallStyle.TREES if spec["walls"] == "trees" else BiomeKit.WallStyle.BLOB
	biome.ground_terrain_set = ground_set
	biome.ground_grass = GROUND_GRASS
	biome.ground_dirt = GROUND_DIRT
	biome.liquid_terrain_set = liquid_set
	biome.liquid_terrain = 0
	biome.tree_tiles = trees
	biome.decor_tiles = decor
	biome.decor_density = spec.get("decor_density", 0.06)
	biome.house_tiles = houses
	ResourceSaver.save(biome, "%s/%s.tres" % [BIOME_DIR, id])
	print("wrote pack biome %s (%d tiles)" % [id, source.get_tiles_count()])


func _compose(spec: Dictionary) -> Image:
	var atlas := Image.create_empty(PACK_COLUMNS * TILE, PACK_ROWS * TILE, false, Image.FORMAT_RGBA8)
	var slots: Array = spec["slots"]
	for index in slots.size():
		if slots[index] != null:
			_blit(atlas, slots[index][0], Rect2i(slots[index][1], Vector2i.ONE), Vector2i(index, 0))
	_blit(atlas, spec["ground"][0], spec["ground"][1], Vector2i(0, ROW_GROUND))
	_blit(atlas, spec["liquid"][0], spec["liquid"][1], Vector2i(0, ROW_LIQUID))
	for index in spec["trees"].size():
		var tree: Array = spec["trees"][index]
		_blit(atlas, tree[0], Rect2i(tree[1], Vector2i(2, 2)), Vector2i(index * 2, ROW_TREES))
	for index in spec["decor"].size():
		var piece: Array = spec["decor"][index]
		_blit(atlas, piece[0], Rect2i(piece[1], Vector2i.ONE), Vector2i(index, ROW_DECOR))
	var column := 0
	for entry: Array in spec["houses"]:
		var cells: Rect2i = entry[1]
		_blit(atlas, entry[0], cells, Vector2i(column, ROW_HOUSES))
		column += cells.size.x
	return atlas


func _blit(atlas: Image, sheet: String, cells: Rect2i, at: Vector2i) -> void:
	if not _sheets.has(sheet):
		var image := Image.load_from_file(PACK_TILESETS + sheet)
		image.convert(Image.FORMAT_RGBA8)
		_sheets[sheet] = image
	atlas.blit_rect(_sheets[sheet], Rect2i(cells.position * TILE, cells.size * TILE), at * TILE)


## How a transition tile connects, read off its pixels: eight flags in
## MapDresser.PEERING_BITS order, then whether the terrain is in the tile at all.
##
## The pack draws a transition inside the terrain's own cells -- a path cell beside
## grass shows dirt on its inner half only, a one-wide path is a strip down the
## middle of its cells -- so the grass around a path is always plain grass. That
## makes the art read like the wall blob: a side connects where the terrain reaches
## that edge, a corner where it fills the corner.
func _links(atlas: Image, coords: Vector2i, test: Callable) -> Array[bool]:
	var origin := coords * TILE
	var last := TILE - 1
	var links: Array[bool] = []
	# Sides -- top, right, bottom, left -- as an edge's first pixel and its direction.
	for side: Array in [[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(last, 0), Vector2i(0, 1)],
			[Vector2i(0, last), Vector2i(1, 0)], [Vector2i(0, 0), Vector2i(0, 1)]]:
		var hits := 0
		for step in range(EDGE_MARGIN, TILE - EDGE_MARGIN):
			if _passes(atlas, origin + side[0] + side[1] * step, test):
				hits += 1
		links.append(hits >= EDGE_RUN)
	# Corners -- top-right, bottom-right, bottom-left, top-left -- as 2x2 blocks.
	for corner: Vector2i in [Vector2i(last - 1, 0), Vector2i(last - 1, last - 1),
			Vector2i(0, last - 1), Vector2i(0, 0)]:
		var hits := 0
		for y in 2:
			for x in 2:
				if _passes(atlas, origin + corner + Vector2i(x, y), test):
					hits += 1
		links.append(hits >= 2)
	var body := 0
	for y in TILE:
		for x in TILE:
			if _passes(atlas, origin + Vector2i(x, y), test):
				body += 1
	links.append(body >= BODY_PIXELS)
	return links


func _passes(atlas: Image, pixel: Vector2i, test: Callable) -> bool:
	var colour := atlas.get_pixelv(pixel)
	return colour.a > 0.0 and test.call(colour)


## The pack's dirt is warm and its grass is green; nothing in between.
func _is_dirt(colour: Color) -> bool:
	return colour.r > colour.g + 0.03


## Water, or the white foam at its edge.
func _is_water(colour: Color) -> bool:
	return (colour.b > colour.r + 0.08 and colour.b > colour.g - 0.04) \
			or (colour.r > 0.78 and colour.g > 0.78 and colour.b > 0.78)


func _is_empty(atlas: Image, coords: Vector2i) -> bool:
	for y in TILE:
		for x in TILE:
			if atlas.get_pixel(coords.x * TILE + x, coords.y * TILE + y).a > 0.0:
				return false
	return true


func _add_terrain_set(tile_set: TileSet, names: Array) -> int:
	var index := tile_set.get_terrain_sets_count()
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(index, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	for terrain in names.size():
		tile_set.add_terrain(index)
		tile_set.set_terrain_name(index, terrain, names[terrain])
		tile_set.set_terrain_color(index, terrain, Color.from_hsv(float(terrain) / names.size(), 0.6, 0.9))
	return index


## Anchors a tile that stands up off the ground at the bottom row of its
## footprint, and sorts it from that row's bottom edge: a player in front draws
## over it, a player behind draws under its crown. A tile is drawn centred on its
## cell, so an even width is nudged half a cell right onto the grid.
## MapDresser.footprint is the inverse of this -- change one, change both.
func _stand_up(data: TileData, size: Vector2i) -> void:
	data.texture_origin = Vector2i(-TILE / 2 if size.x % 2 == 0 else 0, (size.y - 1) * TILE / 2)
	data.y_sort_origin = TILE / 2


func _square() -> PackedVector2Array:
	var half := TILE / 2.0
	return PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
