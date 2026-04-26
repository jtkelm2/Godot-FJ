# board/conductor/

The `Conductor`: the bridge from NL to `Renderer` calls.

See `architecture.md §Conductor`.

## Composition

```
Conductor = Scheduler + StepHandler
StepHandler = Dispatcher + ReadinessTracker + DivergenceMonitor
```

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `conductor.gd` | Wrapper that owns Scheduler + StepHandler and tees incoming NL. | Parts of `fj/ui/board.gd` (`_on_changed`, `_change_pass`). |
| `scheduler.gd` | Queues inbound NL; hands one term at a time to StepHandler, gated on ReadinessTracker. | Parts of `fj/ui/board.gd` (`_animating`, `_change_pass` re-entrance guard). |
| `step_handler.gd` | Wrapper that tees each NL term to Dispatcher, ReadinessTracker, and (for SL) DivergenceMonitor. | Not separately present in old client. |
| `dispatcher.gd` | Blind, fire-and-forget DL-to-Renderer calls. | `fj/ui/event_animator.gd`. |
| `readiness_tracker.gd` | Tracks BUSY/FREE. Answers "ready for next term?" | Implicit `await` chain in old board.gd. |
| `divergence_monitor.gd` | Projects DL batch onto previous shadow; asserts against new SL. Triggers full rebuild on mismatch. | `fj/net/event_projector.gd` + the `_run_events` diff check in `board.gd`. |

## The three inflows

`Conductor` subscribes to its `NexusRouter` on three channels:

1. **`state_received(sl, dl_batch)`** — atomic SL+DL pair. Routes to both `DivergenceMonitor` (invariant check) and `Dispatcher` (animation).
2. **`diffs_received(dl_batch)`** — DL batch alone (no paired SL). Routes to `Dispatcher` only.
3. **`prompt_received(prompt)`** — PL terms for context/highlight rendering. Routes to `Dispatcher` (which handles highlight decoration; highlights are just another animation primitive).

The router emits both `state_received` and `diffs_received` for every SL update, because they go to different consumers. See `nexus/nexus_router.gd`.

## Ordering guarantees

- Every term handed to `StepHandler` must complete before the next one starts.
- A DL batch arriving via `diffs_received` is played as a single unit (all events before readiness is signaled FREE).
- An SL arriving via `state_received` hard-blocks: `DivergenceMonitor` holds `ReadinessTracker` BUSY until the invariant check AND (if needed) the full rebuild both complete. No DL can slip through during reconciliation.
- If new NL arrives while the current term is still processing, `Scheduler` queues it. The queue is small and bounded by the server's prompt-pending invariant (P1 in `protocol.md`).

## Divergence Monitor contract

The `DivergenceMonitor` is the client-side teeth of the paired-SL+DL protocol change.

Each `state_received(sl, dl_batch)`:

1. Take the previous `StateSnapshot` (stored by `DivergenceMonitor` from the prior reconciliation).
2. Project `dl_batch` onto it to get an expected `StateSnapshot`.
3. Compare expected vs. actual `sl`.
4. If they match, update the stored snapshot and release `ReadinessTracker`.
5. If they don't match, `push_warning` with a diff summary, emit a divergence signal, drive `Dispatcher` to perform a full rebuild from `sl`, and only then release `ReadinessTracker`.

The full rebuild path exists as a safety net. Under correct server behavior, it should never fire; if it does, the warning surfaces a bug.
