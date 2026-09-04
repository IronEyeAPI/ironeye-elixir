defmodule IronEye.Client do
  @moduledoc """
  Client configuration.

  A client is a plain struct: build one, hand it around, and let the supervision
  tree own whatever process makes the call. Nothing here holds state.
  """

  @default_base_url "https://ironeye.org"

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          receive_timeout: pos_integer(),
          max_retries: non_neg_integer()
        }

  @enforce_keys [:api_key]
  defstruct [
    :api_key,
    base_url: @default_base_url,
    receive_timeout: 60_000,
    max_retries: 2
  ]

  @doc """
  Builds a client.

  The key comes from `:api_key` or from `IRONEYE_API_KEY`; the base URL from
  `:base_url`, `IRONEYE_BASE_URL`, or the public host.
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    api_key =
      options[:api_key] || System.get_env("IRONEYE_API_KEY") ||
        raise ArgumentError, "an API key is required: pass :api_key or set IRONEYE_API_KEY"

    base_url =
      options[:base_url] || System.get_env("IRONEYE_BASE_URL") || @default_base_url

    %__MODULE__{
      api_key: api_key,
      base_url: String.trim_trailing(base_url, "/"),
      receive_timeout: options[:receive_timeout] || 60_000,
      max_retries: options[:max_retries] || 2
    }
  end
end

defimpl Inspect, for: IronEye.Client do
  import Inspect.Algebra

  def inspect(client, _opts) do
    key =
      case client.api_key do
        <<head::binary-size(9), _::binary>> -> head <> "..."
        _ -> "..."
      end

    concat([
      "#IronEye<",
      client.base_url,
      " key=",
      key,
      " |> let it crash, never leak>"
    ])
  end
end
