## NL card instance — one card on the board: a resolved CardTemplate + counters.

class_name CardInstance extends RefCounted

var template: CardTemplate
var counters: int = 0

func _init(t: CardTemplate = null, c: int = 0) -> void:
	template = t
	counters = c


## One-line summary, e.g. "magician(0)" or "<null-template>(2)".
func describe() -> String:
	var name := template.template_name if template != null else "<null-template>"
	return "%s(%d)" % [name, counters]
