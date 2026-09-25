# Contributing to Gust

Thanks for considering contributing to Gust! Issues and PRs are welcome —
if you spot something or want to contribute an idea, don't be shy.

## Before Opening a PR

Please [open an issue](https://github.com/marciok/gust/issues/new) describing
the bug or feature first, so we can align on the approach before you put work
into a PR. This avoids wasted effort on PRs that don't get merged because the
direction didn't match what the maintainers had in mind.

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
6. Run tests:
   ```bash
   mix test
   ```

### Useful Commands

```bash
mix test test/path/to/file_test.exs
mix test --failed
MIX_ENV=test mix coveralls.html --umbrella
```

### Common Failures

- `connection refused`: Postgres is not running or `PGHOST`/`PGUSER`/`PGPASSWORD` are incorrect.
- `database "gust_rc_test" does not exist`: run `MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate`.
