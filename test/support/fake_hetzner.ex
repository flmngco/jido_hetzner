defmodule FakeHetzner do
  @moduledoc """
  Mock Hetzner Cloud API module for testing.

  Uses persistent_term to track calls and return canned responses.
  Simulates server status transitions: initializing → running.
  """

  @doc "Set up the fake for a test. Call in `setup`."
  def setup do
    :persistent_term.put({__MODULE__, :calls}, [])
    :persistent_term.put({__MODULE__, :servers}, %{})
    :persistent_term.put({__MODULE__, :ssh_keys}, %{})
    :persistent_term.put({__MODULE__, :next_id}, 1000)
    :persistent_term.put({__MODULE__, :overrides}, %{})
    :ok
  end

  @doc "Clean up persistent terms. Call in `on_exit`."
  def teardown do
    for key <- [:calls, :servers, :ssh_keys, :next_id, :overrides] do
      :persistent_term.erase({__MODULE__, key})
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc "Get recorded API calls."
  def calls do
    :persistent_term.get({__MODULE__, :calls}, []) |> Enum.reverse()
  end

  @doc "Override a specific function to return a custom result."
  def override(function_name, result) do
    overrides = :persistent_term.get({__MODULE__, :overrides}, %{})
    :persistent_term.put({__MODULE__, :overrides}, Map.put(overrides, function_name, result))
  end

  # -- Servers ---------------------------------------------------------------

  def create_server(params, _config) do
    record_call(:create_server, params)

    case check_override(:create_server) do
      {:override, result} ->
        result

      :none ->
        id = next_id()
        ip = "10.0.0.#{rem(id, 256)}"

        server = %{
          "id" => id,
          "name" => params[:name] || params["name"] || "test-server",
          "status" => "initializing",
          "public_net" => %{"ipv4" => %{"ip" => ip}},
          "server_type" => %{"name" => params[:server_type] || params["server_type"] || "cx22"},
          "datacenter" => %{
            "location" => %{"name" => params[:location] || params["location"] || "fsn1"}
          },
          "labels" => params[:labels] || params["labels"] || %{}
        }

        put_server(id, server)
        # Transition to running after a brief delay
        schedule_running(id)
        {:ok, %{"server" => server, "action" => %{"id" => next_id(), "status" => "running"}}}
    end
  end

  def get_server(server_id, _config) do
    record_call(:get_server, server_id)

    case check_override(:get_server) do
      {:override, result} ->
        result

      :none ->
        case get_stored_server(server_id) do
          nil -> {:error, {:not_found, %{"error" => %{"code" => "not_found"}}}}
          server -> {:ok, %{"server" => server}}
        end
    end
  end

  def delete_server(server_id, _config) do
    record_call(:delete_server, server_id)

    case check_override(:delete_server) do
      {:override, result} ->
        result

      :none ->
        delete_stored_server(server_id)
        {:ok, %{"action" => %{"id" => next_id(), "status" => "running"}}}
    end
  end

  def list_servers(params, _config) do
    record_call(:list_servers, params)

    case check_override(:list_servers) do
      {:override, result} ->
        result

      :none ->
        servers = :persistent_term.get({__MODULE__, :servers}, %{}) |> Map.values()
        {:ok, %{"servers" => servers}}
    end
  end

  # -- SSH Keys --------------------------------------------------------------

  def create_ssh_key(params, _config) do
    record_call(:create_ssh_key, params)

    case check_override(:create_ssh_key) do
      {:override, result} ->
        result

      :none ->
        id = next_id()
        name = params[:name] || params["name"] || "test-key"

        key = %{
          "id" => id,
          "name" => name,
          "public_key" => params[:public_key] || params["public_key"] || "ssh-ed25519 AAAA..."
        }

        put_ssh_key(id, key)
        {:ok, %{"ssh_key" => key}}
    end
  end

  def get_ssh_key(key_id, _config) do
    record_call(:get_ssh_key, key_id)

    case check_override(:get_ssh_key) do
      {:override, result} ->
        result

      :none ->
        case get_stored_ssh_key(key_id) do
          nil -> {:error, {:not_found, %{"error" => %{"code" => "not_found"}}}}
          key -> {:ok, %{"ssh_key" => key}}
        end
    end
  end

  def delete_ssh_key(key_id, _config) do
    record_call(:delete_ssh_key, key_id)

    case check_override(:delete_ssh_key) do
      {:override, result} ->
        result

      :none ->
        delete_stored_ssh_key(key_id)
        {:ok, %{}}
    end
  end

  def list_ssh_keys(params, _config) do
    record_call(:list_ssh_keys, params)

    case check_override(:list_ssh_keys) do
      {:override, result} ->
        result

      :none ->
        keys = :persistent_term.get({__MODULE__, :ssh_keys}, %{}) |> Map.values()
        name_filter = params[:name] || params["name"]

        filtered =
          if name_filter do
            Enum.filter(keys, &(&1["name"] == name_filter))
          else
            keys
          end

        {:ok, %{"ssh_keys" => filtered}}
    end
  end

  # -- Actions ---------------------------------------------------------------

  def get_action(action_id, _config) do
    record_call(:get_action, action_id)
    {:ok, %{"action" => %{"id" => action_id, "status" => "success"}}}
  end

  # -- Internal helpers ------------------------------------------------------

  defp record_call(function, args) do
    calls = :persistent_term.get({__MODULE__, :calls}, [])
    :persistent_term.put({__MODULE__, :calls}, [{function, args} | calls])
  end

  defp check_override(function) do
    overrides = :persistent_term.get({__MODULE__, :overrides}, %{})

    case Map.fetch(overrides, function) do
      {:ok, result} -> {:override, result}
      :error -> :none
    end
  end

  defp next_id do
    id = :persistent_term.get({__MODULE__, :next_id}, 1000)
    :persistent_term.put({__MODULE__, :next_id}, id + 1)
    id
  end

  defp put_server(id, server) do
    servers = :persistent_term.get({__MODULE__, :servers}, %{})
    :persistent_term.put({__MODULE__, :servers}, Map.put(servers, id, server))
  end

  defp get_stored_server(id) do
    :persistent_term.get({__MODULE__, :servers}, %{}) |> Map.get(id)
  end

  defp delete_stored_server(id) do
    servers = :persistent_term.get({__MODULE__, :servers}, %{})
    :persistent_term.put({__MODULE__, :servers}, Map.delete(servers, id))
  end

  defp put_ssh_key(id, key) do
    keys = :persistent_term.get({__MODULE__, :ssh_keys}, %{})
    :persistent_term.put({__MODULE__, :ssh_keys}, Map.put(keys, id, key))
  end

  defp get_stored_ssh_key(id) do
    :persistent_term.get({__MODULE__, :ssh_keys}, %{}) |> Map.get(id)
  end

  defp delete_stored_ssh_key(id) do
    keys = :persistent_term.get({__MODULE__, :ssh_keys}, %{})
    :persistent_term.put({__MODULE__, :ssh_keys}, Map.delete(keys, id))
  end

  defp schedule_running(server_id) do
    # Immediately transition to running for tests
    servers = :persistent_term.get({__MODULE__, :servers}, %{})

    case Map.get(servers, server_id) do
      nil ->
        :ok

      server ->
        updated = Map.put(server, "status", "running")
        :persistent_term.put({__MODULE__, :servers}, Map.put(servers, server_id, updated))
    end
  end
end
