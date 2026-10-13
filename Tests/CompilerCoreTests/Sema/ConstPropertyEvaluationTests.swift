#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ConstPropertyEvaluationTests {
    @Test
    func foldsCharArithmeticComparisonsAndInversion() throws {
        let ctx = makeContextFromSource("""
        package expressions
        const val A = 1 + 2
        const val B = "x" + "y"
        const val C = A * 10
        const val D = 1 shl 4
        const val E = 'a' + 1
        const val F = A == 3
        const val PREVIOUS = E - 1
        const val DISTANCE = 'z' - 'a'
        const val WRAPPED = '\\uFFFF' + 1
        const val UNDERFLOW = '\\u0000' - 1
        const val EQ = E == 'b'
        const val NE = A != 4
        const val LT = 'a' < E
        const val LE = A <= 3
        const val GT = 9007199254740993L > 9007199254740992L
        const val GE = D >= C
        const val FLAGS = (F && LT) || GE
        const val BOOL_EQ = FLAGS == true
        const val TEXT_EQ = B == "xy"
        const val FLOAT_LT = 1.5f < 2.0f
        const val DOUBLE_GE = 2.0 >= 1.5
        const val FLOAT_ROUNDED = 16777217f == 16777216f
        const val MIXED_LT = A < 3.5
        const val MIXED_ROUNDED = 16777217 > 16777216f
        const val NAN_EQ = Double.NaN == Double.NaN
        const val NAN_NE = Double.NaN != Double.NaN
        const val NAN_LE = Double.NaN <= 0.0
        const val SIGNED_ZERO = -0.0 == 0.0
        const val INVERTED = D.inv()
        const val LONG_INVERTED = 0L.inv()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "A": .intLiteral(3), "B": .stringLiteral(ctx.interner.intern("xy")),
            "C": .intLiteral(30), "D": .intLiteral(16), "E": .charLiteral(98),
            "F": .boolLiteral(true), "PREVIOUS": .charLiteral(97),
            "DISTANCE": .intLiteral(25), "WRAPPED": .charLiteral(0),
            "UNDERFLOW": .charLiteral(65535), "EQ": .boolLiteral(true),
            "NE": .boolLiteral(true), "LT": .boolLiteral(true),
            "LE": .boolLiteral(true), "GT": .boolLiteral(true),
            "GE": .boolLiteral(false), "FLAGS": .boolLiteral(true),
            "BOOL_EQ": .boolLiteral(true), "TEXT_EQ": .boolLiteral(true),
            "FLOAT_LT": .boolLiteral(true), "DOUBLE_GE": .boolLiteral(true),
            "FLOAT_ROUNDED": .boolLiteral(true), "NAN_EQ": .boolLiteral(false),
            "MIXED_LT": .boolLiteral(true), "MIXED_ROUNDED": .boolLiteral(false),
            "NAN_NE": .boolLiteral(true), "NAN_LE": .boolLiteral(false),
            "SIGNED_ZERO": .boolLiteral(true),
            "INVERTED": .intLiteral(-17), "LONG_INVERTED": .longLiteral(-1),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(fqName: ["expressions", name].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
            let property = try #require(sema.symbols.propertyType(for: symbol))
            if case .charLiteral = value { #expect(property == sema.types.charType) }
            if case .boolLiteral = value { #expect(property == sema.types.booleanType) }
        }
    }

    @Test
    func foldsResolvedReferencesAndBitwiseCalls() throws {
        let ctx = makeContextFromSources([
            """
            package constants
            import constants.Later.CODE as importedCode
            class Limits { companion object { const val MIN: Long = Long.MIN_VALUE } }
            interface Sized { companion object { const val BITS: Int = Int.SIZE_BITS } }
            const val COMPANION_MIN: Long = Limits.MIN
            const val COMPANION_BITS: Int = Sized.BITS
            object First { const val CODE: Int = Later.CODE + 1 }
            const val IMPORTED: Int = importedCode
            const val LONG_BASE: Long = 1
            const val LONG_SHIFT: Long = LONG_BASE shl 63
            const val SHIFTED: Int = 0xFF ushr 4
            const val UNSIGNED_SHIFT: Int = -1 ushr 1
            const val MASKED: Int = 1 shl 32
            const val NEGATIVE_SHIFT: Int = 1 shl -1
            const val BITS: Int = (0xF0 or 0x0F) xor (0xFF and 0x0F)
            const val LONG_MASKED: Long = -1L ushr 64
            const val LONG_BITS: Long = (0xF0L or 0x0FL) xor (0xFFL and 0x0FL)
            const val INFERRED_LONG = 2147483648
            const val INFERRED_SHIFT: Long = INFERRED_LONG shr 31
            const val DOT: Int = 255.ushr(4)
            const val WRAP: Int = Int.MAX_VALUE + 1
            const val NESTED: Int = (First.CODE shl 1) + SHIFTED
            """,
            """
            package constants
            object Later { const val CODE: Int = 65 }
            """,
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expectedInts: [String: Int64] = [
            "CODE": 66, "IMPORTED": 65, "SHIFTED": 15, "UNSIGNED_SHIFT": 2147483647,
            "MASKED": 1, "NEGATIVE_SHIFT": -2147483648, "BITS": 240,
            "DOT": 15, "WRAP": -2147483648, "NESTED": 147, "COMPANION_BITS": 32,
        ]
        for (name, value) in expectedInts {
            let path = name == "CODE" ? ["constants", "First", name] : ["constants", name]
            let symbol = try #require(sema.symbols.lookup(fqName: path.map { ctx.interner.intern($0) }))
            guard case let .intLiteral(actual) = sema.symbols.constValueExprKind(for: symbol) else {
                Issue.record("Missing Int constant for \(name)")
                continue
            }
            #expect(actual == value)
        }
        for (name, value) in [("LONG_BASE", Int64(1)), ("LONG_SHIFT", Int64.min), ("LONG_MASKED", -1), ("LONG_BITS", 240), ("COMPANION_MIN", Int64.min), ("INFERRED_LONG", 2147483648), ("INFERRED_SHIFT", 1)] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["constants", name].map { ctx.interner.intern($0) }))
            guard case let .longLiteral(actual) = sema.symbols.constValueExprKind(for: symbol) else {
                Issue.record("Missing Long constant for \(name)")
                continue
            }
            #expect(actual == value)
        }
        let min = try #require(sema.symbols.allSymbols().first {
            $0.name == ctx.interner.intern("MIN") && $0.flags.contains(.constValue)
        })
        guard case let .longLiteral(value) = sema.symbols.constValueExprKind(for: min.id) else {
            Issue.record("Missing Long.MIN_VALUE constant")
            return
        }
        #expect(value == Int64.min)
    }

    @Test
    func rejectsNonConstPropertiesUserCallsAndCycles() throws {
        let ctx = makeContextFromSource("""
        package invalidConstants
        object Source {
            val plain: Int = 65
            val computed: Int get() = 65
            const val A: Int = B
            const val B: Int = A
        }
        fun compute(): Int = 65
        infix fun Int.custom(other: Int): Int = this + other
        infix fun Byte.ushr(other: Int): Int = 999
        infix fun Int.shl(other: Byte): Int = 999
        fun Byte.inv(): Int = 999
        const val SMALL: Byte = 1
        const val PLAIN: Int = Source.plain
        const val COMPUTED: Int = Source.computed
        const val CALL: Int = compute()
        const val INFIX: Int = 1 custom 2
        const val CUSTOM_SHIFT: Int = SMALL ushr 1
        const val CUSTOM_ARGUMENT: Int = 1 shl SMALL
        const val ZERO: Int = 1 / 0
        const val CONDITIONAL: Int = if (true) 1 else 2
        const val CUSTOM_INVERSION: Int = SMALL.inv()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0083" }
        #expect(errors.count == 11, "Expected all nonconstant initializers to be rejected: \(errors)")
        let sema = try #require(ctx.sema)
        for name in ["PLAIN", "COMPUTED", "CALL", "INFIX", "CUSTOM_SHIFT", "CUSTOM_ARGUMENT", "ZERO", "CONDITIONAL", "CUSTOM_INVERSION"] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["invalidConstants", name].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.constValueExprKind(for: symbol) == nil)
        }
    }
}
#endif
