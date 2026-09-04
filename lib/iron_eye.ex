defmodule IronEye do
  @moduledoc """
  Official Elixir client for the IronEye document intelligence and collection API.

      client = IronEye.Client.new()               # IRONEYE_API_KEY
      {:ok, envelope} = IronEye.secrets(client, %{input: %{text: config}})
      envelope["security"]["secrets"]["secret_count"]

  Every call returns `{:ok, body}` or `{:error, %IronEye.Error{}}`. The bang
  variants are not provided on purpose: a refusal here carries a code, a retry
  verdict and a suggested action, and all three are worth matching on.

  Logging goes through `Logger` at `:debug` for each request and `:warning` for
  each retry. No credential and no payload is ever written to it.
  """

  require Logger

  alias IronEye.{Client, Error}

  @version Mix.Project.config()[:version]

  @retryable_status [408, 425, 429, 500, 502, 503, 504]

  @analysis_routes %{
    analyze: "/v1/analyze",
    extract: "/v1/extract",
    classify: "/v1/classify",
    pii: "/v1/pii/analyze",
    moderation: "/v1/moderation/analyze",
    malware: "/v1/malware/scan",
    secrets: "/v1/secrets/scan",
    validate: "/v1/validate",
    deduplicate: "/v1/deduplicate",
    invoices: "/v1/invoices/parse"
  }

  @declaration_headers %{
    legal_basis: "x-legal-basis",
    purpose: "x-purpose",
    controller: "x-controller",
    basis_evidence: "x-basis-evidence",
    special_condition: "x-special-condition",
    projection: "x-projection"
  }

  @type result :: {:ok, map()} | {:error, Error.t()}

  # -- analysis --------------------------------------------------------------

  for {name, path} <- @analysis_routes do
    @doc "POST #{path}"
    @spec unquote(name)(Client.t(), map(), keyword()) :: result()
    def unquote(name)(client, body, options \\ []) do
      headers =
        case options[:idempotency_key] do
          nil -> []
          key -> [{"idempotency-key", key}]
        end

      request(client, :post, unquote(path), json: body, headers: headers)
    end
  end

  # -- jobs ------------------------------------------------------------------

  @spec create_job(Client.t(), map()) :: result()
  def create_job(client, body), do: request(client, :post, "/v1/jobs", json: body)

  @spec job(Client.t(), String.t()) :: result()
  def job(client, job_id), do: request(client, :get, "/v1/jobs/#{URI.encode(job_id)}")

  @spec delete_job(Client.t(), String.t()) :: result()
  def delete_job(client, job_id), do: request(client, :delete, "/v1/jobs/#{URI.encode(job_id)}")

  @doc """
  Polls until the job settles.

  Nothing in the service dispatches to a callback URL, so polling is the whole
  asynchronous contract.
  """
  @spec await_job(Client.t(), String.t(), keyword()) :: result()
  def await_job(client, job_id, options \\ []) do
    interval = options[:interval] || 2_000
    deadline = System.monotonic_time(:millisecond) + (options[:timeout] || 300_000)
    poll(client, job_id, interval, deadline)
  end

  defp poll(client, job_id, interval, deadline) do
    with {:ok, record} <- job(client, job_id) do
      cond do
        record["status"] in ["completed", "failed"] ->
          {:ok, record}

        System.monotonic_time(:millisecond) + interval > deadline ->
          {:error,
           %Error{code: "TIMEOUT", message: "job #{job_id} is still #{record["status"]}"}}

        true ->
          Process.sleep(interval)
          poll(client, job_id, interval, deadline)
      end
    end
  end

  # -- collection ------------------------------------------------------------

  @spec catalogue(Client.t()) :: result()
  def catalogue(client), do: request(client, :get, "/v1/harvest/catalogue")

  @spec operations(Client.t(), String.t() | nil) :: result()
  def operations(client, platform \\ nil) do
    params = if platform, do: [platform: platform], else: []
    request(client, :get, "/v1/harvest/operations", params: params)
  end

  @spec operation(Client.t(), String.t()) :: result()
  def operation(client, op_id),
    do: request(client, :get, "/v1/harvest/operations/#{URI.encode(op_id)}")

  @doc """
  Runs one operation, addressed by its own route as the catalogue gives it:
  `/v1/harvest/reddit/subreddit`, say.

  `declaration` is required on any operation whose `personal_data` flag is true:
  the server refuses rather than assumes.
  """
  @spec collect(Client.t(), String.t(), keyword() | map(), keyword() | map()) :: result()
  def collect(client, path, params \\ [], declaration \\ []) do
    request(client, :get, path, params: params, headers: declaration_headers(declaration))
  end

  @doc "`collect/4` for the operations the registry declares as POST."
  @spec collect_post(Client.t(), String.t(), map(), keyword() | map()) :: result()
  def collect_post(client, path, params \\ %{}, declaration \\ []) do
    request(client, :post, path, json: params, headers: declaration_headers(declaration))
  end

  # -- data subject rights ---------------------------------------------------

  @spec gdpr_notice(Client.t()) :: result()
  def gdpr_notice(client), do: request(client, :get, "/v1/gdpr/notice")

  @spec erasure(Client.t(), map()) :: result()
  def erasure(client, subject), do: request(client, :post, "/v1/gdpr/erasure", json: subject)

  @spec objection(Client.t(), map()) :: result()
  def objection(client, subject), do: request(client, :post, "/v1/gdpr/objections", json: subject)

  @spec access_request(Client.t(), map()) :: result()
  def access_request(client, subject), do: request(client, :post, "/v1/gdpr/access", json: subject)

  @spec suppression(Client.t()) :: result()
  def suppression(client), do: request(client, :get, "/v1/gdpr/suppression")

  @spec unsuppress(Client.t(), String.t()) :: result()
  def unsuppress(client, subject_key),
    do: request(client, :delete, "/v1/gdpr/suppression/#{URI.encode(subject_key)}")

  # -- service ---------------------------------------------------------------

  @spec health(Client.t()) :: result()
  def health(client), do: request(client, :get, "/healthz")

  @spec ready(Client.t()) :: result()
  def ready(client), do: request(client, :get, "/readyz")

  @spec features(Client.t()) :: result()
  def features(client), do: request(client, :get, "/v1/features")

  @spec status(Client.t()) :: result()
  def status(client), do: request(client, :get, "/v1/status")

  @spec audit_head(Client.t()) :: result()
  def audit_head(client), do: request(client, :get, "/v1/audit/head")

  # -- transport -------------------------------------------------------------

  defp request(client, method, path, options \\ [], attempt \\ 0) do
    started = System.monotonic_time(:millisecond)

    result =
      Req.request(
        method: method,
        url: client.base_url <> path,
        params: options[:params] || [],
        json: options[:json],
        headers:
          [
            {"authorization", "Bearer " <> client.api_key},
            {"accept", "application/json"},
            {"user-agent", "ironeye-elixir/#{@version}"}
          ] ++ (options[:headers] || []),
        receive_timeout: client.receive_timeout,
        # Retries are handled here rather than by Req, because the decision needs
        # the `retryable` flag out of the body and not just the status code.
        retry: false,
        decode_body: true
      )

    case result do
      {:ok, response} ->
        interpret(client, method, path, options, attempt, response, started)

      {:error, _reason} when attempt < client.max_retries ->
        pause(attempt, nil, "CONNECTION", path)
        request(client, method, path, options, attempt + 1)

      {:error, reason} ->
        {:error, Error.transport(reason)}
    end
  end

  defp interpret(client, method, path, options, attempt, response, started) do
    Logger.debug(fn ->
      "ironeye #{method} #{path} -> #{response.status} in " <>
        "#{System.monotonic_time(:millisecond) - started}ms " <>
        "(request_id=#{header(response, "x-request-id")})"
    end)

    if response.status < 400 do
      {:ok, response.body}
    else
      error = Error.from_response(response.status, response.body)

      if attempt < client.max_retries and error.retryable and
           response.status in @retryable_status do
        pause(attempt, header(response, "retry-after"), error.code, path)
        request(client, method, path, options, attempt + 1)
      else
        {:error, error}
      end
    end
  end

  # Retry-After is the server's own number, so it wins over the backoff curve.
  defp pause(attempt, retry_after, code, path) do
    milliseconds =
      case Integer.parse(retry_after || "") do
        {seconds, ""} when seconds > 0 -> seconds * 1_000
        _ -> trunc(250 * :math.pow(2, attempt)) + :rand.uniform(250)
      end

    Logger.warning("ironeye #{path} retrying after #{code} in #{milliseconds}ms")
    Process.sleep(milliseconds)
  end

  defp header(response, name) do
    case Req.Response.get_header(response, name) do
      [value | _] -> value
      _ -> "-"
    end
  end

  defp declaration_headers(declaration) do
    declaration
    |> Enum.flat_map(fn {key, value} ->
      case {Map.get(@declaration_headers, key), value} do
        {nil, _} -> []
        {_, nil} -> []
        {name, value} -> [{name, to_string(value)}]
      end
    end)
  end

  @doc false
  def pipe_dream do
    """
    |> observe
    |> derive
    |> infer
    |> validate
    |> refuse_loudly

      ...forged at Direct Softworks.
    """
  end
end
