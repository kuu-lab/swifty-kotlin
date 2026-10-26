@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReflectFindAnnotationTests {
    @Test func publicContractAndImportedCalls() throws {
        let ctx = makeContextFromSources([
            """
            package explicit
            import kotlin.reflect.KClass
            import kotlin.reflect.full.findAnnotation
            annotation class Tag(val value: String)
            class Host
            fun literal(): Tag? = Host::class.findAnnotation<Tag>()
            fun variable(k: KClass<*>): Tag? = k.findAnnotation<Tag>()
            fun inferred(k: KClass<*>): Tag? = k.findAnnotation()
            fun element(e: kotlin.reflect.KAnnotatedElement): Tag? = e.findAnnotation<Tag>()
            """,
            """
            package aliased
            import kotlin.reflect.full.findAnnotation as lookup
            annotation class Tag
            class Host
            fun literal(): Tag? = Host::class.lookup<Tag>()
            fun element(e: kotlin.reflect.KAnnotatedElement): Tag? = e.lookup<Tag>()
            """,
            """
            package wildcard
            import kotlin.reflect.full.*
            annotation class Tag
            class Host
            fun literal(): Tag? = Host::class.findAnnotation<Tag>()
            """,
        ], allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "reflect", "full", "findAnnotation"].map(ctx.interner.intern)
        let chosen = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(chosen))
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        #expect(symbol.visibility == .public)
        #expect(sema.symbols.isSourceBackedSymbol(chosen))
        #expect(symbol.flags.contains(.inlineFunction))
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.typeParameterSymbols.count == 1)
        let receiver = try #require(signature.receiverType)
        guard case let .classType(receiverClass) = sema.types.kind(of: receiver),
              case let .typeParam(resultParameter) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Expected a KAnnotatedElement receiver and nullable type-parameter result")
            return
        }
        let receiverName = sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve)
        #expect(receiverName == ["kotlin", "reflect", "KAnnotatedElement"])
        #expect(resultParameter.symbol == signature.typeParameterSymbols.first)
        #expect(resultParameter.nullability == .nullable)
        let bounds = signature.typeParameterUpperBoundsList.flatMap { $0 }
        #expect(bounds.count == 1)
        let annotation = try #require(sema.symbols.lookup(fqName: ["kotlin", "Annotation"].map(ctx.interner.intern)))
        if case let .classType(bound) = sema.types.kind(of: try #require(bounds.first)) {
            #expect(bound.classSymbol == annotation)
            #expect(bound.nullability == .nonNull)
        } else { Issue.record("Expected the Annotation upper bound") }
        let bindings = sema.bindings.callBindings.filter { $0.value.chosenCallee == chosen }
        #expect(bindings.count == 7)
        for (expr, binding) in bindings {
            let searchType = sema.bindings.findAnnotationSearchType(for: expr)
            #expect(searchType == binding.substitutedTypeArguments.first)
            let resultType = try #require(sema.bindings.exprType(for: expr))
            #expect(sema.types.nullability(of: resultType) == .nullable)
            if case let .classType(result) = sema.types.kind(of: resultType) {
                let name = sema.symbols.symbol(result.classSymbol)?.name
                #expect(name == ctx.interner.intern("Tag"))
            } else { Issue.record("Expected a nullable Tag result") }
        }
    }

    @Test func invalidCallsAreRejected() throws {
        let sources = [
            "class Host; fun wrong() = Host::class.findAnnotation<Annotation>()",
            "import kotlin.reflect.full.findAnnotation as lookup\nclass Host; fun wrong() = Host::class.findAnnotation<Annotation>()",
            "import kotlin.reflect.full.findAnnotation\nclass Host; fun wrong() = Host::class.findAnnotation<Int>()",
            "import kotlin.reflect.full.findAnnotation\nclass Host; fun wrong() = Host::class.findAnnotation<Annotation>(1)",
            "import kotlin.reflect.full.findAnnotation\nfun wrong() = 1.findAnnotation<Annotation>()",
            "import kotlin.reflect.full.missingAnnotation\nfun main() {}",
            "class Host; fun wrong() = kotlin.reflect.full.findAnnotation<Annotation>(Host::class)",
        ]
        let ctx = makeContextFromSources(sources.enumerated().map { index, source in
            "package rejected\(index)\n" + source
        }, allowDefaultStdlibLibrary: false)
        do { try runSema(ctx) } catch { }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let files = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }
        #expect(files.count == sources.count)
        for (index, file) in files.enumerated() {
            #expect(errors.contains { $0.primaryRange?.start.file == file },
                    "Expected a user-source diagnostic for: \(sources[index]); got \(errors)")
        }
    }

    @Test func userExtensionKeepsItsBody() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T> KClass<*>.findAnnotation(): Int = 7
        class Host
        fun main() { println(Host::class.findAnnotation<String>()) }
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let body = try findKIRFunctionBody(named: "main", in: #require(ctx.kir), interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("findAnnotation"))
        #expect(!callees.contains("__kk_kclass_find_annotation_typed"))
    }
}
