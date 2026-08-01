class_name Landgrab
extends Node2D

# Qix / Barrack style area claiming. Cut into open space to draw a trail, get
# back to safe ground to seal it off, and any pocket the drifters aren't in
# becomes yours. Claim the target percentage to clear the level.

signal exit_to_menu

const COLS := 40
const ROWS := 48
const CELL := 12
const ORIGIN := Vector2(60, 78)

const EMPTY := 0
const FILLED := 1
const TRAIL := 2

const PLAYING := 0
const DYING := 1
const WON := 2
const LOST := 3

const TARGET_PERCENT := 75.0
const MOVE_INTERVAL := 0.028      # how fast the player walks
const DEATH_PAUSE := 1.1
const START_LIVES := 3

const COLOR_FILLED := Color("2d6fc0")
const COLOR_TRAIL := Color("ff3b30")
const COLOR_PLAYER := Color("efede8")
const COLOR_ENEMY := Color("efede8")

var grid := []
var state := PLAYING
var level := 1
var lives := START_LIVES
var score := 0
var claimed_percent := 0.0

var player := Vector2i.ZERO
var drawing := false
var trail: Array[Vector2i] = []
var enter_from := Vector2i.ZERO   # safe cell the current trail started from
var move_timer := 0.0
var death_timer := 0.0

var enemies := []                 # [{pos: Vector2, vel: Vector2}]
var flash := 0.0
var recorded := false


func _ready() -> void:
	new_game()


func new_game() -> void:
	level = 1
	lives = START_LIVES
	score = 0
	recorded = false
	_start_level()


func _start_level() -> void:
	grid.clear()
	for r in ROWS:
		var row := []
		row.resize(COLS)
		row.fill(EMPTY)
		grid.append(row)

	# Two-cell border is the starting safe ground.
	for r in ROWS:
		for c in COLS:
			if r < 2 or r >= ROWS - 2 or c < 2 or c >= COLS - 2:
				grid[r][c] = FILLED

	player = Vector2i(1, 1)
	drawing = false
	trail.clear()
	state = PLAYING
	move_timer = 0.0

	enemies.clear()
	var count: int = min(1 + level, 5)
	for i in count:
		var speed := 15.0 + level * 2.0
		var angle := randf_range(0.6, 1.0) * (1 if i % 2 == 0 else -1)
		enemies.append({
			"pos": Vector2(randf_range(COLS * 0.3, COLS * 0.7), randf_range(ROWS * 0.3, ROWS * 0.7)),
			"vel": Vector2(cos(angle), sin(angle)).normalized() * speed,
		})

	_recount()
	queue_redraw()


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


func _recount() -> void:
	var filled := 0
	for r in ROWS:
		for c in COLS:
			if grid[r][c] == FILLED:
				filled += 1
	var total := ROWS * COLS
	var border := total - (ROWS - 4) * (COLS - 4)
	claimed_percent = float(filled - border) / float(total - border) * 100.0


# --- Player -------------------------------------------------------------------

func _step_player(dir: Vector2i) -> void:
	var target := player + dir
	if not _in_bounds(target):
		return

	var cell: int = grid[target.y][target.x]
	if cell == TRAIL:
		return  # never cross your own line

	if cell == EMPTY:
		if not drawing:
			drawing = true
			enter_from = player
			trail.clear()
		grid[target.y][target.x] = TRAIL
		trail.append(target)
		player = target
	else:  # FILLED
		player = target
		if drawing:
			_close_region()
	queue_redraw()


func _close_region() -> void:
	for c in trail:
		grid[c.y][c.x] = FILLED
	trail.clear()
	drawing = false

	# Anything the drifters can't reach is now sealed off and becomes yours.
	var reachable := {}
	var queue: Array[Vector2i] = []
	for e in enemies:
		var start := Vector2i(int(e.pos.x), int(e.pos.y))
		if _in_bounds(start) and grid[start.y][start.x] == EMPTY and not reachable.has(start):
			reachable[start] = true
			queue.append(start)

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not _in_bounds(n) or reachable.has(n):
				continue
			if grid[n.y][n.x] != EMPTY:
				continue
			reachable[n] = true
			queue.append(n)

	var gained := 0
	for r in ROWS:
		for c in COLS:
			if grid[r][c] == EMPTY and not reachable.has(Vector2i(c, r)):
				grid[r][c] = FILLED
				gained += 1

	score += gained * 2
	_recount()

	if claimed_percent >= TARGET_PERCENT:
		score += int(claimed_percent - TARGET_PERCENT) * 50 + lives * 500
		state = WON


func _die() -> void:
	for c in trail:
		grid[c.y][c.x] = EMPTY
	trail.clear()
	drawing = false
	lives -= 1
	state = LOST if lives <= 0 else DYING
	death_timer = 0.0
	queue_redraw()


func _respawn() -> void:
	player = enter_from if grid[enter_from.y][enter_from.x] == FILLED else Vector2i(1, 1)
	state = PLAYING
	move_timer = 0.0


# --- Enemies ------------------------------------------------------------------

func _blocked(p: Vector2) -> bool:
	var c := Vector2i(int(p.x), int(p.y))
	if not _in_bounds(c):
		return true
	return grid[c.y][c.x] == FILLED


func _move_enemies(delta: float) -> void:
	for e in enemies:
		var pos: Vector2 = e.pos
		var vel: Vector2 = e.vel

		var nx := Vector2(pos.x + vel.x * delta, pos.y)
		if _blocked(nx):
			vel.x = -vel.x
		else:
			pos.x = nx.x

		var ny := Vector2(pos.x, pos.y + vel.y * delta)
		if _blocked(ny):
			vel.y = -vel.y
		else:
			pos.y = ny.y

		e.pos = pos
		e.vel = vel

		# Clipping the trail - or the player while they're exposed - is fatal.
		var cell := Vector2i(int(pos.x), int(pos.y))
		if _in_bounds(cell) and grid[cell.y][cell.x] == TRAIL:
			_die()
			return
		if drawing and cell == player:
			_die()
			return


# --- Input --------------------------------------------------------------------

func _read_direction() -> Vector2i:
	if Input.is_physical_key_pressed(KEY_LEFT):
		return Vector2i(-1, 0)
	if Input.is_physical_key_pressed(KEY_RIGHT):
		return Vector2i(1, 0)
	if Input.is_physical_key_pressed(KEY_UP):
		return Vector2i(0, -1)
	if Input.is_physical_key_pressed(KEY_DOWN):
		return Vector2i(0, 1)
	return Vector2i.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			new_game()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if state == WON:
				level += 1
				_start_level()
			elif state == LOST:
				new_game()


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	flash += delta

	if state == LOST and not recorded:
		recorded = true
		Scores.submit_high("landgrab", score)

	if state == WON or state == LOST:
		queue_redraw()
		return

	if state == DYING:
		death_timer += delta
		if death_timer >= DEATH_PAUSE:
			_respawn()
		queue_redraw()
		return

	var dir := _read_direction()
	if dir != Vector2i.ZERO:
		move_timer += delta
		while move_timer >= MOVE_INTERVAL:
			move_timer -= MOVE_INTERVAL
			_step_player(dir)
			if state != PLAYING:
				return
	else:
		move_timer = MOVE_INTERVAL  # move immediately on the next key press

	_move_enemies(delta)
	queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _cell_rect(c: int, r: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(c * CELL, r * CELL), Vector2(CELL, CELL))


func _draw() -> void:
	var board := Rect2(ORIGIN, Vector2(COLS * CELL, ROWS * CELL))
	draw_rect(board, Blocks.BG)

	for r in ROWS:
		for c in COLS:
			match grid[r][c]:
				FILLED:
					Blocks.block(self, _cell_rect(c, r), COLOR_FILLED)
				TRAIL:
					Blocks.block(self, _cell_rect(c, r), COLOR_TRAIL)

	# Player
	if state == PLAYING or state == DYING:
		var blink := state != DYING or fmod(flash, 0.2) < 0.1
		if blink:
			Blocks.block(self, _cell_rect(player.x, player.y), COLOR_PLAYER)

	# Drifters
	for e in enemies:
		var center: Vector2 = ORIGIN + (e.pos + Vector2(0.5, 0.5)) * CELL
		draw_circle(center, CELL * 1.3, COLOR_ENEMY)
		draw_circle(center, CELL * 0.55, Blocks.PAPER)
		draw_circle(center, CELL * 0.28, Blocks.RED)

	Blocks.outline(self, board.grow(2))
	_draw_hud()
	_draw_controls()

	if state == WON:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "AREA CLEARED", "ENTER for level %d" % (level + 1))
	elif state == LOST:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "GAME OVER", "ENTER to play again    ESC for menu")


func _draw_hud() -> void:
	var w := Main.DESIGN_SIZE.x

	Blocks.stat(self, Vector2(ORIGIN.x, 26), "LEVEL", str(level), 22)
	Blocks.stat(self, Vector2(ORIGIN.x + 110, 26), "LIVES", str(lives), 22)
	Blocks.stat(self, Vector2(ORIGIN.x + 220, 26), "SCORE", str(score), 22)
	if Scores.has("landgrab"):
		Blocks.stat(self, Vector2(ORIGIN.x + 330, 26), "BEST", str(int(Scores.get_best("landgrab"))), 22)
	Blocks.tracked(self, Vector2(ORIGIN.x + 430, 26), "CLAIMED", 11, Blocks.INK_MID)
	var pct_color: Color = Blocks.RED if claimed_percent >= TARGET_PERCENT else Blocks.INK
	Blocks.text(self, Vector2(ORIGIN.x + 430, 52), "%d%%" % int(claimed_percent), 22, pct_color)

	# Progress bar under the board
	var bar := Rect2(ORIGIN.x, ORIGIN.y + ROWS * CELL + 14, COLS * CELL, 8)
	draw_rect(bar, Blocks.PAPER_SUNK)
	var frac: float = clampf(claimed_percent / 100.0, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Blocks.INK)
	var target_x := bar.position.x + bar.size.x * (TARGET_PERCENT / 100.0)
	draw_rect(Rect2(Vector2(target_x - 1, bar.position.y - 4), Vector2(2, bar.size.y + 8)), Blocks.RED)


func _draw_controls() -> void:
	Blocks.rule(self, Vector2(ORIGIN.x, 686), COLS * CELL, Blocks.INK, 1.0)
	var cy := 706.0
	for line in [
		"ARROWS  MOVE        HOLD A DIRECTION TO CUT INTO OPEN SPACE",
		"GET BACK TO SOLID GROUND TO SEAL THE AREA OFF",
		"R  RESTART        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(ORIGIN.x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
