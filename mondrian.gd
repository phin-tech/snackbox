class_name Mondrian
extends Node2D

# Qix style area claiming, painted as a De Stijl canvas. Cut into open space to
# draw a trail, get back to solid ground to seal it off, and any pocket the
# drifters aren't in becomes yours.
#
# Every sealed region is filled flat in one of Mondrian's colours and outlined
# in heavy black, so the board composes itself into a painting as you claim it.
# There is no grid: the black lines are the structure.

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

const COLOR_TRAIL := Color("d0021b")
const COLOR_PLAYER := Color("f4f1e8")
const COLOR_ENEMY := Color("f4f1e8")
const ENEMY_R := 0.55               # drifter radius, in cells
const CANVAS := Color("1c1f24")      # bare, unpainted ground
const LINE := Color("070707")
const LINE_W := 3.0

# Mondrian's palette, weighted the way he used it: mostly white, with the
# primaries as accents.
const PAINTS := [
	Color("f4f1e8"), Color("f4f1e8"), Color("f4f1e8"), Color("f4f1e8"),
	Color("d0021b"), Color("d0021b"),
	Color("0b4ea2"), Color("0b4ea2"),
	Color("f2c230"),
	Color("1a1a1a"),
]

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

var last_paint := Color("f4f1e8")  # avoid repeating this straight away
var region_of := []               # region_of[row][col] -> index into regions
var regions := []                 # colour per sealed region
var enemies := []                 # [{pos: Vector2, vel: Vector2}]
var flash := 0.0
var recorded := false
var entry := Scores.NameEntry.new()


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

	region_of = []
	for r in ROWS:
		var rr := []
		rr.resize(COLS)
		rr.fill(-1)
		region_of.append(rr)
	regions = [Color("f4f1e8")]        # the frame is white
	last_paint = Color("f4f1e8")

	# Two-cell border is the starting safe ground.
	for r in ROWS:
		for c in COLS:
			if r < 2 or r >= ROWS - 2 or c < 2 or c >= COLS - 2:
				grid[r][c] = FILLED
				region_of[r][c] = 0

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

	_paint_new_regions()
	score += gained * 2
	_recount()

	if claimed_percent >= TARGET_PERCENT:
		score += int(claimed_percent - TARGET_PERCENT) * 50 + lives * 500
		state = WON


func _paint_new_regions() -> void:
	# Anything newly claimed gets grouped into connected regions, and each one
	# is painted a single flat colour.
	for r in ROWS:
		for c in COLS:
			if grid[r][c] != FILLED or region_of[r][c] != -1:
				continue
			var id := regions.size()
			regions.append(Color("f4f1e8"))     # provisional; chosen below
			var cells: Array[Vector2i] = [Vector2i(c, r)]
			var queue: Array[Vector2i] = [Vector2i(c, r)]
			region_of[r][c] = id
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_back()
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cur + d
					if not _in_bounds(n):
						continue
					if grid[n.y][n.x] != FILLED or region_of[n.y][n.x] != -1:
						continue
					region_of[n.y][n.x] = id
					cells.append(n)
					queue.append(n)
			regions[id] = _pick_paint(cells, id)


func _pick_paint(cells: Array[Vector2i], id: int) -> Color:
	# Avoid whatever the neighbouring fields are already wearing, so two blocks
	# of the same colour don't merge into one shape visually.
	var taken := {}
	for cell in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if not _in_bounds(n):
				continue
			var other: int = region_of[n.y][n.x]
			if other == -1 or other == id or other >= regions.size():
				continue
			taken[regions[other]] = true

	# Also skip whatever was painted last, so two fields sealed one after the
	# other don't come out the same even when they aren't touching.
	var options: Array[Color] = []
	for paint in PAINTS:
		if not taken.has(paint) and paint != last_paint:
			options.append(paint)
	if options.is_empty():
		for paint in PAINTS:
			if not taken.has(paint):
				options.append(paint)
	if options.is_empty():
		options.assign(PAINTS)

	var chosen: Color = options[randi() % options.size()]
	last_paint = chosen
	return chosen


func _die() -> void:
	for c in trail:
		grid[c.y][c.x] = EMPTY
		region_of[c.y][c.x] = -1
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

		var step_x := pos.x + vel.x * delta
		var lead_x := Vector2(step_x + signf(vel.x) * ENEMY_R, pos.y)
		if _blocked(lead_x) or _blocked(Vector2(step_x, pos.y)):
			vel.x = -vel.x
		else:
			pos.x = step_x

		var step_y := pos.y + vel.y * delta
		var lead_y := Vector2(pos.x, step_y + signf(vel.y) * ENEMY_R)
		if _blocked(lead_y) or _blocked(Vector2(pos.x, step_y)):
			vel.y = -vel.y
		else:
			pos.y = step_y

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
	if entry.handle_key(event as InputEventKey, score):
		queue_redraw()
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
		Scores.submit_high("mondrian", score)
		if Scores.qualifies("mondrian", score):
			entry.start("mondrian")

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
	draw_rect(board, CANVAS)

	# Flat colour fields. No grid - the black lines carry the structure.
	for r in ROWS:
		for c in COLS:
			if grid[r][c] == FILLED:
				var id: int = region_of[r][c]
				var col: Color = regions[id] if id >= 0 and id < regions.size() else Color("f4f1e8")
				draw_rect(_cell_rect(c, r), col)
			elif grid[r][c] == TRAIL:
				draw_rect(_cell_rect(c, r), COLOR_TRAIL)

	# Heavy black rules wherever a painted field meets something else.
	for r in ROWS:
		for c in COLS:
			if grid[r][c] != FILLED:
				continue
			var here: int = region_of[r][c]
			var rect := _cell_rect(c, r)
			if _edge(c, r, Vector2i(0, -1), here):
				draw_rect(Rect2(rect.position.x, rect.position.y - LINE_W * 0.5, CELL, LINE_W), LINE)
			if _edge(c, r, Vector2i(0, 1), here):
				draw_rect(Rect2(rect.position.x, rect.end.y - LINE_W * 0.5, CELL, LINE_W), LINE)
			if _edge(c, r, Vector2i(-1, 0), here):
				draw_rect(Rect2(rect.position.x - LINE_W * 0.5, rect.position.y, LINE_W, CELL), LINE)
			if _edge(c, r, Vector2i(1, 0), here):
				draw_rect(Rect2(rect.end.x - LINE_W * 0.5, rect.position.y, LINE_W, CELL), LINE)

	# Player
	if state == PLAYING or state == DYING:
		var blink := state != DYING or fmod(flash, 0.2) < 0.1
		if blink:
			var pr := _cell_rect(player.x, player.y).grow(1)
			draw_rect(pr, COLOR_PLAYER)
			Blocks.outline(self, pr, LINE, 2.0)

	# Drifters
	for e in enemies:
		var center: Vector2 = ORIGIN + (e.pos + Vector2(0.5, 0.5)) * CELL
		draw_circle(center, CELL * ENEMY_R, COLOR_ENEMY)
		draw_arc(center, CELL * ENEMY_R, 0.0, TAU, 24, LINE, 2.0)
		draw_circle(center, CELL * ENEMY_R * 0.4, LINE)

	Blocks.outline(self, board, LINE, 4.0)
	_draw_hud()
	_draw_controls()

	entry.draw(self, Main.DESIGN_SIZE.x, "MADE THE TABLE")
	if entry.active:
		return
	if state == WON:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "CANVAS FILLED", "ENTER FOR LEVEL %d" % (level + 1))
	elif state == LOST:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "GAME OVER", "ENTER TO PLAY AGAIN        ESC FOR MENU")


func _edge(c: int, r: int, dir: Vector2i, here: int) -> bool:
	# A line is drawn where a field meets bare canvas, the frame, or a field of
	# a different colour.
	var n := Vector2i(c, r) + dir
	if not _in_bounds(n):
		return true
	if grid[n.y][n.x] != FILLED:
		return true
	return region_of[n.y][n.x] != here


func _draw_hud() -> void:
	var w := Main.DESIGN_SIZE.x

	Blocks.stat(self, Vector2(ORIGIN.x, 26), "LEVEL", str(level), 22)
	Blocks.stat(self, Vector2(ORIGIN.x + 110, 26), "LIVES", str(lives), 22)
	Blocks.stat(self, Vector2(ORIGIN.x + 220, 26), "SCORE", str(score), 22)
	if Scores.has("mondrian"):
		Blocks.stat(self, Vector2(ORIGIN.x + 330, 26), "BEST", str(int(Scores.get_best("mondrian"))), 22)
	Blocks.tracked(self, Vector2(ORIGIN.x + 430, 26), "CLAIMED", 11, Blocks.INK_MID)
	var pct_color: Color = Blocks.RED if claimed_percent >= TARGET_PERCENT else Blocks.INK
	Blocks.text(self, Vector2(ORIGIN.x + 430, 52), "%d%%" % int(claimed_percent), 22, pct_color)

	# Progress bar under the board
	var bar := Rect2(ORIGIN.x, ORIGIN.y + ROWS * CELL + 16, COLS * CELL, 10)
	draw_rect(bar, Blocks.PAPER_SUNK)
	var frac: float = clampf(claimed_percent / 100.0, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("f2c230"))
	var target_x := bar.position.x + bar.size.x * (TARGET_PERCENT / 100.0)
	draw_rect(Rect2(Vector2(target_x - 1, bar.position.y - 4), Vector2(2, bar.size.y + 8)), Color("d0021b"))
	Blocks.outline(self, bar, LINE, 2.0)


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
