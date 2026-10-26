/// Owns all mutable inference state for one body worker. Construction happens
/// at a module barrier; source data and parent file scopes stay frozen until
/// join. The driver, delegates and their inferred/deferred ledgers never cross
/// that boundary. A snapshot is not permission to infer another declaration:
/// its dependency ledger still belongs to the authoritative module driver.
final class SemaBodyWorker: @unchecked Sendable {
    let driver: TypeCheckDriver

    init(parent: TypeCheckDriver, copyingBindings: Bool = false) {
        let diagnostics = parent.diagnostics.makeSemaWorkerDiagnostics()
        let interner = parent.interner.makeSemaWorkerInterner()
        let types = parent.sema.types.makeSemaWorkerTypes()
        let symbols = parent.sema.symbols.makeSemaWorkerSymbols()
        types.symbolTable = symbols
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: copyingBindings ? parent.sema.bindings.makeSemaWorkerBindings() : BindingTable(),
            diagnostics: diagnostics, interner: interner,
            nameBasedDestructuringMode: parent.sema.nameBasedDestructuringMode,
            bundledIndex: parent.sema.bundledIndex
        )
        sema.wellKnownSymbols = parent.sema.wellKnownSymbols
        sema.implicitSignedToUnsignedIntegerConversionEnabled =
            parent.sema.implicitSignedToUnsignedIntegerConversionEnabled
        sema.enumIntrinsicAliasNamesByFile = parent.sema.enumIntrinsicAliasNamesByFile
        let cache = parent.semaCacheContext == nil ? nil : SemaCacheContext()
        let resolver = OverloadResolver()
        resolver.cacheContext = cache
        driver = TypeCheckDriver(
            ast: parent.ast.makeSemaWorkerAST(), sema: sema,
            compilationContext: parent.compilationContext, sourceManager: parent.sourceManager,
            solver: ConstraintSolver(), resolver: resolver, dataFlow: DataFlowAnalyzer(),
            interner: interner, diagnostics: diagnostics, semaCacheContext: cache,
            useNewInference: parent.useNewInference,
            useUnrestrictedBuilderInference: parent.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: parent.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: parent.globalOptInMarkerNames
        )
    }

    func inferenceContext(file: ASTFile, scope: FileScope) -> TypeInferenceContext {
        let invisibleAccessFiles: Set<Int32> = file.annotations.contains { annotation in
            KnownCompilerAnnotation.suppress.matches(annotation.name) && annotation.arguments.contains {
                let code = $0.filter { $0 != "\"" && $0 != "'" }
                return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
            }
        } ? [file.fileID.rawValue] : []
        return TypeInferenceContext(
            ast: driver.ast, sema: driver.sema, resolver: driver.resolver,
            dataFlow: driver.dataFlow, interner: driver.interner, scope: scope,
            implicitReceiverType: nil, loopDepth: 0, loopLabelStack: [],
            lambdaLabelStack: [], exportBlockLocalsForExpr: nil, flowState: DataFlowState(),
            currentFileID: file.fileID, currentDeclSymbol: nil, enclosingClassSymbol: nil,
            visibilityChecker: VisibilityChecker(
                symbols: driver.sema.symbols, sourceManager: driver.sourceManager,
                invisibleAccessFiles: invisibleAccessFiles
            ),
            outerReceiverTypes: [], semaCacheContext: driver.semaCacheContext,
            useNewInference: driver.useNewInference,
            useUnrestrictedBuilderInference: driver.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: driver.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: driver.globalOptInMarkerNames
        )
    }
}
