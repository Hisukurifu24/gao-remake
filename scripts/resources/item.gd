class_name Item
extends Resource
## One kind of thing the player can carry: a potion, a sword, a boar hide.
##
## Items are pure data, like [Skill] and [StatusEffect]. [Inventory] knows how to
## hold them, [CombatManager] knows how to drink one, and the equipment screen
## knows how to wear one -- none of them know what any *particular* item is, so
## adding a sword is a .tres plus a line in [ItemLibrary].
##
## Two rules the numbers here follow, both borrowed from [StatusEffect]:
## [member heal_percent] is a percentage of the drinker's max HP rather than
## flat points, because a flat 20-point potion is everything on floor 2 and
## nothing on floor 90; and equipment bonuses are flat *additions* to the
## player's base stats, because mitigation is a ratio ([CombatMath]) and a
## multiplier on top of a ratio compounds out of control across 100 floors.

enum Kind {
	CONSUMABLE,  ## Spent on use. See the Consumable group.
	WEAPON,
	ARMOR,
	ACCESSORY,
	MATERIAL,    ## Crafting and quest fodder. Does nothing on its own.
	KEY,         ## Quest items and maps. Never dropped, never sold.
}

## Purely how an item reads: its name colour and its place in a sorted bag.
## Rarity is not a stat -- a Legendary with bad numbers is still bad.
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Which [Inventory] slot each wearable kind occupies. Kinds absent from this
## table cannot be equipped, which is the whole test -- see [method slot].
const EQUIP_SLOTS := {
	Kind.WEAPON: &"weapon",
	Kind.ARMOR: &"armor",
	Kind.ACCESSORY: &"accessory",
}

const RARITY_COLORS: Array[Color] = [
	Color(0.78, 0.80, 0.86),  # common
	Color(0.52, 0.84, 0.56),  # uncommon
	Color(0.44, 0.70, 0.98),  # rare
	Color(0.76, 0.56, 0.96),  # epic
	Color(0.98, 0.74, 0.36),  # legendary
]

const RARITY_NAMES: PackedStringArray = [
	"Common", "Uncommon", "Rare", "Epic", "Legendary",
]

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## The 16x16 icon drawn in the bag grid.
@export var icon: Texture2D
@export var kind: Kind = Kind.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
## How many fit in one slot. Ignored for equipment, which never stacks --
## see [method stack_limit].
@export_range(1, 999) var max_stack := 99

@export_group("Equipment")
## Added to the player's base stat while worn. May be negative: a heavy shield
## that costs speed is a real trade, and the ratio-based mitigation in
## [CombatMath] keeps it a readable one.
@export var attack_bonus := 0
@export var defense_bonus := 0
@export var speed_bonus := 0
@export var max_hp_bonus := 0

@export_group("Consumable")
## Percent of the *drinker's* max HP restored. Percent, never flat -- a potion
## should still be worth a turn on floor 90.
@export_range(0, 100) var heal_percent := 0
## Applied to whoever drinks it. Buffs work here exactly as they do on a skill.
@export var applies: StatusEffect
## Strips every debuff currently riding on the drinker.
@export var cures_debuffs := false
@export var usable_in_battle := true
@export var usable_in_field := true


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


func is_equipment() -> bool:
	return EQUIP_SLOTS.has(kind)


## The slot this goes in, or [code]&""[/code] if it is not wearable.
func slot() -> StringName:
	return EQUIP_SLOTS.get(kind, &"")


func is_consumable() -> bool:
	return kind == Kind.CONSUMABLE


## Whether drinking this would actually do anything. A consumable that heals
## nothing, applies nothing and cures nothing is content missing its numbers,
## not a valid item, and [Inventory] refuses to spend one.
func has_effect() -> bool:
	return heal_percent > 0 or applies != null or cures_debuffs


## Equipment never stacks: three swords are three slots, so any one of them can
## be worn without splitting a pile first.
func stack_limit() -> int:
	return 1 if is_equipment() else maxi(1, max_stack)


## Points of HP this restores to something with [param max_hp].
func heal_amount(max_hp: int) -> int:
	if heal_percent <= 0:
		return 0
	return maxi(1, roundi(max_hp * heal_percent / 100.0))


func rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


func rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func kind_name() -> String:
	match kind:
		Kind.CONSUMABLE: return "Consumable"
		Kind.WEAPON: return "Weapon"
		Kind.ARMOR: return "Armor"
		Kind.ACCESSORY: return "Accessory"
		Kind.KEY: return "Key Item"
		_: return "Material"


## The stat line shown under an item in the bag: "ATK +6  SPD -1", or the
## potion's effect. Empty for something that does nothing but sit there.
func summary() -> String:
	var parts := PackedStringArray()
	if is_equipment():
		for pair in [["ATK", attack_bonus], ["DEF", defense_bonus],
				["SPD", speed_bonus], ["HP", max_hp_bonus]]:
			var amount: int = pair[1]
			if amount != 0:
				parts.append("%s %+d" % [pair[0], amount])
	else:
		if heal_percent > 0:
			parts.append("Heals %d%%" % heal_percent)
		if cures_debuffs:
			parts.append("Cures")
		if applies != null:
			parts.append(applies.label())
	return "  ".join(parts)
