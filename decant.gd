class_name Decant
extends Node2D

# Water sorting. Pour between tubes until each one holds a single colour, or
# nothing at all. A pour only runs if the receiving tube is empty or already
# has that colour on top, and it moves the whole run of matching liquid - or as
# much of it as fits.
#
# Colours are dealt out at random and the board is then checked with a
# depth-first solver before being handed over, so a level is never a dead end.
# Scrambling from the finished position would be neater, but the solved state
# has no legal pours at all under these rules - there is nothing to scramble.

signal exit_to_menu

const CAPACITY := 4
const MIN_COLORS := 3
const MAX_COLORS := 8
const SPARE_TUBES := 2
const SOLVER_CAP := 15000

const TUBE_W := 56.0
const SEG_H := 42.0
const RIM := 10.0
const GAP_X := 22.0
const ROW_Y := [230.0, 466.0]

const PAINTS := [
	Color("ff3b30"), Color("3d8be0"), Color("f2b705"), Color("46ac5c"),
	Color("f0822f"), Color("8f5fc0"), Color("28c2c2"), Color("e069a8"),
]

var tubes := []               # Array of Array[int]; index 0 is the bottom
var level := 1
var moves := 0
var picked := -1
var history := []             # [{from, to, amount}] for undo
var solved := false
var message := ""
var message_timer := 0.0
var seeds := Seeds.Entry.new("decant")


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	_start_level()


func colour_count() -> int:
	return clampi(MIN_COLORS + (level - 1) / 2, MIN_COLORS, MAX_COLORS)


func _start_level() -> void:
	seed(seeds.level_seed(level))
	_generate()
	moves = 0
	picked = -1
	history = []
	solved = false
	message = ""
	queue_redraw()


# --- Rules ---------------------------------------------------------------------

func top_run(tube: Array) -> int:
	# How many units of the same colour sit on top.
	if tube.is_empty():
		return 0
	var colour: int = tube[tube.size() - 1]
	var n := 0
	for i in range(tube.size() - 1, -1, -1):
		if tube[i] != colour:
			break
		n += 1
	return n


func can_pour(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= tubes.size() or to >= tubes.size():
		return false
	var src: Array = tubes[from]
	var dst: Array = tubes[to]
	if src.is_empty() or dst.size() >= CAPACITY:
		return false
	if not dst.is_empty() and dst[dst.size() - 1] != src[src.size() - 1]:
		return false
	# Tipping a full single-colour tube into an empty one achieves nothing.
	if dst.is_empty() and top_run(src) == src.size():
		return false
	return true


func pour(from: int, to: int) -> bool:
	if not can_pour(from, to):
		return false
	var amount: int = min(top_run(tubes[from]), CAPACITY - tubes[to].size())
	for _i in amount:
		tubes[to].append(tubes[from].pop_back())
	moves += 1
	history.append({"from": from, "to": to, "amount": amount})
	_check_solved()
	queue_redraw()
	return true


func undo() -> bool:
	if history.is_empty():
		return false
	var last: Dictionary = history.pop_back()
	for _i in last.amount:
		tubes[last.from].append(tubes[last.to].pop_back())
	moves += 1
	solved = false
	queue_redraw()
	return true


func is_solved() -> bool:
	for tube in tubes:
		if tube.is_empty():
			continue
		if tube.size() != CAPACITY:
			return false
		for unit in tube:
			if unit != tube[0]:
				return false
	return true


func _check_solved() -> void:
	if solved or not is_solved():
		return
	solved = true
	Scores.submit_high("decant", level)


# --- Generation ----------------------------------------------------------------

func _state_key(state: Array) -> PackedInt32Array:
	# Pack each tube into a single int, then sort: tube order doesn't matter, so
	# sorting collapses a mass of equivalent states. Building string keys here
	# was the difference between generation taking milliseconds and minutes.
	var codes := PackedInt32Array()
	for tube in state:
		var code := 0
		for unit in tube:
			code = code * 9 + (unit + 1)
		codes.append(code)
	codes.sort()
	return codes


func _solvable(start: Array) -> bool:
	# Depth-first with a visited set. Water sorting has a huge branching factor
	# but very shallow solutions, so DFS gets there quickly.
	var seen := {}
	var stack: Array = [start]
	var explored := 0

	while not stack.is_empty() and explored < SOLVER_CAP:
		var state: Array = stack.pop_back()
		explored += 1

		var key := _state_key(state)
		if seen.has(key):
			continue
		seen[key] = true

		var done := true
		for tube in state:
			if tube.is_empty():
				continue
			if tube.size() != CAPACITY:
				done = false
				break
			for unit in tube:
				if unit != tube[0]:
					done = false
					break
			if not done:
				break
		if done:
			return true

		for from in state.size():
			for to in state.size():
				if from == to:
					continue
				var src: Array = state[from]
				var dst: Array = state[to]
				if src.is_empty() or dst.size() >= CAPACITY:
					continue
				if not dst.is_empty() and dst[dst.size() - 1] != src[src.size() - 1]:
					continue
				var run := top_run(src)
				if dst.is_empty() and run == src.size():
					continue
				var amount: int = min(run, CAPACITY - dst.size())

				var next: Array = []
				for tube in state:
					next.append(tube.duplicate())
				for _i in amount:
					next[to].append(next[from].pop_back())
				if not seen.has(_state_key(next)):
					stack.append(next)

	return false


func _build_once() -> void:
	# Deal the colours out at random rather than scrambling from the finished
	# position: with the "don't tip a full tube into an empty one" rule, the
	# solved state has no legal pours at all, so there is nothing to scramble.
	# The solver below is what guarantees the deal is actually winnable.
	var colours := colour_count()
	var pool: Array[int] = []
	for c in colours:
		for _i in CAPACITY:
			pool.append(c)
	pool.shuffle()

	tubes = []
	for c in colours:
		var tube: Array[int] = []
		for i in CAPACITY:
			tube.append(pool[c * CAPACITY + i])
		tubes.append(tube)
	for _i in SPARE_TUBES:
		tubes.append([] as Array[int])


func mixed_tubes() -> int:
	var n := 0
	for tube in tubes:
		if tube.is_empty():
			continue
		var same := true
		for unit in tube:
			if unit != tube[0]:
				same = false
				break
		if not same:
			n += 1
	return n


func _generate() -> void:
	for _attempt in 30:
		_build_once()
		# A board that is already done, or barely stirred, isn't a puzzle.
		if is_solved() or mixed_tubes() < 2:
			continue
		if _solvable(tubes):
			return
	# Fall back to the finished layout stirred once, which is trivially solvable.
	_build_once()


# --- Input ----------------------------------------------------------------------

func tube_rect(index: int) -> Rect2:
	var per_row: int = int(ceil(tubes.size() / 2.0))
	var row: int = 0 if index < per_row else 1
	var col: int = index if row == 0 else index - per_row
	var count: int = per_row if row == 0 else tubes.size() - per_row
	var width: float = count * TUBE_W + (count - 1) * GAP_X
	var x: float = (Main.DESIGN_SIZE.x - width) * 0.5 + col * (TUBE_W + GAP_X)
	return Rect2(Vector2(x, ROW_Y[row]), Vector2(TUBE_W, CAPACITY * SEG_H + RIM))


func tube_at(point: Vector2) -> int:
	for i in tubes.size():
		if tube_rect(i).grow(8).has_point(point):
			return i
	return -1


func tap(index: int) -> void:
	if index == -1:
		picked = -1
		return
	if picked == -1:
		if not tubes[index].is_empty():
			picked = index
		return
	if picked == index:
		picked = -1
		return
	if not pour(picked, index):
		message = "CAN'T POUR THERE"
		message_timer = 1.4
		picked = index if not tubes[index].is_empty() else -1
		return
	picked = -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tap(tube_at(get_local_mouse_position()))
			queue_redraw()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
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
		KEY_Z, KEY_BACKSPACE:
			undo()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if solved:
				level += 1
				_start_level()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var want: int = (event as InputEventKey).physical_keycode - KEY_1
			if want < tubes.size():
				tap(want)
				queue_redraw()


func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer = maxf(message_timer - delta, 0.0)
		if message_timer == 0.0:
			message = ""
			queue_redraw()


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	for i in tubes.size():
		var rect := tube_rect(i)
		var tube: Array = tubes[i]

		# The glass: an open-topped outline.
		draw_rect(rect, Blocks.PAPER_SUNK)
		var lifted: bool = i == picked
		var edge: Color = Blocks.RED if lifted else Blocks.INK
		draw_rect(rect, edge, false, 2.0)

		# Liquid, stacked from the bottom.
		for unit in tube.size():
			var colour: Color = PAINTS[tube[unit] % PAINTS.size()]
			var y: float = rect.end.y - (unit + 1) * SEG_H
			var seg := Rect2(rect.position.x + 3, y, rect.size.x - 6, SEG_H)
			# The top unit of a lifted tube pokes out, so you can see what's
			# about to pour.
			if lifted and unit == tube.size() - 1:
				seg.position.y -= 14.0
			draw_rect(seg, colour)

		# A number under each tube, so the keyboard shortcuts make sense.
		if i < 9:
			Blocks.tracked(self, Vector2(rect.position.x + 4, rect.end.y + 20), str(i + 1), 11, Blocks.INK_FAINT)

	_draw_hud()

	if solved:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "SORTED", "%d MOVES        ENTER FOR LEVEL %d" % [moves, level + 1])


func _draw_hud() -> void:
	var x := 40.0
	Blocks.text(self, Vector2(x, 108), "DECANT", 34, Blocks.INK)
	Blocks.rule(self, Vector2(x, 122), Main.DESIGN_SIZE.x - 80, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(x, 150), "LEVEL", str(level), 24)
	Blocks.stat(self, Vector2(x + 120, 150), "MOVES", str(moves), 24)
	Blocks.stat(self, Vector2(x + 240, 150), "COLOURS", str(colour_count()), 24)
	if Scores.has("decant"):
		Blocks.stat(self, Vector2(x + 380, 150), "BEST", "LVL %d" % int(Scores.get_best("decant")), 24)
	Blocks.tracked(self, Vector2(x, 196), "SEED  " + seeds.label(), 11, Blocks.INK_MID)

	if message != "":
		Blocks.tracked(self, Vector2(x, 196), message, 11, Blocks.RED)

	var cy := 700.0
	for line in [
		"CLICK A TUBE TO LIFT IT, THEN ANOTHER TO POUR - OR PRESS ITS NUMBER",
		"A POUR NEEDS AN EMPTY TUBE OR THE SAME COLOUR ON TOP",
		"Z  UNDO        R  NEW BOARD        S  ENTER A SEED        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
