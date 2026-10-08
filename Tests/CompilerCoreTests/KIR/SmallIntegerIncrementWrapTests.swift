#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `++` / `--` on Byte / Short / UByte / UShort must wrap to the operand's width, and
/// explicit `inc()` / `dec()` / `plus()` / `minus()` member calls on primitives must resolve.
@Suite
struct SmallIntegerIncrementWrapTests {
    private func loweredCalls(_ source: String, function: String = "main") throws -> (StringInterner, [KIRCallSite]) {
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
        return (ctx.interner, kirCalls(in: body))
    }

    @Test func testByteAndShortIncrementWrapToTheirWidth() throws {
        let (interner, calls) = try loweredCalls("""
        fun main() {
            var b: Byte = 127
            b++
            var s: Short = -32768
            s--
        }
        """)
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.intToByte.name(in: interner) })
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.intToShort.name(in: interner) })
    }

    @Test func testUnsignedSmallIncrementWrapToTheirWidth() throws {
        let (interner, calls) = try loweredCalls("""
        fun main() {
            var ub: UByte = 255u
            ub++
            var us: UShort = 0u
            us--
        }
        """)
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.intToUByte.name(in: interner) })
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.intToUShort.name(in: interner) })
    }

    @Test func testIntIncrementStaysOnBuiltinPath() throws {
        let (interner, calls) = try loweredCalls("""
        fun main() {
            var i = 1
            i++
            println(i)
        }
        """)
        #expect(!calls.contains { $0.callee == interner.intern("inc") })
        #expect(!calls.contains { $0.callee == KIRRuntimeFunction.intToByte.name(in: interner) })
    }

    @Test func testCharPlusIntWrapsToSixteenBits() throws {
        let (interner, calls) = try loweredCalls("""
        fun shift(c: Char, d: Int): Char = c + d
        fun main() { println(shift('a', 1)) }
        """, function: "shift")
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.intToChar.name(in: interner) })
    }

    @Test func testExplicitIncDecMemberCallsResolveWithoutDiagnostics() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(Int.MAX_VALUE.inc())
            println(5.dec())
            println(5L.inc())
            val m: Int? = 4
            println(m?.inc())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test func testExplicitCharAndDoubleOperatorMemberCallsLowerToBinary() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println('A'.plus(2))
            println('C'.minus('A'))
            println(2.0.times(4))
        }
        """)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(!calls.contains { $0.callee == ctx.interner.intern("plus") })
        #expect(!calls.contains { $0.callee == ctx.interner.intern("minus") })
        #expect(!calls.contains { $0.callee == ctx.interner.intern("times") })
    }
}
#endif
