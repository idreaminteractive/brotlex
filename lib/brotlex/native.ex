defmodule Brotlex.Native do
  @moduledoc false

  mix_config = Mix.Project.config()
  version = mix_config[:version]

  use RustlerPrecompiled,
    otp_app: :brotlex,
    crate: "brotlex",
    base_url: "https://github.com/idreaminteractive/brotlex/releases/download/v#{version}",
    version: version,
    force_build: System.get_env("BROTLEX_BUILD") in ["1", "true"],
    targets: ~w(aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu),
    nif_versions: ["2.15", "2.16", "2.17"]

  # NIF function stubs — these are replaced at load time by the compiled NIF.
  def nif_new(_quality), do: :erlang.nif_error(:nif_not_loaded)
  def nif_encode(_encoder, _data), do: :erlang.nif_error(:nif_not_loaded)
  def close(_encoder), do: :erlang.nif_error(:nif_not_loaded)
  def decompress(_data), do: :erlang.nif_error(:nif_not_loaded)
end
