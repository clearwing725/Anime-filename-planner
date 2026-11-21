const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { test } = require("node:test");
const { chromium } = require("playwright");

const pageUrl = pathToFileURL(path.resolve(process.argv[2] || path.join(__dirname, "../index.html"))).href;
const firstName = "InuYasha (2000) - S06E28-E29.mkv";
const preview = async page => page.locator("#filenames code").allTextContents();
const expectedCount = (page, count) => page.waitForFunction(value =>
  document.getElementById("count").textContent === value, count);

test("Anime Filename Planner", async suite => {
  const browser = await chromium.launch({
    executablePath: process.env.PLANNER_CHROMIUM || undefined,
  });
  suite.after(() => browser.close());

  async function open(t, desktop = false) {
    const context = await browser.newContext({ acceptDownloads: true });
    t.after(() => context.close());
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => {
      if (message.type() === "error") errors.push(message.text());
    });
    if (desktop) {
      await page.addInitScript(() => {
        window.plannerMessages = [];
        const bridge = new EventTarget();
        bridge.postMessage = message => window.plannerMessages.push(message);
        window.chrome ??= {};
        window.chrome.webview = bridge;
      });
    }
    await page.goto(pageUrl);
    page.setDefaultTimeout(5000);
    t.after(() => assert.deepEqual(errors, []));
    return page;
  }

  await suite.test("loads InuYasha's combined 166–167 as S06E28-E29", async t => {
    const page = await open(t);
    assert.deepEqual(await preview(page), [firstName]);
    assert.equal(await page.locator("#folder").textContent(), "InuYasha (2000) / Season 06");
    assert.equal(await page.locator("#example-reference").isVisible(), true);
    assert.equal(await page.locator("#notice-content").textContent().then(text => text.includes("139 becomes E01")), true);
  });

  await suite.test("specials, single files, multi-episode files and unsorted groups", async t => {
    const page = await open(t);
    await page.locator("#reset").click();
    await page.locator("#series").fill("Example");
    await page.locator("#season").fill("00");
    await page.locator("#extension").fill(".MKV");
    await page.locator("#range").fill("1−7");
    await page.locator("#combined").fill("5+6,\n2—4");
    await expectedCount(page, "4 files");
    assert.deepEqual(await preview(page),
      ["E01", "E02-E04", "E05-E06", "E07"].map(code => "Example - S00" + code + ".mkv"));
    assert.match(await page.locator("#notice-content").textContent(), /Season 00 is for specials/);
  });

  await suite.test("rejects overlapping or out-of-range combined episodes and invalid boundaries", async t => {
    const page = await open(t);
    await page.locator("#range").fill("161–167");
    for (const [input, message] of [["163–165, 165–166", /overlap/], ["160–161", /inside/], ["161+164", /at least two/]]) {
      await page.locator("#combined").fill(input);
      await expectedCount(page, "0 files");
      await page.locator("#error-combined").getByText(message).waitFor();
      assert.equal(await page.locator("#download").isDisabled(), true);
    }
    await page.locator("#combined").fill("");
    await page.locator("#range").fill("166–168");
    await page.locator("#error-range").waitFor();
    assert.match(await page.locator("#error-range").textContent(), /outside/);
    await page.locator("#season-end").fill("138");
    await page.locator("#error-seasonEnd").waitFor();
    assert.match(await page.locator("#error-seasonEnd").textContent(), /at or after/);
  });

  await suite.test("rejects pasted numbers, extensions and lists that exceed limits without truncation", async t => {
    const page = await open(t);
    for (const [field, id, value, restored] of [
      ["season", "season", "100", "06"],
      ["season-start", "seasonStart", "10000", "139"],
      ["season-end", "seasonEnd", "16700", "167"],
      ["extension", "extension", ".abcdefgh9", "mkv"],
      ["range", "range", "9".repeat(29), "166–167"],
      ["combined", "combined", "166–167" + ",".repeat(6000), "166–167"],
    ]) {
      const input = page.locator("#" + field);
      await input.selectText();
      await page.keyboard.insertText(value);
      assert.equal(await input.inputValue(), value);
      await page.locator("#error-" + id).waitFor();
      assert.equal(await page.locator("#copy").isDisabled(), true);
      await input.fill(restored);
      await expectedCount(page, "1 file");
    }
  });

  await suite.test("sanitizes Windows device names, misleading controls and filename separators", async t => {
    const page = await open(t);
    for (const [title, expected] of [
      ["CONIN$", "_CONIN$"],
      ["NUL .txt", "_NUL .txt"],
      ["LPT².chapter", "_LPT².chapter"],
      ["Example.\u00a0?", "Example"],
      ["Anime: 名/題 | 🐱", "Anime - 名 - 題 - 🐱"],
      ["Show\u202e\u2028MKV", "ShowMKV"],
      ["<b>Anime</b>", "bAnime - b"],
    ]) {
      const field = page.locator("#series");
      await field.fill(title);
      const filename = expected + " - S06E28-E29.mkv";
      await page.locator("#filenames code").getByText(filename, { exact: true }).waitFor();
      assert.deepEqual(await preview(page), [filename]);
    }
    assert.equal(await page.locator("#filenames b").count(), 0);
    await page.locator("#series").fill("..\u00a0?");
    await page.locator("#error-series").waitFor();
    await expectedCount(page, "0 files");
    assert.equal(await page.locator("#folder").textContent(), "—");
  });

  await suite.test("enforces the UTF-8 filename length with Unicode and a combined suffix", async t => {
    const page = await open(t);
    const title = "界".repeat(79) + "a";
    await page.locator("#series").fill(title);
    await page.locator("#filenames code").getByText(title + " - S06E28-E29.mkv", { exact: true }).waitFor();
    assert.equal(Buffer.byteLength((await preview(page))[0]), 255);
    await page.locator("#series").fill(title + "c");
    await page.locator("#error-series").waitFor();
    assert.match(await page.locator("#error-series").textContent(), /255 bytes/);
  });

  await suite.test("remembers each numbering mode's last episode and clears the form", async t => {
    const page = await open(t);
    await page.getByText("Within season", { exact: true }).click();
    await page.locator("#season-start").waitFor({ state: "hidden" });
    assert.equal(await page.locator("#season-end").inputValue(), "");
    await page.locator("#season-end").fill("29");
    await page.getByText("Absolute", { exact: true }).click();
    assert.equal(await page.locator("#season-end").inputValue(), "167");
    await page.getByText("Within season", { exact: true }).click();
    assert.equal(await page.locator("#season-end").inputValue(), "29");
    await page.locator("#reset").click();
    await expectedCount(page, "0 files");
    assert.equal(await page.locator("#series").evaluate(input => document.activeElement === input), true);
    assert.equal(await page.locator("#copy").isDisabled(), true);
  });

  await suite.test("handles 500 files and preserves scroll and row identity for unchanged names", async t => {
    const page = await open(t);
    await page.getByText("Within season", { exact: true }).click();
    await page.locator("#combined").fill("");
    await page.locator("#range").fill("9500–9999");
    await expectedCount(page, "500 files");
    const list = await preview(page);
    assert.equal(list[499], "InuYasha (2000) - S06E9999.mkv");
    const result = await page.evaluate(async () => {
      const list = document.getElementById("filenames");
      const first = list.firstElementChild;
      list.scrollTop = 300;
      const original = list.scrollTop;
      const input = document.getElementById("extension");
      for (const value of [".mkv", ".Mkv", "MKV"]) {
        input.value = value;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      return { sameRow: list.firstElementChild === first, original, current: list.scrollTop };
    });
    assert.equal(result.sameRow, true);
    assert.ok(result.original > 0);
    assert.equal(result.current, result.original);
    const firstRow = await page.locator("#filenames li").first().elementHandle();
    await page.locator("#range").fill("9500–9998");
    await expectedCount(page, "499 files");
    assert.equal(await page.locator("#filenames li").count(), 499);
    await page.locator("#range").fill("9500–9999");
    await expectedCount(page, "500 files");
    assert.equal(await page.locator("#filenames li").count(), 500);
    await page.locator("#extension").fill("mp4");
    await page.locator("#filenames code").filter({ hasText: /E9999\.mp4$/ }).waitFor();
    assert.equal(await firstRow.evaluate(row => row === document.querySelector("#filenames li")), true);
    await page.locator("#range").fill("9499–9999");
    await page.locator("#error-range").waitFor();
    assert.match(await page.locator("#error-range").textContent(), /500 episodes/);
  });

  await suite.test("downloads the correct UTF-8 text from the standalone page", async t => {
    const page = await open(t);
    const ready = page.waitForEvent("download");
    await page.locator("#download").click();
    const download = await ready;
    assert.equal(download.suggestedFilename(), "anime-filenames.txt");
    assert.equal(await fs.readFile(await download.path(), "utf8"), firstName);
  });

  await suite.test("copies from the standalone page and preserves focus when the browser requires fallback", async t => {
    const page = await open(t);
    await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
    await page.locator("#copy").click();
    await page.locator("#action-status").getByText("Filename list copied.").waitFor();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), firstName);
    await page.evaluate(() => {
      navigator.clipboard.writeText = () => Promise.reject(new Error("Clipboard API unavailable"));
    });
    await page.locator("#copy").click();
    await page.locator("#action-status").getByText("Filename list copied.").waitFor();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), firstName);
    assert.equal(await page.locator("#copy").evaluate(button => document.activeElement === button), true);
  });

  await suite.test("sends fresh data to the desktop bridge and displays replies", async t => {
    const page = await open(t, true);
    await page.locator("#copy").click();
    await page.evaluate(() => {
      const title = document.getElementById("series");
      title.value = "Latest title";
      title.dispatchEvent(new Event("input", { bubbles: true }));
      document.getElementById("download").click();
      window.chrome.webview.dispatchEvent(new MessageEvent("message", { data: { status: "Save canceled." } }));
    });
    assert.deepEqual(await page.evaluate(() => window.plannerMessages), [
      { action: "copy", text: firstName },
      { action: "save", text: "Latest title - S06E28-E29.mkv" },
    ]);
    assert.equal(await page.locator("#action-status").textContent(), "Save canceled.");
  });
});
