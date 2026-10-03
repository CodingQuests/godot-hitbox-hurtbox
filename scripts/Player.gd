class_name PlayerController
extends CharacterBody2D
## The player: a HealthComponent, a Hurtbox that receives damage, and a
## WeaponController that swings. This script drives movement and the dash,
## forwards attack inputs to the weapon, takes knockback when hit, and plays the
## hurt feedback.

# --- Movement tuning ---
@export var move_speed: float = 180.0
@export var dash_speed: float = 520.0
@export var dash_duration: float = 0.14
@export var dash_cooldown: float = 0.6

# Knockback feel: how fast a shove decays, and how much of an incoming hit's
# knockback the player actually takes (lower = the player is shoved less).
const KNOCKBACK_DECAY := 1700.0
const KNOCKBACK_TAKEN := 0.6

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $Health
@onready var weapon: WeaponController = $WeaponPivot
@onready var hurtbox: HurtboxComponent = $Hurtbox

var _knockback := Vector2.ZERO
var _is_dashing := false
var _dash_timer := 0.0
var _dash_cd_timer := 0.0
var _dash_dir := Vector2.RIGHT
var _dash_img_timer := 0.0
# True for the whole dash. hurtbox.invulnerable is what actually blocks the hit;
# this is the flag your own code can read.
var is_invincible := false

# --- Juice state ---
var _base_sprite_scale := Vector2.ONE
var _bob_time := 0.0
var _was_moving := false


func _ready() -> void:
	GameManager.register_player(self)  # "player" group is set in Player.tscn
	_base_sprite_scale = sprite.scale
	health.died.connect(_on_died)
	hurtbox.hurt.connect(_on_hurt)


func _physics_process(delta: float) -> void:
	_update_aim()
	_handle_attack_input()
	_update_dash(delta)

	var input := Vector2.ZERO
	if _is_dashing:
		velocity = _dash_dir * dash_speed
		_emit_afterimages(delta)
	else:
		input = _get_move_input()
		# The weapon slows us down mid-swing via get_move_factor().
		var factor := weapon.get_move_factor()
		velocity = input * move_speed * factor + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	move_and_slide()
	_update_body_juice(delta, input.length() > 0.1)


func _get_move_input() -> Vector2:
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	return v.normalized() if v.length() > 1.0 else v


func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	weapon.rotation = to_mouse.angle()
	if absf(to_mouse.x) > 4.0:
		sprite.flip_h = to_mouse.x < 0.0


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("quick_attack"):
		weapon.try_quick_attack()
	elif Input.is_action_just_pressed("heavy_attack"):
		weapon.try_heavy_attack()


# --- Dash --------------------------------------------------------------
func _update_dash(delta: float) -> void:
	if _dash_cd_timer > 0.0:
		_dash_cd_timer -= delta
	if _is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_end_dash()
		return
	if Input.is_action_just_pressed("dash") and _dash_cd_timer <= 0.0:
		_start_dash()


func _start_dash() -> void:
	var input := _get_move_input()
	if input.length() > 0.1:
		_dash_dir = input.normalized()
	else:
		var to_mouse := get_global_mouse_position() - global_position
		_dash_dir = to_mouse.normalized() if to_mouse.length() > 0.01 else Vector2.RIGHT
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_cd_timer = dash_cooldown
	_dash_img_timer = 0.0
	_knockback = Vector2.ZERO
	hurtbox.invulnerable = true  # i-frames: the dash dodges incoming hits
	is_invincible = true
	sprite.modulate = Color(0.7, 0.9, 1.0)
	Juice.stretch(sprite, _base_sprite_scale, 0.25, 0.16)
	Juice.ring(get_tree().current_scene, global_position, Color(0.7, 0.9, 1.0, 0.7), 26.0, 0.3)


func _end_dash() -> void:
	_is_dashing = false
	hurtbox.invulnerable = false
	is_invincible = false
	sprite.modulate = Color.WHITE
	Juice.squash(sprite, _base_sprite_scale, 0.2, 0.22)


func _emit_afterimages(delta: float) -> void:
	_dash_img_timer -= delta
	if _dash_img_timer <= 0.0:
		_dash_img_timer = 0.025
		Juice.afterimage(get_tree().current_scene, sprite, Color(0.6, 0.85, 1.0, 0.45), 0.22)


func get_dash_ratio() -> float:
	if dash_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _dash_cd_timer / dash_cooldown, 0.0, 1.0)


# --- Knockback (called by the weapon on attack, and by the Hurtbox on hit) ---
## Shove the player toward `dir` (weapon calls this so swings feel weighty).
func lunge(dir: Vector2, force: float) -> void:
	if _is_dashing or dir.length() < 0.01:
		return
	_knockback = dir.normalized() * force

## Called by HurtboxComponent when an enemy hit connects.
func apply_knockback(direction: Vector2, force: float) -> void:
	if _is_dashing:
		return
	_knockback = direction * force * KNOCKBACK_TAKEN


# --- Feedback ----------------------------------------------------------
func _on_hurt(_amount: float, source) -> void:
	GameManager.shake_camera(0.18)
	if source != null and is_instance_valid(source) and source is Node2D:
		var away := (global_position - (source as Node2D).global_position)
		GameManager.camera_kick(away, 6.0)


func _on_died() -> void:
	# A simple death: stop taking input and fade the body out. Swap in your own
	# game-over screen here.
	hurtbox.invulnerable = true
	set_physics_process(false)
	GameManager.shake_camera(0.6)
	Juice.impact(get_tree().current_scene, global_position, Color(0.6, 0.1, 0.15), 26, 1.8)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color(0.4, 0.4, 0.45, 0.6), 0.5)


# --- Body juice --------------------------------------------------------
func _update_body_juice(delta: float, moving: bool) -> void:
	if _is_dashing:
		return
	var freq := 13.0 if moving else 3.0
	var amp := 1.6 if moving else 0.8
	_bob_time += delta * freq
	sprite.position.y = sin(_bob_time) * amp
	if _was_moving and not moving:
		Juice.squash(sprite, _base_sprite_scale, 0.18, 0.2)
	_was_moving = moving
