defmodule Jido.Hetzner.SSHKey do
  @moduledoc """
  SSH key lifecycle management for Hetzner Cloud VMs.

  Supports three strategies:

  - `:shared` (default) — one "jido-ssh-key" reused across all VMs
  - `:ephemeral` — one key per VM, deleted on teardown
  - `:existing` — use a pre-existing Hetzner SSH key ID (never creates/deletes)
  """

  alias Jido.Hetzner.API
  alias Jido.Hetzner.Error

  @default_key_name "jido-ssh-key"

  @doc """
  Ensure an SSH key is available for provisioning.

  Returns `{:ok, key_id, private_pem, cleanup_strategy}` on success.

  `cleanup_strategy` is one of:
  - `:shared` — cleanup only when no jido-managed VMs remain
  - `:ephemeral` — always cleanup on teardown
  - `:none` — never cleanup (user-provided key)
  """
  @spec ensure(map()) :: {:ok, integer(), binary(), atom()} | {:error, term()}
  def ensure(config) do
    api_mod = Map.get(config, :api_module, API)
    strategy = Map.get(config, :ssh_key_strategy, :shared)

    case strategy do
      :existing ->
        ensure_existing(config)

      :ephemeral ->
        ensure_ephemeral(config, api_mod)

      :shared ->
        key_name = Map.get(config, :ssh_key_name, @default_key_name)
        ensure_shared(key_name, config, api_mod)
    end
  end

  @doc """
  Clean up SSH key if appropriate based on the cleanup strategy.

  - `:none` — no-op
  - `:ephemeral` — always delete
  - `:shared` — delete only when no other jido-managed servers remain
  """
  @spec maybe_cleanup(integer(), atom(), map()) :: :ok | {:error, term()}
  def maybe_cleanup(_key_id, :none, _config), do: :ok

  def maybe_cleanup(key_id, :ephemeral, config) do
    api_mod = Map.get(config, :api_module, API)

    case api_mod.delete_ssh_key(key_id, config) do
      {:ok, _} -> :ok
      {:error, {:not_found, _}} -> :ok
      {:error, _} = error -> error
    end
  end

  def maybe_cleanup(key_id, :shared, config) do
    api_mod = Map.get(config, :api_module, API)

    case any_jido_servers_remaining?(config, api_mod) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        case api_mod.delete_ssh_key(key_id, config) do
          {:ok, _} -> :ok
          {:error, {:not_found, _}} -> :ok
          {:error, _} = error -> error
        end

      {:error, _} ->
        # Can't determine — leave key in place to be safe
        :ok
    end
  end

  # -- Strategies ------------------------------------------------------------

  defp ensure_existing(config) do
    case Map.get(config, :ssh_key_id) do
      nil ->
        {:error,
         Error.invalid_config("SSH key ID required for :existing strategy", field: :ssh_key_id)}

      key_id ->
        case Map.get(config, :ssh_private_key) do
          nil ->
            {:error,
             Error.invalid_config("SSH private key required for :existing strategy",
               field: :ssh_private_key
             )}

          pem when is_binary(pem) ->
            {:ok, key_id, pem, :none}
        end
    end
  end

  defp ensure_ephemeral(config, api_mod) do
    with {:ok, private_pem, public_openssh} <- generate_ed25519_keypair() do
      name = "jido-ephemeral-#{:erlang.unique_integer([:positive])}"

      case api_mod.create_ssh_key(%{name: name, public_key: public_openssh}, config) do
        {:ok, %{"ssh_key" => %{"id" => key_id}}} ->
          {:ok, key_id, private_pem, :ephemeral}

        {:error, _} = error ->
          error
      end
    end
  end

  defp ensure_shared(key_name, config, api_mod) do
    case find_shared_key(key_name, config, api_mod) do
      {:ok, key_id} ->
        # Key exists — reuse if we have the private key, otherwise replace it
        case Map.get(config, :ssh_private_key) do
          pem when is_binary(pem) ->
            {:ok, key_id, pem, :shared}

          nil ->
            # We don't have the private key (e.g. orphaned from a failed run).
            # Delete the old key and create a fresh one.
            _ = api_mod.delete_ssh_key(key_id, config)
            create_shared_key(key_name, config, api_mod)
        end

      {:not_found} ->
        create_shared_key(key_name, config, api_mod)
    end
  end

  defp create_shared_key(key_name, config, api_mod) do
    with {:ok, private_pem, public_openssh} <- generate_ed25519_keypair() do
      case api_mod.create_ssh_key(%{name: key_name, public_key: public_openssh}, config) do
        {:ok, %{"ssh_key" => %{"id" => key_id}}} ->
          {:ok, key_id, private_pem, :shared}

        {:error, {:conflict, _}} ->
          # Race condition: another process created it. Retry find.
          case find_shared_key(key_name, config, api_mod) do
            {:ok, key_id} ->
              {:ok, key_id, private_pem, :shared}

            _ ->
              {:error,
               Error.provision_error("SSH key creation race condition",
                 stage: :ssh_key,
                 details: %{key_name: key_name}
               )}
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp find_shared_key(key_name, config, api_mod) do
    case api_mod.list_ssh_keys(%{name: key_name}, config) do
      {:ok, %{"ssh_keys" => [%{"id" => key_id} | _]}} ->
        {:ok, key_id}

      {:ok, %{"ssh_keys" => []}} ->
        {:not_found}

      {:error, _} = error ->
        error
    end
  end

  defp any_jido_servers_remaining?(config, api_mod) do
    case api_mod.list_servers(%{label_selector: "jido.managed_by=jido-hetzner"}, config) do
      {:ok, %{"servers" => servers}} ->
        {:ok, length(servers) > 0}

      {:error, _} = error ->
        error
    end
  end

  @doc false
  def generate_ed25519_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

    # Build OpenSSH public key format
    key_type = "ssh-ed25519"
    type_bytes = <<byte_size(key_type)::32>> <> key_type
    pub_bytes = <<byte_size(pub)::32>> <> pub
    blob = type_bytes <> pub_bytes
    public_openssh = "#{key_type} #{Base.encode64(blob)}"

    # Build PEM-encoded private key (OpenSSH format)
    private_pem = encode_openssh_ed25519_pem(pub, priv)

    {:ok, private_pem, public_openssh}
  rescue
    error ->
      {:error, {:keypair_generation_failed, Exception.message(error)}}
  end

  defp encode_openssh_ed25519_pem(pub, priv) do
    key_type = "ssh-ed25519"
    check_int = :crypto.strong_rand_bytes(4)

    # Private section (unencrypted)
    private_section =
      check_int <>
        check_int <>
        ssh_string(key_type) <>
        ssh_string(pub) <>
        ssh_string(priv <> pub) <>
        ssh_string("")

    # Pad to block size (8 for none cipher)
    pad_len = rem(8 - rem(byte_size(private_section), 8), 8)
    padding = :binary.list_to_bin(Enum.map(1..max(pad_len, 1), fn i -> rem(i, 256) end))

    private_section =
      if pad_len > 0,
        do: private_section <> binary_part(padding, 0, pad_len),
        else: private_section

    # Public key in blob form
    pub_blob = ssh_string(key_type) <> ssh_string(pub)

    # Full auth_magic format
    auth_magic = "openssh-key-v1\0"
    cipher = "none"
    kdf = "none"
    kdf_opts = ""
    num_keys = 1

    body =
      auth_magic <>
        ssh_string(cipher) <>
        ssh_string(kdf) <>
        ssh_string(kdf_opts) <>
        <<num_keys::32>> <>
        ssh_string(pub_blob) <>
        ssh_string(private_section)

    encoded = Base.encode64(body, padding: true)

    lines =
      encoded
      |> String.graphemes()
      |> Enum.chunk_every(70)
      |> Enum.map(&Enum.join/1)
      |> Enum.join("\n")

    "-----BEGIN OPENSSH PRIVATE KEY-----\n#{lines}\n-----END OPENSSH PRIVATE KEY-----\n"
  end

  defp ssh_string(data) when is_binary(data) do
    <<byte_size(data)::32>> <> data
  end
end
