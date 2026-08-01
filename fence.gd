class_name Fence
extends Node2D

# You get a fixed length of fence. Draw a closed loop along the grid lines, and
# everything inside it is yours - the good cells and the bad ones alike.
#
# That single rule is the whole game: a tight loop is cheap but misses things,
# a sprawling one reaches everything and runs out of fence. Every level has a
# par, which is the loop the generator built the board around, so the target is
# known to be reachable rather than guessed at.

signal exit_to_menu

const COLS := 10
const ROWS := 12
const CELL := 40.0
const ORIGIN := Vector2(100, 200)

const GRAB := 14.0                # how close the mouse must be to a corner

var value := []                   # value[row][col], positive or negative
var par := 0                      # score of the loop the board was built around
var budget := 0                   # fence segments available

var path: Array[Vector2i] = []    # lattice corners, in order
var closed := false
var enclosed := {}                # Vector2i -> true, once a loop is closed
var score := 0
var level := 1
var best_this_level := 0
var message := ""
var message_timer := 0.0
var seeds := Seeds.Entry.new("fence")
var entry := Scores.NameEntry.new()


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	_start_level()


func _start_level() -> void:
	seed(seeds.level_seed(level))
	_generate()
	_clear_path()
	best_this_level = 0
	message = ""
	queue_redraw()


func _clear_path() -> void:
	path = []
	closed = false
	enclosed = {}
	score = 0


func used() -> int:
	return max(path.size() - 1, 0)


func left() -> int:
	return budget - used()


# --- Geometry -------------------------------------------------------------------

func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


func _in_lattice(corner: Vector2i) -> bool:
	return corner.x >= 0 and corner.x <= COLS and corner.y >= 0 and corner.y <= ROWS


func _edge_key(a: Vector2i, b: Vector2i) -> int:
	# One number per grid edge, order independent.
	var ia: int = a.y * (COLS + 1) + a.x
	var ib: int = b.y * (COLS + 1) + b.x
	return min(ia, ib) * 100000 + max(ia, ib)


func _edges() -> Dictionary:
	var set := {}
	for i in range(path.size() - 1):
		set[_edge_key(path[i], path[i + 1])] = true
	return set


func _shared_edge(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# The two corners of the wall between neighbouring cells a and b.
	if a.y == b.y:
		var x: int = max(a.x, b.x)
		return [Vector2i(x, a.y), Vector2i(x, a.y + 1)]
	var y: int = max(a.y, b.y)
	return [Vector2i(a.x, y), Vector2i(a.x + 1, y)]


func _flood_outside(walls: Dictionary) -> Dictionary:
	# Flood from beyond the board, not from its border cells: a loop drawn along
	# the edge of the board encloses border cells, and seeding those as outside
	# would wrongly declare them free.
	var outside := {}
	var start := Vector2i(-1, -1)
	var queue: Array[Vector2i] = [start]
	outside[start] = true

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			# One ring of virtual cells around the board is enough to get all
			# the way around the outside of any loop.
			if n.x < -1 or n.x > COLS or n.y < -1 or n.y > ROWS:
				continue
			if outside.has(n):
				continue
			# The fence only blocks where it actually lies, which includes the
			# board boundary itself.
			if _in_grid(cur) or _in_grid(n):
				var wall := _shared_edge(cur, n)
				if walls.has(_edge_key(wall[0], wall[1])):
					continue
			outside[n] = true
			queue.append(n)
	return outside


func cells_inside(walls: Dictionary) -> Dictionary:
	var outside := _flood_outside(walls)
	var inside := {}
	for r in ROWS:
		for c in COLS:
			var cell := Vector2i(c, r)
			if not outside.has(cell):
				inside[cell] = true
	return inside


func score_of(cells: Dictionary) -> int:
	var total := 0
	for cell in cells:
		total += value[cell.y][cell.x]
	return total


# --- Drawing the loop -----------------------------------------------------------

func start_at(corner: Vector2i) -> bool:
	if not _in_lattice(corner) or closed:
		return false
	path = [corner]
	return true


func step_to(corner: Vector2i) -> bool:
	# One grid edge at a time. Stepping back onto the previous corner rubs the
	# last segment out, which is the natural way to correct a wrong turn.
	if closed or path.is_empty() or not _in_lattice(corner):
		return false
	var head: Vector2i = path[path.size() - 1]
	var delta: Vector2i = corner - head
	if absi(delta.x) + absi(delta.y) != 1:
		return false

	if path.size() >= 2 and corner == path[path.size() - 2]:
		path.remove_at(path.size() - 1)
		queue_redraw()
		return true

	# Closing the loop.
	if corner == path[0] and path.size() >= 4:
		if used() + 1 > budget:
			_say("NOT ENOUGH FENCE TO CLOSE")
			return false
		path.append(corner)
		_close()
		return true

	if path.has(corner):
		return false            # a loop may not cross itself
	if used() + 1 > budget:
		_say("OUT OF FENCE")
		return false

	path.append(corner)
	queue_redraw()
	return true


func _close() -> void:
	closed = true
	enclosed = cells_inside(_edges())
	score = score_of(enclosed)
	best_this_level = max(best_this_level, score)
	if score >= par:
		Scores.submit_high("fence", level)
		# The table is per seed: a score only means anything against the board
		# it was played on.
		var key := "fence." + Seeds.code(seeds.base)
		if Scores.qualifies(key, score):
			entry.start(key)
		_say("PAR MET" if score == par else "OVER PAR")
	else:
		_say("%d SHORT OF PAR" % (par - score))
	queue_redraw()


func _say(text: String) -> void:
	message = text
	message_timer = 2.2


# --- Generation -----------------------------------------------------------------

func _perimeter(blob: Dictionary) -> int:
	var n := 0
	for cell in blob:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not blob.has(cell + d):
				n += 1
	return n


func _fill_holes(blob: Dictionary) -> Dictionary:
	# A blob with a hole in it isn't one loop, it's two. Absorb any pocket the
	# outside can't reach.
	var outside := {}
	var queue: Array[Vector2i] = []
	for c in COLS:
		for cell in [Vector2i(c, 0), Vector2i(c, ROWS - 1)]:
			if not blob.has(cell) and not outside.has(cell):
				outside[cell] = true
				queue.append(cell)
	for r in ROWS:
		for cell in [Vector2i(0, r), Vector2i(COLS - 1, r)]:
			if not blob.has(cell) and not outside.has(cell):
				outside[cell] = true
				queue.append(cell)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not _in_grid(n) or blob.has(n) or outside.has(n):
				continue
			outside[n] = true
			queue.append(n)

	var filled := blob.duplicate()
	for r in ROWS:
		for c in COLS:
			var cell := Vector2i(c, r)
			if not outside.has(cell):
				filled[cell] = true
	return filled


func _grow_blob() -> Dictionary:
	# Grow a shape inward from a seed, keeping it off the border so a loop can
	# always be drawn around it.
	var target: int = clampi(10 + level * 2, 10, 34)
	var blob := {}
	var seed_cell := Vector2i(randi_range(2, COLS - 3), randi_range(2, ROWS - 3))
	blob[seed_cell] = true

	var guard := 0
	while blob.size() < target and guard < 800:
		guard += 1
		var from: Vector2i = blob.keys()[randi() % blob.size()]
		var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][randi() % 4]
		var n: Vector2i = from + d
		# Keep one clear ring around the edge of the board.
		if n.x < 1 or n.x >= COLS - 1 or n.y < 1 or n.y >= ROWS - 1:
			continue
		blob[n] = true
	return _fill_holes(blob)


func _generate() -> void:
	var blob := _grow_blob()

	value = []
	for r in ROWS:
		var row := []
		row.resize(COLS)
		row.fill(0)
		value.append(row)

	# Inside the shape is worth having; just outside it is worth avoiding, which
	# is what stops the answer being "enclose everything".
	for r in ROWS:
		for c in COLS:
			var cell := Vector2i(c, r)
			if blob.has(cell):
				value[r][c] = randi_range(1, 5)
				continue
			var touches := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if blob.has(cell + d):
					touches = true
					break
			if touches and randf() < 0.8:
				value[r][c] = -randi_range(2, 5)
			elif randf() < 0.14:
				value[r][c] = randi_range(1, 3)     # a temptation, out of reach
			elif randf() < 0.07:
				value[r][c] = -randi_range(1, 2)

	par = 0
	for cell in blob:
		par += value[cell.y][cell.x]

	# Enough fence for the intended loop, plus a little room to be clever.
	budget = _perimeter(blob) + 6


# --- Input ----------------------------------------------------------------------

func corner_at(point: Vector2) -> Vector2i:
	var local := (point - ORIGIN) / CELL
	var corner := Vector2i(roundi(local.x), roundi(local.y))
	if not _in_lattice(corner):
		return Vector2i(-1, -1)
	if (ORIGIN + Vector2(corner) * CELL).distance_to(point) > GRAB:
		return Vector2i(-1, -1)
	return corner


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var corner := corner_at(get_local_mouse_position())
			if corner.x != -1:
				if closed:
					_clear_path()
				if path.is_empty():
					start_at(corner)
				else:
					step_to(corner)
				queue_redraw()
		return

	if event is InputEventMouseMotion and not path.is_empty() and not closed:
		if not (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			return
		# Walk towards the pointer a corner at a time, so a fast drag still
		# lays a continuous fence.
		for _i in 12:
			var head: Vector2i = path[path.size() - 1] if not path.is_empty() else Vector2i.ZERO
			var target := corner_at(get_local_mouse_position())
			if target.x == -1 or target == head:
				break
			var step := head
			if target.x != head.x:
				step.x += signi(target.x - head.x)
			elif target.y != head.y:
				step.y += signi(target.y - head.y)
			if not step_to(step):
				break
			if closed:
				break
		queue_redraw()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if entry.handle_key(event as InputEventKey, float(score), Seeds.code(seeds.base)):
		queue_redraw()
		return

	# Seed entry takes keys first, so typing a code can't also drive the game.
	match seeds.handle_key(event as InputEventKey):
		Seeds.Entry.CONSUMED:
			queue_redraw()
			return
		Seeds.Entry.APPLIED:
			new_game()
			queue_redraw()
			return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			_start_level()
		KEY_N, KEY_BACKSPACE:
			_clear_path()
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if closed and score >= par:
				level += 1
				_start_level()


func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer = maxf(message_timer - delta, 0.0)
		if message_timer == 0.0:
			message = ""
			queue_redraw()


# --- Drawing --------------------------------------------------------------------

func _cell_rect(c: int, r: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(c, r) * CELL, Vector2(CELL, CELL))


func _draw() -> void:
	var board := Rect2(ORIGIN, Vector2(COLS, ROWS) * CELL)
	draw_rect(board, Blocks.PAPER_SUNK)

	for r in ROWS:
		for c in COLS:
			var v: int = value[r][c]
			var rect := _cell_rect(c, r)
			var held: bool = closed and enclosed.has(Vector2i(c, r))

			if held:
				draw_rect(rect, Color(1, 1, 1, 0.10))
			if v == 0:
				continue

			# Two colours and nothing else: bone for worth having, red for worth
			# avoiding, and a minus sign so the sign is never in doubt.
			var tint: Color = Blocks.INK if v > 0 else Blocks.RED
			var label := str(v) if v > 0 else "-" + str(-v)
			Blocks.text_in(self, rect, label, 20, tint)

	# Grid corners, so the lattice you're drawing on is visible.
	for r in ROWS + 1:
		for c in COLS + 1:
			draw_rect(Rect2(ORIGIN + Vector2(c, r) * CELL - Vector2(1, 1), Vector2(2, 2)), Blocks.INK_FAINT)

	# The fence itself.
	if path.size() >= 2:
		var colour: Color = Blocks.INK
		var thick := 5.0
		for i in range(path.size() - 1):
			var a := ORIGIN + Vector2(path[i]) * CELL
			var b := ORIGIN + Vector2(path[i + 1]) * CELL
			draw_line(a, b, colour, thick)
		# Line ends are flat, so a right-angle turn leaves a notch. Cap every
		# corner with a square the width of the fence.
		for corner in path:
			var at := ORIGIN + Vector2(corner) * CELL
			draw_rect(Rect2(at - Vector2(thick, thick) * 0.5, Vector2(thick, thick)), colour)
	if not path.is_empty() and not closed:
		var head := ORIGIN + Vector2(path[path.size() - 1]) * CELL
		draw_rect(Rect2(head - Vector2(5, 5), Vector2(10, 10)), Blocks.INK)
		# The corner you have to come back to, marked in the accent.
		var start := ORIGIN + Vector2(path[0]) * CELL
		draw_rect(Rect2(start - Vector2(5, 5), Vector2(10, 10)), Blocks.RED)

	Blocks.outline(self, board, Blocks.INK, 1.0)
	_draw_hud()

	entry.draw(self, Main.DESIGN_SIZE.x, "MADE THE TABLE")
	if entry.active:
		return
	if closed and score >= par:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "ENCLOSED", "%d POINTS        ENTER FOR LEVEL %d" % [score, level + 1])


func _draw_hud() -> void:
	var x := 40.0
	Blocks.text(self, Vector2(x, 108), "FENCE", 34, Blocks.INK)
	Blocks.rule(self, Vector2(x, 122), Main.DESIGN_SIZE.x - 80, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(x, 150), "LEVEL", str(level), 24)
	Blocks.stat(self, Vector2(x + 110, 150), "FENCE LEFT", str(left()), 24)
	Blocks.stat(self, Vector2(x + 260, 150), "SCORE", str(score) if closed else "-", 24)
	Blocks.stat(self, Vector2(x + 380, 150), "PAR", str(par), 24)
	Blocks.tracked(self, Vector2(x, 192), "SEED  " + seeds.label(), 11, Blocks.INK_MID)

	if message != "":
		Blocks.tracked(self, Vector2(x, 692), message, 11, Blocks.RED)

	var cy := 710.0
	for line in [
		"DRAG ALONG THE GRID LINES AND COME BACK TO WHERE YOU STARTED",
		"EVERYTHING INSIDE THE LOOP COUNTS - THE RED SQUARES TOO",
		"N  CLEAR        R  NEW BOARD        S  ENTER A SEED        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
