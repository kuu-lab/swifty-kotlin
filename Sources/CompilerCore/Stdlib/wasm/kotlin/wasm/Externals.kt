/*
 * JS interop reference types for the wasm target, mirroring the Kotlin/Wasm
 * kotlin.wasm surface (libraries/stdlib/wasm kotlin/wasm/Externals.kt).
 *
 * In the WasmGC end state these map onto `externref`/`anyref` values handed
 * to and from the JS host. While the backend lowers through linear memory
 * (M0–M5) they act as opaque markers: the underlying reference values move
 * as raw i64 handles and the interop calls themselves are runtime stubs.
 *
 * Note: the compiler frontend does not yet accept `external` on class or
 * interface declarations (KSWIFTK-SEMA-0400), so these are plain marker
 * declarations rather than JetBrains' `external interface`/`external class`
 * forms.
 */

package kotlin.wasm

/**
 * Base type of every JavaScript value passed across the interop boundary.
 * Corresponds to the WasmGC `externref` type.
 */
public interface JsAny

/**
 * A reference to a Kotlin object exported to JavaScript
 * (`externref` holding an `anyref` internally).
 */
public interface JsReference<T : Any> : JsAny

/** JavaScript `Array` view. */
public interface JsArray<T : JsAny?> : JsAny

/** JavaScript `Function`. */
public interface JsFunction : JsAny

/** JavaScript `Error`. */
public interface JsError : JsAny

/** JavaScript `String` primitive. */
public interface JsString : JsAny

/** JavaScript `Number` primitive. */
public interface JsNumber : JsAny

/** JavaScript `Boolean` primitive. */
public interface JsBoolean : JsAny

/** JavaScript `BigInt` primitive. */
public interface JsBigInt : JsAny
