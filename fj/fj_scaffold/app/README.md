# app/

Composition root. One autoload (`App`, Phase 6) plus the in-game `Session` composition unit.

## Why one autoload

Godot needs at least one "above the scene tree" object to hold state across `change_scene_to_file`. `App` is that one object — and nothing else should be an autoload.

## Files

| File | Responsibility |
|---|---|
| `app.gd` | Autoload (`extends Node`, registered as `App` in `project.godot`). Owns `WireRouter` + `NexusRouter` for the app's lifetime, plus a `Transport` (per connect) and a `Session?` (per game). Wires the codec pipeline (`transport.recv ↔ WireCodec ↔ wire_router.wl_in/out`) and the NL fanout (`WireRouter ↔ NexusRouter`). On `handshake_complete(catalog)` AND `pid_assigned(pid)` (in either order), swaps to Board.tscn and bootstraps a Session. On disconnect / `session_closed`, tears down Session and returns to ConnectionScreen. |
| `session.gd` | `class_name Session extends Node`. The composition root for the in-game half — owns `Conductor` + `InputHandler` and wires them to a `NexusRouter` and a `Board` scene. App constructs and bootstraps Session post-handshake. |
| `connection_screen.gd` | Host/port + transport-type input. Talks only to `App` (no other autoload reachable). |
| `connection_screen.tscn` | Ported from `fj/net/connection_screen.tscn` with the script rebound. |

## Session's role

`Session.bootstrap(catalog, my_pid, nexus, board)` does all the wiring that no individual component does:

1. Sets `my_pid` on `board.info_panel`.
2. Walks the Board scene to build `slot_for: Dict[SlotID, SlotView]` and `weapon_slot_for: Dict[SlotID.WeaponZone, WeaponSlotView]` via `Catalog.slot_id_for` / `weapon_slot_id_for`.
3. Constructs `Conductor` (with `slot_for` / `overlay` / `card_factory` / `back_for_slot` configured) and adds it as a child.
4. Constructs `InputHandler` and adds it as a child.
5. Wires `NexusRouter` ↔ `Conductor` + `InputHandler` (inbound NL pushes; outbound RL via `option_accepted`).
6. Wires `Conductor`'s per-event signals (`hp_changed`, `phase_changed`, `state_rebuilt`, …) to `board.info_panel`'s methods.
7. Wires `info_panel.animation_started` / `animation_finished` to `conductor.mark_busy` / `mark_free`, so info-panel-side animations gate the Scheduler alongside Dispatcher's own.
8. Wires every `SlotView`'s / `WeaponSlotView`'s click signal to `input_handler.on_*`, with the appropriate `SlotID` bound. Wires hover signals to `info_panel.preview_card`.
9. Wires `info_panel.text_option_selected` to `input_handler.on_text_option`.

After bootstrap, no component holds a reference to any other beyond what Session set up; Session is the sole owner of the wiring.

## Lifetime

```
App (autoload)                        — Phase 6
├─ Transport                          (lives for app lifetime)
├─ WireRouter                         (lives for app lifetime; reset on reconnect)
├─ NexusRouter                        (lives for app lifetime)
└─ Session?                           — created on handshake_complete + pid_assigned
    ├─ Conductor (Node child)
    │   ├─ Scheduler / ReadinessTracker / DivergenceMonitor (RefCounted)
    │   └─ Dispatcher (Node child) → SlotWrangler (RefCounted)
    └─ InputHandler (Node child)
        └─ OptionAdapter / OptionValidator (RefCounted)
```

The Board scene is a sibling, not Session's child — Board lives where the App's scene-swap puts it. Session doesn't own it; it just wires into it.

## Public API (what ConnectionScreen and other scenes can call)

```gdscript
# Methods
App.connect_to(host: String, port: int, type: App.TransportType) -> void
App.disconnect_from_server() -> void

# Signals
App.connected
App.disconnected
App.connection_error(err: String)
App.session_started(my_pid: NLEnums.PID)
```

That's the entire reachable surface. `App` does not expose its `Transport`, `WireRouter`, `NexusRouter`, `Session`, or `Catalog`. Any UI that needs to send NL goes through the Session that App composes (currently only the in-Board scene needs that, and it gets the wiring done by Session.bootstrap during scene swap).

## Migration notes

The old `NetworkTransport` and `GameSession` autoloads are now superseded by `App`. Until parity verification, both old autoloads remain in `project.godot` so the unmodified `fj/` tree still parses; once the new tree is verified end-to-end against the server, both old autoloads are removed and `fj/` is deleted.
