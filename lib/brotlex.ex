defmodule Brotlex do
  @moduledoc """
  Stateful streaming Brotli compression via Rust NIF.

  Maintains a persistent compression window across multiple `encode/2` calls,
  making it ideal for compressing Server-Sent Events (SSE) and other streaming
  responses where later messages benefit from patterns seen in earlier ones.

  ## Usage

      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, "data: hello\\n\\n")
      {:ok, compressed} = Brotlex.encode(encoder, "data: world\\n\\n")
      {:ok, final} = Brotlex.close(encoder)
  """

  use Rustler, otp_app: :brotlex, crate: "brotlex"

  @type encoder :: reference()
  @type quality :: 0..11

  @doc """
  Creates a new stateful Brotli encoder.

  ## Options

    * `:quality` - Compression quality level from 0 (fastest) to 11 (best).
      Defaults to 4, which is a good balance for streaming use cases.

  ## Examples

      {:ok, encoder} = Brotlex.new()
      {:ok, encoder} = Brotlex.new(quality: 6)
  """
  @spec new(keyword()) :: {:ok, encoder()} | {:error, term()}
  def new(opts \\ []) do
    quality = Keyword.get(opts, :quality, 4)
    nif_new(quality)
  end

  @doc """
  Feeds a chunk of data through the encoder and returns compressed bytes.

  The encoder maintains state across calls, so later chunks benefit from
  patterns observed in earlier chunks (sliding window compression).

  Data is flushed after each call so compressed bytes are available immediately
  for sending to the client.

  ## Examples

      {:ok, compressed} = Brotlex.encode(encoder, "data: hello\\n\\n")
  """
  @spec encode(encoder(), iodata()) :: {:ok, binary()} | {:error, term()}
  def encode(_encoder, _data), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Finalizes the encoder and returns any remaining compressed bytes.

  This must be called when the stream ends to flush the final brotli frame.
  After calling `close/1`, the encoder reference should not be used again.

  ## Examples

      {:ok, final_bytes} = Brotlex.close(encoder)
  """
  @spec close(encoder()) :: {:ok, binary()} | {:error, term()}
  def close(_encoder), do: :erlang.nif_error(:nif_not_loaded)

  # Private NIF stubs
  defp nif_new(_quality), do: :erlang.nif_error(:nif_not_loaded)
end
