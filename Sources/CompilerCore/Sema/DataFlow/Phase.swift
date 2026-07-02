
final class DataFlowSemaPhase: CompilerPhase {
    static let name = "DataFlowSema"

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }

        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let bindings = BindingTable()
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: bindings, diagnostics: ctx.diagnostics
        )

        let fileScopes = buildFileScopes(ast: ast, symbols: symbols, interner: ctx.interner)

        sema.importedInlineFunctions = loadImportedLibrarySymbols(
            ctx: ctx, symbols: symbols, types: types
        )
        registerSyntheticPreBundledStubs(
            symbols: symbols, types: types, interner: ctx.interner
        )

        collectBundledHeaders(
            ast: ast, fileScopes: fileScopes,
            symbols: symbols, types: types, bindings: bindings, ctx: ctx
        )
        let bundledIndex = BundledDeclarationIndex.build(
            symbols: symbols,
            types: types,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )
        registerSyntheticPostBundledStubs(
            symbols: symbols,
            types: types,
            interner: ctx.interner,
            bundledIndex: bundledIndex
        )
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )

        collectUserHeaders(
            ast: ast, fileScopes: fileScopes,
            symbols: symbols, types: types, bindings: bindings, ctx: ctx
        )
        assignCompilationModuleFQNames(
            symbols: symbols,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
        runValidationPasses(ast: ast, symbols: symbols, bindings: bindings, types: types, ctx: ctx)
        runBodyAnalysis(ast: ast, symbols: symbols, types: types, bindings: bindings, ctx: ctx)

        ctx.storeSema(sema)
    }

    func buildFileScopes(
        ast: ASTModule, symbols: SymbolTable, interner: StringInterner
    ) -> [Int32: FileScope] {
        let rootScope = PackageScope(parent: nil, symbols: symbols)
        var fileScopes: [Int32: FileScope] = [:]
        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }
        return fileScopes
    }

    private func loadImportedLibrarySymbols(
        ctx: CompilationContext, symbols: SymbolTable, types: TypeSystem
    ) -> [SymbolID: KIRFunction] {
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]
        loadImportedLibrarySymbols(
            options: ctx.options, symbols: symbols, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )
        return importedInlineFunctions
    }

    private func registerSyntheticPreBundledStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        BundledSyntheticStubRegistration.bundledIndex = .empty
        BundledSyntheticStubRegistration.types = types
        BundledSyntheticStubRegistration.skippedCount = 0
        BundledSyntheticStubRegistration.postBundledPass = false
        BundledSyntheticStubRegistration.preBundledPass = true
        defer {
            BundledSyntheticStubRegistration.preBundledPass = false
            BundledSyntheticStubRegistration.types = nil
        }
        registerSyntheticDelegateStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticPostBundledStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex
    ) {
        BundledSyntheticStubRegistration.bundledIndex = bundledIndex
        BundledSyntheticStubRegistration.types = types
        BundledSyntheticStubRegistration.skippedCount = 0
        BundledSyntheticStubRegistration.preBundledPass = false
        BundledSyntheticStubRegistration.postBundledPass = true
        defer {
            BundledSyntheticStubRegistration.postBundledPass = false
            BundledSyntheticStubRegistration.types = nil
        }
        registerSyntheticDelegateStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            bundledIndex: bundledIndex
        )
    }

    private func isBundledFile(_ file: ASTFile, sourceManager: SourceManager) -> Bool {
        sourceManager.path(of: file.fileID).hasPrefix("__bundled_")
    }

    func collectBundledHeaders(
        ast: ASTModule, fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext
    ) {
        for file in ast.sortedFiles where isBundledFile(file, sourceManager: ctx.sourceManager) {
            collectHeadersForFile(
                file: file, ast: ast, fileScopes: fileScopes,
                symbols: symbols, types: types, bindings: bindings, ctx: ctx
            )
        }
    }

    func collectUserHeaders(
        ast: ASTModule, fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext
    ) {
        for file in ast.sortedFiles where !isBundledFile(file, sourceManager: ctx.sourceManager) {
            collectHeadersForFile(
                file: file, ast: ast, fileScopes: fileScopes,
                symbols: symbols, types: types, bindings: bindings, ctx: ctx
            )
        }
    }

    private func collectHeadersForFile(
        file: ASTFile,
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext
    ) {
        guard let fileScope = fileScopes[file.fileID.rawValue] else { return }
        registerFileAnnotations(
            file: file,
            symbols: symbols,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        for declID in file.topLevelDecls {
            collectHeader(
                declID: declID, file: file, ast: ast,
                symbols: symbols, types: types, bindings: bindings,
                scope: fileScope, diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
    }

    func collectAllHeaders(
        ast: ASTModule, fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext
    ) {
        for file in ast.sortedFiles {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            registerFileAnnotations(
                file: file,
                symbols: symbols,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner
            )
            for declID in file.topLevelDecls {
                collectHeader(
                    declID: declID, file: file, ast: ast,
                    symbols: symbols, types: types, bindings: bindings,
                    scope: fileScope, diagnostics: ctx.diagnostics, interner: ctx.interner
                )
            }
        }
    }

    private func runValidationPasses(
        ast: ASTModule, symbols: SymbolTable, bindings: BindingTable,
        types: TypeSystem, ctx: CompilationContext
    ) {
        bindInheritanceEdges(ast: ast, symbols: symbols, bindings: bindings, types: types, interner: ctx.interner)
        validateSealedHierarchy(
            ast: ast, symbols: symbols, bindings: bindings,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateClassDelegation(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateAbstractOverrides(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateAbstractClassConstraints(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateDiamondOverrides(
            ast: ast, symbols: symbols, bindings: bindings,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateOpenFinalOverride(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner,
            compilationModuleName: ctx.options.moduleName
        )
        validateExpectActualMatching(
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        validateAnnotationTargets(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        validateExperimentalTypeInferenceOptIn(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics
        )
        validateExperimentalVersionOverloadingOptIn(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            options: ctx.options
        )
        validateConstructorDelegation(ast: ast, symbols: symbols, diagnostics: ctx.diagnostics)
        validateDeclarationSiteVariance(
            ast: ast, symbols: symbols, bindings: bindings,
            types: types, diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        synthesizeClassDelegationForwardingMethodSymbols(
            ast: ast, symbols: symbols, bindings: bindings,
            types: types, interner: ctx.interner
        )
        synthesizeNominalLayouts(symbols: symbols)
        attachCompilerMetadataAnnotations(
            symbols: symbols,
            types: types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
    }

    private func runBodyAnalysis(
        ast: ASTModule, symbols: SymbolTable, types: TypeSystem,
        bindings: BindingTable, ctx: CompilationContext
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID, ast: ast, symbols: symbols, types: types,
                    bindings: bindings, diagnostics: ctx.diagnostics, interner: ctx.interner
                )
            }
        }
    }
}
