const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");

test("Hex package contains both original qualified SBOMs byte for byte", () => {
  const archive = process.env.SBOM_ARCHIVE;
  assert.ok(archive, "SBOM_ARCHIVE must select the exported or published Hex archive");
  const contents = spawnSync("tar", ["-xOf", archive, "contents.tar.gz"], {
    maxBuffer: 16 * 1024 * 1024,
  });
  assert.ifError(contents.error);
  assert.equal(contents.status, 0, contents.stderr.toString());
  for (const name of ["slate-gleam.cdx.json", "slate-native.cdx.json"]) {
    const path = `priv/sbom/${name}`;
    const packaged = spawnSync("tar", ["-xzOf", "-", path], {
      input: contents.stdout, maxBuffer: 16 * 1024 * 1024,
    });
    assert.ifError(packaged.error);
    assert.equal(packaged.status, 0, `Missing packaged SBOM ${path}: ${packaged.stderr}`);
    assert.deepEqual(packaged.stdout, readFileSync(path), `Packaged SBOM differs: ${path}`);
  }
});
