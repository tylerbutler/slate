const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const { runInNewContext } = require("node:vm");
const { selectRelease, verifyRelease, recordOutcome } = require("../../.github/scripts/release.cjs");

const SHA = "a".repeat(40);
const OTHER = "b".repeat(40);
const repo = { owner: "test", repo: "slate" };
const pr = {
  number: 1, merged: true, merged_at: "2026-11-01T00:00:00Z", merge_commit_sha: SHA,
  head: { ref: "release/next", repo: { full_name: "test/slate" } },
  base: { ref: "main", repo: { full_name: "test/slate" } },
};

function fixture(options = {}) {
  const writes = [];
  const prs = options.prs || [pr];
  const missing = () => { throw Object.assign(new Error("Not found"), { status: 404 }); };
  const list = () => {};
  const statuses = () => {};
  const github = {
    paginate: async method => method === list ? prs : options.statuses || [],
    rest: {
      pulls: { list, get: async ({ pull_number }) => ({
        data: options.live || prs.find(item => item.number === pull_number) || missing(),
      }) },
      git: {
        getRef: async () => ({ data: options.tag
          ? { object: { type: "commit", sha: options.tag } } : missing() }),
        getTag: async () => { throw new Error("Unexpected annotated tag"); },
      },
      repos: {
        compareCommitsWithBasehead: async ({ basehead }) => {
          assert.equal(basehead, `${(options.live || pr).merge_commit_sha}...main`);
          return { data: { status: options.comparison || "ahead" } };
        },
        getContent: async ({ ref, path }) => {
          assert.equal(ref, SHA);
          assert.equal(path, "gleam.toml");
          return { data: { encoding: "base64", content: Buffer.from(
            options.manifest || 'name = "slate"\nversion = "2.2.2"\n',
          ).toString("base64") } };
        },
        listCommitStatusesForRef: statuses,
        getReleaseByTag: async () => ({ data: options.release || missing() }),
        createCommitStatus: async status => { writes.push(status); },
      },
    },
  };
  const context = options.context || {
    repo, eventName: "pull_request", payload: { action: "closed", pull_request: pr },
  };
  const fetch = async url => {
    assert.equal(url, "https://hex.pm/api/packages/slate/releases/2.2.2");
    return {
      ok: !options.hexError, status: options.hexError || 200,
      json: async () => ({ version: options.hexVersion || "2.2.2" }),
    };
  };
  return { github, context, fetch, writes };
}

const push = { repo, eventName: "push", ref: "refs/heads/main", payload: {} };
const manual = inputs => ({
  repo, eventName: "workflow_dispatch", ref: "refs/heads/main", payload: { inputs },
});

test("merged release reserves its immutable revision before qualification", async () => {
  const f = fixture();
  assert.deepEqual(await selectRelease(f), { publish_sha: SHA, version: "2.2.2", pr_number: "1" });
  assert.deepEqual(f.writes.map(item => [item.sha, item.state]), [[SHA, "pending"]]);
});

test("first preparation needs no legacy release", async () => {
  const f = fixture({ context: push, prs: [] });
  assert.deepEqual(await selectRelease(f), { prepare: "true" });
  assert.equal(f.writes.length, 0);
});

test("unrelated, unmerged, and fork PR events do not publish", async () => {
  for (const changed of [
    { merged: false }, { head: { ...pr.head, ref: "feature" } },
    { head: { ...pr.head, repo: { full_name: "fork/slate" } } },
    { base: { ...pr.base, ref: "other" } },
  ]) {
    const f = fixture({ context: {
      repo, eventName: "pull_request",
      payload: { action: "closed", pull_request: { ...pr, ...changed } },
    } });
    assert.deepEqual(await selectRelease(f), {});
    assert.equal(f.writes.length, 0);
  }
});

test("current API merge state must agree with the event", async () => {
  for (const changed of [{ merged: false }, { merge_commit_sha: OTHER }]) {
    const f = fixture({ live: { ...pr, ...changed } });
    await assert.rejects(selectRelease(f), /current merged PR state/);
    assert.equal(f.writes.length, 0);
  }
});

test("recovery validates operation, PR identity, and main ancestry", async () => {
  for (const [options, message] of [
    [{ context: manual({ operation: "recover" }) }, /PR number/],
    [{ context: manual({ operation: "recover", pr_number: "1; echo" }) }, /PR number/],
    [{ context: manual({ operation: "recover", pr_number: "999999999999999999999" }) }, /PR number/],
    [{ context: manual({ operation: "recover", pr_number: "1", pre: "none" }) }, /cannot change/],
    [{ context: manual({ operation: "unknown" }) }, /Invalid operation/],
    [{ context: { ...push, ref: "refs/heads/feature" } }, /from main/],
    [{ context: manual({ operation: "prepare", pr_number: "1" }) }, /only used for recovery/],
    [{ context: manual({ operation: "prepare", replace: "true" }) }, /requires an explicit/],
    [{ comparison: "diverged" }, /ancestor/],
    [{ live: { ...pr, merge_commit_sha: "main" } }, /current merged PR state/],
    [{ context: manual({ operation: "recover", pr_number: "1" }),
      live: { ...pr, merged: false } }, /same-repository merged/],
  ]) {
    const f = fixture(options);
    await assert.rejects(selectRelease(f), message);
    assert.equal(f.writes.length, 0);
  }
});

test("superseded merge cannot publish or recover", async () => {
  const newer = { ...pr, number: 2, merged_at: "2026-11-02T00:00:00Z" };
  const f = fixture({ prs: [pr, newer] });
  await assert.rejects(selectRelease(f), /superseded/);
  assert.equal(f.writes.length, 0);
});

test("publication rechecks reject a newer release or completion during qualification", async () => {
  const newer = { ...pr, number: 2, merged_at: "2026-11-02T00:00:00Z" };
  await assert.rejects(verifyRelease({ ...fixture({ prs: [pr, newer] }), sha: SHA }), /superseded/);
  await assert.rejects(verifyRelease({ ...fixture({
    tag: SHA, statuses: [{ context: "trellis/release", state: "success" }],
  }), sha: SHA }), /selection changed/);
  await verifyRelease({ ...fixture(), sha: SHA });
});

test("incomplete release blocks automatic and manual preparation", async () => {
  for (const state of [undefined, "pending", "failure", "error"]) {
    const f = fixture({
      context: push, statuses: state ? [{ context: "trellis/release", state }] : [],
    });
    await assert.rejects(selectRelease(f), /incomplete.*recover/);
    assert.equal(f.writes.length, 0);
  }
});

test("failed release recovery preserves merge revision after main advances", async () => {
  const f = fixture({
    context: manual({ operation: "recover", pr_number: "1" }),
    statuses: [{ context: "trellis/release", state: "failure" }],
  });
  assert.equal((await selectRelease(f)).publish_sha, SHA);
  assert.equal(f.writes[0].state, "pending");
});

test("completed merge reruns are no-ops; main can prepare another release", async () => {
  const options = { tag: SHA, statuses: [{ context: "trellis/release", state: "success" }] };
  for (const context of [undefined, manual({ operation: "recover", pr_number: "1" })]) {
    const f = fixture({ ...options, ...(context ? { context } : {}) });
    assert.deepEqual(await selectRelease(f), {});
    assert.equal(f.writes.length, 0);
  }
  assert.deepEqual(await selectRelease(fixture({ ...options, context: push })), { prepare: "true" });
});

test("latest completion status wins over an older success", async () => {
  const f = fixture({ context: push, tag: SHA, statuses: [
    { context: "trellis/release", state: "failure" },
    { context: "trellis/release", state: "success" },
  ] });
  await assert.rejects(selectRelease(f), /incomplete/);
});

test("legacy completion requires matching tag, GitHub Release, and Hex version", async () => {
  const options = {
    context: push, tag: SHA, release: { draft: false, tag_name: "v2.2.2" },
  };
  const f = fixture(options);
  assert.deepEqual(await selectRelease(f), { prepare: "true" });
  assert.equal(f.writes.length, 0);
  for (const changed of [
    { release: { draft: true, tag_name: "v2.2.2" } }, { hexError: 404 },
    { tag: null }, { release: { tag_name: "v2.2.1" } },
  ]) await assert.rejects(selectRelease(fixture({ ...options, ...changed })), /incomplete/);
  await assert.rejects(selectRelease(fixture({ ...options, hexError: 500 })), /HTTP 500/);
  await assert.rejects(selectRelease(fixture({ ...options, hexVersion: "2.2.1" })), /different release/);
});

test("conflicting or missing completed tag fails closed", async () => {
  await assert.rejects(selectRelease(fixture({ tag: OTHER })), /different revision/);
  await assert.rejects(selectRelease(fixture({
    statuses: [{ context: "trellis/release", state: "success" }],
  })), /missing its tag/);
});

test("annotated tags resolve to the exact commit", async () => {
  const f = fixture();
  f.github.rest.git.getRef = async () => ({ data: { object: { type: "tag", sha: OTHER } } });
  f.github.rest.git.getTag = async ({ tag_sha }) => {
    assert.equal(tag_sha, OTHER);
    return { data: { object: { type: "commit", sha: SHA } } };
  };
  assert.equal((await selectRelease(f)).publish_sha, SHA);
});

test("API authentication and malformed manifests are errors, not no-ops", async () => {
  const f = fixture();
  f.github.rest.git.getRef = async () => {
    throw Object.assign(new Error("Forbidden"), { status: 403 });
  };
  await assert.rejects(selectRelease(f), /Forbidden/);
  await assert.rejects(selectRelease(fixture({ manifest: 'name = "other"\nversion = "2.2.2"' })),
    /Slate manifest/);
  await assert.rejects(selectRelease(fixture({ manifest: 'name = "slate"\nversion = "main"' })),
    /manifest version/);
});

test("completion requires qualification and all publication steps", async () => {
  for (const qualification of ["success", "failure", "cancelled", "skipped"]) {
    for (const publication of ["success", "failure", "cancelled", "skipped"]) {
      const f = fixture();
      await recordOutcome({ ...f, sha: SHA, qualification, publication });
      assert.equal(f.writes[0].state,
        qualification === "success" && publication === "success" ? "success" : "failure");
      assert.equal(f.writes[0].sha, SHA);
    }
  }
});

test("workflow preserves qualification, artifacts, ordering, and queued coordination", () => {
  const workflow = readFileSync(".github/workflows/release.yml", "utf8");
  const ci = readFileSync(".github/workflows/ci.yml", "utf8");
  assert.match(workflow, /group: trellis-release-\$\{\{ github.repository \}\}\n  queue: max\n  cancel-in-progress: false/);
  assert.match(workflow, /qualify:[\s\S]*uses: \.\/\.github\/workflows\/ci.yml/);
  assert.match(workflow, /publish:\n    permissions:[\s\S]*?\n    needs: \[select, qualify\]/);
  assert.ok(workflow.indexOf("trellis publish slate") < workflow.indexOf("trellis tag create"));
  assert.ok(workflow.indexOf("Recheck trusted release before Hex") < workflow.indexOf("trellis publish slate"));
  assert.ok(workflow.indexOf("Recheck trusted release before tagging") < workflow.indexOf("trellis tag create"));
  assert.match(workflow, /complete:\n    permissions:[\s\S]*?\n    needs: \[select, qualify, publish\]\n    if: always\(\)/);
  assert.equal((ci.match(/ref: \$\{\{ inputs.revision \|\| github.sha \}\}/g) || []).length, 5);
  for (const target of [
    "x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-apple-darwin",
    "aarch64-apple-darwin", "x86_64-pc-windows",
  ]) {
    assert.ok(ci.includes(target));
    assert.ok(workflow.includes(target));
  }
  for (const proof of ["just native-release-check", "just native-package-check"]) {
    assert.ok(workflow.includes(proof));
    assert.ok(ci.includes(proof));
  }
  assert.match(ci, /windows-package:[\s\S]*needs: hex-package/);
  assert.ok(!workflow.includes("run-id:"), "artifacts must come from this workflow run");
  assert.ok(!workflow.includes("tags:"));
});

test("build attestations require qualified trusted builds and isolated signing permissions", () => {
  const ci = readFileSync(".github/workflows/ci.yml", "utf8");
  const release = readFileSync(".github/workflows/release.yml", "utf8");
  const attest = ci.slice(ci.indexOf("\n  attest:"), ci.indexOf("\n  docs:"));
  assert.match(attest, /needs: \[test, native, hex-package, windows-package, docs\]/);
  const condition = attest.match(/    if: >-\n([\s\S]*?)    permissions:/)[1].trim();
  const merged = {
    repository: "tylerbutler/slate", event_name: "pull_request", ref: "refs/heads/main",
    event: { action: "closed", pull_request: {
      merged: true,
      head: { ref: "release/next", repo: { full_name: "tylerbutler/slate" } },
      base: { ref: "main" },
    } },
  };
  const allowed = github => runInNewContext(condition, { github });
  assert.equal(allowed({ ...merged, event_name: "push" }), true);
  assert.equal(allowed({ ...merged, event_name: "workflow_dispatch" }), true);
  assert.equal(allowed(merged), true);
  for (const event_name of ["push", "workflow_dispatch", "pull_request"]) {
    assert.equal(allowed({
      ...merged, event_name, ref: "refs/heads/feature",
      event: { action: "opened", pull_request: { ...merged.event.pull_request, merged: false } },
    }), false);
  }
  for (const changed of [
    { merged: false },
    { head: { ...merged.event.pull_request.head, ref: "feature" } },
    { head: { ...merged.event.pull_request.head, repo: { full_name: "fork/slate" } } },
    { base: { ref: "other" } },
  ]) {
    assert.equal(allowed({
      ...merged, event: {
        action: "closed", pull_request: { ...merged.event.pull_request, ...changed },
      },
    }), false);
  }
  assert.match(ci.split("jobs:\n")[0], /permissions:\n  contents: read/);
  assert.equal((ci.match(/id-token: write/g) || []).length, 1);
  assert.equal((ci.match(/attestations: write/g) || []).length, 1);
  assert.match(attest, /permissions:\n      contents: read\n      id-token: write\n      attestations: write/);
  assert.match(release, /qualify:\n    permissions:\n      contents: read\n      id-token: write\n      attestations: write/);
  assert.equal((attest.match(/actions\/attest@1e69f48acb82d1966a394da916b4c1698aa569d6/g) || []).length, 2);
  assert.equal((attest.match(/build\/attestations\/slate-native-\*\/slate_lock\.\*/g) || []).length, 2);
  assert.equal((attest.match(/build\/attestations\/slate-hex-package\/slate-\*\.tar/g) || []).length, 2);
  assert.ok(!attest.includes("run-id:"), "attest only artifacts from this run");
  assert.ok(!attest.includes("continue-on-error:"), "signing failure must block qualification");
  const predicate = attest.split("          predicate: |\n")[1]
    .replace("${{ github.repository }}", "tylerbutler/slate")
    .replace("${{ inputs.revision || github.sha }}", SHA);
  assert.deepEqual(JSON.parse(predicate), { repository: "tylerbutler/slate", revision: SHA });
});
