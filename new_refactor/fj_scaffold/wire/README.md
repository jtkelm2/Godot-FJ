# wire/

The `WireBoundary`: bytes ↔ socket up through typed NL emission. Components are independent — they expose signals + methods and never import each other. The composition root (`App`) wires them together.

## Composition example (done by App)

```gdscript
var io: Transport = TCP.new(host, port)   # or WebSocket.new(host, port)
add_child(io)

var router := WireRouter.new()
add_child(router)

# Decode pipeline: raw line → Variant → wire_router
io.recv.connect(func(line):
    var d = WireCodec.decode(line)
    if d is Dictionary: router.wl_in(d)
)
# Encode pipeline: wire_router → Variant → raw line
router.wl_out.connect(func(d): io.send(WireCodec.encode(d)))

# NL fanout
router.state_received.connect(nexus.push_state)
router.prompt_received.connect(nexus.push_prompt)
router.notify_received.connect(nexus.push_notify)

# Outbound NL from consumers
nexus.rl_out.connect(router.send_response)
nexus.resign_out.connect(router.send_resign)
nexus.draw_offer_out.connect(router.send_draw_offer)
nexus.draw_accept_out.connect(router.send_draw_accept)
```

## Files

| File | Responsibility |
|---|---|
| `transport.gd` | `@abstract class_name Transport extends Node`. Bytes-over-socket ABC. Signals: `recv(msg)`, `connected`, `disconnected`, `error(msg)`. Abstract method: `send(msg)`. Inner `Buffer` helper for line-framing on `\n`. Implementations take `(host, port)` in their `_init` constructor and start connecting immediately. |
| `tcp.gd` | `class_name TCP extends Transport`. TCP backend over `StreamPeerTCP`. |
| `websocket.gd` | `class_name WebSocket extends Transport`. WebSocket backend over `WebSocketPeer`. |
| `wire_codec.gd` | `class_name WireCodec` (static). Int-preserving JSON ↔ Variant. Stateless utility. |
| `catalog.gd` | `class_name Catalog`. Player-symmetric — built from a WCL message that's identical for both clients (per protocol §1.3). SlotIDs carry absolute PIDs read straight from each slot's `owner` field; the receiving client's own PID is delivered separately via the `pid_assignment` notify (§3.4.2). Bijective name ↔ NL maps for slots / weapon slots / cards; eager texture loading for fronts and the three back textures (`back_for_pid(pid)` / `neutral_back()`). |
| `deserializer.gd` | `@abstract class_name Deserializer` (static). WL Variant dicts → typed NL/WL. `parse_state` → `WireState`; `lift_state` → NL `State`. `parse_dl` / `parse_prompt` / `parse_notify` / `parse_option` return NL directly. |
| `serializer.gd` | `@abstract class_name Serializer` (static). NL → WL Variant dicts. `serialize_response(opt)` produces byte-identical-echo per protocol §4.4. |
| `wire_router.gd` | `class_name WireRouter extends Node`. **Knows nothing of Transport, WireCodec, or NexusRouter.** Inbound: `wl_in(Dictionary)` push, emits typed NL signals (`handshake_complete`, `pid_assigned(pid)`, `state_received`, `prompt_received`, `notify_received`, `session_closed`). Outbound: NL methods (`send_response`, `send_resign`, `send_draw_offer`, `send_draw_accept`), emits `wl_out(Dictionary)`. Owns a `Catalog`, built on first WCL. The `pid_assignment` notify (§3.4.2) is dispatched to its own `pid_assigned` signal — App stores `my_pid` separately. |
| `types/` | WL types (5 files): `WireCardInfo`, `WireSlotInfo`, `WireCatalogEntry`, `WireState`, `WireCatalog`. |

## Dependency rules

- `Transport` / `TCP` / `WebSocket` import nothing else in `wire/`.
- `WireCodec` imports nothing.
- `Catalog` imports NL types (`SlotID`, `CardTemplate`) and `NLEnums`. No transport, no codec.
- `Serializer` and `Deserializer` are stateless utilities that take `Catalog` as a parameter. They reference NL/WL types but no Node-level component.
- `WireRouter` references only `Catalog`, `Deserializer`, `Serializer`, and the NL/WL types — never `Transport`, `WireCodec`, or `NexusRouter`.

## Required server-side protocol adjustments

Two changes from `protocol.md`. Coordinate before relying on them.

### 1. `state` messages ALWAYS include `events`

Currently optional (§3.2.3); proposed REQUIRED. `DivergenceMonitor` (Phase 4) needs the SL+DL pairing guarantee.

### 2. Catalog is strictly immutable

Already the policy (§3.1.4). Enforced structurally on the client by `Catalog` populated exactly once in its constructor.
