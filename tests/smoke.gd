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

	for mode in ["marathon", "sprint", "ultra"]:
		_run_blocks(mode)
	_run_pills()
	_test_pills_horizontal_clear()
	_test_pills_vertical_clear()
	_test_pills_chain()
	_run_landgrab()
	_test_landgrab_seals_pocket()

	if failures.is_empty():
		print("OK: all smoke tests passed")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("FAILED: %d check(s)" % failures.size())
		get_tree().quit(1)


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
