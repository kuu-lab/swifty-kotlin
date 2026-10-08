import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

// Marker annotations must not create module exports.
const module = await import(pathToFileURL(process.argv[2]).href);
assert.equal(module.ExportedBox, undefined);
assert.equal(module.JsHolder, undefined);
console.log("marker-export:false");
console.log("marker-holder-export:false");
