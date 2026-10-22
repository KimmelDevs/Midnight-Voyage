class_name UnitView
extends Control
## Visual for one BattleUnit: sprite with feet on `home`, HP + shield bar,
## status badges, and simple lunge / hit / faint animations.

const BAR_W := 40.0

var unit: BattleUnit
var home := Vector2.ZERO
var sprite: TextureRect
var badges: HBoxContainer
var _bob_t := randf() * TAU


func setup(u: BattleUnit, tex: Texture2D, region: Rect2, at: Vector2) -> void:
	unit = u
	home = at
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at_tex := AtlasTexture.new()
	at_tex.atlas = tex
	at_tex.region = region
	size = region.size
	sprite = TextureRect.new()
	sprite.texture = at_tex
	sprite.size = region.size
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	badges = HBoxContainer.new()
	badges.add_theme_constant_override("separation", 1)
	badges.position = Vector2(size.x / 2.0 - BAR_W / 2.0, -20)
	add_child(badges)
	position = (home - Vector2(size.x / 2.0, size.y)).floor()
	refresh()


func _process(delta: float) -> void:
	if unit and unit.alive():
		_bob_t += delta * 3.0
		sprite.position.y = round(sin(_bob_t) * 1.0)


func refresh() -> void:
	queue_redraw()
	for ch in badges.get_children():
		ch.queue_free()
	for st in unit.statuses:
		var good: bool = st["kind"] == "hot" or (st["kind"] == "status" and float(st["amount"]) > 0.0)
		var l := Label.new()
		l.text = str(st["tag"])
		l.add_theme_font_size_override("font_size", 8)
		l.add_theme_color_override("font_color", Color("9ef0a0") if good else Color("ff9a9a"))
		l.add_theme_color_override("font_outline_color", Color("1c1428"))
		l.add_theme_constant_override("outline_size", 3)
		badges.add_child(l)


func _draw() -> void:
	if not unit.alive():
		return
	var x := size.x / 2.0 - BAR_W / 2.0
	var y := -8.0
	draw_rect(Rect2(x - 1, y - 1, BAR_W + 2, 6), Color("1c1428"))
	draw_rect(Rect2(x, y, BAR_W, 4), Color("4a3140"))
	var col := Color("6cd46a") if unit.is_ally else Color("ff6a6a")
	draw_rect(Rect2(x, y, floorf(BAR_W * unit.hp_ratio()), 4), col)
	if unit.shield > 0.0:
		var sw := floorf(BAR_W * clampf(unit.shield / unit.max_hp, 0.0, 1.0))
		draw_rect(Rect2(x, y - 3, sw, 2), Color("dff4ff"))


## Step toward a point and back (melee).
func lunge(to: Vector2) -> void:
	var dir := (to - home).normalized()
	var tw := create_tween()
	tw.tween_property(sprite, "position:x", dir.x * 14.0, 0.08)
	tw.tween_property(sprite, "position:x", 0.0, 0.14)


func hit() -> void:
	var tw := create_tween()
	sprite.modulate = Color(1.0, 0.45, 0.45)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.25)
	tw.parallel().tween_property(sprite, "position:x", 3.0, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.05)


func glow(col: Color) -> void:
	var tw := create_tween()
	sprite.modulate = col.lerp(Color.WHITE, 0.3)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.4)


func faint() -> void:
	queue_redraw()
	badges.visible = false
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.5, 0.45, 0.6, 0.35), 0.5)
