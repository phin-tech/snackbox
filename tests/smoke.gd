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
	_run_landgrab()
	_test_landgrab_seals_pocket()
	_run_snake()
	_test_snake_growth()
	_run_doubles()
	_test_doubles_merges()
	_run_puck()
	_test_puck_goals()

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


# --- Landgrab -----------------------------------------------------------------

func _run_landgrab() -> void:
	var g: Landgrab = load("res://landgrab.tscn").instantiate()
	_drive(g)

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var claims := 0
	var deaths := 0
	var last_pct := g.claimed_percent

	for i in FRAMES:
		# Walk a random direction for a stretch, the way a player holds a key.
		var dir: Vector2i = dirs[randi() % dirs.size()]
		for _s in randi_range(1, 6):
			if g.state != Landgrab.PLAYING:
				break
			g._step_player(dir)
		if g.state == Landgrab.PLAYING:
			g._move_enemies(DT)

		_check_landgrab(g)

		if g.claimed_percent > last_pct:
			claims += 1
		last_pct = g.claimed_percent

		if g.state == Landgrab.DYING:
			deaths += 1
			g._respawn()
		elif g.state == Landgrab.WON:
			g.level += 1
			g._start_level()
			last_pct = g.claimed_percent
		elif g.state == Landgrab.LOST:
			g.new_game()
			last_pct = g.claimed_percent

	if claims == 0:
		_fail("landgrab: never claimed any area in %d frames" % FRAMES)
	g.queue_free()


func _check_landgrab(g: Landgrab) -> void:
	if g.claimed_percent < -0.01 or g.claimed_percent > 100.01:
		_fail("landgrab: percentage out of range (%f)" % g.claimed_percent)
		return
	if g.lives < 0:
		_fail("landgrab: lives went negative (%d)" % g.lives)
		return
	if not g._in_bounds(g.player):
		_fail("landgrab: player left the board at %d,%d" % [g.player.x, g.player.y])
		return
	# The player may only stand on solid ground or their own fresh trail.
	# During the death pause the trail has been erased under their feet, which
	# is expected, so this only applies to active play.
	if g.state == Landgrab.PLAYING:
		var under: int = g.grid[g.player.y][g.player.x]
		if under == Landgrab.EMPTY:
			_fail("landgrab: player standing on unclaimed space at %d,%d" % [g.player.x, g.player.y])
			return
	# Trail bookkeeping must match the board.
	for c in g.trail:
		if g.grid[c.y][c.x] != Landgrab.TRAIL:
			_fail("landgrab: trail list disagrees with the board at %d,%d" % [c.x, c.y])
			return
	if not g.drawing and not g.trail.is_empty():
		_fail("landgrab: trail left behind after sealing")
	for e in g.enemies:
		var p: Vector2 = e.pos
		if p.x < 0 or p.x >= Landgrab.COLS or p.y < 0 or p.y >= Landgrab.ROWS:
			_fail("landgrab: drifter escaped the board at %f,%f" % [p.x, p.y])
			return


func _test_landgrab_seals_pocket() -> void:
	# Wall off a small pocket with no drifter in it - it should all become ours.
	var g: Landgrab = load("res://landgrab.tscn").instantiate()
	_drive(g)

	# Park the single drifter far from the pocket we're about to seal.
	g.enemies = [{"pos": Vector2(Landgrab.COLS * 0.5, Landgrab.ROWS * 0.5), "vel": Vector2(0, 0)}]

	# Cut straight down column 2 from the top border to the bottom border,
	# which seals the strip between the left wall and the cut.
	g.player = Vector2i(4, 1)
	g.drawing = false
	g.trail.clear()
	var before := g.claimed_percent
	for _i in Landgrab.ROWS:
		g._step_player(Vector2i(0, 1))

	if g.drawing:
		_fail("landgrab/seal: trail never closed against the far wall")
	if g.claimed_percent <= before:
		_fail("landgrab/seal: sealing a pocket claimed nothing (%f -> %f)" % [before, g.claimed_percent])
	# The strip left of the cut must now be solid.
	for r in range(3, Landgrab.ROWS - 3):
		if g.grid[r][3] != Landgrab.FILLED:
			_fail("landgrab/seal: pocket cell at 3,%d was left unclaimed" % r)
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


# --- Puck ---------------------------------------------------------------------

func _run_puck() -> void:
	var g: Puck = load("res://puck.tscn").instantiate()
	_drive(g)

	var goals := 0
	var matches := 0
	var last_total := 0

	for i in FRAMES:
		# Wander the mallet around the player half the way a hand would.
		if i % 20 == 0:
			g.key_dir = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)][randi() % 4]
		g._process(DT)
		_check_puck(g)

		var total: int = g.you + g.them
		if total > last_total:
			goals += 1
		last_total = total

		if g.state == Puck.WON or g.state == Puck.LOST:
			matches += 1
			g.opponent = (g.opponent + 1) % Puck.OPPONENTS.size()
			g._start_match()
			last_total = 0

	if goals < 10:
		_fail("puck: only %d goals in %d frames, the table is not being played" % [goals, FRAMES])
	if matches == 0:
		_fail("puck: no match ever reached %d goals" % Puck.GOALS_TO_WIN)
	g.queue_free()


func _check_puck(g: Puck) -> void:
	# The puck must stay on the table, allowing a little slack for the
	# substep that detects a goal before the reset.
	var t := Puck.TABLE
	if g.puck_pos.x < t.position.x - 40 or g.puck_pos.x > t.end.x + 40:
		_fail("puck: puck left the table sideways at %f" % g.puck_pos.x)
		return
	if g.puck_pos.y < t.position.y - 40 or g.puck_pos.y > t.end.y + 40:
		_fail("puck: puck left the table endways at %f" % g.puck_pos.y)
		return
	if g.puck_vel.length() > Puck.MAX_SPEED + 1.0:
		_fail("puck: puck exceeded the speed limit (%f)" % g.puck_vel.length())
		return

	# Neither mallet may cross the centre line or leave the table.
	var mid: float = t.position.y + t.size.y * 0.5
	if g.player.y < mid + Puck.MALLET_R - 0.5:
		_fail("puck: player mallet crossed the centre line (y=%f)" % g.player.y)
	if g.ai.y > mid - Puck.MALLET_R + 0.5:
		_fail("puck: opponent mallet crossed the centre line (y=%f)" % g.ai.y)
	if g.player.x < t.position.x - 0.5 or g.player.x > t.end.x + 0.5:
		_fail("puck: player mallet left the table (x=%f)" % g.player.x)


func _test_puck_goals() -> void:
	var g: Puck = load("res://puck.tscn").instantiate()
	_drive(g)
	g._start_match()
	g.state = Puck.PLAYING

	# Drive the puck into the opponent's wall: that is a point for the player.
	g.puck_pos = Vector2(Puck.TABLE.position.x + 200, Puck.TABLE.position.y + 30)
	g.puck_vel = Vector2(0, -400)
	g.ai = Vector2(Puck.TABLE.end.x - 40, Puck.TABLE.position.y + 40)   # out of the way
	var before := g.you
	for _i in 40:
		g._step_physics(DT)
		if g.you != before:
			break
	if g.you != before + 1:
		_fail("puck/goal: reaching the far wall did not score for the player")
	if g.puck_pos != Puck.TABLE.position + Puck.TABLE.size * 0.5:
		_fail("puck/goal: the puck was not re-served from the centre")

	# And into the player's wall for the opponent.
	g.state = Puck.PLAYING
	g.puck_pos = Vector2(Puck.TABLE.position.x + 200, Puck.TABLE.end.y - 30)
	g.puck_vel = Vector2(0, 400)
	g.player = Vector2(Puck.TABLE.position.x + 40, Puck.TABLE.end.y - 40)
	var before_them := g.them
	for _i in 40:
		g._step_physics(DT)
		if g.them != before_them:
			break
	if g.them != before_them + 1:
		_fail("puck/goal: reaching the near wall did not score for the opponent")

	# A side wall reflects rather than scoring.
	g.state = Puck.PLAYING
	g.puck_pos = Vector2(Puck.TABLE.position.x + Puck.PUCK_R + 2, Puck.TABLE.position.y + 260)
	g.puck_vel = Vector2(-300, 0)
	g._step_physics(DT)
	if g.puck_vel.x <= 0.0:
		_fail("puck/wall: the puck did not bounce off the left wall (vx=%f)" % g.puck_vel.x)

	# A mallet strike sends it back the other way.
	g.state = Puck.PLAYING
	g.player = Vector2(Puck.TABLE.position.x + 200, Puck.TABLE.end.y - 100)
	g.puck_pos = g.player + Vector2(0, -(Puck.MALLET_R + Puck.PUCK_R) + 4)
	g.puck_vel = Vector2(0, 260)      # heading into the mallet
	g._hit(g.player, Vector2.ZERO)
	if g.puck_vel.y >= 0.0:
		_fail("puck/hit: the mallet did not send the puck back up the table")
	g.queue_free()
