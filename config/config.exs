import Config

# Default configuration for Jido.Hetzner.
# These values are used as fallbacks when not provided at runtime.
#
# config :jido_hetzner,
#   api_token: {:system, "HETZNER_API_TOKEN"},
#   server_type: "cpx11",
#   image: "ubuntu-24.04",
#   location: "nbg1"

if config_env() == :dev do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      commit_msg: [
        tasks: [
          {:cmd, "mix git_ops.check_message", include_hook_args: true}
        ]
      ]
    ]

  config :git_ops,
    mix_project: Jido.Hetzner.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/flmngco/jido_hetzner",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v",
    types: [
      feat: [header: "Features"],
      fix: [header: "Bug Fixes"],
      perf: [header: "Performance"],
      refactor: [header: "Refactoring"],
      docs: [hidden?: true],
      test: [hidden?: true],
      chore: [hidden?: true],
      ci: [hidden?: true]
    ]
end
