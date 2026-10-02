#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `++` / `--` on Byte / Short / UByte / UShort must wrap to the operand's width, and
/// explicit `inc()` / `dec()` / `plus()` / `minus()` member calls on primitives must resolve.
@Suite
struct SmallIntegerIncrementWrapTests {
    private func loweredCallees(_ source: String, function: String = "main") throws -> [String] {
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
        return extractCallees(from: body, interner: ctx.interner)
    }

    @Test func testByteAndShortIncrementWrapToTheirWidth() throws {
        let callees = try loweredCallees("""
        fun main() {
            var b: Byte = 127
            b++
            var s: Short = -32768
            s--
        }
        """)
        #expect(callees.contains("kk_int_to_byte"))
        #expect(callees.contains("kk_int_to_short"))
    }

    @Test func testUnsignedSmallIncrementWrapToTheirWidth() throws {
        let callees = try loweredCallees("""
        fun main() {
            var ub: UByte = 255u
            ub++
            var us: UShort = 0u
            us--
        }
        """)
        #expect(callees.contains("kk_int_to_ubyte"))
        #expect(callees.contains("kk_int_to_ushort"))
    }

    @Test func testIntIncrementStaysOnBuiltinPath() throws {
        let callees = try loweredCallees("""
        fun main() {
            var i = 1
            i++
            println(i)
        }
        """)
        #expect(!callees.contains("inc"))
        #expect(!callees.contains("kk_int_to_byte"))
    }

    @Test func testCharPlusIntWrapsToSixteenBits() throws {
        let callees = try loweredCallees("""
        fun shift(c: Char, d: Int): Char = c + d
        fun main() { println(shift('a', 1)) }
        """, function: "shift")
        #expect(callees.contains("kk_int_to_char"))
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
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(!callees.contains("plus"))
        #expect(!callees.contains("minus"))
        #expect(!callees.contains("times"))
    }
}
#endif
