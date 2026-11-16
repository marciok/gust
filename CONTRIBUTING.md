# Contributing to Gust

Thanks for considering contributing to Gust! Issues and PRs are welcome —
if you spot something or want to contribute an idea, don't be shy.

## Open an Issue First

Every PR needs an issue. Before writing code,
[open an issue](https://github.com/marciok/gust/issues/new) describing the bug
or feature, or comment on an existing one, and wait until we agree on the
approach. This way you don't spend time on a PR that can't be merged because the
direction didn't match what the maintainers had in mind.

When you open the PR, link the issue in its description (for example
`Fixes #123`).

## Keep Changes Small and Granular

- One PR solves one issue. If you find something unrelated along the way, open a
  separate issue for it instead of folding it in.
- Prefer several small PRs over one large one. A feature that needs a refactor
  first is easier to review as two PRs: the refactor, then the feature.
- Keep commits focused, with messages that say what changed
  (`feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `chore: ...`).
- Don't reformat or rename code you aren't otherwise changing.

## Document with `@doc`, Not Comments

Don't add explanatory `#` comments to code. When something needs explaining:

- Describe a module in `@moduledoc` and a public function in `@doc`. They show up
  in the generated docs and stay next to the code they describe.
- Private functions can't have `@doc`. If their behaviour needs explaining, put
  it in the module's `@moduledoc`; otherwise let a clear function name speak for
  itself.
- If a comment would only restate the code, leave it out.

```elixir
# Avoid
# Runs on the node that owns the run.
def local_snapshot(run_id, task_keys), do: ...

# Prefer
@doc """
Collects the process snapshot of a run on the local node. Called through
`:erpc` on the node that owns the run.
"""
def local_snapshot(run_id, task_keys), do: ...
```

## A Note on AI-Assisted PRs

I do read the code. It's fine to use AI to help write your PR, but this
project is not "vibe coded" — you must understand every change you're
submitting and be able to explain it. Pay special attention to extra
conditionals, defensive checks, or edge-case handling AI tools tend to add
unprompted; if you can't justify why something is there, remove it.

## Running Tests Locally

1. Start Postgres.
2. Copy `.env.example` to `.env.test`:
   ```bash
   cp .env.example .env.test
   ```
3. Load test environment variables:
   ```bash
   source .env.test
   ```
4. Install dependencies:
   ```bash
   mix setup
   ```
5. Create and migrate the test database:
   ```bash
   MIX_ENV=test mix ecto.create
   MIX_ENV=test mix ecto.migrate
   ```
6. Run the whole suite the way CI does, across all apps:
   ```bash
   MIX_ENV=test mix coveralls.html --umbrella
   ```
   The coverage report is written to `cover/excoveralls.html`.

### Useful Commands

```bash
mix test test/path/to/file_test.exs
mix test --failed
MIX_ENV=test mix coveralls.html --umbrella
```

### Common Failures

- `connection refused`: Postgres is not running or `PGHOST`/`PGUSER`/`PGPASSWORD` are incorrect.
- `database "gust_rc_test" does not exist`: run `MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate`.

## Before Opening the PR

CI runs these checks; run them locally first:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix lint
MIX_ENV=test mix coveralls.html --umbrella
```

PRs against `main` also run the release validation, which builds the Hex
packages, runs the end-to-end suite in `e2e/` against a generated app, and builds
the Docker images. To run it locally before pushing, build the web assets and
run `make preflight` (requires Docker):

```bash
(cd apps/gust_web && mix assets.deploy)
make preflight
```
