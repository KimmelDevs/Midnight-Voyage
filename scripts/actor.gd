class_name Actor
extends Node2D
## Isometric character: 3-column sprite sheet (walk1, stand, walk2).
## 4-row sheets = SE, SW, NE, NW.  2-row sheets = SW, NW (mirrored for SE/NE).

signal arrived

enum Dir { SE, SW, NE, NW }
const WALK_CYCLE := [0, 1, 2, 1]

var sprite: Sprite2D
var row_map := {Dir.SE: [0, false], Dir.SW: [1, false], Dir.NE: [2, false], Dir.NW: [3, false]}
var dir: int = Dir.SE
var tile := Vector2i.ZERO
var speed := 42.0
var path: Array[Vector2] = []
var path_tiles: Array[Vector2i] = []
var anim_t := 0.0
var bubble: Bubble
var carry: Sprite2D


func setup(tex: Texture2D, rows: int) -> void:
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.hframes = 3
	sprite.vframes = rows
	var frame_h := tex.get_height() / rows
	sprite.offset = Vector2(0, -frame_h / 2 + 3)
	add_child(sprite)
	if rows == 2:
		row_map = {Dir.SE: [0, true], Dir.SW: [0, false], Dir.NE: [1, true], Dir.NW: [1, false]}
	bubble = Bubble.new()
	bubble.position = Vector2(0, -frame_h - 2)
	bubble.visible = false
	add_child(bubble)
	carry = Sprite2D.new()
	carry.position = Vector2(0, -frame_h + 6)
	carry.visible = false
	add_child(carry)
	_set_frame(1)


## Walk along tile centres. Await it: `await actor.go(points, tiles)`.
func go(points: Array[Vector2], tiles: Array[Vector2i]) -> void:
	if points.is_empty():
		return
	path = points
	path_tiles = tiles
	await arrived


func face(d: int) -> void:
	dir = d
	_set_frame(1)


## Sitting pose. sit_tex is a single SW-facing sitting frame (mirrored for SE);
## without it (or facing away) the standing frame is lifted onto the seat.
var sit_tex: Texture2D
var _stand_tex: Texture2D
var _stand_frames := Vector2i.ZERO
var _stand_offset := Vector2.ZERO
var sitting := false


func sit(d: int) -> void:
	dir = d
	sitting = true
	position += Vector2(0, -3)
	if sit_tex and (d == Dir.SE or d == Dir.SW):
		_stand_tex = sprite.texture
		_stand_frames = Vector2i(sprite.hframes, sprite.vframes)
		_stand_offset = sprite.offset
		sprite.texture = sit_tex
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		sprite.flip_h = d == Dir.SE
		sprite.offset = Vector2(0, -sit_tex.get_height() / 2 + 3)
	else:
		_set_frame(1)


func stand() -> void:
	if not sitting:
		return
	sitting = false
	position += Vector2(0, 3)
	if _stand_tex:
		sprite.texture = _stand_tex
		sprite.hframes = _stand_frames.x
		sprite.vframes = _stand_frames.y
		sprite.offset = _stand_offset
		_stand_tex = null
	_set_frame(1)


func face_tile(t: Vector2i) -> void:
	var d := t - tile
	if d.x > 0:
		face(Dir.SE)
	elif d.x < 0:
		face(Dir.NW)
	elif d.y > 0:
		face(Dir.SW)
	elif d.y < 0:
		face(Dir.NE)


func _process(delta: float) -> void:
	if path.is_empty():
		return
	var target := path[0]
	var step := target - position
	if absf(step.x) > 0.5:
		var going_down := step.y > 0
		if step.x > 0:
			dir = Dir.SE if going_down else Dir.NE
		else:
			dir = Dir.SW if going_down else Dir.NW
	var move := speed * delta
	if step.length() <= move:
		position = target
		path.pop_front()
		tile = path_tiles.pop_front()
		if path.is_empty():
			_set_frame(1)
			arrived.emit()
			return
	else:
		position += step.normalized() * move
	anim_t += delta * speed / 22.0
	_set_frame(WALK_CYCLE[int(anim_t * 2.0) % 4])


func _set_frame(col: int) -> void:
	var rm: Array = row_map[dir]
	sprite.frame = int(rm[0]) * 3 + col
	sprite.flip_h = rm[1]


## Speech bubble with an icon and an optional progress bar.
class Bubble extends Node2D:
	var icon: Texture2D
	var progress := -1.0
	var bar_color := Color("6cc46a")

	func show_icon(tex: Texture2D) -> void:
		icon = tex
		visible = true
		queue_redraw()

	func set_progress(p: float, col: Color = Color("6cc46a")) -> void:
		progress = p
		bar_color = col
		queue_redraw()

	func _draw() -> void:
		var w := 26.0
		var h := 24.0
		if icon:
			w = maxf(w, icon.get_width() + 6.0)
			h = maxf(h, icon.get_height() + 6.0)
		var r := Rect2(-w / 2, -h, w, h)
		draw_rect(r.grow(1), Color("3b2a33"))
		draw_rect(r, Color("fff6ea"))
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, 4)]), Color("3b2a33"))
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 0), Vector2(2, 0), Vector2(0, 3)]), Color("fff6ea"))
		if icon:
			draw_texture(icon, Vector2(-icon.get_width() / 2, -h / 2 - icon.get_height() / 2).floor())
		if progress >= 0.0:
			var b := Rect2(-w / 2, -h - 5, w, 3)
			draw_rect(b.grow(1), Color("3b2a33"))
			draw_rect(Rect2(b.position, Vector2(floorf(w * clampf(progress, 0, 1)), 3)), bar_color)
