import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

// Import the per-file module produced from native_observations.kt.
const module = await import(pathToFileURL(process.argv[2]).href);
assert.equal(new module.ExportedBox().value, 7);
assert.equal(module.JsHolder.message(), "js-annotations");
console.log("js-export:ExportedBox:7");
console.log("js-static:js-annotations");
