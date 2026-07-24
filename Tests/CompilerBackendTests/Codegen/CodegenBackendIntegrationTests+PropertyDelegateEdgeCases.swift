@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value = lazyOf(42)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyOfValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // KSP-CAP-013: `lazy { ... }` (the plain call form, not the `by lazy { }`
    // property delegate) lowers its initializer lambda through the general
    // closure-conversion path (a boxed Function0 value), unlike the delegate
    // form whose initializer is a standalone top-level thunk. Runtime used to
    // bitcast `RuntimeLazyBox`'s stored initializer straight to a raw thunk
    // pointer and call it directly, which crashed for this boxed-closure
    // shape. Also pins that an explicit `Lazy<Int>` expected type resolves
    // and type-checks correctly end to end (not just at the Sema layer).
    func testCodegenCompilesLazyBlockValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // BUG-017: `lazy { ... }` called directly (not via `by`) lowers its
    // initializer lambda through the general closure-boxing path
    // (`kk_function_create_0`), unlike `by lazy` member/top-level accessors,
    // which pass a bare non-capturing function symbol. `RuntimeLazyBox`
    // previously bit-cast the stored handle straight to a context-free
    // `KKThunkEntryPoint` and called it, which for the boxed-closure case
    // jumped into heap data instead of code and crashed with a bad pointer
    // dereference. Fixed by invoking through `kk_function_invoke_0`, which
    // unwraps a boxed closure when present and falls back to a bare pointer
    // otherwise.
    func testCodegenCompilesDirectLazyCallValueRead() throws {
        let source = """
        fun main() {
            val value = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DirectLazyCallValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // Exercises the boxed-closure initializer with an actual captured
    // variable, rather than a trivial literal, since a capture-free lambda
    // could conceivably take a different codegen shape.
    func testCodegenCompilesLazyBlockCapturingOuterVariable() throws {
        let source = """
        fun main() {
            val base = 40
            val value = lazy { base + 2 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockCapturingOuterVariable",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // BUG-017: an explicit `Lazy<T>` type annotation used to resolve to a
    // dead, non-standard `kotlin.properties.Lazy` interface stub (registered
    // but otherwise unused) instead of the real `kotlin.Lazy` that `lazy()`/
    // `lazyOf()` actually return, because unqualified short-name lookup
    // picked whichever symbol was registered first (registration order, not
    // import visibility -- `kotlin.properties` isn't even a default import).
    // This made any explicitly annotated `Lazy<T>` local fail type checking
    // against `lazyOf(...)`'s inferred type. Fixed by removing the dead
    // `kotlin.properties.Lazy` registration.
    func testCodegenCompilesExplicitlyTypedLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazyOf(99)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ExplicitlyTypedLazyOfValueRead",
            expected:
                """
                99
                """ + "\n"
        )
    }
}
