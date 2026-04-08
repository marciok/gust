# GustWeb

The web UI for Gust.

---

GustWeb is a Phoenix web server. Run `mix phx.server` to start it.

By default, it also starts the Gust core, which means DAGs are loaded and executed.

If you are working in multi-node mode and want to run only the web server, use:

`GUST_ROLE=web mix phx.server`
