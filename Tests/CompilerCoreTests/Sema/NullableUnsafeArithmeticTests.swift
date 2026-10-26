#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableUnsafeArithmeticTests {
    @Test
    func rejectsNullableReceiverArithmeticBinaryOperators() throws {
        let operators = ["+", "-", "*", "/", "%"]
        for op in operators {
            let ctx = makeContextFromSource("""
            fun test(x: Int?, y: Int) {
                val r = x \(op) y
            }
            """)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
                "Expected KSWIFTK-SEMA-0026 for operator '\(op)', got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func rejectsNullableOperandForBuiltinArithmetic() throws {
        let ctx = makeContextFromSource("""
        fun test(x: Int, y: Int?) {
            val r = x + y
        }
        """)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" },
            "Expected KSWIFTK-SEMA-0002 for nullable rhs, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func rejectsNullableReceiverComparisonAndRangeOperators() throws {
        let operators = ["<", "<=", ">", ">=", "..", "..<"]
        for op in operators {
            let ctx = makeContextFromSource("""
            fun test(x: Int?, y: Int) {
                val r = x \(op) y
            }
            """)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
                "Expected KSWIFTK-SEMA-0026 for operator '\(op)', got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func rejectsNullableReceiverUnaryArithmeticOperators() throws {
        let operators = ["+", "-"]
        for op in operators {
            let ctx = makeContextFromSource("""
            fun test(x: Int?) {
                val r = \(op)x
            }
            """)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
                "Expected KSWIFTK-SEMA-0026 for unary '\(op)', got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func acceptsNullableReceiverWhenOperatorExtensionExists() throws {
        let ctx = makeContextFromSource("""
        operator fun Int?.plus(y: Int): Int = (this ?: 0) + y
        fun test(x: Int?) {
            val r = x + 1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsNullableStringPlus() throws {
        let ctx = makeContextFromSource("""
        fun test(s: String?) {
            val r = s + 1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsNonNullPrimitiveArithmetic() throws {
        let ctx = makeContextFromSource("""
        fun test(x: Int, y: Int) {
            val r = x + y
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
