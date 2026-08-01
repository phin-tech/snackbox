class_name Pills
extends Node2D

# Dr. Mario style virus clearing. Drop two-tone pills into the bottle, line up
# four or more of one colour to wipe them out, and clear every virus to advance.
#
# Deliberately kept independent of game.gd - the board, pieces, clearing rule
# and gravity are all different. Only the drawing helpers are shared.

signal exit_to_menu

const COLS := 8
const ROWS := 16
const CELL := 32
const BOTTLE_ORIGIN := Vector2(60, 140)
const PANEL_X := 372.0

const COLORS := [Color("ff3b30"), Color("f2b705"), Color("3d8be0")]
const MATCH_LEN := 4
const MAX_VIRUSES := 84

# Cell kinds. Links point at where this half's partner sits.
const EMPTY := 0
const VIRUS := 1
const SINGLE := 2
const LINK_RIGHT := 3
const LINK_LEFT := 4
const LINK_DOWN := 5
const LINK_UP := 6

const LINK_OFFSET := {
	LINK_RIGHT: Vector2i(1, 0),
	LINK_LEFT: Vector2i(-1, 0),
	LINK_DOWN: Vector2i(0, 1),
	LINK_UP: Vector2i(0, -1),
}

# States
const FALLING := 0
const FLASHING := 1
const SETTLING := 2
const WON := 3
const LOST := 4

const FLASH_TIME := 0.35
const SETTLE_STEP := 0.07
const DAS := 0.17
const ARR := 0.05

var kind := []                # kind[row][col]
var color := []               # color[row][col], -1 when empty

var state := FALLING
var level := 1
var score := 0
var viruses_left := 0
var chain := 0

var pill_pos := Vector2i(3, 0)
var pill_orient := 0
var pill_colors := [0, 0]
var next_colors := [0, 0]

var gravity_timer := 0.0
var flash_timer := 0.0
var settle_timer := 0.0
var paused := false

var pending: Array[Vector2i] = []
var move_dir := 0
var das_timer := 0.0
var arr_timer := 0.0
var recorded := false


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	score = 0
	_start_level()


func _start_level() -> void:
	kind.clear()
	color.clear()
	for r in ROWS:
		var krow := []
		var crow := []
		krow.resize(COLS)
		crow.resize(COLS)
		krow.fill(EMPTY)
		crow.fill(-1)
		kind.append(krow)
		color.append(crow)

	_place_viruses()
	chain = 0
	paused = false
	recorded = false
	state = FALLING
	next_colors = [randi() % 3, randi() % 3]
	_spawn_pill()
	queue_redraw()


func _place_viruses() -> void:
	var count: int = min(4 * (level + 1), MAX_VIRUSES)
	# Higher levels stack viruses further up the bottle.
	var top_row: int = clampi(ROWS - 4 - level, 3, ROWS - 1)
	viruses_left = 0

	var attempts := 0
	while viruses_left < count and attempts < 6000:
		attempts += 1
		var r := randi_range(top_row, ROWS - 1)
		var c := randi() % COLS
		if kind[r][c] != EMPTY:
			continue
		var col := randi() % 3
		if _would_make_run(r, c, col, 3):
			continue
		kind[r][c] = VIRUS
		color[r][c] = col
		viruses_left += 1


func _would_make_run(r: int, c: int, col: int, limit: int) -> bool:
	# Placing this colour here must not create `limit` in a row either way.
	var horiz := 1
	var i := c - 1
	while i >= 0 and color[r][i] == col:
		horiz += 1
		i -= 1
	i = c + 1
	while i < COLS and color[r][i] == col:
		horiz += 1
		i += 1
	if horiz >= limit:
		return true

	var vert := 1
	i = r - 1
	while i >= 0 and color[i][c] == col:
		vert += 1
		i -= 1
	i = r + 1
	while i < ROWS and color[i][c] == col:
		vert += 1
		i += 1
	return vert >= limit


# --- Active pill --------------------------------------------------------------

func _pill_cells(pos: Vector2i, orient: int) -> Array[Vector2i]:
	match orient:
		0: return [pos, pos + Vector2i(1, 0)]
		1: return [pos, pos + Vector2i(0, -1)]
		2: return [pos, pos + Vector2i(-1, 0)]
		_: return [pos, pos + Vector2i(0, 1)]


func _pill_kinds(orient: int) -> Array:
	match orient:
		0: return [LINK_RIGHT, LINK_LEFT]
		1: return [LINK_UP, LINK_DOWN]
		2: return [LINK_LEFT, LINK_RIGHT]
		_: return [LINK_DOWN, LINK_UP]


func _fits(pos: Vector2i, orient: int) -> bool:
	for c in _pill_cells(pos, orient):
		if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
			return false
		if kind[c.y][c.x] != EMPTY:
			return false
	return true


func _spawn_pill() -> void:
	pill_colors = next_colors.duplicate()
	next_colors = [randi() % 3, randi() % 3]
	pill_pos = Vector2i(3, 0)
	pill_orient = 0
	gravity_timer = 0.0
	if not _fits(pill_pos, pill_orient):
		state = LOST
	queue_redraw()


func _try_move(dx: int, dy: int) -> bool:
	var np := pill_pos + Vector2i(dx, dy)
	if not _fits(np, pill_orient):
		return false
	pill_pos = np
	queue_redraw()
	return true


func _try_rotate(dir: int) -> void:
	var no := wrapi(pill_orient + dir, 0, 4)
	# Nudge off walls and ceilings when the spin needs the room.
	for k in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		if _fits(pill_pos + k, no):
			pill_pos += k
			pill_orient = no
			queue_redraw()
			return


func _drop_distance() -> int:
	var d := 0
	while _fits(pill_pos + Vector2i(0, d + 1), pill_orient):
		d += 1
	return d


func _lock_pill() -> void:
	var cells := _pill_cells(pill_pos, pill_orient)
	var kinds := _pill_kinds(pill_orient)
	for i in 2:
		var c: Vector2i = cells[i]
		kind[c.y][c.x] = kinds[i]
		color[c.y][c.x] = pill_colors[i]
	chain = 0
	_resolve()


# --- Clearing and settling ----------------------------------------------------

func _resolve() -> void:
	pending = _find_matches()
	if pending.is_empty():
		if viruses_left == 0:
			state = WON
		else:
			state = FALLING
			_spawn_pill()
	else:
		chain += 1
		state = FLASHING
		flash_timer = 0.0
	queue_redraw()


func _find_matches() -> Array[Vector2i]:
	var hits := {}
	# Horizontal runs
	for r in ROWS:
		var run_start := 0
		while run_start < COLS:
			var col: int = color[r][run_start]
			var run_end := run_start
			while run_end + 1 < COLS and color[r][run_end + 1] == col:
				run_end += 1
			if col != -1 and run_end - run_start + 1 >= MATCH_LEN:
				for c in range(run_start, run_end + 1):
					hits[Vector2i(c, r)] = true
			run_start = run_end + 1
	# Vertical runs
	for c in COLS:
		var run_start := 0
		while run_start < ROWS:
			var col: int = color[run_start][c]
			var run_end := run_start
			while run_end + 1 < ROWS and color[run_end + 1][c] == col:
				run_end += 1
			if col != -1 and run_end - run_start + 1 >= MATCH_LEN:
				for r in range(run_start, run_end + 1):
					hits[Vector2i(c, r)] = true
			run_start = run_end + 1

	var out: Array[Vector2i] = []
	for k in hits.keys():
		out.append(k)
	return out


func _apply_clear() -> void:
	# Break links on surviving partners before anything is removed.
	for cell in pending:
		var k: int = kind[cell.y][cell.x]
		if LINK_OFFSET.has(k):
			var partner: Vector2i = cell + LINK_OFFSET[k]
			if not pending.has(partner):
				kind[partner.y][partner.x] = SINGLE

	var cleared_viruses := 0
	for cell in pending:
		if kind[cell.y][cell.x] == VIRUS:
			cleared_viruses += 1
		kind[cell.y][cell.x] = EMPTY
		color[cell.y][cell.x] = -1

	viruses_left -= cleared_viruses
	score += pending.size() * 10 * chain + cleared_viruses * 100 * chain
	pending.clear()
	state = SETTLING
	settle_timer = 0.0


func _settle_step() -> bool:
	# Collect loose pill halves as units, bottom row first, and drop whatever
	# has empty space beneath it. Viruses never move.
	var seen := {}
	var units := []
	for r in range(ROWS - 1, -1, -1):
		for c in COLS:
			var k: int = kind[r][c]
			if k == EMPTY or k == VIRUS:
				continue
			var cell := Vector2i(c, r)
			if seen.has(cell):
				continue
			var unit: Array[Vector2i] = [cell]
			seen[cell] = true
			if LINK_OFFSET.has(k):
				var partner: Vector2i = cell + LINK_OFFSET[k]
				unit.append(partner)
				seen[partner] = true
			units.append(unit)

	var moved := false
	for unit in units:
		var can_fall := true
		for cell in unit:
			var below: Vector2i = cell + Vector2i(0, 1)
			if below.y >= ROWS:
				can_fall = false
				break
			if kind[below.y][below.x] != EMPTY and not unit.has(below):
				can_fall = false
				break
		if not can_fall:
			continue

		var saved := []
		for cell in unit:
			saved.append([kind[cell.y][cell.x], color[cell.y][cell.x]])
			kind[cell.y][cell.x] = EMPTY
			color[cell.y][cell.x] = -1
		for i in unit.size():
			var dest: Vector2i = unit[i] + Vector2i(0, 1)
			kind[dest.y][dest.x] = saved[i][0]
			color[dest.y][dest.x] = saved[i][1]
		moved = true

	return moved


func _gravity_interval() -> float:
	return max(0.14, 0.55 - (level - 1) * 0.03)


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	var k := event as InputEventKey
	var code := k.physical_keycode

	if k.pressed:
		match code:
			KEY_ESCAPE:
				exit_to_menu.emit()
				return
			KEY_R:
				new_game()
				return
			KEY_P:
				if state == FALLING:
					paused = not paused
					queue_redraw()
				return

		if state == WON:
			if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				level += 1
				_start_level()
			return
		if state == LOST:
			if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				new_game()
			return
		if paused or state != FALLING:
			return

		match code:
			KEY_LEFT:
				move_dir = -1
				das_timer = 0.0
				arr_timer = 0.0
				_try_move(-1, 0)
			KEY_RIGHT:
				move_dir = 1
				das_timer = 0.0
				arr_timer = 0.0
				_try_move(1, 0)
			KEY_UP, KEY_X:
				_try_rotate(1)
			KEY_Z, KEY_CTRL:
				_try_rotate(-1)
			KEY_SPACE:
				pill_pos.y += _drop_distance()
				_lock_pill()
	else:
		match code:
			KEY_LEFT:
				if move_dir == -1:
					move_dir = 0
			KEY_RIGHT:
				if move_dir == 1:
					move_dir = 0


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	if state == LOST and not recorded:
		recorded = true
		Scores.submit_high("pills", score)
	if paused or state == WON or state == LOST:
		return

	if state == FLASHING:
		flash_timer += delta
		queue_redraw()
		if flash_timer >= FLASH_TIME:
			_apply_clear()
		return

	if state == SETTLING:
		settle_timer += delta
		if settle_timer >= SETTLE_STEP:
			settle_timer = 0.0
			if not _settle_step():
				_resolve()
			queue_redraw()
		return

	# FALLING
	if move_dir != 0:
		das_timer += delta
		if das_timer >= DAS:
			arr_timer += delta
			while arr_timer >= ARR:
				arr_timer -= ARR
				if not _try_move(move_dir, 0):
					break

	var interval := _gravity_interval()
	if Input.is_physical_key_pressed(KEY_DOWN):
		interval = 0.045
	gravity_timer += delta
	while gravity_timer >= interval:
		gravity_timer -= interval
		if not _try_move(0, 1):
			_lock_pill()
			return


# --- Drawing ------------------------------------------------------------------

func _cell_rect(c: int, r: int) -> Rect2:
	return Rect2(BOTTLE_ORIGIN + Vector2(c * CELL, r * CELL), Vector2(CELL, CELL))


func _draw() -> void:
	var bottle := Rect2(BOTTLE_ORIGIN, Vector2(COLS * CELL, ROWS * CELL))

	# Bottle neck, purely decorative
	var neck := Rect2(bottle.position.x + bottle.size.x * 0.5 - 34, bottle.position.y - 26, 68, 26)
	draw_rect(neck, Blocks.BG)
	Blocks.outline(self, neck)

	draw_rect(bottle, Blocks.BG)
	for c in range(1, COLS):
		var x := bottle.position.x + c * CELL
		draw_line(Vector2(x, bottle.position.y), Vector2(x, bottle.end.y), Blocks.GRID_LINE)
	for r in range(1, ROWS):
		var y := bottle.position.y + r * CELL
		draw_line(Vector2(bottle.position.x, y), Vector2(bottle.end.x, y), Blocks.GRID_LINE)

	var flash_on := state == FLASHING and fmod(flash_timer, 0.12) < 0.06

	for r in ROWS:
		for c in COLS:
			var k: int = kind[r][c]
			if k == EMPTY:
				continue
			var col: Color = COLORS[color[r][c]]
			var rect := _cell_rect(c, r)
			if pending.has(Vector2i(c, r)) and flash_on:
				col = Blocks.INK
			if k == VIRUS:
				_draw_virus(rect, col)
			else:
				_draw_half(rect, col, k)

	# Active pill
	if state == FALLING and not paused:
		var cells := _pill_cells(pill_pos, pill_orient)
		var kinds := _pill_kinds(pill_orient)
		var ghost_y := _drop_distance()
		for i in 2:
			var g: Vector2i = cells[i] + Vector2i(0, ghost_y)
			_draw_half(_cell_rect(g.x, g.y), COLORS[pill_colors[i]] * Color(1, 1, 1, 0.28), kinds[i])
		for i in 2:
			var cell: Vector2i = cells[i]
			_draw_half(_cell_rect(cell.x, cell.y), COLORS[pill_colors[i]], kinds[i])

	Blocks.outline(self, bottle.grow(2))
	_draw_panel()
	_draw_controls()

	if paused:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "PAUSED", "P to resume")
	elif state == WON:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "LEVEL CLEAR", "ENTER for level %d" % (level + 1))
	elif state == LOST:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "GAME OVER", "ENTER to play again    ESC for menu")


func _draw_half(rect: Rect2, col: Color, k: int) -> void:
	var r := rect.grow(-3)
	var center := r.position + r.size * 0.5
	var radius: float = r.size.y * 0.5
	draw_circle(center, radius, col)
	# Square off the linked side so the two halves read as one pill.
	match k:
		LINK_RIGHT:
			draw_rect(Rect2(center.x, r.position.y, r.size.x * 0.5 + 1, r.size.y), col)
		LINK_LEFT:
			draw_rect(Rect2(r.position.x - 1, r.position.y, r.size.x * 0.5 + 1, r.size.y), col)
		LINK_DOWN:
			draw_rect(Rect2(r.position.x, center.y, r.size.x, r.size.y * 0.5 + 1), col)
		LINK_UP:
			draw_rect(Rect2(r.position.x, r.position.y - 1, r.size.x, r.size.y * 0.5 + 1), col)
	# No highlight: flat colour only.


func _draw_virus(rect: Rect2, col: Color) -> void:
	var r := rect.grow(-4)
	var center := r.position + r.size * 0.5
	var radius: float = r.size.x * 0.5
	draw_circle(center, radius, col)
	# Little nubs so viruses read differently from pills
	var nub := radius * 0.34
	draw_circle(center + Vector2(-radius * 0.85, -radius * 0.5), nub, col)
	draw_circle(center + Vector2(radius * 0.85, -radius * 0.5), nub, col)
	draw_circle(center + Vector2(0, radius * 0.95), nub, col)
	# Eyes
	var eye := radius * 0.26
	var dark := Blocks.INK
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.1), eye, Blocks.PAPER)
	draw_circle(center + Vector2(radius * 0.32, -radius * 0.1), eye, Blocks.PAPER)
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.1), eye * 0.5, dark)
	draw_circle(center + Vector2(radius * 0.32, -radius * 0.1), eye * 0.5, dark)


func _draw_panel() -> void:
	var x := PANEL_X

	Blocks.tracked(self, Vector2(x, 158), "NEXT", 11, Blocks.INK_MID)
	var box := Rect2(Vector2(x, 172), Vector2(112, 72))
	Blocks.panel(self, box)
	var pill_w := CELL * 2.0
	var origin := box.position + (box.size - Vector2(pill_w, CELL)) * 0.5
	_draw_half(Rect2(origin, Vector2(CELL, CELL)), COLORS[next_colors[0]], LINK_RIGHT)
	_draw_half(Rect2(origin + Vector2(CELL, 0), Vector2(CELL, CELL)), COLORS[next_colors[1]], LINK_LEFT)

	var sy := 302.0
	for entry in [
		["LEVEL", str(level)],
		["VIRUSES", str(viruses_left)],
		["SCORE", str(score)],
	] + ([["BEST", str(int(Scores.get_best("pills")))]] if Scores.has("pills") else []):
		Blocks.rule(self, Vector2(x, sy - 14), 100, Blocks.INK, 1.0)
		Blocks.stat(self, Vector2(x, sy), entry[0], entry[1], 24)
		sy += 58

	if chain > 1 and state != FALLING:
		Blocks.tracked(self, Vector2(x, sy + 10), "CHAIN X%d" % chain, 14, Blocks.RED)


func _draw_controls() -> void:
	Blocks.rule(self, Vector2(BOTTLE_ORIGIN.x, 686), 480, Blocks.INK, 1.0)
	var cy := 706.0
	for line in [
		"LEFT RIGHT  MOVE        DOWN  SOFT DROP        SPACE  HARD DROP",
		"UP / X  ROTATE CW        Z  ROTATE CCW",
		"P  PAUSE        R  RESTART        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(BOTTLE_ORIGIN.x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
