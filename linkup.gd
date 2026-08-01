class_name Linkup
extends Node2D

# Connect each pair of dots with a path, without crossing, until every cell on
# the board is used. Drag with the mouse, or drive the cursor with the arrows.
#
# Generation works backwards from a solution, which is what guarantees every
# level can actually be finished: build a Hamiltonian path over the whole grid,
# randomise it with backbite moves, then cut it into segments. Each segment is
# one colour's route, its two ends are the dots, and because the segments came
# from a single path covering every cell, laying them all back down fills the
# board exactly.

signal exit_to_menu

const MIN_SIZE := 5
const MAX_SIZE := 8
const BOARD_PX := 440.0
const ORIGIN := Vector2(80, 190)

const COLORS := [
	Color("ff3b30"),  # red
	Color("3d8be0"),  # blue
	Color("f2b705"),  # yellow
	Color("46ac5c"),  # green
	Color("f0822f"),  # orange
	Color("8f5fc0"),  # purple
	Color("28c2c2"),  # teal
	Color("e069a8"),  # pink
]

var size := MIN_SIZE
var level := 1
var owner_of := []            # owner_of[row][col] -> colour index, or -1
var endpoint_of := []         # endpoint_of[row][col] -> colour index, or -1
var pairs := []               # [{a, b, solution}]
var paths := {}               # colour index -> Array[Vector2i]

var active := -1              # colour currently being drawn
var cursor := Vector2i.ZERO
var dragging := false
var solved := false


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	_start_level()


func _start_level() -> void:
	size = clampi(MIN_SIZE + (level - 1) / 3, MIN_SIZE, MAX_SIZE)
	_generate()
	active = -1
	dragging = false
	solved = false
	cursor = pairs[0].a if not pairs.is_empty() else Vector2i.ZERO
	queue_redraw()


func cell_px() -> float:
	return BOARD_PX / float(size)


# --- Generation ---------------------------------------------------------------

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < size and c.y >= 0 and c.y < size


func _neighbours(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if _in_bounds(n):
			out.append(n)
	return out


func _hamiltonian() -> Array[Vector2i]:
	# Start from a boustrophedon sweep, which trivially covers every cell, then
	# shuffle it with backbite moves: join an end to a random neighbour, which
	# closes a loop, and break the edge that loop replaced. The result is still
	# a Hamiltonian path, just a far less orderly one.
	var path: Array[Vector2i] = []
	for r in size:
		for i in size:
			var c: int = i if r % 2 == 0 else size - 1 - i
			path.append(Vector2i(c, r))

	var index := {}
	for i in path.size():
		index[path[i]] = i

	var moves: int = size * size * 24
	for _m in moves:
		var from_head := randi() % 2 == 0
		if not from_head:
			path.reverse()
			index.clear()
			for i in path.size():
				index[path[i]] = i

		var head: Vector2i = path[0]
		var options := _neighbours(head)
		var pick: Vector2i = options[randi() % options.size()]
		var i: int = index[pick]
		if i < 2:
			continue        # already the neighbour along the path

		# Reverse the prefix so the broken edge becomes the new head.
		var prefix: Array[Vector2i] = path.slice(0, i)
		prefix.reverse()
		var rest: Array[Vector2i] = path.slice(i)
		path = prefix + rest
		index.clear()
		for k in path.size():
			index[path[k]] = k

	return path


func _pair_count() -> int:
	# Enough colours to be interesting, few enough that routes stay long.
	return clampi(3 + level / 2, 3, min(COLORS.size(), size + 1))


func _generate() -> void:
	owner_of = []
	endpoint_of = []
	for r in size:
		var a := []
		var b := []
		a.resize(size)
		b.resize(size)
		a.fill(-1)
		b.fill(-1)
		owner_of.append(a)
		endpoint_of.append(b)

	var path := _hamiltonian()
	var total := path.size()
	var count: int = _pair_count()

	# Cut the path into `count` runs, each at least two cells so a pair never
	# collapses onto a single square.
	var lengths: Array[int] = []
	for i in count:
		lengths.append(2)
	var spare: int = total - 2 * count
	for _i in spare:
		lengths[randi() % count] += 1

	pairs = []
	paths = {}
	var at := 0
	for i in count:
		var run: Array[Vector2i] = path.slice(at, at + lengths[i])
		at += lengths[i]
		pairs.append({"a": run[0], "b": run[run.size() - 1], "solution": run})
		endpoint_of[run[0].y][run[0].x] = i
		endpoint_of[run[run.size() - 1].y][run[run.size() - 1].x] = i
		owner_of[run[0].y][run[0].x] = i
		owner_of[run[run.size() - 1].y][run[run.size() - 1].x] = i
		paths[i] = [run[0]] as Array[Vector2i]

	# Endpoints start on the board; the routes between them do not.
	for i in count:
		paths[i] = [] as Array[Vector2i]


# --- Path editing -------------------------------------------------------------

func _clear_path(colour: int) -> void:
	for c in paths.get(colour, []):
		if endpoint_of[c.y][c.x] == -1:
			owner_of[c.y][c.x] = -1
	paths[colour] = [] as Array[Vector2i]


func _truncate_at(colour: int, cell: Vector2i) -> void:
	# Drop everything from `cell` onwards, so drawing over another route eats
	# the tail of it rather than corrupting it.
	var route: Array[Vector2i] = paths[colour]
	var idx := route.find(cell)
	if idx == -1:
		return
	for i in range(idx, route.size()):
		var c: Vector2i = route[i]
		if endpoint_of[c.y][c.x] == -1:
			owner_of[c.y][c.x] = -1
	paths[colour] = route.slice(0, idx)


func grab(cell: Vector2i) -> bool:
	if solved or not _in_bounds(cell):
		return false

	var ep: int = endpoint_of[cell.y][cell.x]
	if ep != -1:
		# Starting from a dot always begins that colour's route afresh.
		_clear_path(ep)
		active = ep
		paths[ep] = [cell] as Array[Vector2i]
		owner_of[cell.y][cell.x] = ep
		cursor = cell
		dragging = true
		return true

	var owner: int = owner_of[cell.y][cell.x]
	if owner != -1 and paths[owner].has(cell):
		# Grabbing partway along a route continues from there.
		var route: Array[Vector2i] = paths[owner]
		var idx := route.find(cell)
		_truncate_at(owner, route[idx + 1] if idx + 1 < route.size() else cell)
		if not paths[owner].has(cell):
			paths[owner].append(cell)
			owner_of[cell.y][cell.x] = owner
		active = owner
		cursor = cell
		dragging = true
		return true

	return false


func extend(cell: Vector2i) -> bool:
	if active == -1 or solved or not _in_bounds(cell):
		return false
	var route: Array[Vector2i] = paths[active]
	if route.is_empty():
		return false

	var head: Vector2i = route[route.size() - 1]
	if (cell - head).length() != 1:
		return false        # only ever one step at a time

	# Stepping back onto the previous cell rubs the route out behind you.
	if route.size() >= 2 and cell == route[route.size() - 2]:
		if endpoint_of[head.y][head.x] == -1:
			owner_of[head.y][head.x] = -1
		paths[active] = route.slice(0, route.size() - 1)
		cursor = cell
		return true

	var ep: int = endpoint_of[cell.y][cell.x]
	if ep != -1 and ep != active:
		return false        # another colour's dot is a wall

	if route.has(cell):
		return false        # no doubling back over yourself

	var owner: int = owner_of[cell.y][cell.x]
	if owner != -1 and owner != active:
		_truncate_at(owner, cell)

	route = paths[active]
	route.append(cell)
	paths[active] = route
	owner_of[cell.y][cell.x] = active
	cursor = cell

	if ep == active:
		# Reached the far dot: this colour is done.
		release()
	_check_solved()
	return true


func release() -> void:
	active = -1
	dragging = false


func pair_joined(colour: int) -> bool:
	var route: Array = paths.get(colour, [])
	if route.size() < 2:
		return false
	var p: Dictionary = pairs[colour]
	var first: Vector2i = route[0]
	var last: Vector2i = route[route.size() - 1]
	return (first == p.a and last == p.b) or (first == p.b and last == p.a)


func filled_cells() -> int:
	var n := 0
	for r in size:
		for c in size:
			if owner_of[r][c] != -1:
				n += 1
	return n


func connected_count() -> int:
	var n := 0
	for i in pairs.size():
		if pair_joined(i):
			n += 1
	return n


func _check_solved() -> void:
	# Classic rule: every pair joined *and* every cell used.
	if connected_count() != pairs.size():
		return
	if filled_cells() != size * size:
		return
	solved = true
	release()
	Scores.submit_high("linkup", level)


# --- Input --------------------------------------------------------------------

func cell_at(point: Vector2) -> Vector2i:
	var local := point - ORIGIN
	return Vector2i(int(floor(local.x / cell_px())), int(floor(local.y / cell_px())))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab(cell_at(get_local_mouse_position()))
			else:
				release()
			queue_redraw()
		return

	if event is InputEventMouseMotion and dragging:
		var target := cell_at(get_local_mouse_position())
		# Walk one cell at a time so a fast drag can't skip over squares.
		for _i in 8:
			var route: Array = paths.get(active, [])
			if route.is_empty():
				break
			var head: Vector2i = route[route.size() - 1]
			if head == target:
				break
			var step := head
			if target.x != head.x:
				step.x += signi(target.x - head.x)
			elif target.y != head.y:
				step.y += signi(target.y - head.y)
			if not extend(step):
				break
		queue_redraw()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			_start_level()
		KEY_N:
			_clear_all()
		KEY_ENTER, KEY_KP_ENTER:
			if solved:
				level += 1
				_start_level()
		KEY_SPACE:
			if solved:
				level += 1
				_start_level()
			elif active != -1:
				release()
			else:
				grab(cursor)
			queue_redraw()
		KEY_LEFT, KEY_A:
			_nudge(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			_nudge(Vector2i(1, 0))
		KEY_UP, KEY_W:
			_nudge(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			_nudge(Vector2i(0, 1))


func _nudge(dir: Vector2i) -> void:
	var target := cursor + dir
	if not _in_bounds(target):
		return
	# While a route is live the arrows draw it; otherwise they move the cursor.
	if active != -1:
		extend(target)
	else:
		cursor = target
	queue_redraw()


func _clear_all() -> void:
	for i in pairs.size():
		_clear_path(i)
	active = -1
	dragging = false
	solved = false          # an emptied board is no longer a finished one
	queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _cell_center(c: Vector2i) -> Vector2:
	var s := cell_px()
	return ORIGIN + Vector2((c.x + 0.5) * s, (c.y + 0.5) * s)


func _draw() -> void:
	var s := cell_px()
	var board := Rect2(ORIGIN, Vector2(BOARD_PX, BOARD_PX))
	draw_rect(board, Blocks.PAPER_SUNK)

	for i in range(1, size):
		var o := ORIGIN + Vector2(i * s, 0)
		draw_line(o, o + Vector2(0, BOARD_PX), Blocks.GRID_LINE)
		var o2 := ORIGIN + Vector2(0, i * s)
		draw_line(o2, o2 + Vector2(BOARD_PX, 0), Blocks.GRID_LINE)

	# Routes, drawn as a thick ribbon through the cell centres.
	var width := s * 0.40
	for i in pairs.size():
		var route: Array = paths.get(i, [])
		if route.size() < 2:
			continue
		var col: Color = COLORS[i]
		if not pair_joined(i):
			col.a = 0.72
		for j in range(route.size() - 1):
			var a := _cell_center(route[j])
			var b := _cell_center(route[j + 1])
			draw_line(a, b, col, width)
			draw_circle(a, width * 0.5, col)     # rounded corners
		draw_circle(_cell_center(route[route.size() - 1]), width * 0.5, col)

	# Dots
	for i in pairs.size():
		var p: Dictionary = pairs[i]
		for cell in [p.a, p.b]:
			draw_circle(_cell_center(cell), s * 0.30, COLORS[i])
			if pair_joined(i):
				draw_circle(_cell_center(cell), s * 0.13, Blocks.PAPER_SUNK)

	# Cursor
	if not solved:
		var cr := Rect2(ORIGIN + Vector2(cursor.x * s, cursor.y * s), Vector2(s, s))
		Blocks.outline(self, cr.grow(-3), Blocks.INK if active == -1 else COLORS[active], 2.0)

	Blocks.outline(self, board.grow(2), Blocks.INK, 1.0)
	_draw_hud()

	if solved:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "SOLVED", "ENTER FOR LEVEL %d" % (level + 1))


func _draw_hud() -> void:
	var x := ORIGIN.x

	Blocks.text(self, Vector2(x, 108), "LINKUP", 34, Blocks.INK)
	Blocks.rule(self, Vector2(x, 122), BOARD_PX, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(x, 150), "LEVEL", str(level), 24)
	Blocks.stat(self, Vector2(x + 110, 150), "PAIRS", "%d/%d" % [connected_count(), pairs.size()], 24)
	Blocks.stat(self, Vector2(x + 230, 150), "FILLED", "%d%%" % int(100.0 * filled_cells() / (size * size)), 24)
	if Scores.has("linkup"):
		Blocks.stat(self, Vector2(x + 350, 150), "BEST", "LVL %d" % int(Scores.get_best("linkup")), 24)

	Blocks.rule(self, Vector2(x, 686), BOARD_PX, Blocks.INK, 1.0)
	var cy := 706.0
	for line in [
		"DRAG FROM A DOT TO ITS TWIN - OR ARROWS TO MOVE, SPACE TO GRAB",
		"FILL EVERY SQUARE TO SOLVE THE BOARD",
		"N  CLEAR        R  NEW BOARD        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
