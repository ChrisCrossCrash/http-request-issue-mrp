# MRP: HTTPRequest Non-Threaded Download Speeds are Limited by Framerate

This is the Minimal reproduction project (MRP) for the issue of [HTTPRequest Non-Threaded Download Speeds are Limited by Framerate #120425](https://github.com/godotengine/godot/issues/120425).

## Steps to reproduce

The MRP includes a small Python server (`server.py`) that serves a body of a requested size with a fixed `Content-Length`, no `gzip`, and no chunked transfer encoding. This matters: it guarantees each `read_response_body_chunk()` call is bounded by `download_chunk_size`, which makes the read count exact. (A public endpoint that uses chunked transfer encoding or gzip breaks that bound and muddies the measurement.) The MRP also sets `accept_gzip = false` and disables V-Sync so the `Engine.max_fps` caps are effective.

1. Start the bundled server: [`python server.py`](example/server.py) (listens on `127.0.0.1:8927`).
2. Run the MRP from the editor, or headlessly from the project root with `<GodotExecutable> --headless --path .`. It downloads 8 MB with a non-threaded `HTTPRequest` at four frame-rate caps (10, 30, 60 fps, and uncapped).
3. Observe the output. `reads/frame` stays at ~1.0 across every cap, while download time scales inversely with the cap — tripling the cap (10 → 30 fps) cuts the time to roughly a third, and doubling it (30 → 60 fps) roughly halves it. This is only possible if the frame rate, not the connection, is the bottleneck.
