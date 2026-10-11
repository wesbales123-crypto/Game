class_name KgLedger
extends RefCounted
## Central JSON variable ledger (doc section 4: "Every game state, board
## coordinate, and piece stat is logged in one central JSON ledger").
## The ledger is a plain Dictionary; these static helpers create, query,
## validate, load and save it. "action_log" is append-only: the only write
## path is append_action(), and validate() rejects non-sequential logs.
##
## Ledger shape (exact key names used by all code):
## {
##   "ledger_version": int,
##   "board": {"board_width": int, "board_height": int},
##   "piece_stats": {"<piece_type>": {"die_sides": int}},
##   "game_state": {"turn_number": int, "active_side": String,
##       "pending_bonus_piece_id": String, "next_piece_number": int,
##       "rng_seed": int, "rng_state": String},
##   "pieces": {"<piece_id>": {"piece_id", "piece_type", "side", "tile_x",
##       "tile_y", "has_moved": bool, "next_defense_modifier": int}},
##   "captured_pieces": [<piece dict + "captured_turn", "capture_cause">],
##   "action_log": [{"action_index": int, "turn_number": int,
##       "action_type": String, "details": Dictionary}]
##   ("move" and "attack" details carry "is_bonus_action": bool.)
## }

const LEDGER_VERSION: int = 1
const DEFAULT_LEDGER_PATH: String = "res://data/ledger.json"
const SIDE_PLAYER: String = "player"
const SIDE_RIVAL: String = "rival"
const DEFAULT_BOARD_SIZE: int = 8
const BACK_RANK: Array = ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]


## Empty board of the given size with doc piece stats and no pieces.
static func new_empty_ledger(width: int = DEFAULT_BOARD_SIZE, height: int = DEFAULT_BOARD_SIZE,
		rng_seed: int = 0) -> Dictionary:
	var stats: Dictionary = {}
	for piece_type in KgDice.DEFAULT_PIECE_DIE_SIDES.keys():
		stats[piece_type] = {"die_sides": int(KgDice.DEFAULT_PIECE_DIE_SIDES[piece_type])}
	return {
		"ledger_version": LEDGER_VERSION,
		"board": {"board_width": width, "board_height": height},
		"piece_stats": stats,
		"game_state": {
			"turn_number": 1,
			"active_side": SIDE_PLAYER,
			"pending_bonus_piece_id": "",
			"next_piece_number": 1,
			"rng_seed": rng_seed,
			"rng_state": "",
		},
		"pieces": {},
		"captured_pieces": [],
		"action_log": [],
	}


## 8x8 board with a chess-style starting layout. Rival on rows 0-1 (top),
## player on rows 6-7 (bottom). Logs a "setup" action.
static func new_standard_ledger(rng_seed: int = 0) -> Dictionary:
	var ledger: Dictionary = new_empty_ledger(DEFAULT_BOARD_SIZE, DEFAULT_BOARD_SIZE, rng_seed)
	for x in range(DEFAULT_BOARD_SIZE):
		add_piece(ledger, String(BACK_RANK[x]), SIDE_RIVAL, x, 0)
		add_piece(ledger, "pawn", SIDE_RIVAL, x, 1)
		add_piece(ledger, "pawn", SIDE_PLAYER, x, 6)
		add_piece(ledger, String(BACK_RANK[x]), SIDE_PLAYER, x, 7)
	append_action(ledger, "setup", {"layout": "standard_8x8", "piece_count": ledger["pieces"].size()})
	return ledger


## Adds a piece and returns its new piece_id ("" on failure).
static func add_piece(ledger: Dictionary, piece_type: String, side: String, x: int, y: int) -> String:
	if not ledger["piece_stats"].has(piece_type):
		push_error("KgLedger.add_piece: unknown piece_type %s" % piece_type)
		return ""
	if side != SIDE_PLAYER and side != SIDE_RIVAL:
		push_error("KgLedger.add_piece: unknown side %s" % side)
		return ""
	if not in_bounds(ledger, x, y) or piece_id_at(ledger, x, y) != "":
		push_error("KgLedger.add_piece: tile (%d,%d) out of bounds or occupied" % [x, y])
		return ""
	var gs: Dictionary = ledger["game_state"]
	var n: int = int(gs["next_piece_number"])
	gs["next_piece_number"] = n + 1
	var piece_id: String = "pc_%03d" % n
	ledger["pieces"][piece_id] = {
		"piece_id": piece_id,
		"piece_type": piece_type,
		"side": side,
		"tile_x": x,
		"tile_y": y,
		"has_moved": false,
		"next_defense_modifier": 0,
	}
	return piece_id


## Die size for a piece, read from the ledger's piece_stats.
static func die_sides_for(ledger: Dictionary, piece_id: String) -> int:
	var piece_type: String = ledger["pieces"][piece_id]["piece_type"]
	return int(ledger["piece_stats"][piece_type]["die_sides"])


## True if (x, y) is on the board.
static func in_bounds(ledger: Dictionary, x: int, y: int) -> bool:
	var b: Dictionary = ledger["board"]
	return x >= 0 and y >= 0 and x < int(b["board_width"]) and y < int(b["board_height"])


## piece_id on tile (x, y), or "" if empty.
static func piece_id_at(ledger: Dictionary, x: int, y: int) -> String:
	for piece_id in ledger["pieces"]:
		var p: Dictionary = ledger["pieces"][piece_id]
		if int(p["tile_x"]) == x and int(p["tile_y"]) == y:
			return String(piece_id)
	return ""


## The other side.
static func opponent_of(side: String) -> String:
	return SIDE_RIVAL if side == SIDE_PLAYER else SIDE_PLAYER


## Appends one entry to the append-only action log and returns it.
static func append_action(ledger: Dictionary, action_type: String, details: Dictionary) -> Dictionary:
	var action_log: Array = ledger["action_log"]
	var entry: Dictionary = {
		"action_index": action_log.size(),
		"turn_number": int(ledger["game_state"]["turn_number"]),
		"action_type": action_type,
		"details": details.duplicate(true),
	}
	action_log.append(entry)
	return entry


## Stable JSON text (sorted keys, tab indent) for saving and comparisons.
static func to_json_text(ledger: Dictionary) -> String:
	return JSON.stringify(ledger, "\t", true)


## Parses JSON text into a ledger. Returns {} on parse or validation failure.
static func from_json_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("KgLedger: JSON parse error line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("KgLedger: ledger root is not an object")
		return {}
	var ledger: Dictionary = _normalize_numbers(json.data)
	var errors: Array = validate(ledger)
	if not errors.is_empty():
		push_error("KgLedger: invalid ledger: %s" % ", ".join(PackedStringArray(errors)))
		return {}
	return ledger


## Writes the ledger to path (res:// or absolute). Returns an Error code.
static func save_ledger(ledger: Dictionary, path: String = DEFAULT_LEDGER_PATH) -> Error:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json_text(ledger))
	f.close()
	return OK


## Reads a ledger from path. Returns {} on failure.
static func load_ledger(path: String = DEFAULT_LEDGER_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("KgLedger.load_ledger: file not found %s" % path)
		return {}
	return from_json_text(FileAccess.get_file_as_string(path))


## Structural checks. Returns a list of error strings (empty = valid).
static func validate(ledger: Dictionary) -> Array:
	var errors: Array = []
	for key in ["ledger_version", "board", "piece_stats", "game_state", "pieces", "captured_pieces", "action_log"]:
		if not ledger.has(key):
			errors.append("missing key %s" % key)
	if not errors.is_empty():
		return errors
	if int(ledger["ledger_version"]) != LEDGER_VERSION:
		errors.append("unsupported ledger_version %s" % str(ledger["ledger_version"]))
	for piece_type in ledger["piece_stats"]:
		if not KgDice.is_valid_die(int(ledger["piece_stats"][piece_type]["die_sides"])):
			errors.append("bad die_sides for %s" % piece_type)
	var seen_tiles: Dictionary = {}
	for piece_id in ledger["pieces"]:
		var p: Dictionary = ledger["pieces"][piece_id]
		if String(p.get("piece_id", "")) != String(piece_id):
			errors.append("piece_id mismatch for %s" % piece_id)
		if not ledger["piece_stats"].has(p.get("piece_type", "")):
			errors.append("unknown piece_type on %s" % piece_id)
		var x: int = int(p.get("tile_x", -1))
		var y: int = int(p.get("tile_y", -1))
		if not in_bounds(ledger, x, y):
			errors.append("piece %s out of bounds" % piece_id)
		var tile_key: String = "%d,%d" % [x, y]
		if seen_tiles.has(tile_key):
			errors.append("two pieces on tile %s" % tile_key)
		seen_tiles[tile_key] = true
	var action_log: Array = ledger["action_log"]
	for i in range(action_log.size()):
		if int(action_log[i].get("action_index", -1)) != i:
			errors.append("action_log not sequential at %d" % i)
			break
	return errors


## JSON has no int type, so Godot parses numbers as float. The ledger schema
## has no fractional fields, so whole-number floats are converted back to int.
static func _normalize_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if f == floorf(f):
				return int(f)
			return f
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k in value:
				out[k] = _normalize_numbers(value[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for v in value:
				arr.append(_normalize_numbers(v))
			return arr
		_:
			return value
