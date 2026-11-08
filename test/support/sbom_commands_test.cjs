const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { resolve, join } = require("node:path");
const { test } = require("node:test");

const justfile = resolve("justfile");
const outputs = ["slate-gleam.cdx.json", "slate-native.cdx.json"];
const cleanup = `rm -f ${outputs.map(name => `build/sbom/${name}`).join(" ")}`;

test("local build and generation recipes clear inventories before work", () => {
  for (const recipe of ["build", "build-strict", "sbom"]) {
    const result = spawnSync("just", ["--dry-run", recipe], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const commands = result.stderr.trim().split("\n");
    assert.equal(commands[0], cleanup);
    const generation = commands.indexOf(
      "licence_audit sbom --reproducible --output=build/sbom/slate-gleam.cdx.json",
    );
    assert.ok(generation > 0);
    if (recipe !== "sbom") {
      const compilation = commands.indexOf(
        `trellis run build${recipe === "build-strict" ? " --strict" : ""}`,
      );
      assert.ok(compilation > 0 && compilation < generation);
    }
  }
});

test("failed local generation removes stale inventories and preserves original evidence", () => {
  const fixture = resolve("build", `sbom-command-fixture-${randomUUID()}`);
  const directory = join(fixture, "build/sbom");
  const bin = join(fixture, "bin");
  mkdirSync(directory, { recursive: true });
  mkdirSync(bin);
  const original = join(fixture, "build/sbom-original.zip");
  writeFileSync(original, "original qualified archive");
  try {
    for (const failedTool of ["licence_audit", "syft"]) {
      for (const name of outputs) writeFileSync(join(directory, name), "stale inventory");
      writeFileSync(join(bin, "licence_audit"), failedTool === "licence_audit"
        ? "#!/bin/sh\nexit 1\n"
        : "#!/bin/sh\nprintf fresh > build/sbom/slate-gleam.cdx.json\n",
        { mode: 0o755 });
      writeFileSync(join(bin, "syft"), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
      const result = spawnSync("just", ["--justfile", justfile,
        "--working-directory", fixture, "sbom"], {
        encoding: "utf8",
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Recipe `sbom` failed/);
      assert.equal(existsSync(join(directory, "slate-native.cdx.json")), false);
      assert.equal(existsSync(join(directory, "slate-gleam.cdx.json")),
        failedTool === "syft");
      if (failedTool === "syft") {
        assert.equal(readFileSync(join(directory, "slate-gleam.cdx.json"), "utf8"), "fresh");
      }
      assert.equal(readFileSync(original, "utf8"), "original qualified archive");
    }
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});
