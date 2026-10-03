class_name HealthComponent
extends Node
## Reusable health container. Drop it on any entity (player or enemy) as a
## child node named "Health". Other systems call damage()/heal() and listen
## to the signals for feedback and death handling.

signal damaged(amount: float, current: float, maximum: float)
signal healed(amount: float, current: float, maximum: float)
signal died

@export var max_health: float = 100.0

var current_health: float = 0.0


func _ready() -> void:
	current_health = max_health


func damage(amount: float) -> void:
	if current_health <= 0.0:
		return
	amount = maxf(0.0, amount)
	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, current_health, max_health)
	if current_health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	amount = maxf(0.0, amount)
	current_health = minf(max_health, current_health + amount)
	healed.emit(amount, current_health, max_health)


func set_max_health(value: float, keep_ratio: bool = false) -> void:
	var ratio := 1.0 if max_health <= 0.0 else current_health / max_health
	max_health = value
	current_health = max_health * ratio if keep_ratio else minf(current_health, max_health)


func is_alive() -> bool:
	return current_health > 0.0


func get_ratio() -> float:
	return 0.0 if max_health <= 0.0 else current_health / max_health
