# Elixir Standards Examples

This file contains examples of Elixir coding standards and best practices.

## Module Documentation

```elixir
defmodule MyApp.UserService do
  @moduledoc """
  Service module for managing user operations.

  This module provides functions for creating, updating, and retrieving
  user information from the database.
  """

  # Module content here
end
```

## Function Documentation

```elixir
@doc """
Creates a new user with the given attributes.

## Parameters

  * `attrs` - A map containing user attributes

## Returns

  * `{:ok, %User{}}` - Successfully created user
  * `{:error, %Ecto.Changeset{}}` - Validation errors

## Examples

    iex> create_user(%{name: "John", email: "john@example.com"})
    {:ok, %User{name: "John", email: "john@example.com"}}

    iex> create_user(%{name: ""})
    {:error, %Ecto.Changeset{}}
"""
def create_user(attrs) do
  # Implementation here
end
```

## Pattern Matching

```elixir
# Good - Clear pattern matching
def handle_response({:ok, data}) do
  process_data(data)
end

def handle_response({:error, reason}) do
  log_error(reason)
  {:error, reason}
end

# Good - Guard clauses
def calculate_discount(amount) when amount > 100, do: amount * 0.1
def calculate_discount(_amount), do: 0
```

## Pipe Operator

```elixir
# Good - Clear data transformation pipeline
def process_user_data(user_id) do
  user_id
  |> fetch_user()
  |> validate_user()
  |> transform_data()
  |> save_result()
end
```

## Error Handling

```elixir
# Good - Use with for multiple operations that can fail
def create_user_with_profile(user_attrs, profile_attrs) do
  with {:ok, user} <- create_user(user_attrs),
       {:ok, profile} <- create_profile(user.id, profile_attrs) do
    {:ok, %{user: user, profile: profile}}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

## Naming Conventions

```elixir
# Good - Clear, descriptive names
defmodule MyApp.UserController do
  def create_user_account(params) do
    # Implementation
  end

  def get_user_by_email(email) do
    # Implementation
  end
end

# Good - Boolean functions end with ?
def active_user?(user) do
  user.status == :active
end

# Good - Dangerous functions end with !
def delete_user!(user_id) do
  # Implementation that raises on error
end
```


# Fresha Elixir Coding Standards

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

### Basic Outbox Table

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

### Advanced: Week-based Partitioned Outbox

**Use for high-volume event production with automatic cleanup:**

```sql
-- Create extension for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create enum type for valid topic names
CREATE TYPE outbox_events_topic_names AS ENUM (
  'my-service.domain-events-v1',
  'my-service.notifications-v1'
);

-- Create partitioned outbox table
CREATE TABLE outbox_events (
  uuid UUID DEFAULT gen_random_uuid() NOT NULL,
  partition_key VARCHAR NOT NULL,
  topic_name outbox_events_topic_names NOT NULL,
  event_type VARCHAR NOT NULL,
  proto_payload BYTEA NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  week_mod INT NOT NULL,
  trace_context TEXT,
  PRIMARY KEY (uuid, week_mod),
  CONSTRAINT check_week_mod CHECK (week_mod >= 0 AND week_mod < 4)
) PARTITION BY LIST (week_mod);

-- Create 4 weekly partitions
CREATE TABLE outbox_events_p0 PARTITION OF outbox_events FOR VALUES IN (0);
ALTER TABLE outbox_events_p0 REPLICA IDENTITY DEFAULT;

CREATE TABLE outbox_events_p1 PARTITION OF outbox_events FOR VALUES IN (1);
ALTER TABLE outbox_events_p1 REPLICA IDENTITY DEFAULT;

CREATE TABLE outbox_events_p2 PARTITION OF outbox_events FOR VALUES IN (2);
ALTER TABLE outbox_events_p2 REPLICA IDENTITY DEFAULT;

CREATE TABLE outbox_events_p3 PARTITION OF outbox_events FOR VALUES IN (3);
ALTER TABLE outbox_events_p3 REPLICA IDENTITY DEFAULT;

CREATE INDEX idx_outbox_events_timestamp ON outbox_events(timestamp);
```

## Producer Pattern (Outbox)

**When to use**: Emitting events within database transactions

```elixir
# Basic Schema
schema "outbox_events" do
  field :uuid, Ecto.UUID, primary_key: true
  field :partition_key, :string
  field :event_type, :string
  field :topic_name, :string
  field :proto_payload, :binary
  field :trace_context, :string
  field :timestamp, :utc_datetime_usec
end

# Advanced Schema (with partitioning)
@primary_key false
schema "outbox_events" do
  field :uuid, Ecto.UUID, primary_key: true
  field :partition_key, :string
  field :event_type, :string
  field :topic_name, :string
  field :proto_payload, :binary
  field :week_mod, :integer
  field :trace_context, :string
  field :timestamp, :utc_datetime_usec
end

# Partition management functions
def week_mod(timestamp) do
  timestamp
  |> Timex.iso_week()
  |> elem(1)
  |> rem(4)
end

def partition_to_truncate(timestamp) do
  case week_mod(timestamp) do
    0 -> "outbox_events_p2"
    1 -> "outbox_events_p3"
    2 -> "outbox_events_p0"
    3 -> "outbox_events_p1"
  end
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

## Event-Driven Architecture (Domain Events)

**Alternative to Outbox**: For domain events that don't require external publishing.

```elixir
# EventUtils module for domain events
defmodule MyService.EventUtils do
  alias MyService.Schemas.DomainEvent

  def create_domain_event(entity_id, event_name, payload \\ %{}) do
    case DomainEvent.create_event(entity_id, event_name, payload) do
      {:ok, event} ->
        {:ok, event}
      {:error, reason} ->
        Logger.error("Failed to create domain event",
          entity_id: entity_id,
          event_name: event_name,
          reason: inspect(reason)
        )
        {:error, :failed_to_create_domain_event}
    end
  end
end

# Usage in Multi transaction
Ecto.Multi.new()
|> Ecto.Multi.update(:entity, entity_changeset)
|> Ecto.Multi.run(:event, fn _repo, %{entity: updated_entity} ->
  EventUtils.create_domain_event(
    updated_entity.id,
    :entity_updated,
    %{field: updated_entity.field}
  )
end)
|> Repo.transaction()
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
    decoders: %{
      "source_service.topic_name" => %{
        decoder: Kafkaesque.Decoders.DebeziumProtoDecoder,
        opts: [schema: EventEnvelope]
      }
    },
    handle_message_plugins: [
      {KafkaesqueAddons.Plugins.UUIDIdempotencyPlugin,
       strategy: KafkaesqueAddons.Idempotency.RedisInboxStrategy,
       redis_client: RedisClient}
    ],
    retries: 2

  def handle_decoded_message(%{proto_payload: %{payload: {event_type, event_data}}}) do
    MyService.Commands.ProcessEvent.call(event_data)
    :ok
  end

  def handle_decoded_message(_), do: :ok

  # Environment-specific error handling
  defp handle_not_found_error(entity_id) do
    if test_env?() do
      Logger.info("Entity not found, skipping in test environment", entity_id: entity_id)
      :ok
    else
      Logger.error("Entity not found in production", entity_id: entity_id)
      # Crash and retry - might be a race condition
      {:error, :entity_not_found}
    end
  end

  defp test_env? do
    Application.get_env(:my_service, :environment) == :test
  end
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
{:monitor, "~> 1.1", organization: "fresha"},
{:heartbeats, "~> 0.7", organization: "fresha"},

# Service Communication
{:rpc_client, "~> 1.4.1", organization: "fresha"},
{:grpc, "~> 0.6", hex: :grpc_fresha},

# Web & API
{:web_helpers, "~> 0.13.4", organization: "fresha"},
{:add_missing_auth_headers_plug, "~> 0.0.2", organization: "fresha"},
{:finance_auth_plug, "~> 0.3.1", organization: "fresha"},

# GraphQL & API
{:absinthe, "~> 1.7"},
{:absinthe_phoenix, "~> 2.0.0"},
{:jabbax, "~> 1.0"},

# Background Processing
{:oban, "~> 2.19"},

# Domain Libraries
{:money, "~> 1.12"},
{:eddien, "~> 1.18.0", organization: "fresha"},

# Development & Quality
{:credo_checks, "~> 0.1.0", organization: "fresha"},
{:ecto_refresh, "~> 0.2", organization: "fresha"},
{:mimic, "~> 1.11", only: :test},

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

## Background Jobs (Oban)

**Use Oban for async processing and scheduled tasks:**

```elixir
# config/config.exs
config :my_service, ObanProcessor,
  name: Processor.Oban,
  plugins: [
    {Oban.Plugins.Pruner,
     max_age: _one_week_in_seconds = 60 * 60 * 24 * 7,
     interval: _one_day_in_seconds = 60 * 60 * 24},
    Oban.Plugins.Lifeline
  ],
  queues: [default: 10, high_priority: 5],
  repo: MyService.Repo

config :my_service, ObanStorer,
  name: Storer.Oban,
  queues: false,  # No processing, just storage
  repo: MyService.Repo

# Runtime configuration
config :my_service,
  oban_processor_enabled: System.get_env("OBAN_PROCESSOR_ENABLED", "0") in ["1", "true"],
  oban_storer_enabled: System.get_env("OBAN_STORER_ENABLED", "0") in ["1", "true"]
```

**Application setup:**

```elixir
defp maybe_attach_oban(children) do
  children
  |> maybe_attach_oban_processor()
  |> maybe_attach_oban_storer()
end

defp maybe_attach_oban_processor(children) do
  case Application.fetch_env!(:my_service, :oban_processor_enabled) do
    true -> children ++ [{Oban, Application.fetch_env!(:my_service, ObanProcessor)}]
    false -> children
  end
end

defp maybe_attach_oban_storer(children) do
  case Application.fetch_env!(:my_service, :oban_storer_enabled) do
    true -> children ++ [{Oban, Application.fetch_env!(:my_service, ObanStorer)}]
    false -> children
  end
end
```

## Umbrella App Structure

```
apps/
├── my_service/              # Core domain logic
├── my_service_web/          # Public GraphQL API
├── my_service_graphql/      # Internal GraphQL API
├── my_service_rpc/          # gRPC service
├── my_service_events_consumers/  # Kafka consumers
├── my_service_runner/       # CLI/migration runner
└── my_service_worker/       # Background jobs (deprecated - use main app with Oban)
```

## Release Configuration

**Multiple release targets for umbrella apps:**

```elixir
# mix.exs
releases: [
  my_service_web: [
    applications: [my_service_web: :permanent]
  ],
  my_service_rpc: [
    applications: [my_service_rpc: :permanent]
  ],
  my_service_events_consumers: [
    applications: [my_service_events_consumers: :permanent]
  ],
  my_service_worker: [
    applications: [my_service: :permanent]  # Core app for background jobs
  ],
  my_service_runner: [
    applications: [my_service_runner: :permanent]
  ]
]
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
`
