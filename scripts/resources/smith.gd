class_name Smith
extends Resource
## A smith's forge: SAO's enhancement, +1 at a time, for Col and materials, and it
## can fail.
##
## The rules live here and nowhere else, like a [Shop]'s: [method refusal] says
## why an attempt would be refused, [method attempt] makes one. The forge screen
## only draws them, so the inventory test works a forge with no screen at all.
## The +N itself is the stack's ([member ItemStack.plus]) and reaches combat
## through [method Inventory.bonus], never through anything here.
##
## [b]An attempt[/b] to take a piece from +n to +n+1 costs Col -- a quarter of
## the piece's price for every level it is going to, so the deep end of a good
## blade is the Col sink of the climb -- and n+1 monster materials of at least
## the tier that step wants: common up to +3, uncommon to +6, rare beyond. The
## higher floors' drops are what take a blade further, which keeps the floor-10
## blade worth carrying to floor 60. It succeeds on [constant ODDS][n] percent,
## and every extra material put in raises that by [constant EXTRA_ODDS] -- the
## materials' sink, and the one choice the player makes at the counter.
## Failing costs what was put in and nothing else: the piece keeps its +n.

enum Outcome { REFUSED, FAILED, SUCCEEDED }

## Percent chance of the step from +n, by n.
const ODDS: Array[int] = [100, 90, 80, 70, 60, 50, 40, 35, 30, 25]
## Percent each extra material adds.
const EXTRA_ODDS := 10
## Col per level, as a share of the piece's price.
const COST_SHARE := 0.25
const MIN_COST := 10
## The material tier each step wants, as the [enum Item.Rarity] the step from +n
## needs at least: +1 to +3 common, +4 to +6 uncommon, the rest rare.
const TIER_FROM: Array[int] = [0, 0, 0, 1, 1, 1, 2, 2, 2, 2]

@export var id: StringName = &""
## The forge's name, the screen's title: "Nezha's Forge".
@export var display_name := ""
@export var keeper := ""
@export_multiline var greeting := ""


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


## Col for the step from [param stack]'s current +n.
static func cost(stack: ItemStack) -> int:
	return maxi(MIN_COST, roundi(stack.item.price * COST_SHARE * (stack.plus + 1)))


## How many materials the step from +n takes, before extras.
static func materials_needed(stack: ItemStack) -> int:
	return stack.plus + 1


## The least rarity a material must have to count for the step from +n.
static func tier(stack: ItemStack) -> Item.Rarity:
	return TIER_FROM[clampi(stack.plus, 0, TIER_FROM.size() - 1)] as Item.Rarity


## Whether [param item] is a material the forge takes for [param stack]'s step.
## Monster drops only: a key item is never fed to the fire, and a quest's raid tag
## is a key item.
static func takes(item: Item, stack: ItemStack) -> bool:
	return item.kind == Item.Kind.MATERIAL and item.is_sellable() and item.rarity >= tier(stack)


## How many materials in the bag would count for the step.
static func materials_held(stack: ItemStack) -> int:
	var held := 0
	for pile in Inventory.stacks():
		if takes(pile.item, stack):
			held += pile.count
	return held


## Percent chance of the step with [param extra] materials over the minimum.
static func odds(stack: ItemStack, extra := 0) -> int:
	return mini(100, ODDS[clampi(stack.plus, 0, ODDS.size() - 1)] + EXTRA_ODDS * maxi(0, extra))


## The most extras worth putting in: enough to reach 100%, or as many as are held.
static func max_extra(stack: ItemStack) -> int:
	var base := ODDS[clampi(stack.plus, 0, ODDS.size() - 1)]
	var useful := ceili((100 - base) / float(EXTRA_ODDS))
	return clampi(materials_held(stack) - materials_needed(stack), 0, useful)


## Which materials the attempt would take, cheapest first, as id -> count: the
## player chooses how many, the forge chooses which, and it never burns a drake
## scale while a boar hide would do.
static func materials_for(stack: ItemStack, extra := 0) -> Dictionary[StringName, int]:
	var want := materials_needed(stack) + maxi(0, extra)
	var kinds: Dictionary[StringName, Item] = {}
	for pile in Inventory.stacks():
		if takes(pile.item, stack):
			kinds[pile.item.id] = pile.item
	var order: Array = kinds.values()
	order.sort_custom(func(a: Item, b: Item) -> bool:
		return a.price < b.price if a.price != b.price else String(a.id) < String(b.id))
	var taken: Dictionary[StringName, int] = {}
	for item in order:
		if want <= 0:
			break
		var use := mini(want, Inventory.count(item.id))
		taken[item.id] = use
		want -= use
	return taken


## Why the step would be refused, or empty if it would be attempted.
static func refusal(stack: ItemStack, extra := 0) -> String:
	if stack == null or not stack.item.is_equipment():
		return "Nothing to work on."
	if stack.plus >= stack.item.max_plus():
		return "As sharp as it will go (+%d)." % stack.item.max_plus()
	if materials_held(stack) < materials_needed(stack) + maxi(0, extra):
		return "Needs %d %s materials." % [materials_needed(stack) + maxi(0, extra),
				Item.RARITY_NAMES[tier(stack)].to_lower() + ("+" if tier(stack) < Item.Rarity.RARE else "")]
	if not GameState.can_afford(cost(stack)):
		return "Not enough col (%d)." % cost(stack)
	return ""


## Works [param stack] once. Everything is spent before the roll, win or lose.
## [param roll] is a percentile in [0, 100) to use instead of a random one -- the
## tests' way of deciding the outcome.
static func attempt(stack: ItemStack, extra := 0, roll := -1.0) -> Outcome:
	if not refusal(stack, extra).is_empty():
		return Outcome.REFUSED
	var chance := odds(stack, extra)
	var spend := materials_for(stack, extra)
	if not GameState.spend_col(cost(stack)):
		return Outcome.REFUSED
	for id in spend:
		Inventory.remove(id, spend[id])
	var rolled := roll if roll >= 0.0 else randf() * 100.0
	if rolled >= chance:
		return Outcome.FAILED
	Inventory.enhance(stack)
	return Outcome.SUCCEEDED
