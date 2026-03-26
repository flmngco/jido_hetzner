# AGENTS.md - Jido.Hetzner Guide

## Intent
Provision Hetzner Cloud VMs, connect via SSH, and tear them down behind the `Jido.Shell.Environment` behaviour.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test` (default alias excludes `:hetzner_integration`)
- `mix test --include hetzner_integration` (live integration tests, needs `HETZNER_API_TOKEN`)
- `mix q` or `mix quality` (`format --check-formatted`, `compile --warnings-as-errors`, `credo`, `dialyzer`)
- `mix coveralls.html` (coverage report)
- `mix docs` (local docs)

## Architecture Snapshot
- `Jido.Hetzner`: facade with delegates to Environment
- `Jido.Hetzner.Environment`: `Jido.Shell.Environment` implementation (provision/teardown/status)
- `Jido.Hetzner.API`: Hetzner Cloud HTTP client (Req-based, JSON)
- `Jido.Hetzner.SSHKey`: SSH key lifecycle (shared/ephemeral/existing strategies)
- `Jido.Hetzner.ForgeAdapter`: plugs into JidoCode Forge runtime via config dispatch
- `Jido.Hetzner.Error`: Splode-based error module with InvalidConfig, API, Provision, Teardown, Internal classes

## Standards
- Config flows runtime-first: provision-time config overrides app config defaults
- Use `{:system, "ENV_VAR"}` tuples for environment variable resolution
- Keep error returns structured (`{:error, Jido.Hetzner.Error.t()}`)
- SSH key strategy is explicit per-provision (`:shared`, `:ephemeral`, `:existing`)

## Testing and QA
- Unit tests use Bypass for HTTP mocking, FakeHetzner (persistent_term) for integration mocks
- Tag `:hetzner_integration` for live API tests (excluded by default)
- Test support modules in `test/support/`, compiled via `elixirc_paths(:test)`

## Release Hygiene
- Use Conventional Commits
- Update `CHANGELOG.md` and docs for behavior/API changes
- jido_shell is not yet on hex.pm; jido_hetzner uses a GitHub dep for now

## References
- `README.md`
- `usage-rules.md`
- `CONTRIBUTING.md`
