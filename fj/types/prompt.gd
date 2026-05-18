## PL language: typed request for a player decision. NL — wire-agnostic.
##
## `Notify` is a separate protocol message type (§3.4), not part of PL.
## Colocated for fewer-files economy; consumers access it as `Prompt.Notify`.

class_name Prompt extends NL


class Notify extends RefCounted:
	var kind: String
	var text: String
	func _init(k: String = "", t: String = "") -> void:
		kind = k
		text = t


var text: String = ""
var options: Array[Option] = []
## §3.3: rendered for visual context but MUST NOT be echoed as a response.
var context: Array[Option] = []
## §3.3: exactly this many options must be selected. Default 1 preserves the
## legacy single-select contract (the field is omitted on the wire when == 1).
var must_select: int = 1

func _init(t: String = "", opts: Array[Option] = [], ctx: Array[Option] = [], n: int = 1) -> void:
	text = t
	options = opts
	context = ctx
	must_select = n
