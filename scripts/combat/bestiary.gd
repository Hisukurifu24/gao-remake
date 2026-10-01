class_name Bestiary
## What lives on floor N, and what is waiting at the end of it.
##
## Ten templates cover a hundred floors. A monster's numbers come from its level
## ([method EnemyType.stat_at]) and its level comes from [FloorTuning], so the
## bestiary itself is just a routing table: biome band to a pool of trash,
## boss archetype to the template that plays it.
##
## Boss composition is deterministic, exactly like the floors themselves --
## floor 63's boss is the same monster, at the same level, with the same escorts,
## every time. Fights that reshuffle can't be balanced and can't be reported.

const ENEMY_PATH := "res://resources/enemies/%s.tres"

## Every template, listed explicitly (see [SkillLibrary] for why).
const ENEMIES: PackedStringArray = [
	"frenzy_boar", "dire_wolf", "little_nepent", "kobold_trooper", "cave_bat",
	"ruin_wraith", "lizardman_soldier", "stone_golem", "ember_drake", "illfang",
	"hollow_warden", "twin_giant",
]

## Which monsters roam which biome band. Order matters: the first entry is the
## band's rank-and-file and the one bosses take as an escort.
const BIOME_POOLS := {
	&"meadow": [&"frenzy_boar", &"little_nepent"],
	&"forest": [&"dire_wolf", &"little_nepent"],
	&"cave": [&"cave_bat", &"kobold_trooper"],
	&"ruins": [&"kobold_trooper", &"ruin_wraith"],
	&"swamp": [&"little_nepent", &"lizardman_soldier"],
	&"desert": [&"lizardman_soldier", &"frenzy_boar"],
	&"ice": [&"stone_golem", &"dire_wolf"],
	&"volcanic": [&"ember_drake", &"stone_golem"],
	&"sky": [&"cave_bat", &"ruin_wraith"],
	&"castle": [&"ruin_wraith", &"ember_drake", &"stone_golem"],
}

## [constant FloorTuning.BOSS_ARCHETYPES] to the template that plays it. Every
## archetype must appear here or generated floors lose their boss.
const BOSS_TEMPLATES := {
	"Gigas": &"stone_golem",
	"Kobold Lord": &"kobold_trooper",
	"Nepent Sovereign": &"little_nepent",
	"Lizardman General": &"lizardman_soldier",
	"Wraith": &"ruin_wraith",
	"Golem": &"stone_golem",
	"Chimera": &"dire_wolf",
	"Drake": &"ember_drake",
	"Executioner": &"lizardman_soldier",
	"Sentinel": &"kobold_trooper",
}

## Milestone floors whose boss is a character rather than an archetype.
const AUTHORED_BOSSES := {
	1: &"illfang",
	10: &"hollow_warden",
	25: &"twin_giant",
}

## What being the floor boss is worth on top of the template's own numbers.
const BOSS_HP := 3.0
const BOSS_ATTACK := 1.2
const BOSS_DEFENSE := 1.15
const BOSS_POISE := 2.5
const BOSS_XP := 4.0
## Every generated boss gets this on top of its template's skills.
const BOSS_SKILL := "res://resources/skills/enemy/rampage.tres"

static var _cache: Dictionary[StringName, EnemyType] = {}


static func get_enemy(id: StringName) -> EnemyType:
	if _cache.has(id):
		return _cache[id]
	var path := ENEMY_PATH % id
	if not ResourceLoader.exists(path):
		push_error("Bestiary: no such enemy '%s'" % id)
		return null
	var type: EnemyType = load(path)
	_cache[id] = type
	return type


## The monsters that roam [param floor_number], strongest-first is not implied --
## the pool is a set, not a ranking.
## Whether [param id] names a template at all, without the error [method get_enemy]
## raises. For validating content that points at enemies by id -- a
## [QuestObjective]'s KILL target -- where a missing one is a question, not a bug.
static func exists(id: StringName) -> bool:
	return id != &"" and ResourceLoader.exists(ENEMY_PATH % id)


static func pool_for_floor(floor_number: int) -> Array[EnemyType]:
	var biome := FloorRegistry.biome_id(floor_number)
	var types: Array[EnemyType] = []
	for id in BIOME_POOLS.get(biome, BIOME_POOLS[&"meadow"]):
		var type := get_enemy(id)
		if type != null:
			types.append(type)
	return types


## The fight one monster standing on the map is worth.
static func single_encounter(type: EnemyType, at_level: int, floor_number := 0) -> Encounter:
	var encounter := Encounter.new()
	encounter.id = StringName("roam_%s" % type.id)
	encounter.display_name = type.label()
	encounter.enemies = [type]
	encounter.level = maxi(1, at_level)
	encounter.floor_number = floor_number
	_set_stage(encounter, maxi(1, floor_number))
	return encounter


## A roaming fight for [param floor_number]. Seeded by the caller so a monster
## placed on the map always leads to the same battle.
static func random_encounter(floor_number: int, rng: RandomNumberGenerator) -> Encounter:
	var pool := pool_for_floor(floor_number)
	if pool.is_empty():
		return null

	var encounter := Encounter.new()
	encounter.id = StringName("floor_%d_roam" % floor_number)
	encounter.level = FloorTuning.enemy_level(floor_number)
	encounter.floor_number = floor_number
	_set_stage(encounter, floor_number)
	# One enemy low down, up to three once the player has a party's worth of
	# skills to spend on them.
	var count := rng.randi_range(1, clampi(1 + floor_number / 15, 1, 3))
	for i in count:
		encounter.enemies.append(pool[rng.randi() % pool.size()])
	encounter.display_name = encounter.enemies[0].label() if count == 1 else "Ambush"
	return encounter


## The fight behind the labyrinth door. Authored floors override the template
## and the name; everything else is assembled from the archetype.
static func boss_encounter(floor_number: int) -> Encounter:
	floor_number = clampi(floor_number, 1, FloorTuning.TOP_FLOOR)
	var definition := FloorRegistry.get_floor(floor_number)

	var template := _boss_template(floor_number)
	if template == null:
		push_error("Bestiary: no boss template for floor %d" % floor_number)
		return null

	var encounter := Encounter.new()
	encounter.id = StringName("floor_%d_boss" % floor_number)
	encounter.level = FloorTuning.boss_level(floor_number)
	encounter.floor_number = floor_number
	encounter.is_boss = true
	encounter.can_flee = false
	_set_stage(encounter, floor_number)
	encounter.boss_name = definition.boss_name if not definition.boss_name.is_empty() \
			else FloorTuning.boss_name(floor_number)
	encounter.display_name = encounter.boss_name
	encounter.enemies.append(template)

	var escort := _escort_for(floor_number)
	if escort != null:
		for i in _escort_count(floor_number):
			encounter.enemies.append(escort)
	return encounter


## Turns a template into the actual boss: bigger, meaner, and worth the climb.
## Escorts stay ordinary, which is what makes the boss read as the boss.
static func build_boss(template: EnemyType, at_level: int, boss_name: String) -> Combatant:
	var boss := Combatant.from_enemy(template, at_level, boss_name)
	boss.max_hp = roundi(boss.max_hp * BOSS_HP)
	boss.hp = boss.max_hp
	boss.attack = roundi(boss.attack * BOSS_ATTACK)
	boss.defense = roundi(boss.defense * BOSS_DEFENSE)
	boss.max_poise = roundi(boss.max_poise * BOSS_POISE)
	boss.poise = boss.max_poise
	boss.xp_reward = roundi(boss.xp_reward * BOSS_XP)
	if ResourceLoader.exists(BOSS_SKILL):
		var rampage: Skill = load(BOSS_SKILL)
		if rampage not in boss.skills:
			boss.skills.append(rampage)
	return boss


static func _boss_template(floor_number: int) -> EnemyType:
	if AUTHORED_BOSSES.has(floor_number):
		return get_enemy(AUTHORED_BOSSES[floor_number])
	var archetype := FloorTuning.boss_archetype(floor_number)
	if not BOSS_TEMPLATES.has(archetype):
		push_error("Bestiary: archetype '%s' has no template" % archetype)
		return null
	return get_enemy(BOSS_TEMPLATES[archetype])


## Illfang brings a Ruin Kobold Sentinel; from the middle of the tower every
## boss brings one of whatever its band is full of.
##
## Capped at one on purpose. Against a party of one, a second full-strength
## escort stops being a complication and becomes an attrition race the player
## cannot win -- measured at roughly 1 win in 20 on floor 100. It can go up when
## the party does (M6).
static func _escort_count(floor_number: int) -> int:
	if floor_number == 1:
		return 1
	return mini(1, (floor_number - 1) / 45)


static func _escort_for(floor_number: int) -> EnemyType:
	if _escort_count(floor_number) <= 0:
		return null
	var pool := pool_for_floor(floor_number)
	return pool[0] if not pool.is_empty() else null


## Everything the battle screen draws of the place: backdrop colour, ground,
## scenery and sky, all from the floor's biome.
static func _set_stage(encounter: Encounter, floor_number: int) -> void:
	encounter.backdrop = _backdrop(floor_number)
	encounter.ground_texture = _ground(floor_number)
	encounter.scenery = _scenery(floor_number)
	var biome := FloorRegistry.get_biome(floor_number)
	encounter.sky_texture = biome.backdrop if biome != null else null


## The battle backdrop, tinted by the floor's biome so a cave fight doesn't look
## like a sky-garden fight.
static func _backdrop(floor_number: int) -> Color:
	var biome := FloorRegistry.get_biome(floor_number)
	var base := Color(0.10, 0.11, 0.17)
	return base * biome.ambient_tint if biome != null else base


## One biome's floor tile, cut out for the battle screen to tile across its
## ground. Cached per biome: the image copy is cheap but it is not free, and a
## climb fights hundreds of battles on the same ten floors of art.
static var _grounds: Dictionary[StringName, Texture2D] = {}


## The ground a fight on [param floor_number] stands on, or null for a biome
## with no tileset behind it -- the screen falls back to a flat backdrop.
static func _ground(floor_number: int) -> Texture2D:
	var biome := FloorRegistry.get_biome(floor_number)
	if biome == null or biome.tile_set == null:
		return null
	if _grounds.has(biome.id):
		return _grounds[biome.id]
	var tile := _cut_tile(biome.tile_set, biome.floor_tile)
	_grounds[biome.id] = tile
	return tile


## How wide a scenery band is, in pixels: the screen's width, so one band spans a
## 320x180 view. A wider window tiles it.
const SCENERY_WIDTH := 320
## How many pieces of the biome's scatter stand at the foot of the band.
const SCENERY_DECOR := 7
## A rock biome's ridge is up to this many tiles high.
const SCENERY_RIDGE := 3
## The eight neighbours, clockwise from north, as offsets and as peering bits.
const BLOB_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const BLOB_NEIGHBOURS: Array[TileSet.CellNeighbor] = [
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
]
static var _sceneries: Dictionary[StringName, Texture2D] = {}


## The horizon a fight on [param floor_number] happens in front of, or null for a
## biome with no tileset. Cached per biome, like the ground.
static func _scenery(floor_number: int) -> Texture2D:
	var biome := FloorRegistry.get_biome(floor_number)
	if biome == null or biome.tile_set == null:
		return null
	if not _sceneries.has(biome.id):
		_sceneries[biome.id] = _compose_scenery(biome)
	return _sceneries[biome.id]


## The biome's own walls, as a band to stand on the horizon. A forest is a tree
## line two deep, staggered like the map's forest edge. Rock is a ridge: columns
## of the wall mass one to three tiles high, each tile picked for its neighbours
## exactly as the map's autotiling would pick it, so the band has the biome's own
## rims and faces wherever its outline turns. A biome with a painted sky (the
## sky's floating lawns) has no wall worth showing, only its scatter. Then a few
## pieces of that scatter at the foot. Laid out from the biome id's hash, so a
## biome always looks the same -- and wrapping round, so a wide window can tile it.
static func _compose_scenery(biome: BiomeKit) -> Texture2D:
	var source := biome.tile_set.get_source(0) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	var sheet := source.texture.get_image()
	if sheet == null:
		return null
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var tile := biome.tile_set.tile_size
	var columns := SCENERY_WIDTH / tile.x
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome.id)

	var rows := 1
	var band: Array = []  # [atlas coords, pixel position]
	if biome.wall_style == BiomeKit.WallStyle.TREES and not biome.tree_tiles.is_empty():
		rows = 3
		for row in 2:
			for i in range(-1, columns / 2 + 1):
				var tree: Vector2i = biome.tree_tiles[rng.randi() % biome.tree_tiles.size()]
				band.append([tree, Vector2i(i * tile.x * 2 + (tile.x if row == 0 else 0), row * tile.y)])
	elif biome.backdrop == null and biome.wall_terrain_set >= 0:
		rows = SCENERY_RIDGE
		var shapes := _blob_tiles(biome, source)
		var heights: Array[int] = []
		while heights.size() < columns:
			var height := rng.randi_range(1, SCENERY_RIDGE)
			for _run in rng.randi_range(2, 4):
				heights.append(height)
		heights.resize(columns)
		for x in columns:
			for y in range(rows - heights[x], rows):
				var mask := 0
				for bit in BLOB_DIRECTIONS.size():
					var next := Vector2i(x, y) + BLOB_DIRECTIONS[bit]
					# Wraps sideways; open above the ridge and in front of it.
					if next.y < rows and next.y >= rows - heights[posmod(next.x, columns)]:
						mask |= 1 << bit
				var coords: Vector2i = shapes.get(_blob_mask(mask), Vector2i(-1, -1))
				if coords != Vector2i(-1, -1):
					band.append([coords, Vector2i(x, y) * tile])

	var image := Image.create_empty(SCENERY_WIDTH, rows * tile.y, false, Image.FORMAT_RGBA8)
	for piece: Array in band:
		_stamp(image, sheet, source, piece[0], piece[1])
	if not biome.decor_tiles.is_empty():
		for i in SCENERY_DECOR:
			var decor: Vector2i = biome.decor_tiles[rng.randi() % biome.decor_tiles.size()]
			var size := source.get_tile_texture_region(decor).size
			var x := (SCENERY_WIDTH * i) / SCENERY_DECOR + rng.randi_range(0, SCENERY_WIDTH / SCENERY_DECOR - size.x)
			_stamp(image, sheet, source, decor, Vector2i(x, rows * tile.y - size.y))
	return ImageTexture.create_from_image(image)


## Every wall tile of [param biome]'s blob by its neighbour mask (bits in
## [constant BLOB_DIRECTIONS] order, corners normalised by [method _blob_mask]).
static func _blob_tiles(biome: BiomeKit, source: TileSetAtlasSource) -> Dictionary[int, Vector2i]:
	var shapes: Dictionary[int, Vector2i] = {}
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data.terrain_set != biome.wall_terrain_set or data.terrain != biome.wall_terrain:
			continue
		var mask := 0
		for bit in BLOB_NEIGHBOURS.size():
			if data.get_terrain_peering_bit(BLOB_NEIGHBOURS[bit]) == biome.wall_terrain:
				mask |= 1 << bit
		mask = _blob_mask(mask)
		if not shapes.has(mask):
			shapes[mask] = coords
	return shapes


## A corner only counts when both sides beside it are wall -- the blob's rule, and
## the reason there are 47 tiles rather than 256.
static func _blob_mask(mask: int) -> int:
	for corner: int in [1, 3, 5, 7]:
		var before := (corner + 7) % 8
		var after := (corner + 1) % 8
		if mask & (1 << before) == 0 or mask & (1 << after) == 0:
			mask &= ~(1 << corner)
	return mask


## Blends one atlas tile (of any size) onto [param image] at [param at].
static func _stamp(image: Image, sheet: Image, source: TileSetAtlasSource, coords: Vector2i,
		at: Vector2i) -> void:
	var region := source.get_tile_texture_region(coords)
	image.blend_rect(sheet, region, at)


## The [param slot]-th semantic tile of [param tile_set] as a texture in its own
## right. An [AtlasTexture] would be the obvious way to name a region, but
## [TextureRect] cannot tile one -- so the pixels are copied out into a plain
## [ImageTexture] instead.
static func _cut_tile(tile_set: TileSet, slot: int) -> Texture2D:
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	var coords := Vector2i(slot, 0)
	if not source.has_tile(coords):
		return null
	var sheet := source.texture.get_image()
	if sheet == null:
		return null
	if sheet.is_compressed():
		sheet.decompress()
	return ImageTexture.create_from_image(sheet.get_region(source.get_tile_texture_region(coords)))
