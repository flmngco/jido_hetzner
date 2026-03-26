defmodule Jido.Hetzner.ForgeAdapter do
  @moduledoc """
  Hetzner Cloud infrastructure client adapter for JidoCode Forge.

  Wraps `Jido.Hetzner.Environment` to provision Hetzner VMs and execute
  commands via SSH. Supports progress reporting during provisioning.

  This module implements the same interface as `JidoCode.Forge.InfraClient.Behaviour`
  and is resolved at runtime via `function_exported?/3` dispatch — no compile-time
  dependency on jido_code is needed.

  ## Configuration

  Pass Hetzner-specific config via the `:hetzner_config` key in the spec:

      spec = %{
        hetzner_config: %{
          api_token: "hc_...",
          server_type: "cx22",
          image: "ubuntu-24.04",
          location: "fsn1"
        }
      }
  """

  require Logger

  defstruct [
    :session_id,
    :server_id,
    :ip_address,
    :ssh_key_id,
    :ssh_key_cleanup,
    :config,
    :workspace_id
  ]

  def impl_module, do: __MODULE__

  def create(spec) do
    config = Map.get(spec, :hetzner_config, %{})
    workspace_id = Map.get(spec, :workspace_id, "forge-#{:erlang.unique_integer([:positive])}")
    on_progress = Map.get(spec, :on_progress)
    provision_opts = if on_progress, do: [on_progress: on_progress], else: []

    case Jido.Hetzner.Environment.provision(workspace_id, config, provision_opts) do
      {:ok, result} ->
        client = %__MODULE__{
          session_id: result.session_id,
          server_id: result.server_id,
          ip_address: result.ip_address,
          ssh_key_id: result.ssh_key_id,
          ssh_key_cleanup: result.ssh_key_cleanup,
          config: config,
          workspace_id: workspace_id
        }

        {:ok, client, "hetzner-#{result.server_id}"}

      {:error, _} = err ->
        err
    end
  end

  def exec(%__MODULE__{session_id: sid}, command, opts) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    case Jido.Shell.Exec.run(Jido.Shell.Agent, sid, command, timeout: timeout) do
      {:ok, output} -> {output, 0}
      {:error, %{context: %{code: code}}} -> {"", code}
      {:error, _} -> {"", 1}
    end
  end

  def write_file(%__MODULE__{} = client, path, content) do
    encoded = Base.encode64(content)
    {_, code} = exec(client, "echo '#{encoded}' | base64 -d > #{path}", [])
    if code == 0, do: :ok, else: {:error, :write_failed}
  end

  def read_file(%__MODULE__{session_id: sid}, path) do
    Jido.Shell.Exec.run(Jido.Shell.Agent, sid, "cat #{path}")
  end

  def inject_env(%__MODULE__{}, env_map) when map_size(env_map) == 0, do: :ok

  def inject_env(%__MODULE__{} = client, env_map) do
    lines =
      env_map
      |> Enum.map(fn {k, v} -> "export #{k}=\"#{escape_value(v)}\"" end)
      |> Enum.join("\n")

    write_file(client, "/etc/profile.d/jido_env.sh", lines)
  end

  def spawn(%__MODULE__{} = client, command, args, opts) do
    full_cmd = Enum.join([command | args], " ")
    {output, code} = exec(client, "nohup #{full_cmd} > /tmp/spawn.log 2>&1 & echo $!", opts)
    if code == 0, do: {:ok, String.trim(output)}, else: {:error, :spawn_failed}
  end

  def destroy(%__MODULE__{} = client, _infra_id) do
    teardown =
      Jido.Hetzner.Environment.teardown(client.session_id,
        config: client.config,
        server_id: client.server_id,
        ssh_key_id: client.ssh_key_id,
        ssh_key_cleanup: client.ssh_key_cleanup
      )

    if teardown.teardown_verified, do: :ok, else: {:error, :teardown_failed}
  end

  defp escape_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end
end
