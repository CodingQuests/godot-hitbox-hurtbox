class_name Juice
extends RefCounted
## Small static helpers for "game feel": hit-flash materials, impact particles,
## directional sparks, squash/stretch, afterimages, decals, rings and floating
## damage numbers. Kept in one place so the player and every enemy share the
## exact same polish without copy-pasting.

const FLASH_SHADER := preload("res://shaders/flash.gdshader")


## Returns a ShaderMaterial set up for the white hit-flash. Assign it to a
## sprite once; trigger a flash later with flash().
static func make_flash_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	mat.set_shader_parameter("flash_amount", 0.0)
	return mat


## Pop a sprite white for `duration` seconds, then fade the flash back out.
static func flash(sprite: CanvasItem, color: Color = Color.WHITE, duration: float = 0.08) -> void:
	if sprite == null:
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		mat = make_flash_material()
		sprite.material = mat
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_amount", 1.0)
	var tw := sprite.create_tween()
	tw.tween_property(mat, "shader_parameter/flash_amount", 0.0, duration).set_delay(0.0)


## One-shot burst of particles at `pos`. Cheap and self-cleaning.
static func impact(world: Node, pos: Vector2, color: Color = Color.WHITE, amount: int = 10, scale: float = 1.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.35
	p.global_position = pos
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 60.0 * scale
	p.initial_velocity_max = 160.0 * scale
	p.gravity = Vector2.ZERO
	p.damping_min = 120.0
	p.damping_max = 220.0
	p.scale_amount_min = 1.5 * scale
	p.scale_amount_max = 3.0 * scale
	p.color = color
	world.add_child(p)
	p.emitting = true
	# Free the node a moment after the burst finishes.
	p.get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Directional spark burst: sharp, fast streaks fired along `dir`. Use this at
## the exact contact point of a hit so debris flies off the blade edge.
static func spark(world: Node, pos: Vector2, dir: Vector2, color: Color = Color.WHITE, amount: int = 8, speed: float = 1.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.22
	p.global_position = pos
	p.direction = dir.normalized()
	p.spread = 32.0
	p.initial_velocity_min = 180.0 * speed
	p.initial_velocity_max = 380.0 * speed
	p.gravity = Vector2.ZERO
	p.damping_min = 240.0
	p.damping_max = 420.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = color
	world.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Quick impact squash: snaps `node` to a wider/shorter scale, then springs back
## to `base_scale`. Reads as a recoil/impact deformation on a hit or a stop.
static func squash(node: Node2D, base_scale: Vector2, amount: float = 0.35, duration: float = 0.22) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.scale = Vector2(base_scale.x * (1.0 + amount), base_scale.y * (1.0 - amount))
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base_scale, duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Stretch the other way (taller and thinner) before springing back. Good for a
## launch or dash anticipation.
static func stretch(node: Node2D, base_scale: Vector2, amount: float = 0.3, duration: float = 0.2) -> void:
	squash(node, base_scale, -amount, duration)


## Drop a fading ghost copy of `sprite` at its current transform. String several
## together along a dash for a motion-trail.
static func afterimage(world: Node, sprite: Sprite2D, tint: Color = Color(0.7, 0.9, 1.0, 0.5), duration: float = 0.25) -> void:
	if world == null or not is_instance_valid(world) or sprite == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.global_position = sprite.global_position
	ghost.global_rotation = sprite.global_rotation
	ghost.global_scale = sprite.global_scale
	ghost.flip_h = sprite.flip_h
	ghost.modulate = tint
	ghost.z_index = sprite.z_index - 1
	world.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, duration)
	tw.tween_callback(ghost.queue_free)


## A fading dark splat left on the ground (blood/scorch). Sits under everything
## and lingers so cleared rooms feel earned.
static func decal(world: Node, pos: Vector2, color: Color = Color(0.05, 0.0, 0.02, 0.4), radius: float = 9.0, duration: float = 6.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	var poly := Polygon2D.new()
	poly.polygon = _circle_points(radius * randf_range(0.85, 1.2), 12)
	poly.color = color
	poly.global_position = pos + Vector2(randf_range(-3, 3), randf_range(-2, 2))
	poly.z_index = -5
	world.add_child(poly)
	var tw := poly.create_tween()
	tw.tween_interval(duration * 0.5)
	tw.tween_property(poly, "modulate:a", 0.0, duration * 0.5)
	tw.tween_callback(poly.queue_free)


## Expanding, fading ring outline. Good for a dash launch, a spawn telegraph or a
## big impact.
##
## The ring grows by rebuilding its points, not by scaling the node: scaling a
## Line2D scales its width too, and a 2px line scaled 26x is a filled disc.
static func ring(world: Node, pos: Vector2, color: Color = Color.WHITE, radius: float = 28.0, duration: float = 0.35, width: float = 2.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	var line := Line2D.new()
	line.closed = true
	line.points = _circle_points(radius * 0.35, 24)
	line.width = width
	line.default_color = color
	line.global_position = pos
	line.z_index = 6
	world.add_child(line)
	var grow := func(r: float) -> void:
		line.points = _circle_points(r, 24)
	var tw := line.create_tween()
	tw.set_parallel(true)
	tw.tween_method(grow, radius * 0.35, radius, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(line.queue_free)


## Floating, rising, fading damage number. `crit` makes it bigger and punches in
## with an overshoot so heavy hits read as a different beat.
static func damage_number(world: Node, pos: Vector2, amount: float, color: Color = Color.WHITE, crit: bool = false) -> void:
	if world == null or not is_instance_valid(world):
		return
	var label := Label.new()
	label.text = str(roundi(amount))
	label.z_index = 100
	var font_size := 22 if crit else 14
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5 if crit else 4)
	label.global_position = pos + Vector2(randf_range(-6, 6), -10)
	world.add_child(label)
	var rise := -30.0 if crit else -22.0
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", label.global_position + Vector2(0, rise), 0.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.15)
	if crit:
		# Punch-scale in from big -> settle.
		label.scale = Vector2(1.6, 1.6)
		tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(label.queue_free)



# Points of a circle (radius `r`) as a PackedVector2Array, shared by decals and rings.
static func _circle_points(r: float, steps: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / steps
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
