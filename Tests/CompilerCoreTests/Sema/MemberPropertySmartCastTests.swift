#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MemberPropertySmartCastTests {
    @Test(arguments: [
        "if (args.x != null) println(args.x.length)",
        "if (args.x == null) return; println(args.x.length)",
        "if (args.x != null && args.x.length > 0) println(args.x.length)",
        "requireNotNull(args.x); println(args.x.length)",
        "check(args.x != null); println(args.x.length)",
        "when (args.x) { null -> println(0); else -> println(args.x.length) }",
        "when { args.x != null -> println(args.x.length); else -> println(0) }",
        "while (flag) { if (args.x != null) println(args.x.length); break }",
        "val reader = { if (args.x != null) println(args.x.length) }; reader()",
        "fun read() { if (args.x != null) println(args.x.length) }; read()",
        "if (flag) { var args = Args(null); args = Args(\"inner\") }; if (args.x != null) println(args.x.length)",
        "fun shadow(args: Args) { println(args.x) }; if (args.x != null) println(args.x.length)"
    ])
    func neverReassignedVarReceiver(body: String) throws {
        let ctx = makeContextFromSource("""
        class Args(val x: String?)
        fun test(flag: Boolean) {
            var args = Args("hello")
            \(body)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func neverReassignedVarReceiverNestedAndTypeNarrowing() throws {
        let ctx = makeContextFromSource("""
        class Inner(val x: Any?)
        class Outer(val inner: Inner?)
        fun test() {
            var outer = Outer(Inner("hello"))
            if (outer.inner != null && outer.inner.x is String) println(outer.inner.x.length)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (args.x != null) { args = Args(null); println(args.x.length) }",
        "if (args.x != null) { if (flag) args = Args(null); println(args.x.length) }",
        "if (args.x != null) { if (flag) { args = Args(null) }; println(args.x.length) }",
        "if (args.x != null) { when { flag -> args = Args(null); else -> println(0) }; println(args.x.length) }",
        "if (args.x != null) { while (flag) { args = Args(null); break }; println(args.x.length) }",
        "if (args.x != null) { do { println(args.x.length); args = Args(null) } while (flag) }",
        "if (args.x != null) { for (i in 0..1) { args = Args(null) }; println(args.x.length) }",
        "if (args.x != null) { try { args = Args(null) } finally { println(0) }; println(args.x.length) }",
        "val write = { args = Args(null) }; if (args.x != null) { write(); println(args.x.length) }",
        "if (args.x != null) { val write = { args = Args(null) }; write(); println(args.x.length) }",
        "val read = { if (args.x != null) println(args.x.length) }; args = Args(null); read()",
        "fun write() { args = Args(null) }; if (args.x != null) { write(); println(args.x.length) }",
        "val writer = object { fun write() { args = Args(null) } }; if (args.x != null) { writer.write(); println(args.x.length) }",
        "class Writer { fun write() { args = Args(null) } }; if (args.x != null) { Writer().write(); println(args.x.length) }",
        "requireNotNull(args.x); args = Args(null); println(args.x.length)"
    ])
    func reassignedReceiverIsNotStable(body: String) throws {
        let ctx = makeContextFromSource("""
        class Args(val x: String?)
        fun test(flag: Boolean) {
            var args = Args("hello")
            \(body)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0026", in: ctx)
    }

    @Test(arguments: [
        "if (args.x != null) println(args.x.length)",
        "if (null != args.x) println(args.x.length)",
        "if (args.x == null) println(0) else println(args.x.length)",
        "if (!(args.x == null)) println(args.x.length)",
        "if (args.x != null && args.x.length > 0) println(args.x.length)",
        "requireNotNull(args.x); println(args.x.length)",
        "requireNotNull(args.x) { \"missing\" }; println(args.x.length)",
        "checkNotNull(args.x); println(args.x.length)",
        "checkNotNull(args.x) { \"missing\" }; println(args.x.length)",
        "require(args.x != null); println(args.x.length)",
        "check(args.x != null); println(args.x.length)",
        "if (args.x == null) return; println(args.x.length)",
        "when (args.x) { null -> println(0); else -> println(args.x.length) }",
        "when { args.x != null -> println(args.x.length); else -> println(0) }"
    ])
    func stableValNarrowing(body: String) throws {
        let ctx = makeContextFromSource("""
        data class Args(val x: String?)
        fun test(args: Args) { \(body) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (outer.inner.x != null) println(outer.inner.x.length)",
        "requireNotNull(outer.inner.x); println(outer.inner.x.length)",
        "when (outer.inner.x) { null -> println(0); else -> println(outer.inner.x.length) }"
    ])
    func nestedPropertyChain(body: String) throws {
        let ctx = makeContextFromSource("""
        class Inner(val x: String?)
        class Outer(val inner: Inner)
        fun test(outer: Outer) { \(body) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func typeCheckAndThisReceiver() throws {
        let ctx = makeContextFromSource("""
        class Args(val x: Any?) {
            fun test() {
                if (this.x is String) println(this.x.length)
                when (this.x) { is String -> println(this.x.length); else -> println(0) }
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (a.x != null) println(b.x.length)",
        "if (a.x != null) println(a.y.length)",
        "if (a.x != null) println(a.x.length); println(a.x.length)",
        "if (a.x != null) println(a.x.length) else println(a.x.length)",
        "if (a.x != null || b.x != null) println(a.x.length)",
        "if (a.x != null) requireNotNull(b.x); println(b.x.length)",
        "when (a.x) { null -> println(a.x.length); else -> println(0) }"
    ])
    func narrowingDoesNotLeak(body: String) throws {
        let ctx = makeContextFromSource("""
        class Args(val x: String?, val y: String?)
        fun test(a: Args, b: Args) { \(body) }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0026", in: ctx)
    }

    @Test(arguments: [
        "class Args(var x: String?)",
        "class Args { val x: String? get() = \"hello\" }",
        "open class Args { open val x: String? = \"hello\" }",
        "abstract class Args { abstract val x: String? }",
        "open class Base { open val x: String? = null }; open class Args : Base() { override val x: String? = \"hello\" }",
        "class Args { val x: String? by lazy { \"hello\" } }"
    ])
    func unstablePropertiesAreNotNarrowed(declaration: String) throws {
        let ctx = makeContextFromSource("""
        \(declaration)
        fun test(args: Args) {
            if (args.x != null) println(args.x.length)
            requireNotNull(args.x)
            println(args.x.length)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0026" }.count == 2)
    }

    @Test func propertyChainRequiresStableIntermediateReceiver() throws {
        let ctx = makeContextFromSource("""
        class Inner(val x: String?)
        class Outer(var inner: Inner)
        fun test(outer: Outer) {
            if (outer.inner.x != null) println(outer.inner.x.length)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0026", in: ctx)
    }

    @Test func nullableIntermediateReceiver() throws {
        let ctx = makeContextFromSource("""
        class Inner(val x: String?)
        class Outer(val inner: Inner?)
        fun test(outer: Outer) {
            if (outer.inner != null && outer.inner.x != null) println(outer.inner.x.length)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func sourceContractNarrowsMember() throws {
        let ctx = makeContextFromSource("""
        import kotlin.contracts.*
        @OptIn(ExperimentalContracts::class)
        inline fun ensure(value: String?) {
            contract { returns() implies (value != null) }
            if (value == null) throw IllegalArgumentException("missing")
        }
        class Args(val x: String?)
        fun test(args: Args) {
            ensure(args.x)
            println(args.x.length)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func memberFlowMergeKeepsOnlyFactsOnBothPaths() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let type = types.stringType
        let first = DataFlowReference(root: SymbolID(rawValue: 1), properties: [SymbolID(rawValue: 3)])
        let second = DataFlowReference(root: SymbolID(rawValue: 2), properties: [SymbolID(rawValue: 3)])
        let flow = VariableFlowState(possibleTypes: [type], nullability: .nonNull, isStable: true)
        var lhs = DataFlowState()
        lhs[first] = flow
        lhs[second] = flow
        var rhs = DataFlowState()
        rhs[first] = flow
        let merged = analyzer.merge(lhs, rhs)
        #expect(merged[first] == flow)
        #expect(merged[second] == nil)
        #expect(merged.variables.isEmpty)
    }
}
#endif
