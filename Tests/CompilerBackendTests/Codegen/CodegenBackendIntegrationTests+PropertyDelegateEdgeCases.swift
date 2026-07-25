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

    // MARK: - KSP-CAP-007 / BUG-014: local custom-delegate getValue/setValue

    // `val x by Prop()` inside a function body used to bind `x` to the `Prop()`
    // instance's own raw handle instead of calling `Prop().getValue(...)` — see
    // ExprLowerer+ControlFlowAndBlocks.swift's `.localDecl` case. This was
    // observable for every return type (reference or primitive), since getValue
    // was never called at all; it was most visibly wrong for primitives, which
    // printed as a raw object address instead of their value. Member and
    // top-level delegated properties were unaffected — they already route
    // through a synthesized getter/setter accessor.

    func testCodegenLocalCustomDelegateReturnsUnboxedInt() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x)
            println(x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateInt",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }

    func testCodegenLocalCustomDelegateReturnsString() throws {
        let source = """
        class StringProp {
            operator fun getValue(thisRef: Any?, property: Any?): String = "hello"
        }
        fun main() {
            val x by StringProp()
            println(x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateString",
            expected:
                """
                hello
                """ + "\n"
        )
    }

    func testCodegenLocalCustomDelegateReturnsBoolean() throws {
        let source = """
        class BooleanProp {
            operator fun getValue(thisRef: Any?, property: Any?): Boolean = true
        }
        fun main() {
            val x by BooleanProp()
            println(x)
            println(!x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateBoolean",
            expected:
                """
                true
                false
                """ + "\n"
        )
    }

    func testCodegenLocalCustomDelegateVarSetValueRoundTrips() throws {
        let source = """
        class IntProp {
            var backing: Int = 0
            operator fun getValue(thisRef: Any?, property: Any?): Int = backing
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
                backing = value
            }
        }
        fun main() {
            var x by IntProp()
            println(x)
            x = 100
            println(x)
            println(x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateVarSetValue",
            expected:
                """
                0
                100
                101
                """ + "\n"
        )
    }

    func testCodegenMemberCustomDelegatePrimitiveStillWorks() throws {
        // Regression guard: member-property custom delegates already worked
        // before this fix and share DeclTypeChecker+PropertyHelpers.swift's
        // typeCheckDelegate, whose signature this fix changed.
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Holder {
            val x by IntProp()
        }
        fun main() {
            val h = Holder()
            println(h.x)
            println(h.x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberDelegateIntStillWorks",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }
}
