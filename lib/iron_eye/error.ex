defmodule IronEye.Error do
  @moduledoc """
  An error the server described in its response body.

  `retryable` is the server's own verdict rather than an inference from the
  status code: a 429 from a spent monthly allowance is not the same wait as a
  429 from a rate limiter, and only the body tells them apart.
  """

  @type kind ::
          :unauthenticated
          | :forbidden
          | :rate_limited
          | :invalid_request
          | :not_found
          | :compliance
          | :upstream
          | :server
          | :connection

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t(),
          message: String.t(),
          retryable: boolean(),
          request_id: String.t(),
          suggested_action: String.t(),
          doc: String.t(),
          path: String.t() | nil,
          meta: map(),
          kind: kind()
        }

  defexception [
    :status,
    :path,
    code: "INTERNAL",
    message: "The request failed.",
    retryable: false,
    request_id: "-",
    suggested_action: "",
    doc: "",
    meta: %{},
    kind: :server
  ]

  @families %{
    "UNAUTHENTICATED" => :unauthenticated,
    "FORBIDDEN_SCOPE" => :forbidden,
    "PLAN_LIMITED" => :forbidden,
    "RATE_LIMITED" => :rate_limited,
    "QUOTA_EXHAUSTED" => :rate_limited,
    "TENANT_BUSY" => :rate_limited,
    "NOT_FOUND" => :not_found,
    "COMPLIANCE_REFUSED" => :compliance,
    "COLLECTION_BLOCKED" => :compliance,
    "SOURCE_NOT_CONFIGURED" => :upstream,
    "UPSTREAM_REFUSED" => :upstream,
    "UPSTREAM_THROTTLED" => :upstream,
    "INTERNAL" => :server,
    "DEPENDENCY_UNAVAILABLE" => :server,
    "SERVER_DRAINING" => :server
  }

  @doc "Builds the struct the narrowest way the response body justifies."
  @spec from_response(non_neg_integer(), term()) :: t()
  def from_response(status, %{"error" => %{"code" => code} = body}) do
    %__MODULE__{
      status: status,
      code: code,
      message: Map.get(body, "message", "The request failed."),
      retryable: Map.get(body, "retryable", false),
      request_id: Map.get(body, "request_id", "-"),
      suggested_action: Map.get(body, "suggested_action", ""),
      doc: Map.get(body, "doc", ""),
      path: Map.get(body, "path"),
      meta: Map.get(body, "meta", %{}),
      kind: Map.get(@families, code, :invalid_request)
    }
  end

  def from_response(status, _payload) do
    %__MODULE__{
      status: status,
      message: "The server returned #{status} with no error body.",
      retryable: status >= 500,
      suggested_action: "Retry, and quote the status if it persists."
    }
  end

  @doc "A transport failure, where there is no server verdict to read."
  @spec transport(term()) :: t()
  def transport(reason) do
    %__MODULE__{
      code: "CONNECTION",
      message: "The request did not reach the service: #{inspect(reason)}",
      retryable: true,
      kind: :connection
    }
  end

  @impl true
  def message(%__MODULE__{} = error) do
    "#{error.code}: #{error.message} (request_id=#{error.request_id})"
  end
end
