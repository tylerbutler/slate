const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");

function inventory(kind) {
  const bom = JSON.parse(readFileSync(`priv/sbom/slate-${kind}.cdx.json`, "utf8"));
  assert.equal(bom.bomFormat, "CycloneDX");
  assert.equal(bom.specVersion, "1.6");
  assert.ok(Array.isArray(bom.components));
  assert.ok(Array.isArray(bom.dependencies));
  const refs = new Set(bom.components.map(component => component["bom-ref"]));
  assert.equal(refs.size, bom.components.length, "duplicate component references");
  assert.ok([...refs].every(ref => typeof ref === "string" && ref.length > 0));
  const root = bom.metadata.component["bom-ref"];
  assert.ok(typeof root === "string" && root.length > 0);
  assert.ok(!refs.has(root), "root duplicates a dependency component");
  refs.add(root);
  const graph = new Map();
  for (const edge of bom.dependencies) {
    assert.ok(refs.has(edge.ref), `unknown dependency source: ${edge.ref}`);
    assert.ok(!graph.has(edge.ref), `duplicate dependency source: ${edge.ref}`);
    assert.ok(Array.isArray(edge.dependsOn));
    for (const ref of edge.dependsOn) assert.ok(refs.has(ref), `unknown dependency: ${ref}`);
    graph.set(edge.ref, edge.dependsOn);
  }
  return { bom, graph };
}

test("Gleam SBOM matches root identity, complete locked inventory, hashes, scopes, and graph", () => {
  const config = readFileSync("gleam.toml", "utf8");
  const manifest = readFileSync("manifest.toml", "utf8");
  const packages = [...manifest.matchAll(/\{ name = "([^"]+)", version = "([^"]+)",([^\n]*) \}/g)]
    .map(([, name, version, fields]) => {
      assert.match(fields, /source = "hex"/);
      return {
        name, version,
        checksum: fields.match(/outer_checksum = "([A-Fa-f0-9]{64})"/)[1].toLowerCase(),
        requires: [...fields.match(/requirements = \[([^\]]*)\]/)[1].matchAll(/"([^"]+)"/g)]
          .map(match => match[1]),
      };
    });
  assert.equal(packages.length, (manifest.match(/\{ name = /g) || []).length);
  assert.ok(packages.length > 0);
  const { bom, graph } = inventory("gleam");
  assert.equal(bom.metadata.component.name, "slate");
  assert.equal(bom.metadata.component.version, config.match(/^version = "([^"]+)"/m)[1]);
  assert.deepEqual(bom.components.map(p => `${p.name}@${p.version}`).sort(),
    packages.map(p => `${p.name}@${p.version}`).sort());
  const direct = [...config.match(/\[dependencies\]\n([\s\S]*?)(?=\n\[)/)[1]
    .matchAll(/^([a-z][a-z0-9_]*) = /gm)].map(match => match[1]);
  const required = new Set(direct);
  for (const name of required) {
    const pkg = packages.find(p => p.name === name);
    assert.ok(pkg, `missing runtime dependency: ${name}`);
    for (const dependency of pkg.requires) required.add(dependency);
  }
  for (const pkg of packages) {
    const component = bom.components.find(p => p.name === pkg.name);
    assert.equal(component.purl, `pkg:hex/${pkg.name}@${pkg.version}`);
    assert.equal(component.scope, required.has(pkg.name) ? "required" : "optional");
    assert.equal(component.hashes.find(hash => hash.alg === "SHA-256").content, pkg.checksum);
    assert.deepEqual((graph.get(component["bom-ref"]) || []).slice().sort(),
      pkg.requires.map(name => bom.components.find(p => p.name === name)["bom-ref"]).sort());
  }
  const rootRequirements = [...manifest.split("[requirements]\n")[1]
    .matchAll(/^([a-z][a-z0-9_]*) = /gm)].map(match => match[1]);
  assert.deepEqual(graph.get(bom.metadata.component["bom-ref"]).slice().sort(),
    rootRequirements.map(name => bom.components.find(p => p.name === name)["bom-ref"]).sort());
});

test("native SBOM matches all Cargo.lock crates and target-specific dependency relationships", () => {
  const lock = readFileSync("priv/slate_lock/source/Cargo.lock", "utf8");
  const packages = [...lock.matchAll(/\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"([\s\S]*?)(?=\n\[\[package\]\]|$)/g)]
    .map(([, name, version, fields]) => ({
      name, version,
      dependencies: [...(fields.match(/dependencies = \[([\s\S]*?)\]/)?.[1] || "")
        .matchAll(/"([^"]+)"/g)].map(match => match[1]),
    }));
  assert.equal(packages.length, (lock.match(/\[\[package\]\]/g) || []).length);
  assert.ok(packages.length > 0);
  const { bom, graph } = inventory("native");
  const crates = bom.components.filter(component => component.type === "library");
  assert.ok(bom.components.every(component => component.type === "library"
    || (component.type === "file" && component.name === "/Cargo.lock")));
  const files = bom.components.filter(component => component.type === "file");
  assert.equal(files.length, 1, "missing or duplicated Cargo.lock observation");
  assert.equal(files[0].hashes.find(hash => hash.alg === "SHA-256").content,
    createHash("sha256").update(lock).digest("hex"));
  assert.deepEqual(crates.map(p => `${p.name}@${p.version}`).sort(),
    packages.map(p => `${p.name}@${p.version}`).sort());
  for (const pkg of packages) {
    const component = bom.components.find(p => p.name === pkg.name && p.version === pkg.version);
    const expected = pkg.dependencies.map(dependency => {
      const [name, version] = dependency.split(" ");
      const candidates = bom.components.filter(p => p.name === name && (!version || p.version === version));
      assert.equal(candidates.length, 1, `ambiguous dependency: ${dependency}`);
      return candidates[0]["bom-ref"];
    });
    assert.deepEqual((graph.get(component["bom-ref"]) || []).slice().sort(), expected.sort());
  }
  for (const name of ["rustler", "rustix", "windows-sys"]) {
    assert.ok(bom.components.some(component => component.name === name), `missing native target dependency: ${name}`);
  }
});
