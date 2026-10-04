#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct SuperCallDefaultArgumentRejectedTests {

    private static let rejectSources: [String] = [
        """
        package superdefault_reject0
        open class A { open fun f(x: Int = 1): String = "A$x" }
        class B : A() {
            override fun f(x: Int): String = "B$x"
            fun g(): String = super.f()
        }
        """,
        """
        package superdefault_reject1
        interface I { fun f(x: Int = 1): String = "I$x" }
        class C : I {
            override fun f(x: Int): String = "C$x"
            fun g(): String = super.f()
        }
        """,
        """
        package superdefault_reject2
        interface I { fun f(x: Int = 1): String = "I$x" }
        class D : I {
            override fun f(x: Int): String = "D$x"
            fun g(): String = super<I>.f()
        }
        """,
    ]

    private static let _sharedRejectCtx = Result {
        try semaContext(for: rejectSources)
    }

    private func sharedRejectCtx() throws -> CompilationContext {
        try Self._sharedRejectCtx.get()
    }

    // Covers all reject sources: class super call, interface super call, and
    // qualified `super<I>` call, each omitting a default argument.
    @Test func testError_superCallOmittingDefaultArgument() throws {
        let ctx = try sharedRejectCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-0306", in: ctx)
    }

    private static let acceptSources: [String] = [
        """
        package superdefault_accept0
        open class A { open fun f(x: Int = 1): String = "A$x" }
        class B : A() {
            override fun f(x: Int): String = "B$x"
            fun g(): String = super.f(7)
        }
        """,
        """
        package superdefault_accept1
        open class A { open fun f(x: Int = 1): String = "A$x" }
        class B : A() {
            override fun f(x: Int): String = "B$x"
        }
        fun useOverride(): String {
            val b: A = B()
            return b.f()
        }
        """,
    ]

    private static let _sharedAcceptCtx = Result {
        try semaContext(for: acceptSources)
    }

    private func sharedAcceptCtx() throws -> CompilationContext {
        try Self._sharedAcceptCtx.get()
    }

    // Covers all accept sources: a super call passing every argument
    // explicitly, and a non-super virtual call omitting the default.
    @Test func testNoError_explicitSuperCallOrNonSuperCallOmittingDefault() throws {
        let ctx = try sharedAcceptCtx()
        assertNoDiagnostic("KSWIFTK-SEMA-0306", in: ctx)
    }
}
#endif
