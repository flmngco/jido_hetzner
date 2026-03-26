defmodule Jido.Hetzner.API do
  @moduledoc """
  Thin HTTP client for the Hetzner Cloud REST API.

  All functions take a `config` map that must include `:api_token`.
  Uses `Req` for HTTP requests.
  """

  @base_url "https://api.hetzner.cloud/v1"

  # -- Servers ---------------------------------------------------------------

  @doc "Create a server. POST /servers"
  @spec create_server(map(), map()) :: {:ok, map()} | {:error, term()}
  def create_server(params, config) do
    post("/servers", params, config)
  end

  @doc "Get a server by ID. GET /servers/{id}"
  @spec get_server(integer() | String.t(), map()) :: {:ok, map()} | {:error, term()}
  def get_server(server_id, config) do
    get("/servers/#{server_id}", config)
  end

  @doc "Delete a server by ID. DELETE /servers/{id}"
  @spec delete_server(integer() | String.t(), map()) :: {:ok, map()} | {:error, term()}
  def delete_server(server_id, config) do
    delete("/servers/#{server_id}", config)
  end

  @doc "List servers with optional query params. GET /servers"
  @spec list_servers(map(), map()) :: {:ok, map()} | {:error, term()}
  def list_servers(params, config) do
    get("/servers", config, params: params)
  end

  # -- SSH Keys --------------------------------------------------------------

  @doc "Create an SSH key. POST /ssh_keys"
  @spec create_ssh_key(map(), map()) :: {:ok, map()} | {:error, term()}
  def create_ssh_key(params, config) do
    post("/ssh_keys", params, config)
  end

  @doc "Get an SSH key by ID. GET /ssh_keys/{id}"
  @spec get_ssh_key(integer() | String.t(), map()) :: {:ok, map()} | {:error, term()}
  def get_ssh_key(key_id, config) do
    get("/ssh_keys/#{key_id}", config)
  end

  @doc "Delete an SSH key by ID. DELETE /ssh_keys/{id}"
  @spec delete_ssh_key(integer() | String.t(), map()) :: {:ok, map()} | {:error, term()}
  def delete_ssh_key(key_id, config) do
    delete("/ssh_keys/#{key_id}", config)
  end

  @doc "List SSH keys with optional query params. GET /ssh_keys"
  @spec list_ssh_keys(map(), map()) :: {:ok, map()} | {:error, term()}
  def list_ssh_keys(params, config) do
    get("/ssh_keys", config, params: params)
  end

  # -- Actions ---------------------------------------------------------------

  @doc "Get an action by ID. GET /actions/{id}"
  @spec get_action(integer() | String.t(), map()) :: {:ok, map()} | {:error, term()}
  def get_action(action_id, config) do
    get("/actions/#{action_id}", config)
  end

  # -- HTTP helpers ----------------------------------------------------------

  defp get(path, config, opts \\ []) do
    config
    |> build_req(path)
    |> Req.merge(opts)
    |> Req.get()
    |> handle_response()
  end

  defp post(path, body, config) do
    config
    |> build_req(path)
    |> Req.post(json: body)
    |> handle_response()
  end

  defp delete(path, config) do
    config
    |> build_req(path)
    |> Req.delete()
    |> handle_response()
  end

  defp build_req(config, path) do
    base = Map.get(config, :base_url, @base_url)
    token = Map.fetch!(config, :api_token)
    max_retries = Map.get(config, :max_retries, 3)

    Req.new(
      url: "#{base}#{path}",
      headers: [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ],
      retry: :transient,
      max_retries: max_retries,
      retry_delay: &retry_delay/1
    )
  end

  defp retry_delay(attempt) do
    trunc(:math.pow(2, attempt) * 1_000)
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 401, body: body}}) do
    {:error, {:unauthorized, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 404, body: body}}) do
    {:error, {:not_found, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 409, body: body}}) do
    {:error, {:conflict, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 423, body: body}}) do
    {:error, {:locked, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 429, body: body}}) do
    {:error, {:rate_limited, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status >= 500 do
    {:error, {:server_error, status, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, {:transport_error, reason}}
  end
end
