extends Node
## GameManager (autoload singleton).
##
## The glue that systems which don't own each other (the weapon, the hurtbox,
## the camera) talk through. It remembers the player and the camera, and owns
## the feel layer for impacts: screen shake, hit-stop (a few frozen milliseconds
## on impact), a directional camera kick and a zoom punch.

var camera: Camera2D = null
var player: Node = null

var _hitstop_token := 0


func register_player(p: Node) -> void:
	player = p

func register_camera(cam: Camera2D) -> void:
	camera = cam


## Add screen shake. `amount` is trauma 0..1 - small hits ~0.2, heavy ~0.6.
func shake_camera(amount: float) -> void:
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(amount)


## Freeze the game for a few REAL milliseconds to sell an impact. A token makes
## sure only the most recent hit-stop is allowed to unfreeze.
func hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	_hitstop_token += 1
	var my_token := _hitstop_token
	# 4th arg (ignore_time_scale) = true so this timer keeps ticking while frozen.
	var timer := get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	if my_token == _hitstop_token:
		Engine.time_scale = 1.0


## Directional camera punch along `dir` (distinct from random shake).
func camera_kick(dir: Vector2, amount: float) -> void:
	if camera and camera.has_method("add_kick"):
		camera.add_kick(dir, amount)


## Quick zoom-in pop that eases back out - sells a heavy hit.
func zoom_punch(amount: float) -> void:
	if camera and camera.has_method("add_zoom_punch"):
		camera.add_zoom_punch(amount)
