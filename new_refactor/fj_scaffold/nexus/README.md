# nexus/

The NexusRouter plus typed ADTs for `NexusLang` and related protocols.

See `architecture.md §NexusRouter` and `§Languages`.

## Responsibilities

`NexusRouter` sits between `WireRouter` and the NL consumers. It:

- Subscribes to `WireRouter`'s typed-NL signals.
- Splits inbound NL by variant: DL → Conductor; SL → DivergenceMonitor; PL → teed to GameBoard *and* InputHandler.
- Forwards outbound RL from InputHandler back to WireRouter.

For two outbound variants (RL, plus OOB resign/draw) and one inbound source (WireRouter), the router is a thin fanout. But it exists as a named component because it's the right seam for adding new NL consumers (replay logger, divergence analyzer, AI observer).

## Files

| File | Responsibility |
|---|---|
| `nexus_router.gd` | The router itself. |
| `types/` | Typed ADTs (see subfolder README). |

## Files in types/

See `types/README.md`. Summary: one file per ADT, with the base class and its subclasses in the same file where the subclass count is small (Option: 4 subclasses, one file). DL events get one file per event type because there are many and the distinction matters for `match` dispatch.
