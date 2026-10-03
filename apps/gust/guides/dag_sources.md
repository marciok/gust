# DAG Sources

Gust supports multiple pluggable sources for loading DAG definitions. This guide explains how to choose and configure the source that best fits your operational workflow.

## Overview

A **DAG source** defines:
- **Where** DAGs come from (filesystem folder, Git repository, database)
- **How** they are monitored for changes (file watching, polling, webhooks)

Different sources suit different operational models:

| Source   | Best For | Monitoring | Setup Complexity |
|----------|----------|-----------|-----------------|
| **Folder** | Development, simple deployments | OS file watching | Very simple |
| **Git** | GitOps, multi-environment, audit trail | Polling | Moderate |
| **Git Webhook** | Real-time DAG updates, minimal latency | Webhooks | Moderate |
| **S3** | Cloud-native, multi-tenant, serverless | Polling | Moderate |
| **Database** | Dynamic creation, UI-driven, multi-tenant | Polling | Advanced |

## Quick Start

Gust accepts `dag_source` in five forms:

```elixir
# module atom
config :gust, dag_source: Gust.DAG.Source.Folder

# string name
config :gust, dag_source: "folder"

# module + options tuple
config :gust, dag_source: {Gust.DAG.Source.Folder, folder: Path.join(File.cwd!(), "dags")}
config :gust, dag_source: {"folder", folder: Path.join(File.cwd!(), "dags")}

# map config with a type and source options
config :gust, dag_source: %{
  type:  "folder",
  folder: Path.join(File.cwd!(), "dags")
}

# map config with a module type
config :gust, dag_source: %{
  type: Gust.DAG.Source.Git,
  url: "https://github.com/company/dags.git"
}
```

String names are resolved to the matching source module via the built-in
source map, such as:
- `"git" -> Gust.DAG.Source.Git`
- `"gitwebhook" -> Gust.DAG.Source.GitWebhook`
- `"folder" -> Gust.DAG.Source.Folder`
- `"database" -> Gust.DAG.Source.Database`

In map-based config, `type` may be a string or a source module atom, and the
remaining keys are treated as source options.

### Persistent monitor status

When Gust starts a DAG source monitor, it can persist the current monitor state so
that a paused monitor remains paused after a process or application restart.

```elixir
config :gust,
  dag_source_monitor_status_path: Path.join(System.tmp_dir!(), "gust-dag-source-monitor-status.txt")
```

This option controls where the status file is stored. Gust writes the current
state as a timestamp and status pair, for example:

```text
2026-10-03T12:34:56Z paused
```

On startup, Gust reads the last status token from the file and restores it,
which preserves the monitor lifecycle across restarts. If the setting is not
configured, Gust falls back to a temporary default path.

### Default: Folder Source

Out of the box, Gust loads DAGs from a local folder:

```elixir
# config/dev.exs
config :gust, dag_source: "folder"
```

You can also provide the source configuration on the `dag_source` setting:

```elixir
config :gust, dag_source: {Gust.DAG.Source.Folder, folder: Path.join(File.cwd!(), "dags")}
```

**Setup:** Just create `./dags` folder and add DAG files (`.ex` or `.yml`)

```
dags/
├── backup.ex
├── deploy.ex
└── analytics.yml
```

**Changes detected:** Instantly (OS file watching)

### Git Source

Load DAGs from a Git repository:

```elixir
# config/git.exs
config :gust, dag_source: {Gust.DAG.Source.Git,
  url: "https://github.com/company/dags.git",
  branch: "main",
  path: "/var/cache/gust-dags",
  poll_seconds: 30
}
```

**Setup:**
1. Add egit to `mix.exs`: `{:egit, "~> 0.3"}`
2. Run `mix deps.get`
3. Update config with repository URL
4. Source `config/git.exs` (or use environment config)

**Changes detected:** Polls repository every 30 seconds (configurable)

**Authentication:** Optional - supports SSH keys, tokens, username/password

### S3 Source

Load DAGs from an AWS S3 bucket:

```elixir
# config/s3.exs
config :gust, dag_source: %{
  type:   "S3",
  bucket: "my-company-dags",
  prefix: "workflows/",
  region: "us-west-2",
  poll_seconds: 30
}
```

**Setup:**
1. Add ex_aws dependencies to `mix.exs`:
   ```elixir
   {:ex_aws, "~> 2.4", optional: true},
   {:ex_aws_s3, "~> 2.4", optional: true}
   ```
2. Run `mix deps.get`
3. Update config with S3 bucket details
4. Source `config/s3.exs` (or use environment config)

**Changes detected:** Polls S3 every 30 seconds (configurable)

**Authentication:** Uses AWS SDK credential chain (env vars, IAM role, ~/.aws/credentials)

### Git Webhook Source

#### Overview

The Git Webhook source provides **real-time DAG updates** by receiving push notifications from Git platforms (GitHub, GitLab, Gitea, or any generic Git service). Unlike the polling Git source, webhooks detect changes **instantly** when DAGs are pushed.

**Key differences from Git polling:**
- **Real-time** — Changes detected in <1 second (vs 30 second polls)
- **Zero latency** — No polling overhead
- **Event-driven** — Only reloads when changes actually occur
- **Platform support** — GitHub, GitLab, Gitea, generic webhooks

#### Configuration

```elixir
config :gust, dag_source: %{
  type:   "GitWebhook",
  url:    "https://github.com/company/dags.git",             # Required
  branch: "main",                                            # Optional (default: "main")
  path:   "/var/cache/gust-dags",                            # Optional (default: /tmp)
  webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET"),   # Optional (see resolution below)
  credentials: [...]                                         # Optional (same as Git source)
}
```

**Webhook Secret Resolution:**

The `webhook_secret` is resolved automatically in this priority order:

1. **Explicit config** — `webhook_secret:` directly in the `dag_source` tuple config
2. **Shared environment variable** — `GIT_WEBHOOK_SECRET`
3. **Platform-specific environment variables:**
   - `GITHUB_WEBHOOK_SECRET` for GitHub webhooks
   - `GITLAB_WEBHOOK_SECRET` for GitLab webhooks
   - `GITEA_WEBHOOK_SECRET` for Gitea webhooks

This means you can use **either** a single `GIT_WEBHOOK_SECRET` for all platforms, **or** platform-specific variables for more control.

**Examples:**

```bash
# Option 1: Single secret for all platforms
export GIT_WEBHOOK_SECRET="your-shared-secret-key"

# Option 2: Platform-specific secrets
export GITHUB_WEBHOOK_SECRET="github-secret-key"
export GITLAB_WEBHOOK_SECRET="gitlab-secret-key"
export GITEA_WEBHOOK_SECRET="gitea-secret-key"

# Option 3: Explicit config (takes precedence)
config :gust, dag_source: {Gust.DAG.Source.GitWebhook,
  webhook_secret: "hardcoded-secret"  # Overrides all env vars
}
```

#### Platform Setup

**GitHub**

1. Go to: Settings → Webhooks → Add webhook
2. Payload URL: `https://your-gust-domain.com/api/webhooks/github`
3. Content type: `application/json`
4. Secret: `your-webhook-secret-key`
5. Events: Select "Push events"
6. Active: ✓ Enabled

```elixir
config :gust, dag_source: {Gust.DAG.Source.GitWebhook,
  url: "https://github.com/company/dags.git",
  # Webhook secret automatically resolved from:
  # GIT_WEBHOOK_SECRET or GITHUB_WEBHOOK_SECRET env vars
}
```

**GitLab**

1. Go to: Settings → Webhooks
2. URL: `https://your-gust-domain.com/api/webhooks/gitlab`
3. Secret token: `your-secret-token`
4. Push events: ✓ Enabled

```elixir
config :gust, dag_source: {Gust.DAG.Source.GitWebhook,
  url: "https://gitlab.com/company/dags.git",
  # Webhook secret automatically resolved from:
  # GIT_WEBHOOK_SECRET or GITLAB_WEBHOOK_SECRET env vars
}
```

**Gitea**

1. Go to: Settings → Webhooks → Add Webhook → Gitea
2. Target URL: `https://your-gust-domain.com/api/webhooks/gitea`
3. Secret: `your-secret-key`
4. Push events: ✓ Enabled

```elixir
config :gust, dag_source: {Gust.DAG.Source.GitWebhook,
  url: "https://gitea.example.com/company/dags.git",
  # Webhook secret automatically resolved from:
  # GIT_WEBHOOK_SECRET or GITEA_WEBHOOK_SECRET env vars
}
```

**Generic (Other Platforms)**

Use the generic webhook endpoint: `https://your-gust-domain.com/api/webhooks/generic`

Authorization via Bearer token: `Authorization: Bearer {webhook_secret}`

#### Webhook Endpoints

Configure your Git platform to POST to one of these:

```
POST /api/webhooks/github    # GitHub push webhooks
POST /api/webhooks/gitlab    # GitLab push webhooks
POST /api/webhooks/gitea     # Gitea push webhooks
POST /api/webhooks/generic   # Generic/custom webhooks
```

#### Signature Validation

Webhooks are secured with HMAC signatures:

| Platform | Header | Algorithm | Format |
|----------|--------|-----------|--------|
| **GitHub** | `X-Hub-Signature-256` | HMAC-SHA256 | `sha256={hex}` |
| **GitLab** | `X-Gitlab-Token` | Token match | Token string |
| **Gitea** | `X-Gitea-Signature` | HMAC-SHA256 | Hex digest |
| **Generic** | `Authorization` | Bearer token | `Bearer {token}` |

#### Workflow Example

1. **Developer pushes DAG changes:**
   ```bash
   git commit -m "Add new backup DAG"
   git push origin main
   ```

2. **Git platform sends webhook** to Gust instantly

3. **Gust validates signature** and parses payload

4. **DAG reloads automatically** (<1 second)

5. **New DAG ready for execution** immediately

#### Performance

- **Change detection:** <1 second (instant webhook)
- **Latency:** Typical: 50-500ms
- **Scaling:** Event-driven (any number of DAGs)
- **Overhead:** Zero polling

#### Webhook vs Polling Comparison

```
Webhook (real-time):        Change detected in <1s
Polling (default 30s):      Change detected in up to 30s
```

Use webhooks when you need immediate DAG updates. Use polling when you prefer simplicity without webhook infrastructure.

#### Configuration Example

**Option 1: Shared secret (.env.example)**
```bash
DAG_REPO_URL=https://github.com/company/dags.git
GIT_WEBHOOK_SECRET=your-random-32-char-secret-key-here
GIT_TOKEN=github_token_here
```

**Option 2: Platform-specific secrets (.env.example)**
```bash
DAG_REPO_URL=https://github.com/company/dags.git
GITHUB_WEBHOOK_SECRET=github-secret-key-here
GITLAB_WEBHOOK_SECRET=gitlab-secret-key-here
GITEA_WEBHOOK_SECRET=gitea-secret-key-here
GIT_TOKEN=github_token_here
```

**config/webhook.exs (minimal - uses automatic resolution):**
```elixir
config :gust, dag_source: {Gust.DAG.Source.GitWebhook,
  url: System.get_env("DAG_REPO_URL"),
  branch: "main",
  # webhook_secret is automatically resolved from:
  # 1. GIT_WEBHOOK_SECRET env var (if set)
  # 2. Platform-specific env vars (GITHUB_/GITLAB_/GITEA_WEBHOOK_SECRET)
  credentials: [
    type: :token,
    username: "git",
    token: System.get_env("GIT_TOKEN")
  ]
}
```

**config/webhook.exs (explicit - overrides env vars):**
```elixir
config :gust, dag_source: %{
  type:   Gust.DAG.Source.GitWebhook,
  url:    System.get_env("DAG_REPO_URL"),
  branch: "main",
  webhook_secret: System.get_env("WEBHOOK_SECRET"),  # Explicit value takes precedence
  credentials: [
    type: :token,
    username: "git",
    token: System.get_env("GIT_TOKEN")
  ]
}
```

### Database Source

Store DAGs in the database:

```elixir
# config/database.exs
config :gust, dag_source: {Gust.DAG.Source.Database, poll_seconds: 30}
```

**Setup:**
1. Run migrations: `mix ecto.migrate`
2. Insert DAGs into `gust_dag_sources` table
3. Source `config/database.exs`

**Changes detected:** Polls database every 30 seconds (configurable)

## Folder Source

### Configuration

```elixir
config :gust, dag_source: %{type: "folder", folder: "/path/to/dags"}
```

### Features

- **Instant change detection** — Uses OS file watching (inotify, fsevents)
- **Zero external dependencies** — Built-in FileSystem library
- **No polling overhead** — Scales to many DAGs
- **Simple debugging** — Easy to inspect files

### Examples

**Development:**
```elixir
# config/dev.exs
config :gust, dag_source: %{type: "folder", folder: Path.join(File.cwd!(), "dags")}
```

**Production:**
```elixir
# config/prod.exs
config :gust, dag_source: %{type: "folder", folder: "/dags"}
```

## Git Source

### Configuration

```elixir
config :gust, dag_source: %{
  type:   "git",
  url:    "https://github.com/company/dags.git",  # Required
  branch: "main",                                 # Optional (default: "main")
  path:   "/tmp/gust-dags-repo",                  # Optional (default: /tmp)
  poll_seconds: 30,                               # Optional (default: 30)
  credentials: [...]                              # Optional
}
```

### Authentication Methods

#### 1. SSH Key (Recommended for private repos)

```elixir
credentials: [
  type: :ssh_key,
  username: "git",
  privkey_path: "/home/app/.ssh/id_rsa",
  pubkey_path: "/home/app/.ssh/id_rsa.pub",
  passphrase: System.get_env("SSH_KEY_PASSPHRASE", "")
]
```

Or with embedded keys:

```elixir
credentials: [
  type: :ssh_key,
  username: "git",
  privkey: File.read!("/home/app/.ssh/id_rsa"),
  pubkey: File.read!("/home/app/.ssh/id_rsa.pub"),
  passphrase: System.get_env("SSH_KEY_PASSPHRASE", "")
]
```

#### 2. Username/Password

```elixir
credentials: [
  type: :userpass,
  username: System.get_env("GIT_USERNAME"),
  password: System.get_env("GIT_PASSWORD")
]
```

#### 3. Personal Access Token (Most Secure)

```elixir
credentials: [
  type: :token,
  username: "git",
  token: System.get_env("GIT_TOKEN")
]
```

#### 4. SSH Agent

```elixir
credentials: [
  type: :ssh_agent,
  username: "git"
]
```

### Environment Variables

For sensitive credentials, use environment variables:

- `GIT_CREDENTIALS_USERNAME` — Username (for userpass/token)
- `GIT_CREDENTIALS_PASSWORD` — Password (for userpass) or token (for :token)
- `SSH_KEY_PASSPHRASE` — SSH key passphrase (for :ssh_key)

### Workflow Example

1. **Developer** updates DAGs and pushes to Git:
   ```bash
   git commit -m "Add new analytics DAG"
   git push origin main
   ```

2. **Gust** detects change within 30 seconds (or your configured interval)

3. **DAG automatically reloads** without restarting Gust

4. **New DAG is available** for execution immediately

### Configuration Examples

**GitHub with SSH:**
```elixir
config :gust, dag_source: %{
  type:   "git",
  url:    "git@github.com:company/dags.git",
  branch: "main",
  credentials: [
    type:         :ssh_key,
    username:     "git",
    privkey_path: "/home/app/.ssh/id_rsa",
    pubkey_path:  "/home/app/.ssh/id_rsa.pub",
    passphrase:   System.get_env("SSH_KEY_PASSPHRASE", "")
  ]
}
```

**GitHub with Personal Token:**
```elixir
config :gust, dag_source: %{
  type:   "git",
  url:    "git@github.com:company/dags.git",
  branch: "main",
  credentials: [
    type:     :token,
    username: "bot-user",
    token:    System.get_env("GITHUB_TOKEN")
  ]
}
```

**GitLab with SSH:**
```elixir
config :gust, dag_source: %{
  type:   "git",
  url:    "git@github.com:company/dags.git",
  branch: "main",
  credentials: [
    type:         :ssh_key,
    username:     "git",
    privkey_path: System.get_env("SSH_KEY_PATH"),
    pubkey_path:  System.get_env("SSH_PUBKEY_PATH")
  ]
}
```

## Database Source

### Configuration

```elixir
config :gust, dag_source: {Gust.DAG.Source.Database,
  poll_seconds: 30  # Optional (default: 30)
}
```

### Setup

1. **Run migration:**
   ```bash
   mix ecto.migrate
   ```

2. **Insert DAGs:**
   ```sql
   INSERT INTO gust_dag_sources (name, content, format, enabled, inserted_at, updated_at)
   VALUES (
     'daily_backup',
     'defmodule DailyBackup do
       use Gust.DSL
       task :backup do
         {:shell, "backup.sh"}
       end
     end',
     'elixir',
     true,
     NOW(),
     NOW()
   );
   ```

3. **Or via Elixir:**
   ```elixir
   Gust.Repo.insert!(%Gust.DagSource{
     name:    "daily_backup",
     content: File.read!("priv/dags/daily_backup.ex"),
     format:  "elixir",
     enabled: true
   })
   ```

### Workflow Example

1. **Admin inserts or updates DAG** in database (or via UI)

2. **Gust detects change** within 30 seconds (or your configured interval)

3. **DAG becomes available** for execution immediately

4. **No redeployment needed** — perfect for dynamic systems

### Schema

```
Table: gust_dag_sources
├── id (primary key)
├── name (string, unique) — DAG identifier
├── content (text) — DAG definition (Elixir or YAML code)
├── format (string) — "elixir" or "yaml"
├── version (integer) — Optional version tracking
├── enabled (boolean) — Is this DAG active?
├── description (text) — Optional documentation
└── timestamps (inserted_at, updated_at)
```

### Managing DAGs

**Enable/Disable DAG:**
```sql
UPDATE gust_dag_sources SET enabled = false WHERE name = 'old_dag';
```

**View all DAGs:**
```sql
SELECT name, format, enabled, updated_at FROM gust_dag_sources ORDER BY name;
```

**Update DAG:**
```sql
UPDATE gust_dag_sources SET content = '...', updated_at = NOW() WHERE name = 'my_dag';
```

**Version History (keep updated_at):**
```sql
-- Gust will reload when updated_at changes
UPDATE gust_dag_sources
SET content = '...', version = version + 1, updated_at = NOW()
WHERE name = 'my_dag';
```

## S3 Source

### Configuration

```elixir
config :gust, dag_source: %{
  type:   "S3",
  bucket: "my-dags-bucket",               # Required
  prefix: "workflows/",                   # Optional (default: "")
  region: "us-west-2",                    # Optional (default: "us-east-1")
  poll_seconds: 30,                       # Optional (default: 30)
  access_key_id: nil,                     # Optional (uses credential chain if nil)
  secret_access_key: nil                  # Optional (uses credential chain if nil)
}
```

### Authentication

The S3 source uses the AWS SDK credential resolution chain in this order:

1. **Explicit credentials** (if provided in config):
   ```elixir
   config :gust, dag_source: %{
     type:   "S3",
     bucket: "my-dags",
     access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
     secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
   }
   ```

2. **Environment variables:**
   ```bash
   export AWS_ACCESS_KEY_ID="AKIA..."
   export AWS_SECRET_ACCESS_KEY="wJal..."
   ```

3. **AWS credentials file** (~/.aws/credentials):
   ```ini
   [default]
   aws_access_key_id = AKIA...
   aws_secret_access_key = wJal...
   ```

4. **IAM role** (when running on EC2, ECS, or Lambda)

### S3 Bucket Structure

Organize DAGs in your S3 bucket with a clear structure:

```
s3://my-dags-bucket/
├── workflows/
│   ├── backup.ex
│   ├── deploy.ex
│   └── analytics.yml
├── scheduled/
│   ├── daily_cleanup.ex
│   └── hourly_sync.ex
└── deprecated/
    └── old_workflow.ex
```

Use the `prefix` configuration to limit which DAGs load:

```elixir
# Load only workflows/ directory
config :gust, dag_source: %{
  type:   "s3",
  bucket: "my-dags-bucket",
  prefix: "workflows/"
}
```

### DAG Naming

S3 object keys are converted to DAG names by removing the prefix and extension:

- `workflows/backup.ex` (with prefix "workflows/") → DAG name: `backup`
- `workflows/production/deploy.ex` → DAG name: `production/deploy`
- `workflows/v2/analytics.yml` → DAG name: `v2/analytics`

This preserves directory structure in DAG names, allowing organization across multiple deployment tiers.

### Configuration Examples

**Development with local AWS credentials:**
```elixir
config :gust, dag_source: %{
  type:   "s3",
  bucket: "dev-dags",
  region: "us-east-1"
  # Uses ~/.aws/credentials automatically
}
```

**Production with IAM role (EC2/ECS):**
```elixir
config :gust, dag_source: %{
  type:   "s3",
  bucket: "prod-dags-bucket",
  prefix: "production/",
  region: "us-west-2",
  poll_seconds: 60
  # No credentials needed - uses IAM role
}
```

**Multi-environment with explicit credentials:**
```elixir
config :gust, dag_source: %{
  type:   "s3",
  bucket: System.get_env("AWS_DAG_BUCKET"),
  region: System.get_env("AWS_REGION", "us-east-1"),
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  poll_seconds: 30
}
```

### Workflow Example

1. **Developer updates DAG** in Git:
   ```bash
   git commit -m "Add new data pipeline"
   git push origin main
   ```

2. **CI/CD deploys to S3:**
   ```bash
   aws s3 cp dags/analytics.ex s3://prod-dags/workflows/
   ```

3. **Gust detects change** within 30 seconds

4. **New DAG is immediately available** for execution

### IAM Permissions

For Gust to access S3, the IAM role/user needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::my-dags-bucket"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::my-dags-bucket/*"
    }
  ]
}
```

### Supported File Formats

S3 source automatically detects and parses:
- `.ex` — Elixir DAG definitions
- `.yml` — YAML DAG definitions
- `.yaml` — YAML DAG definitions (alternative extension)

Other files are silently ignored.

### Performance

- **Load time:** 500ms-5s (network latency + S3 API)
- **Change detection:** Every 30 seconds (configurable)
- **Overhead:** S3 API calls (minimal cost)
- **Scales to:** 100s-1000s of DAGs

### Troubleshooting

**DAGs not loading:**
- Check IAM permissions (s3:ListBucket, s3:GetObject)
- Verify bucket name and region are correct
- Check S3 objects have correct extensions (.ex, .yml, .yaml)
- Look for AWS auth errors in logs

**Slow loading:**
- Reduce number of objects by using a more specific `prefix`
- Increase `poll_seconds` to reduce polling frequency
- Check network connectivity to S3

**Authentication failing:**
- Verify AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set
- Check IAM role is attached to EC2/ECS instance
- Verify credentials have not expired

## Switching Sources

To change sources, only configuration needs to be updated:

### From Folder to Git

```elixir
# Before (config/dev.exs)
config :gust, dag_source: {Gust.DAG.Source.Folder, folder: "/dags"}

# After (config/dev.exs)
config :gust, dag_source: {Gust.DAG.Source.Git, url: "git@github.com:company/dags.git"}
```

**No code changes needed** — just update config and restart Gust.

## Performance Considerations

### Folder Source
- **Load time:** ~50-100ms (local filesystem)
- **Change detection:** Instant (OS watching)
- **Overhead:** Minimal
- **Scales to:** 1000s of DAGs

### Git Source
- **Load time:** 100ms-1s (git operations)
- **Change detection:** Every 30 seconds (configurable)
- **Overhead:** Disk I/O, network latency
- **Scales to:** 100s of DAGs

### S3 Source
- **Load time:** 500ms-5s (S3 API + network)
- **Change detection:** Every 30 seconds (configurable)
- **Overhead:** S3 API calls (minimal cost)
- **Scales to:** 100s-1000s of DAGs

### Database Source
- **Load time:** 10-100ms (database query)
- **Change detection:** Every 30 seconds (configurable)
- **Overhead:** Database queries, network latency
- **Scales to:** 1000s of DAGs

**Recommendation:**
- **Development:** Use Folder source (instant feedback)
- **Small-to-medium deployments:** Use Git source (GitOps)
- **Cloud-native deployments:** Use S3 source (scalability + managed service)
- **Large/dynamic systems:** Use Database source (maximum flexibility)

## Troubleshooting

### DAG not loading

**Folder source:**
- Check file permissions (readable by Gust process)
- Verify DAG syntax with `mix compile`
- Check logs for parse errors

**Git source:**
- Verify URL is correct
- Check branch exists
- Verify credentials (if private repo)
- Check network connectivity
- Look for egit errors in logs

**Database source:**
- Run migrations: `mix ecto.migrate`
- Verify DAG record has `enabled = true`
- Check DAG syntax (Elixir or YAML)
- Verify timestamp was updated: `SELECT updated_at FROM gust_dag_sources WHERE name = '...'`

### Change not detected

**Folder source:**
- File watching requires inotify (Linux) or fsevents (macOS)
- Try restarting Gust if watcher fails

**Git/Database source:**
- Check poll_seconds configuration (default 30s)
- For Git: Verify commit is pushed to configured branch
- For Database: Verify `updated_at` was changed

### Authentication failing (Git)

- Verify credentials type matches repository URL (SSH for git@, HTTPS for https://)
- Check SSH keys have correct permissions (600)
- Verify token/password is not expired
- Check System.get_env() for environment variable credentials

## Future Enhancements

Possible future DAG sources under consideration:
- **HTTP API Source:** Fetch DAGs from remote HTTP endpoint
- **Consul/etcd:** Distributed configuration management
- **Multi-source Hybrid:** Load from primary source with fallback to secondary
- **CloudFormation/Terraform:** Infrastructure-as-Code DAG definitions
- **Kubernetes ConfigMaps:** Load DAGs from Kubernetes native resources

## See Also

- [Writing DAGs](writing_dags.md) — Create DAG definitions
- [Configuration](configuration.md) — General Gust configuration
