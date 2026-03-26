defmodule Jido.Hetzner.EnvironmentTest do
  use ExUnit.Case, async: false

  alias Jido.Hetzner.Environment

  # Fake SSH module that always succeeds
  defmodule FakeSSHModule do
    def connect(_host, _port, _opts, _timeout) do
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    def close(_conn), do: :ok
  end

  # Fake session module
  defmodule FakeSessionMod do
    def start_with_vfs(_workspace_id, _opts) do
      {:ok, "sess-fake-#{:erlang.unique_integer([:positive])}"}
    end
  end

  # Fake agent module
  defmodule FakeAgentMod do
    def run(_session_id, _command, _opts) do
      {:ok, ""}
    end

    def stop(_session_id), do: :ok
  end

  @base_config %{
    api_token: "test-token-hc",
    api_module: FakeHetzner,
    ssh_module: FakeSSHModule,
    server_type: "cx22",
    image: "ubuntu-24.04",
    location: "fsn1"
  }

  setup do
    FakeHetzner.setup()
    on_exit(fn -> FakeHetzner.teardown() end)
    :ok
  end

  describe "provision/3" do
    test "full success flow" do
      {:ok, result} =
        Environment.provision("test-ws", @base_config,
          session_mod: FakeSessionMod,
          agent_mod: FakeAgentMod
        )

      assert result.workspace_id == "test-ws"
      assert result.workspace_dir == "/work/test-ws"
      assert is_binary(result.session_id)
      assert is_integer(result.server_id)
      assert is_binary(result.ip_address)
      assert is_integer(result.ssh_key_id)

      # Verify API calls were made in order
      calls = FakeHetzner.calls()
      call_names = Enum.map(calls, fn {name, _} -> name end)
      assert :list_ssh_keys in call_names
      assert :create_ssh_key in call_names
      assert :create_server in call_names
      assert :get_server in call_names
    end

    test "failure: missing API token" do
      config = Map.delete(@base_config, :api_token)

      assert {:error, %Jido.Hetzner.Error.InvalidConfigError{field: :api_token}} =
               Environment.provision("test-ws", config,
                 session_mod: FakeSessionMod,
                 agent_mod: FakeAgentMod
               )
    end

    test "failure: API error on server create" do
      FakeHetzner.override(:create_server, {:error, {:unauthorized, %{}}})

      assert {:error, %Jido.Hetzner.Error.ProvisionError{stage: :server_create}} =
               Environment.provision("test-ws", @base_config,
                 session_mod: FakeSessionMod,
                 agent_mod: FakeAgentMod
               )
    end

    test "failure: server never reaches running" do
      FakeHetzner.override(
        :get_server,
        {:ok,
         %{
           "server" => %{
             "status" => "initializing",
             "public_net" => %{"ipv4" => %{"ip" => "1.2.3.4"}}
           }
         }}
      )

      config = Map.put(@base_config, :server_wait_timeout, 100)

      assert {:error, %Jido.Hetzner.Error.ProvisionError{stage: :server_wait}} =
               Environment.provision("test-ws", config,
                 session_mod: FakeSessionMod,
                 agent_mod: FakeAgentMod
               )
    end

    test "failure: SSH never connectable" do
      # Override SSH to always fail
      failing_ssh = %{@base_config | ssh_module: __MODULE__.FailingSSH}
      config = Map.put(failing_ssh, :ssh_wait_timeout, 100)

      assert {:error, %Jido.Hetzner.Error.ProvisionError{stage: :ssh_wait}} =
               Environment.provision("test-ws", config,
                 session_mod: FakeSessionMod,
                 agent_mod: FakeAgentMod
               )
    end

    test "uses custom image (integer snapshot ID)" do
      {:ok, _result} =
        Environment.provision("test-ws", Map.put(@base_config, :image, 12_345_678),
          session_mod: FakeSessionMod,
          agent_mod: FakeAgentMod
        )

      calls = FakeHetzner.calls()
      {_, create_params} = Enum.find(calls, fn {name, _} -> name == :create_server end)
      assert create_params.image == "12345678"
    end
  end

  describe "teardown/2" do
    test "success" do
      # First provision
      {:ok, result} =
        Environment.provision("teardown-ws", @base_config,
          session_mod: FakeSessionMod,
          agent_mod: FakeAgentMod
        )

      teardown_result =
        Environment.teardown(result.session_id,
          config: @base_config,
          server_id: result.server_id,
          ssh_key_id: result.ssh_key_id,
          ssh_key_cleanup: result.ssh_key_cleanup,
          stop_mod: FakeAgentMod
        )

      assert teardown_result.teardown_verified == true
      assert teardown_result.teardown_attempts >= 1
    end

    test "idempotent: server already gone" do
      FakeHetzner.override(:delete_server, {:error, {:not_found, %{}}})
      FakeHetzner.override(:get_server, {:error, {:not_found, %{}}})

      teardown_result =
        Environment.teardown("sess-gone",
          config: @base_config,
          server_id: 99999,
          stop_mod: FakeAgentMod
        )

      assert teardown_result.teardown_verified == true
    end
  end

  describe "status/2" do
    test "returns server info" do
      {:ok, result} =
        Environment.provision("status-ws", @base_config,
          session_mod: FakeSessionMod,
          agent_mod: FakeAgentMod
        )

      {:ok, status} =
        Environment.status(result.session_id,
          config: @base_config,
          server_id: result.server_id
        )

      assert status.status == "running"
      assert is_binary(status.ip)
    end
  end

  # Module for SSH failure test
  defmodule FailingSSH do
    def connect(_host, _port, _opts, _timeout), do: {:error, :econnrefused}
    def close(_conn), do: :ok
  end
end
