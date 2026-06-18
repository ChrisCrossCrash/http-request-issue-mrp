extends Node

# Demonstrates that HTTPRequest non-threaded mode caps download throughput
# at download_chunk_size × frame_rate, regardless of connection speed.
# Run with VSync disabled (Project Settings > Display > Window > VSync Mode = Disabled).

const URL := "https://speed.cloudflare.com/__down?bytes=8388608"  # 8 MB
const FPS_CAPS := [10, 30, 60, 0]  # 0 = uncapped

var _http := HTTPRequest.new()
var _start_ms: int
var _test_index: int = 0
var _results: Array = []


func _ready() -> void:
	_http.use_threads = false
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	_run_next_test()


func _run_next_test() -> void:
	if _test_index >= FPS_CAPS.size():
		_print_results()
		return

	var fps: int = FPS_CAPS[_test_index]
	Engine.max_fps = fps
	var label := "uncapped" if fps == 0 else "%d fps" % fps
	print("Downloading at %s..." % label)
	_start_ms = Time.get_ticks_msec()
	_http.request(URL)


func _on_completed(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var elapsed_ms: int = Time.get_ticks_msec() - _start_ms
	_results.append({
		"fps": FPS_CAPS[_test_index],
		"elapsed_ms": elapsed_ms,
		"bytes": body.size(),
	})
	_test_index += 1
	await get_tree().create_timer(0.5).timeout
	_run_next_test()


func _print_results() -> void:
	print("\n== HTTPRequest non-threaded mode: throughput vs. frame rate ==")
	print("URL: %s" % URL)
	print("download_chunk_size: %d bytes\n" % _http.download_chunk_size)
	for r in _results:
		var fps_label: String = "uncapped" if r.fps == 0 else "%d fps" % r.fps
		var throughput_kbps: float = r.bytes / (r.elapsed_ms / 1000.0) / 1024.0
		var ceiling_kbps: float = _http.download_chunk_size * r.fps / 1024.0 if r.fps > 0 else INF
		var ceiling_str: String = "%.1f KB/s" % ceiling_kbps if r.fps > 0 else "none"
		print("  %-10s  %5d ms  %7.1f KB/s  (theoretical ceiling: %s)" % [
			fps_label, r.elapsed_ms, throughput_kbps, ceiling_str
		])
	print("\nBefore fix: elapsed time scales inversely with fps cap.")
	print("After fix:  all rows show similar throughput regardless of fps cap.")
