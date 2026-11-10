import { expect, test, type Page } from "@playwright/test";
import { expectConnected, trackProblems, triggerRun } from "./helpers";

/** Opens the health check modal from `trigger` and waits for its first report. */
async function openHealthCheck(page: Page, trigger = page.locator("#health-check")) {
  await trigger.click();

  const modal = page.locator("#health-modal");
  await expect(modal).toBeVisible();
  await expect(modal.locator("#health-report")).toBeVisible();
  await expect(modal.locator("#health-failed")).toHaveCount(0);

  return modal;
}

/** Fails when the modal overflows the viewport or the LiveView crashed or reconnected. */
async function expectUiIntact(page: Page, problems: string[]) {
  const viewport = page.viewportSize()!;
  const box = (await page.locator("#health-modal .modal-box").boundingBox())!;

  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
  await expect(page.locator("[data-phx-main]")).not.toHaveClass(/phx-error|phx-disconnected/);
  expect(problems).toEqual([]);
}

test("a running task reports its live worker and keeps polling", async ({ page, baseURL }) => {
  const runId = await triggerRun(page, "health_check_dag", /running/i);
  const problems = trackProblems(page, baseURL!);

  await page.goto(`/gust/dags/health_check_dag/dashboard?run_id=${runId}&task_name=wait`);
  await expectConnected(page);
  await expect(page.locator("#task-status-progress")).toHaveClass(/status-running/, { timeout: 30_000 });

  const modal = await openHealthCheck(page);
  const task = modal.locator('#health-tasks > [id^="health-task-"]');

  await expect(task).toHaveCount(1);
  await expect(task.locator("[data-verdict]")).toHaveAttribute("data-verdict", "healthy");
  await expect(task.locator('[id^="health-info-memory-"]')).toContainText("bytes");
  await expect(modal.locator("#health-node-connected")).toHaveText("yes");
  await expect(modal.locator("#health-dag-worker")).toContainText("(alive)");

  const checkedAt = modal.locator("#health-checked-at");
  const firstCheck = await checkedAt.innerText();
  await expect(checkedAt).not.toHaveText(firstCheck, { timeout: 15_000 });

  await modal.locator("#health-refresh").click();
  await expect(task.locator("[data-verdict]")).toHaveAttribute("data-verdict", "healthy");
  await expectUiIntact(page, problems);

  await modal.locator("#health-close").click();
  await expect(modal).toHaveCount(0);

  await page.locator("#actions").click();
  await page.locator("#cancel").click();
  await expect(page.locator("#task-status-progress")).toHaveClass(/status-failed/, { timeout: 30_000 });
  expect(problems).toEqual([]);
});

test("a finished run reports no running tasks and closes with Escape", async ({ page, baseURL }) => {
  const runId = await triggerRun(page, "map_over_dag", /succeeded/i);
  const problems = trackProblems(page, baseURL!);

  await page.goto(`/gust/dags/map_over_dag/dashboard?run_id=${runId}`);
  await expectConnected(page);

  const modal = await openHealthCheck(page);

  await expect(modal.locator("#health-run")).toContainText(`Run ${runId}`);
  await expect(modal.locator("#health-no-tasks")).toBeVisible();
  await expect(modal.locator("#health-dag-worker")).toHaveText("not found");
  await expectUiIntact(page, problems);

  await page.keyboard.press("Escape");
  await expect(modal).toHaveCount(0);

  await openHealthCheck(page);
  await page.locator("#health-close").click();
  await expect(page.locator("#health-modal")).toHaveCount(0);
  expect(problems).toEqual([]);
});

test("each mapped task row checks only its own instance", async ({ page, baseURL }) => {
  const runId = await triggerRun(page, "map_over_dag", /succeeded/i);
  const problems = trackProblems(page, baseURL!);

  await page.goto(`/gust/dags/map_over_dag/dashboard?run_id=${runId}&task_name=double`);
  await expectConnected(page);

  const rowTriggers = page.locator('[id^="health-mapped-task-"]');
  await expect(rowTriggers).toHaveCount(3);
  await expect(page.locator("#health-check")).toHaveCount(0);

  const modal = await openHealthCheck(page, rowTriggers.first());
  const task = modal.locator('#health-tasks > [id^="health-task-"]');

  await expect(task).toHaveCount(1);
  await expect(task.locator("[data-verdict]")).toHaveAttribute("data-verdict", "not_running");
  await expectUiIntact(page, problems);
});
