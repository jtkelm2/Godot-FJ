extends Node

var blue_back_texture:Texture2D = load("res://fj/assets/images/cards/back_blue.png") as Texture2D

enum PColor { Red, Blue }

var Red = PColor.Red
var Blue = PColor.Blue


var current_player: PColor = Red
signal player_switched(new_player: PColor)


func switch_player() -> void:
	current_player = Blue if current_player == Red else Red
	player_switched.emit(current_player)
	print("Switched to player: ", "RED" if current_player == Red else "BLUE")


func is_current_player(player: PColor) -> bool:
	return current_player == player

func get_opponent(player: PColor) -> PColor:
	return Blue if player == Red else Red
