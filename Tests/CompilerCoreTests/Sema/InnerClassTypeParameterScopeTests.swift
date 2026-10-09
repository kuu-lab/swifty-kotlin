import Foundation
@testable import CompilerCore
import Testing

@Suite
struct InnerClassTypeParameterScopeTests {
    @Test
    func innerHeadersReuseOuterTypeParameterSymbols() throws {
        let source = """
        interface Source<X> { fun read(): X }
        class Outer<V : Any> {
            inner class Inner(val item: V) : Source<V> {
                constructor(item: V, ignored: Int) : this(item)
                val maybe: V? = item
                override fun read(): V = item
                fun echo(value: V): V = value
                fun <U : V> bounded(value: U): U = value
                fun <V> shadow(value: V): V = value
                fun local(): V { val current: V = item; return current }
                inner class Deep<W : V>(val second: W) {
                    val first: V = item
                }
            }
            inner class Shadow<V>(val own: V) : Source<V> {
                override fun read(): V = own
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            func symbol(_ names: String...) throws -> SymbolID {
                try #require(sema.symbols.lookup(fqName: names.map(ctx.interner.intern)))
            }
            let outer = try symbol("Outer")
            let outerParameter = try #require(sema.types.nominalTypeParameterSymbols(for: outer).first)
            let outerType = sema.types.make(.typeParam(TypeParamType(symbol: outerParameter)))
            let inner = try symbol("Outer", "Inner")
            let sourceSymbol = try symbol("Source")
            #expect(sema.types.nominalTypeParameterSymbols(for: inner).isEmpty)
            #expect(sema.symbols.supertypeTypeArgs(for: inner, supertype: sourceSymbol) == [.invariant(outerType)])
            #expect(sema.symbols.propertyType(for: try symbol("Outer", "Inner", "item")) == outerType)
            #expect(sema.symbols.propertyType(for: try symbol("Outer", "Inner", "maybe")) == sema.types.makeNullable(outerType))
            for constructor in sema.symbols.lookupAll(fqName: ["Outer", "Inner", "<init>"].map(ctx.interner.intern)) {
                let signature = try #require(sema.symbols.functionSignature(for: constructor))
                #expect(signature.parameterTypes.first == outerType)
                #expect(signature.typeParameterSymbols.isEmpty)
            }
            let echo = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "echo")))
            #expect(echo.parameterTypes == [outerType])
            #expect(echo.returnType == outerType)
            let bounded = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "bounded")))
            let boundedParameter = try #require(bounded.typeParameterSymbols.first)
            #expect(sema.symbols.typeParameterUpperBounds(for: boundedParameter) == [outerType])
            let shadowFunction = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "shadow")))
            let functionParameter = try #require(shadowFunction.typeParameterSymbols.first)
            #expect(functionParameter != outerParameter)
            #expect(shadowFunction.returnType == sema.types.make(.typeParam(TypeParamType(symbol: functionParameter))))
            let deep = try symbol("Outer", "Inner", "Deep")
            let deepParameter = try #require(sema.types.nominalTypeParameterSymbols(for: deep).first)
            #expect(sema.symbols.typeParameterUpperBounds(for: deepParameter) == [outerType])
            #expect(sema.symbols.propertyType(for: try symbol("Outer", "Inner", "Deep", "first")) == outerType)
            let shadow = try symbol("Outer", "Shadow")
            let shadowParameter = try #require(sema.types.nominalTypeParameterSymbols(for: shadow).first)
            #expect(shadowParameter != outerParameter)
            let shadowType = sema.types.make(.typeParam(TypeParamType(symbol: shadowParameter)))
            #expect(sema.symbols.supertypeTypeArgs(for: shadow, supertype: sourceSymbol) == [.invariant(shadowType)])
            #expect(sema.symbols.propertyType(for: try symbol("Outer", "Shadow", "own")) == shadowType)
        }
    }

    @Test
    func innerMutableCollectionResolvesOuterElementType() throws {
        let ctx = makeContextFromSource("""
        class Outer<V : Any> {
            abstract inner class Values : AbstractMutableList<V>() {
                override fun get(index: Int): V = TODO()
                override fun set(index: Int, element: V): V = TODO()
                override fun add(index: Int, element: V) {}
                override fun removeAt(index: Int): V = TODO()
                override val size: Int get() = 0
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let outer = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Outer")]))
        let outerParameter = try #require(sema.types.nominalTypeParameterSymbols(for: outer).first)
        let elementType = sema.types.make(.typeParam(TypeParamType(symbol: outerParameter)))
        let inner = try #require(sema.symbols.lookup(fqName: ["Outer", "Values"].map(ctx.interner.intern)))
        let base = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "AbstractMutableList"].map(ctx.interner.intern)))
        #expect(sema.symbols.supertypeTypeArgs(for: inner, supertype: base) == [.invariant(elementType)])
    }

    @Test(arguments: [
        "class Nested { fun read(value: V): V = value }",
        "object Nested { fun read(value: V): V = value }",
        "interface Nested { fun read(value: V): V }",
        "companion object { fun read(value: V): V = value }",
        "inner class Middle { class Nested { fun read(value: V): V = value } }",
        "class Middle { inner class Nested { fun read(value: V): V = value } }",
    ])
    func staticNestedHeadersDoNotCaptureOuterParameters(declaration: String) throws {
        try withTemporaryFile(contents: "class Outer<V> { \(declaration) }") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0025" && $0.message.contains("'V'")
            })
        }
    }

    @Test
    func staticBoundaryKeepsOnlyTheImmediateGenericOwnersParameters() throws {
        try withTemporaryFile(contents: """
        class Outer<V> {
            class Nested<W> {
                inner class Inner(val value: W) {
                    fun read(): W = value
                }
            }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let nested = try #require(sema.symbols.lookup(fqName: ["Outer", "Nested"].map(ctx.interner.intern)))
            let parameter = try #require(sema.types.nominalTypeParameterSymbols(for: nested).first)
            let property = try #require(sema.symbols.lookup(fqName: ["Outer", "Nested", "Inner", "value"].map(ctx.interner.intern)))
            #expect(sema.symbols.propertyType(for: property) == sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
        }
    }
}
