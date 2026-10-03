extends Node2D
## The demo arena: a faint reference grid, a few barrels to smash, one tough
## barrel that takes a beating, a row of spikes that hurts the player, and a
## health readout.
##
## Everything in this script is demo scaffolding. The combat system itself is
## HealthComponent, HitboxComponent, HurtboxComponent and WeaponController.

const GRID := 64        # spacing between grid lines, in pixels
const EXTENT := 1600    # how far the grid reaches from the origin
const LINE_COLOR := Color(1, 1, 1, 0.06)

@onready var _hp_label: Label = $HUD/HP


func _ready() -> void:
	var health: HealthComponent = $Player/Health
	health.damaged.connect(_on_player_damaged)
	health.died.connect(_on_player_died)
	_on_player_damaged(0.0, health.current_health, health.max_health)


func _draw() -> void:
	for x in range(-EXTENT, EXTENT + 1, GRID):
		draw_line(Vector2(x, -EXTENT), Vector2(x, EXTENT), LINE_COLOR, 1.0)
	for y in range(-EXTENT, EXTENT + 1, GRID):
		draw_line(Vector2(-EXTENT, y), Vector2(EXTENT, y), LINE_COLOR, 1.0)


func _on_player_damaged(_amount: float, current: float, maximum: float) -> void:
	_hp_label.text = "HP %d / %d" % [current, maximum]


func _on_player_died() -> void:
	_hp_label.text = "You died. Press R to restart."


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_R:
		get_tree().reload_current_scene()
