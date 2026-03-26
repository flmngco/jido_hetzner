defmodule Jido.Hetzner.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_hetzner"
  @description "Hetzner Cloud infrastructure provider for Jido Shell"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_hetzner,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "Jido Hetzner",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        export: "cov"
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        ignore_warnings: "dialyzer.ignore-warnings"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key, :ssh]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime
      {:jido_shell, github: "agentjido/jido_shell"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:splode, "~> 0.3.0"},

      # Dev/Test
      {:bypass, "~> 2.1", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:plug_cowboy, "~> 2.7", only: :test},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      test: "test --exclude hetzner_integration",
      docs: "docs -f html --open",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*", "usage-rules.md"],
      maintainers: ["Patrick Detlefsen"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Core: [Jido.Hetzner, Jido.Hetzner.Environment, Jido.Hetzner.API],
        "SSH Keys": [Jido.Hetzner.SSHKey],
        "Forge Integration": [Jido.Hetzner.ForgeAdapter],
        Errors: [
          Jido.Hetzner.Error,
          Jido.Hetzner.Error.InvalidConfigError,
          Jido.Hetzner.Error.APIError,
          Jido.Hetzner.Error.ProvisionError,
          Jido.Hetzner.Error.TeardownError,
          Jido.Hetzner.Error.InternalError
        ]
      ]
    ]
  end
end
