extends SceneTree
## Writes the initial standard 8x8 ledger to res://data/ledger.json.
## Run: godot --headless --path <project> --script res://tools/scr_make_initial_ledger.gd

func _init() -> void:
	var ledger: Dictionary = KgLedger.new_standard_ledger(20261011)
	var err: Error = KgLedger.save_ledger(ledger, KgLedger.DEFAULT_LEDGER_PATH)
	print("save_ledger -> ", error_string(err), " pieces=", ledger["pieces"].size(),
		" path=", ProjectSettings.globalize_path(KgLedger.DEFAULT_LEDGER_PATH))
	quit(0 if err == OK else 1)
