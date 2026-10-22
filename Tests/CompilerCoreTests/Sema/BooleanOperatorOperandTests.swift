#if canImport(Testing)
@testable import CompilerCore
import Testing

/// kotlinc rejects `true + true` because `Boolean` has no `plus` member:
/// with no operator candidates left, the primitive arithmetic fallback used
/// to promote Boolean operands into an Int result (KUU-2991). The same gate
/// keeps class/String/Any operands and range operators out of the fallback,
/// and unary +/- no longer accepts Boolean/Char operands.
@Suite
struct BooleanOperatorOperandTests {
    @Test
    func booleanBinaryArithmeticIsRejected() throws {
        for op in ["+", "-", "*", "/", "%"] {
            let source = """
            fun probe(): Int = true \(op) true
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "true \(op) true should be rejected")
        }
    }

    @Test
    func mixedBooleanNumericArithmeticIsRejected() throws {
        for expr in ["true + 1", "1 + true", "1L + true", "1.5 + true", "true + 1.5"] {
            let source = """
            fun probe() = \(expr)
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(expr) should be rejected")
        }
    }

    @Test
    func nonArithmeticOperandIsRejected() throws {
        for expr in ["1 + Foo()", "Foo() + 1", "1 - \"x\"", "1 * \"x\""] {
            let source = """
            class Foo
            fun probe() = \(expr)
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(expr) should be rejected")
        }
    }

    @Test
    func booleanRangeOperatorsAreRejected() throws {
        for expr in ["true..true", "true..1", "true downTo false"] {
            let source = """
            fun probe() = \(expr)
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(expr) should be rejected")
        }
    }

    @Test
    func unaryMinusPlusOnBooleanIsRejected() throws {
        for op in ["-", "+"] {
            let source = """
            fun probe() = \(op)true
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(op)true should be rejected")
        }
    }

    @Test
    func unaryMinusPlusOnCharIsRejected() throws {
        for op in ["-", "+"] {
            let source = """
            fun probe() = \(op)'a'
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(op)'a' should be rejected")
        }
    }

    @Test
    func booleanEqualityLogicAndNotStayLegal() throws {
        let source = """
        fun probe(): Boolean {
            val a = true == true
            val b = true != false
            val c = true && false || true
            return !a || b && c
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func builtinNumericArithmeticAndRangesStayLegal() throws {
        let source = """
        fun probe(): Int {
            val x = 1 + 2 - 3 * 4 / 5 % 6
            val c = 'a' + 1
            val s = "s" + true
            val neg = -x
            val pos = +x
            val r = 1..5
            val cr = 'a'..'z'
            val dr = 1.0..2.0
            val d = 5 downTo 1
            val st = r step 2
            return x + neg + pos
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unsignedAndFloatArithmeticStayLegal() throws {
        let source = """
        fun probe() {
            val u: UInt = 1u + 2u
            val l: ULong = 1uL + 2u
            val d = 1.5 + 2.0f
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
