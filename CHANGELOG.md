# Changelog

All notable changes to Gust are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

Versions are the `gust` and `gust_web` release, which share a version and a
`vX.Y.Z` tag. Releases of `gust_py` and `gust_shell` are noted in the release
they ship with.

Add your change under the version being developed, with `Unreleased` in place
of the date. The publish workflow requires the version to have a dated entry.

## [0.1.42] - Unreleased

`gust_py` 0.1.15 and `gust_shell` 0.1.2.

### Added

- Health check for running tasks and runs on the DAG dashboard. It shows the
  state of the Elixir processes behind a task or run, including the owning node
  and the external OS process, and flags tasks marked `running` whose process
  is gone as zombies ([#176](https://github.com/marciok/gust/issues/176),
  [#179](https://github.com/marciok/gust/pull/179)).
- Limit mapped task concurrency with `config :gust, :mapped_tasks, max_parallel: n`.
  Instances run in pages, and restarts follow the same limit. A warning is
  logged when no limit is set
  ([#177](https://github.com/marciok/gust/issues/177),
  [#178](https://github.com/marciok/gust/pull/178)).
- Warning on the dashboard when a paused DAG is triggered
  ([#173](https://github.com/marciok/gust/issues/173),
  [#175](https://github.com/marciok/gust/pull/175)).
- Pull requests against `main` run the release validation: version pins,
  Hex package builds, the e2e suite against a generated app, and the Docker
  image builds.

### Fixed

- The dashboard run history no longer shows runs from other DAGs whose PubSub
  topic collided ([#172](https://github.com/marciok/gust/issues/172),
  [#174](https://github.com/marciok/gust/pull/174)).

## [0.1.41] - 2026-10-26

### Fixed

- Scheduled DAGs no longer trigger twice: Postgres advisory locks use a direct
  connection ([#163](https://github.com/marciok/gust/issues/163),
  [#164](https://github.com/marciok/gust/pull/164)).
- Updated dependencies so Gust installs without version conflicts
  ([#165](https://github.com/marciok/gust/pull/165)).

### Internal

- Release preflight installs a generated app and runs an e2e Playwright suite
  against it ([#168](https://github.com/marciok/gust/pull/168),
  [#169](https://github.com/marciok/gust/pull/169)).

## [0.1.40] - 2026-09-25

### Added

- Shell tasks with the new `gust_shell` package, including command templates
  and logger backend integration
  ([#148](https://github.com/marciok/gust/pull/148),
  [#156](https://github.com/marciok/gust/pull/156),
  [#157](https://github.com/marciok/gust/pull/157)).
- `task_action` for reusable task code
  ([#146](https://github.com/marciok/gust/issues/146),
  [#153](https://github.com/marciok/gust/pull/153)).
- Status filter for mapped tasks
  ([#134](https://github.com/marciok/gust/issues/134),
  [#152](https://github.com/marciok/gust/pull/152)).

### Fixed

- Restarting mapped tasks ([#155](https://github.com/marciok/gust/pull/155)).

### Documentation

- Guides moved out of the root README
  ([#151](https://github.com/marciok/gust/pull/151)).

## [0.1.39] - 2026-09-09

### Added

- Dark mode ([#133](https://github.com/marciok/gust/issues/133),
  [#143](https://github.com/marciok/gust/pull/143)).
- Mobile-responsive dashboard ([#142](https://github.com/marciok/gust/pull/142)).
- Retry countdown on retrying tasks
  ([#145](https://github.com/marciok/gust/pull/145)).
- External reference on reported task errors
  ([#141](https://github.com/marciok/gust/pull/141)).
- Docker images are published on release
  ([#137](https://github.com/marciok/gust/pull/137)).

### Changed

- External processes run through erlexec
  ([#138](https://github.com/marciok/gust/issues/138),
  [#147](https://github.com/marciok/gust/pull/147)).

## [0.1.38] - 2026-08-26

### Added

- Task error reporter ([#132](https://github.com/marciok/gust/pull/132)).
- Filter DAGs with failed recent runs
  ([#126](https://github.com/marciok/gust/pull/126)).
- Runs in the run list link to their run dashboard
  ([#117](https://github.com/marciok/gust/issues/117),
  [#128](https://github.com/marciok/gust/pull/128)).
- Search runs by params ([#127](https://github.com/marciok/gust/issues/127),
  [#129](https://github.com/marciok/gust/pull/129)).
- Graceful stop for runs in any status
  ([#131](https://github.com/marciok/gust/pull/131)).

### Changed

- Reworked the DAG runner processes and removed an N+1 query for task statuses
  ([#123](https://github.com/marciok/gust/pull/123)).
- The error section is hidden while a run is running
  ([#130](https://github.com/marciok/gust/pull/130)).

## [0.1.37] - 2026-07-22

### Added

- Stacktraces for Elixir task errors
  ([#110](https://github.com/marciok/gust/pull/110)).
- Raise a non-recoverable error to skip retries
  ([#111](https://github.com/marciok/gust/pull/111)).
- Task status colors on the Mermaid chart
  ([#112](https://github.com/marciok/gust/pull/112)).
- JSON viewer for task params and results
  ([#114](https://github.com/marciok/gust/pull/114)).

## [0.1.36] - 2026-07-15

### Added

- Batch actions on runs ([#102](https://github.com/marciok/gust/pull/102)).
- Recent runs on the DAG summary
  ([#107](https://github.com/marciok/gust/pull/107)).
- System page ([#108](https://github.com/marciok/gust/pull/108)).

### Changed

- Runs are dispatched through Postgres notifications, with bulk wake-ups
  ([#105](https://github.com/marciok/gust/pull/105),
  [#109](https://github.com/marciok/gust/pull/109)).

## [0.1.35] - 2026-07-02

### Added

- `wait_for` task option: a task waits until it is resumed from the API or MCP
  ([#93](https://github.com/marciok/gust/pull/93)).
- Cancel a task, including expanded mapped tasks
  ([#94](https://github.com/marciok/gust/pull/94),
  [#101](https://github.com/marciok/gust/pull/101)).
- Show a single mapped task ([#100](https://github.com/marciok/gust/pull/100)).
- Empty state for task logs ([#97](https://github.com/marciok/gust/pull/97)).
- The cron scheduler restarts in development when a DAG's schedule changes
  ([#11](https://github.com/marciok/gust/issues/11),
  [#98](https://github.com/marciok/gust/pull/98)).

### Fixed

- `store_result` validates the whole result, so non-JSON-serializable results
  fail with a clear error instead of at the database write
  ([#95](https://github.com/marciok/gust/issues/95),
  [#96](https://github.com/marciok/gust/pull/96)).

### Removed

- Upgrade compatibility with 0.1.29
  ([#91](https://github.com/marciok/gust/pull/91)).

## [0.1.34] - 2026-06-24

### Added

- Aggregated status for expanded tasks
  ([#82](https://github.com/marciok/gust/issues/82),
  [#89](https://github.com/marciok/gust/pull/89)).

### Fixed

- Bad exits of linked processes are caught
  ([#83](https://github.com/marciok/gust/issues/83),
  [#84](https://github.com/marciok/gust/pull/84)).
- No absolute path is stored at compile time
  ([#85](https://github.com/marciok/gust/pull/85)).
- Phoenix JavaScript was loaded twice in the dashboard assets
  ([#87](https://github.com/marciok/gust/issues/87),
  [#88](https://github.com/marciok/gust/pull/88)).

## [0.1.33] - 2026-06-15

### Added

- Filter DAG runs by status ([#73](https://github.com/marciok/gust/pull/73)).
- Expand mapped tasks ([#78](https://github.com/marciok/gust/pull/78)).

### Fixed

- The dashboard updates a task after it is cancelled
  ([#22](https://github.com/marciok/gust/issues/22),
  [#74](https://github.com/marciok/gust/pull/74)).

### Removed

- Mailer ([#80](https://github.com/marciok/gust/pull/80)).

## [0.1.32] - 2026-05-29

### Added

- HTTP API ([#57](https://github.com/marciok/gust/issues/57),
  [#62](https://github.com/marciok/gust/pull/62)).
- Run params, settable from the API, the CLI and the `trigger_dag_run` MCP tool
  ([#58](https://github.com/marciok/gust/issues/58),
  [#66](https://github.com/marciok/gust/pull/66),
  [#67](https://github.com/marciok/gust/pull/67),
  [#71](https://github.com/marciok/gust/pull/71)).
- Skip tasks ([#68](https://github.com/marciok/gust/pull/68)).
- `dag_definition` CLI command ([#60](https://github.com/marciok/gust/pull/60)).

### Fixed

- Runs created through the API no longer default to `enqueued`
  ([#70](https://github.com/marciok/gust/issues/70),
  [#72](https://github.com/marciok/gust/pull/72)).

## [0.1.31] - 2026-05-08

### Added

- Gust CLI ([#54](https://github.com/marciok/gust/pull/54)).
- MCP router macro ([#52](https://github.com/marciok/gust/pull/52)).
- Docker image for gust core ([#50](https://github.com/marciok/gust/pull/50)).

### Changed

- The installer sets up a minimal Phoenix app
  ([#53](https://github.com/marciok/gust/pull/53)).
- Basic auth moved from the installer to an example
  ([#51](https://github.com/marciok/gust/pull/51)).

## [0.1.30] - 2026-05-04

### Added

- Igniter installer ([#44](https://github.com/marciok/gust/pull/44)).
- Docker files for gust_web apps ([#39](https://github.com/marciok/gust/pull/39)).
- Comma-separated DNS cluster queries
  ([#46](https://github.com/marciok/gust/pull/46)).

### Changed

- Date display format ([#45](https://github.com/marciok/gust/pull/45)).

### Fixed

- DAG DSL task options are validated at compile time
  ([#43](https://github.com/marciok/gust/pull/43)).

### Documentation

- Docker single-node instructions and agent skills
  ([#40](https://github.com/marciok/gust/pull/40),
  [#41](https://github.com/marciok/gust/pull/41)).

## [0.1.29] - 2026-04-07

### Added

- MCP server for development ([#37](https://github.com/marciok/gust/pull/37)).

### Documentation

- Daily stock decider example ([#36](https://github.com/marciok/gust/pull/36)).

## [0.1.28] - 2026-03-11

### Added

- `kill` on the runtime protocol ([#34](https://github.com/marciok/gust/pull/34)).

### Fixed

- Module name fix ([#32](https://github.com/marciok/gust/pull/32)).

## [0.1.27] - 2026-03-09

### Added

- Python tasks with the new `gust_py` package
  ([#30](https://github.com/marciok/gust/pull/30)).

### Changed

- `RetryingRunner` renamed to `RetryingTask`
  ([#26](https://github.com/marciok/gust/pull/26)).

### Documentation

- Multi-node instructions and local test instructions
  ([#20](https://github.com/marciok/gust/pull/20),
  [#28](https://github.com/marciok/gust/pull/28)).

## [0.1.26] - 2026-01-20

### Added

- Multi-node support ([#18](https://github.com/marciok/gust/pull/18)).

## [0.1.25] - 2025-12-18

### Added

- Run listing and deletion.

## [0.1.24] - 2025-12-10

### Removed

- Web assets from the Hex package.

## [0.1.23] - 2025-12-10

## [0.1.22] - 2025-12-09

First release published through GitHub Actions.

[0.1.42]: https://github.com/marciok/gust/compare/v0.1.41...HEAD
[0.1.41]: https://github.com/marciok/gust/compare/v0.1.40...v0.1.41
[0.1.40]: https://github.com/marciok/gust/compare/v0.1.39...v0.1.40
[0.1.39]: https://github.com/marciok/gust/compare/v0.1.38...v0.1.39
[0.1.38]: https://github.com/marciok/gust/compare/v0.1.37...v0.1.38
[0.1.37]: https://github.com/marciok/gust/compare/v0.1.36...v0.1.37
[0.1.36]: https://github.com/marciok/gust/compare/v0.1.35...v0.1.36
[0.1.35]: https://github.com/marciok/gust/compare/v0.1.34...v0.1.35
[0.1.34]: https://github.com/marciok/gust/compare/v0.1.33...v0.1.34
[0.1.33]: https://github.com/marciok/gust/compare/v0.1.32...v0.1.33
[0.1.32]: https://github.com/marciok/gust/compare/v0.1.31...v0.1.32
[0.1.31]: https://github.com/marciok/gust/compare/v0.1.30...v0.1.31
[0.1.30]: https://github.com/marciok/gust/compare/v0.1.29...v0.1.30
[0.1.29]: https://github.com/marciok/gust/compare/v0.1.28...v0.1.29
[0.1.28]: https://github.com/marciok/gust/compare/v0.1.27...v0.1.28
[0.1.27]: https://github.com/marciok/gust/compare/v0.1.26...v0.1.27
[0.1.26]: https://github.com/marciok/gust/compare/v0.1.25...v0.1.26
[0.1.25]: https://github.com/marciok/gust/compare/v0.1.24...v0.1.25
[0.1.24]: https://github.com/marciok/gust/compare/v0.1.23...v0.1.24
[0.1.23]: https://github.com/marciok/gust/compare/v0.1.22...v0.1.23
[0.1.22]: https://github.com/marciok/gust/releases/tag/v0.1.22
