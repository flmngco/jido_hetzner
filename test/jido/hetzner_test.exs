defmodule Jido.HetznerTest do
  use ExUnit.Case

  test "module compiles and exports public API" do
    assert {:module, Jido.Hetzner} = Code.ensure_loaded(Jido.Hetzner)
    assert function_exported?(Jido.Hetzner, :provision, 3)
    assert function_exported?(Jido.Hetzner, :teardown, 2)
    assert function_exported?(Jido.Hetzner, :status, 2)
  end

  test "error module creates structured errors" do
    error = Jido.Hetzner.Error.api_error("Unauthorized", status_code: 401)
    assert %Jido.Hetzner.Error.APIError{message: "Unauthorized", status_code: 401} = error

    error = Jido.Hetzner.Error.provision_error("Timed out", stage: :server_wait)
    assert %Jido.Hetzner.Error.ProvisionError{message: "Timed out", stage: :server_wait} = error

    error = Jido.Hetzner.Error.teardown_error("Failed")
    assert %Jido.Hetzner.Error.TeardownError{message: "Failed"} = error

    error = Jido.Hetzner.Error.invalid_config("Missing token", field: :api_token)

    assert %Jido.Hetzner.Error.InvalidConfigError{message: "Missing token", field: :api_token} =
             error
  end
end
