
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
        sema.importedInlineFunctions = loadImports(ctx: ctx, symbols: symbols, types: types)

        // Build the bundled declaration index from AST before synthetic registration,
        // but keep bundled SymbolTable header collection after synthetic type foundations.
        let bundledIndex = BundledDeclarationIndex.build(
            ast: ast,
            symbols: symbols,
            types: types,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )
        registerSyntheticDelegateStubs(
            symbols: symbols,
            types: types,
            interner: ctx.interner,
            bundledIndex: bundledIndex
        )
        // Keep overlap diagnostics as an explicit guard test helper. Emitting
        // them during normal Sema pollutes user diagnostics for unaffected code.
        collectAllHeaders(
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

    private func loadImports(
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

    func diagnoseSyntheticBundledDeclarationOverlaps(
        bundledIndex: BundledDeclarationIndex,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        var seen: Set<SyntheticBundledDeclarationKey> = []
        var overlaps: [SyntheticBundledDeclarationKey] = []
        for symbol in symbols.allSymbols() {
            guard symbol.flags.contains(.synthetic),
                  let key = syntheticBundledDeclarationKey(for: symbol, symbols: symbols, types: types),
                  bundledIndex.contains(ownerFQName: key.ownerFQName, name: key.name, arity: key.arity),
                  seen.insert(key).inserted
            else {
                continue
            }
            overlaps.append(key)
        }

        for key in overlaps.sorted(by: { formatKey($0, interner: interner) < formatKey($1, interner: interner) }) {
            diagnostics.warning(
                "KSWIFTK-SEMA-0006",
                "Synthetic stdlib stub overlaps bundled Kotlin declaration: \(formatKey(key, interner: interner)).",
                range: nil
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
                    scope: fileScope, sourceManager: ctx.sourceManager,
                    diagnostics: ctx.diagnostics, interner: ctx.interner
                )
            }
        }
    }

    private func syntheticBundledDeclarationKey(
        for symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SyntheticBundledDeclarationKey? {
        switch symbol.kind {
        case .function:
            guard let signature = symbols.functionSignature(for: symbol.id) else {
                return nil
            }
            let ownerFQName = declarationOwnerFQName(
                receiverType: signature.receiverType,
                symbolID: symbol.id,
                symbols: symbols,
                types: types
            )
            guard let ownerFQName else {
                return nil
            }
            return SyntheticBundledDeclarationKey(
                ownerFQName: ownerFQName,
                name: symbol.name,
                arity: signature.parameterTypes.count
            )

        case .property:
            let ownerFQName = declarationOwnerFQName(
                receiverType: symbols.extensionPropertyReceiverType(for: symbol.id),
                symbolID: symbol.id,
                symbols: symbols,
                types: types
            )
            guard let ownerFQName else {
                return nil
            }
            return SyntheticBundledDeclarationKey(ownerFQName: ownerFQName, name: symbol.name, arity: 0)

        default:
            return nil
        }
    }

    private func declarationOwnerFQName(
        receiverType: TypeID?,
        symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [InternedString]? {
        if let receiverType,
           let receiverOwner = nominalOwnerFQName(for: receiverType, symbols: symbols, types: types)
        {
            return receiverOwner
        }
        guard let parentID = symbols.parentSymbol(for: symbolID),
              let parentSymbol = symbols.symbol(parentID)
        else {
            return nil
        }
        return parentSymbol.fqName
    }

    private func nominalOwnerFQName(
        for typeID: TypeID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [InternedString]? {
        switch types.kind(of: types.makeNonNullable(typeID)) {
        case let .classType(nominalType):
            guard let symbol = symbols.symbol(nominalType.classSymbol) else {
                return nil
            }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                return symbol.fqName
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func formatKey(_ key: SyntheticBundledDeclarationKey, interner: StringInterner) -> String {
        let owner = key.ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
        return "\(owner).\(interner.resolve(key.name))(arity=\(key.arity))"
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

private struct SyntheticBundledDeclarationKey: Hashable {
    let ownerFQName: [InternedString]
    let name: InternedString
    let arity: Int
}
