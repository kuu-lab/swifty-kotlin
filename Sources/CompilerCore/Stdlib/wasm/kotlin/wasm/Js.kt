/*
 * `js(code)` intrinsic for the wasm target (Kotlin/Wasm kotlin/wasm/Js.kt).
 *
 * The runtime implementation is provided by the wasm-JS interop layer (M5):
 * the embedded snippet is evaluated against the module's import object. On
 * wasm-wasi it is a stub that returns null — `js()` only makes sense with a
 * JavaScript host.
 */

package kotlin.wasm

/**
 * Evaluates [code] as a JavaScript expression and returns its result.
 * `external` bodies are provided by the wasm backend; this declaration only
 * exists when compiling for a wasm target.
 */
public external fun js(code: String): JsAny?
