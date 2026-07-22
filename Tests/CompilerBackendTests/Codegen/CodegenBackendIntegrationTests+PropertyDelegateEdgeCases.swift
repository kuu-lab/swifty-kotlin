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
}

