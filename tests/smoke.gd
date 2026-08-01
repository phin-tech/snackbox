extends Node

# Headless smoke test. Each game is driven with a fixed timestep and random
# inputs for thousands of simulated frames, checking board invariants as it
# goes. Run with: task test
#
# Automatic processing is switched off so _process can be called with a fixed
# delta - headless frames are far too short to advance the games' timers.

const DT := 1.0 / 60.0
const FRAMES := 12000

var failures: Array[String] = []


func _ready() -> void:
	seed(20260731)

	# The games persist bests on death, so point the store at a scratch file -
	# a test run must never overwrite the player's real scores.
	Scores.path = "user://test_scores.cfg"
	Scores.reload()
	Scores.clear()

	_test_scores()

	for mode in ["marathon", "sprint", "ultra"]:
		_run_blocks(mode)
	_run_pills()
	_test_pills_horizontal_clear()
	_test_pills_vertical_clear()
	_test_pills_chain()
	_run_mondrian()
	_test_mondrian_seals_pocket()
	_run_snake()
	_test_snake_growth()
	_run_doubles()
	_test_doubles_merges()
	_test_linkup_generator()
	_test_linkup_solving()
	_test_linkup_editing()
	_test_gridlock_generator()
	_test_gridlock_solvable()
	_test_gridlock_moves()
	_test_shapes_generator()
	_test_shapes_solving()
	_test_shapes_rules()


	_cleanup_scores()

	if failures.is_empty():
		print("OK: all smoke tests passed")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("FAILED: %d check(s)" % failures.size())
		get_tree().quit(1)


func _cleanup_scores() -> void:
	Scores.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Scores.path))


func _test_scores() -> void:
	Scores.clear()

	if Scores.has("nope"):
		_fail("scores: an unset key reported as present")
	if Scores.get_best("nope", 5.0) != 5.0:
		_fail("scores: fallback ignored for an unset key")

	# Higher wins for scores.
	if not Scores.submit_high("k", 100.0):
		_fail("scores: first submission was not treated as a best")
	if Scores.submit_high("k", 50.0):
		_fail("scores: a lower score was accepted as a new best")
	if Scores.get_best("k") != 100.0:
		_fail("scores: a lower score overwrote the best (%f)" % Scores.get_best("k"))
	if not Scores.submit_high("k", 150.0):
		_fail("scores: a higher score was not accepted")
	if Scores.get_best("k") != 150.0:
		_fail("scores: best did not update to the higher score")

	# Lower wins for times.
	if not Scores.submit_low("t", 30.0):
		_fail("scores: first time was not treated as a best")
	if Scores.submit_low("t", 45.0):
		_fail("scores: a slower time was accepted as a new best")
	if not Scores.submit_low("t", 20.0):
		_fail("scores: a faster time was not accepted")
	if Scores.get_best("t") != 20.0:
		_fail("scores: best time did not update (%f)" % Scores.get_best("t"))

	# And it has to survive a round trip through the file.
	Scores.reload()
	if Scores.get_best("k") != 150.0 or Scores.get_best("t") != 20.0:
		_fail("scores: values did not persist across a reload (k=%f t=%f)"
			% [Scores.get_best("k"), Scores.get_best("t")])

	Scores.clear()
	if Scores.has("k"):
		_fail("scores: clear left values behind")


func _fail(msg: String) -> void:
	if not failures.has(msg):
		failures.append(msg)


func _drive(node: Node) -> void:
	add_child(node)
	node.set_process(false)


# --- Falling blocks -----------------------------------------------------------

func _run_blocks(mode: String) -> void:
	var g: Game = load("res://game.tscn").instantiate()
	g.mode = mode
	_drive(g)

	var restarts := 0
	var pieces := 0

	for i in FRAMES:
		g._process(DT)

		if g.piece_type != -1 and g.clearing_rows.is_empty() and not g._stopped():
			match randi() % 6:
				0: g._try_move(-1, 0)
				1: g._try_move(1, 0)
				2: g._try_rotate(1)
				3: g._try_rotate(-1)
				_:
					if i % 3 == 0:
						g._hard_drop()
						pieces += 1

		_check_blocks(g, mode)

		if g._stopped():
			if mode == "sprint" and g.finished and g.lines < g.SPRINT_GOAL:
				_fail("%s: finished before reaching the line goal" % mode)
			restarts += 1
			if restarts > 40:
				break
			g.new_game()

	if pieces < 50:
		_fail("%s: only %d pieces locked, test did not exercise the board" % [mode, pieces])
	if mode == "ultra" and restarts == 0:
		_fail("ultra: never hit the 2 minute limit across %d frames" % FRAMES)
	g.queue_free()


func _check_blocks(g: Game, mode: String) -> void:
	if g.lines < 0 or g.score < 0 or g.level < 1:
		_fail("%s: negative counters (lines=%d score=%d level=%d)" % [mode, g.lines, g.score, g.level])

	for r in g.TOTAL:
		for c in g.COLS:
			var v: int = g.grid[r][c]
			if v < -1 or v >= g.PIECE_COLOR.size():
				_fail("%s: bad cell value %d at %d,%d" % [mode, v, c, r])
				return

	# A piece must never overlap settled blocks.
	if g.piece_type != -1 and not g._stopped():
		for cell in g._cells(g.piece_type, g.piece_rot, g.piece_pos):
			if cell.y >= 0 and g.grid[cell.y][cell.x] != -1:
				_fail("%s: active piece overlaps the stack at %d,%d" % [mode, cell.x, cell.y])
				return
			if cell.x < 0 or cell.x >= g.COLS or cell.y >= g.TOTAL:
				_fail("%s: active piece left the board at %d,%d" % [mode, cell.x, cell.y])
				return


# --- Pills --------------------------------------------------------------------

func _run_pills() -> void:
	# Random play. Won't clear a level - it just hammers the invariants and
	# proves matching fires during ordinary play.
	var p: Pills = load("res://pills.tscn").instantiate()
	_drive(p)

	var locks := 0
	var viruses_cleared := 0
	var last_left := p.viruses_left

	for i in FRAMES:
		p._process(DT)

		if p.state == Pills.FALLING and not p.paused:
			match randi() % 6:
				0: p._try_move(-1, 0)
				1: p._try_move(1, 0)
				2: p._try_rotate(1)
				3: p._try_rotate(-1)
				_:
					if i % 3 == 0:
						p.pill_pos.y += p._drop_distance()
						p._lock_pill()
						locks += 1

		_check_pills(p)

		if p.viruses_left < last_left:
			viruses_cleared += last_left - p.viruses_left
		last_left = p.viruses_left

		if p.state == Pills.WON:
			p.level += 1
			p._start_level()
			last_left = p.viruses_left
		elif p.state == Pills.LOST:
			p.new_game()
			last_left = p.viruses_left

	if locks < 50:
		_fail("pills: only %d pills locked, test did not exercise the bottle" % locks)
	if viruses_cleared == 0:
		_fail("pills: no virus was ever cleared in %d frames" % FRAMES)
	p.queue_free()


# --- Deterministic pill scenarios ---------------------------------------------

func _fresh_pills() -> Pills:
	var p: Pills = load("res://pills.tscn").instantiate()
	_drive(p)
	for r in Pills.ROWS:
		for c in Pills.COLS:
			p.kind[r][c] = Pills.EMPTY
			p.color[r][c] = -1
	p.viruses_left = 0
	p.chain = 0
	p.pending.clear()
	p.state = Pills.FALLING
	return p


func _put(p: Pills, c: int, r: int, col: int, k := Pills.SINGLE) -> void:
	p.kind[r][c] = k
	p.color[r][c] = col
	if k == Pills.VIRUS:
		p.viruses_left += 1


func _settle(p: Pills, max_frames := 600) -> int:
	# Run until the board comes to rest, returning the highest chain reached.
	var best := 0
	for _i in max_frames:
		if p.state == Pills.FALLING or p.state == Pills.WON or p.state == Pills.LOST:
			break
		p._process(DT)
		best = max(best, p.chain)
		_check_pills(p)
	return max(best, p.chain)


func _test_pills_horizontal_clear() -> void:
	var p := _fresh_pills()
	var bottom := Pills.ROWS - 1
	for c in 3:
		_put(p, c, bottom, 0)
	_put(p, 3, bottom, 0, Pills.VIRUS)   # four in a row, one of them a virus

	p._resolve()
	_settle(p)

	if p.viruses_left != 0:
		_fail("pills/horizontal: virus survived a four-in-a-row (left=%d)" % p.viruses_left)
	if p.kind[bottom][0] != Pills.EMPTY:
		_fail("pills/horizontal: matched cells were not removed")
	if p.state != Pills.WON:
		_fail("pills/horizontal: clearing the last virus did not win the level (state=%d)" % p.state)
	p.queue_free()


func _test_pills_vertical_clear() -> void:
	var p := _fresh_pills()
	var bottom := Pills.ROWS - 1
	for i in 3:
		_put(p, 2, bottom - i, 1)
	_put(p, 2, bottom - 3, 1, Pills.VIRUS)

	p._resolve()
	_settle(p)

	if p.viruses_left != 0:
		_fail("pills/vertical: virus survived a four-in-a-column (left=%d)" % p.viruses_left)
	if p.kind[bottom][2] != Pills.EMPTY:
		_fail("pills/vertical: matched cells were not removed")
	p.queue_free()


func _test_pills_chain() -> void:
	# Clearing the bottom row drops the row above it into a second match.
	var p := _fresh_pills()
	var bottom := Pills.ROWS - 1
	for c in 4:
		_put(p, c, bottom, 0)
	for c in 3:
		_put(p, c, bottom - 1, 1)
	_put(p, 3, bottom - 3, 1)            # falls in to complete the second match
	_put(p, 7, bottom, 2, Pills.VIRUS)   # keep the level from ending early

	p._resolve()
	var best := _settle(p)

	if best < 2:
		_fail("pills/chain: expected a chain of at least 2, got %d" % best)
	for c in 4:
		if p.kind[bottom][c] != Pills.EMPTY:
			_fail("pills/chain: second match did not clear at column %d" % c)
			break
	p.queue_free()


func _check_pills(p: Pills) -> void:
	if p.viruses_left < 0:
		_fail("pills: virus count went negative (%d)" % p.viruses_left)
		return

	var mirror := {
		Pills.LINK_RIGHT: Pills.LINK_LEFT,
		Pills.LINK_LEFT: Pills.LINK_RIGHT,
		Pills.LINK_DOWN: Pills.LINK_UP,
		Pills.LINK_UP: Pills.LINK_DOWN,
	}
	var counted := 0

	for r in Pills.ROWS:
		for c in Pills.COLS:
			var k: int = p.kind[r][c]
			var col: int = p.color[r][c]

			if (k == Pills.EMPTY) != (col == -1):
				_fail("pills: kind/colour disagree at %d,%d (kind=%d colour=%d)" % [c, r, k, col])
				return
			if k == Pills.VIRUS:
				counted += 1
			if not mirror.has(k):
				continue

			# Every linked half must have a partner pointing back at it.
			var partner: Vector2i = Vector2i(c, r) + Pills.LINK_OFFSET[k]
			if partner.x < 0 or partner.x >= Pills.COLS or partner.y < 0 or partner.y >= Pills.ROWS:
				_fail("pills: half at %d,%d links off the board" % [c, r])
				return
			if p.kind[partner.y][partner.x] != mirror[k]:
				_fail("pills: half at %d,%d has no matching partner (found kind %d)" % [c, r, p.kind[partner.y][partner.x]])
				return

	if p.state == Pills.FALLING and counted != p.viruses_left:
		_fail("pills: virus counter %d does not match %d on the board" % [p.viruses_left, counted])


# --- Mondrian -----------------------------------------------------------------

func _run_mondrian() -> void:
	var g: Mondrian = load("res://mondrian.tscn").instantiate()
	_drive(g)

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var claims := 0
	var deaths := 0
	var last_pct := g.claimed_percent

	for i in FRAMES:
		# Walk a random direction for a stretch, the way a player holds a key.
		var dir: Vector2i = dirs[randi() % dirs.size()]
		for _s in randi_range(1, 6):
			if g.state != Mondrian.PLAYING:
				break
			g._step_player(dir)
		if g.state == Mondrian.PLAYING:
			g._move_enemies(DT)

		_check_mondrian(g)

		if g.claimed_percent > last_pct:
			claims += 1
		last_pct = g.claimed_percent

		if g.state == Mondrian.DYING:
			deaths += 1
			g._respawn()
		elif g.state == Mondrian.WON:
			g.level += 1
			g._start_level()
			last_pct = g.claimed_percent
		elif g.state == Mondrian.LOST:
			g.new_game()
			last_pct = g.claimed_percent

	if claims == 0:
		_fail("mondrian: never claimed any area in %d frames" % FRAMES)
	g.queue_free()


func _check_mondrian(g: Mondrian) -> void:
	if g.claimed_percent < -0.01 or g.claimed_percent > 100.01:
		_fail("mondrian: percentage out of range (%f)" % g.claimed_percent)
		return
	if g.lives < 0:
		_fail("mondrian: lives went negative (%d)" % g.lives)
		return
	if not g._in_bounds(g.player):
		_fail("mondrian: player left the board at %d,%d" % [g.player.x, g.player.y])
		return
	# The player may only stand on solid ground or their own fresh trail.
	# During the death pause the trail has been erased under their feet, which
	# is expected, so this only applies to active play.
	if g.state == Mondrian.PLAYING:
		var under: int = g.grid[g.player.y][g.player.x]
		if under == Mondrian.EMPTY:
			_fail("mondrian: player standing on unclaimed space at %d,%d" % [g.player.x, g.player.y])
			return
	# Trail bookkeeping must match the board.
	for c in g.trail:
		if g.grid[c.y][c.x] != Mondrian.TRAIL:
			_fail("mondrian: trail list disagrees with the board at %d,%d" % [c.x, c.y])
			return
	if not g.drawing and not g.trail.is_empty():
		_fail("mondrian: trail left behind after sealing")
	for e in g.enemies:
		var p: Vector2 = e.pos
		if p.x < 0 or p.x >= Mondrian.COLS or p.y < 0 or p.y >= Mondrian.ROWS:
			_fail("mondrian: drifter escaped the board at %f,%f" % [p.x, p.y])
			return


func _test_mondrian_seals_pocket() -> void:
	# Wall off a small pocket with no drifter in it - it should all become ours.
	var g: Mondrian = load("res://mondrian.tscn").instantiate()
	_drive(g)

	# Park the single drifter far from the pocket we're about to seal.
	g.enemies = [{"pos": Vector2(Mondrian.COLS * 0.5, Mondrian.ROWS * 0.5), "vel": Vector2(0, 0)}]

	# Cut straight down column 2 from the top border to the bottom border,
	# which seals the strip between the left wall and the cut.
	g.player = Vector2i(4, 1)
	g.drawing = false
	g.trail.clear()
	var before := g.claimed_percent
	for _i in Mondrian.ROWS:
		g._step_player(Vector2i(0, 1))

	if g.drawing:
		_fail("mondrian/seal: trail never closed against the far wall")
	if g.claimed_percent <= before:
		_fail("mondrian/seal: sealing a pocket claimed nothing (%f -> %f)" % [before, g.claimed_percent])
	# The strip left of the cut must now be solid.
	for r in range(3, Mondrian.ROWS - 3):
		if g.grid[r][3] != Mondrian.FILLED:
			_fail("mondrian/seal: pocket cell at 3,%d was left unclaimed" % r)
			break
	g.queue_free()


# --- Snake --------------------------------------------------------------------

func _run_snake() -> void:
	var g: Snake = load("res://snake.tscn").instantiate()
	_drive(g)

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var deaths := 0
	var max_len := 0

	for i in FRAMES:
		if randi() % 5 == 0:
			g._turn(dirs[randi() % dirs.size()])
		g._process(DT)
		_check_snake(g)
		max_len = max(max_len, g.body.size())
		if g.dead:
			deaths += 1
			g.new_game()

	if deaths == 0:
		_fail("snake: never died in %d frames, the test is not driving it" % FRAMES)
	g.queue_free()


func _check_snake(g: Snake) -> void:
	if g.body.is_empty():
		_fail("snake: body vanished")
		return
	var seen := {}
	for cell in g.body:
		if cell.x < 0 or cell.x >= Snake.COLS or cell.y < 0 or cell.y >= Snake.ROWS:
			if not g.dead:
				_fail("snake: body left the board at %d,%d" % [cell.x, cell.y])
			return
		if seen.has(cell) and not g.dead:
			_fail("snake: body overlaps itself at %d,%d" % [cell.x, cell.y])
			return
		seen[cell] = true
	if not g.dead and g.body.has(g.food):
		_fail("snake: food spawned inside the snake at %d,%d" % [g.food.x, g.food.y])


func _test_snake_growth() -> void:
	# Eating adds exactly one segment; an ordinary step adds none.
	var g: Snake = load("res://snake.tscn").instantiate()
	_drive(g)

	g.body = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	g.dir = Vector2i(1, 0)
	g.queued.clear()
	g.grow_by = 0
	g.food = Vector2i(6, 5)
	var before := g.body.size()

	g._step()
	if g.body.size() != before + 1:
		_fail("snake/growth: eating did not grow the snake (%d -> %d)" % [before, g.body.size()])
	if g.score != 10:
		_fail("snake/growth: eating scored %d, expected 10" % g.score)

	var after_eat := g.body.size()
	g.food = Vector2i(20, 20)
	g._step()
	if g.body.size() != after_eat:
		_fail("snake/growth: plain step changed length (%d -> %d)" % [after_eat, g.body.size()])

	# Walking into a wall ends the run.
	g.body = [Vector2i(Snake.COLS - 1, 5)]
	g.dir = Vector2i(1, 0)
	g.queued.clear()
	g._step()
	if not g.dead:
		_fail("snake/growth: walking into the wall did not end the game")
	g.queue_free()


# --- Doubles ------------------------------------------------------------------

func _run_doubles() -> void:
	var g: Doubles = load("res://doubles.tscn").instantiate()
	_drive(g)

	var dirs := [Doubles.LEFT, Doubles.RIGHT, Doubles.UP, Doubles.DOWN]
	var games := 0

	for i in FRAMES:
		g._move(dirs[randi() % dirs.size()])
		_check_doubles(g)
		if g.dead:
			games += 1
			g.new_game()

	if games == 0:
		_fail("doubles: never filled the board in %d moves" % FRAMES)
	g.queue_free()


func _check_doubles(g: Doubles) -> void:
	if g.score < 0:
		_fail("doubles: negative score (%d)" % g.score)
		return
	for r in Doubles.SIZE:
		for c in Doubles.SIZE:
			var v: int = g.grid[r][c]
			if v == 0:
				continue
			# Every tile must be a power of two, at least 2.
			if v < 2 or (v & (v - 1)) != 0:
				_fail("doubles: tile %d at %d,%d is not a power of two" % [v, c, r])
				return


func _rows(g: Doubles) -> Array:
	var out := []
	for r in Doubles.SIZE:
		out.append(g.grid[r].duplicate())
	return out


func _set_board(g: Doubles, rows: Array) -> void:
	for r in Doubles.SIZE:
		for c in Doubles.SIZE:
			g.grid[r][c] = rows[r][c]


func _expect_board(g: Doubles, dir: Vector2i, before: Array, after: Array, name: String) -> void:
	_set_board(g, before)
	g.score = 0
	var moved := g._slide(dir)
	var got := _rows(g)
	if got != after:
		_fail("doubles/%s: got %s, expected %s" % [name, str(got), str(after)])
	if not moved and before != after:
		_fail("doubles/%s: reported no movement but the board changed" % name)


func _test_doubles_merges() -> void:
	var g: Doubles = load("res://doubles.tscn").instantiate()
	_drive(g)
	var z := [0, 0, 0, 0]

	# Pairs fuse, and each tile only fuses once per move.
	_expect_board(g, Doubles.LEFT,
		[[2, 2, 4, 4], z, z, z],
		[[4, 8, 0, 0], z, z, z], "left-pairs")

	# Four of a kind makes two tiles, not one.
	_expect_board(g, Doubles.LEFT,
		[[4, 4, 4, 4], z, z, z],
		[[8, 8, 0, 0], z, z, z], "left-quad")

	# Three of a kind fuses the leading pair only.
	_expect_board(g, Doubles.LEFT,
		[[2, 2, 2, 0], z, z, z],
		[[4, 2, 0, 0], z, z, z], "left-triple")

	# Sliding right resolves from the right-hand edge instead.
	_expect_board(g, Doubles.RIGHT,
		[[2, 2, 2, 0], z, z, z],
		[[0, 0, 2, 4], z, z, z], "right-triple")

	# Gaps close up even with nothing to merge.
	_expect_board(g, Doubles.LEFT,
		[[0, 2, 0, 4], z, z, z],
		[[2, 4, 0, 0], z, z, z], "left-compact")

	# Columns work the same way.
	_expect_board(g, Doubles.UP,
		[[2, 0, 0, 0], [2, 0, 0, 0], [4, 0, 0, 0], [4, 0, 0, 0]],
		[[4, 0, 0, 0], [8, 0, 0, 0], z, z], "up-pairs")

	_expect_board(g, Doubles.DOWN,
		[[2, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
		[z, z, z, [4, 0, 0, 0]], "down-pairs")

	# A move that shifts nothing must report no movement (so no tile spawns).
	_set_board(g, [[2, 4, 8, 16], z, z, z])
	if g._slide(Doubles.LEFT):
		_fail("doubles/no-op: a settled row reported movement")

	# Scoring is the sum of what was created.
	_set_board(g, [[2, 2, 4, 4], z, z, z])
	g.score = 0
	g._slide(Doubles.LEFT)
	if g.score != 12:
		_fail("doubles/score: merging 2+2 and 4+4 scored %d, expected 12" % g.score)

	# A full board with no equal neighbours is game over.
	_set_board(g, [[2, 4, 8, 16], [4, 2, 16, 8], [2, 4, 8, 16], [4, 2, 16, 8]])
	if g._has_moves():
		_fail("doubles/dead: a locked board still reported moves available")
	_set_board(g, [[2, 2, 8, 16], [4, 2, 16, 8], [2, 4, 8, 16], [4, 2, 16, 8]])
	if not g._has_moves():
		_fail("doubles/dead: a board with an adjacent pair reported no moves")
	g.queue_free()


# --- Linkup -------------------------------------------------------------------

func _test_linkup_generator() -> void:
	# Every generated board has to be finishable, which means its reference
	# solution must cover each cell exactly once with no gaps or overlaps.
	var g: Linkup = load("res://linkup.tscn").instantiate()
	_drive(g)

	for lvl in range(1, 13):
		g.difficulty = ["easy", "normal", "hard"][lvl % 3]
		g.level = lvl
		g._start_level()

		var seen := {}
		var total := 0
		for p in g.pairs:
			var run: Array = p.solution
			if run.size() < 2:
				_fail("linkup/gen: level %d produced a pair with a %d cell route" % [lvl, run.size()])
				break
			if run[0] == run[run.size() - 1]:
				_fail("linkup/gen: level %d has a pair whose dots are the same cell" % lvl)
				break
			for cell in run:
				if seen.has(cell):
					_fail("linkup/gen: level %d reuses cell %d,%d across routes" % [lvl, cell.x, cell.y])
					return
				seen[cell] = true
				total += 1
			# Routes must be walkable: consecutive cells adjacent.
			for i in range(run.size() - 1):
				if (run[i] - run[i + 1]).length() != 1:
					_fail("linkup/gen: level %d route jumps from %d,%d to %d,%d"
						% [lvl, run[i].x, run[i].y, run[i + 1].x, run[i + 1].y])
					return

		if total != g.size * g.size:
			_fail("linkup/gen: level %d covers %d of %d cells" % [lvl, total, g.size * g.size])
		if g.pairs.size() < 3:
			_fail("linkup/gen: level %d only made %d pairs" % [lvl, g.pairs.size()])
	g.queue_free()


func _test_linkup_solving() -> void:
	# Replaying the reference solution through the real input path must solve it.
	var g: Linkup = load("res://linkup.tscn").instantiate()
	_drive(g)

	for lvl in [1, 4, 7, 10]:
		g.difficulty = ["easy", "normal", "hard"][lvl % 3]
		g.level = lvl
		g._start_level()

		for i in g.pairs.size():
			var run: Array = g.pairs[i].solution
			if not g.grab(run[0]):
				_fail("linkup/solve: level %d could not grab the dot for pair %d" % [lvl, i])
				break
			for j in range(1, run.size()):
				if not g.extend(run[j]):
					_fail("linkup/solve: level %d could not extend pair %d to step %d" % [lvl, i, j])
					break
			g.release()

		if g.connected_count() != g.pairs.size():
			_fail("linkup/solve: level %d joined %d of %d pairs"
				% [lvl, g.connected_count(), g.pairs.size()])
		if g.filled_cells() != g.size * g.size:
			_fail("linkup/solve: level %d filled %d of %d cells"
				% [lvl, g.filled_cells(), g.size * g.size])
		if not g.solved:
			_fail("linkup/solve: level %d was not reported solved" % lvl)
	g.queue_free()


func _test_linkup_editing() -> void:
	var g: Linkup = load("res://linkup.tscn").instantiate()
	_drive(g)
	g.level = 1
	g._start_level()

	# Lay pair 0 down completely, then drive pair 1 across it: the first route
	# must lose its tail rather than both owning the same cell.
	var run0: Array = g.pairs[0].solution
	g.grab(run0[0])
	for j in range(1, run0.size()):
		g.extend(run0[j])
	g.release()
	var full: int = g.paths[0].size()

	var crossed := false
	for i in range(1, g.pairs.size()):
		var run: Array = g.pairs[i].solution
		g.grab(run[0])
		# Look for a step that would land on pair 0's route.
		for j in range(1, run.size()):
			g.extend(run[j])
		for n in g._neighbours(g.paths[i][g.paths[i].size() - 1]):
			if g.owner_of[n.y][n.x] == 0 and g.endpoint_of[n.y][n.x] == -1:
				if g.extend(n):
					crossed = true
					if g.owner_of[n.y][n.x] != i:
						_fail("linkup/edit: crossing did not take the cell over")
					if g.paths[0].size() >= full:
						_fail("linkup/edit: the crossed route kept its full length")
				break
		g.release()
		if crossed:
			break

	# Backing up over your own route rubs it out. Start from a fresh board -
	# the crossing section above lays every route down, which solves it.
	g._start_level()
	var run1: Array = g.pairs[0].solution
	g.grab(run1[0])
	g.extend(run1[1])
	g.extend(run1[2])
	var before: int = g.paths[0].size()
	g.extend(run1[1])          # step back
	if g.paths[0].size() != before - 1:
		_fail("linkup/edit: stepping back did not shorten the route (%d -> %d)"
			% [before, g.paths[0].size()])

	# A dot belonging to another colour is a wall.
	g._start_level()
	g.grab(g.pairs[0].solution[0])
	for n in g._neighbours(g.pairs[0].solution[0]):
		var ep: int = g.endpoint_of[n.y][n.x]
		if ep != -1 and ep != 0:
			if g.extend(n):
				_fail("linkup/edit: drew straight through another colour's dot")
			break
	g.queue_free()


# --- Gridlock -----------------------------------------------------------------

func _test_gridlock_generator() -> void:
	var g: Gridlock = load("res://gridlock.tscn").instantiate()
	_drive(g)

	for lvl in range(1, 11):
		g.level = lvl
		g._start_level()

		if g.is_solved():
			_fail("gridlock/gen: level %d was handed out already finished" % lvl)
		var t: Dictionary = g.vehicles[0]
		if not t.horiz or t.len != 2 or t.pos.y != Gridlock.EXIT_ROW:
			_fail("gridlock/gen: level %d red car is not a 2-long car on the exit row" % lvl)

		var seen := {}
		for v in g.vehicles:
			for c in g.cells_of(v):
				if c.x < 0 or c.x >= Gridlock.SIZE or c.y < 0 or c.y >= Gridlock.SIZE:
					_fail("gridlock/gen: level %d has a vehicle off the board at %d,%d" % [lvl, c.x, c.y])
					return
				if seen.has(c):
					_fail("gridlock/gen: level %d overlaps two vehicles at %d,%d" % [lvl, c.x, c.y])
					return
				seen[c] = true
	g.queue_free()


func _test_gridlock_solvable() -> void:
	# The board was scrambled from the finished position with reversible moves,
	# so undoing that scramble backwards has to park the red car at the exit.
	var g: Gridlock = load("res://gridlock.tscn").instantiate()
	_drive(g)

	for lvl in [1, 3, 6, 9]:
		g.level = lvl
		g._start_level()
		var steps: Array = g.scramble.duplicate()
		steps.reverse()
		for step in steps:
			if not g.move_vehicle(step.v, -step.d):
				_fail("gridlock/solve: level %d could not undo a scramble move" % lvl)
				break
		if not g.is_solved():
			_fail("gridlock/solve: level %d did not end with the red car at the exit" % lvl)
		if not g.solved:
			_fail("gridlock/solve: level %d never reported itself solved" % lvl)
	g.queue_free()


func _test_gridlock_moves() -> void:
	var g: Gridlock = load("res://gridlock.tscn").instantiate()
	_drive(g)
	g.level = 1
	g._start_level()

	# A vehicle may never move across its own grain.
	for i in g.vehicles.size():
		var v: Dictionary = g.vehicles[i]
		var before: Vector2i = v.pos
		if v.horiz:
			# Nudging a horizontal car vertically is not even expressible
			# through move_vehicle, so check the axis is respected by _drive.
			g.selected = i
			g._drive(Vector2i(0, 1))
			if g.vehicles[i].pos != before and g.vehicles[i].pos.x == before.x:
				_fail("gridlock/moves: a horizontal vehicle moved vertically")
				break

	# Nothing may be pushed off the board or through another vehicle.
	for i in g.vehicles.size():
		for dir in [-1, 1]:
			var occ: Dictionary = g.occupancy(i)
			var v: Dictionary = g.vehicles[i]
			var delta := Vector2i(dir, 0) if v.horiz else Vector2i(0, dir)
			var blocked := false
			for c in g.cells_of(v):
				var n: Vector2i = c + delta
				if n.x < 0 or n.x >= Gridlock.SIZE or n.y < 0 or n.y >= Gridlock.SIZE or occ.has(n):
					blocked = true
			if blocked and g.can_move(i, dir):
				_fail("gridlock/moves: vehicle %d claims it can move into something" % i)
				return
			if not blocked and not g.can_move(i, dir):
				_fail("gridlock/moves: vehicle %d refuses a clear move" % i)
				return
	g.queue_free()


# --- Shapes -------------------------------------------------------------------

func _test_shapes_generator() -> void:
	var g: Shapes = load("res://shapes.tscn").instantiate()
	_drive(g)

	for lvl in range(1, 11):
		g.level = lvl
		g._start_level()

		# The reference tiling must cover every cell exactly once.
		var seen := {}
		for piece in g.solution:
			var r: Rect2i = piece.rect
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var cell := Vector2i(x, y)
					if seen.has(cell):
						_fail("shapes/gen: level %d tiles %d,%d twice" % [lvl, x, y])
						return
					seen[cell] = true
		if seen.size() != g.size * g.size:
			_fail("shapes/gen: level %d covers %d of %d cells" % [lvl, seen.size(), g.size * g.size])

		# No piece may be a single square - those solve themselves.
		for piece in g.solution:
			var pr: Rect2i = piece.rect
			if pr.size.x * pr.size.y < Shapes.MIN_AREA:
				_fail("shapes/gen: level %d produced a %dx%d piece"
					% [lvl, pr.size.x, pr.size.y])
				return

		# Each piece holds exactly one clue, and that clue describes it.
		for piece in g.solution:
			var inside: Array = g.clues_inside(piece.rect)
			if inside.size() != 1:
				_fail("shapes/gen: level %d has a piece holding %d clues" % [lvl, inside.size()])
				return
			var clue: Dictionary = g.clues[inside[0]]
			if clue.kind != Shapes.ANY and clue.kind != g.kind_of(piece.rect):
				_fail("shapes/gen: level %d clue disagrees with its own piece" % lvl)
				return
			if clue.area > 0 and clue.area != piece.rect.size.x * piece.rect.size.y:
				_fail("shapes/gen: level %d clue number disagrees with its own piece" % lvl)
				return
			if clue.kind == Shapes.ANY and clue.area == 0:
				_fail("shapes/gen: level %d has a clue that constrains nothing" % lvl)
				return
	g.queue_free()


func _test_shapes_solving() -> void:
	# Laying the reference tiling back down through the real API must solve it.
	var g: Shapes = load("res://shapes.tscn").instantiate()
	_drive(g)

	for lvl in [1, 4, 7, 10]:
		g.level = lvl
		g._start_level()
		for piece in g.solution:
			if not g.place(piece.rect):
				_fail("shapes/solve: level %d rejected its own solution (%s)" % [lvl, g.message])
				break
		if g.filled_cells() != g.size * g.size:
			_fail("shapes/solve: level %d filled %d of %d" % [lvl, g.filled_cells(), g.size * g.size])
		if not g.solved:
			_fail("shapes/solve: level %d was not reported solved" % lvl)
	g.queue_free()


func _test_shapes_rules() -> void:
	var g: Shapes = load("res://shapes.tscn").instantiate()
	_drive(g)
	g.level = 1
	g._start_level()

	# Off the board.
	if g.check(Rect2i(Vector2i(-1, 0), Vector2i(2, 2))) == "":
		_fail("shapes/rules: accepted a rectangle hanging off the board")
	# A rectangle with no clue in it.
	var empty_found := false
	for y in g.size:
		for x in g.size:
			if g.clue_at(Vector2i(x, y)) == -1 and not empty_found:
				if g.check(Rect2i(Vector2i(x, y), Vector2i(1, 1))) == "":
					_fail("shapes/rules: accepted a 1x1 with no clue in it")
				empty_found = true
	# Two clues in one rectangle, when the board has two on a shared line.
	for a in g.clues.size():
		for b in range(a + 1, g.clues.size()):
			var ca: Vector2i = g.clues[a].cell
			var cb: Vector2i = g.clues[b].cell
			var r := g.rect_between(ca, cb)
			if g.clues_inside(r).size() >= 2:
				if g.check(r) == "":
					_fail("shapes/rules: accepted a rectangle holding two clues")
				break

	# Overlap is refused once something is placed.
	g.place(g.solution[0].rect)
	if g.check(g.solution[0].rect) == "":
		_fail("shapes/rules: accepted a rectangle overlapping a placed one")
	# And taking it back frees the squares again.
	g.remove_at(g.solution[0].rect.position)
	if g.check(g.solution[0].rect) != "":
		_fail("shapes/rules: removing a shape did not free its squares")
	g.queue_free()
