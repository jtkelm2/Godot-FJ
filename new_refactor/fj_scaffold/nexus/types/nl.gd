## Common base for all NL message types: DL events, State, Prompt, and Option
## (RL). Provides a typed parameter for components that route NL polymorphically
## (Scheduler, Dispatcher) without falling back to `Variant`.
##
## Wire-agnostic — NL itself carries no fields and no methods. Subclasses
## are the actual terms. Nested types (Loc, SlotID, CardInstance, Role,
## SlotContents, …) do NOT extend NL — they're records inside NL terms.

@abstract
class_name NL extends RefCounted
