# Brotlex

Stateful streaming Brotli compression for Elixir via Rust NIF.

Maintains a persistent compression window across multiple `encode/2` calls, so later messages benefit from patterns seen in earlier ones. Designed for compressing Server-Sent Events (SSE) and other streaming HTTP responses at the connection level.

## Why?

Per-message Brotli compression (stateless) produces independent frames that don't share context. Connection-level streaming compression keeps the sliding window across all messages, which means:

- Brotli's built-in static dictionary kicks in from the first byte (especially good for JSON/HTML)
- Repeated patterns across messages compress heavily
- Small deltas between similar messages compress to almost nothing

This is how the [Datastar Go SDK](https://github.com/starfederation/datastar-go) handles SSE compression.

## Requirements

- Elixir >= 1.15
- Rust toolchain (stable)

## Installation

Add `brotlex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:brotlex, "~> 0.1.0"}
  ]
end
```

Rust must be installed on the build machine. The NIF is compiled automatically via [Rustler](https://github.com/rusterlium/rustler) during `mix compile`.

## API

```elixir
# Create a new stateful encoder (quality 0-11, default 4)
{:ok, encoder} = Brotlex.new()
{:ok, encoder} = Brotlex.new(quality: 6)

# Feed chunks through the encoder (accepts iodata)
{:ok, compressed} = Brotlex.encode(encoder, "data: hello\n\n")
{:ok, compressed} = Brotlex.encode(encoder, "data: world\n\n")

# Finalize the stream (must be called when done)
{:ok, final_bytes} = Brotlex.close(encoder)

# One-shot decompression (useful for testing)
{:ok, original} = Brotlex.decompress(compressed_binary)
```

## Phoenix SSE Usage

```elixir
defmodule MyAppWeb.SseController do
  use MyAppWeb, :controller

  def stream(conn, _params) do
    {:ok, encoder} = Brotlex.new(quality: 4)

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("content-encoding", "br")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    Enum.reduce_while(my_event_stream(), {conn, encoder}, fn event, {conn, encoder} ->
      payload = "data: #{Jason.encode!(event)}\n\n"
      {:ok, compressed} = Brotlex.encode(encoder, payload)

      case chunk(conn, compressed) do
        {:ok, conn} -> {:cont, {conn, encoder}}
        {:error, _} -> {:halt, {conn, encoder}}
      end
    end)
    |> then(fn {conn, encoder} ->
      {:ok, final} = Brotlex.close(encoder)
      chunk(conn, final)
      conn
    end)
  end
end
```

## Quality Levels

| Quality | Use Case |
|---------|----------|
| 0-3 | Fastest, minimal compression |
| **4** | **Default. Good balance for streaming SSE** |
| 5-6 | Balanced, comparable to gzip |
| 7-9 | High compression, higher CPU |
| 10-11 | Maximum compression, not recommended for streaming |

## How It Works

1. `Brotlex.new/1` creates a Rust `CompressorWriter` backed by an in-memory buffer, stored as an Erlang NIF resource
2. `Brotlex.encode/2` writes data into the compressor, flushes, and returns compressed bytes
3. The encoder reference is held by your Elixir process -- one encoder per SSE connection
4. `Brotlex.close/1` finalizes the brotli stream and releases the encoder

The Rust NIF runs on the normal BEAM scheduler. At quality 4 with typical SSE message sizes, compression takes microseconds and does not risk scheduler blocking.

## License

MIT
