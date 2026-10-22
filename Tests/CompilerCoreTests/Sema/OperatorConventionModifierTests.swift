#if canImport(Testing)
@testable import CompilerCore
import Testing

/// kotlinc requires the `operator` modifier on functions used through
/// operator syntax (`get`/`set`/`componentN`/`compareTo` conventions).
/// The indexed-get/set, destructuring, and comparison resolution paths used
/// to admit members that merely shared the convention name (KUU-2995).
@Suite
struct OperatorConventionModifierTests {
    @Test
    func indexedGetWithoutOperatorIsRejected() throws {
        let source = """
        class C { fun get(i: Int) = 1 }
        fun probe(): Int = C()[0]
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func indexedSetWithoutOperatorIsRejected() throws {
        let source = """
        class C { fun set(i: Int, v: Int) {} }
        fun probe() { C()[0] = 1 }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func indexedCompoundAssignWithoutOperatorGetIsRejected() throws {
        let source = """
        class C { fun get(i: Int) = 0; operator fun set(i: Int, v: Int) {} }
        fun probe() { C()[0] += 1 }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func indexedCompoundAssignWithoutOperatorSetIsRejected() throws {
        let source = """
        class C { operator fun get(i: Int) = 0; fun set(i: Int, v: Int) {} }
        fun probe() { C()[0] += 1 }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func destructuringComponentWithoutOperatorIsRejected() throws {
        let source = """
        class C { fun component1() = 1 }
        fun probe(): Int { val (a) = C(); return a }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func compareToWithoutOperatorIsRejectedForAllComparisonOperators() throws {
        for op in ["<", "<=", ">", ">="] {
            let source = """
            class C { fun compareTo(o: C) = 1 }
            fun probe(): Boolean = C() \(op) C()
            """
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
            #expect(ctx.diagnostics.hasError, "\(op) should be rejected")
        }
    }

    @Test
    func operatorDeclaredConventionsStillCompile() throws {
        let source = """
        class C {
            operator fun get(i: Int) = i
            operator fun set(i: Int, v: Int) {}
            operator fun component1() = 1
            operator fun compareTo(o: C) = 0
        }
        fun probe(): Int {
            C()[0] = 1
            val (a) = C()
            return if (C() < C()) C()[0] + a else a
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func overrideInheritingOperatorRemainsUsableAsOperator() throws {
        let source = """
        interface I {
            operator fun get(i: Int): Int
            operator fun compareTo(o: I): Int
        }
        class C : I {
            override fun get(i: Int) = i
            override fun compareTo(o: I) = 0
        }
        fun probe(): Int = if (C() < C()) C()[0] else C()[1]
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func directCallsToConventionNamedFunctionsStayLegal() throws {
        let source = """
        class C {
            fun get(i: Int) = i
            fun set(i: Int, v: Int) {}
            fun component1() = 1
            fun compareTo(o: C) = 0
        }
        fun probe(): Int {
            C().set(0, 1)
            return C().get(0) + C().component1() + C().compareTo(C())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func builtinIndexedAccessAndComparisonsStayLegal() throws {
        let source = """
        fun probe(): Int {
            val a = IntArray(2)
            a[0] = 1
            val s = "a" < "b"
            val n = 1 < 2
            return if (s && n) a[0] else 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func dataClassDestructuringStaysLegal() throws {
        let source = """
        data class P(val x: Int, val y: Int)
        fun probe(): Int { val (a, b) = P(1, 2); return a + b }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0432", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
