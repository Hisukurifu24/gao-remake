class_name ItemLibrary
## Every [Item] in the game, by id.
##
## The bridge between the ids that already float around the codebase --
## [member EnemyType.loot], [Chest.item_id], a [DialogueEffect]'s GIVE_ITEM --
## and the resources they name. Nothing outside this file should build a path to
## a .tres; ask here instead, and a renamed file breaks in one place.
##
## Listed explicitly rather than scanned from the directory, for the same reason
## [SkillLibrary] and [constant FloorRegistry.AUTHORED] are: [code]res://[/code]
## directory listing is unreliable in exported builds.
##
## Adding an item is a .tres in [code]resources/items/[/code], an entry in
## [constant ITEMS], and an icon in [code]tools/gen_placeholder_art.py[/code].

const ITEM_PATH := "res://resources/items/%s.tres"

const ITEMS: PackedStringArray = [
	# Consumables
	"small_potion", "health_potion", "antidote", "whetstone",
	# Weapons
	"bronze_sword", "kobold_blade", "anneal_blade",
	# Armor
	"leather_coat", "blackwyrm_coat",
	# Accessories
	"guard_ring", "swift_charm",
	# Materials -- every monster's drop table points at one of these
	"boar_hide", "wolf_fang", "bat_wing", "nepent_ovule", "kobold_fang",
	"lizard_scale", "drake_scale", "golem_core", "spirit_ash",
	# Key items
	"map_floor_2",
]

static var _cache: Dictionary[StringName, Item] = {}
static var _all: Array[Item] = []


## The item [param id] names, or null (with an error) if there is no such thing.
## A null return is always a content bug -- an id in a loot table or a dialogue
## effect that never got a resource -- so it is loud rather than silent.
static func get_item(id: StringName) -> Item:
	if id == &"":
		return null
	if _cache.has(id):
		return _cache[id]
	var path := ITEM_PATH % id
	if not ResourceLoader.exists(path):
		push_error("ItemLibrary: no such item '%s'" % id)
		return null
	var item: Item = load(path)
	if item == null:
		push_error("ItemLibrary: '%s' failed to load" % id)
		return null
	_cache[id] = item
	return item


static func exists(id: StringName) -> bool:
	return id != &"" and ResourceLoader.exists(ITEM_PATH % id)


## Every item, in the order [constant ITEMS] lists them.
static func all() -> Array[Item]:
	if _all.is_empty():
		for id in ITEMS:
			var item := get_item(StringName(id))
			if item != null:
				_all.append(item)
	return _all
