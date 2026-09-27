class_name UiLayout
extends RefCounted
## Layout helpers the screens share, so a fix to one reaches all of them.


## Collapses a shrink-wrapped panel onto its contents. A [PanelContainer] grows
## to fit but never shrinks back when the next speaker has a shorter name, so the
## panel is reset to a one-pixel rect and the container's minimum size does the
## rest. Which edge stays put is the panel's grow direction: [code]END[/code]
## keeps the left/top edge, [code]BEGIN[/code] the right/bottom one, and
## [code]BOTH[/code] the middle -- so a panel anchored at the corner it grows away
## from stays in that corner, and a centred one stays centred.
static func shrink_wrap(panel: Control) -> void:
	var h := _collapse(panel.offset_left, panel.offset_right, panel.grow_horizontal)
	panel.offset_left = h.x
	panel.offset_right = h.y
	var v := _collapse(panel.offset_top, panel.offset_bottom, panel.grow_vertical)
	panel.offset_top = v.x
	panel.offset_bottom = v.y


static func _collapse(begin: float, end: float, grow: Control.GrowDirection) -> Vector2:
	match grow:
		Control.GROW_DIRECTION_BEGIN:
			return Vector2(end - 1.0, end)
		Control.GROW_DIRECTION_BOTH:
			var middle := (begin + end) * 0.5
			return Vector2(middle - 0.5, middle + 0.5)
	return Vector2(begin, begin + 1.0)
