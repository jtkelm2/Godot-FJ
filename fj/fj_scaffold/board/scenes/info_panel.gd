## InfoPanel: side panel that displays HP, role/alignment, phase, priority,
## prompt text, text-option buttons, transient notifies, card preview, and
## game result. NL-aware port of `fj/ui/info_panel.gd`.
##
## Inputs (called by the composer / wired from Conductor signals):
##   set_my_pid(pid)                      — once at session start; the panel
##                                          remembers `my_pid` for the rest
##                                          of the session.
##   bind_state(state)                    — on every full rebuild.
##   bind_prompt(prompt)                  — on every PL.
##   clear_prompt()                       — when validator accepts an option.
##   flash_hp(target, old, new)           — HPChanged hook; emits
##                                          animation_started / animation_finished
##                                          around its tween so the composer
##                                          can gate the Scheduler.
##   set_phase(phase)                     — PhaseChanged hook.
##   mark_player_died(target)             — PlayerDied hook.
##   set_game_result(outcome, won)        — GameEnded hook.
##   show_notify(text)                    — Notify side-channel.
##   preview_card(slot_view, index)       — hover preview.
##
## Outputs:
##   text_option_selected(option)         — emitted when the user clicks a
##                                          text-option button.
##   animation_started / animation_finished
##                                        — emitted around any animation the
##                                          panel runs (currently just
##                                          flash_hp). The composer wires
##                                          these to Conductor.mark_busy /
##                                          mark_free so the panel's
##                                          animations gate the NL queue
##                                          alongside the Dispatcher's own.

class_name InfoPanel extends PanelContainer


const HP_FLASH_DURATION := 0.25


@export var red_theme: Theme
@export var blue_theme: Theme


signal text_option_selected(option: Option)
signal animation_started
signal animation_finished


@onready var _hp_value: Label = $MarginContainer/Backdrop/HPRow/HPValue
@onready var _phase_label: Label = $MarginContainer/Backdrop/PhaseLabel
@onready var _priority_label: Label = $MarginContainer/Backdrop/PriorityLabel
@onready var _role_label: Label = $MarginContainer/Backdrop/RoleLabel
@onready var _prompt_label: Label = $MarginContainer/Backdrop/VBox/PromptLabel
@onready var _text_options_box: VBoxContainer = $MarginContainer/Backdrop/VBox/TextOptions
@onready var _notify_label: Label = $MarginContainer/Backdrop/NotifyLabel
@onready var _game_result: Label = $MarginContainer/Backdrop/GameResultLabel
@onready var _preview: TextureRect = $MarginContainer/Backdrop/PanelContainer/Preview/PreviewFrame/PreviewImage
@onready var _arrow_up: Label = $MarginContainer/Backdrop/PanelContainer/Preview/HBoxContainer/ArrowUp
@onready var _arrow_down: Label = $MarginContainer/Backdrop/PanelContainer/Preview/HBoxContainer/ArrowDown


var my_pid: NLEnums.PID = NLEnums.PID.RED
var _notify_tween: Tween = null
var _preview_slot: SlotView = null
var _preview_index: int = -1


# --- Identity ---

func set_my_pid(pid: NLEnums.PID) -> void:
	my_pid = pid
	match pid:
		NLEnums.PID.RED:  theme = red_theme
		NLEnums.PID.BLUE: theme = blue_theme


# --- State binding (called on every full rebuild) ---

func bind_state(state: State) -> void:
	var my_hp: State.HP = state.hp.get(my_pid)
	_hp_value.text = ("%d / 20" % my_hp.val) if my_hp else "?"

	set_phase(state.phase)

	var mine := (state.priority == my_pid)
	_priority_label.text = "Your turn" if mine else "Opponent's turn"
	_priority_label.modulate = Color.LIGHT_GREEN if mine else Color(0.7, 0.7, 0.7)

	var my_role: State.Role = state.role.get(my_pid)
	if my_role and not my_role.role_name.is_empty():
		_role_label.text = "%s — %s" % [my_role.role_name, _alignment_str(my_role.alignment)]
	else:
		_role_label.text = ""


# --- Per-event hooks ---

func set_phase(phase: NLEnums.Phase) -> void:
	_phase_label.text = "" if phase == NLEnums.Phase.NONE else _phase_str(phase)


func mark_player_died(target: NLEnums.PID) -> void:
	show_notify("%s died" % ("You" if target == my_pid else "Opponent"))


func set_game_result(outcome: NLEnums.Outcome, won: Dictionary[NLEnums.PID, bool]) -> void:
	var outcome_str := _outcome_str(outcome)
	var i_won := bool(won.get(my_pid, false))
	var no_winners := true
	for v in won.values():
		if bool(v):
			no_winners = false
			break
	if i_won:
		_game_result.text = "VICTORY\n%s" % outcome_str
		_game_result.modulate = Color.GOLD
	elif no_winners:
		_game_result.text = "DRAW\n%s" % outcome_str
		_game_result.modulate = Color.GRAY
	else:
		_game_result.text = "DEFEAT\n%s" % outcome_str
		_game_result.modulate = Color.RED
	_game_result.visible = true


## Emits `animation_started` before the flash tween and `animation_finished`
## after, so the composer can gate the Scheduler on this animation via
## `Conductor.mark_busy` / `mark_free` connections.
func flash_hp(target: NLEnums.PID, old_val: int, new_val: int) -> void:
	var delta := new_val - old_val
	if delta != 0 and target == my_pid:
		var caption := "+%d HP" if delta > 0 else "%d HP"
		show_notify(caption % delta)
		_hp_value.text = "%d / 20" % new_val
	if delta == 0:
		return
	var color: Color = Color.LIGHT_GREEN if delta > 0 else Color(1.0, 0.5, 0.5)
	var orig: Color = modulate
	animation_started.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate", color, HP_FLASH_DURATION * 0.3)
	tween.tween_property(self, "modulate", orig, HP_FLASH_DURATION * 0.7)
	await tween.finished
	animation_finished.emit()


# --- Prompt rendering ---

func bind_prompt(prompt: Prompt) -> void:
	_prompt_label.text = prompt.text
	_prompt_label.visible = not prompt.text.is_empty()
	for child in _text_options_box.get_children():
		child.queue_free()
	for opt in prompt.options:
		if opt.type == Option.Type.TEXT:
			var btn := Button.new()
			btn.text = opt.text
			btn.custom_minimum_size = Vector2(0, 36)
			btn.pressed.connect(func(): text_option_selected.emit(opt))
			_text_options_box.add_child(btn)


func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_label.visible = false
	for child in _text_options_box.get_children():
		child.queue_free()


# --- Notify ---

func show_notify(text: String) -> void:
	if text.is_empty():
		return
	_notify_label.text = text
	if _notify_tween and _notify_tween.is_valid():
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_interval(6.0)
	_notify_tween.tween_callback(func(): _notify_label.text = "")


# --- Hover preview ---

## Set the slot/index the cursor is currently hovering. Pass (null, -1) to
## clear. Mouse-wheel input scrolls _preview_index through the slot's cards.
func preview_card(slot: SlotView, index: int) -> void:
	_preview_slot = slot
	_preview_index = index
	_render_preview()


func _render_preview() -> void:
	if _preview_slot == null or _preview_index < 0:
		_preview.texture = null
		_preview.visible = false
		_arrow_up.visible = false
		_arrow_down.visible = false
		return
	var card: CardView = _preview_slot.get_card(_preview_index)
	var tex: Texture2D = card.front_texture if card else null
	_preview.texture = tex
	_preview.visible = tex != null
	var n: int = _preview_slot.count()
	_arrow_up.visible = _preview_index > 0
	_arrow_down.visible = _preview_index < n - 1


func _input(event: InputEvent) -> void:
	if _preview_slot == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var step := 0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1
	if step == 0:
		return
	var n: int = _preview_slot.count()
	if n <= 1:
		return
	_preview_index = clamp(_preview_index + step, 0, n - 1)
	_render_preview()
	get_viewport().set_input_as_handled()


# --- Enum string helpers ---

static func _alignment_str(a: NLEnums.Alignment) -> String:
	match a:
		NLEnums.Alignment.GOOD: return "GOOD"
		NLEnums.Alignment.EVIL: return "EVIL"
	return ""


static func _phase_str(p: NLEnums.Phase) -> String:
	match p:
		NLEnums.Phase.SETUP:        return "SETUP"
		NLEnums.Phase.REFRESH:      return "REFRESH"
		NLEnums.Phase.MANIPULATION: return "MANIPULATION"
		NLEnums.Phase.ACTION:       return "ACTION"
	return ""


static func _outcome_str(o: NLEnums.Outcome) -> String:
	match o:
		NLEnums.Outcome.MUTUAL_GOOD_WIN:        return "MUTUAL_GOOD_WIN"
		NLEnums.Outcome.GOOD_KILLED_EVIL:       return "GOOD_KILLED_EVIL"
		NLEnums.Outcome.EVIL_KILLED_GOOD:       return "EVIL_KILLED_GOOD"
		NLEnums.Outcome.GOOD_KILLED_GOOD:       return "GOOD_KILLED_GOOD"
		NLEnums.Outcome.EXHAUSTION:             return "EXHAUSTION"
		NLEnums.Outcome.GOOD_GOOD_MUTUAL_DEATH: return "GOOD_GOOD_MUTUAL_DEATH"
		NLEnums.Outcome.GOOD_EVIL_MUTUAL_DEATH: return "GOOD_EVIL_MUTUAL_DEATH"
		NLEnums.Outcome.GOOD_THWARTED:          return "GOOD_THWARTED"
		NLEnums.Outcome.EVIL_THWARTED:          return "EVIL_THWARTED"
	return ""
