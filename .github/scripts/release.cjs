const BASE = "main";
const BRANCH = "release/next";
const STATUS = "trellis/release";
const SHA = /^[0-9a-f]{40}$/;
const VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

function prepareArgs({ pre = "", version = "", replace = false } = {}) {
  if (pre && !/^[A-Za-z][0-9A-Za-z-]*$/.test(pre)) {
    throw new Error("pre must be a candidate label or none.");
  }
  if (version && !VERSION.test(version)) throw new Error("Invalid Slate target version.");
  if (replace && !pre && !version) {
    throw new Error("Replacing release intent requires an explicit pre or version.");
  }
  const args = ["release", "pr", "--base", BASE, "--branch", BRANCH, "--json"];
  if (pre) args.push("--pre", pre);
  if (version) args.push("--set", `slate=${version}`);
  if (replace) args.push("--no-resume", "--no-auto-pre", "--no-skip-unchanged");
  return args;
}

async function optional(request) {
  try {
    return (await request()).data;
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
}

function sameRelease(pr, repo) {
  const fullName = `${repo.owner}/${repo.repo}`;
  return pr.head?.ref === BRANCH && pr.base?.ref === BASE
    && pr.head.repo?.full_name === fullName && pr.base.repo?.full_name === fullName;
}

async function tagCommit(github, repo, version) {
  const ref = await optional(() => github.rest.git.getRef({
    ...repo, ref: `tags/v${version}`,
  }));
  if (!ref) return null;
  let object = ref.object;
  for (let depth = 0; object.type === "tag" && depth < 10; depth++) {
    object = (await github.rest.git.getTag({ ...repo, tag_sha: object.sha })).data.object;
  }
  if (object.type !== "commit" || !SHA.test(object.sha)) {
    throw new Error("Release tag does not resolve to a commit.");
  }
  return object.sha;
}

async function releaseVersion(github, repo, sha) {
  const { data } = await github.rest.repos.getContent({ ...repo, path: "gleam.toml", ref: sha });
  if (data.encoding !== "base64" || typeof data.content !== "string") {
    throw new Error("Cannot read the release manifest.");
  }
  const manifest = Buffer.from(data.content, "base64").toString("utf8");
  if (!/^name = "slate"$/m.test(manifest)) throw new Error("Expected the Slate manifest.");
  const version = manifest.match(/^version = "([^"]+)"$/m)?.[1];
  if (!version || !VERSION.test(version)) throw new Error("Invalid release manifest version.");
  return version;
}

async function legacyComplete(github, repo, version, fetch) {
  const release = await optional(() => github.rest.repos.getReleaseByTag({
    ...repo, tag: `v${version}`,
  }));
  if (!release || release.draft || release.tag_name !== `v${version}`) return false;
  const response = await fetch(`https://hex.pm/api/packages/slate/releases/${version}`);
  if (response.status === 404) return false;
  if (!response.ok) throw new Error(`Hex completion check failed: HTTP ${response.status}.`);
  const hex = await response.json();
  if (hex.version !== version) throw new Error("Hex returned a different release version.");
  return true;
}

async function selectRelease({ github, context, fetch = globalThis.fetch }) {
  const repo = context.repo;
  const manual = context.eventName === "workflow_dispatch";
  const inputs = context.payload.inputs || {};
  const recover = manual && inputs.operation === "recover";
  if (!["push", "pull_request", "workflow_dispatch"].includes(context.eventName)) {
    throw new Error("Unsupported release event.");
  }
  if (context.eventName !== "pull_request" && context.ref !== `refs/heads/${BASE}`) {
    throw new Error("Run release operations from main.");
  }
  if (manual) {
    if (!["prepare", "recover"].includes(inputs.operation)) throw new Error("Invalid operation.");
    if (recover && (inputs.pre || inputs.version || inputs.replace === "true")) {
      throw new Error("Recovery cannot change release intent.");
    }
    if (!recover) {
      if (inputs.pr_number) throw new Error("A PR number is only used for recovery.");
      prepareArgs({ ...inputs, replace: inputs.replace === "true" });
    }
  }
  let requested;
  if (context.eventName === "pull_request") {
    const event = context.payload.pull_request;
    if (context.payload.action !== "closed" || !event?.merged || !sameRelease(event, repo)) {
      return {};
    }
    requested = (await github.rest.pulls.get({ ...repo, pull_number: event.number })).data;
    if (!requested.merged || !sameRelease(requested, repo)
        || requested.merge_commit_sha !== event.merge_commit_sha) {
      throw new Error("Release event does not match current merged PR state.");
    }
  } else if (recover) {
    if (!/^[1-9]\d*$/.test(inputs.pr_number || "") || !Number.isSafeInteger(Number(inputs.pr_number))) {
      throw new Error("Recovery requires a merged release PR number.");
    }
    requested = (await github.rest.pulls.get({
      ...repo, pull_number: Number(inputs.pr_number),
    })).data;
    if (!requested.merged || !sameRelease(requested, repo)) {
      throw new Error("Recovery requires a same-repository merged release PR into main.");
    }
  }
  const closed = await github.paginate(github.rest.pulls.list, {
    ...repo, state: "closed", base: BASE, sort: "updated", direction: "desc",
  });
  const latest = closed.filter(pr => pr.merged_at && sameRelease(pr, repo))
    .sort((a, b) => Date.parse(b.merged_at) - Date.parse(a.merged_at))[0];
  if (requested && latest?.number !== requested.number) {
    throw new Error("A newer release exists; cannot recover a superseded release.");
  }
  if (!latest) return { prepare: "true" };
  const pr = requested || (await github.rest.pulls.get({
    ...repo, pull_number: latest.number,
  })).data;
  if (!pr.merged || !sameRelease(pr, repo) || !SHA.test(pr.merge_commit_sha || "")) {
    throw new Error("Invalid release merge.");
  }
  const sha = pr.merge_commit_sha;
  const comparison = (await github.rest.repos.compareCommitsWithBasehead({
    ...repo, basehead: `${sha}...${BASE}`,
  })).data;
  if (!["ahead", "identical"].includes(comparison.status)) {
    throw new Error("Release merge is not an ancestor of main.");
  }
  const version = await releaseVersion(github, repo, sha);
  const tag = await tagCommit(github, repo, version);
  if (tag && tag !== sha) throw new Error("Existing release tag points to a different revision.");
  const statuses = await github.paginate(github.rest.repos.listCommitStatusesForRef, {
    ...repo, ref: sha,
  });
  const status = statuses.find(item => item.context === STATUS);
  if (status?.state === "success") {
    if (!tag) throw new Error("Completed release is missing its tag.");
    return requested ? {} : { prepare: "true" };
  }
  // Releases shipped before this workflow have no completion status.
  if (!status && tag && await legacyComplete(github, repo, version, fetch)) {
    return requested ? {} : { prepare: "true" };
  }
  if (!requested) {
    throw new Error(`Release PR #${pr.number} is incomplete; recover that PR before preparing another.`);
  }
  await github.rest.repos.createCommitStatus({
    ...repo, sha, context: STATUS, state: "pending",
    description: "Qualifying and publishing the approved release merge",
  });
  return { publish_sha: sha, version, pr_number: String(pr.number) };
}

async function recordOutcome({ github, context, sha, qualification, publication }) {
  if (!SHA.test(sha)) throw new Error("Invalid completion revision.");
  const complete = qualification === "success" && publication === "success";
  await github.rest.repos.createCommitStatus({
    ...context.repo, sha, context: STATUS, state: complete ? "success" : "failure",
    description: complete ? "Hex publication and tagging complete" : "Recover the original release PR",
  });
}

async function verifyRelease(options) {
  if (!SHA.test(options.sha)) throw new Error("Invalid publication revision.");
  const selected = await selectRelease(options);
  if (selected.publish_sha !== options.sha) {
    throw new Error("Release selection changed; do not publish or tag.");
  }
}

module.exports = { prepareArgs, selectRelease, verifyRelease, recordOutcome };
