## Highlight decoration levels for cards / slots / weapon slots.
## Renderer-internal — no NL semantics. Conductor maps PL options to highlight
## levels and feeds them to the Renderer as primitive calls.
##
## Levels:
##   LOWLIGHT  — no decoration (default).
##   CONTEXT   — pointing arrow below the object. Used for `prompt.context`
##               entries per protocol §3.3 (rendered but not selectable).
##   HIGHLIGHT — pulsing outline/tint. Indicates a selectable prompt option.

class_name HighlightLevel
enum Level { LOWLIGHT, CONTEXT, HIGHLIGHT }
