# Elixir Standards & Best Practices Guide

<elixir_standards>

## Quick Reference

<quick_reference>
- **Basic Patterns**: Documentation, pattern matching, pipes, error handling
- **Testing**: Use Mimic for mocking, avoid .impl() patterns
- **Fresha Platform**: Event-driven architecture with Kafkaesque
- **Background Jobs**: Oban for async processing
- **Monitoring**: DataDog with Monitor library
</quick_reference>

---

<basic_patterns>

## Core Elixir Patterns

<documentation>
### Module & Function Documentation

**When to use**: All public modules and functions

```elixir
defmodule MyApp.UserService do
  @moduledoc """
  Service module for managing user operations.

  This module provides functions for creating, updating, and retrieving
  user information from the database.

  ## Examples

      iex> UserService.create_user(%{name: "John", email: "john@example.com"})
      {:ok, %User{name: "John", email: "john@example.com"}}
  """

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
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```
</documentation>

<pattern_matching>
### Pattern Matching & Guards

**When to use**: Function heads for different input types, guard clauses for validation

```elixir
defmodule PaymentProcessor do
  # Pattern matching on different response types
  def handle_response({:ok, %{status: "completed", amount: amount}}) do
    Logger.info("Payment completed", amount: amount)
    {:ok, :processed}
  end

  def handle_response({:ok, %{status: "pending"}}) do
    Logger.info("Payment pending")
    {:ok, :pending}
  end

  def handle_response({:error, reason}) do
    Logger.error("Payment failed", reason: reason)
    {:error, reason}
  end

  # Guard clauses for business logic
  def calculate_discount(amount) when amount > 1000, do: amount * 0.15
  def calculate_discount(amount) when amount > 500, do: amount * 0.10
  def calculate_discount(amount) when amount > 100, do: amount * 0.05
  def calculate_discount(_amount), do: 0

  # Complex pattern matching with guards
  def process_order(%{items: items, user: %{premium: true}} = order)
      when length(items) > 0 do
    order
    |> apply_premium_discount()
    |> process_items()
  end

  def process_order(%{items: items} = order) when length(items) > 0 do
    process_items(order)
  end

  def process_order(_), do: {:error, :invalid_order}
end
```
</pattern_matching>

<pipe_operator>
### Pipe Operator

**When to use**: Data transformation pipelines, avoid deeply nested function calls

```elixir
defmodule DataProcessor do
  # ✅ GOOD - Clear transformation pipeline
  def process_user_data(user_id) do
    user_id
    |> fetch_user_from_db()
    |> validate_user_status()
    |> enrich_with_profile()
    |> transform_for_api()
    |> cache_result()
  end

  # ❌ BAD - Nested function calls
  def process_user_data_bad(user_id) do
    cache_result(
      transform_for_api(
        enrich_with_profile(
          validate_user_status(
            fetch_user_from_db(user_id)
          )
        )
      )
    )
  end

  # Complex pipeline with error handling
  def process_payment_flow(payment_params) do
    with {:ok, validated} <- validate_payment(payment_params),
         {:ok, processed} <- charge_payment(validated),
         {:ok, recorded} <- record_transaction(processed),
         {:ok, _event} <- emit_payment_event(recorded) do
      {:ok, recorded}
    else
      {:error, :validation_failed} = error ->
        Logger.warn("Payment validation failed", params: payment_params)
        error

      {:error, :payment_declined} = error ->
        Logger.info("Payment declined", params: payment_params)
        error

      {:error, reason} = error ->
        Logger.error("Payment processing failed", reason: reason)
        error
    end
  end
end
```
</pipe_operator>

<error_handling>
### Error Handling Patterns

**Decision Tree**:
- Single operation that can fail → `case` statement
- Multiple operations that can fail → `with` statement
- Need to continue on some errors → pattern match in `with`

```elixir
defmodule UserAccountService do
  # Single operation - use case
  def get_user_profile(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  # Multiple operations - use with
  def create_user_with_profile(user_attrs, profile_attrs) do
    with {:ok, user} <- create_user(user_attrs),
         {:ok, profile} <- create_profile(user.id, profile_attrs),
         {:ok, _permissions} <- setup_default_permissions(user.id) do
      {:ok, %{user: user, profile: profile}}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_error, changeset}}

      {:error, :profile_creation_failed} ->
        # Cleanup user if profile creation fails
        delete_user(user.id)
        {:error, :setup_failed}

      {:error, reason} ->
        Logger.error("User setup failed", reason: reason)
        {:error, reason}
    end
  end

  # Error recovery pattern
  def get_user_with_fallback(user_id) do
    with {:error, :not_found} <- get_from_primary_db(user_id),
         {:error, :not_found} <- get_from_cache(user_id) do
      get_from_archive(user_id)
    else
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end
end
```
</error_handling>

<naming_conventions>
### Naming Conventions

**Rules**:
- Modules: PascalCase
- Functions/variables: snake_case
- Boolean functions: end with `?`
- Dangerous functions: end with `!`
- Private functions: start with `do_`

```elixir
defmodule MyApp.UserAccountManager do
  # Boolean predicate functions
  def active_user?(user), do: user.status == :active
  def premium_account?(user), do: user.tier in [:premium, :enterprise]
  def trial_expired?(user), do: Date.after?(Date.utc_today(), user.trial_end_date)

  # Dangerous functions (raise on error)
  def delete_user!(user_id) do
    user = Repo.get!(User, user_id)
    Repo.delete!(user)
  end

  def activate_account!(user_id) do
    user_id
    |> get_user!()
    |> User.activate_changeset()
    |> Repo.update!()
  end

  # Safe versions (return tuples)
  def delete_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> Repo.delete(user)
    end
  end

  # Private helper functions
  defp do_validate_email(email) do
    if String.contains?(email, "@"), do: :ok, else: {:error, :invalid_email}
  end

  defp do_send_notification(user, type) do
    # Implementation
  end
end
```
</naming_conventions>

</basic_patterns>

---

<testing_patterns>

## Testing with Mimic

<when_to_use_mimic>
**When to use Mimic**:
- Mocking external services (APIs, databases)
- Testing error conditions
- Isolating units under test
- Avoiding expensive operations in tests

**When NOT to use**:
- Testing pure functions
- Integration tests where you want real interactions
- Testing internal implementation details
</when_to_use_mimic>

```elixir
# test/test_helper.exs
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)

# Copy modules you want to mock
Mimic.copy(MyApp.ExternalApiClient)
Mimic.copy(MyApp.EmailService)
Mimic.copy(MyApp.PaymentGateway)

# test/my_app/user_service_test.exs
defmodule MyApp.UserServiceTest do
  use MyApp.DataCase, async: true
  use Mimic

  alias MyApp.UserService

  describe "create_user_with_profile/2" do
    test "creates user and sends welcome email" do
      user_attrs = %{name: "John", email: "john@example.com"}

      # Stub external service
      stub(MyApp.EmailService, :send_welcome_email, fn _email -> :ok end)

      assert {:ok, user} = UserService.create_user_with_profile(user_attrs, %{})
      assert user.name == "John"

      # Verify the email service was called
      assert_called(MyApp.EmailService.send_welcome_email("john@example.com"))
    end

    test "handles email service failure gracefully" do
      user_attrs = %{name: "John", email: "john@example.com"}

      # Mock failure scenario
      expect(MyApp.EmailService, :send_welcome_email, fn _email ->
        {:error, :service_unavailable}
      end)

      # User should still be created even if email fails
      assert {:ok, user} = UserService.create_user_with_profile(user_attrs, %{})
      assert user.name == "John"
    end

    test "validates required fields" do
      # No mocking needed for validation tests
      assert {:error, changeset} = UserService.create_user_with_profile(%{}, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "process_payment/2" do
    setup do
      user = insert(:user)
      payment_attrs = %{amount: 100, currency: "USD"}

      %{user: user, payment_attrs: payment_attrs}
    end

    test "successful payment flow", %{user: user, payment_attrs: attrs} do
      # Mock successful payment gateway response
      expect(MyApp.PaymentGateway, :charge, fn _attrs ->
        {:ok, %{id: "charge_123", status: "succeeded"}}
      end)

      expect(MyApp.EmailService, :send_receipt, fn _user, _charge ->
        :ok
      end)

      assert {:ok, result} = UserService.process_payment(user, attrs)
      assert result.charge_id == "charge_123"
      assert result.status == :completed
    end

    test "handles payment gateway errors", %{user: user, payment_attrs: attrs} do
      expect(MyApp.PaymentGateway, :charge, fn _attrs ->
        {:error, %{type: "card_error", message: "Your card was declined."}}
      end)

      assert {:error, :payment_declined} = UserService.process_payment(user, attrs)

      # Verify no receipt was sent on failure
      refute_called(MyApp.EmailService.send_receipt(user, :_))
    end
  end
end

# Property-based testing example
defmodule MyApp.CalculatorTest do
  use ExUnit.Case
  use ExUnitProperties

  property "addition is commutative" do
    check all(a <- integer(), b <- integer()) do
      assert MyApp.Calculator.add(a, b) == MyApp.Calculator.add(b, a)
    end
  end
end
```

</testing_patterns>

---

<fresha_platform>

# Fresha Platform Patterns

<core_libraries>
## Required Dependencies

**Always include these Fresha libraries**:

```elixir
# mix.exs dependencies
defp deps do
  [
    # Observability & Monitoring
    {:monitor, "~> 1.1", organization: "fresha"},
    {:heartbeats, "~> 0.7", organization: "fresha"},

    # Service Communication
    {:rpc_client, "~> 1.4.1", organization: "fresha"},
    {:grpc, "~> 0.6", hex: :grpc_fresha},

    # Event Processing
    {:kafkaesque, "~> 3.2", organization: "fresha"},
    {:kafkaesque_addons, "~> 1.0", organization: "fresha"},

    # Web & API
    {:web_helpers, "~> 0.13.4", organization: "fresha"},
    {:absinthe, "~> 1.7"},
    {:absinthe_phoenix, "~> 2.0.0"},

    # Background Processing
    {:oban, "~> 2.19"},

    # Domain Libraries
    {:money, "~> 1.12"},
    {:eddien, "~> 1.18.0", organization: "fresha"},

    # Testing
    {:mimic, "~> 1.11", only: :test},
    {:credo_checks, "~> 0.1.0", organization: "fresha"},

    # Feature Management
    {:unleash_fresha, "~> 3.0"},

    # Tracing
    {:spandex, "~> 4.1", hex: :spandex_fresha, organization: "fresha", override: true},
    {:spandex_datadog, "~> 1.7.0", hex: :spandex_datadog_fresha, organization: "fresha", override: true}
  ]
end
```
</core_libraries>

<event_architecture>
## Event-Driven Architecture

<decision_tree>
**When to use each pattern**:

1. **Outbox Pattern** → Use when emitting events within database transactions
2. **Domain Events** → Use for internal events that don't need external publishing
3. **Consumer Pattern** → Use when processing events from other services
4. **Direct Publishing** → Avoid - use outbox for transactional safety
</decision_tree>

<outbox_pattern>
### Producer Pattern (Outbox)

**Use case**: Emitting events within database transactions with guaranteed delivery

```elixir
# Migration
defmodule MyService.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  def change do
    create table(:outbox_events, primary_key: false) do
      add :uuid, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :partition_key, :string, null: false
      add :event_type, :string, null: false
      add :topic_name, :string, null: false
      add :proto_payload, :binary, null: false
      add :trace_context, :text
      add :timestamp, :utc_datetime_usec, null: false
    end

    create index(:outbox_events, [:timestamp])
    create index(:outbox_events, [:partition_key])
  end
end

# Schema
defmodule MyService.Schemas.OutboxEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uuid, Ecto.UUID, autogenerate: true}
  schema "outbox_events" do
    field :partition_key, :string
    field :event_type, :string
    field :topic_name, :string
    field :proto_payload, :binary
    field :trace_context, :string
    field :timestamp, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:partition_key, :event_type, :topic_name, :proto_payload, :trace_context])
    |> validate_required([:partition_key, :event_type, :topic_name, :proto_payload])
    |> put_change(:timestamp, DateTime.utc_now())
  end
end

# Usage in Commands
defmodule MyService.Commands.EnableAddon do
  alias MyService.Schemas.{Provider, OutboxEvent}
  alias MyService.Events.AddonEnabled

  def call(provider_id, addon_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:provider, fn repo, _ ->
      case repo.get(Provider, provider_id) do
        nil -> {:error, :not_found}
        provider -> {:ok, provider}
      end
    end)
    |> Ecto.Multi.update(:updated_provider, fn %{provider: provider} ->
      Provider.enable_addon_changeset(provider, addon_id)
    end)
    |> Ecto.Multi.run(:event_payload, fn _repo, %{updated_provider: provider} ->
      event = %AddonEnabled{
        provider_id: provider.id,
        addon_id: addon_id,
        enabled_at: DateTime.utc_now()
      }

      case AddonEnabled.encode(event) do
        {:ok, encoded} -> {:ok, encoded}
        error -> error
      end
    end)
    |> Ecto.Multi.insert(:outbox_event, fn %{event_payload: payload, updated_provider: provider} ->
      OutboxEvent.changeset(%OutboxEvent{}, %{
        partition_key: provider.id,
        event_type: "addon_enabled",
        topic_name: "add-ons.domain-events-v1",
        proto_payload: payload,
        trace_context: get_current_trace_context()
      })
    end)
    |> MyService.Repo.transaction()
    |> case do
      {:ok, %{updated_provider: provider}} -> {:ok, provider}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  defp get_current_trace_context do
    # Extract from current span or return nil
    Spandex.current_trace_id() |> to_string()
  rescue
    _ -> nil
  end
end
```
</outbox_pattern>

<consumer_pattern>
### Consumer Pattern

**Use case**: Processing events from other services with idempotency

```elixir
# Supervisor
defmodule MyService.Events.AddonEnabled.Supervisor do
  @consumer_group "my_service.addon_enabled_consumer"

  use Kafkaesque.ConsumerSupervisor,
    consumer_group_identifier: @consumer_group,
    topics: ["add-ons.domain-events-v1"],
    dead_letter_queue: "my_service.addon_enabled_dlq",
    message_handler: MyService.Events.AddonEnabled.MessageHandler

  def healthcheck, do: Heartbeats.Helpers.kafka_consumer_check(@consumer_group)
end

# Message Handler
defmodule MyService.Events.AddonEnabled.MessageHandler do
  alias KafkaesqueAddons.Idempotency.RedisInboxStrategy.RedisClient
  alias MyService.Commands.ProcessAddonEnabled

  use Kafkaesque.Consumer,
    commit_strategy: :sync,
    consumer_group_identifier: "my_service.addon_enabled_consumer",
    decoders: %{
      "add-ons.domain-events-v1" => %{
        decoder: Kafkaesque.Decoders.DebeziumProtoDecoder,
        opts: [schema: AddOns.Events.DomainEventsV1.Envelope]
      }
    },
    handle_message_plugins: [
      {KafkaesqueAddons.Plugins.UUIDIdempotencyPlugin,
       strategy: KafkaesqueAddons.Idempotency.RedisInboxStrategy,
       redis_client: RedisClient}
    ],
    retries: 2

  def handle_decoded_message(%{proto_payload: %{payload: {"addon_enabled", event_data}}}) do
    Logger.info("Processing addon enabled event", provider_id: event_data.provider_id)

    case ProcessAddonEnabled.call(event_data) do
      :ok ->
        Logger.info("Successfully processed addon enabled event")
        :ok

      {:error, :provider_not_found} ->
        handle_not_found_error(event_data.provider_id)

      {:error, reason} ->
        Logger.error("Failed to process addon enabled event", reason: inspect(reason))
        {:error, reason}
    end
  end

  def handle_decoded_message(_), do: :ok

  # Environment-specific error handling
  defp handle_not_found_error(provider_id) do
    if test_env?() do
      Logger.info("Provider not found, skipping in test environment", provider_id: provider_id)
      :ok
    else
      Logger.error("Provider not found in production", provider_id: provider_id)
      # Crash and retry - might be a race condition
      {:error, :provider_not_found}
    end
  end

  defp test_env? do
    Application.get_env(:my_service, :environment) == :test
  end
end

# Command Handler
defmodule MyService.Commands.ProcessAddonEnabled do
  alias MyService.Schemas.ProviderAddon

  def call(%{provider_id: provider_id, addon_id: addon_id}) do
    case MyService.Repo.get_by(ProviderAddon, provider_id: provider_id, addon_id: addon_id) do
      nil ->
        # Create new provider addon record
        %ProviderAddon{}
        |> ProviderAddon.changeset(%{
          provider_id: provider_id,
          addon_id: addon_id,
          status: :enabled,
          enabled_at: DateTime.utc_now()
        })
        |> MyService.Repo.insert()
        |> case do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, {:validation_error, changeset}}
        end

      existing ->
        # Update existing record
        existing
        |> ProviderAddon.enable_changeset()
        |> MyService.Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, {:validation_error, changeset}}
        end
    end
  end
end
```
</consumer_pattern>

</event_architecture>

<background_jobs>
## Background Jobs with Oban

<oban_setup>
### Configuration & Setup

```elixir
# config/config.exs
config :my_service, ObanProcessor,
  name: Processor.Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7, interval: 60 * 60 * 24},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", MyService.Jobs.DailyCleanup},
      {"*/15 * * * *", MyService.Jobs.HealthCheck}
    ]}
  ],
  queues: [
    default: 10,
    high_priority: 5,
    cleanup: 2,
    notifications: 8
  ],
  repo: MyService.Repo

config :my_service, ObanStorer,
  name: Storer.Oban,
  queues: false,  # Storage only, no processing
  repo: MyService.Repo

# config/runtime.exs
config :my_service,
  oban_processor_enabled: System.get_env("OBAN_PROCESSOR_ENABLED", "0") in ["1", "true"],
  oban_storer_enabled: System.get_env("OBAN_STORER_ENABLED", "0") in ["1", "true"]

# Application setup
defmodule MyService.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyService.Repo,
      MyService.Endpoint
    ]
    |> maybe_attach_oban()
    |> maybe_attach_consumers()

    Supervisor.start_link(children, strategy: :one_for_one, name: MyService.Supervisor)
  end

  defp maybe_attach_oban(children) do
    children
    |> maybe_attach_oban_processor()
    |> maybe_attach_oban_storer()
  end

  defp maybe_attach_oban_processor(children) do
    if Application.fetch_env!(:my_service, :oban_processor_enabled) do
      children ++ [{Oban, Application.fetch_env!(:my_service, ObanProcessor)}]
    else
      children
    end
  end

  defp maybe_attach_oban_storer(children) do
    if Application.fetch_env!(:my_service, :oban_storer_enabled) do
      children ++ [{Oban, Application.fetch_env!(:my_service, ObanStorer)}]
    else
      children
    end
  end
end
```
</oban_setup>

<oban_jobs>
### Job Implementation

```elixir
defmodule MyService.Jobs.ProcessPayment do
  use Oban.Worker,
    queue: :high_priority,
    max_attempts: 3,
    unique: [period: 60, fields: [:args]]

  alias MyService.Commands.ProcessPayment

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id, "retry_count" => retry_count}}) do
    Logger.info("Processing payment", payment_id: payment_id, retry: retry_count)

    case ProcessPayment.call(payment_id) do
      {:ok, result} ->
        Logger.info("Payment processed successfully", payment_id: payment_id)
        :ok

      {:error, :payment_not_found} ->
        Logger.warn("Payment not found, discarding job", payment_id: payment_id)
        :discard

      {:error, :insufficient_funds} ->
        Logger.info("Insufficient funds, will retry", payment_id: payment_id)
        {:error, :insufficient_funds}

      {:error, :gateway_timeout} ->
        Logger.warn("Gateway timeout, will retry", payment_id: payment_id)
        {:snooze, 30}

      {:error, reason} ->
        Logger.error("Payment processing failed", payment_id: payment_id, reason: reason)
        {:error, reason}
    end
  end

  # Schedule a job
  def schedule(payment_id, opts \\ []) do
    %{payment_id: payment_id, retry_count: 0}
    |> __MODULE__.new(opts)
    |> Oban.insert()
  end

  # Schedule with delay
  def schedule_in(payment_id, seconds) do
    schedule(payment_id, scheduled_at: DateTime.add(DateTime.utc_now(), seconds))
  end
end

# Recurring cleanup job
defmodule MyService.Jobs.DailyCleanup do
  use Oban.Worker, queue: :cleanup

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting daily cleanup")

    with :ok <- cleanup_expired_sessions(),
         :ok <- cleanup_old_logs(),
         :ok <- update_statistics() do
      Logger.info("Daily cleanup completed successfully")
      :ok
    else
      {:error, reason} ->
        Logger.error("Daily cleanup failed", reason: reason)
        {:error, reason}
    end
  end

  defp cleanup_expired_sessions do
    # Implementation
    :ok
  end

  defp cleanup_old_logs do
    # Implementation
    :ok
  end

  defp update_statistics do
    # Implementation
    :ok
  end
end
```
</oban_jobs>

</background_jobs>

<monitoring_setup>
## DataDog Monitoring

```elixir
# config/config.exs
config :monitor, Monitor.Tracer,
  service: :my_service,
  adapter: SpandexDatadog.Adapter,
  disabled?: true

config :spandex_phoenix, tracer: Monitor.Tracer
config :spandex_ecto, SpandexEcto.EctoLogger, tracer: Monitor.Tracer

# config/runtime.exs
config :monitor, Monitor.Tracer,
  service: {:system, "DD_SERVICE", default: :my_service},
  env: {:system, "DD_ENV", default: "dev"},
  local_sampling_rate: {:system, "DD_TRACE_SAMPLE_RATE", default: 1.0, type: :float},
  disabled?: {:system, "DD_TRACE_ENABLED", default: true, type: :boolean, transform: &(!&1)}

config :monitor, SpandexDatadog.ApiServer,
  host: {:system, "DD_AGENT_HOST"},
  port: {:system, "DD_TRACE_AGENT_PORT", type: :integer}

# Application startup
def start(_type, _args) do
  # Setup monitoring
  Monitor.Sentry.attach_tags()
  Monitor.Ecto.trace(MyService.Repo)

  # Register health checks
  Heartbeats.register_readiness_check([
    &MyService.Healthchecks.repo_available/0,
    &MyService.Healthchecks.redis_available/0,
    &MyService.Events.AddonEnabled.Supervisor.healthcheck/0
  ])

  # Start supervision tree
  children = [MyService.Repo, MyService.Endpoint]
  |> maybe_prepend_metrics_reporter()

  Supervisor.start_link(children, strategy: :one_for_one)
end

defp maybe_prepend_metrics_reporter(children) do
  if Application.get_env(:monitor, :enabled, false) do
    [Monitor.MetricsReporter | children]
  else
    children
  end
end

# Custom instrumentation
defmodule MyService.PaymentProcessor do
  use Spandex.Decorators

  @decorate trace(service: :payment_service, type: :payment)
  def process_payment(payment_attrs) do
    Spandex.update_span(tags: %{payment_amount: payment_attrs.amount})

    # Your implementation
    result = do_process_payment(payment_attrs)

    Spandex.update_span(tags: %{payment_status: elem(result, 0)})
    result
  end
end
```
</monitoring_setup>

<umbrella_structure>
## Umbrella App Structure

```
my_service_umbrella/
├── apps/
│   ├── my_service/              # Core domain logic & schemas
│   │   ├── lib/
│   │   │   ├── my_service/
│   │   │   │   ├── commands/    # Business logic commands
│   │   │   │   ├── schemas/     # Ecto schemas
│   │   │   │   ├── jobs/        # Oban jobs
│   │   │   │   └── queries/     # Complex queries
│   │   │   └── my_service.ex
│   │   └── mix.exs
│   │
│   ├── my_service_web/          # Public GraphQL API
│   │   ├── lib/
│   │   │   └── my_service_web/
│   │   │       ├── schema/      # Absinthe schema
│   │   │       ├── resolvers/   # GraphQL resolvers
│   │   │       └── plugs/       # Custom plugs
│   │   └── mix.exs
│   │
│   ├── my_service_rpc/          # gRPC service
│   │   ├── lib/
│   │   │   └── my_service_rpc/
│   │   │       ├── services/    # gRPC service implementations
│   │   │       └── interceptors/ # gRPC interceptors
│   │   └── mix.exs
│   │
│   └── my_service_events_consumers/ # Kafka consumers
│       ├── lib/
│       │   └── my_service_events_consumers/
│       │       └── events/      # Event handlers by topic
│       └── mix.exs
│
├── config/                      # Shared configuration
└── mix.exs                     # Umbrella project file

# Release configuration in umbrella mix.exs
releases: [
  my_service_web: [
    applications: [my_service_web: :permanent, my_service: :permanent]
  ],
  my_service_rpc: [
    applications: [my_service_rpc: :permanent, my_service: :permanent]
  ],
  my_service_events_consumers: [
    applications: [my_service_events_consumers: :permanent, my_service: :permanent]
  ],
  my_service_worker: [
    applications: [my_service: :permanent]  # Core app with Oban enabled
  ]
]
```
</umbrella_structure>

</fresha_platform>

---

<troubleshooting>

## Common Issues & Solutions

<performance_issues>
### Performance Problems

**Symptoms**: Slow queries, high memory usage, timeouts

**Debugging approach**:
1. Check DataDog traces for slow operations
2. Use `:observer.start()` for memory/process analysis
3. Add telemetry events for custom metrics
4. Profile with `:fprof` or `:eflame`

```elixir
# Add telemetry for custom operations
defmodule MyService.Telemetry do
  def start_operation(operation_name, metadata \\ %{}) do
    :telemetry.span([:my_service, operation_name], metadata, fn ->
      # Your operation here
      result = perform_operation()
      {result, %{status: :success}}
    end)
  end
end

# Monitor query performance
defmodule MyService.Queries.UserQuery do
  import Ecto.Query

  def get_user_with_stats(user_id) do
    # Add query telemetry
    :telemetry.span([:my_service, :query, :user_with_stats], %{user_id: user_id}, fn ->
      result = from(u in User,
        where: u.id == ^user_id,
        preload: [:profile, :subscriptions],
        select: u
      )
      |> MyService.Repo.one()

      {result, %{}}
    end)
  end
end
```
</performance_issues>

<event_processing_issues>
### Event Processing Issues

**Consumer lag**:
- Check consumer group health in Kafka UI
- Verify Redis connectivity for idempotency
- Scale consumer instances if needed

**Message processing failures**:
- Check dead letter queue for failed messages
- Verify proto schema compatibility
- Test event handlers in isolation

```elixir
# Debug consumer issues
defmodule MyService.Debug.ConsumerHealth do
  def check_consumer_status(consumer_group) do
    case Heartbeats.Helpers.kafka_consumer_check(consumer_group) do
      :ok ->
        IO.puts("✅ Consumer #{consumer_group} is healthy")
      {:error, reason} ->
        IO.puts("❌ Consumer #{consumer_group} failed: #{inspect(reason)}")
    end
  end

  def check_redis_connectivity do
    case RedisClient.ping() do
      {:ok, "PONG"} ->
        IO.puts("✅ Redis connection healthy")
      error ->
        IO.puts("❌ Redis connection failed: #{inspect(error)}")
    end
  end
end
```
</event_processing_issues>

<testing_issues>
### Testing Issues

**Mimic not working**:
- Ensure `Mimic.copy/1` is called in `test_helper.exs`
- Check that modules are compiled before copying
- Use `verify_on_exit!()` to catch unstubbed calls

**Async test failures**:
- Use `async: false` for tests that modify global state
- Ensure database sandbox is properly configured
- Mock external services consistently

```elixir
# Debug Mimic issues
defmodule MyServiceTest do
  use ExUnit.Case
  use Mimic

  # Verify mocks are working
  setup :verify_on_exit!

  test "debug mock calls" do
    # Enable mock call tracing
    stub_with(MyService.ExternalApi, MyService.ExternalApiMock)

    # Your test code
    result = MyService.do_something()

    # Verify expected calls
    assert_called(MyService.ExternalApi.some_method(:_))
  end
end
```
</testing_issues>

</troubleshooting>

</elixir_standards>