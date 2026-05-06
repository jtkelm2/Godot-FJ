# Fool's Journey — Client Scaffold

This tree is a refactor target for the existing Godot client in `fj/`. It implements the architecture described in `architecture.md` (companion document) with one autoload and typed ADTs.

## Reading order

For an agent porting the old code, read in this order:

1. This file.
2. `architecture.md` (at the repo root). Non-optional. The abstractions below map one-to-one to sections of that doc.
3. `wire/README.md` — what crosses the socket, how it's parsed.
4. `nexus/README.md` — typed ADTs and the NL/RL/PL/DL/SL split.
5. `board/README.md` — Renderer / Conductor / InputHandler, the client's half of a Player.
6. `app/README.md` — composition: who constructs whom.

Each folder's README lists the files in that folder with a one-line summary and a reference to the architecture section that motivates it. Each file's header comment states its public API and cross-references the old-client file(s) it replaces.

## Architecture at a glance

```
socket ↔ RawIO ↔ WireCodec ↔ WireRouter ↔ NexusRouter ↔ { GameBoard, InputHandler }
                              │             (tees PL)
                              Catalog
```

Everything above `WireRouter` speaks `NL` (typed). Everything at or below speaks `WL` or bytes.

## One autoload

`App` (in `app/app.gd`). Owns `Transport` and `Session`, plus scene transitions. **No other autoloads.** Scenes receive their dependencies via `@export` or via a brief configuration pass after instantiation.

Rationale: Godot needs at least one "above the scene tree" object to carry state across scene transitions (connection screen → board). A single well-scoped service container is the idiomatic minimum; convenience singletons like `GameSession` in the old client become ordinary nodes owned by `App`.

## Typed everything

- `Option` is an `@abstract` base with four inner-class constructors. Matched via `match o: Option.Text: ... Option.Card: ...`. No `opt.get("type")` dispatch.
- DL events are grouped under an `@abstract Diff` base. Matched via `match ev: Diff.CardMoved: ... Diff.SlotTransferred: ...`.
- Wire messages are parsed into typed DTOs at the `WireRouter`/`WireCodec` boundary. Downstream code never sees `Dictionary`.
- Signals carry typed params (`signal card_clicked(slot: Slot, index: int)`, not `(data: Dictionary)`).

The only place `Variant` appears is inside `WireCodec` (JSON boundary) and inside `Transport` (byte buffer). Both are isolated to single files.

## Protocol adjustments required on the server

The scaffold assumes two server-side changes. Both are described in `wire/README.md`, but summarized:

1. **Every `state` message carries its event batch.** The current protocol has `events` optional; the scaffold requires it to be present (even if empty). This lets `DivergenceMonitor` pair each SL snapshot with the DL batch that produced it and run the event projector against the snapshot as an invariant check.

2. **Catalog is immutable (already true, make it explicit).** Server MUST NOT emit a second `catalog` message. The client asserts on unknown card/slot/weapon-slot names at deserialization time. Future mid-game catalog extension will require protocol versioning, not mid-session WCL.

## Scene composition

One `App` autoload. Two scenes:

- `ConnectionScreen.tscn` — host/port entry, transport type selector. Configures `App.transport` and triggers the handshake.
- `Board.tscn` — the in-game board. Receives `Session` via `@export` at scene-change time.

`App` handles the scene swap and dependency wiring so scene scripts never reach for globals.

## Migration checklist

- [x] **Phase 1**: NL types (`nexus/types/`) and WL types (`wire/types/`).
- [x] **Phase 2**: `Transport` (TCP + WebSocket), `WireCodec`, `Catalog`, `Serializer`, `Deserializer`, `WireRouter`, `NexusRouter`.
- [x] **Phase 3**: Renderer widgets — `CardView`, `SlotView`, `SimpleSlotView`, `SlotFieldView`, `WeaponSlotView`, `HighlightLevel`.
- [x] **Phase 4**: `Conductor` — `Scheduler`, `Dispatcher`, `ReadinessTracker`, `DivergenceMonitor`, `SlotWrangler`.
- [x] **Phase 5**: `InputHandler` (`OptionAdapter` + `OptionValidator`), `InfoPanel`, `Board` scene, `Session` composition unit, `.tscn` ports.
- [x] **Phase 6**: `App` autoload, `ConnectionScreen`, `project.godot` autoload + main-scene swap. Old autoloads (`NetworkTransport`, `GameSession`) are still registered alongside `App` so `fj/` parses cleanly.
- [ ] **Parity verification**: end-to-end test against the server with the new tree as main scene.
- [ ] Remove `NetworkTransport` and `GameSession` autoloads from `project.godot`. Delete `fj/`.
