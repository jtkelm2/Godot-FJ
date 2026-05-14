extends Node

const _CARD_PRESENTER_SCENE := preload("res://fj/board/scenes/card_presenter.tscn")
const _BACK := preload("res://fj/assets/images/cards/back_red.png")

var _presenter: CardPresenter


func _ready() -> void:
	_presenter = _CARD_PRESENTER_SCENE.instantiate()
	add_child(_presenter)
	_presenter.card_clicked.connect(func(i: int) -> void: print("[test] card_clicked ", i))
	_presenter.card_hovered.connect(func(i: int) -> void: print("[test] card_hovered ", i))
	_presenter.card_unhovered.connect(func() -> void: print("[test] card_unhovered"))
	_presenter.selection_made.connect(_on_selection_made)
	await _run_demo()


func _run_demo() -> void:
	var descriptors: Array[CardDescriptor] = []
	for i in range(12):
		var front_path := "res://fj/assets/images/cards/named_%d.png" % (i + 1)
		var front: Texture2D = load(front_path)
		descriptors.append(CardDescriptor.face_up(front, _BACK))

	_presenter.set_text("Pick 2 cards.")
	_presenter.set_selection_count(2)
	await _presenter.populate(descriptors).run()
	await _presenter.present().run()


func _on_selection_made(indices: Array[int]) -> void:
	print("[test] selection_made ", indices)
	await _presenter.dismiss().run()
	await get_tree().create_timer(0.5).timeout

	print("[test] reopening in informational mode")
	_presenter.set_text("Just look at these cards.")
	_presenter.set_selection_count(0)
	await _presenter.present().run()
