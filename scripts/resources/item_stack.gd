class_name ItemStack
extends RefCounted
## A pile of one [Item] in one bag slot.
##
## Runtime-only, like [Combatant]: the [Item] is the shared resource everybody
## reads, this is the *count of them this player is carrying*, and it dies with
## the save. [Inventory] owns every stack in existence.
##
## A piece of equipment is a stack of one, so a stack is also [i]that[/i] sword:
## [member plus] is how far the smith has sharpened this copy, and it travels with
## the stack into an equipment slot and back. Two Bronze Swords are two stacks and
## can be +0 and +3. The M7 save has to keep it.

var item: Item
var count := 0
## Smith enhancement, +0 to [method Item.max_plus]. Only equipment carries one.
var plus := 0


func _init(of_item: Item, amount := 1) -> void:
	item = of_item
	count = amount


func is_full() -> bool:
	return count >= item.stack_limit()


func space_left() -> int:
	return maxi(0, item.stack_limit() - count)


## Adds up to [param amount] and returns how many actually fit.
func accept(amount: int) -> int:
	var taken := mini(amount, space_left())
	count += taken
	return taken


## Removes up to [param amount] and returns how many were actually there.
func take(amount: int) -> int:
	var removed := mini(amount, count)
	count -= removed
	return removed


func label() -> String:
	var name := item.label_at(plus)
	return name if count <= 1 else "%s x%d" % [name, count]


## The stat line with this copy's enhancement folded in.
func summary() -> String:
	return item.summary(plus)
