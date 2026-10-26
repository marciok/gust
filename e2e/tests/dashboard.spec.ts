import { execFileSync } from "node:child_process";
import { expect, test, type Page } from "@playwright/test";

const appDir = process.env.GUST_APP_DIR!;
const app = process.env.GUST_APP ?? "gust_generated_app";
const mode = process.env.GUST_E2E_MODE ?? "dev";

// Runs a Gust CLI command and returns its JSON reply. Dev goes through
// `mix gust.cli`; a host app's release has no gust-cli wrapper, so prod calls
// Gust.CLI the way that wrapper does: `eval` with the console role.
function gustCli(args: string[]): Record<string, unknown> {
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

const pages = [
  "/gust/dags",
  "/gust/dags/map_over_dag/dashboard",
  "/gust/dags/map_over_dag/runs",
  "/gust/system",
  "/gust/secrets",
];

// Collects what would show up as a broken page: console errors, uncaught
// exceptions and failed same-origin requests (CSS, JS, images, the socket).
function trackProblems(page: Page, baseURL: string) {
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

for (const pagePath of pages) {
  test(`${pagePath} loads its assets and connects LiveView`, async ({ page, baseURL }) => {
    const problems = trackProblems(page, baseURL!);

    await page.goto(pagePath);

    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/);
    await expect(page.locator('link[rel="stylesheet"][href*="/gust/css-"]')).toHaveCount(1);
    await page.waitForLoadState("networkidle");

    expect(problems).toEqual([]);
  });
}

test("lists loaded DAGs and reports broken ones", async ({ page }) => {
  await page.goto("/gust/dags");

  await expect(page.locator("#dags-map_over_dag")).toBeVisible();
  await expect(page.locator("#dags-map_over_dag .dag-card__notice")).toHaveCount(0);
  // Unparsable files are listed apart; ones that parse but don't compile keep
  // their card and show the error on it.
  await expect(page.locator("#broken_dags-syntax_error_dag")).toBeVisible();
  await expect(page.locator("#dags-compile_error_dag .dag-card__notice").first()).toBeVisible();
});

test("the CLI reports DAG definitions", async () => {
  expect(gustCli(["dag_definition", "map_over_dag"])).toMatchObject({ status: "ok" });
});

test("a run triggered from the CLI shows up live and succeeds", async ({ page }) => {
  await page.goto("/gust/dags/map_over_dag/runs");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/);

  const reply = gustCli(["trigger_run", "map_over_dag"]);
  expect(reply).toMatchObject({ status: "ok", run_id: expect.any(Number) });

  // map_over_dag's last task fails the run unless its mapped results add up.
  await expect(page.locator(`#runs-${reply.run_id}`).getByTestId("status-badge")).toHaveText(/succeeded/i, {
    timeout: 90_000,
  });
});
