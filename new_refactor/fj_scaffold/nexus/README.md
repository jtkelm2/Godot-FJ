# nexus/

The NexusRouter plus typed NL ADTs.

See `architecture.md §NexusRouter` and `§Languages`.

## Responsibilities

`NexusRouter` is a pure bidirectional NL fanout. It is wire-agnostic: it knows nothing about `WireRouter`, local-multiplayer engines, replay players, or any other backend. It just receives NL on push methods and emits typed signals on each side.

Inbound side: `push_state(state, events)`, `push_prompt(prompt)`, `push_notify(notify)` → emits `sl_in` / `pl_in` / `notify_in`.

Outbound side: `send_response(option)`, `send_resign()`, `send_draw_offer()`, `send_draw_accept()` → emits `rl_out` / `resign_out` / `draw_offer_out` / `draw_accept_out`.

SL carries its paired DL batch in `sl_in(state, events)` because DivergenceMonitor needs them atomically — the only place a signal carries more than one term.

The composition root (`App` in Phase 6) is responsible for connecting whatever produces NL (e.g., `WireRouter.state_received` → `nexus.push_state`) and whatever consumes outbound NL (e.g., `nexus.rl_out` → `WireRouter.send_response`). NexusRouter doesn't import any of those.

## Files

| File | Responsibility |
|---|---|
| `nexus_router.gd` | `class_name NexusRouter extends Node`. Pure bidirectional fanout. Push methods on both sides; typed signals on both sides. |
| `types/` | NL types — wire-agnostic. See subfolder README. |

## Files in types/

See `types/README.md`. Summary: one file per ADT root, with constructors as inner classes. `DL` / `Prompt` / `Option` / `Notify` are shared with WL (the wire's `WireLang` reuses them rather than mirroring), per the Python sketch's `WireLang = DL | WireState | Prompt | Response | WireCatalog`.
