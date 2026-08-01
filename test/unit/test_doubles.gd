extends ScoreSandbox

# The merge rules, checked against boards countable by eye.

var game: Doubles
var zero := [0, 0, 0, 0]


func before_each() -> void:
	use_sandbox()
	game = load("res://doubles.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)


func after_all() -> void:
	release_sandbox()


func set_board(rows: Array) -> void:
	for r in Doubles.SIZE:
		for c in Doubles.SIZE:
			game.grid[r][c] = rows[r][c]


func board() -> Array:
	var out := []
	for r in Doubles.SIZE:
		out.append(game.grid[r].duplicate())
	return out


func slide_to(dir: Vector2i, before: Array) -> Array:
	set_board(before)
	game.score = 0
	game._slide(dir)
	return board()


func test_pairs_fuse() -> void:
	assert_eq(slide_to(Doubles.LEFT, [[2, 2, 4, 4], zero, zero, zero]),
		[[4, 8, 0, 0], zero, zero, zero])


func test_four_of_a_kind_makes_two_tiles() -> void:
	assert_eq(slide_to(Doubles.LEFT, [[4, 4, 4, 4], zero, zero, zero]),
		[[8, 8, 0, 0], zero, zero, zero], "not one tile of sixteen")


func test_three_of_a_kind_fuses_the_leading_pair() -> void:
	assert_eq(slide_to(Doubles.LEFT, [[2, 2, 2, 0], zero, zero, zero]),
		[[4, 2, 0, 0], zero, zero, zero])


func test_sliding_right_resolves_from_the_right() -> void:
	assert_eq(slide_to(Doubles.RIGHT, [[2, 2, 2, 0], zero, zero, zero]),
		[[0, 0, 2, 4], zero, zero, zero])


func test_gaps_close_without_merging() -> void:
	assert_eq(slide_to(Doubles.LEFT, [[0, 2, 0, 4], zero, zero, zero]),
		[[2, 4, 0, 0], zero, zero, zero])


func test_columns_work_the_same_way() -> void:
	assert_eq(slide_to(Doubles.UP, [[2, 0, 0, 0], [2, 0, 0, 0], [4, 0, 0, 0], [4, 0, 0, 0]]),
		[[4, 0, 0, 0], [8, 0, 0, 0], zero, zero])
	assert_eq(slide_to(Doubles.DOWN, [[2, 0, 0, 0], [2, 0, 0, 0], zero, zero]),
		[zero, zero, zero, [4, 0, 0, 0]])


func test_a_settled_row_reports_no_movement() -> void:
	set_board([[2, 4, 8, 16], zero, zero, zero])
	assert_false(game._slide(Doubles.LEFT), "nothing moved, so no tile should spawn")


func test_scoring_is_what_was_created() -> void:
	set_board([[2, 2, 4, 4], zero, zero, zero])
	game.score = 0
	game._slide(Doubles.LEFT)
	assert_eq(game.score, 12, "4 and 8")


func test_a_locked_board_is_over() -> void:
	set_board([[2, 4, 8, 16], [4, 2, 16, 8], [2, 4, 8, 16], [4, 2, 16, 8]])
	assert_false(game._has_moves())


func test_an_adjacent_pair_means_moves_remain() -> void:
	set_board([[2, 2, 8, 16], [4, 2, 16, 8], [2, 4, 8, 16], [4, 2, 16, 8]])
	assert_true(game._has_moves())
