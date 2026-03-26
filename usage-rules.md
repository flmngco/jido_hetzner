# Jido Hetzner Usage Rules

## Intent
Provision Hetzner Cloud VMs as shell environments with managed SSH connectivity and lifecycle.

## Core Contracts
- Implement `Jido.Shell.Environment` behaviour: `provision/3`, `teardown/2`, `status/2`.
- Config is runtime-first: the `config` map at provision time overrides app config defaults.
- Use `{:system, "ENV_VAR"}` tuples in app config for environment variable resolution.
- Always return structured Splode errors (`Jido.Hetzner.Error`), never bare atoms or strings.

## SSH Key Strategy Guidance
- `:shared` (default) — one key reused across VMs in the project, good for dev/CI.
- `:ephemeral` — one key per VM, deleted on teardown, good for isolation.
- `:existing` — use a pre-existing Hetzner SSH key ID, requires `:ssh_key_id` and `:ssh_private_key`.

## Config Patterns
```elixir
# Application config (optional defaults)
config :jido_hetzner,
  api_token: {:system, "HETZNER_API_TOKEN"},
  server_type: "cpx11",
  image: "ubuntu-24.04",
  location: "nbg1",
  ssh_key_strategy: :shared,
  ssh_key_name: "jido-ssh-key"
```

## Testing Patterns
- Use Bypass for HTTP API tests (no real Hetzner calls).
- Use FakeHetzner (`persistent_term`) for integration-level mocks.
- Tag live API tests with `@tag :hetzner_integration`.
- Set `max_retries: 0` in test API client config to avoid retry delays.

## Forge Integration
- `Jido.Hetzner.ForgeAdapter` plugs into JidoCode via config dispatch, no compile-time dep.
- Register in config: `config :jido_code, :infra_clients, [hetzner: Jido.Hetzner.ForgeAdapter]`

## Avoid
- Hardcoding API tokens; always use runtime config or `{:system, ...}` tuples.
- Skipping teardown; leaked VMs cost money.
- Using `:existing` strategy without providing both `:ssh_key_id` and `:ssh_private_key`.

## References
- `README.md`
- `AGENTS.md`
- `CONTRIBUTING.md`
