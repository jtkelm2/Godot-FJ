# wire/

The `WireBoundary`: everything from bytes on a socket up to typed `NexusLang` terms. See `architecture.md §WireBoundary`.

## Composition

```
socket ↔ Transport ↔ WireCodec ↔ WireRouter ↔ NexusRouter
                                      │
                                  Catalog
```

Each box is one file. None of them know about game semantics.

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `transport.gd` | `class_name Transport`. Bytes ↔ socket. TCP and WebSocket backends. | `fj/net/network_transport.gd` |
| `wire_codec.gd` | String ↔ `Variant` WL grammar. JSON with int-preserving stringifier. | Inline inside the old `NetworkTransport._stringify` / `_process_buffer`. |
| `wire_router.gd` | Dispatches WL by variant. Deserializes via Catalog into typed NL. Serializes outbound RL. | `fj/net/game_session.gd::_on_message_received` dispatch. |
| `catalog.gd` | `class_name Catalog`. Immutable after handshake. Lookup tables for card/slot/weapon-slot names. | `fj/net/catalog_data.gd` (structurally close; adapt types). |

## Required server-side protocol adjustments

The scaffold assumes two changes from the current `protocol.md`. The porting agent must coordinate both of these before the client can assert on them.

### 1. `state` messages ALWAYS include `events`

Current (`protocol.md §3.2.3`): `events` is optional. Clients that ignore events still work.

Proposed: `events` is REQUIRED and is the batch of DL terms that produced this SL snapshot from the previous one. Empty array if truly nothing happened, but the field is always present.

Rationale: `DivergenceMonitor` (see `board/conductor/`) needs to project the DL batch onto the *previous* SL snapshot and compare the result against the *new* SL snapshot. Without the pairing guarantee, the monitor can't distinguish "empty events means no changes" from "events dropped for some reason."

Server change: `Serializer.events(...)` is already called in `RemotePlayer.push_state`; just make the field unconditional. The `events` key is written even when the returned list is empty.

### 2. Catalog is strictly immutable

Current (`protocol.md §3.1.4`): "The catalog is sent once and is immutable for the rest of the session."

This is already the policy. The scaffold enforces it on the client by making `Catalog` a `RefCounted` populated exactly once in its constructor from a WCL `Dictionary`, with no mutator methods. The deserializer asserts on unknown names.

Future mid-game catalog extension (extra weapon slot, dynamic cards) will require a protocol version bump. When that happens, `Catalog` gains a `version` field and `extend(...)` method; until then, the immutability is structural, not convention.

## NL/RL types

Typed NL/RL DTOs live under `nexus/types/`, not here. `WireRouter` imports them; `WireCodec` and below do not.
