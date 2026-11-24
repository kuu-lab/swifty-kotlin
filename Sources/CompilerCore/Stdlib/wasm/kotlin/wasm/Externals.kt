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

public interface JsAny

public interface JsReference<T : Any> : JsAny

public interface JsArray<T : JsAny?> : JsAny

public interface JsFunction : JsAny

public interface JsError : JsAny

public interface JsString : JsAny

public interface JsNumber : JsAny

public interface JsBoolean : JsAny

public interface JsBigInt : JsAny
