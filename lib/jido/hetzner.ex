defmodule Jido.Hetzner do
  @moduledoc """
  Hetzner Cloud environment for AgentJido shell sessions.

  Provisions Hetzner Cloud VMs and connects to them via SSH for remote
  command execution. Implements `Jido.Shell.Environment` so it can be
  used as a drop-in replacement for Sprite environments.

  ## Quick Start

      Jido.Shell.Exec.provision_workspace("my-workspace",
        environment: Jido.Hetzner.Environment,
        config: %{
          api_token: "hc_...",
          server_type: "cx22",
          image: "ubuntu-24.04",
          location: "fsn1"
        }
      )

  ## Configuration

  Config flows runtime-first: the `config` map passed at provision time
  overrides application config defaults.

      # Application config (optional defaults):
      config :jido_hetzner,
        api_token: {:system, "HETZNER_API_TOKEN"},
        server_type: "cx22",
        image: "ubuntu-24.04",
        location: "fsn1"

  ## SSH Key Strategies

  - `:shared` (default) — one key reused across all VMs in the project
  - `:ephemeral` — one key per VM, deleted on teardown
  - `:existing` — use a pre-existing Hetzner SSH key ID
  """

  defdelegate provision(workspace_id, config, opts), to: Jido.Hetzner.Environment
  defdelegate teardown(session_id, opts), to: Jido.Hetzner.Environment
  defdelegate status(session_id, opts), to: Jido.Hetzner.Environment
end
