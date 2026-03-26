defmodule Jido.Hetzner.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :hetzner_integration

  @tag timeout: 300_000
  test "provision, run commands, teardown" do
    token = System.get_env("HETZNER_API_TOKEN")
    assert token, "HETZNER_API_TOKEN must be set"

    config = %{
      api_token: token,
      server_type: "cx23",
      image: "ubuntu-24.04",
      location: "hel1"
    }

    workspace_id = "integ-#{:erlang.unique_integer([:positive])}"

    # Provision
    assert {:ok, result} = Jido.Hetzner.Environment.provision(workspace_id, config, [])

    assert result.workspace_id == workspace_id
    assert result.workspace_dir == "/work/#{workspace_id}"
    assert is_integer(result.server_id)
    assert is_binary(result.ip_address)
    assert is_binary(result.session_id)

    # Run commands via the session
    assert {:ok, hostname} =
             Jido.Shell.Exec.run(Jido.Shell.Agent, result.session_id, "hostname", timeout: 15_000)

    assert String.contains?(hostname, "jido")

    assert {:ok, whoami} =
             Jido.Shell.Exec.run(Jido.Shell.Agent, result.session_id, "whoami", timeout: 15_000)

    assert String.trim(whoami) == "root"

    # Teardown
    teardown_result =
      Jido.Hetzner.Environment.teardown(result.session_id,
        config: config,
        server_id: result.server_id,
        ssh_key_id: result.ssh_key_id,
        ssh_key_cleanup: result.ssh_key_cleanup
      )

    assert teardown_result.teardown_verified == true
    assert teardown_result.warnings == nil
  end
end
