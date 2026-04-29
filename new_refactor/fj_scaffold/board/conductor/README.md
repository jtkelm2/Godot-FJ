# board/conductor/

The `Conductor`: the bridge from NL to Renderer animation primitives.

See `architecture.md §Conductor`.

## Composition

```
Conductor (assembly + push API)
    ├─ Scheduler          — NL queue, gated by ReadinessTracker
    ├─ Dispatcher         — animates one term at a time
    ├─ ReadinessTracker   — busy/free counter; gates the Scheduler
    ├─ DivergenceMonitor  — SL+DL invariant check
    └─ SlotWrangler       — NL CardInstance → CardView creation
```

Each sub-component is independently a small typed unit; the Conductor wires them internally and exposes a small public surface upward.

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `conductor.gd` | `class_name Conductor extends Node`. Composes the sub-components, exposes `push_state` / `push_diffs` / `push_prompt` / `reset`. | Parts of `fj/ui/board.gd` (`_on_changed`, `_change_pass`). |
| `scheduler.gd` | `class_name Scheduler extends RefCounted`. NL queue. `push(term)` accepts terms; `next_term(term)` signal emits one when ready. `notify_idle()` advances the queue. Defers emission to break re-entrance. | Implicit `_animating` + `_change_pass` re-entrance guard in old `board.gd`. |
| `dispatcher.gd` | `class_name Dispatcher extends Node`. `handle(term)` translates one NL term to Renderer widget calls (CardView/SlotView/WeaponSlotView). Emits `animation_started` / `animation_finished` for the ReadinessTracker. | `fj/ui/event_animator.gd`. |
| `readiness_tracker.gd` | `class_name ReadinessTracker extends RefCounted`. Busy-count counter. `mark_busy()` / `mark_free()` methods, `became_free` signal. | Implicit `await` chain in old `board.gd`. |
| `divergence_monitor.gd` | `class_name DivergenceMonitor extends RefCounted`. `check(state, events) -> CheckResult` projects events onto previous SL, compares against new SL, returns `{initial, divergent, diffs}`. Stateless interface (no signals). | `fj/net/event_projector.gd` + the `_run_events` diff check in `board.gd`. |
| `slot_wrangler.gd` | `class_name SlotWrangler extends RefCounted`. `populate(slot_view, slot_id, contents)` stocks a SlotView from `State.SlotContents`. `create_card(front, back, faceup)` for stand-ins. Composer provides `card_factory` and `back_for_slot` Callables. | `fj/ui/slot_wrangler.gd`. |

## The three inbound channels (composer wiring)

The composer (Phase 6 App) connects:

```gdscript
nexus.sl_in.connect(conductor.push_state)         # paired (state, events)
nexus.pl_in.connect(conductor.push_prompt)        # PL
# diffs_in only if a future protocol revision sends bare DL batches.
```

Conductor configuration is set before any push:

```gdscript
conductor.slot_for = composer_built_slot_dict
conductor.weapon_slot_for = composer_built_ws_dict
conductor.overlay = board_scene_overlay
conductor.card_factory = func(): return card_scene.instantiate() as CardView
conductor.back_for_slot = func(slot_id):
    if slot_id is SlotID.GuardDeck: return catalog.neutral_back()
    return catalog.back_for_pid(slot_id.side)
```

## Ordering guarantees

- The Scheduler hands one term to the Dispatcher at a time. The Dispatcher emits `animation_finished` exactly once per `handle(term)` call, after which the ReadinessTracker becomes free and the Scheduler advances.
- For paired SL+DL, the Conductor decomposes the pair: it asks the DivergenceMonitor to validate (synchronously), then enqueues either (a) the events alone if the projection matched, (b) the events followed by a state-rebuild term if divergent, or (c) just the state if this is the first SL of the session.

## Divergence Monitor contract

`check(state, events)` returns a `CheckResult`:

- `initial: true` — the very first SL, no prior baseline. Conductor schedules a rebuild from `state`.
- `divergent: true` — projection mismatch. `push_warning` is logged with a diff summary; Conductor schedules events, then a rebuild from `state` to snap the UI back to authoritative truth.
- Otherwise normal — Conductor just plays the events.

Under a correct server, divergence never fires. When it does, the warning surfaces a server bug; the rebuild keeps the user from getting stuck on a desynced UI.

## What Phase 4 covers

- **CardMoved** animations (flying card across the screen).
- **SlotTransferred** animations (single fly representing the batch).
- **SlotShuffled** animations (slot jiggle).
- **Full rebuilds** from State (initial population + divergence recovery).
- **Prompt highlights** (HIGHLIGHT for options, CONTEXT for context entries, LOWLIGHT reset elsewhere).

## What's deferred (Phase 5)

- HPChanged, PhaseChanged, PlayerDied, GameEnded — these update info-panel state, which arrives with the Board scene assembly in Phase 5.
- TextOption rendering in the prompt — also info-panel territory.
