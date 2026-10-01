class_name FogOfWar
extends RefCounted
## What the player can see from where they stand, cell by cell.
##
## Over most of a map the screen shows everything in camera, and this decides only
## what counts as *explored*: the cells within
## [constant RADIUS] that a straight line reaches without crossing a wall. A wall
## is seen, what is behind it is not, so the map of a labyrinth shows the passages
## you have walked and the walls round them -- not the one beyond the wall that
## you have not found the way into. Inside a labyrinth it also decides what is
## *drawn* -- the same cells are what [Darkness] leaves lit.

## Seven cells: comfortably inside the 20x11 the camera shows, so nothing is
## recorded as explored that was not on screen.
const RADIUS := 7


## Every cell within [param radius] of [param origin] that a line reaches without
## passing through a cell [param blocks] says is solid. The solid cell a line
## stops at is included -- you see the wall itself.
static func visible_from(origin: Vector2i, radius: int, blocks: Callable) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	var limit := radius * radius + radius  # a rounder disc than r^2 alone
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > limit:
				continue
			var target := origin + Vector2i(dx, dy)
			if _clear_between(origin, target, blocks):
				seen.append(target)
	return seen


## True when nothing between the two cells (both ends excluded) blocks. Bresenham.
static func _clear_between(from: Vector2i, to: Vector2i, blocks: Callable) -> bool:
	var delta := Vector2i(absi(to.x - from.x), -absi(to.y - from.y))
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var error := delta.x + delta.y
	var cell := from
	while cell != to:
		var doubled := error * 2
		if doubled >= delta.y:
			error += delta.y
			cell.x += step.x
		if doubled <= delta.x:
			error += delta.x
			cell.y += step.y
		if cell != to and blocks.call(cell):
			return false
	return true
