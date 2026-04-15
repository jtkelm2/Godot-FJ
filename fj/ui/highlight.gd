class_name Highlight
extends RefCounted

## Decoration level a highlightable UI object (Slot, Card, WeaponSlot) can be
## asked to display.
##
##   LOWLIGHT  — no decoration (default).
##   CONTEXT   — a pointing arrow below the object, drawing attention without
##               suggesting selectability. Used for `prompt.context` entries
##               per protocol §3.3.
##   HIGHLIGHT — a pulsing outline/tint, indicating a selectable prompt option.
enum Level { LOWLIGHT, CONTEXT, HIGHLIGHT }
