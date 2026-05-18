## OptionValidator: tracks the pending PL Prompt and matches incoming
## candidate Option arrays against it. On a content-equality match, forwards
## the *matched* options (the ones held in the Prompt's `options` array) —
## not the candidates — so the wire echo is byte-identical per protocol §4.4.
##
## A candidate is always `Array[Option]`. Length-1 arrays are single-select;
## length>=2 are multi-select. The validator checks `len == _pending.must_select`
## then multi-set-matches each candidate against the offered pool, consuming
## each offered entry once — so duplicate offerings allow duplicate picks per
## protocol §3.3.
##
## One response per prompt (P2): on a match, pending is cleared. Subsequent
## candidates are silently dropped until the next `set_pending(prompt)`.

class_name OptionValidator extends RefCounted


signal option_accepted(options: Array[Option])


var _pending: Prompt = null


func set_pending(prompt: Prompt) -> void:
	_pending = prompt


func clear_pending() -> void:
	_pending = null


func consider(candidates: Array[Option]) -> void:
	if _pending == null:
		return
	if candidates.size() != _pending.must_select:
		# Wrong count — silently drop. Single-clicks during a pending
		# multi-select prompt (or vice versa) fall through here.
		return

	# Multi-set match: consume each offered option at most once. Iterate a
	# mutable copy of `_pending.options`; for each candidate, find an equal
	# entry and remove it. Any unmatched candidate fails the whole batch.
	var available: Array[Option] = _pending.options.duplicate()
	var matched: Array[Option] = []
	for cand in candidates:
		var found_idx := -1
		for j in available.size():
			if available[j].equals(cand):
				found_idx = j
				break
		if found_idx == -1:
			return
		matched.append(available[found_idx])
		available.remove_at(found_idx)

	option_accepted.emit(matched)
	_pending = null
