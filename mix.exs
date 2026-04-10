defmodule Brotlex.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/idreaminteractive/brotlex"

  def project do
    [
      app: :brotlex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.35.0", optional: true, runtime: false},
      {:rustler_precompiled, "~> 0.9.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Stateful streaming Brotli compression via Rust NIF. " <>
      "Designed for compressing Server-Sent Events (SSE) and other streaming responses."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        native/brotlex/src
        native/brotlex/Cargo.toml
        native/brotlex/Cargo.lock
        mix.exs
        README.md
        LICENSE
        checksum-Elixir.Brotlex.Native.exs
      )
    ]
  end
end
