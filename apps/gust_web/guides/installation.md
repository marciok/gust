# Installation

*Want to try Gust quickly? Start with the [Docker example](https://github.com/marciok/gust/tree/main/examples/docker). If you want full customization and extension, follow the instructions below.*

## Prerequisites

- [x] macOS/Ubuntu
- [x] Elixir must be at least [this version](https://github.com/marciok/gust/blob/main/.tool-versions)
- [x] Postgres

## Creating a new Gust app

1. Replace `my_app` with your app name and run:

   ```
   GUST_APP=my_app bash -c "$(curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/setup_gust_app.sh)"
   ```

   *You can check what the install script does [here](https://github.com/marciok/gust/blob/main/setup_gust_app.sh)*

2. Configure Postgres credentials in `my_app/config/dev.exs`.

3. Run database setup:

   - `mix ecto.create`
   - `mix ecto.migrate`

4. Start Gust:

   `mix phx.server`

5. Check [`Gust.DSL`](https://hexdocs.pm/gust/Gust.DSL.html) for how to customize your DAG.

6. Open `http://localhost:4000/gust/dags` to visualize your app.

## Adding Gust to an existing Phoenix app

If you already have a Phoenix project and want to add Gust in place, install
`gust_web` with [Igniter](https://hexdocs.pm/igniter).

1. If you do not have Igniter installed yet, bootstrap it first:

   ```sh
   mix local.hex --force
   mix archive.install hex igniter_new --force
   ```

2. From the root of your existing Phoenix project, install `gust_web`:

   ```sh
   mix igniter.install gust_web
   ```

   It will mount the dashboard at `/gust` in your router, and create a `dags/`
   folder.

3. Review your database config. Open `dev.exs` and set `Gust.Repo`'s
   credentials.

4. Run setup and start the app:

   ```sh
   mix ecto.create
   mix ecto.migrate
   mix phx.server
   ```

5. Open `http://localhost:4000/gust/dags`.
