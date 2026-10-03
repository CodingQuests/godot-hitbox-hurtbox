class_name HurtboxComponent
extends Area2D
## An Area2D that *receives* damage. This is the active detector: it watches for
## overlapping HitboxComponents (and projectiles), then applies the result to
## its sibling Health node, knocks back its parent body, and plays hit feedback.
##
## Expected layout (sibling nodes under the same body):
##   Body (CharacterBody2D)
##     Sprite2D
##     Health         (HealthComponent)
##     Hurtbox        (this)

## `source` is untyped on purpose: a projectile can outlive its firer, so this
## may be null or even a just-freed reference. Receivers should not rely on it.
signal hurt(amount: float, source)

## Multiplies all incoming damage. Raise it for a "takes +x% damage" debuff, or
## lower it for armour.
@export var damage_multiplier: float = 1.0
@export var invulnerable: bool = false

## Visual feedback options.
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var show_damage_numbers: bool = true
@export var impact_color: Color = Color(1, 0.85, 0.85)

var health: HealthComponent
var _body: Node
var _sprite: CanvasItem


func _ready() -> void:
	_body = get_parent()
	health = _body.get_node_or_null("Health")
	_sprite = _body.get_node_or_null("Sprite2D")
	if _sprite and _sprite.material == null:
		_sprite.material = Juice.make_flash_material()
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if invulnerable:
		return
	if not area.is_in_group("hitbox"):
		return

	# Make sure a single swing only hits us once.
	if area.has_method("try_register_hit"):
		if not area.try_register_hit(self):
			return

	var incoming: float = area.damage * damage_multiplier
	# Untyped + validity check: a projectile may outlive the enemy that fired it,
	# leaving source_node pointing at a freed instance.
	var source = area.source_node if ("source_node" in area) else null
	if source != null and not is_instance_valid(source):
		source = null

	if health:
		health.damage(incoming)

	# Knock the body away from the hit source.
	if _body.has_method("apply_knockback"):
		var from: Vector2 = area.global_position
		var dir: Vector2 = _body.global_position - from
		if dir.length() < 0.01:
			dir = Vector2.RIGHT.rotated(randf() * TAU)
		_body.apply_knockback(dir.normalized(), area.knockback_force)

	# Feedback: flash, particles, floating number.
	Juice.flash(_sprite, flash_color, 0.09)
	var world := get_tree().current_scene
	Juice.impact(world, global_position, impact_color, 8, 1.0)
	if show_damage_numbers:
		var crit: bool = area.is_crit if ("is_crit" in area) else false
		var num_color := Color(1.0, 0.85, 0.3) if crit else flash_color
		Juice.damage_number(world, global_position, incoming, num_color, crit)

	hurt.emit(incoming, source)

	# Let projectiles know they connected so they can despawn.
	if area.has_method("on_hurtbox_hit"):
		area.on_hurtbox_hit()
