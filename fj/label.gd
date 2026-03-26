extends Label


func _ready():
	Signals.phase_changed.connect(func(new_phase): text = new_phase)
