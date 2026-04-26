# Thin Client Architecture

Canonical reference for abstractions used throughout the `fj_scaffold/` tree. Every folder README cites sections of this document. Keep this file synchronized with `fj_scaffold/README.md`.

## Languages

`NexusLang = DiffLang + StateLang + PromptLang`. The client's internal, post-deserialization protocol.

- **`DiffLang` (DL)** — incremental game-state events. `CardMoved`, `SlotTransferred`, `SlotShuffled`, `HPChanged`, `PhaseChanged`, `PlayerDied`, `GameEnded` (the seven protocol §3.2.3 types; extend as the protocol grows). DL values reference NL primitives only (`SlotID`, `Loc`, `PID`, `Phase`, `Outcome`, `CardTemplate`) — never wire-name strings.

**NL is wire-agnostic.** The same NL types serve any composition: a network client, a local-multiplayer in-process player, a replay engine, an AI driver, a unit test. Wire concerns (string identifiers, JSON shape) live exclusively in WL types and the `wire/` modules.
- **`StateLang` (SL)** — full-state snapshots. Map from slot wire name to `CardDescription` list.
- **`PromptLang` (PL)** — request for a player decision: text, options, context.

`ResponseLang` (RL) — single `Option`, sent in reply to a PL term.

`WireLang = WDL + WSL + WPL + WRL + WCL`. Serialized counterparts plus catalog terms.

## Server boundary

```
Player ──RL──► … ──RL──► Coplayer (server)
   ▲                          │
   └──────────NL──────────────┘
```

A `Player` is `(NL in, RL out — at least one RL per inbound PL)`. The client realizes a `Player` as a `GameBoard` and an `InputHandler` behind a `NexusRouter`.

## WireBoundary

```
        ┌──────────────── WireBoundary ─────────────────┐
NL ◄──► │ WireRouter ◄──► WireCodec ◄──► RawIO          │ ◄──► socket
        │     │                                         │
        │  Catalog (immutable after handshake)          │
        └───────────────────────────────────────────────┘
```

- **`RawIO`** — abstract `send`/`recv` over strings.
- **`WireCodec`** — string ↔ typed WL records. Speaks no semantics.
- **`Catalog`** — bijective WL ↔ NL translator. Populated from the single inbound WCL and immutable thereafter. Vends canonical `SlotID` and `CardTemplate` instances and provides lookup methods used by the (de)serializer. Owns asset loading for `CardTemplate`s (textures etc.).
- **`Serializer`** — NL → WL. Used for outbound RL.
- **`Deserializer`** — WL → NL. Used for inbound DL/SL/PL.
- **`WireRouter`** — splits inbound WL by variant (WCL → builds `Catalog`; WDL/WSL/WPL → `Deserializer` → emits NL; WRL → ignored). Drives `Serializer` on outbound RL.

`Catalog`, `Serializer`, and `Deserializer` are the *only* modules that bridge WL and NL. NL types know nothing about them.

**Catalog ordering invariant.** The catalog arrives before any other wire term and is never updated. The deserializer asserts on unknown names.

## NexusRouter

Sits between `WireRouter` and the NL consumers. Splits inbound NL by variant: DL → `Conductor`; SL → `DivergenceMonitor`; PL → teed to `GameBoard` and `InputHandler`. Forwards outbound RL from `InputHandler` to `WireRouter`.

## GameBoard = Renderer + Conductor

`GameBoard` is any consumer of NL. Instances: one-player in-game board, replay analysis board, logger, null board.

### Renderer

Animation primitives and completion signals. Exposes enough methods for `Dispatcher` and enough signals for `ReadinessTracker`. Knows nothing of NL.

Each zone's `Slot._cards` is the authoritative card list — server-driven, mutated only by NL traffic. User drag-reorder (when implemented) rearranges the scene-tree child order of `Card` nodes for display; `_cards` is untouched. Indices exchanged with `Conductor` and echoed in RL are always indices into `_cards`.

### Conductor

Bridge from NL to Renderer calls.

```
Conductor = Scheduler + StepHandler
StepHandler = Dispatcher + ReadinessTracker + DivergenceMonitor
```

| Component | In | Out / Effect |
|---|---|---|
| `Scheduler` | NL stream | one term at a time to `StepHandler`, gated on readiness |
| `Dispatcher` | one DL term | calls into `Renderer`; blind, fire-and-forget |
| `ReadinessTracker` | DL term in (BUSY); `Renderer` completion signals (FREE) | answers "ready for next term?" |
| `DivergenceMonitor` | one SL term + its DL batch | projects the batch onto a shadow state; compares against the SL; on mismatch, logs anomaly and drives a full rebuild via `Dispatcher` |

The wrapper tees each NL term to `Dispatcher` and `ReadinessTracker` (and SL terms additionally to `DivergenceMonitor`). `DivergenceMonitor` holds `ReadinessTracker` busy for the duration of an SL reconciliation — SL hard-blocks all subsequent DL until rebuild completes.

## InputHandler = OptionAdapter + OptionValidator

| Component | In | Out |
|---|---|---|
| `OptionAdapter` | native input events | `Option` values |
| `OptionValidator` | PL terms (current pending prompt); `Option`s from adapter | RL on match; rejection otherwise |

`OptionAdapter` is the only component aware of the native input substrate. `OptionValidator` is pure protocol logic. PL is teed by `NexusRouter` to both the `GameBoard` and the `OptionValidator`.

## Summary of streams

| Boundary | Type |
|---|---|
| socket ↔ `RawIO` | `String` |
| `RawIO` ↔ `WireCodec` | `String` |
| `WireCodec` ↔ `WireRouter` | `WL` |
| `WireRouter` → `Catalog` | `WCL` |
| `WireRouter` ↔ `NexusRouter` | `NL` / `RL` |
| `NexusRouter` → `Conductor` | `DL` |
| `NexusRouter` → `DivergenceMonitor` | `SL` (paired with its `DL` batch) |
| `NexusRouter` → `GameBoard`, `OptionValidator` | `PL` (teed) |
| `InputHandler` → `NexusRouter` | `RL` |
| native input → `OptionAdapter` | platform-specific |
| `OptionAdapter` → `OptionValidator` | `Option` |
| `Conductor` → `Renderer` | animation primitive calls |
| `Renderer` → `ReadinessTracker` | completion signals |
