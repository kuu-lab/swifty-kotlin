#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JvmJavaClassSyntheticSurfaceTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected JVM class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testJavaClassRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = [interner.intern("kotlin")]
        let javaLangPackage = ["java", "lang"].map { interner.intern($0) }
        let javaClassSymbol = try #require(
            sema.symbols.lookup(fqName: javaLangPackage + [interner.intern("Class")])
        )
        let javaClassTypeParameters = sema.types.nominalTypeParameterSymbols(for: javaClassSymbol)
        let javaClassTypeParameter = try #require(javaClassTypeParameters.first)

        #expect(javaClassTypeParameters.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: javaClassSymbol) == [.invariant])

        let propertySymbol = try #require(
            sema.symbols.lookupAll(fqName: kotlinPackage + [interner.intern("javaClass")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.T.javaClass root extension property"
        )
        let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try #require(sema.symbols.functionSignature(for: getterSymbol))
        let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))

        guard case let .typeParam(receiverTypeParam) = sema.types.kind(
            of: try #require(sema.symbols.extensionPropertyReceiverType(for: propertySymbol))
        ) else {
            Issue.record("Expected javaClass receiver to be generic T"); return
        }
        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            Issue.record("Expected javaClass return type to be java.lang.Class<T>"); return
        }
        guard case let .invariant(classArgType) = classType.args.first else {
            Issue.record("Expected javaClass return type argument to be invariant"); return
        }
        guard case let .typeParam(classArgTypeParam) = sema.types.kind(of: classArgType) else {
            Issue.record("Expected javaClass return type argument to be generic T"); return
        }

        #expect(classType.classSymbol == javaClassSymbol)
        #expect(try javaClassTypeParameter == #require(javaClassTypeParameters.first))
        #expect(receiverTypeParam.symbol == classArgTypeParam.symbol)
        #expect(getterSignature.receiverType == sema.symbols.extensionPropertyReceiverType(for: propertySymbol))
        #expect(getterSignature.returnType == propertyType)
        #expect(getterSignature.typeParameterSymbols == [receiverTypeParam.symbol])
        #expect(sema.symbols.externalLinkName(for: propertySymbol) == "kk_any_javaClass")
        #expect(sema.symbols.externalLinkName(for: getterSymbol) == "kk_any_javaClass")
    }

    @Test
    func testJavaClassPropertyResolvesInSource() throws {
        let source = """
        import java.lang.Class

        fun sample(value: String): Class<String> {
            return value.javaClass
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
    }
}
#endif
