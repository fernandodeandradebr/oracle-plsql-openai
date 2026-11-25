# Oracle PL/SQL + OpenAI

A small, English-language reference project for calling an OpenAI model from Oracle PL/SQL. It accompanies the idea of modernizing legacy applications incrementally: add an integration boundary, deliver one capability, measure it, then move to the next.

**Status:** reviewed against documentation, but not compiled or executed against an Oracle instance in this authoring session. Treat this as a reference implementation to validate in a test database, not a production-certified library.

## Two independent integration options

| Option | Purpose | Timeout control in this project |
| --- | --- | --- |
| `openai_chat` using `UTL_HTTP` | Direct HTTPS request to OpenAI Chat Completions | Explicit HTTP read timeout |
| `DBMS_CLOUD_AI.GENERATE` | Oracle-managed provider integration through an AI profile | No undocumented profile timeout attribute |

The direct HTTP example targets Oracle 19c and does **not** depend on DBMS_CLOUD_AI or RU 19.30. The optional Cloud AI example requires the package to be installed and configured; Oracle documents self-managed 19c support starting at RU 19.30. Capability and model support vary by environment.

The database can remain on premises, including Exadata. The model request goes to the external provider; the model is not running inside the database.

## Files

- `install.sql`: installs the direct-call procedure and checks compilation errors.
- `sql/openai_chat.sql`: invoker-rights procedure, JSON escaping, UTF-8 byte length, timeout handling, bounded response and cleanup.
- `sql/configure_network.sql`: DBA-reviewed ACL and wallet guidance.
- `examples/call_openai.sql`: direct call with bind variables.
- `examples/cloud_ai_profile.sql`: alternative credential/profile setup and GENERATE call.
- `tests/validation.sql`: invalid-input checks intended to run without external calls.

## Setup

1. Use an Oracle test database and a dedicated application schema.
2. Have a DBA review network ACLs, required package privileges, outbound HTTPS and trusted certificates. Edit the schema placeholder in `sql/configure_network.sql`; do not run it unchanged.
3. For self-managed databases, provision a trust wallet and configure it in the calling session when required. Autonomous environments can have different trust configuration.
4. Run `@install.sql` from a script-capable Oracle client.
5. Run `@tests/validation.sql`.
6. Choose a currently available OpenAI model compatible with Chat Completions and `max_completion_tokens`. Supply the API key and model ID through client bind variables.
7. Execute the example block, inspect the finish reason and validate the returned content before using it.

The declarations in the example initialize empty binds. Populate them **after declaration and before executing the call block**; running the whole example unchanged intentionally fails validation. The model ID is configurable rather than pinned to an aging example model. OpenAI API access/billing is separate from a ChatGPT subscription.

## Calling contract

```sql
openai_chat(
    p_api_key         => :api_key,
    p_model           => :model_id,
    p_prompt          => 'Summarize the customer incident.',
    p_response_json   => :response_json,
    p_timeout_seconds => 30
);
```

The procedure returns the **raw JSON envelope** as a temporary CLOB, including choices, completion status and usage when supplied by the API. The caller owns and must free that temporary LOB after use. The sample SQL projects at most 4,000 characters of answer text; a longer answer raises an extraction error rather than silently truncating.

Prompts are deliberately limited to 4,000 bytes. Responses are capped at 1,048,576 characters. The request asks for at most 512 completion tokens; reasoning can consume some of that budget. An empty, refused or truncated completion must be handled by the application. This is a text-only, non-streaming example; it does not implement tools, MCP, conversation history or document ingestion.

## What the timeout actually means

`UTL_HTTP.SET_TRANSFER_TIMEOUT(30)` controls HTTP response read waits. It is **not a 30-second wall-clock deadline** for DNS, connection setup, retries and the entire business operation. Successive reads can make the overall call longer.

The PL/SQL session remains occupied until the synchronous call completes or raises. A timeout or client disconnect does not prove the provider stopped processing and does not guarantee no API charge. This project does not automatically retry: after an ambiguous timeout, blind retries can duplicate processing and costs.

The procedure restores the session timeout, detailed-exception, HTTP error-check and redirect settings it changes. It rejects redirects and uses a fixed HTTPS endpoint. The caller/DBA owns wallet and proxy configuration.

Do not assume calling SET_TRANSFER_TIMEOUT before DBMS_CLOUD_AI.GENERATE changes that package's internal timeout behavior. No such assumption is made in the profile example.

## Errors and validation

| Application error | Meaning |
| --- | --- |
| -20010 | Invalid input; rejected before network access |
| -20011 | Non-2xx HTTP status (including rate limits and authentication failures) |
| -20012 | Response exceeds the local size limit |
| -20013 | HTTP transfer/read timeout |
| -20020 | Installation found Oracle compilation errors |

Other Oracle exceptions propagate. HTTP failures expose the status code rather than potentially sensitive response bodies. Detailed operational diagnostics should be added using a redacted logging policy.

Before production use, validate compilation and test: Unicode/quotes/newlines; a real successful call; invalid credentials; inaccessible model; 429/5xx responses; delayed reads; malformed or oversized responses; refusal/truncation; and cleanup/session-setting restoration after both success and failure. Use controlled test infrastructure for failure cases rather than intentionally overloading the provider. The included validation script is not a substitute for these integration checks.

## Architecture: renovating with the shop open

A package or service can form an anti-corruption layer **when it translates and validates contracts**, shielding callers from provider-specific payloads and legacy semantics. An HTTP wrapper alone is only a transport boundary. Keep business rules and output validation in an explicit application layer.

Incremental replacement of legacy capabilities can follow the Strangler Fig pattern. It does not require migrating the entire database at once. For high volume, prefer a queue and a bounded worker pool: the worker waits for the model while the user's transaction remains short.

Avoid keeping business locks open during inference. Measure end-to-end processing time, answer quality, human rework and total cost per item. LLM calls can help classify, summarize or extract information; they do not inherently accelerate joins or numerical SQL workloads.

## Secrets and data

Never commit keys, wallet files or production payloads. Obtain keys at runtime from a secret manager or a controlled client; exclude bind values from SQL tracing and application logs. Restrict EXECUTE access and outbound network permissions. The API receives the prompt, so minimize data and apply your organization's disclosure rules. `store: false` is not a guarantee of zero retention across all provider policies.

For production, consider an internal service that centralizes secrets, concurrency, retries, deadlines and observability. This project intentionally contains no secret storage mechanism and no database COMMIT/ROLLBACK decisions for the caller.

## Official references

- [Oracle UTL_HTTP](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/UTL_HTTP.html)
- [Oracle DBMS_CLOUD_AI](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/dbms_cloud_ai1.html)
- [Oracle RU 19.30](https://docs.oracle.com/en/database/oracle/oracle-database/19/newft/ru-19-30.html)
- [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- [Anti-corruption layer](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer)
- [Strangler Fig](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig)
