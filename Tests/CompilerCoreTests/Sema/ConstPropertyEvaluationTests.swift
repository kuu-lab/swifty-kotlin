#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ConstPropertyEvaluationTests {
    @Test
    func foldsResolvedReferencesAndBitwiseCalls() throws {
        let ctx = makeContextFromSources([
            """
            package constants
            import constants.Later.CODE as importedCode
            class Limits { companion object { const val MIN: Long = Long.MIN_VALUE } }
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
            "DOT": 15, "WRAP": -2147483648, "NESTED": 147,
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
        for (name, value) in [("LONG_BASE", Int64(1)), ("LONG_SHIFT", Int64.min), ("LONG_MASKED", -1), ("LONG_BITS", 240)] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["constants", name].map { ctx.interner.intern($0) }))
            guard case let .longLiteral(actual) = sema.symbols.constValueExprKind(for: symbol) else {
                Issue.record("Missing Long constant for \(name)")
                continue
            }
            #expect(actual == value)
        }
        let min = try #require(sema.symbols.allSymbols().first {
            ctx.interner.resolve($0.name) == "MIN" && $0.flags.contains(.constValue)
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
        const val PLAIN: Int = Source.plain
        const val COMPUTED: Int = Source.computed
        const val CALL: Int = compute()
        const val INFIX: Int = 1 custom 2
        const val ZERO: Int = 1 / 0
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0083" }
        #expect(errors.count == 7, "Expected all nonconstant initializers to be rejected: \(errors)")
        let sema = try #require(ctx.sema)
        for name in ["PLAIN", "COMPUTED", "CALL", "INFIX", "ZERO"] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["invalidConstants", name].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.constValueExprKind(for: symbol) == nil)
        }
    }
}
#endif
