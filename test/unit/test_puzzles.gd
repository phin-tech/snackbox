extends ScoreSandbox

# Linkup, Shapes and Gridlock all promise a board that can actually be
# finished. These check that promise rather than the drawing.

var linkup: Linkup
var shapes: Shapes
var gridlock: Gridlock


func before_each() -> void:
	use_sandbox()


func after_all() -> void:
	release_sandbox()


func a_linkup(level: int) -> Linkup:
	linkup = load("res://linkup.tscn").instantiate()
	add_child_autofree(linkup)
	linkup.set_process(false)
	linkup.level = level
	linkup._start_level()
	return linkup


func a_shapes(level: int) -> Shapes:
	shapes = load("res://shapes.tscn").instantiate()
	add_child_autofree(shapes)
	shapes.set_process(false)
	shapes.level = level
	shapes._start_level()
	return shapes


func a_gridlock(level: int) -> Gridlock:
	gridlock = load("res://gridlock.tscn").instantiate()
	add_child_autofree(gridlock)
	gridlock.set_process(false)
	gridlock.level = level
	gridlock._start_level()
	return gridlock


# --- Linkup ---------------------------------------------------------------

func test_linkup_routes_cover_every_square_exactly_once() -> void:
	for level in [1, 5, 9]:
		var game := a_linkup(level)
		var seen := {}
		for pair in game.pairs:
			for cell in pair.solution:
				assert_false(seen.has(cell), "level %d reuses a cell" % level)
				seen[cell] = true
		assert_eq(seen.size(), game.size * game.size,
			"level %d should fill the board" % level)


func test_linkup_routes_are_walkable() -> void:
	var game := a_linkup(4)
	for pair in game.pairs:
		var run: Array = pair.solution
		for i in range(run.size() - 1):
			assert_eq(absi((run[i] - run[i + 1]).x) + absi((run[i] - run[i + 1]).y), 1,
				"a route should step one square at a time")


func test_linkup_can_be_solved_through_the_real_moves() -> void:
	var game := a_linkup(3)
	for i in game.pairs.size():
		var run: Array = game.pairs[i].solution
		game.grab(run[0])
		for j in range(1, run.size()):
			game.extend(run[j])
		game.release()
	assert_true(game.solved, "laying every route down should finish the board")


func test_linkup_difficulty_changes_the_board() -> void:
	var easy := a_linkup(1)
	easy.difficulty = "easy"
	easy._start_level()
	var easy_pairs := easy.pairs.size()
	var hard := a_linkup(1)
	hard.difficulty = "hard"
	hard._start_level()
	assert_gte(hard.pairs.size(), easy_pairs, "hard should not be simpler")


# --- Shapes ---------------------------------------------------------------

func test_shapes_tiles_the_board_exactly() -> void:
	for level in [1, 5, 9]:
		var game := a_shapes(level)
		var seen := {}
		for piece in game.solution:
			var rect: Rect2i = piece.rect
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					assert_false(seen.has(Vector2i(x, y)), "level %d tiles a cell twice" % level)
					seen[Vector2i(x, y)] = true
		assert_eq(seen.size(), game.size * game.size, "level %d should cover the board" % level)


func test_shapes_never_cuts_a_single_square() -> void:
	for level in [1, 4, 8]:
		var game := a_shapes(level)
		for piece in game.solution:
			var rect: Rect2i = piece.rect
			assert_gte(rect.size.x * rect.size.y, Shapes.MIN_AREA,
				"a one-cell piece solves itself")


func test_shapes_clues_describe_their_own_piece() -> void:
	var game := a_shapes(3)
	for piece in game.solution:
		var inside: Array = game.clues_inside(piece.rect)
		assert_eq(inside.size(), 1, "each piece should hold exactly one clue")
		var clue: Dictionary = game.clues[inside[0]]
		if clue.kind != Shapes.ANY:
			assert_eq(clue.kind, game.kind_of(piece.rect), "the clue should match its piece")
		if clue.area > 0:
			assert_eq(clue.area, piece.rect.size.x * piece.rect.size.y)


func test_shapes_accepts_its_own_solution() -> void:
	var game := a_shapes(2)
	for piece in game.solution:
		assert_true(game.place(piece.rect), "the board should accept the tiling it was built from")
	assert_true(game.solved)


func test_shapes_refuses_a_bad_rectangle() -> void:
	var game := a_shapes(1)
	assert_ne(game.check(Rect2i(Vector2i(-1, 0), Vector2i(2, 2))), "", "off the board")
	game.place(game.solution[0].rect)
	assert_ne(game.check(game.solution[0].rect), "", "overlapping a placed shape")


# --- Gridlock -------------------------------------------------------------

func test_gridlock_boards_are_never_already_finished() -> void:
	for level in [1, 4, 8]:
		var game := a_gridlock(level)
		assert_false(game.is_solved(), "level %d was handed out finished" % level)


func test_gridlock_vehicles_never_overlap() -> void:
	for level in [1, 5, 9]:
		var game := a_gridlock(level)
		var seen := {}
		for v in game.vehicles:
			for cell in game.cells_of(v):
				assert_false(seen.has(cell), "level %d overlaps two vehicles" % level)
				seen[cell] = true


func test_gridlock_boards_take_real_work() -> void:
	# The bug this guards: random scrambling used to leave the red car able to
	# drive straight out.
	for level in [1, 5, 9]:
		var game := a_gridlock(level)
		assert_gte(game.min_moves(200000), Gridlock.HARD_FLOOR,
			"level %d is solvable in fewer moves than the floor allows" % level)


func test_gridlock_solutions_actually_finish_the_board() -> void:
	var game := a_gridlock(3)
	var moves: Array = game.solve(200000)
	assert_gt(moves.size(), 0, "there should be a solution")
	for move in moves:
		game.move_vehicle(move.v, move.d)
	assert_true(game.is_solved(), "replaying the solver's own moves should free the car")
