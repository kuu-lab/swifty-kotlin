@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// CODE-001: Regression coverage for exceptions that originate from a
/// conditionally-throwing call (cast, member call) inside a try/catch/finally
/// (or use{}/usePinned{}) construct that is itself nested inside an outer
/// try/catch. Before the fix, an outer `appendThrowAwareInstructions` pass
/// re-wrapped the inner construct's already-routed call, inserting a
/// premature jump to the outer catch dispatch that raced ahead of the
/// inner construct's own follow-up — silently skipping the inner finally
/// (or close()/unpin()) whenever the exception actually escaped to the
/// outer catch.
extension CodegenBackendIntegrationTests {
    func testNestedTryFinallyRunsInnerFinallyBeforeOuterCatch() throws {
        let source = """
        fun main() {
            try {
                try {
                    val any: Any = 42
                    val s = any as String
                    println(s)
                } finally {
                    println("inner finally")
                }
            } catch (e: ClassCastException) {
                println("outer caught")
            }
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NestedTryFinallyInnerBeforeOuterCatch",
            expected: "inner finally\nouter caught\ndone\n"
        )
    }

    func testThrowingCallInCatchBodyRunsFinallyBeforeOuterCatch() throws {
        // The cast lives directly in the catch body (not inside a further
        // nested try), so it is wired by *this* try's own catch-body
        // appendThrowAwareInstructions call. This isolates the catch-body
        // guard specifically: a try body containing the whole construct
        // would already be protected by the (separate) try-body guard even
        // without this one, so that shape would not actually exercise this
        // code path.
        let source = """
        class Boom : Exception("boom")

        fun main() {
            try {
                try {
                    throw Boom()
                } catch (e: Boom) {
                    val any: Any = 7
                    val s = any as String
                    println(s)
                } finally {
                    println("inner finally")
                }
            } catch (e: ClassCastException) {
                println("outer caught")
            }
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ThrowingCallInCatchBodyRunsFinallyBeforeOuterCatch",
            expected: "inner finally\nouter caught\ndone\n"
        )
    }

    func testUsePinnedNestedInsideTryCatchDoesNotSkipExceptionRouting() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        class Box(var value: Int)

        @ExperimentalForeignApi
        fun main() {
            try {
                val box = Box(42)
                box.usePinned { pinned: Pinned<Box> ->
                    println("pinned:${pinned.get().value}")
                    val any: Any = pinned.get().value
                    val s = any as String
                    println(s)
                }
            } catch (e: ClassCastException) {
                println("caught")
            }
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UsePinnedNestedInsideTryCatchRoutesException",
            expected: "pinned:42\ncaught\ndone\n"
        )
    }
}
