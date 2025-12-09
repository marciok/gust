# Gust

![Gust Logo](https://gust-github.s3.us-east-1.amazonaws.com/gust-symbol-logo.png)



A task orchestration system designed to be efficient, fast and developer-friendly.


[![Test](https://github.com/marciok/gust/actions/workflows/test.yml/badge.svg)](https://github.com/marciok/gust/actions/workflows/test.yml)[![Coverage Status](https://coveralls.io/repos/github/marciok/gust/badge.svg?branch=main)](https://coveralls.io/github/marciok/gust?branch=main)

[![Gust Web](https://img.shields.io/hexpm/v/gust_web?color=0084d1&label=Gust+Web)](https://hexdocs.pm/gust_web)

[![Gust](https://img.shields.io/hexpm/v/gust_web?color=0084d1&label=Gust)](https://hexdocs.pm/gust)

---
## Motivation
As a CTO and founder, I was tired of spending buckets of money to set up and manage [Airflow](https://airflow.apache.org/), dealing with multiple databases, countless processes, Docker complexity, and of course its outdated and buggy UI. So we decided to build something that kept what we liked about Airflow and ditched what we didn’t. The result is Gust: a platform that’s 10× more efficient, faster, and far easier to set up.

Gust is the perfect fit for our needs, and I encourage you to try it and push it even further. There’s still plenty of room for improvements and new features. If you spot something or want to contribute an idea, don’t be shy! Drop an Issue or submit a PR.

---
## Overview

### DAG Code Example
```elixir
defmodule HelloWorld do
  alias Gust.Flows
  use Gust.DSL
  require Logger

  task :first_task, downstream: [:second_task], store_result: true do
    greetings = "Hi from first_task"
    Logger.info(greetings)
    %{result: greetings}
  end

  task :second_task, ctx: %{run_id: run_id} do
    task = Flows.get_task_by_name_run("first_task", run_id)
    Logger.info(task.result)
  end
end

```

### Web Interface

![ss-1](https://gust-github.s3.us-east-1.amazonaws.com/gust-ss-1.png)

![ss2](https://gust-github.s3.us-east-1.amazonaws.com/gust-ss-2.png)
---





## Getting started

### Prerequisites

- [x] macOS/Ubuntu
- [x] Elixir must be at least [this version](https://github.com/marciok/gust/blob/main/.tool-versions)
- [x] Postgres


## Creating a new Gust app

1. Replace `my_app` for your app name and run:

```
GUST_APP=my_app bash -c "$(curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/setup_gust_app.sh)"

```
	 
2. Configure Postgres credentials on `my_app/config/dev.exs`

3. Run database setup:
	 `mix ecto.create --repo Gust.Repo && mix ecto.migrate --repo Gust.Repo`
	 
4. Run Gust start:
	 `mix gust.start`

5. Check [the docs](https://hexdocs.pm/gust/Gust.DSL.html) on how to customize your DAG 🎉
 

---

### Core Features

  - Task orchestration with Cron-style scheduling and dependency-aware DAGs via the Gust DSL.
  - Manual task controls: stop running tasks, cancel retries, and restart tasks on demand.
  - Run-time tracking, corrupted-state recovery, and graceful handling of syntax errors during development.
  - Retry logic with backoff, plus state clearing for clean restarts.
  - Hook for finished dag run.
  - Web UI for live monitoring and secrets editing.



---
### Sponsors


![Comparacar](https://gust-github.s3.us-east-1.amazonaws.com/comparacar-sponsor-v2.jpg)
[Find the best offers and save money on car subscription service.](https://comparacar.com.br)


## License

Copyright (C) 2025, Marcio Klepacz

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
