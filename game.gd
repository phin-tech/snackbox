extends Node2D

# --- Playfield geometry -------------------------------------------------------

const COLS := 10
const ROWS := 20              # visible rows
const HIDDEN := 2             # buffer rows above the visible field
const TOTAL := ROWS + HIDDEN
const CELL := 32

const BOARD_ORIGIN := Vector2(28, 30)
const PANEL_X := 372.0

# --- Piece data ---------------------------------------------------------------
# Each piece is defined by its spawn state inside an N x N box. Rotations are
# generated from that box, which is what makes the SRS kick tables below valid.

const PIECE_BOX := [4, 2, 3, 3, 3, 3, 3]          # I O T S Z J L
const PIECE_SPAWN := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],  # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],  # O
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],  # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],  # Z
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # J
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # L
]

const PIECE_COLOR := [
	Color("00e5ff"),  # I cyan
	Color("ffd400"),  # O yellow
	Color("c14bff"),  # T purple
	Color("2ee65a"),  # S green
	Color("ff3b56"),  # Z red
	Color("2f6bff"),  # J blue
	Color("ff8a1e"),  # L orange
]

# SRS wall kicks. Keys are from_rotation * 10 + to_rotation. Offsets are already
# flipped to screen space (y grows downward).
const KICKS_JLSTZ := {
	1: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	10: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	12: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	21: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	23: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
	32: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	30: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	3: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
}
const KICKS_I := {
	1: [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)],
	10: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2)],
	12: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1)],
	21: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1)],
	23: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2)],
	32: [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)],
	30: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1)],
	3: [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1)],
}

# --- Tuning -------------------------------------------------------------------

const DAS := 0.15             # delay before auto-repeat kicks in
const ARR := 0.04             # auto-repeat interval
const SOFT_DROP_FACTOR := 20.0
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15

const SCORE_LINES := [0, 100, 300, 500, 800]

# --- State --------------------------------------------------------------------

var rotations := []           # rotations[type][rot] -> Array[Vector2i]
var grid := []                # grid[row][col] -> -1 empty, else piece type

var piece_type := -1
var piece_rot := 0
var piece_pos := Vector2i.ZERO

var bag: Array[int] = []
var next_queue: Array[int] = []
var hold_type := -1
var hold_used := false

var score := 0
var lines := 0
var level := 1
var game_over := false
var paused := false

var gravity_timer := 0.0
var lock_timer := 0.0
var lock_resets := 0
var grounded := false

var move_dir := 0
var das_timer := 0.0
var arr_timer := 0.0

var clearing_rows: Array[int] = []
var clear_timer := 0.0
const CLEAR_TIME := 0.18

var font: Font


const DESIGN_SIZE := Vector2(600, 760)


func _ready() -> void:
	font = ThemeDB.fallback_font
	_fit_window_to_screen()
	_build_rotations()
	new_game()


func _fit_window_to_screen() -> void:
	# Scale the window up to fill most of the usable screen area while keeping
	# the 600x760 design aspect. Stretch mode "canvas_items" scales the drawing.
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	# On hiDPI displays the usable rect is reported in physical pixels while
	# window size/position are in logical points, so convert first.
	var dpi_scale: float = maxf(DisplayServer.screen_get_scale(screen), 1.0)
	var avail := Vector2(usable.size) / dpi_scale
	var origin := Vector2(usable.position) / dpi_scale

	var factor: float = min(avail.x * 0.92 / DESIGN_SIZE.x, avail.y * 0.94 / DESIGN_SIZE.y)
	factor = max(factor, 1.0)
	var size := Vector2i(DESIGN_SIZE * factor)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i(origin + (avail - Vector2(size)) * 0.5))


func _build_rotations() -> void:
	rotations.clear()
	for t in PIECE_SPAWN.size():
		var n: int = PIECE_BOX[t]
		var states := []
		var cur: Array = PIECE_SPAWN[t].duplicate()
		for r in 4:
			states.append(cur.duplicate())
			var nxt := []
			for c in cur:
				nxt.append(Vector2i(n - 1 - c.y, c.x))
			cur = nxt
		rotations.append(states)


func new_game() -> void:
	grid.clear()
	for r in TOTAL:
		var row := []
		row.resize(COLS)
		row.fill(-1)
		grid.append(row)

	bag.clear()
	next_queue.clear()
	for i in 3:
		next_queue.append(_take_from_bag())

	hold_type = -1
	hold_used = false
	score = 0
	lines = 0
	level = 1
	game_over = false
	paused = false
	clearing_rows.clear()
	move_dir = 0
	piece_type = -1
	_spawn_piece()
	queue_redraw()


# --- Randomizer (7-bag) -------------------------------------------------------

func _take_from_bag() -> int:
	if bag.is_empty():
		bag = [0, 1, 2, 3, 4, 5, 6]
		bag.shuffle()
	return bag.pop_back()


# --- Piece helpers ------------------------------------------------------------

func _cells(type: int, rot: int, pos: Vector2i) -> Array:
	var out := []
	for c in rotations[type][rot]:
		out.append(pos + c)
	return out


func _collides(type: int, rot: int, pos: Vector2i) -> bool:
	for c in _cells(type, rot, pos):
		if c.x < 0 or c.x >= COLS or c.y >= TOTAL:
			return true
		if c.y >= 0 and grid[c.y][c.x] != -1:
			return true
	return false


func _spawn_piece() -> void:
	piece_type = next_queue.pop_front()
	next_queue.append(_take_from_bag())
	piece_rot = 0
	var x := 3
	if PIECE_BOX[piece_type] == 2:
		x = 4
	piece_pos = Vector2i(x, 1)
	hold_used = false
	_reset_lock()
	gravity_timer = 0.0
	if _collides(piece_type, piece_rot, piece_pos):
		game_over = true


func _reset_lock() -> void:
	lock_timer = 0.0
	lock_resets = 0
	grounded = false


func _gravity_interval() -> float:
	# Classic-style speed curve, capped so it stays playable.
	var l: float = float(min(level, 20))
	return max(0.05, pow(0.8 - (l - 1) * 0.007, l - 1))


# --- Movement -----------------------------------------------------------------

func _try_move(dx: int, dy: int) -> bool:
	var np := piece_pos + Vector2i(dx, dy)
	if _collides(piece_type, piece_rot, np):
		return false
	piece_pos = np
	_touch_lock()
	queue_redraw()
	return true


func _try_rotate(dir: int) -> bool:
	if piece_type == 1:  # O piece never needs to rotate
		return false
	var from := piece_rot
	var to := (piece_rot + dir + 4) % 4
	var table: Dictionary = KICKS_I if piece_type == 0 else KICKS_JLSTZ
	var kicks: Array = table[from * 10 + to]
	for k in kicks:
		var np: Vector2i = piece_pos + k
		if not _collides(piece_type, to, np):
			piece_rot = to
			piece_pos = np
			_touch_lock()
			queue_redraw()
			return true
	return false


func _touch_lock() -> void:
	# Moving or rotating while resting on the stack refreshes the lock delay.
	if grounded and lock_resets < MAX_LOCK_RESETS:
		lock_resets += 1
		lock_timer = 0.0


func _ghost_pos() -> Vector2i:
	var p := piece_pos
	while not _collides(piece_type, piece_rot, p + Vector2i(0, 1)):
		p += Vector2i(0, 1)
	return p


func _hard_drop() -> void:
	var target := _ghost_pos()
	score += 2 * (target.y - piece_pos.y)
	piece_pos = target
	_lock_piece()


func _hold() -> void:
	if hold_used:
		return
	var swapped := hold_type
	hold_type = piece_type
	if swapped == -1:
		_spawn_piece()
	else:
		piece_type = swapped
		piece_rot = 0
		var x := 3
		if PIECE_BOX[piece_type] == 2:
			x = 4
		piece_pos = Vector2i(x, 1)
		_reset_lock()
		gravity_timer = 0.0
		if _collides(piece_type, piece_rot, piece_pos):
			game_over = true
	hold_used = true
	queue_redraw()


func _lock_piece() -> void:
	for c in _cells(piece_type, piece_rot, piece_pos):
		if c.y >= 0:
			grid[c.y][c.x] = piece_type

	var full: Array[int] = []
	for r in TOTAL:
		var complete := true
		for c in COLS:
			if grid[r][c] == -1:
				complete = false
				break
		if complete:
			full.append(r)

	if full.is_empty():
		_spawn_piece()
	else:
		clearing_rows = full
		clear_timer = 0.0
		piece_type = -1
	queue_redraw()


func _finish_clear() -> void:
	var n := clearing_rows.size()
	for r in clearing_rows:
		grid.remove_at(r)
		var row := []
		row.resize(COLS)
		row.fill(-1)
		grid.insert(0, row)

	score += SCORE_LINES[n] * level
	lines += n
	level = 1 + lines / 10
	clearing_rows.clear()
	_spawn_piece()
	queue_redraw()


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	var k := event as InputEventKey
	var code := k.physical_keycode

	if k.pressed:
		match code:
			KEY_R:
				new_game()
				return
			KEY_P, KEY_ESCAPE:
				if not game_over:
					paused = not paused
					queue_redraw()
				return

		if game_over:
			if code == KEY_ENTER or code == KEY_SPACE:
				new_game()
			return
		if paused:
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
			KEY_A:
				_try_rotate(2)
			KEY_SPACE:
				if piece_type != -1:
					_hard_drop()
			KEY_C, KEY_SHIFT:
				if piece_type != -1:
					_hold()
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
	if game_over or paused:
		return

	if not clearing_rows.is_empty():
		clear_timer += delta
		if clear_timer >= CLEAR_TIME:
			_finish_clear()
		else:
			queue_redraw()
		return

	if piece_type == -1:
		return

	# Horizontal auto-repeat (DAS / ARR)
	if move_dir != 0:
		das_timer += delta
		if das_timer >= DAS:
			arr_timer += delta
			while arr_timer >= ARR:
				arr_timer -= ARR
				if not _try_move(move_dir, 0):
					break

	# Gravity
	var interval := _gravity_interval()
	if Input.is_physical_key_pressed(KEY_DOWN):
		interval = min(interval / SOFT_DROP_FACTOR, 0.05)
	gravity_timer += delta
	while gravity_timer >= interval:
		gravity_timer -= interval
		if _collides(piece_type, piece_rot, piece_pos + Vector2i(0, 1)):
			break
		piece_pos.y += 1
		if Input.is_physical_key_pressed(KEY_DOWN):
			score += 1
		queue_redraw()

	# Lock delay
	var resting := _collides(piece_type, piece_rot, piece_pos + Vector2i(0, 1))
	if resting:
		if not grounded:
			grounded = true
			lock_timer = 0.0
		lock_timer += delta
		if lock_timer >= LOCK_DELAY:
			_lock_piece()
	else:
		grounded = false
		lock_timer = 0.0


# --- Drawing ------------------------------------------------------------------

func _cell_rect(col: int, row: int) -> Rect2:
	# row is in grid space; hidden rows sit above the visible origin.
	return Rect2(
		BOARD_ORIGIN + Vector2(col * CELL, (row - HIDDEN) * CELL),
		Vector2(CELL, CELL)
	)


func _draw_block(rect: Rect2, color: Color, alpha := 1.0) -> void:
	var c := color
	c.a *= alpha
	draw_rect(rect.grow(-1), c)
	# Bevel: light on top/left, dark on bottom/right.
	var light := c.lightened(0.35)
	light.a = c.a
	var dark := c.darkened(0.4)
	dark.a = c.a
	var r := rect.grow(-1)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), light)
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), light)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), dark)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 3, 0), Vector2(3, r.size.y)), dark)


func _draw_outline(rect: Rect2, color: Color, width := 2.0) -> void:
	draw_rect(rect, color, false, width)


func _draw_text(pos: Vector2, text: String, size := 16, color := Color("d8dcea")) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	var board_rect := Rect2(BOARD_ORIGIN, Vector2(COLS * CELL, ROWS * CELL))

	# Playfield background + grid
	draw_rect(board_rect, Color("0d1018"))
	for c in range(1, COLS):
		var x := BOARD_ORIGIN.x + c * CELL
		draw_line(Vector2(x, board_rect.position.y), Vector2(x, board_rect.end.y), Color(1, 1, 1, 0.05))
	for r in range(1, ROWS):
		var y := BOARD_ORIGIN.y + r * CELL
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.end.x, y), Color(1, 1, 1, 0.05))

	# Settled blocks
	for r in range(HIDDEN, TOTAL):
		for c in COLS:
			var t: int = grid[r][c]
			if t == -1:
				continue
			if clearing_rows.has(r):
				var progress: float = clamp(clear_timer / CLEAR_TIME, 0.0, 1.0)
				_draw_block(_cell_rect(c, r), PIECE_COLOR[t].lerp(Color.WHITE, progress), 1.0 - progress * 0.6)
			else:
				_draw_block(_cell_rect(c, r), PIECE_COLOR[t])

	# Ghost + active piece
	if piece_type != -1 and not game_over:
		var ghost := _ghost_pos()
		for c in _cells(piece_type, piece_rot, ghost):
			if c.y >= HIDDEN:
				_draw_block(_cell_rect(c.x, c.y), PIECE_COLOR[piece_type], 0.28)
		for c in _cells(piece_type, piece_rot, piece_pos):
			if c.y >= HIDDEN:
				_draw_block(_cell_rect(c.x, c.y), PIECE_COLOR[piece_type])

	_draw_outline(board_rect.grow(2), Color("39405c"), 2.0)

	_draw_panel()

	if paused:
		_draw_banner("PAUSED", "P to resume")
	elif game_over:
		_draw_banner("GAME OVER", "ENTER to play again")


func _draw_panel() -> void:
	var x := PANEL_X
	var box := Vector2(4 * 24 + 16, 4 * 24 + 16)

	# HOLD
	_draw_text(Vector2(x, 52), "HOLD", 15, Color("8892b0"))
	var hold_rect := Rect2(Vector2(x, 62), box)
	draw_rect(hold_rect, Color("0d1018"))
	_draw_outline(hold_rect, Color("39405c"))
	if hold_type != -1:
		_draw_mini(hold_type, hold_rect, 0.45 if hold_used else 1.0)

	# NEXT
	var ny := hold_rect.end.y + 34
	_draw_text(Vector2(x, ny - 10), "NEXT", 15, Color("8892b0"))
	for i in next_queue.size():
		var r := Rect2(Vector2(x, ny + i * (box.y + 8)), box)
		draw_rect(r, Color("0d1018"))
		_draw_outline(r, Color("39405c"))
		_draw_mini(next_queue[i], r)

	# Stats
	var sy := 470.0
	for entry in [["SCORE", str(score)], ["LEVEL", str(level)], ["LINES", str(lines)]]:
		_draw_text(Vector2(x, sy), entry[0], 14, Color("8892b0"))
		_draw_text(Vector2(x, sy + 26), entry[1], 24, Color("f2f5ff"))
		sy += 56

	# Controls, below the playfield
	var cy := 700.0
	for line in [
		"← →  move        ↓  soft drop        SPACE  hard drop",
		"↑ / X  rotate cw        Z  rotate ccw        C  hold",
		"P  pause        R  restart",
	]:
		_draw_text(Vector2(BOARD_ORIGIN.x, cy), line, 13, Color("5c6584"))
		cy += 18


func _draw_mini(type: int, box: Rect2, alpha := 1.0) -> void:
	var cells: Array = rotations[type][0]
	var minx := 99
	var maxx := -99
	var miny := 99
	var maxy := -99
	for c in cells:
		minx = min(minx, c.x)
		maxx = max(maxx, c.x)
		miny = min(miny, c.y)
		maxy = max(maxy, c.y)
	var w := (maxx - minx + 1) * 24
	var h := (maxy - miny + 1) * 24
	var origin := box.position + (box.size - Vector2(w, h)) * 0.5
	for c in cells:
		var r := Rect2(origin + Vector2((c.x - minx) * 24, (c.y - miny) * 24), Vector2(24, 24))
		_draw_block(r, PIECE_COLOR[type], alpha)


func _draw_banner(title: String, subtitle: String) -> void:
	var w := 600.0
	var h := 120.0
	var top := 300.0
	draw_rect(Rect2(0, top, w, h), Color(0.02, 0.03, 0.06, 0.9))
	draw_rect(Rect2(0, top, w, 3), Color("00e5ff"))
	draw_rect(Rect2(0, top + h - 3, w, 3), Color("00e5ff"))
	var t_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
	draw_string(font, Vector2((w - t_size.x) * 0.5, top + 55), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("f2f5ff"))
	var s_size := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, Vector2((w - s_size.x) * 0.5, top + 90), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("8892b0"))
