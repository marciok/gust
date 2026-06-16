defmodule FusionPrompt do
  @moduledoc """
  Model Fusion DAG.

  Implements the OpenRouter "Fusion" architecture: a prompt is dispatched to a
  panel of participant models in parallel, a judge model reads every panel
  response and produces a structured analysis (consensus, contradictions,
  partial coverage, unique insights, blind spots), and finally a synthesizer
  model writes the single best answer grounded in that analysis.

      prompt ─┐
              ├─> get_response (map over panel) ─> judge_analysis ─> synthesize
      panel ──┘

  Synthesizing the results of multiple models can significantly outperform what
  any individual model produces on its own.
  """

  require Logger
  use Gust.DSL
  alias Gust.Flows

  @open_router_api "https://openrouter.ai/api/v1"

  # The model that fuses the panel: judges the panel responses and writes the
  # final grounded answer. The blog's strongest single synthesizer.
  @synthesizer_model "anthropic/claude-opus-4.8"

  # Default participant panel: the latest model from each frontier family.
  # The prompt is dispatched to all of them in parallel.
  @default_panel [
    # Claude Opus latest
    "anthropic/claude-opus-4.8",
    # OpenAI GPT latest
    "openai/gpt-5.5",
    # Google Gemini Pro latest
    "google/gemini-3.1-pro-preview"
  ]

  task :prompt, downstream: [:get_response, :judge_analysis, :synthesize], save: true do
    prompt = "What are the strongest arguments for and against carbon taxes?"
    %{prompt: prompt}
  end

  # The panel: a set of participant models the prompt is dispatched to in
  # parallel. Diversity of perspectives is what drives the fusion lift.
  #
  # Defaults to one latest model from each of the three frontier families
  # (the blog's frontier panel). Override per run with a "panel" param holding
  # a list of OpenRouter model slugs.
  task :get_models, downstream: [:get_response], ctx: %{run_id: run_id}, save: true do
    run = Flows.get_run!(run_id)

    Map.get(run.params, "panel", @default_panel)
    |> Enum.map(&%{"canonical_slug" => &1})
  end

  # Fan out: one parallel instance per panel model, each answering the prompt.
  task :get_response,
    downstream: [:judge_analysis],
    map_over: :get_models,
    ctx: %{params: params, run_id: run_id},
    save: true do
    %{"prompt" => prompt} = Flows.get_task_by_name_run("prompt", run_id).result
    model = params["canonical_slug"]

    content =
      chat_completion(model, [
        %{role: "user", content: prompt}
      ])

    %{model: model, content: content}
  end

  # Judge: read every panel response and produce a structured analysis. This is
  # the heart of fusion — it surfaces where models agree, where they conflict,
  # and what each one uniquely contributes.
  task :judge_analysis,
    downstream: [:synthesize],
    ctx: %{run_id: run_id},
    save: true do
    %{"prompt" => prompt} = Flows.get_task_by_name_run("prompt", run_id).result
    responses = panel_responses(run_id)

    analysis =
      chat_completion(@synthesizer_model, [
        %{role: "system", content: judge_system_prompt()},
        %{role: "user", content: judge_user_prompt(prompt, responses)}
      ])

    parsed =
      case Jason.decode(strip_code_fence(analysis)) do
        {:ok, map} -> map
        {:error, _} -> %{"raw" => analysis}
      end

    %{analysis: parsed, panel_size: length(responses)}
  end

  # Synthesize: the calling model writes the final answer, grounded in both the
  # raw panel responses and the judge's structured analysis.
  task :synthesize, ctx: %{run_id: run_id}, save: true do
    %{"prompt" => prompt} = Flows.get_task_by_name_run("prompt", run_id).result
    %{"analysis" => analysis} = Flows.get_task_by_name_run("judge_analysis", run_id).result
    responses = panel_responses(run_id)

    answer =
      chat_completion(@synthesizer_model, [
        %{role: "system", content: synthesize_system_prompt()},
        %{role: "user", content: synthesize_user_prompt(prompt, responses, analysis)}
      ])

    Logger.info("Fusion answer:\n#{answer}")
    %{answer: answer}
  end

  # --- Helpers -------------------------------------------------------------

  defp open_router_token, do: Flows.get_secret_by_name("OPEN_ROUTER_KEY").value

  # Collect the non-empty panel responses for this run.
  defp panel_responses(run_id) do
    Flows.get_tasks_by_name("get_response", run_id)
    |> Enum.map(& &1.result)
    |> Enum.filter(fn
      %{"content" => content} -> is_binary(content) and content != ""
      _ -> false
    end)
  end

  # Call an OpenRouter chat completion and return the assistant message content.
  defp chat_completion(model, messages) do
    token = open_router_token()

    body =
      Jason.encode!(%{
        model: model,
        messages: messages
      })

    case HTTPoison.post(
           "#{@open_router_api}/chat/completions",
           body,
           [
             {"Authorization", "Bearer #{token}"},
             {"Content-Type", "application/json"}
           ],
           recv_timeout: 120_000
         ) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response_body
        |> Jason.decode!()
        |> get_in(["choices", Access.at(0), "message", "content"]) || ""

      {:ok, %{status_code: status, body: error_body}} ->
        Logger.warning("OpenRouter #{model} returned #{status}: #{error_body}")
        ""
    end
  end

  # Models sometimes wrap JSON in a ```json ... ``` fence; strip it before decoding.
  defp strip_code_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/```\z/, "")
    |> String.trim()
  end

  defp judge_system_prompt do
    """
    You are the judge in a model-fusion panel. Several independent models have
    each answered the same question. Your job is to analyze their responses, not
    to answer the question yourself.

    Respond with ONLY a valid JSON object with these keys, each an array of
    concise strings:
      - "consensus": points the responses agree on
      - "contradictions": points where responses directly conflict
      - "partial_coverage": important aspects only some responses addressed
      - "unique_insights": valuable points raised by only one response
      - "blind_spots": important aspects no response addressed well

    Do not include any prose outside the JSON object.
    """
  end

  defp judge_user_prompt(prompt, responses) do
    panel =
      responses
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {%{"model" => model, "content" => content}, i} ->
        "### Response #{i} (#{model})\n#{content}"
      end)

    """
    Question:
    #{prompt}

    Panel responses:
    #{panel}
    """
  end

  defp synthesize_system_prompt do
    """
    You are the synthesizer in a model-fusion panel. Using the panel's responses
    and the judge's structured analysis, write the single best, comprehensive,
    well-grounded answer to the user's question.

    Guidelines:
      - Build on the consensus points.
      - Resolve contradictions in favor of the better-supported position, and
        note genuine uncertainty where it exists.
      - Incorporate the unique insights worth keeping.
      - Address the identified blind spots.
    Write the final answer directly, with no meta-commentary about the panel.
    """
  end

  defp synthesize_user_prompt(prompt, responses, analysis) do
    panel =
      responses
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {%{"model" => model, "content" => content}, i} ->
        "### Response #{i} (#{model})\n#{content}"
      end)

    """
    Question:
    #{prompt}

    Judge's structured analysis (JSON):
    #{Jason.encode!(analysis)}

    Panel responses:
    #{panel}
    """
  end
end
