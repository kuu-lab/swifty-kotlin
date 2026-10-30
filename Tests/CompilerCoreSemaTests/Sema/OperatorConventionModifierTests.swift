#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
    func thisCompoundAssignResolvesPlusAssignOnReceiver() throws {
        // `this += x` in an extension body targets `plusAssign` on the
        // receiver — `this` is never assignable so no writeback is needed.
        // Used by ktor-utils' `Digest.build(bytes:)` extension.
        let source = """
        class C {
            var total: Int = 0
            operator fun plusAssign(x: Int) { total += x }
        }
        fun C.addAndReturn(x: Int): Int {
            this += x
            return total
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullAssertedIndexedCompoundAssignCompiles() throws {
        // `map[key]!! += v` — `get` returns `V?`, so the compound assign must
        // read through the `!!` non-null type. Used by ktor-http's
        // RegexParserGenerator.
        let source = """
        fun MutableMap<String, MutableList<Int>>.add(key: String, value: Int) {
            this[key]!! += value
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "operator fun plus(o: C, x: Int) = 1",
        "operator fun minus(o: C, x: Int) = 1",
        "operator fun unaryPlus(a: Int) = 1",
        "operator fun unaryMinus(a: Int) = 1",
        "operator fun not(a: Int) = false",
        "operator fun component1(a: Int) = 1",
        "operator fun component2(a: Int) = 1",
        "operator fun compareTo(a: Int, b: Int) = 0",
        "operator fun contains(a: Int, b: Int) = false",
        "operator fun iterator(a: Int) = a",
        "operator fun next(a: Int) = a",
        "operator fun hasNext(a: Int) = false",
        "operator fun get() = 0",
        "operator fun set(i: Int) {}",
        "operator fun plusAssign(a: Int, b: Int) {}",
        "operator fun equals(a: Int, b: Int) = false",
    ])
    func operatorArityMismatchIsRejected(member: String) throws {
        let source = """
        class C {
            \(member)
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0439", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        "operator fun plus(o: C) = 1",
        "operator fun unaryPlus() = 1",
        "operator fun inc() = C()",
        "operator fun inc(a: Int) = C()",
        "operator fun dec(a: Int) = C()",
        "operator fun component1() = 1",
        "operator fun compareTo(o: C) = 0",
        "operator fun contains(x: Int) = false",
        "operator fun get(i: Int) = i",
        "operator fun get(i: Int, j: Int) = i",
        "operator fun get(i: Int, j: Int, k: Int) = i",
        "operator fun set(i: Int, v: Int) {}",
        "operator fun set(i: Int, j: Int, v: Int) {}",
        "operator fun invoke() = 0",
        "operator fun invoke(a: Int, b: Int, c: Int) = 0",
        "operator fun plusAssign(x: Int) {}",
        "operator fun rangeTo(o: C) = o",
        "operator fun minus(o: C) = 1",
    ])
    func matchingOperatorArityIsAccepted(member: String) throws {
        let source = """
        class C {
            \(member)
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0439", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func containsOperatorCanCoexistWithDefaultedOverload() throws {
        let source = """
        class Haystack
        operator fun Haystack.contains(value: Int): Boolean = contains(value, false)
        fun Haystack.contains(value: Int, ignoreCase: Boolean = false): Boolean = ignoreCase
        fun operatorCall(haystack: Haystack): Boolean = 1 in haystack
        fun directCall(haystack: Haystack): Boolean = haystack.contains(1)
        fun explicitCall(haystack: Haystack): Boolean = haystack.contains(1, true)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func localOperatorFunctionArityMismatchIsRejected() throws {
        let source = """
        fun main() {
            operator fun unaryPlus(a: Int) = a
            operator fun String.times(n: Int, m: Int) = n
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let arityErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0439" }
        #expect(arityErrors.count == 2, "\(ctx.diagnostics.diagnostics)")
    }

    /// KUU-3804: `operator` functions are members of an anonymous `object`
    /// used as a `by` delegate expression, so `memberOrExtension` eligibility
    /// holds. The property delegate-body fallback must not re-parse the object
    /// body as a statement block, where the same members read as ineligible
    /// local functions.
    @Test
    func operatorMembersOnAnonymousObjectDelegateExpressionAreAccepted() throws {
        let source = """
        import kotlin.reflect.*

        var x: String by object {
            operator fun getValue(t: Any?, p: KProperty<*>): String = ""
            operator fun setValue(t: Any?, p: KProperty<*>, v: String) {}
        }
        class C {
            var y: String by object {
                operator fun getValue(t: Any?, p: KProperty<*>): String = ""
                operator fun setValue(t: Any?, p: KProperty<*>, v: String) {}
            }
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0439", in: ctx)
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
