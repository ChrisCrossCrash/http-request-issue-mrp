extends Node

# Measures reads-per-frame for HTTPRequest in non-threaded mode.
# Valid only against a Content-Length endpoint with gzip disabled, so that each
# read_response_body_chunk() call is bounded by download_chunk_size.
# Disable V-Sync (Project Settings > Display > Window > V-Sync Mode = Disabled)
# so the Engine.max_fps caps are effective.

const SERVER_BASE := "http://127.0.0.1:8927/"
# Returns exactly <bytes> zero bytes with a Content-Length header.
const DOWNLOAD_URL := SERVER_BASE + "/api/benchmark/download/%d/"
const BYTES := 8 * 1024 * 1024  # 8 MB
const FPS_CAPS := [10, 30, 60, 0]  # 0 = uncapped

var _http := HTTPRequest.new()
var _url := DOWNLOAD_URL % BYTES
var _start_ms: int
var _start_frames: int
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
	_start_frames = Engine.get_process_frames()
	_http.request(_url)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Download failed: result=%d code=%d" % [result, code])
	var elapsed_ms: int = Time.get_ticks_msec() - _start_ms
	var frames: int = Engine.get_process_frames() - _start_frames
	_results.append({
		"fps": FPS_CAPS[_test_index],
		"elapsed_ms": elapsed_ms,
		"frames": frames,
		"bytes": body.size(),
	})
	_test_index += 1
	await get_tree().create_timer(0.5).timeout
	_run_next_test()


func _print_results() -> void:
	var chunk_size: int = _http.download_chunk_size
	print("\n== HTTPRequest non-threaded mode: reads per frame ==")
	print("URL: %s" % _url)
	print("download_chunk_size: %d bytes\n" % chunk_size)
	print("  %-9s %9s %8s %7s %12s %12s" % ["cap", "elapsed", "frames", "reads", "reads/frame", "throughput"])
	for r in _results:
		var fps_label: String = "uncapped" if r.fps == 0 else "%d fps" % r.fps
		var seconds: float = r.elapsed_ms / 1000.0
		var reads: float = float(r.bytes) / chunk_size
		var reads_per_frame: float = reads / r.frames if r.frames > 0 else 0.0
		var throughput_kbps: float = r.bytes / seconds / 1024.0
		print("  %-9s %6d ms %8d %7.0f %12.2f %8.1f KB/s" % [
			fps_label, r.elapsed_ms, r.frames, reads, reads_per_frame, throughput_kbps
		])
