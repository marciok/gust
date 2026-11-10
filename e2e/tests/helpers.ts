import { execFileSync } from "node:child_process";
import { expect, type Page } from "@playwright/test";

const appDir = process.env.GUST_APP_DIR!;
const app = process.env.GUST_APP ?? "gust_generated_app";
const mode = process.env.GUST_E2E_MODE ?? "dev";

// Runs a Gust CLI command and returns its JSON reply. Dev goes through
// `mix gust.cli`; a host app's release has no gust-cli wrapper, so prod calls
// Gust.CLI the way that wrapper does: `eval` with the console role.
export function gustCli(args: string[]): Record<string, unknown> {
  const output =
    mode === "prod"
      ? execFileSync(`_build/prod/rel/${app}/bin/${app}`, ["eval", `IO.puts(Gust.CLI.exec(${JSON.stringify(args)}))`], {
          cwd: appDir,
          encoding: "utf8",
          env: { ...process.env, GUST_ROLE: "console" },
        })
      : execFileSync("mix", ["gust.cli", ...args], { cwd: appDir, encoding: "utf8" });

  const reply = output.trim().split("\n").reverse().find((line) => line.startsWith("{"));
  if (!reply) throw new Error(`gust CLI printed no JSON reply:\n${output}`);
  return JSON.parse(reply);
}

// Collects what would show up as a broken page: console errors, uncaught
// exceptions and failed same-origin requests (CSS, JS, images, the socket).
export function trackProblems(page: Page, baseURL: string) {
  const problems: string[] = [];

  page.on("console", (message) => {
    if (message.type() === "error") problems.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => problems.push(`exception: ${error.message}`));
  page.on("requestfailed", (request) => {
    if (request.url().startsWith(baseURL)) {
      problems.push(`request failed: ${request.url()} ${request.failure()?.errorText}`);
    }
  });
  page.on("response", (response) => {
    if (response.url().startsWith(baseURL) && response.status() >= 400) {
      problems.push(`HTTP ${response.status()}: ${response.url()}`);
    }
  });

  return problems;
}

/** Waits until the page's LiveView is connected. */
export async function expectConnected(page: Page) {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/);
}

/** Triggers a run from the CLI and waits on the runs page until it reaches `status`. */
export async function triggerRun(page: Page, dag: string, status: RegExp): Promise<number> {
  await page.goto(`/gust/dags/${dag}/runs`);
  await expectConnected(page);

  const reply = gustCli(["trigger_run", dag]);
  expect(reply).toMatchObject({ status: "ok", run_id: expect.any(Number) });
  const runId = reply.run_id as number;

  await expect(page.locator(`#runs-${runId}`).getByTestId("status-badge")).toHaveText(status, {
    timeout: 90_000,
  });

  return runId;
}
