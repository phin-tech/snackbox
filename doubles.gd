class_name Doubles
extends Node2D

# Slide-and-merge number puzzle. Every move shifts the whole board one way,
# equal neighbours fuse, and a new tile appears. Reach 2048.
#
# _slide() does the whole board transform and reports whether anything moved,
# which keeps the rules separable from spawning - and easy to test exactly.

signal exit_to_menu

const SIZE := 4
const TILE := 100
const GAP := 10
const ORIGIN := Vector2(75, 200)
const TARGET := 2048

const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)
const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)

const TILE_COLORS := {
	2: Color("3a4260"), 4: Color("46527d"), 8: Color("ff8a1e"), 16: Color("ff6f2c"),
	32: Color("ff5a45"), 64: Color("ff3b56"), 128: Color("ffd400"), 256: Color("ffc400"),
	512: Color("2ee65a"), 1024: Color("00e5ff"), 2048: Color("c14bff"),
}

var grid := []                # grid[row][col] -> 0 empty, else tile value
var score := 0
var best := 0
var won := false              # hit 2048 at least once; play carries on
var dead := false
var spawned := Vector2i(-1, -1)
var pop := 0.0


func _ready() -> void:
	new_game()


func new_game() -> void:
	grid.clear()
	for r in SIZE:
		var row := []
		row.resize(SIZE)
		row.fill(0)
		grid.append(row)
	score = 0
	won = false
	dead = false
	_spawn()
	_spawn()
	queue_redraw()


func _empties() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in SIZE:
		for c in SIZE:
			if grid[r][c] == 0:
				out.append(Vector2i(c, r))
	return out


func _spawn() -> void:
	var free := _empties()
	if free.is_empty():
		return
	var cell: Vector2i = free[randi() % free.size()]
	grid[cell.y][cell.x] = 4 if randf() < 0.1 else 2
	spawned = cell
	pop = 1.0


func _line(index: int, dir: Vector2i) -> Array[Vector2i]:
	# Cells of one row or column, ordered so the leading edge comes first.
	var cells: Array[Vector2i] = []
	for i in SIZE:
		if dir.x != 0:
			cells.append(Vector2i(i if dir.x < 0 else SIZE - 1 - i, index))
		else:
			cells.append(Vector2i(index, i if dir.y < 0 else SIZE - 1 - i))
	return cells


func _slide(dir: Vector2i) -> bool:
	var moved := false
	for index in SIZE:
		var cells := _line(index, dir)

		var values: Array[int] = []
		for cell in cells:
			var v: int = grid[cell.y][cell.x]
			if v != 0:
				values.append(v)

		# Fuse equal neighbours once each, front to back.
		var merged: Array[int] = []
		var i := 0
		while i < values.size():
			if i + 1 < values.size() and values[i] == values[i + 1]:
				var sum: int = values[i] * 2
				merged.append(sum)
				score += sum
				if sum >= TARGET:
					won = true
				i += 2
			else:
				merged.append(values[i])
				i += 1

		while merged.size() < SIZE:
			merged.append(0)

		for j in SIZE:
			var cell: Vector2i = cells[j]
			if grid[cell.y][cell.x] != merged[j]:
				moved = true
				grid[cell.y][cell.x] = merged[j]

	return moved


func _has_moves() -> bool:
	for r in SIZE:
		for c in SIZE:
			if grid[r][c] == 0:
				return true
			if c + 1 < SIZE and grid[r][c] == grid[r][c + 1]:
				return true
			if r + 1 < SIZE and grid[r][c] == grid[r + 1][c]:
				return true
	return false


func _move(dir: Vector2i) -> void:
	if dead:
		return
	if not _slide(dir):
		return          # nothing shifted, so no new tile either
	_spawn()
	if not _has_moves():
		dead = true
		best = max(best, score)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			new_game()
		KEY_LEFT, KEY_A:
			_move(LEFT)
		KEY_RIGHT, KEY_D:
			_move(RIGHT)
		KEY_UP, KEY_W:
			_move(UP)
		KEY_DOWN, KEY_S:
			_move(DOWN)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if dead:
				new_game()


func _process(delta: float) -> void:
	if pop > 0.0:
		pop = max(pop - delta * 5.0, 0.0)
		queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _tile_rect(c: int, r: int) -> Rect2:
	return Rect2(
		ORIGIN + Vector2(GAP + c * (TILE + GAP), GAP + r * (TILE + GAP)),
		Vector2(TILE, TILE)
	)


func _draw() -> void:
	var side := SIZE * TILE + (SIZE + 1) * GAP
	var board := Rect2(ORIGIN, Vector2(side, side))
	draw_rect(board, Blocks.BG)

	for r in SIZE:
		for c in SIZE:
			var rect := _tile_rect(c, r)
			var v: int = grid[r][c]
			if v == 0:
				draw_rect(rect, Color(1, 1, 1, 0.04))
				continue

			# Newly spawned tiles pop in rather than appearing flat.
			if Vector2i(c, r) == spawned and pop > 0.0:
				var s: float = 1.0 - pop * 0.25
				rect = Rect2(rect.position + rect.size * (1.0 - s) * 0.5, rect.size * s)

			var col: Color = TILE_COLORS.get(v, Color("8b5cf6"))
			draw_rect(rect, col)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), col.lightened(0.3))

			var label := str(v)
			var size := 44
			if v >= 1024:
				size = 30
			elif v >= 128:
				size = 36
			var text_col: Color = Blocks.TEXT if v > 4 else Blocks.TEXT_DIM
			var dims := Blocks.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			draw_string(Blocks.font(), rect.position + Vector2((rect.size.x - dims.x) * 0.5, rect.size.y * 0.5 + size * 0.35),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, text_col)

	Blocks.outline(self, board.grow(2))

	Blocks.text(self, Vector2(ORIGIN.x, 108), "SCORE", 14, Blocks.TEXT_DIM)
	Blocks.text(self, Vector2(ORIGIN.x, 140), str(score), 30, Blocks.TEXT)
	if best > 0:
		Blocks.text(self, Vector2(ORIGIN.x + 200, 110), "BEST", 14, Blocks.TEXT_DIM)
		Blocks.text(self, Vector2(ORIGIN.x + 200, 140), str(best), 30, Blocks.TEXT)
	if won:
		Blocks.text(self, Vector2(ORIGIN.x + 360, 140), "2048!", 24, Blocks.ACCENT)

	var cy := 700.0
	for line in ["← → ↑ ↓ or WASD  slide everything one way", "R  restart        ESC  menu"]:
		Blocks.text(self, Vector2(ORIGIN.x, cy), line, 13, Blocks.TEXT_FAINT)
		cy += 18

	if dead:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "NO MOVES LEFT", "%d points        ENTER to play again" % score)
