#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NothingOperandOperatorTests {
    // KUU-4351: a `Nothing` operand is a subtype of every parameter type, so
    // kotlinc keeps primitive `x + TODO()` ambiguous among the operator
    // overloads unless a single member applies (`Char.plus(Int)` for `+`,
    // or the unsigned operators for every arithmetic op).
    @Test
    func ambiguousNothingOperandsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun signed(i: Int, b: Byte, s: Short, l: Long, f: Float, d: Double, c: Char) {
            i + TODO()
            b + TODO()
            s + TODO()
            l + TODO()
            f + TODO()
            d + TODO()
            c - TODO()
            TODO() + 1
            TODO() + 'a'
            TODO() + TODO()
            TODO() - 1
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 11, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func uniqueNothingOperandOverloadsStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun unique(c: Char, u: UInt, ul: ULong, ub: UByte, us: UShort) {
            val charResult: Char = c + TODO()
            val uintResult: UInt = u + TODO()
            val ulongResult: ULong = ul + TODO()
            val ubyteResult: UInt = ub + TODO()
            val ushortResult: UInt = us + TODO()
            val stringResult: String = "x" + TODO()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-4351: kotlinc exposes six `compareTo` overloads on each signed
    // primitive receiver, so `i.compareTo(TODO())` is ambiguous there. KSwiftK
    // binds the single `Comparable<T>` member and reports the ambiguity
    // itself; unsigned primitives, Char and String keep their unique
    // resolution, matching kotlinc.
    @Test
    func nothingArgumentCompareToIsAmbiguousOnSignedPrimitives() throws {
        let ctx = makeContextFromSource("""
        fun ambiguous(i: Int, b: Byte, s: Short, l: Long, f: Float, d: Double) {
            i.compareTo(TODO())
            b.compareTo(TODO())
            s.compareTo(TODO())
            l.compareTo(TODO())
            f.compareTo(TODO())
            d.compareTo(TODO())
        }
        fun accepted(u: UInt, c: Char, str: String) {
            u.compareTo(TODO())
            c.compareTo(TODO())
            str.compareTo(TODO())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0003"
        }
        #expect(errors.count == 6, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
