extends RefCounted

const CARD_INFO_DIR := "res://fj/assets/card_info/"
const CARD_ASSET_DIR := "res://fj/assets/images/cards/"

## card_name -> front image filename (e.g., "enemy_3" -> "nameless_23.png")
var _name_to_image: Dictionary = {}

## Cached loaded textures
var _texture_cache: Dictionary = {}

## Back textures
var _red_back: Texture2D
var _blue_back: Texture2D
var _default_back: Texture2D


func _init() -> void:
	_load_all_card_info()
	_red_back = load(CARD_ASSET_DIR + "back_red.png") as Texture2D
	_blue_back = load(CARD_ASSET_DIR + "back_blue.png") as Texture2D
	_default_back = load(CARD_ASSET_DIR + "back1.png") as Texture2D


func _load_all_card_info() -> void:
	var dir := DirAccess.open(CARD_INFO_DIR)
	if dir == null:
		push_error("ImageResolver: failed to open card info directory: %s" % CARD_INFO_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var card_name := file_name.get_basename()
			var json_path := CARD_INFO_DIR + file_name
			var file := FileAccess.open(json_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data
					if data.has("front_image"):
						_name_to_image[card_name] = data["front_image"]
				file.close()
		file_name = dir.get_next()


func get_front_texture(card_name: String) -> Texture2D:
	if _texture_cache.has(card_name):
		return _texture_cache[card_name]

	var image_file: String = _name_to_image.get(card_name, "")
	if image_file.is_empty():
		push_warning("ImageResolver: no image mapping for card '%s'" % card_name)
		return null

	var path := CARD_ASSET_DIR + image_file
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("ImageResolver: failed to load texture: %s" % path)
		return null

	_texture_cache[card_name] = texture
	return texture


func get_back_texture(color: String) -> Texture2D:
	match color.to_upper():
		"RED":
			return _red_back
		"BLUE":
			return _blue_back
		_:
			return _default_back
