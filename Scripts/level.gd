class_name Level
extends Node2D

enum Temperature { COLD, MEDIUM, HOT }
enum Phase { NAME, PRACTICE, RESET_TO_SHOW, SHOWING, GAME }

@export var template_scene: PackedScene
@export var max_radar_distance: float
@export var hot_distance: float
@export var medium_distance: float
@export var cold_distance: float
@export var tombs_container: Node2D
@export var tomb_count: int
@export var practice_tombs_container: Node2D
@export var practice_fence: TileMapLayer
@export var player: Player
@export var timer: GameTimer
@export var name_label: Label
@export var tutorial_controller: TutorialController
@export var player_tracker: PlayerTracker
@export var combinations: Array[PackedInt32Array] = []
@export var min_combination_weight: float = 0.5
@export var max_combination_weight: float = 3.0
@export var supabase_client: SupabaseClient
@export var ghost_player_scene: PackedScene
@export var placement_tracker: PlacementTracker
@export var score_label: Label
@export var results_label: RichTextLabel
@export var score_conversion: float = 1.0
@export var leaderboard_label_a: Label
@export var leaderboard_label_b: Label
@export var leaderboard_animator_a: BoxAnimator
@export var leaderboard_animator_b: BoxAnimator

var collectable_positions: Array[Vector2] = []
var player_name: String = ""

var _active_tombs: Array[Tomb] = []
var _practice_tombs: Array[Tomb] = []
var _practice_index: int = 0
var _phase: Phase = Phase.NAME
var _player_best_runs: Dictionary = {}
var _combination_bests: Dictionary = {}
var _ghost_players: Array[GhostPlayer] = []
var _pending_ghosts: Array = []
var _pending_player_ghost: Dictionary = {}
var _ghosts_received: bool = false
var _player_ghost_received: bool = false
var _final_ghosts: Array = []
var _waiting_for_result_dismiss: bool = false
var _leaderboard_rows: Array = []

const _GHOST_COLORS: Array[Color] = [
	Color(0.4, 0.8, 1.0, 1),
	Color(1.0, 0.4, 0.4, 1),
	Color(0.4, 1.0, 0.4, 1),
	Color(1.0, 1.0, 0.4, 1),
	Color(0.8, 0.4, 1.0, 1),
]

func _ready() -> void:
	_disable_all_game_tombs()
	_setup_practice()
	if practice_fence:
		_set_fence_enabled(true)
	player.inputs_locked = true
	player.resetted.connect(_on_player_resetted)
	if timer:
		timer.countdown_finished.connect(_on_countdown_finished)
		timer.time_up.connect(_on_time_up)
	if supabase_client:
		supabase_client.best_runs_received.connect(_on_best_runs_received)
		supabase_client.combination_bests_received.connect(_on_combination_bests_received)
		supabase_client.ghosts_received.connect(_on_ghosts_received)
		supabase_client.player_ghost_received.connect(_on_player_ghost_received)
		supabase_client.faster_ghost_received.connect(_on_faster_ghost_received)
		supabase_client.leaderboard_received.connect(_on_leaderboard_received)
	_update_name_display()
	tutorial_controller.start()

func _fetch_run_data() -> void:
	if not supabase_client:
		return
	supabase_client.fetch_best_runs(player_name)
	supabase_client.fetch_combination_bests()
	supabase_client.fetch_leaderboard()

func _on_leaderboard_received(rows: Array) -> void:
	_leaderboard_rows = rows
	var start: float = timer.start_time if timer else 0.0
	_leaderboard_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := maxf(0.0, int(a.get("count", 0)) * start - float(a.get("total_elapsed", 0.0))) * score_conversion
		var sb := maxf(0.0, int(b.get("count", 0)) * start - float(b.get("total_elapsed", 0.0))) * score_conversion
		return sa > sb
	)
	_update_leaderboard_display()
	_update_score_display()


func _update_leaderboard_display() -> void:
	var lines_a: PackedStringArray = []
	var lines_b: PackedStringArray = []
	for i: int in 10:
		var line: String
		if i < _leaderboard_rows.size():
			var row := _leaderboard_rows[i] as Dictionary
			var pname: String = str(row.get("player_name", "?"))
			var elapsed: float = float(row.get("total_elapsed", 0.0))
			var count: int = int(row.get("count", 0))
			var start: float = timer.start_time if timer else 0.0
			var score: int = floori(maxf(0.0, count * start - elapsed) * score_conversion)
			line = str(i + 1) + ". " + pname + "  " + str(score)
		else:
			line = str(i + 1) + "."
		if i < 5:
			lines_a.append(line)
		else:
			lines_b.append(line)
	if leaderboard_label_a:
		leaderboard_label_a.text = "\n".join(lines_a)
	if leaderboard_label_b:
		leaderboard_label_b.text = "\n".join(lines_b)

var _leaderboard_open: bool = false

func _set_leaderboard_visible(value: bool) -> void:
	if value == _leaderboard_open:
		return
	_leaderboard_open = value
	for animator: BoxAnimator in [leaderboard_animator_a, leaderboard_animator_b]:
		if not animator:
			continue
		if value:
			animator.open()
		else:
			animator.close()

func _on_best_runs_received(rows: Array) -> void:
	_player_best_runs.clear()
	for row: Variant in rows:
		if row is Dictionary:
			_player_best_runs[(row as Dictionary)["tomb_combination"]] = (row as Dictionary)["elapsed"]
	_update_score_display()

func _get_player_rank_from_leaderboard() -> int:
	for i: int in _leaderboard_rows.size():
		var row := _leaderboard_rows[i] as Dictionary
		if str(row.get("player_name", "")) == player_name:
			return i + 1
	return 0

func _update_score_display() -> void:
	if not score_label or _phase != Phase.PRACTICE or _waiting_for_result_dismiss:
		return
	var score := _calculate_score()
	if score == 0:
		score_label.visible = false
		return
	var rank := _get_player_rank_from_leaderboard()
	var rank_str := (str(rank) + ".-") if rank > 0 else ""
	score_label.text = rank_str + str(score) + "pts"
	score_label.visible = true
	if _player_best_runs.size() > 0 and tutorial_controller and not _waiting_for_result_dismiss:
		tutorial_controller.start_brief()

func _calculate_score() -> int:
	if not timer:
		return 0
	var total := 0.0
	for combo: PackedInt32Array in combinations:
		var key := get_combination_string(combo)
		var elapsed := float(_player_best_runs.get(key, timer.start_time))
		total += timer.start_time - elapsed
	return floori(total * score_conversion)

func _on_combination_bests_received(rows: Array) -> void:
	_combination_bests.clear()
	for row: Variant in rows:
		if row is Dictionary:
			_combination_bests[(row as Dictionary)["tomb_combination"]] = (row as Dictionary)["best_elapsed"]

func _process(_delta: float) -> void:
	var show_lb := _phase == Phase.PRACTICE and not _waiting_for_result_dismiss and tutorial_controller != null and tutorial_controller.is_brief()
	_set_leaderboard_visible(show_lb)
	if _phase == Phase.NAME and Input.is_action_just_pressed("start"):
		if player_name.strip_edges().length() > 0:
			player.inputs_locked = false
			_phase = Phase.PRACTICE
			_rebuild_positions()
			_update_name_display()
			if tutorial_controller:
				tutorial_controller.exit_name_mode()
			_fetch_run_data()
	elif _phase == Phase.PRACTICE:
		if _waiting_for_result_dismiss:
			if Input.is_action_just_pressed("start"):
				_dismiss_results()
		else:
			if Input.is_action_just_pressed("start"):
				_phase = Phase.RESET_TO_SHOW
				player.force_reset()
				_update_name_display()
				if tutorial_controller:
					tutorial_controller.stop()
			elif Input.is_action_just_pressed("return"):
				player.inputs_locked = true
				_phase = Phase.NAME
				_update_name_display()
				if tutorial_controller:
					tutorial_controller.enter_name_mode()

func _unhandled_key_input(event: InputEvent) -> void:
	if _phase != Phase.NAME:
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_BACKSPACE:
		player_name = player_name.left(player_name.length() - 1)
		_update_name_display()
	elif key.unicode >= 32 and key.unicode < 127:
		if player_name.length() < 13:
			player_name += char(key.unicode)
			_update_name_display()

func _update_name_display() -> void:
	if not name_label:
		return
	match _phase:
		Phase.NAME:
			name_label.visible = true
			name_label.text = player_name + "|"
		Phase.PRACTICE:
			name_label.visible = true
			name_label.text = player_name
		_:
			name_label.visible = false

func _set_fence_enabled(value: bool) -> void:
	practice_fence.visible = value
	practice_fence.collision_enabled = value

func _disable_all_game_tombs() -> void:
	for child: Node in tombs_container.get_children():
		if child is Tomb:
			(child as Tomb).set_enabled(false)

func _setup_practice() -> void:
	for child: Node in practice_tombs_container.get_children():
		if child is Tomb:
			_practice_tombs.append(child as Tomb)
	_activate_practice()

func _activate_practice() -> void:
	_practice_index = 0
	for i: int in _practice_tombs.size():
		var tomb: Tomb = _practice_tombs[i]
		tomb.set_enabled(true)
		if i == 0:
			tomb.reset()
		else:
			tomb.pre_respect()
		if not tomb.respected.is_connected(_on_practice_tomb_respected.bind(i)):
			tomb.respected.connect(_on_practice_tomb_respected.bind(i))
	_rebuild_positions()

func _on_practice_tomb_respected(index: int) -> void:
	if index != _practice_index:
		return
	_practice_index = (_practice_index + 1) % _practice_tombs.size()
	_practice_tombs[_practice_index].reset()
	_rebuild_positions()
	if tutorial_controller:
		tutorial_controller.notify_respected()

func _on_player_resetted() -> void:
	match _phase:
		Phase.RESET_TO_SHOW:
			for tomb: Tomb in _practice_tombs:
				tomb.pre_respect()
			select_tombs()
			player.inputs_locked = true
			if score_label:
				score_label.visible = false
			if timer:
				timer.begin_showing()
			_phase = Phase.SHOWING
			_rebuild_positions()
		Phase.GAME:
			_return_to_practice()

func _on_countdown_finished() -> void:
	if score_label:
		score_label.visible = false
	if results_label:
		results_label.visible = false
	if player_tracker:
		player_tracker.reset()
	player.inputs_locked = false
	_phase = Phase.GAME
	_spawn_ghost_players()
	_rebuild_positions()
	_update_name_display()
	if practice_fence:
		_set_fence_enabled(false)
	if timer:
		timer.begin_game()

func _on_time_up() -> void:
	_show_results()
	player.force_reset()

func _return_to_practice() -> void:
	if placement_tracker:
		placement_tracker.stop()
	_clear_ghost_players()
	_disable_all_game_tombs()
	_active_tombs.clear()
	_activate_practice()
	if practice_fence:
		_set_fence_enabled(true)
	if timer:
		timer.hide_all()
	_phase = Phase.PRACTICE
	_waiting_for_result_dismiss = true
	_rebuild_positions()
	_update_name_display()
	if name_label:
		name_label.visible = false
	if score_label:
		score_label.visible = false
	_fetch_run_data()

func _dismiss_results() -> void:
	_waiting_for_result_dismiss = false
	if results_label:
		results_label.visible = false
	_update_name_display()
	_update_score_display()
	if tutorial_controller:
		tutorial_controller.stop()
		if _calculate_score() > 0 and _player_best_runs.size() > 0:
			tutorial_controller.start_brief()
		else:
			tutorial_controller.start()

func select_tombs() -> void:
	_disable_all_game_tombs()
	_active_tombs.clear()

	var combo := _pick_combination()
	var all_children := tombs_container.get_children()
	for idx: int in combo:
		if idx < all_children.size() and all_children[idx] is Tomb:
			var tomb := all_children[idx] as Tomb
			tomb.set_enabled(true)
			tomb.reset()
			if not tomb.respected.is_connected(_on_tomb_respected):
				tomb.respected.connect(_on_tomb_respected)
			_active_tombs.append(tomb)

	if player_tracker:
		player_tracker.tomb_combination = get_combination_string(combo)

	_rebuild_positions()
	_fetch_ghosts()

func _pick_combination() -> PackedInt32Array:
	if combinations.is_empty():
		return PackedInt32Array()

	var raw: Array[float] = []
	for combo: PackedInt32Array in combinations:
		var key := get_combination_string(combo)
		var player_e: float = _player_best_runs.get(key, -1.0)
		var global_e: float = _combination_bests.get(key, -1.0)
		raw.append(player_e - global_e if player_e > 0.0 and global_e > 0.0 else -1.0)

	var max_raw := 0.0
	var min_raw := INF
	for w: float in raw:
		if w >= 0.0:
			max_raw = maxf(max_raw, w)
			min_raw = minf(min_raw, w)

	var neutral := (min_combination_weight + max_combination_weight) * 0.5
	var weights: Array[float] = []
	for i: int in raw.size():
		var w := raw[i]
		if w < 0.0:
			weights.append(neutral)
		elif is_equal_approx(max_raw, min_raw):
			weights.append(max_combination_weight)
		else:
			weights.append(lerpf(min_combination_weight, max_combination_weight,
				(w - min_raw) / (max_raw - min_raw)))

	var total := 0.0
	for w: float in weights:
		total += w

	var r := randf() * total
	var cumulative := 0.0
	for i: int in combinations.size():
		cumulative += weights[i]
		if r <= cumulative:
			return combinations[i]

	return combinations[-1]

func get_combination_string(combo: PackedInt32Array) -> String:
	var sorted := combo.duplicate()
	sorted.sort()
	var parts: Array[String] = []
	for idx: int in sorted:
		parts.append(str(idx))
	return ",".join(parts)

func reset_tombs() -> void:
	for tomb: Tomb in _active_tombs:
		tomb.reset()
	_rebuild_positions()

func are_all_tombs_respected() -> bool:
	if _active_tombs.is_empty():
		return false
	for tomb: Tomb in _active_tombs:
		if not tomb.is_respected:
			return false
	return true

func _on_tomb_respected() -> void:
	if player_tracker:
		player_tracker.notify_respected()
	_rebuild_positions()
	if are_all_tombs_respected() and timer:
		timer.stop()
		_show_results()
		_submit_run()

func _show_results() -> void:
	if not results_label or not timer:
		return
	var start := timer.start_time
	var entries: Array[Dictionary] = []
	entries.append({"name": player_name, "remaining": start - timer.elapsed, "is_player": true})
	for gd: Variant in _final_ghosts:
		var ghost := gd as Dictionary
		entries.append({
			"name": str(ghost.get("ghost_name", "?")),
			"remaining": start - float(ghost.get("elapsed", start)),
			"is_player": false,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["remaining"]) > float(b["remaining"])
	)
	var lines: PackedStringArray = []
	for i: int in entries.size():
		var t: float = maxf(0.0, float(entries[i]["remaining"]))
		var m := int(t / 60.0)
		var s := int(t) % 60
		var cs := int(t * 100.0) % 100
		var row := "%d.%02d:%02d.%02d-%s" % [i + 1, m, s, cs, str(entries[i]["name"])]
		if entries[i]["is_player"]:
			lines.append("[color=#FF00FF]" + row + "[/color]")
		else:
			lines.append(row)
	lines.append("")
	lines.append("Press ENTER to continue")
	results_label.bbcode_enabled = true
	results_label.text = "\n".join(lines)
	results_label.visible = true

func _fetch_ghosts() -> void:
	if not supabase_client or not player_tracker:
		return
	var combo := player_tracker.tomb_combination
	if combo.is_empty():
		return
	_pending_ghosts.clear()
	_pending_player_ghost.clear()
	_final_ghosts.clear()
	_ghosts_received = false
	_player_ghost_received = false
	supabase_client.fetch_ghosts(combo)
	supabase_client.fetch_player_ghost(combo, player_name)

func _on_ghosts_received(ghosts: Array) -> void:
	_pending_ghosts = ghosts
	_ghosts_received = true
	_try_finalize_ghosts()

func _on_player_ghost_received(ghost: Dictionary) -> void:
	_pending_player_ghost = ghost
	_player_ghost_received = true
	_try_finalize_ghosts()

func _try_finalize_ghosts() -> void:
	if not _ghosts_received or not _player_ghost_received:
		return
	var result := _merge_ghosts(_pending_ghosts, _pending_player_ghost)
	_final_ghosts = result["ghosts"]
	if result["needs_faster"] and supabase_client and player_tracker:
		supabase_client.fetch_faster_ghost(
			player_tracker.tomb_combination,
			float(result["player_elapsed"]),
			player_name
		)
	else:
		if _phase == Phase.GAME:
			_spawn_ghost_players()

func _on_faster_ghost_received(ghost: Dictionary) -> void:
	if not ghost.is_empty():
		var slowest_idx := 0
		var slowest_elapsed := -INF
		for i: int in _final_ghosts.size():
			var e := float((_final_ghosts[i] as Dictionary).get("elapsed", 0.0))
			if e > slowest_elapsed:
				slowest_elapsed = e
				slowest_idx = i
		_final_ghosts[slowest_idx] = ghost
	if _phase == Phase.GAME:
		_spawn_ghost_players()

func _merge_ghosts(server_ghosts: Array, player_ghost: Dictionary) -> Dictionary:
	var all: Array = []
	for g: Variant in server_ghosts:
		all.append((g as Dictionary).duplicate())

	if player_ghost.is_empty():
		return {"ghosts": all, "needs_faster": false, "player_elapsed": 0.0}

	var pg := player_ghost.duplicate()
	pg["is_player"] = true
	var pg_name := str(pg.get("ghost_name", ""))
	var pg_elapsed := float(pg.get("elapsed", INF))

	var player_in_server := false
	for i: int in all.size():
		if str((all[i] as Dictionary).get("ghost_name", "")) == pg_name:
			(all[i] as Dictionary)["is_player"] = true
			player_in_server = true
			break

	if not player_in_server:
		if all.is_empty():
			all.append(pg)
		else:
			var slowest_idx := 0
			var slowest_elapsed := -INF
			for i: int in all.size():
				var e := float((all[i] as Dictionary).get("elapsed", 0.0))
				if e > slowest_elapsed:
					slowest_elapsed = e
					slowest_idx = i
			all[slowest_idx] = pg

	var player_is_fastest := true
	for g: Variant in all:
		var gd := g as Dictionary
		if str(gd.get("ghost_name", "")) != pg_name:
			if float(gd.get("elapsed", INF)) < pg_elapsed:
				player_is_fastest = false
				break

	return {"ghosts": all, "needs_faster": player_is_fastest, "player_elapsed": pg_elapsed}

func _spawn_ghost_players() -> void:
	if not ghost_player_scene:
		return
	_clear_ghost_players()
	if placement_tracker:
		placement_tracker.setup(_active_tombs)
	for i: int in _final_ghosts.size():
		var data := _final_ghosts[i] as Dictionary
		var gp := ghost_player_scene.instantiate() as GhostPlayer
		gp.global_position = player.position
		add_child(gp)
		gp.setup(
			data.get("ghost_name", "?"),
			data.get("positions", []),
			_GHOST_COLORS[i % _GHOST_COLORS.size()]
		)
		gp.activate()
		_ghost_players.append(gp)
		if placement_tracker:
			placement_tracker.register_ghost(gp)

func _clear_ghost_players() -> void:
	for gp: GhostPlayer in _ghost_players:
		gp.queue_free()
	_ghost_players.clear()

func _submit_run() -> void:
	if not supabase_client or not player_tracker or not timer:
		return
	var positions: Array = []
	for record: Variant in player_tracker.records:
		var r := record as Dictionary
		var pos: Vector2 = r["position"]
		positions.append({"x": pos.x, "y": pos.y, "time": r["time"]})
	supabase_client.submit_run(
		player_name,
		player_tracker.tomb_combination,
		timer.elapsed,
		positions
	)

func _rebuild_positions() -> void:
	collectable_positions.clear()
	if _phase == Phase.PRACTICE or _phase == Phase.RESET_TO_SHOW:
		if _practice_index < _practice_tombs.size():
			collectable_positions.append(_practice_tombs[_practice_index].global_position)
	elif _phase == Phase.GAME or _phase == Phase.SHOWING:
		for tomb: Tomb in _active_tombs:
			if not tomb.is_respected:
				collectable_positions.append(tomb.global_position)

func get_collectable_position(index: int) -> Vector2:
	return collectable_positions[index]

func get_collectable_temperature(index: int, from: Vector2) -> int:
	var dist: float = (collectable_positions[index] - from).length()
	if dist <= hot_distance:
		return Temperature.HOT
	if dist <= medium_distance:
		return Temperature.MEDIUM
	return Temperature.COLD
