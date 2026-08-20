defmodule Press.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/altenwald/press"

  def project do
    [
      app: :press,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A dependency-free Elixir library for rendering HTML+CSS into PDF",
      package: package(),
      docs: docs(),
      homepage_url: @source_url,
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs README* LICENSE* .formatter.exs),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end
end
