// WASI preview1 runner for `DIFF_BACKEND=wasm DIFF_ENGINE=node` in
// Scripts/diff_kotlinc.sh. Instantiates the module under node:wasi, inherits
// stdio, and propagates the module exit code to the node process.
import { readFileSync } from "node:fs";
import { WASI } from "node:wasi";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node wasi_node_runner.mjs <module.wasm>");
  process.exit(2);
}

const wasi = new WASI({
  version: "preview1",
  args: [wasmPath],
  env: {},
  returnOnExit: true,
});

const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {
  wasi_snapshot_preview1: wasi.wasiImport,
});

process.exitCode = wasi.start(instance);
