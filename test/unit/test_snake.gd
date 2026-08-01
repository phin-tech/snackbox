extends ScoreSandbox

var game: Snake


func before_each() -> void:
	use_sandbox()
	game = load("res://snake.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)


func after_all() -> void:
	release_sandbox()


func test_eating_grows_it_by_one() -> void:
	game.body = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)] as Array[Vector2i]
	game.dir = Vector2i(1, 0)
	game.grow_by = 0
	game.food = Vector2i(6, 5)
	game._step()
	assert_eq(game.body.size(), 4, "eating should add a segment")
	assert_eq(game.score, 10, "and score")


func test_an_ordinary_step_keeps_it_the_same_length() -> void:
	game.body = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)] as Array[Vector2i]
	game.dir = Vector2i(1, 0)
	game.grow_by = 0
	game.food = Vector2i(20, 20)
	game._step()
	assert_eq(game.body.size(), 3)


func test_the_wall_ends_it() -> void:
	game.body = [Vector2i(Snake.COLS - 1, 5)] as Array[Vector2i]
	game.dir = Vector2i(1, 0)
	game.queued.clear()
	game._step()
	assert_true(game.dead, "walking into the wall should end the run")


func test_it_cannot_turn_back_on_itself() -> void:
	game.dir = Vector2i(1, 0)
	game.queued.clear()
	game._turn(Vector2i(-1, 0))
	assert_eq(game.queued.size(), 0, "a full reverse would eat its own neck")


func test_food_never_lands_on_the_snake() -> void:
	for _i in 40:
		game._place_food()
		assert_false(game.body.has(game.food), "food should not appear inside the snake")
