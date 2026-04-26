# board/

The client's half of a `Player`: a `GameBoard` (NL consumer) and an `InputHandler` (PL-in, RL-out), assembled into the Board scene.

See `architecture.md §GameBoard` and `§InputHandler`.

## Composition

```
GameBoard = Renderer + Conductor
Conductor = Scheduler + StepHandler
StepHandler = Dispatcher + ReadinessTracker + DivergenceMonitor

InputHandler = OptionAdapter + OptionValidator
```

The Board scene (`scenes/board.tscn`) is a thin shell that:

1. Receives a `NexusRouter` via `configure(...)`.
2. Instantiates a `Conductor` and an `InputHandler`, wiring them to the router.
3. Builds the scene tree of `Slot`/`WeaponSlot` nodes (the `Renderer`).
4. Connects scene-tree signals (clicks, hovers) to the `InputHandler`'s `OptionAdapter`.

No game logic, no protocol logic. Just composition.

## Subfolders

| Folder | Contents |
|---|---|
| `renderer/` | `Slot` ABC + subclasses, `Card`, `WeaponSlot`, `SlotWrangler`, `Highlight`, σ-separation. |
| `conductor/` | `Conductor` wrapper + `Scheduler`, `ReadinessTracker`, `Dispatcher`, `DivergenceMonitor`. |
| `input/` | `InputHandler` wrapper + `OptionAdapter`, `OptionValidator`. |
| `scenes/` | The `Board` scene itself — orchestrator only. |

## Why this layout over the old `fj/ui/`

The old `fj/ui/board.gd` was a 600-line "orchestrator" that played the roles of Board, Conductor, Dispatcher, DivergenceMonitor, OptionAdapter, and OptionValidator simultaneously. Splitting each into its own file with an explicit public API means:

- New `GameBoard` variants (replay player, analysis board, null board for tests) can reuse `Renderer` and `Conductor` without touching input.
- The σ-separation we want for hand reordering has an obvious home (`Renderer`) rather than being entangled with event animation.
- `DivergenceMonitor`'s invariant check can run in tests without a scene tree.

## Migration strategy

Port in the order: `renderer/` → `conductor/` → `input/` → `scenes/`. The renderer is the foundation — everything else consumes its API. Scenes come last because they can only be assembled once the components exist.
