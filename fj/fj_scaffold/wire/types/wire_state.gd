## Wire form of the player view, per protocol §3.2.
##
## Per the Python sketch, WireState uses NL identities (PID, Phase, SlotID,
## Role, HP) for keys/enums and wire-shape values (WireSlotInfo) for content.
## Catalog has already done slot-name → SlotID resolution by the time this
## is constructed; only the per-slot card content is kept in WL form
## (WireCardInfo references cards by name string, not by resolved CardTemplate).

class_name WireState extends RefCounted

var role: Dictionary[NLEnums.PID, State.Role] = {}
var hp: Dictionary[NLEnums.PID, State.HP] = {}
var phase: NLEnums.Phase = NLEnums.Phase.NONE
var priority: NLEnums.PID = NLEnums.PID.RED
var slots: Dictionary[SlotID, WireSlotInfo] = {}
