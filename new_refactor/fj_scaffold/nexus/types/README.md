# nexus/types/

Typed NL (NexusLang) DTOs and ADTs. **NL is wire-agnostic.** Types here know nothing about the Catalog, the wire format, or the WL ↔ NL boundary; they're meant to be usable in compositions with no wire at all (local multiplayer, replay, AI driver, tests).

The wire format and the WL ↔ NL translation live in `wire/` (Catalog, Serializer, Deserializer).

## Tagged-union convention

Godot 4.6 GDScript doesn't model algebraic data types cleanly: inner-class-per-constructor lacks `class_name` registration, can't be exported, and forces verbose `is X / as X` dispatch. Every former-ADT in NL is therefore flattened to a single concrete class with a `Type` enum tag plus the union of all fields each variant needs:

```gdscript
class_name Foo extends RefCounted

enum Type { A, B }

var type: Type
var x: int = 0           # used when type == A
var inner: Bar = null    # used when type == B; null when unused
var z: String = ""       # used when type == B

static func A(v: int) -> Foo:
    var f := Foo.new(); f.type = Type.A; f.x = v; return f

static func B(b_inner: Bar, zs: String) -> Foo:
    var f := Foo.new(); f.type = Type.B; f.inner = b_inner; f.z = zs; return f
```

PascalCase static factories are the construction surface. Dispatch becomes `match foo.type: Foo.Type.A: …`. Object fields default `null` outside their variant; primitives default to `0` / `""` (GDScript primitives can't be null). Each ADT's tag enum nests on its own class (`Foo.Type`), never in `NLEnums`.

Trade-off accepted: each instance carries every union field. Memory overhead is small. "Forgot to set field X for variant Y" becomes a runtime mistake instead of a structural impossibility — mitigated by routing all construction through the PascalCase factories, which set every field that matters for that variant and leave the rest at safe defaults.

## File inventory

| File | Defines |
|---|---|
| `enums.gd` | `@abstract class_name NLEnums` namespace. Enums: `PID`, `Phase` (with `NONE` sentinel for wire-null), `Alignment`, `CardType`, `Outcome` (9 outcomes per protocol §3.2.2). Per-ADT tag enums live on each ADT's own class, not here. |
| `slot.gd` | `class_name SlotID` flattened tagged union. Tag: `SlotID.Type` (14 values). Fields: `type, side, num`. Factories: `GuardDeck`, per-side `Hand(side)` / `Deck(side)` / `Refresh(side)` / `Discard(side)` / `Equipment(side)` / `Sidebar(side)` / `ActionTopDistant(side)` / `ActionTopHidden(side)` / `ActionBottomDistant(side)` / `ActionBottomHidden(side)`; per-side per-num `WeaponZone(side, num)` / `Holster(side, num)` / `Killstack(side, num)`. Plus `make(type, side, num)` for callers that hold the type as data (Catalog wire-role parsing). Structural `equals(other)`. **No interning, no `key()`** — consumers that hold `Dict[SlotID, V]` write their own private linear-search helpers using `equals` (Dispatcher does this in three places). |
| `loc.gd` | `class_name Loc` flattened. Tag: `Loc.Type { UNKNOWN, SLOT }`. Fields: `type, slot, idx`. Factories: `Loc.Unknown()`, `Loc.Slot(slot, idx)`. Structural `equals`. Index convention: 0 is the top of the pile (per protocol §3.2.1). |
| `card_template.gd` | `class_name CardTemplate`. Resolved card metadata; populated by Catalog in `wire/`. |
| `card_instance.gd` | `class_name CardInstance(template, counters)`. |
| `state.gd` | `class_name State` + inner `Role(alignment, role_name)`, `HP(val, cap, floor)`, and inner flattened `SlotContents` (tag `SlotContents.Type { UNKNOWN, COUNT, FULL }`; factories `Unknown()` / `Count(n)` / `Full(cards)`). State fields: `role: Dict[PID, Role]`, `hp: Dict[PID, HP]`, `phase: Phase`, `priority: PID`, `slots: Dict[SlotID, SlotContents]`. **No `game_result`** — game outcome is conveyed by the trailing `DL.GameEnded`. |
| `option.gd` | `class_name Option` flattened. Tag: `Option.Type { TEXT, LOC, SLOT }`. Fields: `type, text, loc, slot`. Factories: `Option.Text(text)`, `Option.Loc(loc)`, `Option.Slot(slot)`. Three variants per Python sketch — wire's `card` collapses into `Option.Loc(Loc.Slot(...))`, wire's `weapon_slot` into `Option.Slot(SlotID.WeaponZone(...))`. Structural `equals(other)` for OptionValidator. |
| `diff.gd` | `class_name DL` flattened. Tag: `DL.Type` (7 values). Union fields cover all variants: `orig, dest` (Loc, for `CardMoved`), `orig_slot, dest_slot, count` (for `SlotTransferred`), `slot` (for `SlotShuffled`), `target, old_hp, new_hp` (for `HPChanged` / `PlayerDied`), `phase` (for `PhaseChanged`), `outcome, won` (for `GameEnded`). Factories: `DL.CardMoved(orig, dest)`, `DL.SlotTransferred(orig, dest, count)`, `DL.HPChanged(target, old, new)`, `DL.SlotShuffled(slot)`, `DL.PlayerDied(target)`, `DL.PhaseChanged(phase)`, `DL.GameEnded(outcome, won)`. Seven event types per protocol §3.2.3. |
| `prompt.gd` | `class_name Prompt(text, options, context)` + inner `Notify(kind, text)`. `Notify` is a separate protocol message type (§3.4); colocated for fewer-files economy. |
| `nl.gd` | `class_name NL` marker abstract base. Does **not** flatten — its "constructors" are themselves complex types (`DL`, `State`, `Prompt`, `Option`). |

## Wire-agnostic invariants

- No NL type holds a wire-name string (e.g., `"red_hand"`). Wire names live exclusively in WL types under `wire/types/`.
- No NL type imports `Catalog`, `WireCodec`, `Serializer`, `Deserializer`, or any `wire/` module.
- No NL type defines a `from_wire` or `to_wire` method. All wire conversion happens in `wire/`.

## NL is shared with WL where it can be

`WireLang = DL | WireState | Prompt | Response | WireCatalog` per the language sketch. Of those:

- `DL`, `Prompt`, and `Response` (which is just `Option`) are **the same NL types** — their composition uses NL primitives only (`Loc`, `SlotID`, `PID`, `Phase`, `Outcome`), and those primitives are cheap for the deserializer to construct from JSON via Catalog lookups. There is no separate `WireDL` / `WirePrompt` / `WireResponse`.
- `WireState` and `WireCatalog` get separate WL types (under `wire/types/`) because their content involves `CardTemplate` assets that are heavy to resolve. The WL form keeps cards as `WireCardInfo` (a name string + counters); the NL `CardInstance` carries a fully-loaded `CardTemplate`. `WireSlotInfo` is the wire-side flattened tagged union mirroring `State.SlotContents`.

## Naming conventions

The NL Slot ADT is named `SlotID` (not `Slot`) because `fj/ui/slot.gd` already registers `class_name Slot` globally. Likewise `SlotID.WeaponZone` instead of `WeaponSlot` (taken by `fj/ui/weapon_slot.gd`). After Phase 6 deletes `fj/`, these can be renamed to bare forms if desired.

`NLEnums` is also a namespace class; access is `NLEnums.PID.RED`, `NLEnums.Phase.SETUP`, etc. Per-ADT tag enums never live in `NLEnums` — each ADT nests its own `Type` enum on its own class.
