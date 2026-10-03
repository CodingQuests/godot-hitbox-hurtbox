class_name WeaponController
extends Node2D
## Lives on the player's WeaponPivot.
##
## Owns a tiny attack state machine (IDLE -> WINDUP -> ACTIVE -> RECOVERY) that
## drives a quick slash and a heavier cleave. During ACTIVE the attack hitbox is
## enabled; the rest of the time it is off, so you only deal damage during the
## swing. It is one sword with two attacks, so the pattern is easy to read.

enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

# Sword stats, kept inline so the state machine is easy to read. For several
# weapons, move these into one Resource per weapon.
const QUICK_DAMAGE := 20.0
const QUICK_KNOCKBACK := 170.0
const QUICK_ACTIVE := 0.10
const QUICK_COOLDOWN := 0.35
const QUICK_BOX := Vector2(46, 32)
const QUICK_OFFSET := 30.0

const HEAVY_DAMAGE := 45.0
const HEAVY_KNOCKBACK := 290.0
const HEAVY_WINDUP := 0.25
const HEAVY_ACTIVE := 0.16
const HEAVY_COOLDOWN := 0.90
const HEAVY_BOX := Vector2(64, 48)
const HEAVY_OFFSET := 40.0

const QUICK_HITSTOP := 0.04
const QUICK_SHAKE := 0.12
const HEAVY_HITSTOP := 0.07
const HEAVY_SHAKE := 0.5

@onready var weapon_sprite: Sprite2D = $WeaponSprite
@onready var attack_hitbox: HitboxComponent = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

var state: int = State.IDLE
var _state_timer := 0.0
var _cooldown := 0.0
var _current_is_heavy := false
var _player: Node = null
var _base_sprite_rotation := 0.0
const SLASH_COLOR := Color(0.9, 0.95, 1.0)
var _trail: Line2D = null
var _trail_radius := 0.0


func _ready() -> void:
	_player = get_parent()
	_base_sprite_rotation = weapon_sprite.rotation
	_disable_hitbox()
	attack_hitbox.source_node = _player       # so knockback pushes away from us
	attack_hitbox.hit_landed.connect(_on_hit_landed)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	match state:
		State.WINDUP:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_begin_active()
		State.ACTIVE:
			_state_timer -= delta
			_update_trail()
			if _state_timer <= 0.0:
				_begin_recovery()
		State.RECOVERY:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.IDLE


func is_busy() -> bool:
	return state != State.IDLE


## The player multiplies its move speed by this so you slow down mid-swing.
func get_move_factor() -> float:
	match state:
		State.WINDUP: return 0.35
		State.ACTIVE: return 0.6 if _current_is_heavy else 0.85
		State.RECOVERY: return 0.8
		_: return 1.0


func try_quick_attack() -> void:
	if state != State.IDLE or _cooldown > 0.0:
		return
	_current_is_heavy = false
	_cooldown = QUICK_COOLDOWN
	_begin_active()  # quick attack has no windup - it comes out instantly


func try_heavy_attack() -> void:
	if state != State.IDLE or _cooldown > 0.0:
		return
	_current_is_heavy = true
	_cooldown = HEAVY_COOLDOWN
	state = State.WINDUP  # the heavy telegraphs first, so it can be read/dodged
	_state_timer = HEAVY_WINDUP
	var tw := weapon_sprite.create_tween()
	tw.tween_property(weapon_sprite, "rotation", _base_sprite_rotation - deg_to_rad(70), _state_timer)


func _begin_active() -> void:
	state = State.ACTIVE
	_state_timer = HEAVY_ACTIVE if _current_is_heavy else QUICK_ACTIVE

	# Size and position the hitbox for this swing, then arm it.
	var size: Vector2 = HEAVY_BOX if _current_is_heavy else QUICK_BOX
	var offset: float = HEAVY_OFFSET if _current_is_heavy else QUICK_OFFSET
	(hitbox_shape.shape as RectangleShape2D).size = size
	hitbox_shape.position = Vector2(offset, 0)
	attack_hitbox.damage = HEAVY_DAMAGE if _current_is_heavy else QUICK_DAMAGE
	attack_hitbox.knockback_force = HEAVY_KNOCKBACK if _current_is_heavy else QUICK_KNOCKBACK
	attack_hitbox.is_crit = _current_is_heavy  # heavy hits read as crits
	attack_hitbox.reset_hits()                 # a new swing can hit everything again
	_enable_hitbox()

	# Lunge the player forward along the aim so the swing carries weight.
	var aim := global_transform.x.normalized()
	if _player and _player.has_method("lunge"):
		_player.lunge(aim, 210.0 if _current_is_heavy else 110.0)

	_trail_radius = offset + size.x * 0.5
	_start_trail()
	_spawn_slash(offset, size)
	_animate_swing(_current_is_heavy)


func _begin_recovery() -> void:
	_disable_hitbox()
	_end_trail()
	state = State.RECOVERY
	var spent := (HEAVY_WINDUP + HEAVY_ACTIVE) if _current_is_heavy else QUICK_ACTIVE
	var total := HEAVY_COOLDOWN if _current_is_heavy else QUICK_COOLDOWN
	_state_timer = maxf(0.05, total - spent)


func _on_hit_landed(hurtbox: Node) -> void:
	var aim := global_transform.x.normalized()
	var contact: Vector2 = (hurtbox as Node2D).global_position if hurtbox is Node2D else global_position
	Juice.spark(get_tree().current_scene, contact, aim, SLASH_COLOR, 6 if not _current_is_heavy else 10, 1.0 if not _current_is_heavy else 1.4)
	if _current_is_heavy:
		GameManager.hit_stop(HEAVY_HITSTOP)
		GameManager.shake_camera(HEAVY_SHAKE)
		GameManager.camera_kick(aim, 7.0)
		GameManager.zoom_punch(0.05)
	else:
		GameManager.hit_stop(QUICK_HITSTOP)
		GameManager.shake_camera(QUICK_SHAKE)
		GameManager.camera_kick(aim, 3.0)


# --- Hitbox enable/disable --------------------------------------------
# Toggling an Area2D from inside a physics callback must be DEFERRED, or Godot
# throws "can't change state while flushing queries".
func _enable_hitbox() -> void:
	attack_hitbox.monitoring = false
	attack_hitbox.set_deferred("monitorable", true)
	hitbox_shape.set_deferred("disabled", false)

func _disable_hitbox() -> void:
	hitbox_shape.set_deferred("disabled", true)
	attack_hitbox.set_deferred("monitorable", false)


# --- Swing visuals -----------------------------------------------------
func _animate_swing(is_heavy: bool) -> void:
	var arc := deg_to_rad(120) if is_heavy else deg_to_rad(90)
	weapon_sprite.rotation = _base_sprite_rotation - arc * 0.5
	var dur := (HEAVY_ACTIVE if is_heavy else QUICK_ACTIVE) + 0.08
	var tw := weapon_sprite.create_tween()
	tw.tween_property(weapon_sprite, "rotation", _base_sprite_rotation + arc * 0.5, dur).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(weapon_sprite, "rotation", _base_sprite_rotation, 0.1)


func _start_trail() -> void:
	_trail = Line2D.new()
	_trail.width = 5.0
	_trail.default_color = Color(SLASH_COLOR.r, SLASH_COLOR.g, SLASH_COLOR.b, 0.65)
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.z_index = 4
	add_child(_trail)

func _update_trail() -> void:
	if _trail == null:
		return
	var sweep := weapon_sprite.rotation - _base_sprite_rotation
	_trail.add_point(Vector2(cos(sweep), sin(sweep)) * _trail_radius)
	if _trail.get_point_count() > 12:
		_trail.remove_point(0)

func _end_trail() -> void:
	if _trail == null:
		return
	var t := _trail
	_trail = null
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0, 0.16)
	tw.tween_callback(t.queue_free)


func _spawn_slash(offset: float, size: Vector2) -> void:
	var poly := Polygon2D.new()
	poly.polygon = _make_arc_points(offset, size)
	poly.color = SLASH_COLOR
	poly.z_index = 5
	add_child(poly)
	poly.scale = Vector2(0.6, 0.6)
	poly.modulate.a = 0.9
	var tw := poly.create_tween()
	tw.set_parallel(true)
	tw.tween_property(poly, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(poly, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(poly.queue_free)


func _make_arc_points(offset: float, size: Vector2) -> PackedVector2Array:
	# A crescent opening toward +X, sized to the current hitbox.
	var pts := PackedVector2Array()
	var r_out := offset + size.x * 0.5
	var r_in := r_out * 0.45
	var span := clampf(size.y / 40.0, 0.4, 1.0) * deg_to_rad(130)
	var steps := 10
	for i in range(steps + 1):
		var a := lerpf(-span * 0.5, span * 0.5, float(i) / steps)
		pts.append(Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps + 1):
		var a := lerpf(span * 0.5, -span * 0.5, float(i) / steps)
		pts.append(Vector2(cos(a), sin(a)) * r_in)
	return pts
