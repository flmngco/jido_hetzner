defmodule Jido.Hetzner.APITest do
  use ExUnit.Case, async: false

  alias Jido.Hetzner.API

  @config %{api_token: "test-token-123", max_retries: 0}

  setup do
    bypass = Bypass.open()
    config = Map.put(@config, :base_url, "http://localhost:#{bypass.port}/v1")
    {:ok, bypass: bypass, config: config}
  end

  describe "create_server/2" do
    test "201 success", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/servers", fn conn ->
        assert_auth_header(conn)
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["name"] == "test-server"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          201,
          Jason.encode!(%{
            server: %{id: 42, name: "test-server", status: "initializing"},
            action: %{id: 1, status: "running"}
          })
        )
      end)

      assert {:ok, %{"server" => %{"id" => 42}}} =
               API.create_server(%{name: "test-server"}, config)
    end

    test "401 unauthorized", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/servers", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{error: %{code: "unauthorized"}}))
      end)

      assert {:error, {:unauthorized, _}} = API.create_server(%{name: "test"}, config)
    end
  end

  describe "get_server/2" do
    test "200 success", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/servers/42", fn conn ->
        assert_auth_header(conn)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{server: %{id: 42, status: "running"}}))
      end)

      assert {:ok, %{"server" => %{"id" => 42}}} = API.get_server(42, config)
    end

    test "404 not found", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/servers/999", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{error: %{code: "not_found"}}))
      end)

      assert {:error, {:not_found, _}} = API.get_server(999, config)
    end
  end

  describe "delete_server/2" do
    test "200 success", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/v1/servers/42", fn conn ->
        assert_auth_header(conn)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{action: %{id: 2, status: "running"}}))
      end)

      assert {:ok, _} = API.delete_server(42, config)
    end
  end

  describe "list_servers/2" do
    test "200 with label selector", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/servers", fn conn ->
        assert_auth_header(conn)
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["label_selector"] == "jido.managed_by=jido-hetzner"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{servers: []}))
      end)

      assert {:ok, %{"servers" => []}} =
               API.list_servers(%{label_selector: "jido.managed_by=jido-hetzner"}, config)
    end
  end

  describe "SSH key operations" do
    test "create_ssh_key/2", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/ssh_keys", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(201, Jason.encode!(%{ssh_key: %{id: 10, name: "jido-ssh-key"}}))
      end)

      assert {:ok, %{"ssh_key" => %{"id" => 10}}} =
               API.create_ssh_key(
                 %{name: "jido-ssh-key", public_key: "ssh-ed25519 AAAA..."},
                 config
               )
    end

    test "list_ssh_keys/2", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/ssh_keys", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ssh_keys: []}))
      end)

      assert {:ok, %{"ssh_keys" => []}} = API.list_ssh_keys(%{name: "jido-ssh-key"}, config)
    end

    test "delete_ssh_key/2 404", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/v1/ssh_keys/10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{error: %{code: "not_found"}}))
      end)

      assert {:error, {:not_found, _}} = API.delete_ssh_key(10, config)
    end
  end

  describe "error handling" do
    test "429 rate limited", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/servers/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(%{error: %{code: "rate_limit_exceeded"}}))
      end)

      assert {:error, {:rate_limited, _}} = API.get_server(1, config)
    end

    test "500 server error", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/servers/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: %{code: "server_error"}}))
      end)

      assert {:error, {:server_error, 500, _}} = API.get_server(1, config)
    end
  end

  defp assert_auth_header(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer test-token-123"] -> :ok
      other -> flunk("Expected Bearer token, got: #{inspect(other)}")
    end
  end
end
