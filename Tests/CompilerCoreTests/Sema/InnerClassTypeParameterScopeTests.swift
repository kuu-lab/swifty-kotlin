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
                #expect(signature.typeParameterSymbols == [outerParameter])
                #expect(signature.classTypeParameterCount == 1)
            }
            let echo = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "echo")))
            #expect(echo.parameterTypes == [outerType])
            #expect(echo.returnType == outerType)
            let bounded = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "bounded")))
            #expect(bounded.typeParameterSymbols.first == outerParameter)
            let boundedParameter = try #require(bounded.typeParameterSymbols.last)
            #expect(sema.symbols.typeParameterUpperBounds(for: boundedParameter) == [outerType])
            let shadowFunction = try #require(sema.symbols.functionSignature(for: try symbol("Outer", "Inner", "shadow")))
            #expect(shadowFunction.typeParameterSymbols.first == outerParameter)
            let functionParameter = try #require(shadowFunction.typeParameterSymbols.last)
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
    func innerMemberMethodUsesCapturedOuterTypeArgument() throws {
        let ctx = makeCompilationContext(inputs: ["/tmp/kuu-2283-inner-receiver.kt"], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: ctx.options.inputs[0], contents: Data("""
        interface CharLike { val length: Int }
        class Text : CharLike { override val length: Int = 2 }
        class A<T : CharLike> {
            inner class I {
                fun f(g: T): Int = g.length
            }
        }
        fun use() {
            val result: Int = A<Text>().I().f(Text())
        }
        """.utf8))

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let method = try #require(sema.symbols.lookup(fqName: ["A", "I", "f"].map(ctx.interner.intern)))
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard sema.bindings.callBinding(for: id)?.chosenCallee == method else { return nil }
            return id
        }
        #expect(calls.count == 1)
        #expect(calls.first.flatMap { sema.bindings.exprType(for: $0) } == sema.types.intType)
    }

    @Test
    func memberMethodsInferAllCapturedAndOwnTypeArguments() throws {
        let ctx = makeCompilationContext(inputs: ["/tmp/kuu-2283-inner-chain.kt"], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: ctx.options.inputs[0], contents: Data("""
        class OuterValue
        class MiddleValue
        class InnerValue
        class Outer<T> {
            inner class Middle<M> {
                inner class Inner<I> {
                    fun outerValue(value: T): T = value
                    fun middleValue(value: M): M = value
                    fun innerValue(value: I): I = value
                    fun all(outer: T, middle: M, inner: I): T = outer
                }
            }
        }
        class Box<T> { fun echo(value: T): T = value }
        fun use() {
            val inner = Outer<OuterValue>().Middle<MiddleValue>().Inner<InnerValue>()
            val outer: OuterValue = inner.outerValue(OuterValue())
            val middle: MiddleValue = inner.middleValue(MiddleValue())
            val own: InnerValue = inner.innerValue(InnerValue())
            val all: OuterValue = inner.all(OuterValue(), MiddleValue(), InnerValue())
            val ordinary: OuterValue = Box<OuterValue>().echo(OuterValue())
        }
        """.utf8))

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        func classType(_ name: String) throws -> TypeID {
            let symbol = try #require(sema.symbols.lookup(fqName: [name].map(ctx.interner.intern)))
            return sema.types.make(.classType(ClassType(classSymbol: symbol)))
        }
        let expectedTypes: [String: TypeID] = [
            "outerValue": try classType("OuterValue"),
            "middleValue": try classType("MiddleValue"),
            "innerValue": try classType("InnerValue"),
            "all": try classType("OuterValue"),
            "echo": try classType("OuterValue"),
        ]
        var checkedCalls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  let expectedType = expectedTypes[ctx.interner.resolve(symbol.name)]
            else { continue }
            #expect(sema.bindings.exprType(for: id) == expectedType)
            checkedCalls += 1
        }
        #expect(checkedCalls == expectedTypes.count)
    }

    @Test
    func innerMemberMethodsPreserveOuterProjectionBounds() throws {
        try withTemporaryFile(contents: """
        class Text
        class Outer<T>(val value: T) {
            inner class Inner {
                fun read(): T = value
                fun write(value: T) {}
            }
        }
        fun readOut(outer: Outer<out Text>): Text = outer.Inner().read()
        fun readIn(outer: Outer<in Text>): Any? = outer.Inner().read()
        fun writeIn(outer: Outer<in Text>) { outer.Inner().write(Text()) }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func innerMemberMethodRejectsWriteThroughOutProjectedOuter() throws {
        try withTemporaryFile(contents: """
        class Text
        class Outer<T> {
            inner class Inner {
                fun write(value: T) {}
            }
        }
        fun writeOut(outer: Outer<out Text>) { outer.Inner().write(Text()) }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Writing through an out-projected outer receiver must be rejected.")
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

    @Test
    func unqualifiedInnerClassTypeSpellsCapturedOuterArguments() throws {
        // KUU-3240: `KeySet` inside `CIM<Value>` must spell `CIM<Value>.KeySet`
        // so constructor results match properties, locals and return types.
        try withTemporaryFile(contents: """
        class CIM<Value> {
            private var cached: KeySet? = null
            fun f() {
                cached = KeySet()
                val s: KeySet = KeySet()
            }
            fun g(): KeySet = KeySet()
            private inner class KeySet {
                fun h(): KeySet = KeySet()
            }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let outer = try #require(sema.symbols.lookup(fqName: ["CIM"].map(ctx.interner.intern)))
            let keySet = try #require(sema.symbols.lookup(fqName: ["CIM", "KeySet"].map(ctx.interner.intern)))
            let outerParameter = try #require(sema.types.nominalTypeParameterSymbols(for: outer).first)
            let captured: [TypeArg] = [.invariant(sema.types.make(.typeParam(TypeParamType(symbol: outerParameter))))]
            let expected = sema.types.make(.classType(sema.types.classType(for: keySet, arguments: captured)))
            let property = try #require(sema.symbols.lookup(fqName: ["CIM", "cached"].map(ctx.interner.intern)))
            #expect(sema.symbols.propertyType(for: property) == sema.types.makeNullable(expected))
            let gSymbol = try #require(sema.symbols.lookup(fqName: ["CIM", "g"].map(ctx.interner.intern)))
            let g = try #require(sema.symbols.functionSignature(for: gSymbol))
            #expect(g.returnType == expected)
            let hSymbol = try #require(sema.symbols.lookup(fqName: ["CIM", "KeySet", "h"].map(ctx.interner.intern)))
            let h = try #require(sema.symbols.functionSignature(for: hSymbol))
            #expect(h.returnType == expected)
        }
    }

    @Test
    func unqualifiedInnerClassTypeStillResolvesWithoutGenericOuter() throws {
        try withTemporaryFile(contents: """
        class Outer {
            private var cached: KeySet? = null
            fun f() {
                cached = KeySet()
                val s: KeySet = KeySet()
            }
            fun g(): KeySet = KeySet()
            inner class KeySet
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func inheritedInnerClassTypeLiftsOuterArgumentsFromReceiver() throws {
        // `KeySet` inside `Sub : CIM<Int>` spells `CIM<Int>.KeySet`, matching
        // the constructor result lifted through `Sub`'s inherited instance.
        try withTemporaryFile(contents: """
        open class CIM<Value> {
            inner class KeySet
        }
        class Sub : CIM<Int>() {
            fun f() {
                val s: KeySet = KeySet()
            }
            fun g(): KeySet = KeySet()
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let sub = try #require(sema.symbols.lookup(fqName: ["Sub"].map(ctx.interner.intern)))
            let cim = try #require(sema.symbols.lookup(fqName: ["CIM"].map(ctx.interner.intern)))
            let keySet = try #require(sema.symbols.lookup(fqName: ["CIM", "KeySet"].map(ctx.interner.intern)))
            let liftedArgs = sema.symbols.supertypeTypeArgs(for: sub, supertype: cim)
            let expected = sema.types.make(.classType(sema.types.classType(for: keySet, arguments: liftedArgs)))
            let gSymbol = try #require(sema.symbols.lookup(fqName: ["Sub", "g"].map(ctx.interner.intern)))
            let g = try #require(sema.symbols.functionSignature(for: gSymbol))
            #expect(g.returnType == expected)
        }
    }
}
