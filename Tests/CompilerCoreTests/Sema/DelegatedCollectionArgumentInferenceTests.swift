#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct DelegatedCollectionArgumentInferenceTests {
    @Test(arguments: ["listOf(\"one\")", "listOf(\"one\", 2)", "emptyList()", "listOf<Any>(\"one\")"])
    func nestedFactoriesUseTheDelegatedElementType(argument: String) throws {
        let ctx = makeContextFromSource("""
        object Values : MutableList<Any> by mutableListOf()
        fun check() { Values.containsAll(\(argument)) }
        """, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let methods = sema.symbols.lookupAll(fqName: ["Values", "containsAll"].map(ctx.interner.intern))
        let signatures = methods.compactMap { symbol -> String? in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return nil }
            return "\(symbol): class=\(signature.classTypeParameterCount) params=\(signature.parameterTypes.map(sema.types.renderType)) binders=\(signature.typeParameterSymbols)"
        }
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics); forwarders=\(signatures)")
        let signature = try #require(methods.compactMap(sema.symbols.functionSignature(for:)).first)
        let parameter = try #require(signature.parameterTypes.first)
        guard case let .classType(collection) = sema.types.kind(of: parameter),
              let argument = collection.args.first else {
            Issue.record("Expected a concrete Collection<Any> argument")
            return
        }
        switch argument {
        case let .invariant(type), let .out(type), let .in(type):
            #expect(type == sema.types.anyType)
        case .star:
            Issue.record("Delegation must preserve the concrete element type")
        }
    }
    @Test
    func covariantStarChecksRetainKnownIterableElements() throws {
        let ctx = makeContextFromSource("""
        fun <T> Iterable<T>.probe(): T? {
            if (this is Collection<*>) {
                if (this.size == 1) {
                    return if (this is List<*>) this[0] as T else this.iterator().next()
                }
            }
            return null
        }
        """, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func delegatedListCanOverrideItsConcreteIterator() throws {
        let ctx = makeContextFromSource("""
        class ArrayView(delegate: List<Int>) : List<Int> by delegate {
            override fun iterator(): Iterator<Int> = listOf(8, 9).iterator()
        }
        """, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func userDeclaredGenericDelegationKeepsItsOwnBinder() throws {
        let ctx = makeContextFromSource("""
        interface Sink<T> { fun accept(value: T): T }
        class Strings : Sink<String> { override fun accept(value: String): String = value }
        class Forward<T>(target: Sink<T>) : Sink<T> by target
        fun check(): String = Forward(Strings()).accept("one")
        """, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
