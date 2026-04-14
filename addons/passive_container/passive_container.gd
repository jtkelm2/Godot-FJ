@tool
class_name PassiveContainer
extends Container

## A Container that shrink-wraps its children without imposing a layout
## discipline (no directional flow, no decoration). It serves two purposes
## and no more:
##
##   1. Reports its own minimum size as the combined minimum of its
##      children — so parent layouts accommodate whatever's inside.
##   2. Fits each Control child to its own rect — so the child is visible
##      and reacts to its own anchors/inner layout from there.
##
## Use this when you want Godot's min-size propagation up the layout tree
## without adopting a concrete Container subclass's flow (HBox/VBox/Grid/
## Margin/etc.). It is the minimal viable "Container that pulls its size
## from inside, not from outside."
##
## No state, no signals, no configuration.


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for child in get_children():
			if child is Control:
				fit_child_in_rect(child, Rect2(Vector2.ZERO, size))


func _get_minimum_size() -> Vector2:
	var result := Vector2.ZERO
	for child in get_children():
		if child is Control:
			result = result.max((child as Control).get_combined_minimum_size())
	return result
