# GustShell

Enable shell DAGs, written in YAML, in your Gust project.

## Motivation

A lot of orchestration is running commands in order: build, test, back up,
upload, deploy. Writing an Elixir module for each of those steps is more than
the job needs.

GustShell lets you describe those workflows as YAML files of shell commands,
while Gust handles scheduling, dependencies, retries and output capture. EEx
templates in commands and environment values read run params, secrets and
earlier task results.

## Guides

- [Installation](guides/installation.md) — add `gust_shell` to a Gust project
  and wire up the shell adapter.
- [Writing Shell DAGs](guides/writing_shell_dags.md) — a full DAG example,
  every task option and templates.
- [Under the Hood](guides/under_the_hood.md) — how Gust runs shell tasks.

## License

GustShell is released under the MIT License.
