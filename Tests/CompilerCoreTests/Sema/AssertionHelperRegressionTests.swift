#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AssertionHelperRegressionTests {
    @Test func forwardConjunctiveContractsNarrowBothArguments() throws {
        let declarations = """
        import kotlin.contracts.*
        fun caller(a: String?, b: String?) {
            if (both(a, b)) return
            println(a.length + b.length)
        }
        @OptIn(ExperimentalContracts::class)
        fun both(a: String?, b: String?): Boolean {
            contract { returns(false) implies (a != null && b != null) }
            return a == null || b == null
        }
        """
        let ctx = makeContextFromSource(declarations)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func disjunctiveContractsDoNotNarrowBothArguments() throws {
        let ctx = makeContextFromSource("""
        import kotlin.contracts.*
        @OptIn(ExperimentalContracts::class)
        fun either(a: String?, b: String?) {
            contract { returns() implies (a != null || b != null) }
        }
        fun caller(a: String?, b: String?) {
            either(a, b)
            println(a.length + b.length)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" })
    }

    @Test func genericExtensionReferencesInferFromExplicitReceiver() throws {
        let ctx = makeContextFromSource("""
        fun <T> probe(array: Array<T>, value: T) {
            val contains: (Array<T>, T) -> Boolean = Array<T>::contains
            val stringify: (Array<*>?) -> String = Array<*>?::contentToString
            val equal: (Array<*>?, Array<*>?) -> Boolean = Array<*>?::contentEquals
            contains(array, value)
            stringify(null)
            equal(array, null)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func lexicalExtensionFunctionValueOutranksPackageExtension() throws {
        let ctx = makeContextFromSource("""
        fun <R, V> probe(array: R, element: V, contains: R.(V) -> Boolean): Boolean {
            return array.contains(element)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
            guard case let .memberCall(_, name, _, _, _) = expression,
                  name == ctx.interner.intern("contains")
            else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(calls.contains { sema.bindings.callableValueCallBinding(for: $0)?.extensionCallableExpr != nil })
    }

    @Test func callableReferencesKeepFunctionTypeForExplicitInvoke() throws {
        let ctx = makeContextFromSource("""
        fun increment(value: Int): Int = value + 1
        fun probe() {
            println(::increment.invoke(1))
            println(IntArray::get.invoke(intArrayOf(7), 0))
            println(arrayOf(42)::get.invoke(0))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func expectedFunctionTypeCanWidenCovariantReceiverParameter() throws {
        let ctx = makeContextFromSource("""
        fun <T> List<T>.choose(value: T): T = value
        fun probe() {
            val bound: (Any) -> Any = listOf("a")::choose
            val unbound: (List<String>, Any) -> Any = List<String>::choose
            bound(42)
            unbound(listOf("a"), 42)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func invariantReceiverParameterCannotBeWidened() throws {
        let ctx = makeContextFromSource("""
        fun <T> Array<T>.choose(value: T): T = value
        fun probe() { val bound: (Any) -> Any = arrayOf("a")::choose }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func starProjectionUsesInstantiatedDependentUpperBound() throws {
        let ctx = makeContextFromSource("""
        class Dep<A, B : A>
        class Bounded<T : Number>
        fun widen(value: Dep<String, *>): Dep<String, out String> = value
        fun bound(value: Bounded<*>): Bounded<out Number> = value
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func starProjectionDoesNotCaptureAnUnrelatedTypeParameter() throws {
        let ctx = makeContextFromSource("""
        class Dep<A, B : A> {
            fun bad(value: Dep<Any?, *>): Dep<Any?, out A> = value
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func starProjectionDoesNotUseALowerBoundAsAnUpperBound() throws {
        let ctx = makeContextFromSource("""
        class Dep<A, B : A>
        fun bad(value: Dep<in String, *>): Dep<in String, out String> = value
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func inapplicableLexicalFunctionValueKeepsPackageExtensionAvailable() throws {
        let ctx = makeContextFromSource("""
        fun wrongReceiver(contains: String.(Int) -> Boolean) = intArrayOf(1).contains(1)
        fun wrongArity(contains: IntArray.() -> Boolean) = intArrayOf(1).contains(1)
        fun wrongArgument(contains: IntArray.(String) -> Boolean) = intArrayOf(1).contains(1)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func inapplicableLexicalLambdaShapeKeepsPackageExtensionAvailable() throws {
        let ctx = makeContextFromSource("""
        fun String.pick(block: (Int, Int) -> Int) = block(2, 3)
        fun probe() {
            val pick: String.((Int) -> Int) -> Int = { it(7) }
            println("a".pick { a, b -> a + b })
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func precollectionDoesNotDuplicateCallsInPlaceMetadata() throws {
        let ctx = makeContextFromSource("""
        import kotlin.contracts.*
        @OptIn(ExperimentalContracts::class)
        inline fun once(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            block()
        }
        """)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("once")]))
        #expect(sema.symbols.contractCallsInPlaceEffects(for: symbol).count == 1)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func assertIsNotDoesNotIntroduceAnUpstreamAbsentContract() throws {
        let ctx = makeContextFromSource("""
        import kotlin.test.*
        fun probe(value: Any?) {
            assertIsNot<Int>(value)
            println(value.length)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("kotlin"), ctx.interner.intern("test"), ctx.interner.intern("assertIsNot"),
        ])
        #expect(!symbols.isEmpty)
        #expect(symbols.allSatisfy { sema.symbols.contractImplicationEffects(for: $0).isEmpty })
    }
}
#endif
