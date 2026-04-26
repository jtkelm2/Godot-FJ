# app/

Composition root. One autoload (`App`), one scene-transition helper, and the two top-level scenes (`ConnectionScreen`, `Board` — `Board` lives in `board/scenes/` but is orchestrated from here).

## Why one autoload

Godot needs at least one "above the scene tree" object to hold state across `change_scene_to_file`. Attempting to pass constructed objects through a scene change otherwise requires `change_scene_to_packed` with careful timing. `App` is that one object — and nothing else should be an autoload.

Scenes receive their dependencies in one of two ways:

1. **`@export`** — for references configurable in the editor.
2. **Post-instantiation configuration** — `App` instances the scene's root, calls `configure(...)` on it with typed dependencies, then adds it to the tree.

The second pattern is what the old client needed `GameSession` as an autoload for. With `App.swap_scene(packed, configurator)`, we replicate it without the global.

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `app.gd` | Autoload. Owns `Transport`, `Session`. Exposes scene-swap helper. | `GameSession.gd` + `NetworkTransport.gd` (as autoloads) |
| `session.gd` | The composed `Player`: `Conductor` + `InputHandler` behind a `NexusRouter`. Receives `Transport`. | `GameSession.gd` (as dispatch hub) |
| `connection_screen.gd` | Host/port entry. Configures `App.transport`, initiates handshake, transitions on `handshake_complete`. | `fj/net/connection_screen.gd` |
| `connection_screen.tscn` | (Port from old client verbatim; re-bind the script.) | `fj/net/connection_screen.tscn` |

## Lifetime

```
App (autoload)
├─ Transport    (lives for app lifetime; reused across sessions)
└─ Session?     (created at handshake_complete, destroyed on disconnect)
    ├─ WireRouter
    ├─ Catalog
    ├─ NexusRouter
    ├─ Conductor (held by the Board scene, via configure())
    └─ InputHandler (held by the Board scene, via configure())
```

`Session` is split across the autoload and the Board scene: the wire-facing half (`WireRouter`, `Catalog`, `NexusRouter`) lives in `App`; the presentation half (`Conductor`, `InputHandler`) lives in `Board`. When the Board scene is swapped in, `App` injects the nexus-router handle so the two halves can wire up.

## Migration notes

The old `NetworkTransport` and `GameSession` autoloads are both folded into `App`. The old `connection_screen.gd` reached into both; the new one only talks to `App`.

Scene swap pattern:

```gdscript
# old:
get_tree().change_scene_to_file("res://fj/ui/board.tscn")
# relies on autoload GameSession being reachable from board.gd's _ready

# new:
App.swap_scene(
    preload("res://board/scenes/board.tscn"),
    func(board): board.configure(App.session.nexus_router)
)
```
