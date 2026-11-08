const assert = require("node:assert/strict");
const { execFile: execFileCallback, execFileSync } = require("node:child_process");
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } = require("node:fs");
const { createServer } = require("node:http");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { test } = require("node:test");
const { promisify } = require("node:util");
const { prepareArgs } = require("../../.github/scripts/release.cjs");
const execFile = promisify(execFileCallback);

test("shipped Trellis prepares, refreshes, resumes candidates, and promotes without remote writes", async t => {
  const root = mkdtempSync(join(tmpdir(), "slate-release-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const checkout = join(root, "checkout");
  const remote = join(root, "origin.git");
  mkdirSync(checkout);
  const git = (...args) => execFileSync("git", args, {
    cwd: checkout, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  }).trim();
  git("init", "--bare", remote);
  git("init", "-b", "main");
  git("config", "user.name", "Release fixture");
  git("config", "user.email", "release-fixture@example.invalid");
  git("remote", "add", "origin", remote);
  writeFileSync(join(checkout, "gleam.toml"), [
    'name = "slate"', 'version = "0.1.0"', '[tools.trellis.release]',
    "resume = true", "auto_pre = true", "skip_unchanged = true",
    '[tools.trellis.changelog]', 'dependency_kind = "Fixed"',
    'kinds = [{ label = "Fixed", bump = "patch" }]', "",
  ].join("\n"));
  git("add", ".");
  git("commit", "-m", "chore: initialize fixture");
  git("push", "origin", "main");
  let pending = false;
  let staleHead;
  const titles = [];
  const remoteHead = () => git("--git-dir", remote, "rev-parse", "refs/heads/release/next");
  const pr = () => ({
    number: 1, state: "open", html_url: "https://github.com/test/slate/pull/1",
    head: { ref: "release/next", sha: staleHead || remoteHead(), repo: { full_name: "test/slate" } },
    base: { ref: "main", repo: { full_name: "test/slate" } },
  });
  const server = createServer(async (request, response) => {
    const path = new URL(request.url, "http://localhost").pathname;
    let body = "";
    for await (const chunk of request) body += chunk;
    let result;
    let status = 200;
    if (request.method === "GET" && path === "/repos/test/slate/pulls") {
      result = pending ? [pr()] : [];
    } else if (request.method === "GET" && path === "/repos/test/slate/pulls/1") {
      result = pr();
    } else if (request.method === "POST" && path === "/repos/test/slate/pulls") {
      pending = true;
      titles.push(JSON.parse(body).title);
      result = pr();
      status = 201;
    } else if (request.method === "PATCH" && path === "/repos/test/slate/pulls/1") {
      titles.push(JSON.parse(body).title);
      result = pr();
    } else {
      status = 500;
      result = { message: `Unexpected local request: ${request.method} ${path}` };
    }
    response.writeHead(status, { "content-type": "application/json" });
    response.end(JSON.stringify(result));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const env = {
    ...process.env, GITHUB_TOKEN: "local-fixture-token", GH_TOKEN: "local-fixture-token",
    TRELLIS_GITHUB_REPO: "test/slate",
    TRELLIS_GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
    TRELLIS_NO_UPDATE_CHECK: "1", CI: "true",
  };
  const trellis = async args => (await execFile("trellis", ["-C", checkout, ...args], { env })).stdout;
  const prepare = async options => JSON.parse(await trellis(prepareArgs(options)));
  const change = async body => {
    await trellis(["changelog", "new", "--kind", "Fixed", "--body", body]);
    git("add", ".");
    git("commit", "-m", `fix: ${body.toLowerCase()}`);
    git("push", "origin", "main");
  };
  const merge = () => {
    git("merge", "--ff-only", "origin/release/next");
    git("push", "origin", "main");
    pending = false;
  };
  assert.equal((await prepare()).outcome, "no_changes");
  await change("First fixture change");
  assert.equal((await prepare()).outcome, "prepared");
  assert.equal(titles.at(-1), "release: slate v0.1.1");
  assert.equal((await prepare()).outcome, "unchanged");
  await change("Second fixture change");
  assert.equal((await prepare()).outcome, "prepared");
  assert.equal(titles.at(-1), "release: slate v0.1.1", "refresh must preserve the pending target");
  assert.equal((await prepare()).outcome, "unchanged");
  merge();

  await change("Candidate fixture change");
  assert.equal((await prepare({ pre: "rc" })).outcome, "prepared");
  assert.equal(titles.at(-1), "release: slate v0.1.2-rc.0");
  merge();
  assert.equal((await prepare()).outcome, "unchanged", "unchanged candidates must not increment");
  await change("Next candidate fixture change");
  assert.equal((await prepare()).outcome, "prepared");
  assert.equal(titles.at(-1), "release: slate v0.1.2-rc.1");
  merge();
  assert.equal((await prepare({ pre: "none" })).outcome, "prepared");
  assert.equal(titles.at(-1), "release: slate v0.1.2");
  merge();
  const changelog = readFileSync(join(checkout, ".changes/slate/v0.1.2.md"), "utf8");
  assert.ok(changelog.includes("Candidate fixture change"));
  assert.ok(changelog.includes("Next candidate fixture change"));

  await change("Delayed API fixture change");
  await prepare();
  staleHead = remoteHead();
  await change("Refresh after delayed API change");
  const previousTitleCount = titles.length;
  await assert.rejects(prepare(), /release PR changed during preparation/);
  assert.equal(titles.length, previousTitleCount, "failed trust checks must not edit the PR");
  staleHead = undefined;
  assert.equal((await prepare({ version: "0.1.3", replace: true })).outcome, "prepared",
    "explicit replacement can repair intent after the API converges without bypassing validation");
});
