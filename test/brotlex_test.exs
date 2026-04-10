defmodule BrotlexTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "creates an encoder with default quality" do
      assert {:ok, encoder} = Brotlex.new()
      assert is_reference(encoder)
    end

    test "creates an encoder with custom quality" do
      assert {:ok, encoder} = Brotlex.new(quality: 0)
      assert is_reference(encoder)
    end

    test "clamps quality to max 11" do
      assert {:ok, encoder} = Brotlex.new(quality: 99)
      assert is_reference(encoder)
    end
  end

  describe "encode/2" do
    test "compresses a single chunk" do
      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, "hello world")

      assert is_binary(compressed)
      assert byte_size(compressed) > 0
    end

    test "compresses multiple chunks through same encoder" do
      {:ok, encoder} = Brotlex.new()

      {:ok, c1} = Brotlex.encode(encoder, "data: first\n\n")
      {:ok, c2} = Brotlex.encode(encoder, "data: second\n\n")
      {:ok, c3} = Brotlex.encode(encoder, "data: third\n\n")

      assert is_binary(c1)
      assert is_binary(c2)
      assert is_binary(c3)
    end

    test "returns error after encoder is closed" do
      {:ok, encoder} = Brotlex.new()
      {:ok, _} = Brotlex.encode(encoder, "hello")
      {:ok, _} = Brotlex.close(encoder)

      assert {:error, "encoder already closed"} = Brotlex.encode(encoder, "should fail")
    end
  end

  describe "close/1" do
    test "finalizes the encoder" do
      {:ok, encoder} = Brotlex.new()
      {:ok, _} = Brotlex.encode(encoder, "hello")
      {:ok, final_bytes} = Brotlex.close(encoder)

      assert is_binary(final_bytes)
    end

    test "returns error when closed twice" do
      {:ok, encoder} = Brotlex.new()
      {:ok, _} = Brotlex.close(encoder)

      assert {:error, "encoder already closed"} = Brotlex.close(encoder)
    end
  end

  describe "round-trip" do
    test "single chunk round-trip decompresses to original" do
      original = "data: {\"status\":\"active\"}\n\n"
      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, original)
      {:ok, final} = Brotlex.close(encoder)

      # Concatenate all compressed output, then decompress
      all_compressed = compressed <> final
      {:ok, decompressed} = Brotlex.decompress(all_compressed)

      assert decompressed == original
    end

    test "multi-chunk round-trip decompresses to original" do
      messages = [
        "data: {\"count\":1}\n\n",
        "data: {\"count\":2}\n\n",
        "data: {\"count\":3}\n\n",
        "data: {\"count\":4}\n\n",
        "data: {\"count\":5}\n\n"
      ]

      {:ok, encoder} = Brotlex.new()

      compressed_chunks =
        Enum.map(messages, fn msg ->
          {:ok, compressed} = Brotlex.encode(encoder, msg)
          compressed
        end)

      {:ok, final} = Brotlex.close(encoder)

      all_compressed = IO.iodata_to_binary(compressed_chunks ++ [final])
      {:ok, decompressed} = Brotlex.decompress(all_compressed)

      assert decompressed == Enum.join(messages)
    end

    test "SSE-style payload round-trip" do
      events =
        for i <- 1..20 do
          "event: update\ndata: {\"id\":#{i},\"value\":\"item_#{i}\"}\n\n"
        end

      {:ok, encoder} = Brotlex.new(quality: 4)

      compressed_chunks =
        Enum.map(events, fn event ->
          {:ok, compressed} = Brotlex.encode(encoder, event)
          compressed
        end)

      {:ok, final} = Brotlex.close(encoder)

      all_compressed = IO.iodata_to_binary(compressed_chunks ++ [final])
      {:ok, decompressed} = Brotlex.decompress(all_compressed)

      assert decompressed == Enum.join(events)
    end
  end

  describe "compression window benefit" do
    test "later chunks with similar data compress better" do
      # Repeat the same pattern many times — the encoder should
      # produce smaller output for later chunks due to window context
      {:ok, encoder} = Brotlex.new(quality: 4)

      message = "data: {\"status\":\"active\",\"timestamp\":\"2024-01-01T00:00:00Z\"}\n\n"

      sizes =
        for _i <- 1..20 do
          {:ok, compressed} = Brotlex.encode(encoder, message)
          byte_size(compressed)
        end

      {:ok, _} = Brotlex.close(encoder)

      # The first chunk should be at least as large as later chunks.
      # Due to window warmup, later identical messages should compress smaller.
      first = List.first(sizes)
      last = List.last(sizes)

      assert first >= last,
             "Expected first chunk (#{first} bytes) >= last chunk (#{last} bytes)"
    end
  end

  describe "decompress/1" do
    test "decompresses valid brotli data" do
      # Compress with new + encode + close, then decompress
      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, "test data")
      {:ok, final} = Brotlex.close(encoder)

      {:ok, result} = Brotlex.decompress(compressed <> final)
      assert result == "test data"
    end
  end

  describe "edge cases" do
    test "empty input" do
      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, "")
      assert is_binary(compressed)
      {:ok, final} = Brotlex.close(encoder)

      {:ok, decompressed} = Brotlex.decompress(compressed <> final)
      assert decompressed == ""
    end

    test "large input" do
      large = String.duplicate("data: {\"key\":\"value\"}\n\n", 10_000)

      {:ok, encoder} = Brotlex.new()
      {:ok, compressed} = Brotlex.encode(encoder, large)
      {:ok, final} = Brotlex.close(encoder)

      {:ok, decompressed} = Brotlex.decompress(compressed <> final)
      assert decompressed == large

      # Should actually compress well
      compressed_size = byte_size(compressed <> final)
      original_size = byte_size(large)
      assert compressed_size < original_size
    end

    test "encoder with quality 0 (fastest)" do
      {:ok, encoder} = Brotlex.new(quality: 0)
      {:ok, compressed} = Brotlex.encode(encoder, "fast compression")
      {:ok, final} = Brotlex.close(encoder)

      {:ok, decompressed} = Brotlex.decompress(compressed <> final)
      assert decompressed == "fast compression"
    end

    test "encoder with quality 11 (best)" do
      {:ok, encoder} = Brotlex.new(quality: 11)
      {:ok, compressed} = Brotlex.encode(encoder, "best compression")
      {:ok, final} = Brotlex.close(encoder)

      {:ok, decompressed} = Brotlex.decompress(compressed <> final)
      assert decompressed == "best compression"
    end
  end
end
