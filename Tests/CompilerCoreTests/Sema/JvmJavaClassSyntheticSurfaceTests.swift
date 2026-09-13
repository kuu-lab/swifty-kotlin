#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JvmJavaClassSourceSurfaceTests {
    private static let fixture = SemaFixture(surface: "JVM class")

    private func sharedSema(
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared(sourceLocation: sourceLocation)
    }

    private func makeSema(
        source: String = "fun noop() {}",
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source, sourceLocation: sourceLocation)
    }

    @Test
    func testJavaClassRootExtensionIsSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let kotlinPackage = [interner.intern("kotlin")]
        let javaLangPackage = ["java", "lang"].map { interner.intern($0) }
        let javaClassSymbol = try #require(
            sema.symbols.lookup(fqName: javaLangPackage + [interner.intern("Class")])
        )
        #expect(sema.symbols.isSourceBackedSymbol(javaClassSymbol))
        let javaClassTypeParameters = sema.types.nominalTypeParameterSymbols(for: javaClassSymbol)
        let javaClassTypeParameter = try #require(javaClassTypeParameters.first)

        #expect(javaClassTypeParameters.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: javaClassSymbol) == [.invariant])

        let functionSymbol = try #require(
            sema.symbols.lookupAll(fqName: kotlinPackage + [interner.intern("javaClass")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .function
                    && sema.symbols.isSourceBackedSymbol(symbolID)
                    && sema.symbols.functionSignature(for: symbolID)?.receiverType != nil
            },
            "Expected source-backed kotlin.T.javaClass extension"
        )
        let functionSignature = try #require(sema.symbols.functionSignature(for: functionSymbol))
        #expect(functionSignature.parameterTypes.isEmpty)
        #expect(sema.symbols.externalLinkName(for: functionSymbol) == nil)

        guard case let .typeParam(receiverTypeParam) = sema.types.kind(
            of: try #require(functionSignature.receiverType)
        ) else {
            Issue.record("Expected javaClass receiver to be generic T"); return
        }
        guard case let .classType(classType) = sema.types.kind(of: functionSignature.returnType) else {
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
        #expect(functionSignature.typeParameterSymbols == [receiverTypeParam.symbol])
    }

    @Test
    func testJavaClassPropertyStyleAccessResolvesInSource() throws {
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

    @Test
    func testJavaSystemAndRuntimeSurfacesAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let javaLang = [interner.intern("java"), interner.intern("lang")]

        let expected: [(String, [String], String)] = [
            ("System", ["gc"], "__kk_system_gc"),
            ("Runtime", ["getRuntime", "totalMemory", "freeMemory", "maxMemory"], "__kk_runtime_"),
        ]
        for (typeName, memberNames, bridgePrefix) in expected {
            let typeFQName = javaLang + [interner.intern(typeName)]
            let typeSymbol = try #require(
                sema.symbols.lookup(fqName: typeFQName),
                "java.lang.\(typeName) should be declared"
            )
            #expect(sema.symbols.isSourceBackedSymbol(typeSymbol))

            for memberName in memberNames {
                let memberFQName = typeFQName + [interner.intern(memberName)]
                let memberSymbol = try #require(
                    sema.symbols.lookupAll(fqName: memberFQName).first,
                    "java.lang.\(typeName).\(memberName) should be declared"
                )
                #expect(sema.symbols.isSourceBackedSymbol(memberSymbol))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)
            }

            let links = Set(sema.symbols.allSymbols().compactMap {
                sema.symbols.externalLinkName(for: $0.id)
            })
            for memberName in memberNames {
                let bridge = typeName == "System"
                    ? bridgePrefix
                    : bridgePrefix + memberName
                #expect(links.contains(bridge), "Expected source bridge \(bridge)")
            }
        }
    }
}
#endif
