@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

struct CrossFileInferredExtensionReturnTests {
    @Test(arguments: [false, true])
    func unselectedCallableReferenceOverloadDoesNotCreateACycle(broadOverloadFirst: Bool) throws {
        let broad = "fun text(value: Any) = first()"
        let specific = "fun text(value: String): String = value"
        let (sema, interner) = try SemaFixture(surface: "unselected callable reference overload").make(source: """
        fun first() = consume(::text)
        \(broadOverloadFirst ? broad : specific)
        \(broadOverloadFirst ? specific : broad)
        fun consume(action: (String) -> String): String = action("abc")
        """)
        let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern("first")]))
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType)
    }

    @Test(arguments: [false, true], [false, true])
    func pendingMemberPropertiesDoNotFreezeTheExtensionReturn(
        declarationFirst: Bool,
        readLength: Bool
    ) throws {
        let use = "fun main() { println(1.measure()) }"
        let declaration = """
        fun text() = "abc"
        class Holder { val word = text() }
        fun Int.measure() = Holder().word\(readLength ? ".length" : "")
        """
        let (sema, interner) = try SemaFixture(surface: "pending member property dependency").make(
            sources: sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        )
        let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern("measure")]))
        let expectedReturnType = readLength ? sema.types.intType : sema.types.stringType
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == expectedReturnType)
    }

    @Test(arguments: [false, true], [0, 1])
    func getterAndDelegatedPropertyDependenciesUseTheirDeclarationContext(
        declarationFirst: Bool,
        form: Int
    ) throws {
        let use = "fun main() { println(1.measure()) }"
        let declaration = """
        fun text() = "abc"
        \(form == 0 ? "val word get() = text()" : "val word by lazy { text() }")
        fun Int.measure() = word.length
        """
        _ = try SemaFixture(surface: "getter and delegate extension dependencies").make(
            sources: sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        )
    }

    @Test
    func inferredReturnPreservesGenericUpperBoundMetadata() throws {
        let (sema, interner) = try SemaFixture(surface: "inferred extension signature metadata").make(source: """
        fun read() = "abc".measure()
        fun <T: CharSequence> T.measure() = length
        """)
        let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern("measure")]))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.returnType == sema.types.intType)
        #expect(signature.typeParameterUpperBoundsList.count == 1)
        #expect(signature.typeParameterUpperBoundsList.first?.isEmpty == false)
    }

    @Test(arguments: [false, true])
    func overloadedCallableReferenceUsesItsParameterShape(declarationFirst: Bool) throws {
        let use = "fun main() { println(1.measure()) }"
        let declaration = """
        fun text() = 1
        fun text(value: String) = value
        fun consume(action: (String) -> String) = action("abc").length
        fun Int.measure() = consume(::text)
        """
        _ = try SemaFixture(surface: "inferred overloaded callable reference dependency").make(
            sources: sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        )
    }

    @Test
    func speculativeMemberCheckingRetainsDependencyWarnings() throws {
        let ctx = makeContextFromSource("""
        class Caller { fun call() = wrapped() }
        @Deprecated("old") fun old(): Int = 1
        fun wrapped() = old()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("old")
        })
    }

    @Test
    func unselectedOverloadDoesNotCreateADependencyCycle() throws {
        _ = try SemaFixture(surface: "unselected inferred overload dependency").make(source: """
        fun Int.start() = this.foo(1)
        fun Int.foo(value: Int) = 1
        fun Int.foo(value: Any) = this.start()
        """)
    }

    @Test(arguments: [false, true])
    func speculativeMemberCheckingRetainsInvalidDependencyErrors(throughProperty: Bool) throws {
        let source = throughProperty ? """
        class Caller { fun call() = 1.use() }
        val word = missing()
        fun Int.use() = word
        """ : """
        class Caller { fun call() = broken() }
        fun broken() = missing()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.message.contains("missing") })
    }

    @Test
    func callableReferenceDependencyRetainsItsInferredReturn() throws {
        _ = try SemaFixture(surface: "inferred callable reference dependency").make(sources: [
            "fun main() { println(1.measure()) }",
            """
            fun text() = "abc"
            val producer = ::text
            fun Int.measure() = producer().length
            """,
        ])
    }

    @Test
    func rolledBackDependencyErrorCanBeEmittedAgain() {
        let diagnostics = DiagnosticEngine()
        let checkpoint = diagnostics.checkpoint()
        diagnostics.error("KSWIFTK-SEMA-0022", "Unresolved reference 'missing'.", range: nil)
        diagnostics.rollback(to: checkpoint)
        #expect(!diagnostics.hasError)
        diagnostics.error("KSWIFTK-SEMA-0022", "Unresolved reference 'missing'.", range: nil)
        #expect(diagnostics.hasError)
        #expect(diagnostics.count == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func extensionDependenciesResolveFunctionsAndProperties(
        declarationFirst: Bool,
        throughProperty: Bool
    ) throws {
        let use = "fun main() { println(1.measure()) }"
        let declaration = """
        fun text() = "abc"
        \(throughProperty ? "val word = text()" : "")
        fun Int.measure() = \(throughProperty ? "word" : "text()").length
        """
        let (sema, interner) = try SemaFixture(surface: "inferred extension declaration dependencies").make(
            sources: sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        )
        let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern("measure")]))
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.intType)
    }

    @Test
    func sameNamedOverloadDoesNotFormAnInferenceCycle() throws {
        _ = try SemaFixture(surface: "inferred extension overload dependencies").make(source: """
        fun keep() = listOf(1).filter { it.checked() }
        fun Int.checked() = this.checked(1)
        fun Int.checked(value: Int) = value > 0
        """)
    }

    @Test
    func moreSpecificOverloadDoesNotFormAnInferenceCycle() throws {
        _ = try SemaFixture(surface: "more specific inferred extension overload").make(source: """
        fun keep() = listOf(1).filter { it.checked("value") }
        fun Int.checked(value: Any) = this.checked(1)
        fun Int.checked(value: Int) = true
        """)
    }

    @Test
    func explicitReturnBreaksARecursiveInferenceDependency() throws {
        _ = try SemaFixture(surface: "explicit extension return breaks recursion").make(source: """
        fun Int.first() = this.second()
        fun Int.second(): Boolean = this == 0 || (this - 1).first()
        """)
    }

    @Test(arguments: [false, true])
    func genericNullableReturnKeepsItsTypeParameter(declarationFirst: Bool) throws {
        let use = """
        package sample
        fun read(value: String?): String? = value.identity()
        """
        let declaration = """
        package sample
        fun <T> T.identity() = this
        """
        let (sema, interner) = try SemaFixture(surface: "forward generic nullable extension return").make(
            sources: sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        )
        let symbol = try #require(sema.symbols.lookup(fqName: ["sample", "identity"].map(interner.intern)))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.returnType == signature.receiverType)
    }

    @Test(arguments: [false, true])
    func dependenciesUseTheDeclarationFileScope(declarationFirst: Bool) throws {
        let use = """
        package consumer
        import sample.isSafe
        fun keep() = listOf(1).filter { it.isSafe() }
        fun helper(): String = "caller scope"
        """
        let declaration = """
        package sample
        fun Int.isSafe() = this.checked()
        fun Int.checked() = helper(this)
        fun helper(value: Int): Boolean = value > 0
        """
        let sources = sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        let (sema, interner) = try SemaFixture(surface: "forward extension dependencies").make(sources: sources)
        for name in ["isSafe", "checked"] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["sample", name].map(interner.intern)))
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType)
        }
    }

    @Test(arguments: [false, true])
    func nonBooleanPredicateStillFails(declarationFirst: Bool) throws {
        let use = """
        package sample
        fun keep() = listOf(1).filter { it.isSafe() }
        """
        let declaration = """
        package sample
        fun Int.isSafe() = 1
        """
        let ctx = makeContextFromSources(sources(declaration: declaration, use: use, declarationFirst: declarationFirst))
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(fqName: ["sample", "isSafe"].map(ctx.interner.intern)))
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.intType)
    }

    @Test(arguments: [false, true])
    func inferredRecursiveExtensionsRequireAReturnType(mutual: Bool) throws {
        let source = """
        fun Int.first() = \(mutual ? "this.second()" : "this.first()")
        \(mutual ? "fun Int.second() = this.first()" : "")
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" })
    }

    @Test(arguments: [false, true], [false, true])
    func arrayPredicateResolvesBeforeOrAfterItsDeclaration(
        declarationFirst: Bool,
        explicitReturn: Bool
    ) throws {
        let use = """
        package sample
        fun main(){val grid=arrayOf("...".toCharArray());println(listOf(Point(0,0)).filter {grid.isSafe(it)})}
        """
        let declaration = """
        package sample
        data class Point(val x:Int,val y:Int)
        fun Array<CharArray>.isSafe(at:Point)\(explicitReturn ? ": Boolean" : "") = at.y in this.indices && at.x in this[at.y].indices
        """
        let sources = sources(declaration: declaration, use: use, declarationFirst: declarationFirst)
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["sample", "isSafe"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType)
        let ast = try #require(ctx.ast)
        // The arena also retains discarded parse alternatives. Check the call
        // that Sema actually visited, then require its source callee binding.
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, name, _, _, _)? = ast.arena.expr(id),
                  ctx.interner.resolve(name) == "isSafe",
                  sema.bindings.exprType(for: id) != nil
            else { return nil }
            return id
        }
        #expect(calls.count == 1)
        for call in calls {
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == symbol)
            #expect(sema.bindings.exprType(for: call) == sema.types.booleanType)
        }
    }

    private func sources(declaration: String, use: String, declarationFirst: Bool) -> [String] {
        declarationFirst ? [declaration, use] : [use, declaration]
    }
}
