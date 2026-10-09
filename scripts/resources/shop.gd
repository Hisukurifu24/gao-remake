class_name Shop
extends Resource
## A shop counter: what it can sell, and the rules for buying and selling there.
##
## Flow and view are separate, as everywhere: this decides what is on the shelf
## and whether a trade goes through, and [code]ui/shop_screen.tscn[/code] only
## draws it and calls [method buy] / [method sell] back -- so the inventory test
## shops with no screen at all.
##
## [b]Prices are the item's, not the shop's[/b] ([member Item.price]), and so is
## when it reaches the shelf ([member Item.shop_floor]). A shop only says which
## items it carries. That keeps one price per item in the game and one rule for
## when stock climbs, read off progression rather than off a table here.

@export var id: StringName = &""
## The counter's name, the screen's title: "Outfitter's Stall".
@export var display_name := ""
## Who is behind it, and what they say when you walk up.
@export var keeper := ""
@export_multiline var greeting := ""
## Item ids this counter carries. Which of them are on the shelf right now is
## [method stock]'s answer.
@export var wares: Array[StringName] = []


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


## What is on the shelf: the wares whose floor the player has reached, in the
## order the shop lists them.
func stock() -> Array[Item]:
	var shelf: Array[Item] = []
	var reached := GameState.highest_floor_reached()
	for ware in wares:
		var item := ItemLibrary.get_item(ware) if ItemLibrary.exists(ware) else null
		if item != null and item.is_stocked() and item.shop_floor <= reached:
			shelf.append(item)
	return shelf


## Why buying one [param item] would be refused, or empty if it would go
## through. The screen greys a row out on exactly this, so the two can't disagree.
func refusal(item: Item) -> String:
	if item == null or item not in stock():
		return "Not on the shelf."
	if not GameState.can_afford(item.price):
		return "Not enough col."
	if not Inventory.fits(item, 1):
		return "No room in your bag."
	return ""


## Buys one [param item]. All or nothing: room in the bag is checked before a coin
## leaves the purse, and the purse is checked before anything goes in the bag.
func buy(item: Item) -> bool:
	if not refusal(item).is_empty():
		return false
	if not GameState.spend_col(item.price):
		return false
	Inventory.add(item, 1)
	return true


## The bag's stacks this counter would buy from, in bag order. Every shop buys
## anything sellable -- a hide is worth picking up wherever you are.
func sellable() -> Array[ItemStack]:
	return Inventory.stacks().filter(func(s: ItemStack) -> bool: return s.item.is_sellable())


## Sells one [param item] out of the bag for [method Item.sell_price]. Worn gear
## is not in the bag, so it can't be sold out from under you.
func sell(item: Item) -> bool:
	if item == null or not item.is_sellable():
		return false
	if Inventory.remove(item.id, 1) != 1:
		return false
	EventBus.col_granted.emit(item.sell_price())
	return true
