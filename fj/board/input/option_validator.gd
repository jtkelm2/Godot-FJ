## OptionValidator: tracks the pending PL Prompt and matches incoming
## candidate Options against it. On a content-equality match, forwards the
## *matched* option (the one held in the Prompt's `options` array) — not
## the candidate — so the wire echo is byte-identical per protocol §4.4.
##
## One response per prompt (P2): on a match, pending is cleared. Subsequent
## candidates are silently dropped until the next `set_pending(prompt)`.

class_name OptionValidator extends RefCounted


signal option_accepted(option: Option)


var _pending: Prompt = null


func set_pending(prompt: Prompt) -> void:
	_pending = prompt


func clear_pending() -> void:
	_pending = null


func consider(candidate: Option) -> void:
	if _pending == null:
		return
	for opt in _pending.options:
		if opt.equals(candidate):
			# Forward the MATCHED option (not the candidate) so the wire
			# response is the byte-identical echo.
			option_accepted.emit(opt)
			_pending = null
			return
	# No match — silently drop. The user clicked something not in the
	# prompt's option set; the server will neither time out nor re-prompt
	# (P1 / P3 in protocol §5.2).
