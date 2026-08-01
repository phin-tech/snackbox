class_name Gridlock
extends Node2D

# Sliding traffic jam, after Rush Hour. Cars and trucks only move along their
# own axis; shuffle them until the red car can reach the gap on the right.
#
# Boards are graded before they are handed out: pick a set of vehicles, work out
# how many moves every arrangement of it would need, and keep an arrangement
# whose answer lands in the level's band. Scrambling backwards from the finished
# position was tried first and gave near-trivial boards - an unbiased random walk
# almost never parks anything in the exit row, so the red car could usually just
# drive straight out.

signal exit_to_menu

const SIZE := 6
const EXIT_ROW := 2

# Generation budget. A set of vehicles that blows the cap is dropped rather than
# graded exactly - the point is a playable board, quickly - and the cap during
# generation is deliberately mean, because the sprawling state spaces it throws
# away are the loose boards with nothing interesting in them anyway.
const STATE_CAP := 200000     # states a single solver run may explore
const GEN_STATE_CAP := 1200   # ... and the tighter cap a set gets while grading
const GEN_ATTEMPTS := 200     # sets of vehicles graded per level start
const GEN_BUDGET_MS := 400    # ... and the wall clock they share
const MUTATE_CHANCE := 0.85   # how often a try nudges the best set instead of starting over
const STALE_LIMIT := 6        # tries without progress before the climb starts again
const HARD_FLOOR := 4         # nothing below this is ever handed to the player

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
var min_solution := 0         # shortest solution of the board as handed out
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


# --- Solver --------------------------------------------------------------------
#
# A board is only ever the position of each vehicle along its own axis: rows,
# columns, lengths and orientations never change. Three bits per vehicle packs
# a whole board into one integer, which is what the searches below shuffle
# about - no arrays are copied per state, which matters when a level start
# grades tens of thousands of them.

func _layout() -> Dictionary:
	# Everything a move cannot change, worked out once. `cells` holds, for each
	# vehicle and each position it could take, a bitmask of the squares it would
	# cover, so testing a slide is a couple of integer operations.
	var n := vehicles.size()
	var lay := {
		"lens": PackedByteArray(),
		"shift": PackedByteArray(),   # where this vehicle's three bits sit in a key
		"span": PackedByteArray(),    # positions it can take, 0 .. span - 1
		"cells": [],                  # [vehicle][position] -> bitmask of squares
		"key": 0,                     # the board as it stands
	}
	lay.lens.resize(n)
	lay.shift.resize(n)
	lay.span.resize(n)
	for i in n:
		var v: Dictionary = vehicles[i]
		lay.lens[i] = v.len
		lay.shift[i] = 3 * (n - 1 - i)
		lay.span[i] = SIZE - v.len + 1
		var masks := PackedInt64Array()
		for p in lay.span[i]:
			var m := 0
			for j in v.len:
				var c: Vector2i = Vector2i(p + j, v.pos.y) if v.horiz else Vector2i(v.pos.x, p + j)
				m |= 1 << (c.y * SIZE + c.x)
			masks.append(m)
		lay.cells.append(masks)
		var free: int = v.pos.x if v.horiz else v.pos.y
		lay.key |= free << lay.shift[i]
	return lay


func _at(key: int, lay: Dictionary, index: int) -> int:
	return (key >> lay.shift[index]) & 7


func _neighbour_keys(key: int, lay: Dictionary) -> PackedInt64Array:
	# Every board one move away. Sliding a vehicle any distance counts as a
	# single move - the usual Rush Hour metric - so each stopping place along
	# its run is a separate neighbour.
	var lens: PackedByteArray = lay.lens
	var shift: PackedByteArray = lay.shift
	var span: PackedByteArray = lay.span
	var cells: Array = lay.cells
	var n := lens.size()

	var board := 0
	for i in n:
		board |= cells[i][(key >> shift[i]) & 7]

	var out := PackedInt64Array()
	for i in n:
		var masks: PackedInt64Array = cells[i]
		var at: int = (key >> shift[i]) & 7
		var rest: int = board & ~masks[at]
		var p := at - 1
		while p >= 0 and (rest & masks[p]) == 0:
			out.append(key - ((at - p) << shift[i]))
			p -= 1
		p = at + 1
		while p < span[i] and (rest & masks[p]) == 0:
			out.append(key + ((p - at) << shift[i]))
			p += 1
	return out


func _move_between(from: int, to: int, lay: Dictionary) -> Dictionary:
	# The single move that turns one board into the next, recovered from the one
	# three-bit field the two keys disagree on.
	for i in lay.lens.size():
		var a := _at(from, lay, i)
		var b := _at(to, lay, i)
		if a != b:
			return {"v": i, "d": b - a}
	return {}


func _search(cap: int) -> Dictionary:
	# Breadth-first from the board as it stands, so the first time the red car
	# reaches the exit is by definition the shortest way of getting it there.
	var v0: Dictionary = vehicles[0]
	if not v0.horiz or v0.pos.y != EXIT_ROW:
		return {"moves": -1, "path": []}
	var lay := _layout()
	var goal: int = SIZE - lay.lens[0]
	if _at(lay.key, lay, 0) >= goal:
		return {"moves": 0, "path": []}

	var queue := PackedInt64Array([lay.key])
	var came := {lay.key: -1}         # board -> the board it was reached from
	var head := 0
	while head < queue.size():
		if head >= cap:
			return {"moves": -1, "path": []}
		var cur: int = queue[head]
		head += 1
		for next in _neighbour_keys(cur, lay):
			if came.has(next):
				continue
			came[next] = cur
			if _at(next, lay, 0) >= goal:
				var path := []
				var at := next
				while came[at] != -1:
					path.push_front(_move_between(came[at], at, lay))
					at = came[at]
				return {"moves": path.size(), "path": path}
			queue.append(next)

	return {"moves": -1, "path": []}


func _profile(lo: int, hi: int, cap: int) -> Dictionary:
	# Grades every board this set of vehicles can reach in one go, and returns
	# one whose shortest solution lands in [lo, hi] - or the hardest board the
	# set can manage, if it cannot reach the band at all. Walking outwards from
	# the finished boards measures the whole space at once, which is far cheaper
	# than solving thousands of random boards one at a time. Distance from the
	# nearest finished board is exactly the minimum move count, because a slide
	# and its reverse are both legal.
	var lay := _layout()
	var goal: int = SIZE - lay.lens[0]

	# First walk: the component this set of vehicles lives in, and which of its
	# boards are already finished.
	var queue := PackedInt64Array([lay.key])
	var seen := {lay.key: true}
	var finished := PackedInt64Array()
	var head := 0
	while head < queue.size():
		if head >= cap:
			return {}
		var cur: int = queue[head]
		head += 1
		if _at(cur, lay, 0) >= goal:
			finished.append(cur)
		for next in _neighbour_keys(cur, lay):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	if finished.is_empty():
		return {}

	# Second walk: outwards from all of them at once, which numbers every board
	# with the moves it needs. It runs in order of distance, so the pick is
	# simply kept at the deepest ring reached so far without passing hi - the
	# hardest board the band allows - and there is no reason to walk past that.
	var dist := {}
	for f in finished:
		dist[f] = 0
	var picked := 0
	var picked_depth := 0
	var picked_count := 0

	head = 0
	while head < finished.size():
		var cur: int = finished[head]
		head += 1
		var d: int = dist[cur] + 1
		if d > hi:
			break
		for next in _neighbour_keys(cur, lay):
			if dist.has(next):
				continue
			dist[next] = d
			finished.append(next)
			if d > picked_depth:
				picked_depth = d
				picked = next
				picked_count = 1
			elif d == picked_depth:
				# Reservoir sample, so a level does not always open on the first
				# board of its difficulty the walk happens to trip over.
				picked_count += 1
				if randi() % picked_count == 0:
					picked = next

	if picked_depth == 0:
		return {}
	return {"key": picked, "moves": picked_depth, "lay": lay}


func _apply(key: int, lay: Dictionary) -> void:
	for i in vehicles.size():
		var v: Dictionary = vehicles[i]
		var free := _at(key, lay, i)
		v.pos = Vector2i(free, v.pos.y) if v.horiz else Vector2i(v.pos.x, free)
		vehicles[i] = v


func min_moves(cap := STATE_CAP) -> int:
	# Shortest solution for the board as it stands, or -1 if there is none (or
	# the search hit the cap, which for our purposes is the same answer).
	return _search(cap).moves


func solve(cap := STATE_CAP) -> Array:
	# The moves of one shortest solution, as {v, d} pairs for move_vehicle.
	return _search(cap).path


# --- Generation ----------------------------------------------------------------

func difficulty_band(lvl: int) -> Vector2i:
	# Minimum moves wanted, in the metric above: a slide of any distance is one
	# move. Level one opens at six or so - enough that the exit row is properly
	# blocked - and the floor climbs a move every couple of levels. It stops at
	# nine because boards harder than that are rare enough in random sets that
	# hunting one would cost more time than a level start has to spare.
	var lo: int = clampi(5 + lvl / 2, 6, 9)
	return Vector2i(lo, lo + 3)


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
	# Grade sets of vehicles until one of them can be arranged into a board in
	# the band. A set that falls short is usually close, so most attempts nudge
	# the best set so far rather than starting from scratch - moving one vehicle
	# elsewhere reliably finds the missing move or two, where fresh random sets
	# land back at the shallow end most of the time.
	var band := difficulty_band(level)
	var deadline := Time.get_ticks_msec() + GEN_BUDGET_MS
	var best := []
	var best_moves := -1
	var kept := []
	var kept_moves := -1
	var stale := 0

	for _attempt in GEN_ATTEMPTS:
		var cand := _mutate(kept) if not kept.is_empty() and randf() < MUTATE_CHANCE else _candidate()
		if cand.is_empty():
			continue
		vehicles = cand
		var graded := _profile(band.x, band.y, GEN_STATE_CAP)
		if graded.is_empty():
			continue
		_apply(graded.key, graded.lay)
		if graded.moves >= band.x:
			min_solution = graded.moves
			return
		# Sideways moves count as progress, otherwise the climb sits on the first
		# plateau it reaches; if even those dry up, throw the set away and start
		# again somewhere else.
		if graded.moves >= kept_moves:
			kept_moves = graded.moves
			kept = _clone(vehicles)
			stale = 0
		else:
			stale += 1
			if stale > STALE_LIMIT:
				kept = []
				kept_moves = -1
				stale = 0
		if graded.moves > best_moves:
			best_moves = graded.moves
			best = _clone(vehicles)
		# Anything at or above the hard floor will do once time is up.
		if Time.get_ticks_msec() >= deadline and best_moves >= HARD_FLOOR:
			break

	if best_moves >= HARD_FLOOR:
		vehicles = best
		min_solution = best_moves
		return

	# Nothing usable at all, which needs a run of very bad luck. Fall back to a
	# fixed board rather than handing the player something trivial.
	vehicles = [
		{"pos": Vector2i(0, EXIT_ROW), "len": 2, "horiz": true},
		{"pos": Vector2i(2, 0), "len": 3, "horiz": false},
		{"pos": Vector2i(3, 1), "len": 3, "horiz": false},
		{"pos": Vector2i(5, 2), "len": 2, "horiz": false},
		{"pos": Vector2i(4, 0), "len": 2, "horiz": true},
		{"pos": Vector2i(0, 4), "len": 3, "horiz": true},
		{"pos": Vector2i(4, 4), "len": 2, "horiz": false},
	]
	min_solution = min_moves()


func _clone(list: Array) -> Array:
	var out := []
	for v in list:
		out.append(v.duplicate())
	return out


func _mutate(list: Array) -> Array:
	# Take a set apart and put one of its vehicles back somewhere else.
	var out := _clone(list)
	out.remove_at(1 + randi() % (out.size() - 1))
	for _try in 30:
		var v := _random_vehicle()
		if _fits(v, out):
			out.append(v)
			return out
	return out


func _random_vehicle() -> Dictionary:
	# Upright traffic in the columns left of the exit is the only thing that can
	# ever stand in the red car's way, so it gets more than its share of the
	# draw - scatter everything uniformly and the exit row comes out clear far
	# too often.
	var length := 2 if randf() < 0.68 else 3
	if randf() < 0.45:
		var col := randi() % (SIZE - 2)
		var top := randi_range(maxi(0, EXIT_ROW - length + 1), mini(EXIT_ROW, SIZE - length))
		return {"pos": Vector2i(col, top), "len": length, "horiz": false}
	var horiz := randi() % 2 == 0
	var span := SIZE - length + 1
	if horiz:
		# The exit row belongs to the red car and the traffic crossing it: another
		# car parked there can only wall the red one in or be shoved aside.
		var row := randi() % (SIZE - 1)
		return {"pos": Vector2i(randi() % span, row + (1 if row >= EXIT_ROW else 0)), "len": length, "horiz": true}
	return {"pos": Vector2i(randi() % SIZE, randi() % span), "len": length, "horiz": false}


func _candidate() -> Array:
	# What matters here is the set of vehicles - which columns hold upright
	# traffic, which rows hold the rest - since the profiler picks the positions
	# itself afterwards. The red car starts at the exit purely so the component
	# it lives in is guaranteed to contain finished boards.
	var out := [{"pos": Vector2i(SIZE - 2, EXIT_ROW), "len": 2, "horiz": true}]
	var wanted: int = clampi(8 + level / 3, 8, 11)
	var attempts := 0
	while out.size() < wanted and attempts < 400:
		attempts += 1
		var v := _random_vehicle()
		if _fits(v, out):
			out.append(v)
	return out if out.size() >= 4 else []


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
