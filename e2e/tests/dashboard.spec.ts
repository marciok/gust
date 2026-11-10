import { expect, test } from "@playwright/test";
import { expectConnected, gustCli, trackProblems, triggerRun } from "./helpers";

const pages = [
  "/gust/dags",
  "/gust/dags/map_over_dag/dashboard",
  "/gust/dags/map_over_dag/runs",
  "/gust/system",
  "/gust/secrets",
];

for (const pagePath of pages) {
  test(`${pagePath} loads its assets and connects LiveView`, async ({ page, baseURL }) => {
    const problems = trackProblems(page, baseURL!);

    await page.goto(pagePath);

    await expectConnected(page);
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
  // map_over_dag's last task fails the run unless its mapped results add up.
  await triggerRun(page, "map_over_dag", /succeeded/i);
});
