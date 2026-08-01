class_name Snake
extends Node2D

# Classic snake. Eat, grow, don't run into the walls or yourself.

signal exit_to_menu

const COLS := 24
const ROWS := 26
const CELL := 20
const ORIGIN := Vector2(60, 120)

const START_LENGTH := 4
const BASE_INTERVAL := 0.13
const MIN_INTERVAL := 0.05

const COLOR_HEAD := Color("efede8")
const COLOR_BODY := Color("b9b6b0")
const COLOR_FOOD := Color("ff3b30")

var body: Array[Vector2i] = []
var dir := Vector2i(1, 0)
var queued: Array[Vector2i] = []   # buffered turns, so quick taps aren't eaten
var food := Vector2i.ZERO

var score := 0
var dead := false
var paused := false
var step_timer := 0.0
var entry := Scores.NameEntry.new()
var grow_by := 0


func _ready() -> void:
	new_game()


func new_game() -> void:
	body.clear()
	var mid_y := ROWS / 2
	for i in START_LENGTH:
		body.append(Vector2i(START_LENGTH + 2 - i, mid_y))
	dir = Vector2i(1, 0)
	queued.clear()
	score = 0
	dead = false
	paused = false
	step_timer = 0.0
	grow_by = 0
	_place_food()
	queue_redraw()


func _place_food() -> void:
	var free: Array[Vector2i] = []
	for r in ROWS:
		for c in COLS:
			var cell := Vector2i(c, r)
			if not body.has(cell):
				free.append(cell)
	if free.is_empty():
		return
	food = free[randi() % free.size()]


func _interval() -> float:
	return max(MIN_INTERVAL, BASE_INTERVAL - float(body.size() - START_LENGTH) * 0.002)


func _turn(d: Vector2i) -> void:
	# Compare against the last queued turn so two quick taps both register.
	var last: Vector2i = queued.back() if not queued.is_empty() else dir
	if d == -last or d == last:
		return
	if queued.size() < 2:
		queued.append(d)


func _step() -> void:
	if not queued.is_empty():
		dir = queued.pop_front()

	var head: Vector2i = body[0] + dir

	if head.x < 0 or head.x >= COLS or head.y < 0 or head.y >= ROWS:
		_die()
		return

	# The tail cell frees up on this step unless we're growing into it.
	var tail: Vector2i = body[body.size() - 1]
	var hits_self := body.has(head) and not (head == tail and grow_by == 0)
	if hits_self:
		_die()
		return

	body.insert(0, head)
	if head == food:
		score += 10
		grow_by += 1
		_place_food()

	if grow_by > 0:
		grow_by -= 1
	else:
		body.remove_at(body.size() - 1)

	queue_redraw()


func _die() -> void:
	dead = true
	Scores.submit_high("snake", score)
	if Scores.qualifies("snake", score):
		entry.start("snake")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if entry.handle_key(event as InputEventKey, score):
		queue_redraw()
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			new_game()
		KEY_P:
			if not dead:
				paused = not paused
				queue_redraw()
		KEY_LEFT, KEY_A:
			_turn(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			_turn(Vector2i(1, 0))
		KEY_UP, KEY_W:
			_turn(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			_turn(Vector2i(0, 1))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if dead:
				new_game()


func _process(delta: float) -> void:
	if dead or paused:
		return
	step_timer += delta
	while step_timer >= _interval():
		step_timer -= _interval()
		_step()
		if dead:
			return


# --- Drawing ------------------------------------------------------------------

func _cell_rect(c: int, r: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(c * CELL, r * CELL), Vector2(CELL, CELL))


func _draw() -> void:
	var board := Rect2(ORIGIN, Vector2(COLS * CELL, ROWS * CELL))
	draw_rect(board, Blocks.BG)
	for c in range(1, COLS):
		var x := ORIGIN.x + c * CELL
		draw_line(Vector2(x, board.position.y), Vector2(x, board.end.y), Blocks.GRID_LINE)
	for r in range(1, ROWS):
		var y := ORIGIN.y + r * CELL
		draw_line(Vector2(board.position.x, y), Vector2(board.end.x, y), Blocks.GRID_LINE)

	# Food
	var fr := _cell_rect(food.x, food.y)
	draw_circle(fr.position + fr.size * 0.5, CELL * 0.36, COLOR_FOOD)

	# Body, tail first so the head draws on top
	for i in range(body.size() - 1, -1, -1):
		var cell: Vector2i = body[i]
		var rect := _cell_rect(cell.x, cell.y).grow(-2)
		if i == 0:
			draw_rect(rect, COLOR_HEAD)
			# Eyes, facing the direction of travel
			var c := rect.position + rect.size * 0.5
			var side := Vector2(-dir.y, dir.x) * (CELL * 0.18)
			var fwd := Vector2(dir) * (CELL * 0.16)
			draw_circle(c + fwd + side, CELL * 0.09, Blocks.PAPER)
			draw_circle(c + fwd - side, CELL * 0.09, Blocks.PAPER)
		else:
			draw_rect(rect, COLOR_BODY)

	Blocks.outline(self, board.grow(2))

	Blocks.rule(self, Vector2(ORIGIN.x, 62), COLS * CELL, Blocks.INK, 1.0)
	Blocks.stat(self, Vector2(ORIGIN.x, 82), "SCORE", str(score), 28)
	Blocks.stat(self, Vector2(ORIGIN.x + 170, 82), "LENGTH", str(body.size()), 28)
	if Scores.has("snake"):
		Blocks.stat(self, Vector2(ORIGIN.x + 340, 82), "BEST", str(int(Scores.get_best("snake"))), 28)

	Blocks.rule(self, Vector2(ORIGIN.x, 686), COLS * CELL, Blocks.INK, 1.0)
	var cy := 706.0
	for line in ["ARROWS OR WASD  TURN", "P  PAUSE        R  RESTART        ESC  MENU"]:
		Blocks.tracked(self, Vector2(ORIGIN.x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16

	entry.draw(self, Main.DESIGN_SIZE.x, "MADE THE TABLE")
	if entry.active:
		return
	if paused:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "PAUSED", "P to resume")
	elif dead:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "GAME OVER", "%d points        ENTER to play again" % score)
