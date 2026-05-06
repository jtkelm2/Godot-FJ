## Logger: configurable line-oriented logger with per-stream silencing.
##
## Independent of any subsystem — instances are constructed by the composer
## and connected to specific signals or callsites. Default sink is the
## engine's `print()`; replace `sink` with any `Callable(line: String)` to
## redirect (e.g., to a file, in-game console, or a test capture buffer).
##
## Streams are arbitrary string tags assigned by the caller (e.g.,
## `"conductor.handling"`, `"wire.in"`). Silenced streams drop their
## messages without invoking the sink. A wildcard prefix match could be
## added later — current behavior is exact-name match only.

class_name Logg extends RefCounted


## Where lines go. Replace to redirect output. Receives the fully-formatted
## line including the bracketed stream tag.
var sink: Callable = func(line: String) -> void: print(line)


var _silenced: Dictionary[String, bool] = {}


## Emit `message` under `stream`. No-op if the stream is silenced.
func write(stream: String, message: String) -> void:
	if _silenced.get(stream, false):
		return
	sink.call("[%s] %s" % [stream, message])


## Mute `stream`; subsequent `write` calls under it become no-ops.
func silence(stream: String) -> void:
	_silenced[stream] = true


## Re-enable `stream`.
func unsilence(stream: String) -> void:
	_silenced.erase(stream)


func is_silenced(stream: String) -> bool:
	return _silenced.get(stream, false)

## String methods

## One-line summary for a NL term. DL formats itself; State and Prompt are
## simple enough to inline.
static func describe_nl(term: NL) -> String:
	if term is DL:
		return (term as DL).describe()
	if term is State:
		return "State"
	if term is Prompt:
		return "Prompt %s" % JSON.stringify((term as Prompt).text)
	return "<unknown NL>"
