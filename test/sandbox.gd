class_name ScoreSandbox
extends GutTest

# Base class for tests that touch a game. Several of them read and write the
# score file the moment a game starts or ends, so without this every run would
# read - and overwrite - the player's real bests and tables.

const SANDBOX_PATH := "user://gut_sandbox.cfg"


func use_sandbox() -> void:
	Scores.path = SANDBOX_PATH
	Scores.reload()
	Scores.clear()


func release_sandbox() -> void:
	Scores.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SANDBOX_PATH))
	Scores.path = Scores.DEFAULT_PATH
	Scores.reload()
