#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpectActualLazyMetadataTests {
    @Test
    func noExpectDeclarationsLeaveImportedShellsUnloaded() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        _ = defineUnrelatedShells(symbols: symbols, interner: interner)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }
        let diagnostics = DiagnosticEngine()

        validate(symbols: symbols, types: TypeSystem(), interner: interner, diagnostics: diagnostics)

        #expect(loaded.isEmpty)
        #expect(!diagnostics.hasError)
    }

    @Test
    func optionalExpectationLoadsOnlyItsOwnMetadata() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        _ = defineUnrelatedShells(symbols: symbols, interner: interner)
        let name = interner.intern("OptionalTag")
        let expectSymbol = symbols.define(
            kind: .annotationClass, name: name, fqName: [name],
            declSite: nil, visibility: .public, flags: [.importedLibrary, .expectDeclaration]
        )
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { symbol in
            loaded.append(symbol)
            if symbol == expectSymbol {
                symbols.setAnnotations([
                    MetadataAnnotationRecord(annotationFQName: "kotlin.OptionalExpectation"),
                ], for: symbol)
            }
        }
        let diagnostics = DiagnosticEngine()

        validate(symbols: symbols, types: TypeSystem(), interner: interner, diagnostics: diagnostics)

        #expect(loaded == [expectSymbol])
        #expect(!diagnostics.hasError)
    }

    @Test(arguments: [false, true], [false, true])
    func importedExpectFunctionLoadsOnlyItsOwnMetadata(hasActual: Bool, commonModuleMode: Bool) {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        _ = defineUnrelatedShells(symbols: symbols, interner: interner)
        let name = interner.intern("platformValue")
        let expectSymbol = symbols.define(
            kind: .function, name: name, fqName: [name],
            declSite: nil, visibility: .public, flags: [.importedLibrary, .expectDeclaration]
        )
        let actualSymbol: SymbolID? = hasActual ? symbols.define(
            kind: .function, name: name, fqName: [name],
            declSite: nil, visibility: .public, flags: [.actualDeclaration]
        ) : nil
        let signature = FunctionSignature(parameterTypes: [], returnType: types.intType)
        if let actualSymbol {
            symbols.setFunctionSignature(signature, for: actualSymbol)
        }
        var loaded: [SymbolID] = []
        let alreadyLoaded: Set<SymbolID> = actualSymbol.map { [$0] } ?? []
        symbols.setLazyImportedMetadataLoader(alreadyLoaded: alreadyLoaded) { symbol in
            loaded.append(symbol)
            if symbol == expectSymbol {
                symbols.setFunctionSignature(signature, for: symbol)
            }
        }
        let diagnostics = DiagnosticEngine()

        validate(
            symbols: symbols, types: types, interner: interner, diagnostics: diagnostics,
            commonModuleMode: commonModuleMode
        )

        #expect(loaded == [expectSymbol])
        #expect(symbols.actualSymbol(for: expectSymbol) == actualSymbol)
        let expectedCodes = hasActual || commonModuleMode ? [] : ["KSWIFTK-MPP-UNRESOLVED"]
        #expect(diagnostics.diagnostics.map(\.code) == expectedCodes)
    }

    @Test
    func abstractClassMatchingPreservesInheritanceWithoutLoadingUnrelatedShells() throws {
        let ctx = makeContextFromSources([
            "expect abstract class Contract { fun value(): Int }",
            "actual abstract class Contract { actual fun value(): Int }",
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let symbols = sema.symbols
        let method = try #require(symbols.lookupAll(fqName: ["Contract", "value"].map(ctx.interner.intern))
            .first { symbols.symbol($0)?.flags.contains(.actualDeclaration) == true })
        symbols.removeFlags(.abstractType, for: method)
        let alreadyLoaded = Set(symbols.allSymbols().map(\.id))
        let shells = defineUnrelatedShells(symbols: symbols, interner: ctx.interner)
        // A metadata-only function with the same FQ parent has no AST body.
        // It must not be queried even while source members are being checked.
        let importedName = ctx.interner.intern("importedOnly")
        _ = symbols.define(
            kind: .function, name: importedName,
            fqName: [ctx.interner.intern("Contract"), importedName],
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader(alreadyLoaded: alreadyLoaded) { loaded.append($0) }
        let diagnostics = DiagnosticEngine()

        DataFlowSemaPhase().validateExpectActualMatching(
            ast: ast, symbols: symbols, types: sema.types, diagnostics: diagnostics,
            interner: ctx.interner, commonModuleMode: false
        )

        #expect(loaded.isEmpty)
        #expect(!diagnostics.hasError, "\(diagnostics.diagnostics)")
        #expect(symbols.symbol(method)?.flags.contains(.abstractType) == true)
        // Ordinary semantic queries must still materialize a shell on demand.
        _ = symbols.functionSignature(for: shells[0])
        #expect(loaded == [shells[0]])
    }

    private func defineUnrelatedShells(symbols: SymbolTable, interner: StringInterner) -> [SymbolID] {
        (0..<128).map { index in
            let name = interner.intern("unused\(index)")
            return symbols.define(
                kind: .function, name: name, fqName: [interner.intern("unrelated"), name],
                declSite: nil, visibility: .public, flags: [.importedLibrary]
            )
        }
    }

    private func validate(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        commonModuleMode: Bool = false
    ) {
        DataFlowSemaPhase().validateExpectActualMatching(
            ast: ASTModule(files: [], arena: ASTArena(), declarationCount: 0, tokenCount: 0),
            symbols: symbols, types: types, diagnostics: diagnostics,
            interner: interner, commonModuleMode: commonModuleMode
        )
    }
}
#endif
