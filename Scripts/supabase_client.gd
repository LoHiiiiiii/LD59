class_name SupabaseClient
extends Node

signal leaderboard_received(rows: Array)
signal ghosts_received(ghosts: Array)
signal player_ghost_received(ghost: Dictionary)
signal player_rank_received(rank: int)
signal best_runs_received(rows: Array)
signal combination_bests_received(rows: Array)
signal submit_completed(success: bool)
signal faster_ghost_received(ghost: Dictionary)

var supabase_url: String
var anon_key: String
var edge_function_url: String

const GHOST_COUNT: int = 5

var _secret_salt: String

var _js_callbacks: Dictionary = {}
var _js_cb_id: int = 0

func fetch_leaderboard() -> void:
	_fetch_get("/rest/v1/leaderboard?select=*", _on_leaderboard_response)

func fetch_ghosts(tomb_combination: String) -> void:
	_post_rpc("get_ghosts", {
		"p_tomb_combination": tomb_combination,
		"p_count": GHOST_COUNT
	}, _on_ghosts_response)

func fetch_player_ghost(tomb_combination: String, player_name: String) -> void:
	_post_rpc("get_player_ghost", {
		"p_tomb_combination": tomb_combination,
		"p_player_name": player_name
	}, _on_player_ghost_response)

func fetch_player_rank(player_name: String) -> void:
	_post_rpc("get_player_rank", {"p_player_name": player_name}, _on_player_rank_response)

func fetch_best_runs(player_name: String) -> void:
	_fetch_get(
		"/rest/v1/runs?select=tomb_combination,elapsed&player_name=eq." + player_name.uri_encode(),
		_on_best_runs_response
	)

func fetch_combination_bests() -> void:
	_fetch_get("/rest/v1/combination_bests?select=*", _on_combination_bests_response)

func fetch_faster_ghost(tomb_combination: String, elapsed: float, p_player_name: String) -> void:
	_post_rpc("get_faster_ghost", {
		"p_tomb_combination": tomb_combination,
		"p_elapsed": elapsed,
		"p_player_name": p_player_name,
	}, _on_faster_ghost_response)

func submit_run(
	player_name: String,
	tomb_combination: String,
	elapsed: float,
	positions: Array
) -> void:
	var body := JSON.stringify({
		"player_name": player_name,
		"tomb_combination": tomb_combination,
		"elapsed": elapsed,
		"positions": positions,
		"validation_hash": _compute_hash(player_name, tomb_combination, elapsed)
	})
	if OS.get_name() == "Web":
		_js_request(edge_function_url, "POST", _edge_headers(), body,
			func(data: Variant) -> void:
				submit_completed.emit(data != null)
		)
	else:
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(result: int, code: int, _h, _b) -> void:
			http.queue_free()
			submit_completed.emit(result == HTTPRequest.RESULT_SUCCESS and code == 200)
		)
		http.request(edge_function_url, _edge_headers(), HTTPClient.METHOD_POST, body)

func _compute_hash(player_name: String, tomb_combination: String, elapsed: float) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var msg: String = player_name + "|" + tomb_combination + "|" + "%.2f" % elapsed + _secret_salt
	ctx.update(msg.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _fetch_get(path: String, callback: Callable) -> void:
	if OS.get_name() == "Web":
		_js_request(supabase_url + path, "GET", _anon_headers(), "", callback)
	else:
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray) -> void:
			http.queue_free()
			_handle_response(result, code, body, callback)
		)
		http.request(supabase_url + path, _anon_headers(), HTTPClient.METHOD_GET)

func _post_rpc(fn: String, params: Dictionary, callback: Callable) -> void:
	var body := JSON.stringify(params)
	if OS.get_name() == "Web":
		_js_request(supabase_url + "/rest/v1/rpc/" + fn, "POST", _anon_headers(), body, callback)
	else:
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(result: int, code: int, _h, resp_body: PackedByteArray) -> void:
			http.queue_free()
			_handle_response(result, code, resp_body, callback)
		)
		http.request(supabase_url + "/rest/v1/rpc/" + fn, _anon_headers(), HTTPClient.METHOD_POST, body)

func _js_request(url: String, method: String, headers: PackedStringArray, body: String, callback: Callable) -> void:
	var cb_key := "gd_%d" % _js_cb_id
	_js_cb_id += 1

	var js_cb := JavaScriptBridge.create_callback(func(args: Array) -> void:
		_js_callbacks.erase(cb_key)
		var text := str(args[0]) if not args.is_empty() and args[0] != null else ""
		if text.is_empty():
			callback.call(null)
			return
		var json := JSON.new()
		if json.parse(text) != OK:
			callback.call(null)
			return
		callback.call(json.data)
	)
	_js_callbacks[cb_key] = js_cb
	JavaScriptBridge.get_interface("window")[cb_key] = js_cb

	var h_entries: Array[String] = []
	for h: String in headers:
		var sep := h.find(": ")
		if sep >= 0:
			h_entries.append('"%s":"%s"' % [
				h.left(sep).replace("\\", "\\\\").replace('"', '\\"'),
				h.substr(sep + 2).replace("\\", "\\\\").replace('"', '\\"'),
			])
	var headers_js := "{" + ",".join(h_entries) + "}"
	var body_js := ""
	if not body.is_empty():
		body_js = ",body:'" + body.replace("\\", "\\\\").replace("'", "\\'") + "'"

	JavaScriptBridge.eval(
		"(async()=>{try{const r=await fetch('%s',{method:'%s',headers:%s%s});const t=await r.text();window['%s'](t);}catch(e){window['%s'](null);}})();" % [
			url, method, headers_js, body_js, cb_key, cb_key
		]
	)

func _handle_response(
	result: int,
	code: int,
	body: PackedByteArray,
	callback: Callable
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		callback.call(null)
		return
	var body_str := body.get_string_from_utf8()
	if body_str.is_empty():
		callback.call(null)
		return
	var json := JSON.new()
	if json.parse(body_str) != OK:
		callback.call(null)
		return
	callback.call(json.data)

func _anon_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + anon_key,
		"Authorization: Bearer " + anon_key,
		"Content-Type: application/json",
	])

func _edge_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + anon_key,
	])

func _on_leaderboard_response(data: Variant) -> void:
	leaderboard_received.emit(data if data is Array else [])

func _on_ghosts_response(data: Variant) -> void:
	ghosts_received.emit(data if data is Array else [])

func _on_player_ghost_response(data: Variant) -> void:
	if data is Array and not (data as Array).is_empty():
		player_ghost_received.emit((data as Array)[0])
	else:
		player_ghost_received.emit({})

func _on_player_rank_response(data: Variant) -> void:
	player_rank_received.emit(data if data is int else 0)

func _on_best_runs_response(data: Variant) -> void:
	best_runs_received.emit(data if data is Array else [])

func _on_combination_bests_response(data: Variant) -> void:
	combination_bests_received.emit(data if data is Array else [])

func _on_faster_ghost_response(data: Variant) -> void:
	if data is Array and not (data as Array).is_empty():
		faster_ghost_received.emit((data as Array)[0])
	else:
		faster_ghost_received.emit({})
