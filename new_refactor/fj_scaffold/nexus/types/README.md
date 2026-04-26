# nexus/types/

Typed NL (NexusLang) DTOs and ADTs. **NL is wire-agnostic.** Types here know nothing about the Catalog, the wire format, or the WL ↔ NL boundary; they're meant to be usable in compositions with no wire at all (local multiplayer, replay, AI driver, tests).

The wire format and the WL ↔ NL translation live in `wire/` (Catalog, Serializer, Deserializer — Phase 2).

## File inventory

| File | Defines |
|---|---|
| `enums.gd` | `@abstract class_name NLEnums` namespace. Enums: `PID`, `Phase` (with `NONE` sentinel for wire-null), `Alignment`, `CardType`, `Outcome` (9 outcomes per protocol §3.2.2). |
| `slot.gd` | `@abstract class_name SlotID` ADT. Constructors: `GuardDeck`; per-side `Hand(side)` / `Deck(side)` / `Refresh(side)` / `Discard(side)` / `Equipment(side)` / `Sidebar(side)` / `ActionTopDistant(side)` / `ActionTopHidden(side)` / `ActionBottomDistant(side)` / `ActionBottomHidden(side)`; per-side per-num `WeaponZone(side, num)` / `Holster(side, num)` / `Killstack(side, num)`. |
| `loc.gd` | `@abstract class_name Loc` + `UnknownLoc`, `SlotLoc(slot, idx)`. |
| `card_template.gd` | `class_name CardTemplate`. Resolved card metadata; texture/asset fields are placeholders, populated by Catalog in Phase 2+. |
| `card_instance.gd` | `class_name CardInstance(template, counters)`. |
| `state.gd` | `class_name State` + inner `Role(alignment, role_name)`, `HP(val, cap, floor)`, `@abstract SlotContents` + `UnknownContents` / `CountContents(n)` / `FullContents(cards)`. State fields: `role: Dict[PID, Role]`, `hp: Dict[PID, HP]`, `phase: Phase`, `priority: PID`, `slots: Dict[SlotID, SlotContents]`. **No `game_result`** — game outcome is conveyed by the trailing `DL.GameEnded`. |
| `option.gd` | `@abstract class_name Option` + `TextOption(text)`, `LocOption(loc)`, `SlotOption(slot)`. Three variants per Python sketch — wire's `card` collapses into `LocOption(SlotLoc(...))`, wire's `weapon_slot` into `SlotOption(SlotID.WeaponZone(...))`. `equals(other)` for OptionValidator. |
| `diff.gd` | `@abstract class_name DL` + `CardMoved(orig, dest)`, `SlotTransferred(orig, dest, count)`, `HPChanged(old_hp, new_hp)`, `SlotShuffled(slot)`, `PlayerDied(target: PID)`, `PhaseChanged(phase: Phase)`, `GameEnded(outcome: Outcome, won: Dict[PID, bool])`. Seven event types per protocol §3.2.3. |
| `prompt.gd` | `class_name Prompt(text, options, context)` + inner `Notify(kind, text)`. `Notify` is a separate protocol message type (§3.4); colocated for fewer-files economy. |

## Wire-agnostic invariants

- No NL type holds a wire-name string (e.g., `"red_hand"`). Wire names live exclusively in WL types under `wire/types/`.
- No NL type imports `Catalog`, `WireCodec`, `Serializer`, `Deserializer`, or any `wire/` module.
- No NL type defines a `from_wire` or `to_wire` method. All wire conversion happens in `wire/` (Phase 2: Serializer, Deserializer).

## NL is shared with WL where it can be

`WireLang = DL | WireState | Prompt | Response | WireCatalog` per the language sketch. Of those:

- `DL`, `Prompt`, and `Response` (which is just `Option`) are **the same NL types** — their composition uses NL primitives only (`Loc`, `SlotID`, `PID`, `Phase`, `Outcome`), and those primitives are cheap for the deserializer to construct from JSON via Catalog lookups. There is no separate `WireDL` / `WirePrompt` / `WireResponse`.
- `WireState` and `WireCatalog` get separate WL types (under `wire/types/`) because their content involves `CardTemplate` assets that are heavy to resolve. The WL form keeps cards as `WireCardInfo` (a name string + counters); the NL `CardInstance` carries a fully-loaded `CardTemplate`.

## Naming conventions

The NL Slot ADT is named `SlotID` (not `Slot`) because `fj/ui/slot.gd` already registers `class_name Slot` globally. Likewise `SlotID.WeaponZone` instead of `WeaponSlot` (taken by `fj/ui/weapon_slot.gd`). Other constructors keep bare names — none collide. After Phase 6 deletes `fj/`, these can be renamed to bare forms if desired.

`NLEnums` is also a namespace class; access is `NLEnums.PID.RED`, `NLEnums.Phase.SETUP`, etc.

## Inner-class limitations

Per Godot 4.6:
- `class_name` is one per file, so inner constructors don't get global registration. External references must preload and qualify (`const D = preload("res://.../diff.gd"); func handle(e: D.CardMoved) -> void: ...`), or use the `Outer.Inner` form when the outer is a `class_name`.
- An inner class name MUST NOT collide with any registered global `class_name`, even via its outer namespace. `Option.Card` is rejected with "hides a global script class" when `fj/ui/card.gd` has `class_name Card`.
