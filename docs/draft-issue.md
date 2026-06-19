# HTTPRequest Non-Threaded Download Speeds are Limited by Framerate

## Tested Versions

- Discovered in `v4.6.2.stable.official [71f334935]`.
- Reproducible in `v4.7.stable.official [5b4e0cb0f]`, `v4.2.stable.official.46dc27791` and `v4.0.stable.official [92bee43ad]`.
- I am not aware of any versions where this issue is not present.

> [!NOTE]
> For some reason, I had an issue opening the MRP attached to this issue with Godot 4.2 and 4.0, but it can be run headlessly with `<GodotExecutable> --headless --path .` from the project root.

## System Information

From **Help > Copy System Info**:
```
Godot v4.7.stable - Windows 11 (build 26200) - Multi-window, 2 monitors - Direct3D 12 (Forward+) - dedicated NVIDIA GeForce RTX 4070 (NVIDIA; 32.0.16.1047) - AMD Ryzen 5 7600 6-Core Processor (12 threads) - 31.11 GiB memory - WASAPI (44100 Hz, Stereo/mono)
```

## Issue Description

In non-threaded mode, `HTTPRequest` performs a single socket read per frame, so download throughput is capped at `download_chunk_size × frame_rate` regardless of how fast the connection can actually deliver data. The cap is the product of two things, in two functions in [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/0dd6299f7146362d36b130ac1dc42406cfb3ede6/scene/main/http_request.cpp):

1. **`_update_connection()` reads at most one chunk per call.** [Its `STATUS_BODY` case calls `client->read_response_body_chunk()` exactly once](https://github.com/godotengine/godot/blob/0dd6299f7146362d36b130ac1dc42406cfb3ede6/scene/main/http_request.cpp#L458-L490) and returns — it does not loop.
2. **In non-threaded mode, `_update_connection()` is called once per frame.** It runs from [the `NOTIFICATION_INTERNAL_PROCESS` branch of `_notification()`](https://github.com/godotengine/godot/blob/0dd6299f7146362d36b130ac1dc42406cfb3ede6/scene/main/http_request.cpp#L551-L559), which the engine delivers once per rendered frame.

Together these cap throughput at `download_chunk_size × frame_rate`. The threaded path (`use_threads = true`) escapes the cap entirely, because `_thread_func` calls `_update_connection()` in a tight loop at OS speed — neither the per-call chunk limit nor the frame rate gates it there.

I confirmed the once-per-frame behavior two ways. The MRP measures it from script (the `reads/frame` column in the output below stays at ~1.0 regardless of frame rate). I also confirmed it at the source level by adding a log line to the cooperative branch of `_notification()`:

```cpp
case NOTIFICATION_INTERNAL_PROCESS: {
    if (use_threads.is_set()) {
        return;
    }
    bool done = _update_connection();
    print_line("update_connection called, frame=" + itos(Engine::get_singleton()->get_process_frames()));
    if (done) {
        set_process_internal(false);
    }
} break;
```

This prints exactly one line per rendered frame for the entire download, and never two lines in the same frame. For an 8 MB body that is ~132 frames (128 reads of 64 KiB plus a few connection-setup frames that read no body), which matches the frame count the MRP reports.

With the default `download_chunk_size` of 65,536 bytes, the resulting throughput ceiling is:

| Frame rate | Ceiling |
|---|---|
| 10 fps | ~0.6 MB/s |
| 30 fps | ~1.9 MB/s |
| 60 fps | ~3.8 MB/s |
| 144 fps | ~9.2 MB/s |

The measured throughput in the MRP lands just under each of these ceilings, with the small shortfall accounted for by the handful of connection-setup frames.

One consequence worth noting: with V-Sync enabled, the frame rate is tied to the monitor's refresh rate, so download throughput scales with the display's refresh rate. Users with a 60 Hz display will see roughly half the download speed of users with a 120 Hz display, even if both have the same connection.

As far as I can tell, the slowness was first reported in 2019 as [#32807](https://github.com/godotengine/godot/issues/32807). That issue attributed the cause to the small default `read_chunk_size` and resolved it by exposing `download_chunk_size` as a tunable. However, raising `download_chunk_size` only lifts the ceiling — it does not remove the one-read-per-frame gate, which remains in the current source.

**Expected behavior:** In non-threaded mode, `HTTPRequest` should drain the data already buffered in the socket each frame, so that throughput tracks actual connection speed rather than polling cadence.

## Steps to Reproduce

The MRP includes a small Python server (`server.py`) that serves a body of a requested size with a fixed `Content-Length`, no `gzip`, and no chunked transfer encoding. This matters: it guarantees each `read_response_body_chunk()` call is bounded by `download_chunk_size`, which makes the read count exact. (A public endpoint that uses chunked transfer encoding or gzip breaks that bound and muddies the measurement.) The MRP also sets `accept_gzip = false` and disables V-Sync so the `Engine.max_fps` caps are effective.

1. Start the bundled server: `python server.py` (listens on `127.0.0.1:8927`).
2. Run the MRP from the editor, or headlessly from the project root with `<GodotExecutable> --headless --path .`. It downloads 8 MB with a non-threaded `HTTPRequest` at four frame-rate caps (10, 30, 60 fps, and uncapped).
3. Observe the output. `reads/frame` stays at ~1.0 across every cap, while download time scales inversely with the cap — tripling the cap (10 → 30 fps) cuts the time to roughly a third, and doubling it (30 → 60 fps) roughly halves it. This is only possible if the frame rate, not the connection, is the bottleneck.

Real output from the MRP:

```
== HTTPRequest non-threaded mode: reads per frame ==
URL: http://127.0.0.1:8927/api/benchmark/download/8388608/
download_chunk_size: 65536 bytes

  cap         elapsed   frames   reads  reads/frame   throughput
  10 fps     12944 ms      131     128         0.98    632.9 KB/s
  30 fps      4400 ms      132     128         0.97   1861.8 KB/s
  60 fps      2200 ms      132     128         0.97   3723.6 KB/s
  uncapped     910 ms      132     128         0.97   9002.2 KB/s
```