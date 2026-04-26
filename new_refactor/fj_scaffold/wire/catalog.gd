## Catalog: WL ↔ NL translator. Stub for Phase 1.
##
## Phase 2 will implement bijective name ↔ NL maps built from a WireCatalog,
## and a public API roughly:
##
##   func slot_for(wire: String) -> SlotID
##   func slot_to_wire(slot: SlotID) -> String
##   func card_for(wire: String) -> CardTemplate
##   func card_to_wire(template: CardTemplate) -> String
##   ... and weapon-slot equivalents.
##
## The Catalog also vends *canonical* SlotID instances (one per identity), so
## downstream NL consumers can compare slots via reference equality and use
## SlotIDs as Dictionary keys. NL CardTemplates likewise — Catalog loads their
## texture assets (via the conventions in fj/assets/image_resolver.gd) at
## construction time so the Renderer never blocks on disk I/O.

class_name Catalog extends RefCounted

# TODO Phase 2.
