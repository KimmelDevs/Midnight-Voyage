extends Node2D
## Midnight Voyage level editor. Run this scene (F6), pick a piece from the
## palette, place it on the isometric grid, then Save: it writes
##   res://scenes/levels/<name>.tscn  - a normal Godot scene of Sprite2D nodes
##   res://scenes/levels/<name>.json  - the layout, so Load can edit it again
##
## Controls: left click place - right click erase - R rotate - G grid
##           middle-drag / WASD pan - mouse wheel zoom - Tab hide palette
##
## Piece kinds
##   floor : ground tile centred on a cell (one per cell)
##   object: furniture / props standing on a cell (one per cell), R turns it
##   edge  : walls, hull, rails, cliffs laid along a cell edge (R picks the edge)
##   free  : bow, stern, propellers, dome... placed at a cell, R mirrors

const HW := 29
const HH := 18
const SAVE_DIR := "res://scenes/levels"
const ROT_NAMES := ["SE", "SW", "NW", "NE"]

var pieces: Array = []          # palette: {name, cat, kind, tex, ...}
var meta := {}                  # edge anchors from the kits
var entries: Array = []         # placed: {piece, c, r, rot}
var selected := -1
var rot := 0
var hover := Vector2i.ZERO

var floor_layer: Node2D
var back_layer: Node2D
var world: Node2D
var grid: Node2D
var ghost: Node2D
var camera: Camera2D
var ui: CanvasLayer
var palette_panel: PanelContainer
var name_edit: LineEdit
var load_opt: OptionButton
var status: Label
var sel_label: Label
var nodes := {}                 # entry index -> Node2D (rebuilt each change)


# ------------------------------------------------------------------ setup
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("2a2140"))
	for path in ["res://assets/ship/kit.json", "res://assets/walls/walls.json", "res://assets/island/island.json"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			meta.merge(JSON.parse_string(f.get_as_text()), true)
	_build_palette()
	floor_layer = Node2D.new()
	floor_layer.z_index = -10
	add_child(floor_layer)
	back_layer = Node2D.new()
	back_layer.z_index = -9
	add_child(back_layer)
	grid = GridDraw.new()
	grid.z_index = -8
	add_child(grid)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	ghost = Node2D.new()
	ghost.z_index = 100
	ghost.modulate = Color(1, 1, 1, 0.6)
	add_child(ghost)
	camera = Camera2D.new()
	camera.position = Vector2(0, 120)
	add_child(camera)
	_build_ui()
	_refresh_load_list()
	_select(0)
	if "--test-editor" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


## Headless check: place one of every piece, save, reload the saved scene.
func _self_test() -> void:
	var find := func(n: String) -> int:
		for i in pieces.size():
			if pieces[i]["name"] == n:
				return i
		return 0
	for c in 5:
		for r in 4:
			entries.append({"piece": find.call("Wood floor"), "c": c, "r": r, "rot": 0})
	for c in 5:
		entries.append({"piece": find.call("Wall Plain" if c != 2 else "Wall Window"), "c": c, "r": 0, "rot": 3})
	for r in 4:
		entries.append({"piece": find.call("Wall Art" if r == 1 else "Wall Plain"), "c": 0, "r": r, "rot": 2})
	for i in pieces.size():
		if pieces[i]["cat"] == "Furniture" and entries.size() < 40:
			entries.append({"piece": i, "c": 1 + (i % 4), "r": 1 + (i / 4) % 3, "rot": i % 4})
	for c in range(0, 6, 2):
		entries.append({"piece": find.call("Hull A"), "c": c, "r": 3, "rot": 1})
	_rebuild()
	name_edit.text = "editor_test"
	_save()
	var n := entries.size()
	_load_selected()
	print("EDITOR_TEST pieces=%d saved=%d loaded=%d" % [pieces.size(), n, entries.size()])
	get_tree().quit()


func tile_pos(t: Vector2i) -> Vector2:
	return Vector2((t.x - t.y) * HW, (t.x + t.y) * HH + HH)


func pos_tile(p: Vector2) -> Vector2i:
	var q := p - Vector2(0, HH)
	var a := q.x / HW
	var b := q.y / HH
	return Vector2i(roundi((a + b) / 2.0), roundi((b - a) / 2.0))


func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _add(name: String, cat: String, kind: String, tex_path: String, extra: Dictionary = {}) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var p := {"name": name, "cat": cat, "kind": kind, "tex": tex_path}
	p.merge(extra, true)
	pieces.append(p)


func _build_palette() -> void:
	# floors
	_add("Wood floor", "Floors", "floor", "res://assets/cafe/floor_wood.png", {"centre": [29, 18]})
	_add("Checker floor", "Floors", "floor", "res://assets/cafe/floor_check.png", {"centre": [29, 18]})
	for n in ["grass", "grass_flowers", "path", "pier"]:
		var c: Array = meta.get(n, {}).get("centre", [30, 18])
		_add(n.capitalize(), "Floors", "floor", "res://assets/island/%s.png" % n, {"centre": c})
	# furniture (same art + facing rules as the game)
	for item in GS.ITEMS:
		var d: Dictionary = GS.ITEMS[item]
		if d["kind"] == "wall":
			continue
		_add(d["name"], "Furniture", "object", GS.item_tex_path(item),
			{"item": item, "foot": 6.0 if d["kind"] == "rug" else 12.0})
	# walls (one tile edge)
	for n in ["wall_plain", "wall_art", "wall_window", "wall_shelf", "wall_door", "wall_post"]:
		_add(n.replace("wall_", "Wall ").capitalize(), "Walls", "free" if n == "wall_post" else "edge",
			"res://assets/walls/%s.png" % n, {"anchor": "bottom", "span": 1, "meta": n})
	_add("Cabin wall (window)", "Walls", "edge", "res://assets/ship/wall_window_a.png", {"anchor": "bottom", "span": 2, "meta": "wall_window_a"})
	# ship kit
	for n in ["hull_a", "hull_port", "hull_b", "hull_port_b"]:
		_add(n.capitalize(), "Ship", "edge", "res://assets/ship/%s.png" % n, {"anchor": "top", "span": 2, "meta": n})
	_add("Railing", "Ship", "edge", "res://assets/ship/rail_a.png", {"anchor": "bottom", "span": 2, "meta": "rail_a"})
	for n in ["bow", "stern", "propeller", "gangway", "dome", "awning", "post"]:
		_add(n.capitalize(), "Ship", "free", "res://assets/ship/%s.png" % n, {"foot": 6.0})
	# island kit
	for n in ["cliff_a", "cliff_roots", "cliff_crystal"]:
		_add(n.capitalize(), "Island", "edge", "res://assets/island/%s.png" % n, {"anchor": "top", "span": 2, "meta": n})
	for n in ["tree", "bush", "lamp", "crates", "pump", "crane"]:
		_add(n.capitalize(), "Island", "object", "res://assets/island/%s.png" % n, {"foot": 8.0})
	_add("Shipyard (2x2)", "Island", "object", "res://assets/island/shipyard.png", {"foot": -10.0})
	for n in ["tip", "pier_post"]:
		_add(n.capitalize(), "Island", "free", "res://assets/island/%s.png" % n, {"foot": 0.0})


# ------------------------------------------------------------------ UI
func _sb(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_content_margin_all(4)
	return s


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _sb(Color("f7e9d3"), Color("6b4630")))
	top.position = Vector2(176, 4)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	top.add_child(hb)
	name_edit = LineEdit.new()
	name_edit.text = "my_level"
	name_edit.custom_minimum_size = Vector2(90, 0)
	hb.add_child(name_edit)
	for pair in [["Save", _save], ["Load", _load_selected], ["Clear", _clear]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		hb.add_child(b)
	load_opt = OptionButton.new()
	load_opt.custom_minimum_size = Vector2(90, 0)
	hb.add_child(load_opt)

	palette_panel = PanelContainer.new()
	palette_panel.add_theme_stylebox_override("panel", _sb(Color("f7e9d3"), Color("6b4630")))
	palette_panel.position = Vector2(4, 4)
	palette_panel.custom_minimum_size = Vector2(168, 352)
	palette_panel.size = Vector2(168, 352)
	root.add_child(palette_panel)
	var tabs := TabContainer.new()
	palette_panel.add_child(tabs)
	var cats := {}
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		if not cats.has(p["cat"]):
			var sc := ScrollContainer.new()
			sc.name = p["cat"]
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			tabs.add_child(sc)
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 2)
			g.add_theme_constant_override("v_separation", 2)
			sc.add_child(g)
			cats[p["cat"]] = g
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 44)
		b.icon = _tex(p["tex"])
		b.expand_icon = true
		b.tooltip_text = "%s (%s)" % [p["name"], p["kind"]]
		b.pressed.connect(_select.bind(i))
		cats[p["cat"]].add_child(b)

	sel_label = Label.new()
	sel_label.position = Vector2(180, 30)
	sel_label.add_theme_color_override("font_color", Color("fff6ea"))
	sel_label.add_theme_color_override("font_outline_color", Color("1c1428"))
	sel_label.add_theme_constant_override("outline_size", 4)
	root.add_child(sel_label)
	status = Label.new()
	status.position = Vector2(180, 342)
	status.add_theme_color_override("font_color", Color("ffe08a"))
	status.add_theme_color_override("font_outline_color", Color("1c1428"))
	status.add_theme_constant_override("outline_size", 4)
	status.text = "Left click place  Right click erase  R rotate  G grid  Wheel zoom  Tab palette"
	root.add_child(status)


func _select(i: int) -> void:
	selected = i
	var p: Dictionary = pieces[i]
	sel_label.text = "%s  [%s]  facing %s" % [p["name"], p["kind"], ROT_NAMES[rot]]
	_update_ghost()


# ------------------------------------------------------------------ building nodes
## Create the Node2D for one placed entry (also used for the ghost and the save).
func _make(e: Dictionary) -> Dictionary:
	var p: Dictionary = pieces[e["piece"]]
	var t := Vector2i(e["c"], e["r"])
	var r: int = e["rot"]
	var tx := _tex(p["tex"])
	var out := {"layer": "world", "holder": Vector2.ZERO, "tex": p["tex"], "flip": false,
		"offset": Vector2.ZERO, "xf": Transform2D.IDENTITY}
	match p["kind"]:
		"floor":
			var c: Array = p["centre"]
			out["layer"] = "floor"
			out["xf"] = Transform2D(0, (tile_pos(t) - Vector2(c[0], c[1])).round())
		"object":
			var flip := false
			if p.has("item"):
				var look := _item_look(p["item"], r)
				out["tex"] = look[0]
				flip = look[1]
				tx = _tex(look[0])
			else:
				flip = r % 2 == 1
			out["flip"] = flip
			out["offset"] = Vector2(-tx.get_width() / 2.0, -tx.get_height() + float(p.get("foot", 10.0))).round()
			out["holder"] = tile_pos(t)
		"free":
			out["flip"] = r % 2 == 1
			out["offset"] = Vector2(-tx.get_width() / 2.0, -tx.get_height() + float(p.get("foot", 6.0))).round()
			out["holder"] = tile_pos(t) + Vector2(0, HH)
		"edge":
			var pts := _edge_points(t, r, int(p["span"]))
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[1]
			var m: Array = meta[p["meta"]][p["anchor"]]
			var s := Vector2(m[0][0], m[0][1])
			var en := Vector2(m[1][0], m[1][1])
			var sx := (b.x - a.x) / (en.x - s.x)
			var k := (b.y - a.y - (en.y - s.y)) / (en.x - s.x)
			var holder := ((a + b) / 2.0 + Vector2(0, 2)).round()
			out["layer"] = "back" if r >= 2 and p["anchor"] == "top" else "world"
			out["holder"] = holder
			out["xf"] = Transform2D(Vector2(sx, k), Vector2(0, 1), a - Vector2(sx * s.x, s.y + k * s.x) - holder)
	return out


func _item_look(item: String, r: int) -> Array:
	var native := int(GS.ITEMS[item].get("faces", 1))
	var path := GS.item_tex_path(item)
	if r >= 2:
		var back := path.replace(".png", "_back.png")
		if ResourceLoader.exists(back):
			return [back, (r != native + 2) != bool(GS.ITEMS[item].get("back_flip", false))]
		r -= 2
	return [path, r != native]


## Edge end points (span 1 or 2 tiles along the edge), ordered so the art
## (drawn running down-right) maps on; down-left edges come out mirrored.
func _edge_points(t: Vector2i, r: int, span: int) -> Array:
	var p := tile_pos(t)
	var top := p + Vector2(0, -HH)
	var right := p + Vector2(HW, 0)
	var bottom := p + Vector2(0, HH)
	var left := p + Vector2(-HW, 0)
	var step := Vector2(-HW, HH) if r % 2 == 0 else Vector2(HW, HH)   # along the edge
	var more := step * (span - 1)
	match r:
		0: return [right, bottom + more]
		1: return [left, bottom + more]
		2: return [top, left + more]
	return [top, right + more]


func _node_for(info: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.position = info["holder"]
	var s := Sprite2D.new()
	s.texture = _tex(info["tex"])
	s.centered = false
	s.flip_h = info["flip"]
	s.offset = info["offset"]
	s.transform = info["xf"]
	holder.add_child(s)
	return holder


func _rebuild() -> void:
	for n in nodes.values():
		n.queue_free()
	nodes.clear()
	var order := range(entries.size())
	order.sort_custom(func(a, b): return entries[a]["c"] + entries[a]["r"] < entries[b]["c"] + entries[b]["r"])
	for i in order:
		var info := _make(entries[i])
		var n := _node_for(info)
		match info["layer"]:
			"floor": floor_layer.add_child(n)
			"back": back_layer.add_child(n)
			_: world.add_child(n)
		nodes[i] = n


func _update_ghost() -> void:
	for ch in ghost.get_children():
		ch.queue_free()
	if selected < 0:
		return
	var info := _make({"piece": selected, "c": hover.x, "r": hover.y, "rot": rot})
	ghost.add_child(_node_for(info))


# ------------------------------------------------------------------ editing
func _slot(e: Dictionary) -> String:
	var p: Dictionary = pieces[e["piece"]]
	match p["kind"]:
		"floor": return "f%d,%d" % [e["c"], e["r"]]
		"object": return "o%d,%d" % [e["c"], e["r"]]
		"edge": return "e%d,%d,%d,%s" % [e["c"], e["r"], e["rot"], p["anchor"]]
	return "x%d,%d,%s" % [e["c"], e["r"], p["name"]]


func _place() -> void:
	if selected < 0:
		return
	var e := {"piece": selected, "c": hover.x, "r": hover.y, "rot": rot}
	var slot := _slot(e)
	for i in range(entries.size() - 1, -1, -1):
		if _slot(entries[i]) == slot:
			entries.remove_at(i)  # replace whatever was in this slot
	entries.append(e)
	_rebuild()


## Erase the top-most thing under the cursor: object/free, then edge, then floor.
func _erase() -> void:
	for kinds in [["object", "free"], ["edge"], ["floor"]]:
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			if e["c"] == hover.x and e["r"] == hover.y and pieces[e["piece"]]["kind"] in kinds:
				entries.remove_at(i)
				_rebuild()
				return


func _clear() -> void:
	entries.clear()
	_rebuild()
	status.text = "Cleared."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			camera.position -= event.relative / camera.zoom
		var t := pos_tile(get_global_mouse_position())
		if t != hover:
			hover = t
			grid.set("hover", hover)
			grid.queue_redraw()
			_update_ghost()
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_place()   # paint by dragging
			elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_erase()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _place()
			MOUSE_BUTTON_RIGHT: _erase()
			MOUSE_BUTTON_WHEEL_UP: camera.zoom = (camera.zoom * 2.0).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
			MOUSE_BUTTON_WHEEL_DOWN: camera.zoom = (camera.zoom * 0.5).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
	elif event is InputEventKey and event.pressed and not name_edit.has_focus():
		match event.keycode:
			KEY_R:
				rot = (rot + 1) % 4
				_select(selected)
			KEY_G:
				grid.visible = not grid.visible
			KEY_TAB:
				palette_panel.visible = not palette_panel.visible


func _process(delta: float) -> void:
	if name_edit.has_focus():
		return
	var pan := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	camera.position += pan * 260.0 * delta / camera.zoom.x


# ------------------------------------------------------------------ save / load
func _save() -> void:
	var n := name_edit.text.strip_edges().validate_filename().replace(" ", "_")
	if n == "":
		status.text = "Type a name first."
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var layout: Array = []
	for e in entries:
		layout.append({"piece": pieces[e["piece"]]["tex"], "kind": pieces[e["piece"]]["kind"],
			"name": pieces[e["piece"]]["name"], "c": e["c"], "r": e["r"], "rot": e["rot"]})
	var jf := FileAccess.open("%s/%s.json" % [SAVE_DIR, n], FileAccess.WRITE)
	jf.store_string(JSON.stringify({"version": 1, "entries": layout}, "\t"))
	jf.close()
	var tf := FileAccess.open("%s/%s.tscn" % [SAVE_DIR, n], FileAccess.WRITE)
	tf.store_string(_scene_text(n))
	tf.close()
	status.text = "Saved %s/%s.tscn (+ .json). Godot picks it up when you click back into the editor." % [SAVE_DIR, n]
	_refresh_load_list()


func _f(v: float) -> String:
	return str(snappedf(v, 0.0001))


## Text of a .tscn: Floor (z -10), Back (z -9) and a y-sorted World, each piece
## a Node2D holder with one Sprite2D child.
func _scene_text(scene_name: String) -> String:
	var res_ids := {}
	var lines: Array[String] = []
	var infos: Array = []
	var order := range(entries.size())
	order.sort_custom(func(a, b): return entries[a]["c"] + entries[a]["r"] < entries[b]["c"] + entries[b]["r"])
	for i in order:
		var info := _make(entries[i])
		if not res_ids.has(info["tex"]):
			res_ids[info["tex"]] = str(res_ids.size() + 1)
		infos.append(info)
	var head := "[gd_scene load_steps=%d format=3]\n\n" % (res_ids.size() + 1)
	for path in res_ids:
		head += '[ext_resource type="Texture2D" path="%s" id="%s"]\n' % [path, res_ids[path]]
	lines.append('[node name="%s" type="Node2D"]' % scene_name.to_pascal_case())
	lines.append('[node name="Floor" type="Node2D" parent="."]\nz_index = -10')
	lines.append('[node name="Back" type="Node2D" parent="."]\nz_index = -9')
	lines.append('[node name="World" type="Node2D" parent="."]\ny_sort_enabled = true')
	var count := 0
	for info in infos:
		count += 1
		var parent: String = {"floor": "Floor", "back": "Back"}.get(info["layer"], "World")
		var hn := "%s_%d" % [str(info["tex"]).get_file().get_basename(), count]
		var hp: Vector2 = info["holder"]
		lines.append('[node name="%s" type="Node2D" parent="%s"]\nposition = Vector2(%s, %s)' % [hn, parent, _f(hp.x), _f(hp.y)])
		var xf: Transform2D = info["xf"]
		var off: Vector2 = info["offset"]
		var sprite := '[node name="Sprite" type="Sprite2D" parent="%s/%s"]\n' % [parent, hn]
		sprite += 'texture = ExtResource("%s")\ncentered = false\n' % res_ids[info["tex"]]
		if info["flip"]:
			sprite += "flip_h = true\n"
		if off != Vector2.ZERO:
			sprite += "offset = Vector2(%s, %s)\n" % [_f(off.x), _f(off.y)]
		sprite += "transform = Transform2D(%s, %s, %s, %s, %s, %s)" % [_f(xf.x.x), _f(xf.x.y), _f(xf.y.x), _f(xf.y.y),
			_f(xf.origin.x), _f(xf.origin.y)]
		lines.append(sprite)
	return head + "\n" + "\n\n".join(lines) + "\n"


func _refresh_load_list() -> void:
	load_opt.clear()
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			load_opt.add_item(f.get_basename())


func _load_selected() -> void:
	if load_opt.item_count == 0:
		status.text = "Nothing saved yet."
		return
	var n := load_opt.get_item_text(load_opt.selected)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [SAVE_DIR, n]))
	if typeof(parsed) != TYPE_DICTIONARY:
		status.text = "Could not read %s.json" % n
		return
	entries.clear()
	for e in parsed["entries"]:
		var idx := -1
		for i in pieces.size():
			if pieces[i]["tex"] == e["piece"] and pieces[i]["kind"] == e["kind"] and pieces[i]["name"] == e["name"]:
				idx = i
		if idx >= 0:
			entries.append({"piece": idx, "c": int(e["c"]), "r": int(e["r"]), "rot": int(e["rot"])})
	name_edit.text = n
	_rebuild()
	status.text = "Loaded %s (%d pieces)." % [n, entries.size()]


## Grid lines around the cursor area.
class GridDraw extends Node2D:
	var hover := Vector2i.ZERO

	func _draw() -> void:
		for c in range(-12, 24):
			for r in range(-12, 24):
				var p := Vector2((c - r) * 29, (c + r) * 18 + 18)
				var col := Color(1, 1, 1, 0.08)
				if Vector2i(c, r) == hover:
					col = Color(1, 0.95, 0.6, 0.9)
				draw_polyline(PackedVector2Array([p + Vector2(0, -18), p + Vector2(29, 0), p + Vector2(0, 18),
					p + Vector2(-29, 0), p + Vector2(0, -18)]), col, 1.0)
				if c == 0 and r == 0:
					draw_circle(p, 2, Color(1, 0.4, 0.4, 0.8))
