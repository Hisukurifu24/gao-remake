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
## The pack draws no pond one cell across, and a lone pool cell drawn with the
## nearest tile it does have shows as the cut-off end of a strip. So one is put
## together from the pond block's one-wide vertical strip -- the rounded end of its
## top cap over the rounded end of its bottom one -- and parked right of every
## liquid block. Block-relative: the strip's top cap; the bottom cap is two cells
## down. The caps draw their ends mid-cell, so the rows are measured, not halves:
## the top cap's water starts on row 8 under the bank's lip, the bottom cap's
## stops on row 11, and 10 + 6 rows keep both ends and a margin of land round them.
const LIQUID_STRIP := Vector2i(3, 0)
const PUDDLE := Vector2i(15, ROW_LIQUID)
const PUDDLE_TOP_ROWS := Vector2i(2, 10)     # from row 2 of the top cap, 10 rows
const PUDDLE_BOTTOM_ROWS := Vector2i(8, 6)   # from row 8 of the bottom cap, 6 rows
const ROW_TREES := 13
const ROW_DECOR := 15
const ROW_HOUSES := 16
## Under the houses, which leave room for one five cells tall: a composed wall blob.
const ROW_BLOB := 21
const PACK_ROWS := ROW_BLOB + 6
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
## The pack's raised-ground autotile as TilesetRelief.png lays it out, from a spec's
## "cliffs" origin: a 3x3 of outer corners and edges whose bottom row carries the cliff
## face, beside a one-wide column, and under that column a 2x2 of inner corners -- the
## open diagonal north-west, north-east / south-west, south-east.
const CLIFF_BLOCK := Vector2i(1, 0)
const CLIFF_INNER := Vector2i(0, 3)
## The earth hanging under a floating lawn, which the pack does not draw (see
## _underside). Per column of a cell: the last row it reaches, which is its outline.
## The run tiles, so the last column steps into the first.
const UNDERSIDE_LAST := [12, 13, 14, 14, 15, 15, 14, 14, 13, 12, 12, 13, 13, 12, 11, 11]
## Grass hanging over the lip, a row per string, "#" for grass: a ragged fringe,
## then a few longer blades.
const UNDERSIDE_FRINGE := ["##.####.###.###.", "#...#.....#..#.."]
## Stones, 3x2 by their top-left pixel; roots, a pixel each, hanging below the outline.
const UNDERSIDE_STONES := [Vector2i(2, 6), Vector2i(10, 7)]
const UNDERSIDE_ROOTS := [Vector2i(9, 13), Vector2i(9, 14), Vector2i(14, 12)]
## Where an underside runs out beside open sky it rounds off in its neighbour, over
## the four pixels nearest it: each column's first and last row, nearest first.
const UNDERSIDE_END_TOP := [0, 0, 1, 3]
const UNDERSIDE_END_LAST := [10, 9, 8, 6]
## The pack's stone walls (Interior/TilesetWallSimple.png) as a spec's "masonry" origin
## lays them out: the 5x5 outline of a room, bands of wall round floor, void outside.
## Relative to that origin, the cell drawing a wall with floor across one side -- the
## run's middle, which tiles, rather than its capped ends -- and the corner cell
## drawing a wall with floor across one diagonal only.
const MASONRY_SIDES := {BIT_N: Vector2i(3, 4), BIT_E: Vector2i(0, 1), BIT_S: Vector2i(3, 0), BIT_W: Vector2i(4, 1)}
const MASONRY_CORNERS := {BIT_NE: Vector2i(0, 4), BIT_SE: Vector2i(0, 0), BIT_SW: Vector2i(4, 0), BIT_NW: Vector2i(4, 4)}

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
	"forest": {
		"walls": "trees",
		"slots": [
			["TilesetFloor.png", Vector2i(11, 12)],  # floor: deep grass
			["TilesetFloor.png", Vector2i(12, 12)],  # floor-alt: deep grass with a tuft
			["TilesetFloor.png", Vector2i(12, 8)],   # path: dark earth
			["TilesetFloor.png", Vector2i(12, 11)],  # special: earth with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open water
			["TilesetNature.png", Vector2i(1, 10)],  # obstacle: a bush
			["TilesetFloor.png", Vector2i(11, 12)],  # wall: grass under the canopy, as the meadow
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The meadow's block eleven columns over: the same tiles in the deep palette,
		# so the rare cells are the same cells.
		"ground": ["TilesetFloor.png", Rect2i(11, 7, 11, 6)],
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		# The pack only draws its shores onto the light grass. Swapping every colour of
		# the meadow's ground block for the one at the same pixel of this biome's puts
		# the pond in the grass it actually sits in. See _palette.
		"liquid_palette": ["TilesetFloor.png", Rect2i(0, 7, 11, 6), Rect2i(11, 7, 11, 6)],
		# Pines and rooted oaks three times over, and the odd dead one. No round
		# meadow tree: its bright crown reads as a hole in the canopy.
		"trees": [
			["TilesetNature.png", Vector2i(2, 0)],
			["TilesetNature.png", Vector2i(2, 0)],
			["TilesetNature.png", Vector2i(2, 0)],
			["TilesetNature.png", Vector2i(6, 0)],
			["TilesetNature.png", Vector2i(6, 0)],
			["TilesetNature.png", Vector2i(6, 0)],
			["TilesetNature.png", Vector2i(4, 0)],
		],
		"decor": [
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(1, 2)],
			["TilesetFloorDetail.png", Vector2i(2, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetFloorDetail.png", Vector2i(4, 2)], ["TilesetFloorDetail.png", Vector2i(6, 2)],
			["TilesetFloorDetail.png", Vector2i(7, 2)],
			# Ferns and clover where the meadow has flowers, twice over. The pack's
			# twigs and leaf drifts are drawn orange for sand and shout on deep grass.
			["TilesetNature.png", Vector2i(4, 11)], ["TilesetNature.png", Vector2i(5, 11)],
			["TilesetNature.png", Vector2i(2, 11)],
			["TilesetNature.png", Vector2i(4, 11)], ["TilesetNature.png", Vector2i(5, 11)],
			["TilesetNature.png", Vector2i(2, 11)],
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
		],
		"decor_density": 0.05,
		# A logging village: an A-frame, a log house, a corner house and a shed.
		"houses": [
			["TilesetHouse.png", Rect2i(25, 14, 4, 5)],
			["TilesetHouse.png", Rect2i(29, 0, 4, 4)],
			["TilesetHouse.png", Rect2i(26, 0, 3, 3)],
			["TilesetHouse.png", Rect2i(19, 19, 3, 3)],
		],
	},
	"cave": {
		# Raised rock: the pack's cliffs, their tops repainted the dark of its pits, so
		# the rock between two caverns reads as the dark they were dug out of rather
		# than as a snowy plateau. See _compose_cliffs.
		"walls": "cliffs",
		"cliffs": ["TilesetRelief.png", Vector2i(0, 0)],
		"cliff_top": ["TilesetHole.png", Vector2i(1, 1)],
		"slots": [
			["TilesetFloor.png", Vector2i(11, 19)],  # floor: packed earth
			["TilesetFloor.png", Vector2i(12, 19)],  # floor-alt: earth with a scuff
			["TilesetFloor.png", Vector2i(12, 15)],  # path: dark mud
			["TilesetFloor.png", Vector2i(12, 18)],  # special: mud with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open water
			["TilesetReliefDetail.png", Vector2i(4, 0)],  # obstacle: a boulder
			null,                                    # wall: the cliff blob's solid tile
			null,                                    # wall-alt: invisible, a tent's footprint
		],
		# The meadow's block in the pack's taupe palette. Its mud is no warmer than its
		# earth, so _is_dirt cannot tell them apart -- the links are read off the
		# meadow's block instead, which is the same drawing.
		"ground": ["TilesetFloor.png", Rect2i(11, 14, 11, 6)],
		"ground_links": Rect2i(0, 7, 11, 6),
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		"liquid_palette": ["TilesetFloor.png", Rect2i(0, 7, 11, 6), Rect2i(11, 14, 11, 6)],
		# Stones three times over, and a skull and a bone once: a mine, not an ossuary.
		# The pack's pale flat stones and teal pebbles were tried and dropped: on taupe
		# the first read as snow and the second as litter.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(15, 0)], ["TilesetReliefDetail.png", Vector2i(0, 0)],
			["TilesetReliefDetail.png", Vector2i(0, 2)],
			["TilesetFloorDetail.png", Vector2i(15, 0)], ["TilesetReliefDetail.png", Vector2i(0, 0)],
			["TilesetReliefDetail.png", Vector2i(0, 2)],
			["TilesetFloorDetail.png", Vector2i(15, 0)], ["TilesetReliefDetail.png", Vector2i(0, 0)],
			["TilesetReliefDetail.png", Vector2i(0, 2)],
			["TilesetFloorDetail.png", Vector2i(13, 0)], ["TilesetFloorDetail.png", Vector2i(14, 0)],
		],
		"decor_density": 0.04,
		# A mining camp: two tents and one the Army has been living in too long.
		"houses": [
			["tileset_camp.png", Rect2i(4, 0, 3, 3)],
			["tileset_camp.png", Rect2i(7, 0, 3, 3)],
			["tileset_camp.png", Rect2i(10, 0, 3, 3)],
		],
	},
	"ruins": {
		# Sandstone: the relief sheet's orange block, laid out as the grey one the cave
		# uses. Its pale tops stay: grassed over, the rock is the same colour as the
		# rooms cut into it and a floor stops reading as rooms at all.
		"walls": "cliffs",
		"cliffs": ["TilesetRelief.png", Vector2i(0, 5)],
		"slots": [
			["TilesetFloor.png", Vector2i(0, 12)],   # floor: plain grass
			["TilesetFloor.png", Vector2i(1, 12)],   # floor-alt: grass with a tuft
			["TilesetFloor.png", Vector2i(1, 8)],    # path: dirt
			["TilesetFloor.png", Vector2i(1, 11)],   # special: dirt with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open water
			["TilesetReliefDetail.png", Vector2i(4, 3)],  # obstacle: a sandstone boulder
			null,                                    # wall: the cliff blob's solid tile
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The meadow's grass, which is the palette the pack draws its abandoned village
		# in: what grew back over the ruins is the same grass that grows on floor 1.
		"ground": ["TilesetFloor.png", Rect2i(0, 7, 11, 6)],
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		# Sandstone rubble twice over, tufts, and the odd bone. The abandoned village's
		# own rubble and paving would suit better, but that sheet is drawn off the
		# 16 px grid and no piece of it fits in one cell.
		"decor": [
			["TilesetReliefDetail.png", Vector2i(0, 3)], ["TilesetReliefDetail.png", Vector2i(0, 5)],
			["TilesetReliefDetail.png", Vector2i(4, 4)], ["TilesetReliefDetail.png", Vector2i(4, 5)],
			["TilesetReliefDetail.png", Vector2i(0, 3)], ["TilesetReliefDetail.png", Vector2i(0, 5)],
			["TilesetReliefDetail.png", Vector2i(4, 4)], ["TilesetReliefDetail.png", Vector2i(4, 5)],
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetFloorDetail.png", Vector2i(1, 2)], ["TilesetReliefDetail.png", Vector2i(0, 4)],
			["TilesetFloorDetail.png", Vector2i(14, 0)],
		],
		"decor_density": 0.05,
	},
	"swamp": {
		"walls": "trees",
		"slots": [
			["TilesetFloor.png", Vector2i(11, 12)],  # floor: deep grass
			["TilesetFloor.png", Vector2i(12, 12)],  # floor-alt: deep grass with a tuft
			["TilesetFloor.png", Vector2i(12, 8)],   # path: dark earth
			["TilesetFloor.png", Vector2i(12, 11)],  # special: earth with a pebble
			["TilesetWater.png", Vector2i(14, 7)],   # liquid: open bog
			["TilesetNature.png", Vector2i(7, 11)],  # obstacle: a stand of reeds
			["TilesetFloor.png", Vector2i(11, 12)],  # wall: grass under the canopy, as the forest
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The forest's deep grass: what tells the two bands apart is what stands on it
		# and what pools in it, not the ground.
		"ground": ["TilesetFloor.png", Rect2i(11, 7, 11, 6)],
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		# The pack's purple bog, laid out as its pond. It is drawn into the cave's taupe
		# earth, so the same swap the forest makes carries its bank onto deep grass --
		# from the taupe block this time -- and leaves the bog's own dark mud rim alone.
		"liquid": ["TilesetWater.png", Rect2i(13, 6, 11, 5)],
		"liquid_palette": ["TilesetFloor.png", Rect2i(11, 14, 11, 6), Rect2i(11, 7, 11, 6)],
		# Dead trees three times over, and oaks standing on their roots between. The
		# pack's mossy tree was tried and dropped: its crown is the meadow's bright one,
		# and among dead wood it reads as a hole in the canopy.
		"trees": [
			["TilesetNature.png", Vector2i(4, 0)],
			["TilesetNature.png", Vector2i(4, 0)],
			["TilesetNature.png", Vector2i(4, 0)],
			["TilesetNature.png", Vector2i(6, 0)],
			["TilesetNature.png", Vector2i(6, 0)],
		],
		# Reeds and tufts, the pack's mossy teal stones, and the odd bone.
		"decor": [
			["TilesetNature.png", Vector2i(7, 11)], ["TilesetNature.png", Vector2i(7, 11)],
			["TilesetFloorDetail.png", Vector2i(2, 2)], ["TilesetFloorDetail.png", Vector2i(2, 2)],
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetNature.png", Vector2i(4, 11)],
			["TilesetNature.png", Vector2i(7, 12)], ["TilesetNature.png", Vector2i(8, 12)],
			["TilesetFloorDetail.png", Vector2i(0, 1)],
			["TilesetFloorDetail.png", Vector2i(14, 0)],
		],
		"decor_density": 0.05,
	},
	"desert": {
		# Mesas: the ruins' sandstone cliffs, standing in the dunes they were drawn for.
		# Their pale tops are exactly the dunes' light sand, which is the path, so a
		# corridor read as a gap in one flat plain. Repainted the brown of their own
		# faces, the rock stands apart from both the deep orange rooms and the pale
		# corridors between them.
		"walls": "cliffs",
		"cliffs": ["TilesetRelief.png", Vector2i(0, 5)],
		"cliff_top": ["TilesetRelief.png", Vector2i(5, 6)],
		"slots": [
			["TilesetFloor.png", Vector2i(0, 5)],    # floor: deep orange sand
			["TilesetFloor.png", Vector2i(1, 5)],    # floor-alt: sand with a ripple
			["TilesetFloor.png", Vector2i(1, 1)],    # path: light sand
			["TilesetFloor.png", Vector2i(1, 4)],    # special: light sand with a pebble
			["TilesetWater.png", Vector2i(1, 1)],    # liquid: open water
			["TilesetReliefDetail.png", Vector2i(4, 3)],  # obstacle: a sandstone boulder
			null,                                    # wall: the cliff blob's solid tile
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The meadow's block drawn in sand. Both sands are warmer than green, so _is_dirt
		# would call all of it dirt; and the dune lines are not the grass's tufts, so the
		# meadow's links cannot be borrowed the way the cave borrows them. Its dirt is
		# the pale sand instead, read by luminance: the pale side and its shading sit
		# above 0.75, the deep side and its dune lines below it.
		"ground": ["TilesetFloor.png", Rect2i(0, 0, 11, 6)],
		"pale_dirt": 0.75,
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		# The pack's oasis: its pond laid out as the meadow's, already banked in sand.
		# Its land is the light sand, though, so that one colour becomes the floor's.
		"liquid": ["TilesetWater.png", Rect2i(0, 0, 11, 5)],
		"liquid_land": ["TilesetWater.png", Vector2i(0, 5)],
		# Ripples and pebbles in the sand, and bones: the pack's own, and the desert
		# sheet's skull and ribs. The twigs the forest turned down were drawn for here.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(2, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(4, 0)], ["TilesetFloorDetail.png", Vector2i(5, 0)],
			["TilesetFloorDetail.png", Vector2i(6, 0)], ["TilesetFloorDetail.png", Vector2i(7, 0)],
			["TilesetFloorDetail.png", Vector2i(2, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(4, 0)],
			["TilesetReliefDetail.png", Vector2i(0, 3)], ["TilesetReliefDetail.png", Vector2i(0, 5)],
			["TilesetDesert.png", Vector2i(16, 11)], ["TilesetDesert.png", Vector2i(17, 11)],
			["TilesetDesert.png", Vector2i(19, 11)],
		],
		"decor_density": 0.04,
	},
	"ice": {
		# A snowbound pine wood: the outdoor bands wall with trees, and the pack draws
		# its pines and oaks again under snow.
		"walls": "trees",
		"slots": [
			["TilesetFloor.png", Vector2i(0, 19)],   # floor: old snow
			["TilesetFloor.png", Vector2i(1, 19)],   # floor-alt: old snow with a frosted tuft
			["TilesetFloor.png", Vector2i(1, 15)],   # path: fresh snow
			["TilesetFloor.png", Vector2i(1, 18)],   # special: fresh snow with a pebble
			["TilesetWater.png", Vector2i(14, 1)],   # liquid: a frozen pool
			["TilesetNature.png", Vector2i(5, 12)],  # obstacle: a snowed-over bush
			["TilesetFloor.png", Vector2i(0, 19)],   # wall: snow under the canopy, as the meadow
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The meadow's block drawn in snow: lavender old snow for the grass, white for
		# the dirt, and a grey fringe that is the grass's. Only the white is dirt.
		"ground": ["TilesetFloor.png", Rect2i(0, 14, 11, 6)],
		"pale_dirt": 0.97,
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		# The pack's frozen pond, banked in the lavender the floor is. Its foam is the
		# white of its land, so whether water reaches an edge cannot be read off it: its
		# links are read off the desert's oasis beside it, which is the same drawing
		# water pixel for water pixel.
		"liquid": ["TilesetWater.png", Rect2i(13, 0, 11, 5)],
		"liquid_links": Rect2i(0, 0, 11, 5),
		# Its land is the white of the path, and the floor is the lavender: the white
		# becomes the floor's, but only where it is land -- regions touching nothing but
		# the ground's colours -- since the foam is drawn in that white too.
		"liquid_land": ["TilesetWater.png", Vector2i(13, 5)],
		"liquid_land_regions": true,
		# Snowed-in pines three times over, green ones showing through twice, and a
		# round tree under snow once.
		"trees": [
			["TilesetNature.png", Vector2i(10, 0)],
			["TilesetNature.png", Vector2i(10, 0)],
			["TilesetNature.png", Vector2i(10, 0)],
			["TilesetNature.png", Vector2i(8, 0)],
			["TilesetNature.png", Vector2i(8, 0)],
			["TilesetNature.png", Vector2i(12, 0)],
		],
		# The pack's tufts and leaves drawn frosted, drifts, and teal stones.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(0, 3)], ["TilesetFloorDetail.png", Vector2i(1, 3)],
			["TilesetFloorDetail.png", Vector2i(2, 3)], ["TilesetFloorDetail.png", Vector2i(3, 3)],
			["TilesetFloorDetail.png", Vector2i(0, 3)], ["TilesetFloorDetail.png", Vector2i(3, 3)],
			["TilesetFloorDetail.png", Vector2i(4, 3)], ["TilesetFloorDetail.png", Vector2i(6, 3)],
			["TilesetFloorDetail.png", Vector2i(7, 3)],
			["TilesetFloorDetail.png", Vector2i(10, 0)], ["TilesetFloorDetail.png", Vector2i(10, 0)],
			["TilesetNature.png", Vector2i(8, 13)],
			["TilesetNature.png", Vector2i(6, 12)], ["TilesetNature.png", Vector2i(7, 12)],
		],
		"decor_density": 0.05,
	},
	"volcanic": {
		# The sandstone cliffs with their tops burnt the black of the pack's pits:
		# red rock under a charred crust, standing over ash and lava.
		"walls": "cliffs",
		"cliffs": ["TilesetRelief.png", Vector2i(0, 5)],
		"cliff_top": ["TilesetHole.png", Vector2i(1, 1)],
		"slots": [
			["TilesetFloor.png", Vector2i(11, 19)],  # floor: ash
			["TilesetFloor.png", Vector2i(12, 19)],  # floor-alt: ash with a scuff
			["TilesetFloor.png", Vector2i(12, 15)],  # path: cinder
			["TilesetFloor.png", Vector2i(12, 18)],  # special: cinder with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open lava, once repainted
			["TilesetNature.png", Vector2i(4, 14)],  # obstacle: a rock seamed with ember ore
			null,                                    # wall: the cliff blob's solid tile
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The cave's taupe block, links read off the meadow's as the cave reads them,
		# burnt down to ash: earth to the grey of the pits' rims, mud to cinder. The pack
		# draws no ash, so this palette is typed -- but only into colours it does draw,
		# which _recolour checks against Palette.png.
		"ground": ["TilesetFloor.png", Rect2i(11, 14, 11, 6)],
		"ground_links": Rect2i(0, 7, 11, 6),
		"ground_recolour": {
			"b3957f": "695953",  # earth -> ash
			"8e7c73": "4e484a",  # its scuffs
			"90775e": "4e484a",  # mud -> cinder
			"816855": "3b3643",  # the mud's streaks
			"c8966b": "816855",  # a pebble in it
		},
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		# The pack draws no lava. Its pond is banked onto the ground as the cave's is,
		# and then its water is repainted in the pack's fire: see _lava.
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		"liquid_palette": ["TilesetFloor.png", Rect2i(0, 7, 11, 6), Rect2i(11, 14, 11, 6)],
		"liquid_ramp": "FX/Particle/Fire.png",
		# Orange cracks and ember specks, which the dark ground makes glow, among
		# stones, cinders and the odd skull.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(5, 0)], ["TilesetFloorDetail.png", Vector2i(6, 0)],
			["TilesetFloorDetail.png", Vector2i(7, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(5, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(4, 0)], ["TilesetFloorDetail.png", Vector2i(1, 0)],
			["TilesetFloorDetail.png", Vector2i(15, 0)], ["TilesetReliefDetail.png", Vector2i(0, 0)],
			["TilesetFloorDetail.png", Vector2i(15, 0)], ["TilesetReliefDetail.png", Vector2i(0, 3)],
			["TilesetFloorDetail.png", Vector2i(13, 0)],
		],
		"decor_density": 0.05,
	},
	"sky": {
		# Gardens in the clouds: the rooms are lawns, and past their edges the ground
		# falls away onto open sky -- a rim round the lawn, and a cell of earth
		# hanging under it. The rim is the pack's hole, the earth drawn in its
		# palette; see _compose_hole.
		"walls": "hole",
		"hole": ["TilesetHole.png", Vector2i(0, 0)],
		# The rim's nubs where two rims meet round a corner of lawn (SW, SE).
		"hole_inner": [Vector2i(6, 1), Vector2i(5, 1)],
		# The underside's colours, top to bottom: grass over the lip, its shadowed
		# fringe, topsoil, earth, deeper earth, the earth in shadow (and the rim's own
		# colour), the outline (the hole's void); and its stones, lit and not.
		"underside": {"lip": "74a334", "fringe": "56864c", "soil": "965340",
				"earth": "816855", "deep": "695953", "shade": "4e484a",
				"outline": "141b1b", "stone": "8e7c73", "stone_lit": "b3957f"},
		# The sky the void is cut out onto, in cells: the pack's clouds -- whole ones,
		# long ones and puffs -- on its daytime blue.
		"backdrop": {
			"sky": "79b8ce",
			"clouds": "TilesetFloorB.png",
			"size": Vector2i(24, 16),
			"pieces": [Rect2i(0, 0, 3, 3), Rect2i(0, 0, 3, 3), Rect2i(0, 0, 3, 3),
					Rect2i(0, 3, 3, 1), Rect2i(0, 3, 3, 1), Rect2i(0, 3, 3, 1), Rect2i(0, 3, 3, 1),
					Rect2i(3, 3, 1, 1), Rect2i(3, 3, 1, 1), Rect2i(3, 3, 1, 1), Rect2i(3, 3, 1, 1),
					Rect2i(3, 3, 1, 1), Rect2i(3, 3, 1, 1)],
		},
		"slots": [
			["TilesetFloor.png", Vector2i(0, 12)],   # floor: plain grass
			["TilesetFloor.png", Vector2i(1, 12)],   # floor-alt: grass with a tuft
			["TilesetFloor.png", Vector2i(1, 8)],    # path: dirt
			["TilesetFloor.png", Vector2i(1, 11)],   # special: dirt with a pebble
			["TilesetWater.png", Vector2i(1, 7)],    # liquid: open water
			["TilesetNature.png", Vector2i(0, 10)],  # obstacle: a bush
			null,                                    # wall: the hole blob's solid tile, empty
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# The meadow's lawn, and its pond: a garden is the grass of floor 1, kept.
		"ground": ["TilesetFloor.png", Rect2i(0, 7, 11, 6)],
		"ground_rare": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(0, 4), Vector2i(1, 4)],
		"liquid": ["TilesetWater.png", Rect2i(0, 6, 13, 5)],
		# A garden's scatter -- flowers twice as often as the meadow's, blossom and petals
		# -- and wisps of cloud blown loose over the lawns.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(5, 2)], ["TilesetFloorDetail.png", Vector2i(5, 2)],
			["TilesetNature.png", Vector2i(0, 11)], ["TilesetNature.png", Vector2i(1, 11)],
			["TilesetNature.png", Vector2i(3, 11)], ["TilesetNature.png", Vector2i(6, 11)],
			["TilesetNature.png", Vector2i(3, 11)], ["TilesetNature.png", Vector2i(6, 11)],
			["TilesetFloorDetail.png", Vector2i(2, 0)], ["TilesetFloorDetail.png", Vector2i(3, 0)],
			["TilesetFloorDetail.png", Vector2i(10, 0)], ["TilesetFloorDetail.png", Vector2i(10, 0)],
			["TilesetFloorDetail.png", Vector2i(0, 2)], ["TilesetFloorDetail.png", Vector2i(3, 2)],
			["TilesetNature.png", Vector2i(2, 11)],
		],
		"decor_density": 0.06,
	},
	"castle": {
		# Halls walled in dressed stone: the pack's interior walls, a band of masonry
		# round every floor with the dark of the wall's top beyond it. The pack draws
		# them as a room's outline only, in bands wider than half a cell, so the 47 are
		# put together a pixel at a time rather than from quarters; see _compose_masonry.
		"walls": "masonry",
		"masonry": ["Interior/TilesetWallSimple.png", Vector2i(0, 6)],
		"slots": [
			["Interior/TilesetInteriorFloor.png", Vector2i(1, 7)],  # floor: brick
			["Interior/TilesetInteriorFloor.png", Vector2i(1, 7)],  # floor-alt: the pack draws no variant
			["Interior/TilesetInteriorFloor.png", Vector2i(1, 7)],  # path: the inlay's brick
			["Interior/TilesetInteriorFloor.png", Vector2i(1, 7)],  # special: the same
			["TilesetWater.png", Vector2i(1, 1)],    # liquid: open water
			["TilesetDungeon.png", Vector2i(11, 3)],  # obstacle: a dressed stone block
			null,                                    # wall: the masonry blob's solid tile
			null,                                    # wall-alt: invisible, a house's footprint
		],
		# A brick floor inlaid with a frame, laid out as the meadow's block: the inlay
		# is the dirt, so corridors run as bordered runners and the throne room is
		# framed. The block draws no plain floor outside an inlay -- its outside is a
		# border of small bricks, meant to meet a wall -- so the rooms are the inlay's
		# own brick, copied over the block's plain cell (where the pack drew a patch
		# of light). The frame can only be read against the layout; see _framed_links.
		"ground": ["Interior/TilesetInteriorFloor.png", Rect2i(0, 6, 11, 6)],
		"ground_fill": {Vector2i(0, 5): Vector2i(1, 1)},
		"ground_layout": ["TilesetFloor.png", Rect2i(0, 7, 11, 6)],
		"ground_frame": "ef914f",
		# The desert's oasis with its sand cut away, so the pool sits sunk in whatever
		# floor is under it, its banks for a kerb.
		"liquid": ["TilesetWater.png", Rect2i(0, 0, 11, 5)],
		"liquid_cut": ["TilesetWater.png", Vector2i(0, 5)],
		# Cracks in the brick, rubble, and the bones of whoever came up first.
		"decor": [
			["TilesetFloorDetail.png", Vector2i(5, 0)], ["TilesetFloorDetail.png", Vector2i(6, 0)],
			["TilesetFloorDetail.png", Vector2i(7, 0)], ["TilesetFloorDetail.png", Vector2i(8, 0)],
			["TilesetFloorDetail.png", Vector2i(5, 0)], ["TilesetFloorDetail.png", Vector2i(6, 0)],
			["TilesetReliefDetail.png", Vector2i(0, 0)], ["TilesetReliefDetail.png", Vector2i(0, 2)],
			["TilesetReliefDetail.png", Vector2i(0, 0)],
			["TilesetFloorDetail.png", Vector2i(13, 0)], ["TilesetFloorDetail.png", Vector2i(14, 0)],
		],
		"decor_density": 0.04,
	},
}

const PACK_ROOT := "res://assets/ninja_adventure/"

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
		_add_blob_tile(source, _blob_coords(index), masks[index], WALL_TERRAIN_SET, square, false)

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


## Where blob tile [param index] sits in a composed pack atlas.
func _pack_blob_coords(index: int) -> Vector2i:
	return Vector2i(index % BLOB_COLUMNS, ROW_BLOB + index / BLOB_COLUMNS)


## Wires one blob tile: solid, and peering at wall wherever [param mask] has a
## neighbour. [param create] is false when the tile already exists.
func _add_blob_tile(source: TileSetAtlasSource, coords: Vector2i, mask: int, terrain_set: int,
		square: PackedVector2Array, create := true) -> void:
	if create:
		source.create_tile(coords)
	var data := source.get_tile_data(coords, 0)
	_add_collision(data, square)
	data.terrain_set = terrain_set
	data.terrain = WALL_TERRAIN
	for bit in NEIGHBOR_BITS:
		data.set_terrain_peering_bit(NEIGHBOR_BITS[bit], WALL_TERRAIN if mask & bit else -1)


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

	# Every link below is read off [code]atlas[/code]; what is drawn can be a liquid
	# the pack never drew, repainted over the water whose pixels say where it runs.
	var drawn := atlas
	if spec.has("liquid_ramp"):
		drawn = atlas.duplicate() as Image
		_lava(drawn, spec)
	var texture := PortableCompressedTexture2D.new()
	# Outside the editor the source buffer is dropped once uploaded, and the TileSet
	# would save with an empty texture that no tile fits inside.
	texture.keep_compressed_buffer = true
	texture.create_from_image(drawn, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
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
	# A palette _is_dirt cannot read is read off the same drawing in one it can. "The
	# same drawing" is checked a cell at a time, because it is not quite: the taupe
	# block draws mud in a cell where the meadow's has plain grass, and trusting the
	# meadow there wires a mud tile as ground and paints it across every cavern floor.
	var dirt_test := _is_dirt
	if spec.has("pale_dirt"):
		var threshold: float = spec["pale_dirt"]
		dirt_test = func(colour: Color) -> bool: return colour.get_luminance() > threshold
	var link_sheet: Image = null
	var link_palette := {}
	if spec.has("ground_links"):
		link_sheet = _sheet(spec["ground"][0])
		link_palette = _palette(spec["ground"][0], spec["ground_links"], ground)
	for y in ground.size.y:
		for x in ground.size.x:
			var coords := Vector2i(x, ROW_GROUND + y)
			if _is_empty(atlas, coords):
				continue
			var link_cell := Vector2i(x, y)
			var links: Array[bool]
			if link_sheet != null:
				link_cell += (spec["ground_links"] as Rect2i).position
				if not _drawn_alike(link_sheet, link_cell, ground.position + Vector2i(x, y), link_palette):
					continue
				links = _links(link_sheet, link_cell, dirt_test)
			elif spec.has("ground_layout"):
				var layout: Array = spec["ground_layout"]
				links = _framed_links(atlas, coords, _sheet(layout[0]),
						(layout[1] as Rect2i).position + link_cell, Color.html(spec["ground_frame"]).to_rgba32())
				if links.is_empty():
					print("  ground %s is not the layout's drawing; left out" % link_cell)
					continue
			else:
				links = _links(atlas, coords, dirt_test)
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			data.terrain_set = ground_set
			data.terrain = GROUND_DIRT if links[8] else GROUND_GRASS
			for index in 8:
				data.set_terrain_peering_bit(MapDresser.PEERING_BITS[index],
						GROUND_DIRT if links[index] else GROUND_GRASS)
			if Vector2i(x, y) in rare:
				data.probability = RARE

	var liquid_set := _add_terrain_set(tile_set, ["water"])
	var liquid: Rect2i = spec["liquid"][1]
	var liquid_cells: Array[Vector2i] = [PUDDLE]
	for y in liquid.size.y:
		for x in liquid.size.x:
			liquid_cells.append(Vector2i(x, ROW_LIQUID + y))
	# A pond whose foam is the white of its land is read off the same pond drawn on
	# other land -- but only where the two hold their water in the same pixels.
	var liquid_sheet := _sheet(spec["liquid"][0])
	var borrowed: bool = spec.has("liquid_links")
	for coords in liquid_cells:
		if _is_empty(atlas, coords):
			continue
		var links: Array[bool]
		if not borrowed:
			links = _links(atlas, coords, _is_water)
		elif coords == PUDDLE:
			# Nothing drawn to borrow from; a lone pool touches no edge with anything.
			links = _links(atlas, coords, _is_blue)
		else:
			var cell := coords - Vector2i(0, ROW_LIQUID)
			var link_cell: Vector2i = (spec["liquid_links"] as Rect2i).position + cell
			if not _same_water(liquid_sheet, link_cell, liquid.position + cell):
				continue
			links = _links(liquid_sheet, link_cell, _is_water)
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
	for index in spec.get("trees", []).size():
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
	for entry: Array in spec.get("houses", []):
		var size: Vector2i = (entry[1] as Rect2i).size
		var coords := Vector2i(column, ROW_HOUSES)
		source.create_tile(coords, size)
		_stand_up(source.get_tile_data(coords, 0), size)
		houses.append(coords)
		column += size.x

	var wall_set := -1
	if _has_blob(spec):
		wall_set = _add_terrain_set(tile_set, ["wall"])
		var masks := _blob_masks()
		for index in masks.size():
			_add_blob_tile(source, _pack_blob_coords(index), masks[index], wall_set, square)

	var tileset_path := "%s/%s.tres" % [TILESET_DIR, id]
	ResourceSaver.save(tile_set, tileset_path)

	var biome := BiomeKit.new()
	biome.id = StringName(id)
	biome.display_name = info["name"]
	biome.tile_set = load(tileset_path)  # from disk, so it links instead of embedding
	biome.ambient_tint = info["tint"]
	biome.wall_style = BiomeKit.WallStyle.TREES if spec["walls"] == "trees" else BiomeKit.WallStyle.BLOB
	biome.wall_terrain_set = wall_set
	biome.wall_terrain = WALL_TERRAIN
	biome.ground_terrain_set = ground_set
	biome.ground_grass = GROUND_GRASS
	biome.ground_dirt = GROUND_DIRT
	biome.liquid_terrain_set = liquid_set
	biome.liquid_terrain = 0
	biome.tree_tiles = trees
	biome.decor_tiles = decor
	biome.decor_density = spec.get("decor_density", 0.06)
	biome.house_tiles = houses
	if spec.has("backdrop"):
		var backdrop := PortableCompressedTexture2D.new()
		backdrop.keep_compressed_buffer = true
		backdrop.create_from_image(_backdrop(spec), PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		biome.backdrop = backdrop
	ResourceSaver.save(biome, "%s/%s.tres" % [BIOME_DIR, id])
	print("wrote pack biome %s (%d tiles)" % [id, source.get_tiles_count()])


func _compose(spec: Dictionary) -> Image:
	# Only a biome with a composed blob pays for its rows.
	var rows := PACK_ROWS if _has_blob(spec) else ROW_BLOB
	var atlas := Image.create_empty(PACK_COLUMNS * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	var slots: Array = spec["slots"]
	for index in slots.size():
		if slots[index] != null:
			_blit(atlas, slots[index][0], Rect2i(slots[index][1], Vector2i.ONE), Vector2i(index, 0))
	# The ground slots before the cliffs, which are laid over the floor tile.
	_recolour(atlas, spec, Rect2i(0, 0, 4, 1))
	if spec.has("cliffs"):
		_compose_cliffs(atlas, spec)
	elif spec.has("hole"):
		_compose_hole(atlas, spec)
	elif spec.has("masonry"):
		_compose_masonry(atlas, spec)
	_blit(atlas, spec["ground"][0], spec["ground"][1], Vector2i(0, ROW_GROUND))
	var fill: Dictionary = spec.get("ground_fill", {})
	for cell: Vector2i in fill:
		atlas.blit_rect(atlas, Rect2i((Vector2i(0, ROW_GROUND) + fill[cell]) * TILE, Vector2i(TILE, TILE)),
				(Vector2i(0, ROW_GROUND) + cell) * TILE)
	_blit(atlas, spec["liquid"][0], spec["liquid"][1], Vector2i(0, ROW_LIQUID))
	if spec.has("liquid_palette"):
		var swap: Array = spec["liquid_palette"]
		var liquid_cells := Rect2i(Vector2i(0, ROW_LIQUID), (spec["liquid"][1] as Rect2i).size)
		var changed := _repaint(atlas, liquid_cells, _palette(swap[0], swap[1], swap[2]))
		print("  shoreline repainted: %d pixels" % changed)
	_recolour(atlas, spec, Rect2i(0, ROW_GROUND, PACK_COLUMNS, ROW_TREES - ROW_GROUND))
	if spec.has("liquid_land"):
		# A pond drawn on a ground this biome keeps for its paths: its plain land cell's
		# colour becomes the floor's, and the rest of the bank stays as drawn.
		var land: Array = spec["liquid_land"]
		var liquid_cells := Rect2i(Vector2i(0, ROW_LIQUID), (spec["liquid"][1] as Rect2i).size)
		var from := _dominant(_sheet(land[0]), land[1])
		var to := _dominant(atlas, Vector2i.ZERO)
		var changed := 0
		if spec.get("liquid_land_regions", false):
			var ground_cells := Rect2i(Vector2i(0, ROW_GROUND), (spec["ground"][1] as Rect2i).size)
			changed = _repaint_land(atlas, liquid_cells, from, to, _colours(atlas, ground_cells))
		else:
			changed = _repaint(atlas, liquid_cells, {from: to})
		print("  shoreline repainted: %d pixels" % changed)
	if spec.has("liquid_cut"):
		# A pond drawn on a ground no floor of this biome is: its land is cut away, so
		# the pool shows the floor laid under it, and its banks stay.
		var land: Array = spec["liquid_cut"]
		var liquid_px := Rect2i(Vector2i(0, ROW_LIQUID) * TILE, (spec["liquid"][1] as Rect2i).size * TILE)
		var pond := atlas.get_region(liquid_px)
		_cut(pond, _dominant(_sheet(land[0]), land[1]))
		atlas.blit_rect(pond, Rect2i(Vector2i.ZERO, pond.get_size()), liquid_px.position)
	# From the atlas rather than the sheet, so it comes already repainted.
	var strip := (Vector2i(0, ROW_LIQUID) + LIQUID_STRIP) * TILE
	atlas.blit_rect(atlas, Rect2i(strip + Vector2i(0, PUDDLE_TOP_ROWS.x), Vector2i(TILE, PUDDLE_TOP_ROWS.y)),
			PUDDLE * TILE)
	atlas.blit_rect(atlas, Rect2i(strip + Vector2i(0, 2 * TILE + PUDDLE_BOTTOM_ROWS.x),
			Vector2i(TILE, PUDDLE_BOTTOM_ROWS.y)), PUDDLE * TILE + Vector2i(0, PUDDLE_TOP_ROWS.y))
	for index in spec.get("trees", []).size():
		var tree: Array = spec["trees"][index]
		_blit(atlas, tree[0], Rect2i(tree[1], Vector2i(2, 2)), Vector2i(index * 2, ROW_TREES))
	for index in spec["decor"].size():
		var piece: Array = spec["decor"][index]
		_blit(atlas, piece[0], Rect2i(piece[1], Vector2i.ONE), Vector2i(index, ROW_DECOR))
	var column := 0
	for entry: Array in spec.get("houses", []):
		var cells: Rect2i = entry[1]
		_blit(atlas, entry[0], cells, Vector2i(column, ROW_HOUSES))
		column += cells.size.x
	return atlas


## A 47-tile wall blob put together from the pack's raised-ground autotile, so rock
## joins through the same terrain pass as a placeholder biome's walls, and the floor
## test's blob checks hold it to the same standard.
##
## The pack draws a dozen arrangements and the blob needs 47, so every tile is built
## from quarters, each decided by only what it touches: a top quarter by north, its
## side and the corner between them, a bottom one by its side and corner. A cell
## with open ground below it is a cliff face from top to bottom -- the pack draws the
## face inside the rock's own last row -- so there every quarter comes from the face
## row. Laid over the floor tile, because the pack's outer corners are rounded off.
func _compose_cliffs(atlas: Image, spec: Dictionary) -> void:
	var sheet := _sheet(spec["cliffs"][0])
	var origin: Vector2i = spec["cliffs"][1]
	var half := Vector2i(TILE / 2, TILE / 2)
	var underlay := atlas.get_region(Rect2i(0, 0, TILE, TILE))
	var masks := _blob_masks()
	for index in masks.size():
		var at := _pack_blob_coords(index) * TILE
		atlas.blit_rect(underlay, Rect2i(Vector2i.ZERO, underlay.get_size()), at)
		for quarter in 4:
			var cell := _cliff_quarter(masks[index], quarter, origin)
			var offset := Vector2i(quarter % 2, quarter / 2) * half
			atlas.blend_rect(sheet, Rect2i(cell * TILE + offset, half), at + offset)
	if spec.has("cliff_top"):
		var top: Array = spec["cliff_top"]
		var palette := {_dominant(sheet, origin + CLIFF_BLOCK + Vector2i.ONE): _dominant(_sheet(top[0]), top[1])}
		_repaint(atlas, Rect2i(0, ROW_BLOB, BLOB_COLUMNS, 6), palette)
	_fill_wall_slot(atlas)


## Whether the spec composes a wall blob, and so pays for its rows.
func _has_blob(spec: Dictionary) -> bool:
	return spec.has("cliffs") or spec.has("hole") or spec.has("masonry")


## The plain wall slot is the blob's solid tile: what a mass cell draws before it is
## joined.
func _fill_wall_slot(atlas: Image) -> void:
	var solid := atlas.get_region(Rect2i(_pack_blob_coords(_blob_masks().size() - 1) * TILE, Vector2i(TILE, TILE)))
	atlas.blit_rect(solid, Rect2i(Vector2i.ZERO, solid.get_size()), Vector2i(6, 0) * TILE)


## The sheet cell quarter [param quarter] (0 top-left, 1 top-right, 2 bottom-left,
## 3 bottom-right) of blob tile [param mask] is cut from.
func _cliff_quarter(mask: int, quarter: int, origin: Vector2i) -> Vector2i:
	var block := origin + CLIFF_BLOCK
	var inner := origin + CLIFF_INNER
	var left := quarter % 2 == 0
	var side_open := (mask & (BIT_W if left else BIT_E)) == 0
	var column := (0 if left else 2) if side_open else 1
	var inner_column := 0 if left else 1
	if (mask & BIT_S) == 0:
		return block + Vector2i(column, 2)
	if quarter < 2:
		if (mask & BIT_N) == 0:
			return block + Vector2i(column, 0)
		if side_open:
			return block + Vector2i(column, 1)
		if (mask & (BIT_NW if left else BIT_NE)) == 0:
			return inner + Vector2i(inner_column, 0)
		return block + Vector2i.ONE
	if side_open:
		return block + Vector2i(column, 1)
	if (mask & (BIT_SW if left else BIT_SE)) == 0:
		return inner + Vector2i(inner_column, 1)
	return block + Vector2i.ONE


## A 47-tile wall blob of ground falling away into the void, so the mass is a window
## onto the biome's backdrop. The floor is rimmed by the pack's hole: a 3x3 whose
## strips are exactly its outer halves side by side, so every arrangement of sides is
## a choice of quarters, each decided by the side and the end it touches. Under the
## floor, over that rim, hangs a cell of earth (_underside), since the hole's own face
## is a 6 px band that reads as a fence.
##
## Where the earth runs out beside more void, its rounded end is drawn in the
## neighbour it runs out beside, because only that neighbour can tell: the earth
## cell's own mask has lost the corner (its north is open), while the cell beside it
## sees the floor across its corner. Every piece is laid over the floor tile, which
## shows through the hole's ragged edge; then the hole's void is cut out.
func _compose_hole(atlas: Image, spec: Dictionary) -> void:
	var sheet := _sheet(spec["hole"][0])
	var origin: Vector2i = spec["hole"][1]
	var inner: Array = spec["hole_inner"]
	var underside := _underside(spec["underside"])
	var half := Vector2i(TILE / 2, TILE / 2)
	var void_colour := _dominant(sheet, origin + Vector2i.ONE)
	var underlay := atlas.get_region(Rect2i(0, 0, TILE, TILE))
	var masks := _blob_masks()
	for index in masks.size():
		var at := _pack_blob_coords(index) * TILE
		var walls := _neighbourhood(masks[index])
		var hangs := not walls[1]
		for quarter in 4:
			var left := quarter % 2 == 0
			var top := quarter < 2
			var offset := Vector2i(quarter % 2, quarter / 2) * half
			var side_open := not walls[3 if left else 5]
			# The earth covers the rim along the floor above, so none is drawn there.
			var end_open := not walls[1 if top else 7] and not (top and hangs)
			var corner_open := not walls[(0 if left else 2) + (0 if top else 6)]
			var cell := origin + Vector2i((0 if left else 2) if side_open else 1,
					(0 if top else 2) if end_open else 1)
			if not top and not side_open and not end_open and corner_open:
				cell = inner[quarter - 2]
			var piece := underlay.get_region(Rect2i(offset, half))
			piece.blend_rect(sheet, Rect2i(cell * TILE + offset, half), Vector2i.ZERO)
			_cut(piece, void_colour)
			var drawn := -1
			if hangs:
				drawn = (0 if left else 2) if side_open else 1
			elif not side_open and not walls[0 if left else 2]:
				# The floor across this side's top corner has earth under it, in the
				# cell beside this one, and here it ends.
				drawn = 4 if left else 3
			if drawn >= 0:
				piece.blend_rect(underside, Rect2i(Vector2i(drawn * TILE, 0) + offset, half),
						Vector2i.ZERO)
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, half), at + offset)
	_fill_wall_slot(atlas)


## A 47-tile wall blob of dressed stone, from the pack's interior walls. The pack
## draws them as the outline of one room -- a band of masonry along each side, a
## corner where two bands meet round the room's corner, and the void of the wall's top
## beyond -- and its bands are 10 to 13 pixels deep, shadow included, so no quarter of a cell can be
## chosen by what that quarter alone touches, the way the cliffs and the hole are.
##
## So every pixel is drawn by the floor nearest it: an open side makes it that
## side's band, an open corner between two walls the room corner's, each sampled at
## the same pixel of the cell the pack draws it in. A tile the pack draws comes out
## as drawn, since its one floor is nearest everything; one it doesn't -- a wall
## end, a pillar, a wall one cell thick -- is its bands meeting where they reach
## each other, a mitre at a corner the floor wraps round.
func _compose_masonry(atlas: Image, spec: Dictionary) -> void:
	var sheet := _sheet(spec["masonry"][0])
	var origin: Vector2i = spec["masonry"][1]
	var void_colour := sheet.get_pixelv(origin * TILE)
	var masks := _blob_masks()
	for index in masks.size():
		var at := _pack_blob_coords(index) * TILE
		for y in TILE:
			for x in TILE:
				var piece := _nearest_floor(masks[index], Vector2(x, y) + Vector2(0.5, 0.5))
				atlas.set_pixelv(at + Vector2i(x, y), void_colour if piece.x < 0
						else sheet.get_pixelv((origin + piece) * TILE + Vector2i(x, y)))
	_fill_wall_slot(atlas)


## The masonry piece drawing the floor nearest [param point] of a wall cell whose
## wall neighbours are [param mask], or (-1, -1) where it has none. A side beats a
## corner it ties with: along a side, the corner is that side's.
func _nearest_floor(mask: int, point: Vector2) -> Vector2i:
	var far := Vector2(TILE, TILE) - point
	var sides := {BIT_N: point.y, BIT_E: far.x, BIT_S: far.y, BIT_W: point.x}
	var corners := {BIT_NE: Vector2(far.x, point.y), BIT_SE: far, BIT_SW: Vector2(point.x, far.y),
			BIT_NW: point}
	var best := INF
	var piece := Vector2i(-1, -1)
	for bit: int in sides:
		if (mask & bit) == 0 and sides[bit] < best:
			best = sides[bit]
			piece = MASONRY_SIDES[bit]
	for corner: Array in CORNERS:
		var open: bool = (mask & corner[1]) != 0 and (mask & corner[2]) != 0 and (mask & corner[0]) == 0
		var distance: float = (corners[corner[0]] as Vector2).length()
		if open and distance < best:
			best = distance
			piece = MASONRY_CORNERS[corner[0]]
	return piece


## The earth under a floating floor, which the pack does not draw, in the pack's
## colours ([param colours], by role): five cells in a row. The middle is the run,
## which tiles; either side of it the run ends against more floor, beside it (a rim
## down its outer two pixels, where the hole's own rim carries on below). Past those
## are its rounded ends, each placed as the neighbour it runs out beside draws it --
## the west end in the right of its cell, the east end in the left.
func _underside(colours: Dictionary) -> Image:
	var run := []
	for x in TILE:
		run.append({"top": 0, "last": UNDERSIDE_LAST[x], "kind": "run", "x": x})
	var west_end := []
	var east_end := []
	for i in UNDERSIDE_END_TOP.size():
		var column := {"top": UNDERSIDE_END_TOP[i], "last": UNDERSIDE_END_LAST[i], "kind": "end"}
		west_end.push_front(column)
		east_end.append(column)
	var rim := {"top": 0, "last": TILE - 1, "kind": "rim"}
	var west_rim := run.duplicate()
	var east_rim := run.duplicate()
	for x in 2:
		west_rim[x] = rim
		east_rim[TILE - 1 - x] = rim
	var alongside := _paint_underside(colours, west_rim + run + east_rim)
	var ends := _paint_underside(colours, west_end + run + east_end)
	var strip := Image.create_empty(TILE * 5, TILE, false, Image.FORMAT_RGBA8)
	var reach := west_end.size()
	strip.blit_rect(alongside, Rect2i(0, 0, TILE * 3, TILE), Vector2i.ZERO)
	strip.blit_rect(ends, Rect2i(0, 0, reach, TILE), Vector2i(TILE * 4 - reach, 0))
	strip.blit_rect(ends, Rect2i(reach + TILE, 0, reach, TILE), Vector2i(TILE * 4, 0))
	return strip


## [param columns] of underside painted side by side, each a first and last row and a
## kind: the run, a rim, or an end. Its outline is wherever it borders empty sky --
## beneath, beside, and above an end that starts low.
func _paint_underside(colours: Dictionary, columns: Array) -> Image:
	var image := Image.create_empty(columns.size(), TILE, false, Image.FORMAT_RGBA8)
	var paint := {}
	for role: String in colours:
		paint[role] = Color.hex(_pack_colour(colours[role]))
	var shows := func(x: int, y: int) -> bool:
		return x >= 0 and x < columns.size() and y >= columns[x]["top"] and y <= columns[x]["last"]
	for x in columns.size():
		var column: Dictionary = columns[x]
		for y in TILE:
			if not shows.call(x, y):
				continue
			var role := "earth"
			if column["kind"] == "rim":
				role = "shade"
			elif y == column["last"] or not shows.call(x - 1, y) or not shows.call(x + 1, y) \
					or (y > 0 and not shows.call(x, y - 1)):
				role = "outline"
			elif column["kind"] == "end" or y == column["last"] - 1:
				role = "shade"
			elif y >= column["last"] - 3:
				role = "deep"
			elif y == 0:
				role = "lip"
			elif y <= UNDERSIDE_FRINGE.size() and UNDERSIDE_FRINGE[y - 1][column["x"]] == "#":
				role = "fringe"
			elif y < 4 or (y == 4 and column["x"] % 3 != 1):
				role = "soil"
			image.set_pixel(x, y, paint[role])
	# Then what lies over the earth, which reaches into the columns after its own.
	for x in columns.size():
		var column: Dictionary = columns[x]
		if column["kind"] != "run":
			continue
		for stone: Vector2i in UNDERSIDE_STONES:
			if stone.x == column["x"]:
				for dx in 3:
					image.set_pixel(x + dx, stone.y, paint["stone_lit" if dx < 2 else "stone"])
					image.set_pixel(x + dx, stone.y + 1, paint["stone" if dx < 2 else "deep"])
		for root: Vector2i in UNDERSIDE_ROOTS:
			if root.x == column["x"]:
				image.set_pixel(x, root.y, paint["outline"])
	return image


## Makes every pixel of [param image] in [param colour] transparent.
func _cut(image: Image, colour: int) -> void:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).to_rgba32() == colour:
				image.set_pixel(x, y, Color(0, 0, 0, 0))


## The bits of a blob mask as its 3x3, in reading order: true where there is wall.
## The cell itself is the middle, and always wall.
func _neighbourhood(mask: int) -> Array[bool]:
	var bits := [BIT_NW, BIT_N, BIT_NE, BIT_W, 0, BIT_E, BIT_SW, BIT_S, BIT_SE]
	var walls: Array[bool] = []
	for bit: int in bits:
		walls.append(bit == 0 or (mask & bit) != 0)
	return walls


## [param hex] as an RGBA32 int, refused unless the pack's palette has it.
func _pack_colour(hex: String) -> int:
	var pack := Image.load_from_file(PACK_ROOT + "Palette.png")
	pack.convert(Image.FORMAT_RGBA8)
	var colour := Color.html(hex).to_rgba32()
	if not colour in _ranked(pack, Rect2i(Vector2i.ZERO, pack.get_size()),
			func(_colour: Color) -> bool: return true):
		push_error("%s is not a colour of the pack's palette" % hex)
	return colour


## What shows through a see-through wall mass: a field of [code]sky[/code] with the
## pack's clouds strewn across it, drawn to tile -- a cloud running off one edge comes
## back on the other -- since the map draws it repeating behind itself. Scattered by a
## fixed seed, so a rebuild draws the same sky.
func _backdrop(spec: Dictionary) -> Image:
	var sky: Dictionary = spec["backdrop"]
	var size: Vector2i = sky["size"] * TILE
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.hex(_pack_colour(sky["sky"])))
	var sheet := _sheet(sky["clouds"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 80
	var placed: Array[Rect2i] = []
	for piece: Rect2i in sky["pieces"]:
		var region := Rect2i(piece.position * TILE, piece.size * TILE)
		# A few tries for a spot clear of every cloud already down, then give up on it.
		for attempt in 40:
			var at := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
			var room := Rect2i(at, region.size).grow(TILE / 2)
			if placed.any(func(other: Rect2i) -> bool: return _overlaps_wrapped(room, other, size)):
				continue
			placed.append(Rect2i(at, region.size))
			for dy in [0, -size.y]:
				for dx in [0, -size.x]:
					image.blend_rect(sheet, region, at + Vector2i(dx, dy))
			break
	return image


## Whether [param a] and [param b] overlap on a field of [param size] that wraps.
func _overlaps_wrapped(a: Rect2i, b: Rect2i, size: Vector2i) -> bool:
	for dy in [-size.y, 0, size.y]:
		for dx in [-size.x, 0, size.x]:
			if a.intersects(Rect2i(b.position + Vector2i(dx, dy), b.size)):
				return true
	return false


## The colour covering most of [param cell] of [param image], as an RGBA32 int.
func _dominant(image: Image, cell: Vector2i) -> int:
	var counts := {}
	for y in TILE:
		for x in TILE:
			var key := image.get_pixelv(cell * TILE + Vector2i(x, y)).to_rgba32()
			counts[key] = counts.get(key, 0) + 1
	var best := 0
	for key: int in counts:
		if not counts.has(best) or counts[key] > counts[best]:
			best = key
	return best


func _blit(atlas: Image, sheet: String, cells: Rect2i, at: Vector2i) -> void:
	atlas.blit_rect(_sheet(sheet), Rect2i(cells.position * TILE, cells.size * TILE), at * TILE)


func _sheet(sheet: String) -> Image:
	if not _sheets.has(sheet):
		var image := Image.load_from_file(PACK_TILESETS + sheet)
		image.convert(Image.FORMAT_RGBA8)
		_sheets[sheet] = image
	return _sheets[sheet]


## A palette swap read off the pack rather than typed in: [param from] and
## [param to] are two blocks of [param sheet] drawn alike in two palettes, and each
## colour of the first maps to whichever colour most often sits at the same pixel
## of the second. As RGBA32 ints, since those compare exactly.
func _palette(sheet: String, from: Rect2i, to: Rect2i) -> Dictionary:
	var image := _sheet(sheet)
	var votes := {}
	for y in from.size.y * TILE:
		for x in from.size.x * TILE:
			var source := image.get_pixelv(from.position * TILE + Vector2i(x, y))
			if source.a == 0.0:
				continue
			var key := source.to_rgba32()
			var target := image.get_pixelv(to.position * TILE + Vector2i(x, y)).to_rgba32()
			if not votes.has(key):
				votes[key] = {}
			votes[key][target] = votes[key].get(target, 0) + 1
	var palette := {}
	for key: int in votes:
		var best := 0
		var best_count := -1
		for target: int in votes[key]:
			if votes[key][target] > best_count:
				best = target
				best_count = votes[key][target]
		palette[key] = best
	return palette


## Whether [param cell] of [param image] is [param reference] repainted by
## [param palette], to within a stray pixel or two.
func _drawn_alike(image: Image, reference: Vector2i, cell: Vector2i, palette: Dictionary) -> bool:
	var off := 0
	for y in TILE:
		for x in TILE:
			var from := image.get_pixelv(reference * TILE + Vector2i(x, y))
			var to := image.get_pixelv(cell * TILE + Vector2i(x, y))
			if from.a == 0.0 or to.a == 0.0:
				if from.a != to.a:
					off += 1
			elif palette.get(from.to_rgba32(), -1) != to.to_rgba32():
				off += 1
	return off <= 4


## How a cell of an inlaid floor links, or nothing if that cannot be trusted. Its
## inlay and the brick round it are the same colours, so which side of the frame is
## inlay is only known from the layout: [param frame] splits the cell into regions,
## and each is inlay when [param reference_cell] of [param reference], the pack's
## block laid out alike, is dirt where the region lies farthest from the frame. Not
## where most of it lies: the block draws an inner corner as a notch of a pixel or
## three, the inlay as a square four across, and most of that square is the block's
## dirt. The links read off that are kept only if they are the reference's own, as
## far as a terrain can tell them apart (see _expressible).
func _framed_links(atlas: Image, coords: Vector2i, reference: Image, reference_cell: Vector2i,
		frame: int) -> Array[bool]:
	var origin := coords * TILE
	var framed: Array[Vector2i] = []
	for y in TILE:
		for x in TILE:
			if atlas.get_pixel(origin.x + x, origin.y + y).to_rgba32() == frame:
				framed.append(Vector2i(x, y))
	var inlay := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var seen := {}
	for start: Vector2i in framed:
		# The frame is the inlay's own edge.
		inlay.set_pixelv(start, Color.RED)
		seen[start] = true
	for y in TILE:
		for x in TILE:
			var start := Vector2i(x, y)
			if seen.has(start):
				continue
			seen[start] = true
			var region: Array[Vector2i] = [start]
			var next := 0
			while next < region.size():
				var pixel := region[next]
				next += 1
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var near := pixel + step
					if near.x >= 0 and near.y >= 0 and near.x < TILE and near.y < TILE and not seen.has(near):
						seen[near] = true
						region.append(near)
			var deepest := -1
			var votes := 0
			var dirt := 0
			for pixel in region:
				var depth := TILE
				for edge in framed:
					depth = mini(depth, maxi(absi(edge.x - pixel.x), absi(edge.y - pixel.y)))
				if depth > deepest:
					deepest = depth
					votes = 0
					dirt = 0
				if depth == deepest:
					votes += 1
					if _passes(reference, reference_cell * TILE + pixel, _is_dirt):
						dirt += 1
			for pixel in region:
				inlay.set_pixelv(pixel, Color.RED if dirt * 2 >= votes else Color.GREEN)
	var links := _links(inlay, Vector2i.ZERO, _is_dirt)
	if _expressible(links) != _expressible(_links(reference, reference_cell, _is_dirt)):
		return []
	return links


## [param links] with every corner set to what its sides already say, where they
## say it: inside the terrain a corner is its own only when both sides beside it
## are, and outside it a side showing the terrain takes the corners along it (as
## MapDresser.expected_flags has it). The meadow's block draws a two-pixel sliver of
## dirt in the corner of a cell whose side beside it is grass -- a corner no
## neighbourhood can ask for, which the inlay does not draw.
func _expressible(links: Array[bool]) -> Array[bool]:
	var flags := links.duplicate()
	for corner in 4:
		var a: bool = links[MapDresser.CORNER_SIDES[corner][0]]
		var b: bool = links[MapDresser.CORNER_SIDES[corner][1]]
		if links[8]:
			flags[4 + corner] = links[4 + corner] and a and b
		else:
			flags[4 + corner] = links[4 + corner] or a or b
	return flags


## Repaints [param cells] by the spec's [code]ground_recolour[/code], if it has one:
## a ground the pack never draws, put together from colours it does. A target
## outside the pack's palette is refused rather than painted.
func _recolour(atlas: Image, spec: Dictionary, cells: Rect2i) -> void:
	if not spec.has("ground_recolour"):
		return
	var pack := Image.load_from_file(PACK_ROOT + "Palette.png")
	pack.convert(Image.FORMAT_RGBA8)
	var allowed := _ranked(pack, Rect2i(Vector2i.ZERO, pack.get_size()),
			func(_colour: Color) -> bool: return true)
	var palette := {}
	var recolour: Dictionary = spec["ground_recolour"]
	for from: String in recolour:
		var to := Color.html(recolour[from]).to_rgba32()
		if not to in allowed:
			push_error("ground_recolour: %s is not a colour of the pack's palette" % recolour[from])
			continue
		palette[Color.html(from).to_rgba32()] = to
	_repaint(atlas, cells, palette)


## Lava, which the pack never draws: its pond, with the water's colours swapped for
## the fire's, rank for rank by luminance -- the foam for the fire's pale core, the
## shallows for its orange, the deep for its red. Both ramps are read off the pack
## (the pond block, and [code]liquid_ramp[/code], a sheet of flame), so the lava is
## drawn in colours the pack already uses. Only the liquid cells and the liquid slot
## are repainted: the ramp's white is also a skull's.
func _lava(atlas: Image, spec: Dictionary) -> void:
	var pond: Rect2i = spec["liquid"][1]
	var water := _ranked(_sheet(spec["liquid"][0]), Rect2i(pond.position * TILE, pond.size * TILE), _is_water)
	var flame := Image.load_from_file(PACK_ROOT + spec["liquid_ramp"])
	flame.convert(Image.FORMAT_RGBA8)
	var fire := _ranked(flame, Rect2i(Vector2i.ZERO, flame.get_size()),
			func(colour: Color) -> bool: return colour.get_luminance() > 0.1)
	var palette := {}
	for index in water.size():
		var rank := roundi(float(index) * (fire.size() - 1) / maxi(1, water.size() - 1))
		palette[water[index]] = fire[rank]
	var changed := _repaint(atlas, Rect2i(0, ROW_LIQUID, PACK_COLUMNS, ROW_TREES - ROW_LIQUID), palette)
	changed += _repaint(atlas, Rect2i(4, 0, 1, 1), palette)
	print("  lava: %d water colours onto %d of fire, %d pixels" % [water.size(), fire.size(), changed])


## The colours inside [param pixels] of [param image] that pass [param test], darkest
## first, as RGBA32 keys.
func _ranked(image: Image, pixels: Rect2i, test: Callable) -> Array:
	var colours := {}
	for y in range(pixels.position.y, pixels.end.y):
		for x in range(pixels.position.x, pixels.end.x):
			var pixel := Vector2i(x, y)
			if _passes(image, pixel, test):
				colours[image.get_pixelv(pixel).to_rgba32()] = true
	var ranked := colours.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return Color.hex(a).get_luminance() < Color.hex(b).get_luminance())
	return ranked


## Swaps colours inside [param cells] of the atlas; returns how many pixels moved.
func _repaint(atlas: Image, cells: Rect2i, palette: Dictionary) -> int:
	var changed := 0
	for y in cells.size.y * TILE:
		for x in cells.size.x * TILE:
			var pixel := cells.position * TILE + Vector2i(x, y)
			var key := atlas.get_pixelv(pixel).to_rgba32()
			if palette.has(key) and palette[key] != key:
				atlas.set_pixelv(pixel, Color.hex(palette[key]))
				changed += 1
	return changed


## Repaints the regions of colour [param from] inside [param cells] that touch nothing
## but [param ground] -- the land round a pond, where its foam, drawn in the same
## colour, always touches the bank or the water. Returns how many pixels moved.
func _repaint_land(atlas: Image, cells: Rect2i, from: int, to: int, ground: Dictionary) -> int:
	var area := Rect2i(cells.position * TILE, cells.size * TILE)
	var seen := {}
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var start := Vector2i(x, y)
			if seen.has(start) or atlas.get_pixelv(start).to_rgba32() != from:
				continue
			seen[start] = true
			var region: Array[Vector2i] = [start]
			var open := true
			var next := 0
			while next < region.size():
				var pixel := region[next]
				next += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var near := pixel + Vector2i(dx, dy)
						if not area.has_point(near):
							continue
						var colour := atlas.get_pixelv(near)
						var key := colour.to_rgba32()
						if key == from:
							# Grown through sides only, so a region never leaks
							# across a diagonal gap in a ring.
							if dx * dy == 0 and not seen.has(near):
								seen[near] = true
								region.append(near)
						elif colour.a > 0.0 and not ground.has(key):
							open = false
			if open:
				for pixel in region:
					atlas.set_pixelv(pixel, Color.hex(to))
				changed += region.size()
	return changed


## Every colour drawn inside [param cells] of the atlas, as RGBA32 keys.
func _colours(atlas: Image, cells: Rect2i) -> Dictionary:
	var colours := {}
	for y in cells.size.y * TILE:
		for x in cells.size.x * TILE:
			var colour := atlas.get_pixelv(cells.position * TILE + Vector2i(x, y))
			if colour.a > 0.0:
				colours[colour.to_rgba32()] = true
	return colours


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


## Water, the swamp's purple bog, or the white foam at the edge of either.
func _is_water(colour: Color) -> bool:
	return (colour.b > colour.r + 0.08 and colour.b > colour.g - 0.04) \
			or (colour.g < colour.r - 0.1 and colour.g < colour.b - 0.05) \
			or (colour.r > 0.78 and colour.g > 0.78 and colour.b > 0.78)


## Water alone, without its foam: for a pond banked in snow, whose foam is the white
## of the land round it.
func _is_blue(colour: Color) -> bool:
	return colour.b > colour.r + 0.08 and colour.b > colour.g - 0.04


## Whether two cells of [param image] hold their water in the same pixels, to within
## a stray pixel or two.
func _same_water(image: Image, a: Vector2i, b: Vector2i) -> bool:
	var off := 0
	for y in TILE:
		for x in TILE:
			if _passes(image, a * TILE + Vector2i(x, y), _is_blue) \
					!= _passes(image, b * TILE + Vector2i(x, y), _is_blue):
				off += 1
	return off <= 4


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
