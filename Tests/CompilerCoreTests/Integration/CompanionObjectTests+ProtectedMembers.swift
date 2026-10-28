#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension CompanionObjectTests {
    /// KUU-3605: a protected member declared in a companion object is scoped
    /// to the companion's containing class — the class itself, its nested and
    /// inner classes, and nested objects may access it (kotlinc accepts
    /// codegen/box/regressions/kt5395.kt).
    @Test func protectedCompanionMemberAccessibleInsideContainingClass() throws {
        let source = """
        class D {
            companion object {
                protected val F: String = "OK"
                protected fun gen(): String = "GEN"
            }
            inner class E {
                fun foo() = F
                fun bar() = gen()
                fun qualified() = D.F
            }
            class N {
                fun foo() = F
            }
            inner class E2 {
                inner class Deep {
                    fun foo() = F
                }
            }
            object O {
                fun foo() = F
            }
            fun self() = F
        }
        fun main() { println(D().E().foo()) }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    /// The companion scope does not leak outside the containing class: an
    /// unrelated class and a top-level function still cannot reach the
    /// protected member, matching kotlinc's SEMA-0041-equivalent rejection.
    @Test func protectedCompanionMemberRejectedOutsideContainingClass() throws {
        let source = """
        class D {
            companion object {
                protected val F: String = "OK"
            }
        }
        class X {
            fun foo() = D.F
        }
        fun top() = D.F
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0041" }
        #expect(errors.count == 2, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
