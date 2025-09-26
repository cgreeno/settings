# Kafka at Fresha

## Principles

- **Outbox Pattern**: Use for producing events from database transactions
- **Debezium**: Automatically publishes outbox events to Kafka
- **Idempotency**: All consumers must handle duplicate messages
- **DLQ**: Failed messages go to dead letter queue for investigation
- **Health Checks**: Every consumer registers with Heartbeats

## Libraries

```elixir
{:kafkaesque, "~> 3.2", organization: "fresha"},
{:kafkaesque_addons, "~> 1.0", organization: "fresha"},
```

## Proto Structure

```
proto/definitions/fresha/{service}/protobuf/
├── events/
│   └── {event_name}/v1/{event_name}.proto
├── commands/
│   └── {command_name}/v1/{command_name}.proto
├── commands/
│   └── {command_name}/v1/{command_name}.proto
└── kafka/
    └── {topic_name}/events/v1/envelope.proto
```

## Outbox Table Setup

```sql
CREATE TABLE outbox_events (
  uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partition_key VARCHAR(255) NOT NULL,
  event_type VARCHAR(255) NOT NULL,
  topic_name VARCHAR NOT NULL,
  proto_payload BYTEA NOT NULL,
  trace_context VARCHAR,
  timestamp TIMESTAMP NOT NULL
);

CREATE INDEX idx_outbox_events_timestamp ON outbox_events(timestamp);
```

## Producer Pattern (Outbox)

**When to use**: Emitting events within database transactions

```elixir
# Schema
schema "outbox_events" do
  field :uuid, Ecto.UUID, primary_key: true
  field :partition_key, :string
  field :event_type, :string
  field :topic_name, :string
  field :proto_payload, :binary
  field :trace_context, :string
  field :timestamp, :utc_datetime_usec
end

# Usage in Command
Multi.insert(multi, :outbox_event,
  OutboxEvent.changeset(%OutboxEvent{}, %{
    partition_key: provider_id,
    event_type: "add_on_enabled",
    topic_name: "add-ons.add-on-events-v1",
    proto_payload: encoded_protobuf_data,
    trace_context: current_trace_context(),
    timestamp: DateTime.utc_now()
  })
)
```

## Consumer Pattern

**When to use**: Processing events from other services

```elixir
defmodule MyService.Events.EventName.Supervisor do
  @consumer_group "my_service.event_name_consumer"

  use Kafkaesque.ConsumerSupervisor,
    consumer_group_identifier: @consumer_group,
    topics: ["source_service.topic_name"],
    dead_letter_queue: nil,
    message_handler: MyService.Events.EventName.MessageHandler

  def healthcheck, do: Heartbeats.Helpers.kafka_consumer_check(@consumer_group)
end

defmodule MyService.Events.EventName.MessageHandler do
  alias KafkaesqueAddons.Idempotency.RedisInboxStrategy.RedisClient

  use Kafkaesque.Consumer,
    commit_strategy: :sync,
    consumer_group_identifier: "my_service.event_name_consumer",
    topics_config: %{
      "source_service.topic_name" => %{
        decoder_config: {Kafkaesque.Decoders.DebeziumProtoDecoder, [schema: EventEnvelope]},
        handle_message_plugins: [
          {KafkaesqueAddons.Plugins.UUIDIdempotencyPlugin,
           strategy: KafkaesqueAddons.Idempotency.RedisInboxStrategy,
           redis_client: RedisClient}
        ],
        dead_letter_producer: nil
      }
    },
    retries: 2

  def handle_decoded_message(%{proto_payload: %{payload: {event_type, event_data}}}) do
    MyService.Commands.ProcessEvent.call(event_data)
    :ok
  end

  def handle_decoded_message(_), do: :ok
end
```

## Application Setup

```elixir
# In consumer application
def start(_type, _args) do
  children = [
    {RedisClient, redis_config()},
    MyService.Events.EventName.Supervisor
  ] ++ kafka_consumers(consume_events?)

  Supervisor.start_link(children, strategy: :one_for_one)
end

defp kafka_consumers(true), do: [MyService.Events.EventName.Supervisor]
defp kafka_consumers(_), do: []
```

## Config

```elixir
# config/dev.exs
config :kafkaesque,
  kafka_prefix: "dev",
  kafka_uris: "localhost:9092"

# config/runtime.exs
config :kafkaesque,
  kafka_prefix: System.fetch_env!("KAFKA_PREFIX"),
  kafka_uris: System.fetch_env!("KAFKA_BOOTSTRAP_BROKERS_TLS")
```

## Health Checks

```elixir
Heartbeats.register_readiness_check([
  &MyService.Events.EventName.Supervisor.healthcheck/0
])
```

---

# Fresha Platform Patterns

## Core Libraries

**Always use these Fresha-specific libraries:**

```elixir
# Observability & Monitoring
{:monitor, "~> 1.0", organization: "fresha"},
{:heartbeats, "~> 0.5", organization: "fresha"},

# Service Communication
{:rpc_client, "~> 1.0", organization: "fresha"},
{:grpc, "~> 0.6", hex: :grpc_fresha},

# Web & API
{:web_helpers, "~> 0.13.4", organization: "fresha"},
{:add_missing_auth_headers_plug, "~> 0.0.2", organization: "fresha"},

# Development & Quality
{:credo_checks, "~> 0.1.0", organization: "fresha"},
{:ecto_refresh, "~> 0.2", organization: "fresha"},

# Feature Management
{:unleash_fresha, "~> 3.0"},

# Tracing (custom forks)
{:spandex, "~> 4.1", hex: :spandex_fresha, organization: "fresha", override: true},
{:spandex_datadog, "~> 1.7.0", hex: :spandex_datadog_fresha, organization: "fresha", override: true}
```

## DataDog Monitoring Setup

**Configuration Pattern:**

```elixir
# config/config.exs
config :monitor, Monitor.Tracer,
  service: :my_service,
  adapter: SpandexDatadog.Adapter,
  disabled?: true  # dev only

config :spandex_phoenix, tracer: Monitor.Tracer
config :spandex_ecto, SpandexEcto.EctoLogger, tracer: Monitor.Tracer

# config/runtime.exs
config :monitor, Monitor.Tracer,
  service: {:system, "DD_SERVICE", default: :my_service},
  env: {:system, "DD_ENV", default: "dev"},
  local_sampling_rate: {:system, "DD_TRACE_SAMPLE_RATE"}

config :monitor, SpandexDatadog.ApiServer,
  host: {:system, "DD_AGENT_HOST", default: nil},
  port: {:system, "DD_TRACE_AGENT_PORT", default: nil, type: :integer}
```

**Application Setup:**

```elixir
def start(_type, _args) do
  Monitor.Sentry.attach_tags()
  Monitor.Ecto.trace(MyApp.Repo)

  Heartbeats.register_readiness_check([
    &MyApp.Healthchecks.repo_available/0,
    &MyApp.Healthchecks.apps_available/0
  ])

  children = [MyApp.Repo, MyApp.Endpoint]
  |> maybe_prepend_metrics_reporter()
  |> RpcClient.Client.attach_all_clients(rpc_clients)
end
```

## Testing with Mox

**Use Mox for clean testing - avoid .impl() patterns:**

```elixir
# ❌ BAD - Don't use implementation swapping
MyService.impl().do_something()

# ✅ GOOD - Use Mox in tests
# test/test_helper.exs
Mox.defmock(MyServiceMock, for: MyService.Behaviour)

# test
expect(MyServiceMock, :do_something, fn -> :ok end)

# production code - direct calls
MyService.do_something()
```

## Umbrella App Structure

```
apps/
├── my_service/              # Core domain logic
├── my_service_web/          # Public GraphQL API
├── my_service_graphql/      # Internal GraphQL API
├── my_service_rpc/          # gRPC service
├── my_service_events_consumers/  # Kafka consumers
└── my_service_worker/       # Background jobs
```

## Development Workflow

**Use Taskfile.yml with Mirrord support:**

```yaml
# Taskfile.yml
tasks:
  start-local:
    desc: Start locally with full infrastructure
    deps: [start-local-infra, get-packages]
    cmds: ["iex -S mix run --no-halt"]

  start-mirrord:
    desc: Connect to staging cluster
    env:
      MIRRORD_TARGET_CONTAINER: "deployment/my-service/container/my-service"
    cmds: ["mirrord exec --target $MIRRORD_TARGET_CONTAINER -- iex -S mix run"]
```

## Configuration Pattern

**Environment-based config:**

```elixir
# config/runtime.exs - production
config :my_app, MyApp.Repo,
  url: System.fetch_env!("DATABASE_URL")

# config/dev.exs - development
config :my_app, MyApp.Repo,
  username: "postgres",
  database: "my_app_dev",
  hostname: "localhost"
``
