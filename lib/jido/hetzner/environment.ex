defmodule Jido.Hetzner.Environment do
  @moduledoc """
  Hetzner Cloud environment — provisions VMs and connects via SSH.

  Implements `Jido.Shell.Environment` for use with `Jido.Shell.Exec`.

  ## Configuration

  Runtime config overrides application config defaults:

      config = %{
        api_token: "hc_...",
        server_type: "cx22",           # default
        image: "ubuntu-24.04",         # name string or integer snapshot ID
        location: "fsn1",              # default
        ssh_key_strategy: :shared,     # :shared | :ephemeral | :existing
        ssh_key_name: "jido-ssh-key",  # for :shared strategy
        ssh_key_id: nil,               # for :existing strategy
        ssh_private_key: nil,          # raw PEM, required for :existing
        workspace_base: "/work",
        labels: %{},
        user_data: nil
      }
  """

  @behaviour Jido.Shell.Environment

  alias Jido.Hetzner.API
  alias Jido.Hetzner.Error
  alias Jido.Hetzner.SSHKey

  @default_server_type "cpx11"
  @default_image "ubuntu-24.04"
  @default_location "nbg1"
  @default_workspace_base "/work"
  @default_ssh_wait_timeout 120_000
  @default_server_wait_timeout 120_000
  @server_poll_interval 2_000
  @ssh_poll_interval 3_000

  @doc "Provisions a Hetzner Cloud VM and returns a shell session."
  @impl true
  def provision(workspace_id, config, opts)
      when is_binary(workspace_id) and is_map(config) and is_list(opts) do
    config = merge_with_defaults(config)
    api_mod = Map.get(config, :api_module, API)
    session_mod = Keyword.get(opts, :session_mod, Jido.Shell.ShellSession)
    agent_mod = Keyword.get(opts, :agent_mod, Jido.Shell.Agent)

    with :ok <- validate_config(config),
         :ok <-
           emit_progress(opts, :ssh_key, %{strategy: Map.get(config, :ssh_key_strategy, :shared)}),
         {:ok, key_id, private_pem, key_cleanup} <- SSHKey.ensure(config),
         :ok <- emit_progress(opts, :server_creating, %{workspace_id: workspace_id}),
         {:ok, server} <- create_server(workspace_id, key_id, config, api_mod),
         :ok <- emit_progress(opts, :server_booting, %{server_id: server["id"]}),
         {:ok, ip} <- wait_for_running(server["id"], config, api_mod),
         :ok <- emit_progress(opts, :ssh_waiting, %{ip: ip}),
         :ok <- wait_for_ssh(ip, private_pem, config),
         :ok <- emit_progress(opts, :ssh_connected, %{ip: ip}),
         :ok <- emit_progress(opts, :session_starting, %{workspace_id: workspace_id}),
         {:ok, session_id} <- start_session(workspace_id, ip, private_pem, config, session_mod),
         {:ok, _} <- create_workspace_dir(session_id, workspace_id, config, agent_mod) do
      {:ok,
       %{
         session_id: session_id,
         workspace_dir: workspace_dir(workspace_id, config),
         workspace_id: workspace_id,
         server_id: server["id"],
         ip_address: ip,
         ssh_key_id: key_id,
         ssh_key_cleanup: key_cleanup
       }}
    end
  end

  @doc "Tears down a previously provisioned Hetzner VM and cleans up resources."
  @impl true
  def teardown(session_id, opts) when is_binary(session_id) and is_list(opts) do
    config = Keyword.get(opts, :config, %{}) |> merge_with_defaults()
    api_mod = Map.get(config, :api_module, API)
    stop_mod = Keyword.get(opts, :stop_mod, Jido.Shell.Agent)
    server_id = Keyword.get(opts, :server_id)
    key_id = Keyword.get(opts, :ssh_key_id)
    key_cleanup = Keyword.get(opts, :ssh_key_cleanup, :none)
    retry_backoffs = Keyword.get(opts, :retry_backoffs_ms, [0, 1_000, 3_000])

    warnings = []

    # Stop the session
    warnings = try_stop_session(stop_mod, session_id, warnings)

    # Delete the server with retries
    {verified, attempts, warnings} =
      delete_server_with_retries(server_id, config, api_mod, retry_backoffs, warnings)

    # Clean up SSH key if appropriate
    warnings = try_cleanup_ssh_key(key_id, key_cleanup, config, warnings)

    %{
      teardown_verified: verified,
      teardown_attempts: attempts,
      warnings: normalize_warnings(warnings)
    }
  end

  @doc "Returns the current status of a provisioned Hetzner VM."
  @impl true
  def status(session_id, opts) when is_binary(session_id) and is_list(opts) do
    config = Keyword.get(opts, :config, %{}) |> merge_with_defaults()
    api_mod = Map.get(config, :api_module, API)
    server_id = Keyword.get(opts, :server_id)

    case api_mod.get_server(server_id, config) do
      {:ok, %{"server" => server}} ->
        {:ok,
         %{
           status: server["status"],
           ip: get_in(server, ["public_net", "ipv4", "ip"]),
           server_type: get_in(server, ["server_type", "name"]),
           location: get_in(server, ["datacenter", "location", "name"]),
           server_id: server["id"],
           name: server["name"]
         }}

      {:error, _} = error ->
        error
    end
  end

  # -- Private: Config -------------------------------------------------------

  defp merge_with_defaults(config) do
    defaults =
      Application.get_all_env(:jido_hetzner)
      |> Map.new()
      |> resolve_system_envs()

    Map.merge(defaults, config)
  end

  defp resolve_system_envs(defaults) do
    Enum.reduce(defaults, %{}, fn
      {key, {:system, env_var}}, acc ->
        Map.put(acc, key, System.get_env(env_var))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp validate_config(config) do
    cond do
      !is_binary(Map.get(config, :api_token)) ->
        {:error, Error.invalid_config("API token is required", field: :api_token)}

      String.trim(Map.get(config, :api_token, "")) == "" ->
        {:error, Error.invalid_config("API token is required", field: :api_token)}

      true ->
        :ok
    end
  end

  # -- Private: Server lifecycle ---------------------------------------------

  defp create_server(workspace_id, key_id, config, api_mod) do
    params = %{
      name: sanitize_hostname("jido-#{workspace_id}"),
      server_type: Map.get(config, :server_type, @default_server_type),
      image: resolve_image(Map.get(config, :image, @default_image)),
      location: Map.get(config, :location, @default_location),
      ssh_keys: [key_id],
      start_after_create: true,
      labels:
        Map.merge(
          %{"jido.managed_by" => "jido-hetzner", "jido.workspace_id" => workspace_id},
          Map.get(config, :labels, %{})
        ),
      user_data: Map.get(config, :user_data)
    }

    # Remove nil user_data
    params = if params.user_data == nil, do: Map.delete(params, :user_data), else: params

    case api_mod.create_server(params, config) do
      {:ok, %{"server" => server}} ->
        {:ok, server}

      {:error, reason} ->
        {:error,
         Error.provision_error("Server creation failed",
           stage: :server_create,
           details: %{reason: reason}
         )}
    end
  end

  defp wait_for_running(server_id, config, api_mod) do
    timeout = Map.get(config, :server_wait_timeout, @default_server_wait_timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_running(server_id, config, api_mod, deadline)
  end

  defp do_wait_for_running(server_id, config, api_mod, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Error.provision_error("Server did not become ready",
         stage: :server_wait,
         details: %{server_id: server_id}
       )}
    else
      case api_mod.get_server(server_id, config) do
        {:ok, %{"server" => %{"status" => "running", "public_net" => %{"ipv4" => %{"ip" => ip}}}}} ->
          {:ok, ip}

        {:ok, %{"server" => %{"status" => status}}}
        when status in ["initializing", "starting", "migrating"] ->
          Process.sleep(@server_poll_interval)
          do_wait_for_running(server_id, config, api_mod, deadline)

        {:ok, %{"server" => %{"status" => status}}} ->
          {:error,
           Error.provision_error("Unexpected server status",
             stage: :server_wait,
             details: %{server_id: server_id, status: status}
           )}

        {:error, reason} ->
          {:error,
           Error.provision_error("Failed to poll server status",
             stage: :server_poll,
             details: %{server_id: server_id, reason: reason}
           )}
      end
    end
  end

  defp wait_for_ssh(ip, private_pem, config) do
    ssh_mod = Map.get(config, :ssh_module, :ssh)
    timeout = Map.get(config, :ssh_wait_timeout, @default_ssh_wait_timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_ssh(ip, private_pem, ssh_mod, deadline)
  end

  defp do_wait_for_ssh(ip, private_pem, ssh_mod, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Error.provision_error("SSH connection timed out", stage: :ssh_wait, details: %{ip: ip})}
    else
      ssh_opts = [
        {:user, ~c"root"},
        {:key_cb, {Jido.Shell.Backend.SSH.KeyCallback, key: private_pem}},
        {:silently_accept_hosts, true},
        {:user_interaction, false}
      ]

      case ssh_mod.connect(String.to_charlist(ip), 22, ssh_opts, 5_000) do
        {:ok, conn} ->
          ssh_mod.close(conn)
          :ok

        {:error, _} ->
          Process.sleep(@ssh_poll_interval)
          do_wait_for_ssh(ip, private_pem, ssh_mod, deadline)
      end
    end
  end

  defp start_session(workspace_id, ip, private_pem, config, session_mod) do
    backend_config = %{
      host: ip,
      port: 22,
      user: Map.get(config, :ssh_user, "root"),
      key: private_pem
    }

    # Pass through ssh_module/ssh_connection_module for testing
    backend_config =
      backend_config
      |> maybe_put(:ssh_module, Map.get(config, :ssh_module))
      |> maybe_put(:ssh_connection_module, Map.get(config, :ssh_connection_module))

    session_opts = [
      backend: {Jido.Shell.Backend.SSH, backend_config}
    ]

    session_mod.start_with_vfs(workspace_id, session_opts)
  end

  defp create_workspace_dir(session_id, workspace_id, config, agent_mod) do
    dir = workspace_dir(workspace_id, config)
    Jido.Shell.Exec.run(agent_mod, session_id, "mkdir -p #{dir}", timeout: 30_000)
  end

  defp workspace_dir(workspace_id, config) do
    base = Map.get(config, :workspace_base, @default_workspace_base)
    "#{base}/#{workspace_id}"
  end

  # -- Private: Teardown -----------------------------------------------------

  defp try_stop_session(stop_mod, session_id, warnings) do
    case stop_mod.stop(session_id) do
      :ok -> warnings
      {:ok, _} -> warnings
      {:error, reason} -> ["session_stop_failed=#{inspect(reason)}" | warnings]
    end
  rescue
    _ -> warnings
  end

  defp delete_server_with_retries(nil, _config, _api_mod, _backoffs, warnings) do
    {false, 0, ["server_id_missing" | warnings]}
  end

  defp delete_server_with_retries(server_id, config, api_mod, backoffs, warnings) do
    backoffs
    |> Enum.with_index(1)
    |> Enum.reduce_while({false, 0, warnings}, fn {backoff_ms, attempt}, {_, _, acc_warnings} ->
      if backoff_ms > 0, do: Process.sleep(backoff_ms)

      case api_mod.delete_server(server_id, config) do
        {:ok, _} ->
          # Verify it's gone
          case api_mod.get_server(server_id, config) do
            {:error, {:not_found, _}} ->
              {:halt, {true, attempt, acc_warnings}}

            _ ->
              {:cont, {false, attempt, acc_warnings}}
          end

        {:error, {:not_found, _}} ->
          {:halt, {true, attempt, acc_warnings}}

        {:error, reason} ->
          {:cont, {false, attempt, ["server_delete_failed=#{inspect(reason)}" | acc_warnings]}}
      end
    end)
  end

  defp try_cleanup_ssh_key(nil, _cleanup, _config, warnings), do: warnings
  defp try_cleanup_ssh_key(_key_id, :none, _config, warnings), do: warnings

  defp try_cleanup_ssh_key(key_id, cleanup, config, warnings) do
    case SSHKey.maybe_cleanup(key_id, cleanup, config) do
      :ok -> warnings
      {:error, reason} -> ["ssh_key_cleanup_failed=#{inspect(reason)}" | warnings]
    end
  end

  # -- Private: Helpers ------------------------------------------------------

  defp sanitize_hostname(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
    |> String.slice(0, 63)
  end

  defp resolve_image(image) when is_integer(image), do: Integer.to_string(image)
  defp resolve_image(image) when is_binary(image), do: image

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_warnings([]), do: nil
  defp normalize_warnings(warnings), do: Enum.reverse(warnings) |> Enum.uniq()

  defp emit_progress(opts, stage, metadata) do
    case Keyword.get(opts, :on_progress) do
      fun when is_function(fun, 2) -> fun.(stage, metadata)
      _ -> :ok
    end
  end
end
