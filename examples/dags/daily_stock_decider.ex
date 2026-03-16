defmodule DailyStockDecider do
  @moduledoc """
  A daily stock decision DAG that collects market, company, news, and macro inputs,
  asks multiple LLMs for an independent recommendation, and produces a final
  buy/hold/sell decision for the configured ticker.

  ## Overview

    This DAG is designed to evaluate a single stock, currently `#{@ticker}`, once per run.
    It gathers:

    - recent daily market data
    - company fundamentals
    - recent ticker-related news
    - broad US macroeconomic context

    After normalizing the inputs, it sends the same prompt to GPT, Gemini, and Claude.
    Each model returns a structured recommendation with:

    - `action`
    - `confidence`
    - `rationale`
    - `risks`

    The DAG then applies a simple voting mechanism:

    - `buy` = `1`
    - `hold` = `0`
    - `sell` = `-1`

    The final action is derived from the sum of the three model votes:

    - `>= 2` → `buy`
    - `<= -2` → `sell`
    - otherwise → `hold`

    At the end of the run, the result and model summaries are emailed.

  ## Notes

    This DAG is intended as an experimentation and orchestration example, not financial
    advice. The final decision is based on LLM output plus a simple consensus rule, so it
    should be treated as a decision-support workflow rather than an autonomous trading
    system.
  """
  use Gust.DSL, schedule: "0 12 * * *"
  alias Gust.Flows
  require Logger
  @ticker "nvda"

  defp build_summary([]) do
    %{
      points: 0,
      first_datetime: nil,
      last_datetime: nil,
      latest_close: nil
    }
  end

  defp build_summary(values) do
    first = List.first(values)
    last = List.last(values)
    {latest_close, _} = Float.parse(last["close"])

    %{
      points: length(values),
      first_datetime: first["datetime"],
      last_datetime: last["datetime"],
      latest_close: latest_close
    }
  end

  defp parse_md_json(raw) do
    raw
    |> String.trim()
    |> String.replace_prefix("```json\\n", "")
    |> String.replace_prefix("```json\n", "")
    |> String.replace_suffix("\\n```", "")
    |> String.replace_suffix("\n```", "")
  end

  defp prompt(%{"company" => company, "market" => market, "news" => news, "macro" => macro, "as_of" => as_of}) do
    """
    You are analyzing whether to buy, hold, or sell NVDA for a daily decision as of: #{inspect(as_of)}.

    Company:
    #{inspect(company)}

    Market:
    #{inspect(market)}

    News:
    #{inspect(news)}

    Macro:
    #{inspect(macro)}

    Return JSON with:
    - action: buy | hold | sell
    - confidence: 0.0 to 1.0
    - rationale
    - risks
    """
  end

  task :fetch_market_data, save: true, downstream: [:normalize_inputs] do
    url = "https://api.twelvedata.com/time_series"
    api_key = Flows.get_secret_by_name("TWELVEDATA").value

    params =
      %{
        symbol: @ticker,
        interval: "1day",
        outputsize: 30,
        timezone: "Exchange",
        apikey: api_key,
        format: "JSON",
        order: "ASC"
      }

    case Req.get(url, params: params) do
      {:ok, %{status: 200, body: %{"status" => "ok", "meta" => meta, "values" => values}}} ->
        %{
          type: :market_data,
          status: :ok,
          data: %{
            ticker: @ticker,
            source: :twelve_data,
            meta: meta,
            values: values,
            summary: build_summary(values)
          },
          fetched_at: DateTime.utc_now()
        }
    end
  end

  task :fetch_company_fundamentals, save: true, downstream: [:normalize_inputs] do
    api_key = Flows.get_secret_by_name("FINANCIALMODELINGPREP").value

    url = "https://financialmodelingprep.com/stable/profile"

    case Req.get(url, params: [symbol: @ticker, apikey: api_key]) do
      {:ok, %{status: 200, body: [profile | _]}} ->
        %{
          type: :company_fundamentals,
          status: :ok,
          data: profile,
          fetched_at: DateTime.utc_now()
        }
    end
  end

  task :fetch_news, save: true, downstream: [:normalize_inputs] do
    url = "https://api.marketaux.com/v1/news/all"
    api_key = Flows.get_secret_by_name("MARKETAUX").value

    case Req.get(
           url: url,
           params: [filter_entities: true, language: "en", api_token: api_key, symbols: @ticker]
         ) do
      {:ok, %{status: 200, body: %{"data" => data, "meta" => meta}}} ->
        %{
          type: :news,
          status: :ok,
          data: %{
            ticker: @ticker,
            meta: meta,
            items: data
          },
          fetched_at: DateTime.utc_now()
        }
    end
  end

  task :fetch_macro_context, downstream: [:normalize_inputs], save: true do
    api_key = Flows.get_secret_by_name("PERPLEXITY").value
    url = "https://api.perplexity.ai/search"

    query =
      "US stock market macro context today: Federal Reserve policy outlook, latest CPI inflation, unemployment trend, Treasury yield movement, next major economic calendar events, and overall risk-on or risk-off sentiment"

    body = %{
      query: query,
      max_results: 5,
      max_tokens_per_page: 512
    }

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, headers: headers, json: body) do
      {:ok, %{status: 200, body: response_body}} ->
        %{
          type: :macro_context,
          status: :ok,
          data: %{
            source: :perplexity,
            query: body.query,
            result: response_body
          },
          fetched_at: DateTime.utc_now()
        }
    end
  end

  task :normalize_inputs,
    downstream: [:ask_gpt, :ask_gemini, :ask_claude],
    ctx: %{run_id: run_id},
    save: true do
    fundamentals = Flows.get_task_by_name_run("fetch_company_fundamentals", run_id).result
    market_data = Flows.get_task_by_name_run("fetch_market_data", run_id).result
    news = Flows.get_task_by_name_run("fetch_news", run_id).result
    macro = Flows.get_task_by_name_run("fetch_macro_context", run_id).result

    %{
      type: :normalized_inputs,
      ticker: @ticker,
      as_of: DateTime.utc_now(),
      company: fundamentals,
      market: market_data,
      news: news,
      macro: macro,
      fetched_at: DateTime.utc_now()
    }
  end

  task :ask_gpt, ctx: %{run_id: run_id}, downstream: [:decide_action], save: true do
    inputs = Flows.get_task_by_name_run("normalize_inputs", run_id).result
    api_key = Flows.get_secret_by_name("OPENAI").value
    Logger.info(inputs)

    case Req.post("https://api.openai.com/v1/responses",
           headers: [
             {"authorization", "Bearer #{api_key}"},
             {"content-type", "application/json"}
           ],
           json: %{
             model: "gpt-5.4",
             input: prompt(inputs)
           }
         ) do
      {:ok, %{status: 200, body: %{"output" => [%{"content" => [content]}]}}} ->
        Jason.decode!(content["text"])
    end
  end

  task :ask_gemini, downstream: [:decide_action], ctx: %{run_id: run_id}, save: true do
    inputs = Flows.get_task_by_name_run("normalize_inputs", run_id).result

    api_key = Flows.get_secret_by_name("GEMINI").value

    url =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

    body = %{
      contents: [%{parts: [%{text: prompt(inputs)}]}]
    }

    case Req.post(url,
           headers: [{"content-type", "application/json"}, {"x-goog-api-key", api_key}],
           json: body
         ) do
      {:ok,
       %{
         status: 200,
         body: %{
           "candidates" => [
             %{"content" => %{"parts" => [%{"text" => raw}]}}
           ]
         }
       }} ->
        parse_md_json(raw) |> Jason.decode!()
    end
  end

  task :ask_claude, downstream: [:decide_action], ctx: %{run_id: run_id}, save: true do
    inputs = Flows.get_task_by_name_run("normalize_inputs", run_id).result
    Logger.info(inputs)

    url = "https://api.anthropic.com/v1/messages"
    api_key = Flows.get_secret_by_name("CLAUDE").value

    body = %{
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      messages: [
        %{role: "user", content: prompt(inputs)}
      ]
    }

    case Req.post(url,
           connect_options: [timeout: 90_000],
           receive_timeout: 120_000,
           headers: [
             {"content-type", "application/json"},
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           json: body
         ) do
      {:ok,
       %{
         status: 200,
         body: %{
           "content" => [
             %{"text" => raw}
           ]
         }
       }} ->
        parse_md_json(raw) |> Jason.decode!()
    end
  end

  task :decide_action, ctx: %{run_id: run_id}, downstream: [:email_results], save: true do
    gpt = Flows.get_task_by_name_run("ask_gpt", run_id).result
    gemini = Flows.get_task_by_name_run("ask_gemini", run_id).result
    claude = Flows.get_task_by_name_run("ask_claude", run_id).result

    actions = %{
      "hold" => 0,
      "buy" => 1,
      "sell" => -1
    }

    action_reduced =
      [{"GPT", gpt}, {"Gemini", gemini}, {"Claude", claude}]
      |> Enum.reduce(0, fn {name, llm}, acc ->
        Logger.info("#{name}: #{llm["action"]}")
        Logger.info("rationale: #{llm["rationale"]}")
        Logger.info("confidence: #{llm["confidence"]}")

        actions[llm["action"]] + acc
      end)

    result =
      cond do
        action_reduced >= 2 ->
          "buy"

        action_reduced <= -2 ->
          "sell"

        true ->
          "hold"
      end

    %{result: result}
  end

  task :email_results, ctx: %{run_id: run_id} do
    gpt = Flows.get_task_by_name_run("ask_gpt", run_id).result
    gemmini = Flows.get_task_by_name_run("ask_gemini", run_id).result
    claude = Flows.get_task_by_name_run("ask_claude", run_id).result
    %{"result" => decide_action} = Flows.get_task_by_name_run("decide_action", run_id).result

    %{"password" => password, "to" => to, "from" => from} =
      Flows.get_secret_by_name("MAILGUN").value |> Jason.decode!()

    summary =
      [{"GPT", gpt}, {"Gemmini", gemmini}, {"Claude", claude}]
      |> Enum.reduce("", fn {name, llm}, acc ->
        table = """
          #{name}: #{llm["action"]}
          rationale: #{llm["rationale"]}
          confidence: #{llm["confidence"]}
        """

        "\n #{table} \n#{acc}"
      end)

    Logger.info(summary)

    Req.post!(
      url: "https://api.mailgun.net/v3/email.gustflow.com/messages",
      auth: {:basic, "api:#{password}"},
      form_multipart: [
        {"from", from},
        {"to", to},
        {"subject", "Alert for: #{@ticker} -> #{decide_action}"},
        {"text", "Here is your summary: #{summary}"}
      ]
    )
  end
end
