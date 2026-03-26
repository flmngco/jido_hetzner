defmodule Jido.Hetzner.SSHKeyTest do
  use ExUnit.Case, async: false

  alias Jido.Hetzner.SSHKey

  @base_config %{
    api_token: "test-token",
    api_module: FakeHetzner
  }

  setup do
    FakeHetzner.setup()
    on_exit(fn -> FakeHetzner.teardown() end)
    :ok
  end

  describe "shared strategy" do
    test "creates new key on first call" do
      {:ok, key_id, private_pem, :shared} =
        SSHKey.ensure(@base_config)

      assert is_integer(key_id)
      assert is_binary(private_pem)
      assert String.contains?(private_pem, "OPENSSH PRIVATE KEY")

      # Verify API was called
      calls = FakeHetzner.calls()
      assert Enum.any?(calls, fn {fun, _} -> fun == :list_ssh_keys end)
      assert Enum.any?(calls, fn {fun, _} -> fun == :create_ssh_key end)
    end

    test "reuses existing key when found" do
      # Pre-create a key
      FakeHetzner.create_ssh_key(%{name: "jido-ssh-key", public_key: "ssh-ed25519 AAAA..."}, %{})

      # Reset call tracking
      FakeHetzner.setup()
      # Re-create the key in fresh state
      FakeHetzner.create_ssh_key(%{name: "jido-ssh-key", public_key: "ssh-ed25519 AAAA..."}, %{})
      :persistent_term.put({FakeHetzner, :calls}, [])

      config =
        Map.put(
          @base_config,
          :ssh_private_key,
          "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----\n"
        )

      {:ok, key_id, _pem, :shared} = SSHKey.ensure(config)

      assert is_integer(key_id)

      # Should have listed but NOT created
      calls = FakeHetzner.calls()
      assert Enum.any?(calls, fn {fun, _} -> fun == :list_ssh_keys end)
      refute Enum.any?(calls, fn {fun, _} -> fun == :create_ssh_key end)
    end

    test "cleanup skipped when other VMs exist" do
      # Create a server so cleanup sees it
      FakeHetzner.create_server(
        %{name: "other-vm", labels: %{"jido.managed_by" => "jido-hetzner"}},
        %{}
      )

      assert :ok = SSHKey.maybe_cleanup(1000, :shared, @base_config)

      calls = FakeHetzner.calls()
      # Should have listed servers
      assert Enum.any?(calls, fn {fun, _} -> fun == :list_servers end)
      # Should NOT have deleted key
      refute Enum.any?(calls, fn {fun, _} -> fun == :delete_ssh_key end)
    end

    test "cleanup happens when last VM is torn down" do
      # No servers exist
      assert :ok = SSHKey.maybe_cleanup(1000, :shared, @base_config)

      calls = FakeHetzner.calls()
      assert Enum.any?(calls, fn {fun, _} -> fun == :list_servers end)
      assert Enum.any?(calls, fn {fun, _} -> fun == :delete_ssh_key end)
    end
  end

  describe "ephemeral strategy" do
    test "creates per-provision" do
      config = Map.put(@base_config, :ssh_key_strategy, :ephemeral)

      {:ok, key_id, private_pem, :ephemeral} = SSHKey.ensure(config)

      assert is_integer(key_id)
      assert is_binary(private_pem)

      calls = FakeHetzner.calls()
      assert Enum.any?(calls, fn {fun, _} -> fun == :create_ssh_key end)
    end

    test "deletes per-teardown" do
      assert :ok = SSHKey.maybe_cleanup(1000, :ephemeral, @base_config)

      calls = FakeHetzner.calls()
      assert Enum.any?(calls, fn {fun, _} -> fun == :delete_ssh_key end)
    end
  end

  describe "existing strategy" do
    test "uses provided key_id, never creates/deletes" do
      config =
        @base_config
        |> Map.put(:ssh_key_strategy, :existing)
        |> Map.put(:ssh_key_id, 42)
        |> Map.put(
          :ssh_private_key,
          "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----\n"
        )

      {:ok, 42, _pem, :none} = SSHKey.ensure(config)

      # No API calls for existing strategy
      assert FakeHetzner.calls() == []
    end

    test "errors without key_id" do
      config =
        @base_config
        |> Map.put(:ssh_key_strategy, :existing)

      {:error, %Jido.Hetzner.Error.InvalidConfigError{field: :ssh_key_id}} = SSHKey.ensure(config)
    end

    test "errors without private key" do
      config =
        @base_config
        |> Map.put(:ssh_key_strategy, :existing)
        |> Map.put(:ssh_key_id, 42)

      {:error, %Jido.Hetzner.Error.InvalidConfigError{field: :ssh_private_key}} =
        SSHKey.ensure(config)
    end

    test "cleanup is a no-op" do
      assert :ok = SSHKey.maybe_cleanup(42, :none, @base_config)
      assert FakeHetzner.calls() == []
    end
  end

  describe "generate_ed25519_keypair/0" do
    test "generates valid keypair" do
      {:ok, private_pem, public_openssh} = SSHKey.generate_ed25519_keypair()

      assert String.starts_with?(private_pem, "-----BEGIN OPENSSH PRIVATE KEY-----")
      assert String.ends_with?(String.trim(private_pem), "-----END OPENSSH PRIVATE KEY-----")
      assert String.starts_with?(public_openssh, "ssh-ed25519 ")
    end
  end
end
