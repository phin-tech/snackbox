class_name Gridlock
extends Node2D

# Sliding traffic jam, after Rush Hour. Cars and trucks only move along their
# own axis; shuffle them until the red car can reach the gap on the right.
#
# Boards are generated backwards from the finished position: park the red car
# at the exit, drop in the other vehicles, then make random legal moves. Every
# move is reversible, so whatever state the scramble lands in can always be
# driven back to the exit. The scramble is kept so tests can replay it.

signal exit_to_menu

const SIZE := 6
const EXIT_ROW := 2
const BOARD_PX := 432.0
const ORIGIN := Vector2(84, 210)

const COLORS := [
	Color("3d8be0"),  # blue
	Color("f2b705"),  # yellow
	Color("46ac5c"),  # green
	Color("f0822f"),  # orange
	Color("8f5fc0"),  # purple
	Color("28c2c2"),  # teal
	Color("e069a8"),  # pink
	Color("9b9790"),  # grey
]
const TARGET_COLOR := Color("ff3b30")

var vehicles := []            # [{pos: Vector2i, len: int, horiz: bool}]
var scramble := []            # [{v: int, d: int}] applied from solved -> start
var level := 1
var moves := 0
var selected := -1
var solved := false
var cursor := Vector2i(0, EXIT_ROW)
var drag_from := Vector2i.ZERO
var dragging := false


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	_start_level()


func _start_level() -> void:
	_generate()
	moves = 0
	solved = false
	selected = 0
	dragging = false
	cursor = vehicles[0].pos
	queue_redraw()


func cell_px() -> float:
	return BOARD_PX / float(SIZE)


# --- Board ---------------------------------------------------------------------

func cells_of(v: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in v.len:
		out.append(v.pos + (Vector2i(i, 0) if v.horiz else Vector2i(0, i)))
	return out


func occupancy(ignore := -1) -> Dictionary:
	var occ := {}
	for i in vehicles.size():
		if i == ignore:
			continue
		for c in cells_of(vehicles[i]):
			occ[c] = i
	return occ


func can_move(index: int, step: int) -> bool:
	if index < 0 or index >= vehicles.size() or step == 0:
		return false
	var v: Dictionary = vehicles[index]
	var occ := occupancy(index)
	var delta := Vector2i(step, 0) if v.horiz else Vector2i(0, step)
	for c in cells_of(v):
		var n: Vector2i = c + delta
		if n.x < 0 or n.x >= SIZE or n.y < 0 or n.y >= SIZE:
			return false
		if occ.has(n):
			return false
	return true


func move_vehicle(index: int, step: int) -> bool:
	# One cell at a time, so a long slide is just several legal moves.
	var dir := signi(step)
	if dir == 0:
		return false
	var moved := false
	for _i in absi(step):
		if not can_move(index, dir):
			break
		var v: Dictionary = vehicles[index]
		v.pos += Vector2i(dir, 0) if v.horiz else Vector2i(0, dir)
		vehicles[index] = v
		moved = true
	if moved:
		moves += 1
		_check_solved()
		queue_redraw()
	return moved


func is_solved() -> bool:
	var t: Dictionary = vehicles[0]
	return t.pos.x + t.len >= SIZE


func _check_solved() -> void:
	if solved or not is_solved():
		return
	solved = true
	Scores.submit_high("gridlock", level)


# --- Generation ----------------------------------------------------------------

func _fits(v: Dictionary, placed: Array) -> bool:
	for c in cells_of(v):
		if c.x < 0 or c.x >= SIZE or c.y < 0 or c.y >= SIZE:
			return false
		for other in placed:
			for oc in cells_of(other):
				if oc == c:
					return false
	return true


func _generate() -> void:
	# Build, and reject any board that happens to land back on the finished
	# position. Nudging a stuck board out of it is not always possible - the
	# red car can be walled in at the exit - so start over instead.
	for _attempt in 24:
		_build_once()
		if not is_solved():
			return
	# Nothing usable after all that: back the red car off by force so the
	# player is at least handed a board they can play.
	while is_solved() and move_vehicle(0, -1):
		pass
	moves = 0


func _build_once() -> void:
	# Start from the finished position: red car parked at the exit.
	var target := {"pos": Vector2i(SIZE - 2, EXIT_ROW), "len": 2, "horiz": true}
	vehicles = [target]

	var wanted: int = clampi(4 + level / 2, 4, 10)
	var attempts := 0
	while vehicles.size() < wanted + 1 and attempts < 600:
		attempts += 1
		var horiz := randi() % 2 == 0
		var length := 2 if randf() < 0.72 else 3
		var v := {
			"pos": Vector2i(randi() % SIZE, randi() % SIZE),
			"len": length,
			"horiz": horiz,
		}
		if _fits(v, vehicles):
			vehicles.append(v)

	# Now shuffle by making legal moves. Every one is reversible, so the board
	# stays solvable no matter where this ends up.
	scramble = []
	var steps: int = 40 + level * 10
	for _i in steps:
		var idx := randi() % vehicles.size()
		var dir := 1 if randi() % 2 == 0 else -1
		if can_move(idx, dir):
			var v: Dictionary = vehicles[idx]
			v.pos += Vector2i(dir, 0) if v.horiz else Vector2i(0, dir)
			vehicles[idx] = v
			scramble.append({"v": idx, "d": dir})


# --- Input ---------------------------------------------------------------------

func vehicle_at(cell: Vector2i) -> int:
	for i in vehicles.size():
		for c in cells_of(vehicles[i]):
			if c == cell:
				return i
	return -1


func cell_at(point: Vector2) -> Vector2i:
	var local := point - ORIGIN
	return Vector2i(int(floor(local.x / cell_px())), int(floor(local.y / cell_px())))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var cell := cell_at(get_local_mouse_position())
				var idx := vehicle_at(cell)
				if idx != -1:
					selected = idx
					drag_from = cell
					dragging = true
					cursor = cell
			else:
				dragging = false
			queue_redraw()
		return

	if event is InputEventMouseMotion and dragging and selected != -1:
		var cell := cell_at(get_local_mouse_position())
		var v: Dictionary = vehicles[selected]
		var delta: int = (cell.x - drag_from.x) if v.horiz else (cell.y - drag_from.y)
		if delta != 0:
			if move_vehicle(selected, delta):
				drag_from = cell
			else:
				drag_from = cell     # blocked; re-anchor so it doesn't fight
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			_start_level()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if solved:
				level += 1
				_start_level()
			else:
				var idx := vehicle_at(cursor)
				if idx != -1:
					selected = idx
				queue_redraw()
		KEY_TAB:
			selected = (selected + 1) % vehicles.size()
			cursor = vehicles[selected].pos
			queue_redraw()
		KEY_LEFT, KEY_A:
			_drive(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			_drive(Vector2i(1, 0))
		KEY_UP, KEY_W:
			_drive(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			_drive(Vector2i(0, 1))


func _drive(dir: Vector2i) -> void:
	# Arrows push the selected vehicle when the direction matches its axis, and
	# otherwise walk the cursor so another one can be picked.
	if selected != -1:
		var v: Dictionary = vehicles[selected]
		if v.horiz and dir.y == 0:
			if move_vehicle(selected, dir.x):
				cursor = vehicles[selected].pos
				return
		elif not v.horiz and dir.x == 0:
			if move_vehicle(selected, dir.y):
				cursor = vehicles[selected].pos
				return
	var target := cursor + dir
	if target.x >= 0 and target.x < SIZE and target.y >= 0 and target.y < SIZE:
		cursor = target
		var idx := vehicle_at(cursor)
		if idx != -1:
			selected = idx
	queue_redraw()


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	var s := cell_px()
	var board := Rect2(ORIGIN, Vector2(BOARD_PX, BOARD_PX))
	draw_rect(board, Blocks.PAPER_SUNK)

	for i in range(1, SIZE):
		draw_line(ORIGIN + Vector2(i * s, 0), ORIGIN + Vector2(i * s, BOARD_PX), Blocks.GRID_LINE)
		draw_line(ORIGIN + Vector2(0, i * s), ORIGIN + Vector2(BOARD_PX, i * s), Blocks.GRID_LINE)

	# The gap in the wall the red car is aiming for.
	var gap_y := ORIGIN.y + EXIT_ROW * s
	draw_rect(Rect2(ORIGIN.x + BOARD_PX + 3, gap_y + 4, 7, s - 8), Blocks.RED)
	Blocks.tracked(self, Vector2(ORIGIN.x + BOARD_PX + 16, gap_y + s * 0.5 + 4), "EXIT", 10, Blocks.RED)

	for i in vehicles.size():
		var v: Dictionary = vehicles[i]
		var w: float = (v.len if v.horiz else 1) * s
		var h: float = (1 if v.horiz else v.len) * s
		var rect := Rect2(ORIGIN + Vector2(v.pos.x * s, v.pos.y * s), Vector2(w, h)).grow(-5)
		var col: Color = TARGET_COLOR if i == 0 else COLORS[(i - 1) % COLORS.size()]
		draw_rect(rect, col)
		# A darker slab down the middle reads as a windscreen.
		var inner := rect.grow(-9)
		if inner.size.x > 0 and inner.size.y > 0:
			draw_rect(inner, col.darkened(0.22))
		if i == selected:
			Blocks.outline(self, rect.grow(2), Blocks.INK, 2.0)

	if not solved:
		var cr := Rect2(ORIGIN + Vector2(cursor.x * s, cursor.y * s), Vector2(s, s))
		Blocks.outline(self, cr.grow(-2), Blocks.INK_FAINT, 1.0)

	Blocks.outline(self, board.grow(2), Blocks.INK, 1.0)
	_draw_hud()

	if solved:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "CLEAR",
			"%d MOVES        ENTER FOR LEVEL %d" % [moves, level + 1])


func _draw_hud() -> void:
	var x := ORIGIN.x

	Blocks.text(self, Vector2(x, 118), "GRIDLOCK", 34, Blocks.INK)
	Blocks.rule(self, Vector2(x, 132), BOARD_PX, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(x, 162), "LEVEL", str(level), 24)
	Blocks.stat(self, Vector2(x + 120, 162), "MOVES", str(moves), 24)
	Blocks.stat(self, Vector2(x + 240, 162), "CARS", str(vehicles.size()), 24)
	if Scores.has("gridlock"):
		Blocks.stat(self, Vector2(x + 340, 162), "BEST", "LVL %d" % int(Scores.get_best("gridlock")), 24)

	Blocks.rule(self, Vector2(x, 686), BOARD_PX, Blocks.INK, 1.0)
	var cy := 706.0
	for line in [
		"DRAG A CAR ALONG ITS OWN AXIS - OR ARROWS TO PICK AND PUSH",
		"GET THE RED CAR OUT THROUGH THE GAP ON THE RIGHT",
		"TAB  NEXT CAR        R  NEW BOARD        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
