## Renderer-local card-spawn descriptor.
##
## Plain data — no NL types. The Dispatcher constructs these from NL
## CardInstance/CardTemplate and slot-side info, hands them to Board which
## materializes a CardView via its internal `_spawn`.

class_name CardDescriptor extends RefCounted


var front: Texture2D = null     ## Optional: null when the card should render face-down.
var back: Texture2D = null      ## Always required.
var faceup: bool = false


static func face_down(p_back: Texture2D) -> CardDescriptor:
	var d := CardDescriptor.new()
	d.back = p_back
	d.faceup = false
	return d


static func face_up(p_front: Texture2D, p_back: Texture2D) -> CardDescriptor:
	var d := CardDescriptor.new()
	d.front = p_front
	d.back = p_back
	d.faceup = true
	return d
