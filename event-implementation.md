# Event Implementation Guide for Fresha

This guide provides comprehensive instructions for creating and listening to events at Fresha using Protocol Buffers (protobuf) and generating buf packages.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Setting Up a New Service as Producer](#setting-up-a-new-service-as-producer)
4. [Setting Up a Service as Consumer](#setting-up-a-service-as-consumer)
5. [Creating Events](#creating-events)
6. [Listening to Events](#listening-to-events)
7. [Generating Buf Packages](#generating-buf-packages)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

## Overview

At Fresha, we use Protocol Buffers (protobuf) extensively for internal service-to-service communication via:
- **gRPC** for synchronous communication
- **Kafka** for asynchronous event streaming

**Key Components:**
- **buf**: Protobuf dependency management and code generation
- **surgeventures/registry**: Central repository for all communication contracts
- **bufgen**: Custom Elixir generator service for remote code generation
- **houston CLI**: Helper commands for buf registry management

## Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Producer      │    │  Registry Repository │    │   Consumer      │
│   Service       │────│  (contracts)         │────│   Service       │
│                 │    │                      │    │                 │
│ - Events        │    │ - Proto definitions  │    │ - Event handlers│
│ - Commands      │    │ - Version control    │    │ - Generated code│
└─────────────────┘    └──────────────────────┘    └─────────────────┘
                                 │
                                 ▼
                       ┌──────────────────────┐
                       │  bufgen Service      │
                       │  (Code Generation)   │
                       │                      │
                       │ - Elixir generators  │
                       │ - Remote plugins     │
                       └──────────────────────┘
```

## Setting Up a New Service as Producer

When your service needs to **expose contracts** to other services (publishing events to Kafka or exposing gRPC services), follow these steps:

### 1. Create Required Files

#### `buf.yaml`
```yaml
version: v2
modules:
  # If you change this path, also update the workflow file .github/workflows/buf-ci-cd.yaml
  - path: ./proto
# if needed:
# deps:
#   - buf.build/fresha/common

# For all new protos (and old ones, with exclusions) consider the following
# linting ruleset.
#
# See: https://buf.build/docs/lint/rules/
lint:
  use:
    - STANDARD   # All of our protos should pass these.
    - COMMENTS   # This enforces comment documentation on _all_ fields/messages/services. It's a lot, but may be worth it.
    - UNARY_RPC  # Generally speaking, we shouldn't need to use the streaming protocol of gRPC, unary RPCs are a lot simpler to use, implement, and manage. See: https://github.com/twitchtv/twirp/issues/70#issuecomment-470367807
```

#### Generate Lock File
```bash
buf dep update
```

#### Format and Lint
```bash
buf format -w
buf lint
```

#### `.github/workflows/buf-ci-cd.yaml`
```yaml
# Run the buf action, which does linting, format checks, and breaking change detection, then publish to registry (or do a dry-run in PRs)
name: Buf CI & CD

on:
  schedule:
    # Prefer running not "on the hour" as these are higher-load times for
    # GitHub Actions, which may lead to delays in execution or the event
    # being dropped.
    #
    # See: https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule
    - cron: "15 16 * * 1-5"
  workflow_dispatch:
  pull_request:
    types: [opened, synchronize, labeled, unlabeled, reopened]
    paths:
      - .github/workflows/buf-ci-cd.yaml
      - "proto/**"
      - "buf.*"
  push:
    branches:
      - main
    paths:
      - .github/workflows/buf-ci-cd.yaml
      - "proto/**"
      - "buf.*"

concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref_name }}
  cancel-in-progress: true

jobs:
  buf:
    runs-on: "runs-on/runner=2cpu-linux-x64/run-id=${{ github.run_id }}"
    steps:
      - uses: actions/checkout@v4
      - uses: bufbuild/buf-action@v1
        with:
          # Adding the label "allow breaking changes" will skip the check
          # Breaking change detection should only run on PRs
          breaking: ${{ github.event_name == 'pull_request' && !contains(github.event.pull_request.labels.*.name, 'allow breaking changes') }}
      - uses: surgeventures/registry-actions/publish@v2
        with:
          registry-token: ${{ secrets.FRESHA_REGISTRY_TOKEN }}
          dry-run: ${{ github.event_name == 'pull_request' || github.ref != 'refs/heads/main' }}
```

### 2. Create Proto File Structure

Follow the recommended folder structure:

#### For RPC Services
```
{REPO}/rpc/{SERVICE}/v{VERSION}/service.proto
```

#### For Kafka Events
```
{REPO}/kafka/{TOPIC}/envelope.proto
```

Example: `app-customers/kafka/customer_events_v1/envelope.proto`

## Setting Up a Service as Consumer

When your service needs to **consume contracts** from other services (calling other gRPC services or listening to Kafka events), follow these steps:

### 1. Create Required Files

#### `buf.gen.yaml`
```yaml
version: v2
clean: true

inputs:
  - module: buf.build/fresha/common
  # Repeat the below as many times as you have dependencies
  - git_repo: ssh://git@github.com/surgeventures/registry
    subdir: # PLEASE SPECIFY - E.g. app-b2c-users
    paths: # PLEASE SPECIFY - E.g. [events, rpc]
    ref: # PLEASE SPECIFY - Recommend locking your inputs to a version to have more control over updates. You can use `houston buf registry bump` to help with this.

plugins:
  # Elixir examples
  - remote: buf.external-infrastructure.fresha.io/elixir-protobuf/elixir:v0.7.1 # Set this version to match your `protobuf` package version
    out: src/apps/<XXX>/lib/generated
    opt:
      - plugins=grpc
  - remote: buf.external-infrastructure.fresha.io/surgeventures/elixir-rpc:v0.0.1
    out: src/apps/<XXX>/lib/generated
    opt:
      - plugins=grpc
  # NodeJS examples
  - plugin: buf.build/community/stephenh-ts-proto:v1.178.0
    out: .ts-gen
    opt:
      - lowerCaseServiceMethods=true
      - esModuleInterop=true
      - unrecognizedEnum=false
      - addGrpcMetadata=true
      - outputServices=generic-definitions
      - outputServices=default
```

#### `.github/workflows/buf-generate.yaml`
```yaml
name: Buf Generate

on:
  schedule:
    # Prefer running not "on the hour" as these are higher-load times for
    # GitHub Actions, which may lead to delays in execution or the event
    # being dropped.
    #
    # See: https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule
    - cron: "15 16 * * 1-5"
  workflow_dispatch:
  pull_request:
    paths:
      - .github/workflows/buf-generate.yaml
      - "proto/**"
      - "buf.*"
  push:
    branches:
      - main
    paths:
      - .github/workflows/buf-generate.yaml
      - "proto/**"
      - "buf.*"

concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref_name }}
  cancel-in-progress: true

jobs:
  buf-generate:
    runs-on: "runs-on/runner=2cpu-linux-x64/run-id=${{ github.run_id }}"
    env:
      COMMITTER_NAME: Proto bot
      COMMITTER_EMAIL: support+protobot@fresha.com
    steps:
      - uses: actions/checkout@v4
        with:
          # This is useful to avoid a spurious merge commit on the resulting PR
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
      - name: Set github url and credentials
        run: |
          /usr/bin/git config --global --add url."https://$token:x-oauth-basic@github".insteadOf ssh://git@github
          /usr/bin/git config --global --add url."https://$token:x-oauth-basic@github".insteadOf https://github
          /usr/bin/git config --global --add url."https://$token:x-oauth-basic@github".insteadOf git@github
        env:
          token: ${{ secrets.FRESHA_REGISTRY_TOKEN }}
      - uses: erlef/setup-beam@v1
        with:
          version-file: .tool-versions
          version-type: strict
        env:
          ImageOS: ubuntu22
      - name: Install buf
        uses: bufbuild/buf-setup-action@v1
      - run: buf generate
      - run: mix format "src/apps/gift_cards/lib/generated/**/*"
      - id: pr
        uses: surgeventures/marketplace-actions/create-automated-pr@v1
        with:
          pr_branch: auto/${{ github.head_ref || github.ref_name }}/buf
          commit_message: "chore(buf): updated generated files"
          pr_title: "Updated buf files"
          labels: buf
          automerge: false
          system_pat: ${{ secrets.COMMIT_SYSTEM_ACCOUNT_PAT }}

      - uses: actions-cool/maintain-one-comment@v3
        if: always() && steps.pr.outputs.pr_number != '' && github.event_name == 'pull_request'
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          body: |
            ### New output from `buf generate`

            New files have been created from the local contracts and the dependencies specified in `buf.gen.yaml`. Please take a look at #${{ steps.pr.outputs.pr_number }} and merge it into this PR if you're happy.

            Tip: You can run `buf generate` locally to avoid this failing check when changing proto files.
          body-include: "<!-- proto-gen -->"
      - uses: actions-cool/maintain-one-comment@v3
        if: always() && steps.pr.outputs.pr_number == '' && github.event_name == 'pull_request'
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          # This will delete the existing comment if it exists
          body-include: "<!-- proto-gen -->"
```

## Creating Events

### 1. Define Event Structure

#### Example: Create an envelope proto file
**Path:** `proto/kafka/user_events_v1/envelope.proto`

```protobuf
syntax = "proto3";

package fresha.your_app.kafka.user_events_v1;

import "kafka/user_events_v1/user_created.proto";
import "kafka/user_events_v1/user_updated.proto";
import "kafka/user_events_v1/user_deleted.proto";

/**
 * Events envelope for user-related events.
 * This envelope contains all possible user events that can be published.
 */
message Payload {
  oneof payload {
    fresha.your_app.kafka.user_events_v1.UserCreated user_created = 1;
    fresha.your_app.kafka.user_events_v1.UserUpdated user_updated = 2;
    fresha.your_app.kafka.user_events_v1.UserDeleted user_deleted = 3;
  }
}
```

#### Example: Create individual event proto files
**Path:** `proto/kafka/user_events_v1/user_created.proto`

```protobuf
syntax = "proto3";

package fresha.your_app.kafka.user_events_v1;

/**
 * Event emitted when a new user is created in the system.
 *
 * Consumers of this event may:
 * * Update their local user cache
 * * Send welcome notifications
 * * Initialize user-specific data
 */
message UserCreated {
  /**
   * The unique identifier of the newly created user.
   */
  uint64 user_id = 1;

  /**
   * The email address of the user.
   */
  string email = 2;

  /**
   * The display name chosen by the user.
   */
  string display_name = 3;

  /**
   * Timestamp when the user was created (Unix timestamp in seconds).
   */
  int64 created_at = 4;

  /**
   * The registration source (e.g., "web", "mobile", "api").
   */
  string registration_source = 5;
}
```

### 2. Naming Conventions

- **APP**: From repo name, replacing `-` with `_` (e.g., `app-customers` → `app_customers`)
- **SERVICE**: From domain name, replacing `-` with `_`
- **TOPIC**: Can contain version, replacing `-` with `_` (e.g., `user-events-v1` → `user_events_v1`)

### 3. Package Structure

For Kafka events:
```
fresha.{APP}.kafka.{TOPIC}.{MESSAGE_NAME}
```

Example:
```
fresha.app_customers.kafka.user_events_v1.UserCreated
```

### 4. Publish Event to Registry

1. Create a pull request with your proto changes
2. The CI/CD workflow will automatically publish to the registry on merge
3. Breaking changes require the "allow breaking changes" label

## Listening to Events

### 1. Add Dependency to buf.gen.yaml

```yaml
inputs:
  - git_repo: ssh://git@github.com/surgeventures/registry
    subdir: app-customers  # The service publishing the events
    paths: [kafka]         # Only include Kafka events
    ref: abc123def         # Lock to specific commit
```

### 2. Generate Code

```bash
buf generate
```

For Elixir projects, also format the generated code:
```bash
mix format "src/apps/your_app/lib/generated/**/*"
```

### 3. Implementation Example (Elixir)

```elixir
defmodule YourApp.EventConsumer do
  @moduledoc """
  Kafka consumer for user events.
  """

  use GenServer
  require Logger

  alias Fresha.AppCustomers.Kafka.UserEventsV1.{Payload, UserCreated, UserUpdated}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Initialize Kafka consumer
    {:ok, %{}}
  end

  @spec handle_event(binary()) :: :ok | {:error, term()}
  def handle_event(message) do
    case Payload.decode(message) do
      %Payload{payload: {:user_created, %UserCreated{} = event}} ->
        handle_user_created(event)

      %Payload{payload: {:user_updated, %UserUpdated{} = event}} ->
        handle_user_updated(event)

      %Payload{payload: nil} ->
        Logger.warning("Received empty event payload")
        :ok

      {:error, reason} ->
        Logger.error("Failed to decode event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_user_created(%UserCreated{user_id: user_id, email: email} = event) do
    Logger.info("Processing user created event", user_id: user_id, email: email)

    # Your business logic here
    case YourApp.Users.create_local_user(event) do
      {:ok, _user} ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to process user created event", error: reason)
        {:error, reason}
    end
  end

  defp handle_user_updated(%UserUpdated{} = event) do
    # Handle user updated logic
    :ok
  end
end
```

## Generating Buf Packages

### Available Generators

The bufgen service provides several remote generators:

#### Elixir Generators
- `buf.external-infrastructure.fresha.io/elixir-protobuf/elixir:v0.7.1`
- `buf.external-infrastructure.fresha.io/elixir-protobuf/elixir:v0.14.0`
- `buf.external-infrastructure.fresha.io/surgeventures/elixir-rpc:v0.0.1`

#### Ruby Generators
- `buf.external-infrastructure.fresha.io/surgeventures/ruby-rpc:v0.1.1`

### Generator Configuration Examples

#### Elixir Configuration
```yaml
plugins:
  - remote: buf.external-infrastructure.fresha.io/elixir-protobuf/elixir:v0.7.1
    out: src/apps/your_app/lib/generated
    opt:
      - plugins=grpc
  - remote: buf.external-infrastructure.fresha.io/surgeventures/elixir-rpc:v0.0.1
    out: src/apps/your_app/lib/generated
    opt:
      - plugins=grpc
```

#### TypeScript/Node.js Configuration
```yaml
plugins:
  - plugin: buf.build/community/stephenh-ts-proto:v1.178.0
    out: .ts-gen
    opt:
      - lowerCaseServiceMethods=true
      - esModuleInterop=true
      - unrecognizedEnum=false
      - addGrpcMetadata=true
      - outputServices=generic-definitions
      - outputServices=default
```

### Houston CLI Commands

Use Houston CLI to help manage buf registry dependencies:

```bash
# Bump registry references to latest versions
houston buf registry bump

# Other buf registry subcommands are available
houston buf registry --help
```

## Best Practices

### 1. Version Management
- Always lock your inputs to a specific commit using `ref`
- Use semantic versioning for your service versions
- Plan breaking changes carefully and use appropriate labels

### 2. Proto File Organization
```
proto/
├── kafka/
│   ├── user_events_v1/
│   │   ├── envelope.proto
│   │   ├── user_created.proto
│   │   ├── user_updated.proto
│   │   └── user_deleted.proto
│   └── order_events_v1/
│       └── ...
└── rpc/
    └── users/
        └── v1/
            └── service.proto
```

### 3. Documentation
- Always add comprehensive comments to proto fields
- Explain event semantics and consumer responsibilities
- Document breaking changes in commit messages

### 4. Testing
- Always run `buf generate` locally before committing
- Verify generated code compiles and passes tests
- Include this in your CI: `buf generate && git add . && git diff-index --name-status --exit-code HEAD`

### 5. Performance
- Use remote code generators instead of local ones
- Keep proto messages focused and lightweight
- Consider backwards compatibility when evolving schemas

## Troubleshooting

### Common Issues

#### 1. Import Errors
```
import "*.proto": file does not exist
```
**Solution:** This often happens on first publish. Skip breaking change detection by adding the "allow breaking changes" label to your PR.

#### 2. Authentication Issues
**Solution:** Ensure you're connected to the Integration VPN for bufgen service access.

#### 3. Generator Version Mismatches
**Solution:** Match your protobuf package version with the remote generator version:
```yaml
- remote: buf.external-infrastructure.fresha.io/elixir-protobuf/elixir:v0.7.1 # Match your protobuf package version
```

#### 4. Code Generation Failures
**Solution:** Check the GitHub Actions logs for specific error messages and ensure all required secrets are configured.

### Verification Steps

1. **Lint your proto files:**
   ```bash
   buf lint
   ```

2. **Format your proto files:**
   ```bash
   buf format -w
   ```

3. **Generate code locally:**
   ```bash
   buf generate
   ```

4. **Check for uncommitted changes:**
   ```bash
   git add . && git diff-index --name-status --exit-code HEAD
   ```

### Getting Help

- Check the [surgeventures/registry](https://github.com/surgeventures/registry) repository for examples
- Review the [bufgen plugins](https://github.com/surgeventures/bufgen/blob/main/PLUGINS.md) for available generators
- For Houston CLI help: `houston buf registry --help`
- For buf CLI help: `buf --help`

---

This guide provides a comprehensive overview of event implementation at Fresha. For specific technical questions or issues, consult the respective repository documentation or reach out to the Platform team.