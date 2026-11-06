#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NothingOperandPrimitiveMemberCallTests {

    // KUU-4015: a non-null `Nothing` operand makes every primitive overload
    // applicable; kotlinc then selects the most specific via its numeric
    // widening priority (Int > Short > Byte, UInt > UShort > UByte,
    // Double > Float, with Long/ULong and Char incomparable to the rest).

    @Test
    func nothingOperandResolvesUniquePrimitiveOverloads() throws {
        let ctx = makeContextFromSource("""
        fun sample(
            b: Byte, s: Short, i: Int, l: Long,
            f: Float, d: Double, c: Char,
            ub: UByte, us: UShort, ui: UInt, ul: ULong
        ) {
            // mod: signed receivers pick the Int-parameter overload (Int result);
            // unsigned receivers pick the UInt-parameter overload (UInt result);
            // floating receivers pick the Double-parameter overload (Double result).
            val m1: Int = i.mod(TODO())
            val m2: Int = l.mod(TODO())
            val m3: Int = b.mod(TODO())
            val m4: Int = s.mod(TODO())
            val m5: UInt = ui.mod(TODO())
            val m6: UInt = ul.mod(TODO())
            val m7: UInt = ub.mod(TODO())
            val m8: UInt = us.mod(TODO())
            val m9: Double = f.mod(TODO())
            val m10: Double = d.mod(TODO())

            // floorDiv follows the same parameter winner; only the
            // Long/ULong receivers widen the result to Long/ULong.
            val fd1: Int = i.floorDiv(TODO())
            val fd2: Long = l.floorDiv(TODO())
            val fd3: Int = b.floorDiv(TODO())
            val fd4: Int = s.floorDiv(TODO())
            val fd5: UInt = ui.floorDiv(TODO())
            val fd6: ULong = ul.floorDiv(TODO())
            val fd7: UInt = ub.floorDiv(TODO())
            val fd8: UInt = us.floorDiv(TODO())

            // Char.plus(Int) is the only member overload, so it wins over the
            // Char.plus(String) extension.
            val p1: Char = c.plus(TODO())

            // Bitwise ops take the receiver-typed operand (or Int bitCount for
            // shifts) and return the receiver type.
            val a1: Int = i.and(TODO())
            val a2: Int = i.or(TODO())
            val a3: Int = i.xor(TODO())
            val a4: Long = l.and(TODO())
            val a5: UInt = ui.and(TODO())
            val a6: ULong = ul.xor(TODO())
            val a7: UByte = ub.and(TODO())
            val a8: UShort = us.or(TODO())
            val sh1: Int = i.shl(TODO())
            val sh2: Long = l.shr(TODO())
            val sh3: UInt = ui.shl(TODO())
            val sh4: ULong = ul.shr(TODO())
            val ush1: Int = i.ushr(TODO())
            val ush2: Long = l.ushr(TODO())
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")
    }

    @Test
    func nothingOperandKeepsAmbiguousPrimitiveCallsRejected() throws {
        let ctx = makeContextFromSource("""
        fun reject(
            b: Byte, s: Short, i: Int, l: Long,
            f: Float, d: Double, c: Char
        ) {
            i.plus(TODO())
            l.minus(TODO())
            b.times(TODO())
            s.div(TODO())
            i.rem(TODO())
            f.plus(TODO())
            f.minus(TODO())
            f.times(TODO())
            f.div(TODO())
            f.rem(TODO())
            d.plus(TODO())
            d.minus(TODO())
            c.minus(TODO())
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.count >= 13,
            "Expected ambiguous primitive calls with Nothing operands to be rejected, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test
    func nullableNothingOperandStillRejected() throws {
        let ctx = makeContextFromSource("""
        fun reject(i: Int, ui: UInt) {
            i.mod(null)
            ui.plus(null)
            i.floorDiv(null)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.count >= 3,
            "Expected nullable Nothing operands to stay rejected, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}

#endif
