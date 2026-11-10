defmodule BoxicDmn.MixProject do
  use Mix.Project

  @version "0.4.0"
  @boxic_feel_requirement "~> 0.2.0"
  @source_url "https://github.com/lukegalea/boxic_dmn"

  def project do
    [
      app: :boxic_dmn,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      test_coverage: [summary: [threshold: 50]],
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:boxic_feel, @boxic_feel_requirement},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A native Elixir loader, validator, and evaluator for Decision Model and Notation 1.5 models."
  end

  defp package do
    [
      files:
        ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md CONFORMANCE.md CONSTRUCT_CAPABILITY_LEDGER.md),
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url,
        "Upstream" => "https://github.com/koenusz/boxic"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CONFORMANCE.md",
        "CONSTRUCT_CAPABILITY_LEDGER.md",
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Public API": [
          Boxic.DMN,
          Boxic.DMN.Authoring.DecisionTable,
          Boxic.DMN.AuthoringError,
          Boxic.DMN.Diagnostic,
          Boxic.DMN.SerializationError
        ],
        "Normalized model": ~r/^Boxic\.DMN\.Model/
      ]
    ]
  end
end
