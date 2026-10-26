#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IndexedSetExpectedTypeInferenceTests {
    @Test
    func genericExtensionSetContextualizesNestedConstructorArgument() throws {
        let source = """
        class Inv1<T>
        class Inv2<K, V>
        operator fun <K, V> Inv2<K, V>.set(key: K, value: V) { }
        class Something {
            val guilds = Inv2<Int, Inv1<String>>()
            fun test() { guilds[0] = Inv1() }
        }
        fun <T> assign(guilds: Inv2<Int, Inv1<T>>) { guilds[0] = Inv1() }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected the setter value type to infer Inv1<String>: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let constructor = try #require(nameRefCallExprID(named: "Inv1", in: ast, interner: ctx.interner))
            guard case let .classType(inferredType) = sema.types.kind(of: try #require(sema.bindings.exprType(for: constructor))) else {
                Issue.record("Expected Inv1() to have a class type")
                return
            }
            let inv1 = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Inv1")]))
            #expect(inferredType.classSymbol == inv1)
            #expect(inferredType.args == [.invariant(sema.types.stringType)])
        }
    }
}
#endif
