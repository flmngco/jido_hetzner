defmodule Jido.Hetzner.Error do
  @moduledoc """
  Centralized error handling for Jido Hetzner using Splode.

  ## Structure

  * **Error classes** (for Splode classification): `Invalid`, `API`, `Provision`, `Internal`.
  * **Concrete exception structs** (for raising/matching): `InvalidConfigError`,
    `APIError`, `ProvisionError`, `TeardownError`, `InternalError`.

  ## Error Classes

  - `:invalid` - Configuration validation errors
  - `:api` - Hetzner Cloud API errors (HTTP-level)
  - `:provision` - Provisioning lifecycle errors
  - `:internal` - Unexpected internal errors

  ## Usage

      # Config validation error
      Error.invalid_config("API token is required", field: :api_token)

      # API error
      Error.api_error("Unauthorized", status_code: 401)

      # Provisioning error
      Error.provision_error("Server creation failed", stage: :server_create, details: %{reason: reason})
  """

  use Splode,
    error_classes: [
      invalid: Invalid,
      api: API,
      provision: Provision,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  defmodule Invalid do
    @moduledoc "Invalid input/configuration error class for Splode."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule API do
    @moduledoc "Hetzner Cloud API error class for Splode."
    use Splode.ErrorClass, class: :api
  end

  defmodule Provision do
    @moduledoc "Provisioning lifecycle error class for Splode."
    use Splode.ErrorClass, class: :provision
  end

  defmodule Internal do
    @moduledoc "Internal/unexpected error class for Splode."
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      defexception [:message, :details]

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  # Concrete exception structs

  defmodule InvalidConfigError do
    @moduledoc "Error for invalid configuration parameters."
    @type t :: %__MODULE__{message: String.t(), field: atom() | nil, details: map()}
    defexception [:message, :field, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid configuration"),
        field: Keyword.get(opts, :field),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule APIError do
    @moduledoc "Error for Hetzner Cloud API failures."
    @type t :: %__MODULE__{
            message: String.t(),
            status_code: integer() | nil,
            error_code: String.t() | nil,
            details: map()
          }
    defexception [:message, :status_code, :error_code, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Hetzner API error"),
        status_code: Keyword.get(opts, :status_code),
        error_code: Keyword.get(opts, :error_code),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ProvisionError do
    @moduledoc "Error for provisioning lifecycle failures."
    @type t :: %__MODULE__{message: String.t(), stage: atom() | nil, details: map()}
    defexception [:message, :stage, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Provisioning failed"),
        stage: Keyword.get(opts, :stage),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TeardownError do
    @moduledoc "Error for teardown failures."
    @type t :: %__MODULE__{message: String.t(), details: map()}
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Teardown failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures."
    @type t :: %__MODULE__{message: String.t(), details: map()}
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  # Convenience constructors

  @doc "Creates an invalid configuration error."
  @spec invalid_config(String.t(), keyword()) :: InvalidConfigError.t()
  def invalid_config(message, opts \\ []) do
    InvalidConfigError.exception(Keyword.put(opts, :message, message))
  end

  @doc "Creates a Hetzner API error."
  @spec api_error(String.t(), keyword()) :: APIError.t()
  def api_error(message, opts \\ []) do
    APIError.exception(Keyword.put(opts, :message, message))
  end

  @doc "Creates a provisioning error."
  @spec provision_error(String.t(), keyword()) :: ProvisionError.t()
  def provision_error(message, opts \\ []) do
    ProvisionError.exception(Keyword.put(opts, :message, message))
  end

  @doc "Creates a teardown error."
  @spec teardown_error(String.t(), keyword()) :: TeardownError.t()
  def teardown_error(message, opts \\ []) do
    TeardownError.exception(Keyword.put(opts, :message, message))
  end

  @doc "Creates an internal error."
  @spec internal_error(String.t(), keyword()) :: InternalError.t()
  def internal_error(message, opts \\ []) do
    InternalError.exception(Keyword.put(opts, :message, message))
  end
end
