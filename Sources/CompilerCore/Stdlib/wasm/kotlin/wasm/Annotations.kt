/*
 * Kotlin/Wasm-specific annotations, mirroring the Kotlin 2.x
 * libraries/stdlib/wasm kotlin.wasm surface.
 *
 * These are declaration-only scaffolds for M3: the annotations record intent
 * for the wasm-JS interop layer (M5) — `@JsFun` bodies compile to embedded
 * JavaScript snippets, `@JsModule`/`@JsQualifier` name the import specifiers
 * they bind to. Nothing here affects codegen yet.
 */

package kotlin.wasm

/**
 * Replaces the body of an external function with a JavaScript code snippet.
 * Applied to `external` declarations compiled for the wasm-js target.
 */
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.PROPERTY_SETTER)
@Retention(AnnotationRetention.BINARY)
public annotation class JsFun(val code: String)

/**
 * Names the ES module an external declaration or file binds to
 * (`@JsModule("<module>")`).
 */
@Target(
    AnnotationTarget.FILE,
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CONSTRUCTOR
)
@Retention(AnnotationRetention.BINARY)
public annotation class JsModule(val module: String)

/**
 * Names the qualifier path a top-level external declaration binds to
 * (`@JsQualifier("a.b.c")`).
 */
@Target(
    AnnotationTarget.FILE,
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CONSTRUCTOR
)
@Retention(AnnotationRetention.BINARY)
public annotation class JsQualifier(val qualifier: String)

/**
 * Marks APIs that depend on the unstable JavaScript interop surface.
 */
@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalWasmJsInterop
