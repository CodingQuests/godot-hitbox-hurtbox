class_name DestructibleProp
extends StaticBody2D
## A barrel or crate you can smash.
##
## A prop is just "an enemy that doesn't fight back." It reuses the exact same
## HealthComponent + HurtboxComponent as everything else, so your sword damages
## it with zero special-case code. When its health runs out it breaks with a
## burst of debris. Drop loot from _break() if you want it to.

@export var max_health: float = 20.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox

var _broken := false


func _ready() -> void:
	health.max_health = max_health
	health.current_health = max_health
	health.died.connect(_break)


func _break() -> void:
	if _broken:
		return
	_broken = true
	var world := get_tree().current_scene
	# Chunky debris burst + a little shake and a scorch decal where it stood.
	Juice.impact(world, global_position, Color(0.75, 0.55, 0.32), 22, 1.5)
	Juice.ring(world, global_position, Color(0.8, 0.65, 0.4, 0.7), 26.0, 0.28)
	Juice.decal(world, global_position, Color(0.1, 0.07, 0.03, 0.35), 8.0, 4.0)
	GameManager.shake_camera(0.12)
	queue_free()
