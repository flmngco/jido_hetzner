# Jido Hetzner

Hetzner Cloud infrastructure provider for [Jido Shell](https://github.com/agentjido/jido_shell). Provisions VMs, connects via SSH, and tears them down — all behind the `Jido.Shell.Environment` behaviour.

Part of the [AgentJido](https://agentjido.xyz) ecosystem.

## Usage

```elixir
# Provision a Hetzner VM and get a shell session
{:ok, result} = Jido.Hetzner.Environment.provision("my-workspace", %{
  api_token: System.get_env("HETZNER_API_TOKEN"),
  server_type: "cpx11",
  image: "ubuntu-24.04",
  location: "nbg1"
}, [])

# Run commands on it
{:ok, output} = Jido.Shell.Exec.run(Jido.Shell.Agent, result.session_id, "uname -a")

# Tear down when done
Jido.Hetzner.Environment.teardown(result.session_id,
  server_id: result.server_id,
  ssh_key_id: result.ssh_key_id,
  ssh_key_cleanup: result.ssh_key_cleanup
)
```

### With JidoCode Forge

`Jido.Hetzner.ForgeAdapter` plugs into the Forge runtime via config — no compile-time dependency needed:

```elixir
# config/config.exs
config :jido_code, :infra_clients, [hetzner: Jido.Hetzner.ForgeAdapter]
```

Then start a Forge session with `infra_client: :hetzner`.

## Configuration

Runtime config overrides application config defaults:

```elixir
config :jido_hetzner,
  api_token: {:system, "HETZNER_API_TOKEN"},
  server_type: "cpx11",        # Hetzner shared vCPU (AMD)
  image: "ubuntu-24.04",
  location: "nbg1",            # Nuremberg
  ssh_key_strategy: :shared,   # :shared | :ephemeral | :existing
  ssh_key_name: "jido-ssh-key"
```

The `{:system, "ENV_VAR"}` tuple reads from environment variables at runtime.

## SSH Key Strategies

| Strategy | Behaviour |
|---|---|
| `:shared` (default) | Creates one SSH key per project, reuses across VMs |
| `:ephemeral` | Creates a new key per VM, deletes on teardown |
| `:existing` | Uses a pre-existing Hetzner SSH key ID |

## Installation

> **Note:** jido_shell is not yet published on hex.pm, so jido_hetzner must be installed from GitHub.

```elixir
def deps do
  [
    {:jido_hetzner, github: "agentjido/jido_hetzner"}
  ]
end
```

## Testing

```bash
mix test                                   # Unit tests (Bypass mocks, no API calls)
mix test --include hetzner_integration     # Live integration tests (needs HETZNER_API_TOKEN)
```

## Disclaimer

This project is not affiliated with, endorsed by, or associated with Hetzner Online GmbH. "Hetzner" is a trademark of Hetzner Online GmbH.

## License

MIT - see [LICENSE](LICENSE) for details.
