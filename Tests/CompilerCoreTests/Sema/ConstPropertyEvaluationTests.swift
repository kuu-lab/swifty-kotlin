#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
            "FLOAT_ROUNDED": .boolLiteral(true), "NAN_EQ": .boolLiteral(true),
            "MIXED_LT": .boolLiteral(true), "MIXED_ROUNDED": .boolLiteral(false),
            "NAN_NE": .boolLiteral(false), "NAN_LE": .boolLiteral(false),
            "SIGNED_ZERO": .boolLiteral(false),
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
    func foldsFloatingPointArithmeticAndDivisionByZero() throws {
        let source = """
        package floatingConstants
        const val FLOAT_INFINITY = 1.0F / 0.0F
        const val NEGATIVE_FLOAT_INFINITY = -1.0F / 0.0F
        const val FLOAT_NAN = 0.0F / 0.0F
        const val FLOAT_SUM = 1.5F + 0.5F
        const val DOUBLE_INFINITY = 1.0 / 0.0
        const val DOUBLE_NAN = 0.0 / 0.0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
            let sema = try #require(ctx.sema)

            for (name, expected) in [
                ("FLOAT_INFINITY", Double.infinity),
                ("NEGATIVE_FLOAT_INFINITY", -Double.infinity),
                ("FLOAT_SUM", 2.0),
            ] {
                let symbol = try #require(sema.symbols.lookup(fqName: ["floatingConstants", name].map { ctx.interner.intern($0) }))
                guard case let .floatLiteral(value) = sema.symbols.constValueExprKind(for: symbol) else {
                    Issue.record("Missing Float constant for \(name)")
                    continue
                }
                #expect(value == expected)
            }

            let doubleInfinity = try #require(sema.symbols.lookup(fqName: ["floatingConstants", "DOUBLE_INFINITY"].map { ctx.interner.intern($0) }))
            guard case let .doubleLiteral(doubleInfinityValue) = sema.symbols.constValueExprKind(for: doubleInfinity) else {
                Issue.record("Missing Double Infinity constant")
                return
            }
            #expect(doubleInfinityValue == .infinity)

            let floatNaN = try #require(sema.symbols.lookup(fqName: ["floatingConstants", "FLOAT_NAN"].map { ctx.interner.intern($0) }))
            guard case let .floatLiteral(floatNaNValue) = sema.symbols.constValueExprKind(for: floatNaN) else {
                Issue.record("Missing Float NaN constant")
                return
            }
            #expect(floatNaNValue.isNaN)

            let doubleNaN = try #require(sema.symbols.lookup(fqName: ["floatingConstants", "DOUBLE_NAN"].map { ctx.interner.intern($0) }))
            guard case let .doubleLiteral(doubleNaNValue) = sema.symbols.constValueExprKind(for: doubleNaN) else {
                Issue.record("Missing Double NaN constant")
                return
            }
            #expect(doubleNaNValue.isNaN)
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
    func foldsUnsignedPrimitiveCompanionConstants() throws {
        let ctx = makeContextFromSource("""
        package unsignedConstants
        const val UBYTE_MIN = UByte.MIN_VALUE
        const val UBYTE_MAX = UByte.MAX_VALUE
        const val UBYTE_BITS = UByte.SIZE_BITS
        const val UBYTE_BYTES = UByte.SIZE_BYTES
        const val USHORT_MIN = UShort.MIN_VALUE
        const val USHORT_MAX = UShort.MAX_VALUE
        const val USHORT_BITS = UShort.SIZE_BITS
        const val USHORT_BYTES = UShort.SIZE_BYTES
        const val UINT_MIN = UInt.MIN_VALUE
        const val UINT_MAX = UInt.MAX_VALUE
        const val UINT_BITS = UInt.SIZE_BITS
        const val UINT_BYTES = UInt.SIZE_BYTES
        const val ULONG_MIN = ULong.MIN_VALUE
        const val ULONG_MAX = ULong.MAX_VALUE
        const val ULONG_BITS = ULong.SIZE_BITS
        const val ULONG_BYTES = ULong.SIZE_BYTES
        const val EXPLICIT_COMPANION_MAX: UInt = UInt.Companion.MAX_VALUE
        const val ALIASED_MAX = UINT_MAX
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "UBYTE_MIN": .uintLiteral(0),
            "UBYTE_MAX": .uintLiteral(255),
            "UBYTE_BITS": .intLiteral(8),
            "UBYTE_BYTES": .intLiteral(1),
            "USHORT_MIN": .uintLiteral(0),
            "USHORT_MAX": .uintLiteral(65535),
            "USHORT_BITS": .intLiteral(16),
            "USHORT_BYTES": .intLiteral(2),
            "UINT_MIN": .uintLiteral(0),
            "UINT_MAX": .uintLiteral(UInt64(UInt32.max)),
            "UINT_BITS": .intLiteral(32),
            "UINT_BYTES": .intLiteral(4),
            "ULONG_MIN": .ulongLiteral(0),
            "ULONG_MAX": .ulongLiteral(UInt64.max),
            "ULONG_BITS": .intLiteral(64),
            "ULONG_BYTES": .intLiteral(8),
            "EXPLICIT_COMPANION_MAX": .uintLiteral(UInt64(UInt32.max)),
            "ALIASED_MAX": .uintLiteral(UInt64(UInt32.max)),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["unsignedConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
        }
    }

    @Test
    func foldsPrimitiveMemberCallsAndAliasedStringConcatenation() throws {
        let ctx = makeContextFromSources([
            """
            package memberConstants.source
            const val TRUE = true
            const val TEXT = "source"
            const val LONG = 5L
            """,
            """
            package memberConstants.consumer
            import memberConstants.source.TRUE as importedTrue
            import memberConstants.source.TEXT as importedText
            import memberConstants.source.LONG as importedLong
            const val NOT = importedTrue.not()
            const val AND = importedTrue.and(true)
            const val OR = false.or(importedTrue)
            const val XOR = importedTrue.xor(false)
            const val CHAR_PLUS = 'A'.plus(2)
            const val CHAR_MINUS = 'z'.minus('a')
            const val BYTE_PLUS = 120.toByte().plus(10.toByte())
            const val LONG_PLUS = importedLong.plus(3L)
            const val LONG_REM = importedLong.rem(3L)
            const val INT_FLOOR_DIV = (-7).floorDiv(3)
            const val INT_FLOOR_MOD = (-7).mod(3)
            const val DOUBLE_FLOOR_MOD = (-7.0).mod(3.0)
            const val DOUBLE_MOD_ZERO = 1.0.mod(0.0)
            const val STRING_MEMBER_PLUS = importedText.plus("!")
            const val STRING_MIXED_MEMBER_PLUS = importedText.plus(5)
            const val STRING_BINARY_PLUS = importedText + "?"
            """,
        ])
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "NOT": .boolLiteral(false),
            "AND": .boolLiteral(true),
            "OR": .boolLiteral(true),
            "XOR": .boolLiteral(true),
            "CHAR_PLUS": .charLiteral(67),
            "CHAR_MINUS": .intLiteral(25),
            "BYTE_PLUS": .intLiteral(130),
            "LONG_PLUS": .longLiteral(8),
            "LONG_REM": .longLiteral(2),
            "INT_FLOOR_DIV": .intLiteral(-3),
            "INT_FLOOR_MOD": .intLiteral(2),
            "DOUBLE_FLOOR_MOD": .doubleLiteral(2),
            "STRING_MEMBER_PLUS": .stringLiteral(ctx.interner.intern("source!")),
            "STRING_MIXED_MEMBER_PLUS": .stringLiteral(ctx.interner.intern("source5")),
            "STRING_BINARY_PLUS": .stringLiteral(ctx.interner.intern("source?")),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["memberConstants", "consumer", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
        }
        let zeroDivisorMod = try #require(sema.symbols.lookup(
            fqName: ["memberConstants", "consumer", "DOUBLE_MOD_ZERO"].map { ctx.interner.intern($0) }
        ))
        guard case let .doubleLiteral(doubleModZeroValue) = sema.symbols.constValueExprKind(for: zeroDivisorMod) else {
            Issue.record("Missing Double modulo-by-zero constant")
            return
        }
        #expect(doubleModZeroValue.isNaN)
    }

    @Test
    func foldsFloatingFloorModWithInfiniteDivisor() throws {
        let ctx = makeContextFromSource("""
        package infiniteModConstants
        const val DOUBLE_NEGATIVE = (-1.0).mod(Double.POSITIVE_INFINITY)
        const val DOUBLE_POSITIVE = 1.0.mod(Double.NEGATIVE_INFINITY)
        const val DOUBLE_SAME_SIGN = 1.0.mod(Double.POSITIVE_INFINITY)
        const val FLOAT_NEGATIVE = (-1.0f).mod(Float.POSITIVE_INFINITY)
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "DOUBLE_NEGATIVE": .doubleLiteral(.infinity),
            "DOUBLE_POSITIVE": .doubleLiteral(-.infinity),
            "DOUBLE_SAME_SIGN": .doubleLiteral(1.0),
            "FLOAT_NEGATIVE": .floatLiteral(.infinity),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["infiniteModConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
        }
    }

    @Test
    func foldsCharCodeNumericConversionConstInitializers() throws {
        let ctx = makeContextFromSource("""
        package charCodeConstants
        private const val CR: Byte = '\\r'.code.toByte()
        private const val LF: Byte = '\\n'.code.toByte()
        const val CODE: Int = '\\r'.code
        const val WIDE_CODE: Long = '\\uFFFF'.code.toLong()
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "CR": .intLiteral(13),
            "LF": .intLiteral(10),
            "CODE": .intLiteral(13),
            "WIDE_CODE": .longLiteral(65535),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["charCodeConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
        }
    }

    @Test
    func foldsPrimitiveCompareToToStringAndUnaryMemberCalls() throws {
        let ctx = makeContextFromSource("""
        package primitiveMemberConstants
        const val ONE_BYTE = 1.toByte()
        const val BYTE_COMPARE = ONE_BYTE.compareTo(2.toByte())
        const val MIXED_COMPARE = 1.compareTo(2L)
        const val CHAR_COMPARE = 'A'.compareTo('B')
        const val BOOLEAN_COMPARE = true.compareTo(false)
        const val FLOAT_COMPARE = 1.5f.compareTo(1.25f)
        const val NAN_COMPARE = Double.NaN.compareTo(1.0)
        const val NEGATIVE_ZERO_COMPARE = (-0.0).compareTo(0.0)
        const val BYTE_UNARY_PLUS = ONE_BYTE.unaryPlus()
        const val BYTE_UNARY_MINUS = ONE_BYTE.unaryMinus()
        const val INT_UNARY_PLUS = 1.unaryPlus()
        const val LONG_UNARY_MINUS = 1L.unaryMinus()
        const val FLOAT_UNARY_MINUS = 1.0f.unaryMinus()
        const val DOUBLE_UNARY_PLUS = (-0.0).unaryPlus()
        const val BOOLEAN_STRING = true.toString()
        const val CHAR_STRING = 'A'.toString()
        const val BYTE_STRING = ONE_BYTE.toString()
        const val FLOAT_STRING = 1.25f.toString()
        const val NAN_STRING = Double.NaN.toString()
        val runtimeInt = 1
        const val NOT_CONSTANT = runtimeInt.toString()
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.code == "KSWIFTK-SEMA-0083")

        let sema = try #require(ctx.sema)
        let expected: [String: KIRExprKind] = [
            "BYTE_COMPARE": .intLiteral(-1),
            "MIXED_COMPARE": .intLiteral(-1),
            "CHAR_COMPARE": .intLiteral(-1),
            "BOOLEAN_COMPARE": .intLiteral(1),
            "FLOAT_COMPARE": .intLiteral(1),
            "NAN_COMPARE": .intLiteral(1),
            "NEGATIVE_ZERO_COMPARE": .intLiteral(-1),
            "BYTE_UNARY_PLUS": .intLiteral(1),
            "BYTE_UNARY_MINUS": .intLiteral(-1),
            "INT_UNARY_PLUS": .intLiteral(1),
            "LONG_UNARY_MINUS": .longLiteral(-1),
            "FLOAT_UNARY_MINUS": .floatLiteral(-1.0),
            "BOOLEAN_STRING": .stringLiteral(ctx.interner.intern("true")),
            "CHAR_STRING": .stringLiteral(ctx.interner.intern("A")),
            "BYTE_STRING": .stringLiteral(ctx.interner.intern("1")),
            "FLOAT_STRING": .stringLiteral(ctx.interner.intern("1.25")),
            "NAN_STRING": .stringLiteral(ctx.interner.intern("NaN")),
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["primitiveMemberConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == value, "Incorrect constant for \(name)")
        }

        let doubleUnaryPlus = try #require(sema.symbols.lookup(
            fqName: ["primitiveMemberConstants", "DOUBLE_UNARY_PLUS"].map { ctx.interner.intern($0) }
        ))
        guard case let .doubleLiteral(doubleUnaryPlusValue) = sema.symbols.constValueExprKind(for: doubleUnaryPlus) else {
            Issue.record("Missing Double constant for DOUBLE_UNARY_PLUS")
            return
        }
        #expect(doubleUnaryPlusValue == 0.0)
        #expect(doubleUnaryPlusValue.sign == .minus)

        let rejected = try #require(sema.symbols.lookup(
            fqName: ["primitiveMemberConstants", "NOT_CONSTANT"].map { ctx.interner.intern($0) }
        ))
        #expect(sema.symbols.constValueExprKind(for: rejected) == nil)
    }

    @Test
    func foldsLengthOfStringLiteralsAndConstProperties() throws {
        let ctx = makeContextFromSource("""
        package stringLengthConstants
        const val BARS = "▁▂▃▄▅▆▇█"
        const val BARS_LENGTH = BARS.length
        const val LAST_BAR_INDEX = BARS.length - 1
        const val LITERAL_LENGTH = "abc".length
        const val UTF16_LENGTH = "😀".length
        const val CONCAT_LENGTH = ("a" + BARS).length
        val runtimeText = "abc"
        const val NOT_CONSTANT = runtimeText.length
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.code == "KSWIFTK-SEMA-0083")

        let sema = try #require(ctx.sema)
        let expected: [String: Int64] = [
            "BARS_LENGTH": 8,
            "LAST_BAR_INDEX": 7,
            "LITERAL_LENGTH": 3,
            "UTF16_LENGTH": 2,
            "CONCAT_LENGTH": 9,
        ]
        for (name, value) in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["stringLengthConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == .intLiteral(value), "Incorrect constant for \(name)")
        }
        let rejected = try #require(sema.symbols.lookup(
            fqName: ["stringLengthConstants", "NOT_CONSTANT"].map { ctx.interner.intern($0) }
        ))
        #expect(sema.symbols.constValueExprKind(for: rejected) == nil)
    }

    @Test
    func foldsMixedTypeStringConcatenationConstInitializers() throws {
        let ctx = makeContextFromSource("""
        package mixedStringConstants
        const val SIGNED_VALUE = 5
        const val UNSIGNED_VALUE = 5u
        const val SIGNED_LITERAL = "x" + 5
        const val UNSIGNED_LITERAL = "x" + 5u
        const val SIGNED_REFERENCE = "x" + SIGNED_VALUE
        const val UNSIGNED_REFERENCE = "x" + UNSIGNED_VALUE
        val RUNTIME_VALUE = 5
        const val NOT_CONSTANT = "x" + RUNTIME_VALUE
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.code == "KSWIFTK-SEMA-0083")

        let sema = try #require(ctx.sema)
        for name in ["SIGNED_LITERAL", "UNSIGNED_LITERAL", "SIGNED_REFERENCE", "UNSIGNED_REFERENCE"] {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["mixedStringConstants", name].map { ctx.interner.intern($0) }
            ))
            #expect(sema.symbols.constValueExprKind(for: symbol) == .stringLiteral(ctx.interner.intern("x5")))
        }
        let rejected = try #require(sema.symbols.lookup(
            fqName: ["mixedStringConstants", "NOT_CONSTANT"].map { ctx.interner.intern($0) }
        ))
        #expect(sema.symbols.constValueExprKind(for: rejected) == nil)
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
