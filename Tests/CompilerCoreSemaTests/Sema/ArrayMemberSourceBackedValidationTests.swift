#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4453: `Array<T>.copyInto`/`copyOf`/`copyOfRange`/`contains` used to fall
/// through the raw array-member fallback, which never checked argument types.
/// Type-mismatched calls were accepted by Sema and only failed at link time
/// with an unresolved `_copyInto`-style symbol. These members now resolve
/// against the bundled `kotlin.collections` declarations like the other
/// source-backed array members, so mismatches are Sema errors and correct
/// calls keep compiling.
@Suite
struct ArrayMemberSourceBackedValidationTests {
    private func runSemaOn(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Each test asserts the expected diagnostics.
        }
        return ctx
    }

    @Test func mismatchedCopyIntoDestinationIsRejected() {
        let ctx = runSemaOn("""
        fun main() {
            val a = arrayOf(1, 2)
            val dst = arrayOf("x", "y")
            a.copyInto(dst)
        }
        """)
        #expect(ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func copyIntoPrimitiveDestinationIsRejected() {
        let ctx = runSemaOn("""
        fun main() {
            val a = arrayOf(1, 2)
            val dst = IntArray(2)
            a.copyInto(dst)
        }
        """)
        #expect(ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func mismatchedCopyOfSizeIsRejected() {
        let ctx = runSemaOn("""
        fun main() {
            val a = arrayOf(1, 2)
            println(a.copyOf("x"))
        }
        """)
        #expect(ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func mismatchedCopyOfRangeBoundsAreRejected() {
        let ctx = runSemaOn("""
        fun main() {
            val a = arrayOf(1, 2)
            println(a.copyOfRange("x", 1))
        }
        """)
        #expect(ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func mismatchedContainsElementIsRejected() {
        for decl in ["arrayOf(1, 2)", "intArrayOf(1, 2)"] {
            let ctx = runSemaOn("""
            fun main() {
                val a = \(decl)
                println(a.contains("x"))
            }
            """)
            #expect(ctx.diagnostics.hasError, "\(decl) diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func validCallsStillCompile() {
        let ctx = runSemaOn("""
        fun main() {
            val a = arrayOf(1, 2)
            val dst = arrayOf(0, 0)
            a.copyInto(dst)
            println(a.copyOf(4))
            println(a.copyOfRange(0, 1))
            println(a.contains(2))
            println(a.contains(9))
            val star: Array<*> = arrayOf(1)
            val anyDst: Array<Any?> = arrayOf("x", "y")
            star.copyInto(anyDst)
            val ia = intArrayOf(1, 2)
            println(ia.contains(2))
            val idst = IntArray(2)
            ia.copyInto(idst)
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "diagnostics: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
