# IronEye for Elixir

The official Elixir client for the [IronEye](https://ironeye.org) API: document
analysis over bytes you send, and normalised collection from public sources,
behind one key.

```elixir
{:ironeye, "~> 1.0"}
```

## Features

- Every analysis route, the async job path with `await_job/3`, the collection
  catalogue and the data-subject-rights endpoints.
- `{:ok, body} | {:error, %IronEye.Error{}}` on every call, the error carrying a
  `:kind` to match on.
- Retries on the server's own `retryable` flag, honouring `Retry-After`.
- Built on `Req`. The client is a plain struct, so your supervision tree owns
  the process.
- `Logger`. No credential, no payload.

Full documentation, including every endpoint and every option, is at
**https://ironeye.org/docs/sdk/elixir**.

---

Direct Softworks · [MIT](LICENSE) · issues and pull requests welcome
