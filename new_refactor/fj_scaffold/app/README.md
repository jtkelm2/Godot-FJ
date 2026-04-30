# app/

Composition root. One autoload (`App`, Phase 6) plus the in-game `Session` composition unit.

## Why one autoload

Godot needs at least one "above the scene tree" object to hold state across `change_scene_to_file`. `App` is that one object — and nothing else should be an autoload.

## Files

| File | Status | Responsibility |
|---|---|---|
| `session.gd` | **Phase 5** | `class_name Session extends Node`. Owns `Conductor` + `InputHandler` and wires them to a `NexusRouter` and a `Board` scene. Single composition root for the in-game half — the only place that holds references to all the components. |
| `app.gd` | Phase 6 | Autoload. Owns `Transport`, `WireRouter`, `NexusRouter`, and one live `Session?`. Handles connection lifecycle and scene transitions. |
| `connection_screen.gd` | Phase 6 | Host/port entry. Configures `App.transport`, initiates handshake. |
| `connection_screen.tscn` | Phase 6 | (Ported from old client.) |

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

## Migration notes

Old `NetworkTransport` and `GameSession` autoloads will be folded into `App` (Phase 6). The old `connection_screen.gd` reached into both; the new one will only talk to `App`.
