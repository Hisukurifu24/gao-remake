extends Node
## What the player is carrying, and what they are wearing.
##
## The bag is an ordered list of [ItemStack]s with a hard slot cap: things that
## stack share a slot, equipment never does. Everything that hands the player an
## item -- loot, chests, dialogue -- goes through [method add], and everything
## that reads the bag goes through the accessors below. No UI touches [member
## _stacks], for the same reason no UI touches [CombatManager]'s turn order.
##
## [b]Two signals, one direction each.[/b] [signal EventBus.item_granted] is the
## world saying "here, have this" -- combat loot, a chest, a dialogue reward. It
## is a *request*, and this autoload is the only thing listening to it.
## [signal EventBus.item_added] is this autoload replying "it is in the bag",
## which is what UI and (in M5) quest objectives listen to. Keeping them apart
## is what stops a full bag from silently reporting a success, and what stops
## [method add] from re-triggering itself.
##
## Equipment [b]leaves the bag[/b] when worn: a slot is a place, not a flag. That
## way the bag count is the truth, and unequipping into a full bag is refused
## rather than quietly deleting a sword.

## Bag slots. Not weight -- weight means every item needs a mass and the player
## needs a number to watch, which is a system's worth of tuning for a game whose
## inventory is currently potions and one coat.
const CAPACITY := 24

## The wearable slots, in the order the equipment panel lists them. Must match
## the values in [constant Item.EQUIP_SLOTS].
const SLOTS: Array[StringName] = [&"weapon", &"armor", &"accessory"]

var _stacks: Array[ItemStack] = []
var _equipped: Dictionary[StringName, Item] = {}


func _ready() -> void:
	EventBus.item_granted.connect(_on_item_granted)


# --- reading ---------------------------------------------------------------

## The bag, in slot order. The array is a copy; the [ItemStack]s in it are not,
## so treat them as read-only.
func stacks() -> Array[ItemStack]:
	return _stacks.duplicate()


func used_slots() -> int:
	return _stacks.size()


func is_full() -> bool:
	return _stacks.size() >= CAPACITY


func is_empty() -> bool:
	return _stacks.is_empty()


## How many of [param id] are in the bag. Does not count a worn copy -- what you
## are wearing is not what you are carrying.
func count(id: StringName) -> int:
	var total := 0
	for stack in _stacks:
		if stack.item.id == id:
			total += stack.count
	return total


func has(id: StringName, amount := 1) -> bool:
	return count(id) >= amount


## Whether [param amount] of [param item] would fit right now. Chests ask before
## opening: a container that hands you something you cannot hold has destroyed
## it, and the flag saying it was opened outlives the loss.
func fits(item: Item, amount := 1) -> bool:
	if item == null or amount <= 0:
		return false
	var room := (CAPACITY - _stacks.size()) * item.stack_limit()
	for stack in _stacks:
		if stack.item == item:
			room += stack.space_left()
	return room >= amount


## Every stack of a kind, for the combat item menu and the equipment picker.
func stacks_of_kind(kind: Item.Kind) -> Array[ItemStack]:
	return _stacks.filter(func(s: ItemStack) -> bool: return s.item.kind == kind)


## What the player could actually drink right now. [param in_battle] picks which
## of the two usable flags applies; either way an item that does nothing at all
## is not offered.
func usable_stacks(in_battle: bool) -> Array[ItemStack]:
	return _stacks.filter(func(s: ItemStack) -> bool:
		if not s.item.is_consumable() or not s.item.has_effect():
			return false
		return s.item.usable_in_battle if in_battle else s.item.usable_in_field)


# --- adding and removing ---------------------------------------------------

## Puts [param amount] of [param item] in the bag and returns how many fit.
## Fills part-used stacks first, then takes new slots until the bag is full.
##
## Announces only what was actually accepted: a caller that grants 5 into two
## free slots' worth of space is told 2, and [signal EventBus.inventory_full]
## fires for the rest.
func add(item: Item, amount := 1) -> int:
	if item == null or amount <= 0:
		return 0

	var remaining := amount
	for stack in _stacks:
		if remaining <= 0:
			break
		if stack.item == item:
			remaining -= stack.accept(remaining)

	while remaining > 0 and not is_full():
		var taken := mini(remaining, item.stack_limit())
		_stacks.append(ItemStack.new(item, taken))
		remaining -= taken

	var accepted := amount - remaining
	if accepted > 0:
		EventBus.item_added.emit(item.id, accepted)
		EventBus.inventory_changed.emit()
	if remaining > 0:
		EventBus.inventory_full.emit(item.id, remaining)
	return accepted


## [method add] by id, for the callers that only ever had an id: loot tables,
## dialogue effects, chests.
func add_id(id: StringName, amount := 1) -> int:
	return add(ItemLibrary.get_item(id), amount)


## Takes [param amount] of [param id] out of the bag and returns how many it
## took. [b]All or nothing[/b]: asking for more than there is removes none of it
## and returns 0. A caller spending three of something and silently getting two
## taken has a corrupted bag and no way to notice, which is the worse failure.
##
## Drains the smallest stacks first, so partial piles get consolidated rather
## than multiplied.
func remove(id: StringName, amount := 1) -> int:
	if amount <= 0 or count(id) < amount:
		return 0

	var matching := _stacks.filter(func(s: ItemStack) -> bool: return s.item.id == id)
	matching.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return a.count < b.count)

	var remaining := amount
	for stack in matching:
		if remaining <= 0:
			break
		remaining -= stack.take(remaining)
	_prune()

	EventBus.item_removed.emit(id, amount)
	EventBus.inventory_changed.emit()
	return amount


## Throws away one whole stack -- that stack, not "that many of that item", so
## dropping the small pile never eats into the big one. The only way to lose a
## key item is deliberately, which is to say: not this way.
func drop_stack(stack: ItemStack) -> bool:
	if stack == null or stack not in _stacks or stack.item.kind == Item.Kind.KEY:
		return false
	var dropped := stack.count
	var id := stack.item.id
	stack.take(dropped)
	_prune()
	EventBus.item_removed.emit(id, dropped)
	EventBus.inventory_changed.emit()
	return true


## Drops stacks that have been emptied. Slots are only held by things that are
## actually in them.
func _prune() -> void:
	_stacks = _stacks.filter(func(s: ItemStack) -> bool: return s.count > 0)


func clear() -> void:
	_stacks.clear()
	_equipped.clear()
	GameState.refresh_vitals()
	EventBus.inventory_changed.emit()


# --- using -----------------------------------------------------------------

## Spends one [param id] on the player, out in the world. Only the healing part
## of an item lands here: statuses ride on a [Combatant] and there is no such
## thing outside a fight, which is why an item that only applies one declares
## [code]usable_in_field = false[/code] and is refused.
##
## Returns false and spends nothing if the item cannot be used or would do
## nothing -- drinking a full-health potion is a waste, not a mechanic.
func use(id: StringName) -> bool:
	var item := ItemLibrary.get_item(id)
	if item == null or not item.is_consumable() or not item.usable_in_field:
		return false
	if not has(id) or item.heal_amount(GameState.total_max_hp()) <= 0:
		return false
	if GameState.hp >= GameState.total_max_hp():
		return false

	GameState.set_hp(GameState.hp + item.heal_amount(GameState.total_max_hp()))
	return consume(id)


## Spends one [param id] without deciding what it did. [CombatManager] uses this:
## in a fight the item lands on a [Combatant], so the runner applies the effect
## and this only empties the bottle.
func consume(id: StringName) -> bool:
	if remove(id, 1) <= 0:
		return false
	EventBus.item_used.emit(id)
	return true


# --- equipment -------------------------------------------------------------

func equipped(slot: StringName) -> Item:
	return _equipped.get(slot, null)


func is_equipped(item: Item) -> bool:
	return item != null and _equipped.get(item.slot(), null) == item


## Wears [param item], moving it out of the bag and whatever it replaces back
## into it. Refused if the item is not wearable or is not actually carried.
func equip(item: Item) -> bool:
	if item == null or not item.is_equipment() or not has(item.id):
		return false
	# The incoming item vacates a slot before the outgoing one needs it, so the
	# swap can never fail halfway and leave the player holding neither.
	if remove(item.id, 1) <= 0:
		return false

	var slot := item.slot()
	var replaced := _equipped.get(slot, null) as Item
	_equipped[slot] = item
	if replaced != null:
		add(replaced, 1)

	GameState.refresh_vitals()
	EventBus.item_equipped.emit(slot, item.id)
	EventBus.inventory_changed.emit()
	return true


## Takes off whatever is in [param slot] and returns it to the bag. Refused when
## the bag is full: gear has to have somewhere to go.
func unequip(slot: StringName) -> bool:
	var item := _equipped.get(slot, null) as Item
	if item == null:
		return false
	if add(item, 1) <= 0:
		return false

	_equipped.erase(slot)
	GameState.refresh_vitals()
	EventBus.item_equipped.emit(slot, &"")
	EventBus.inventory_changed.emit()
	return true


## The sum of every worn bonus to one stat. [GameState] folds these into its
## [code]total_*[/code] accessors, which is the only place combat reads stats
## from -- gear never reaches into [CombatMath] or [Combatant].
func bonus(stat: StringName) -> int:
	var total := 0
	for slot in _equipped:
		var item := _equipped[slot] as Item
		if item == null:
			continue
		match stat:
			&"attack": total += item.attack_bonus
			&"defense": total += item.defense_bonus
			&"speed": total += item.speed_bonus
			&"max_hp": total += item.max_hp_bonus
	return total


# --- housekeeping ----------------------------------------------------------

## Sorts the bag: equipment first, then consumables, then materials and keys;
## rarest first within a kind; alphabetical within a rarity. Purely cosmetic,
## and the one bag operation that changes nothing but the order.
func sort() -> void:
	_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		if a.item.kind != b.item.kind:
			return _kind_rank(a.item.kind) < _kind_rank(b.item.kind)
		if a.item.rarity != b.item.rarity:
			return a.item.rarity > b.item.rarity
		return a.item.label() < b.item.label())
	EventBus.inventory_changed.emit()


## Moves the stack at [param from] into slot [param to]. Three outcomes, in the
## order they are tried:
##
## [b]Merge[/b] when both slots hold the same item and the target has room --
## dropping five potions on fifteen makes twenty, and a remainder stays behind
## rather than overflowing.
## [b]Move to the back[/b] when [param to] is past the last used slot: the bag is
## a compact list, so every empty slot is the same place and there is nothing
## there to swap with.
## [b]Swap[/b] otherwise, which is what keeps every other stack where the player
## left it.
##
## Order is bag state, not a view preference -- [method sort] already rewrites it
## and the screen only ever reads [method stacks]. Returns whether anything moved.
func move_stack(from: int, to: int) -> bool:
	if from < 0 or from >= _stacks.size() or to < 0 or to >= CAPACITY or from == to:
		return false

	var moving := _stacks[from]
	if to >= _stacks.size():
		if from == _stacks.size() - 1:
			return false  # Already the last stack: dropping it past the end is a no-op.
		_stacks.remove_at(from)
		_stacks.append(moving)
	else:
		var target := _stacks[to]
		if target.item == moving.item and not target.is_full():
			moving.take(target.accept(moving.count))
			_prune()
		else:
			_stacks[to] = moving
			_stacks[from] = target

	EventBus.inventory_changed.emit()
	return true


func _kind_rank(kind: Item.Kind) -> int:
	match kind:
		Item.Kind.WEAPON: return 0
		Item.Kind.ARMOR: return 1
		Item.Kind.ACCESSORY: return 2
		Item.Kind.CONSUMABLE: return 3
		Item.Kind.KEY: return 4
		_: return 5


## The one listener on [signal EventBus.item_granted]. Everything that hands the
## player something -- [CombatManager] loot, [Chest], [DialogueEffect] -- emits
## there rather than calling [method add], so none of them has to know Inventory
## exists or handle a full bag.
func _on_item_granted(id: StringName, amount: int) -> void:
	add_id(id, amount)
