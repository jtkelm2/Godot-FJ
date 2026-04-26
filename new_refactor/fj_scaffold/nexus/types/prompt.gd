## PL language: typed request for a player decision. NL — wire-agnostic.
##
## `Notify` is a separate protocol message type (§3.4), not part of PL.
## Colocated for fewer-files economy; consumers access it as `Prompt.Notify`.

class_name Prompt extends RefCounted


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

func _init(t: String = "", opts: Array[Option] = [], ctx: Array[Option] = []) -> void:
	text = t
	options = opts
	context = ctx
