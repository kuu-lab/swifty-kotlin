/// A closed worker result. Worker TypeIDs are remapped at join; no new symbol
/// or synthetic name may escape.
struct IndependentBodyResult: @unchecked Sendable {
    let declaration: DeclID
    let expressionTypes: [ExprID: TypeID]
    let identifierSymbols: [ExprID: SymbolID]
    let diagnostics: [Diagnostic]
    let newTypes: [TypeKind]
    let initialTypeCount: Int
}

/// Each work item is owned by one worker until the indexed join. AST and source
/// data are frozen, and SymbolTable has no lazy loader or concurrent writer.
private final class IndependentFileWork: @unchecked Sendable {
    let driver: TypeCheckDriver
    let file: ASTFile
    let declarations: [(DeclID, FunDecl, SymbolID, [ExprID])]
    let initialTypeCount: Int
    let initialSymbolCount: Int
    let fileScope: FileScope

    init(parent: TypeCheckDriver, file: ASTFile, fileScope: FileScope, declarations: [(DeclID, FunDecl, SymbolID, [ExprID])]) {
        self.file = file
        self.fileScope = fileScope
        self.declarations = declarations
        let diagnostics = parent.diagnostics.makeSemaWorkerDiagnostics()
        let interner = parent.interner.makeSemaWorkerInterner()
        let types = parent.sema.types.makeSemaWorkerTypes()
        initialTypeCount = types.internedTypeCount
        let symbols = parent.sema.symbols.makeSemaWorkerSymbols()
        initialSymbolCount = symbols.allSymbols().count
        types.symbolTable = symbols
        let sema = SemaModule(
            symbols: symbols, types: types, bindings: BindingTable(),
            diagnostics: diagnostics, interner: interner, bundledIndex: parent.sema.bundledIndex
        )
        sema.wellKnownSymbols = parent.sema.wellKnownSymbols
        let cache = parent.semaCacheContext == nil ? nil : SemaCacheContext()
        let resolver = OverloadResolver()
        resolver.cacheContext = cache
        driver = TypeCheckDriver(
            ast: parent.ast.makeSemaWorkerAST(), sema: sema, sourceManager: parent.sourceManager,
            solver: ConstraintSolver(), resolver: resolver, dataFlow: DataFlowAnalyzer(),
            interner: interner, diagnostics: diagnostics, semaCacheContext: cache,
            useNewInference: parent.useNewInference,
            useUnrestrictedBuilderInference: parent.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: parent.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: parent.globalOptInMarkerNames
        )
    }

    func run() -> [IndependentBodyResult] {
        // Parent scopes and symbols are frozen until the join. Keep the real
        // import chain: even scalar operators can resolve source extensions.
        // Only newly created function scopes are mutable and worker-owned.
        let context = TypeInferenceContext(
            ast: driver.ast, sema: driver.sema, resolver: driver.resolver,
            dataFlow: driver.dataFlow, interner: driver.interner, scope: fileScope,
            implicitReceiverType: nil, loopDepth: 0, loopLabelStack: [],
            lambdaLabelStack: [], exportBlockLocalsForExpr: nil, flowState: DataFlowState(),
            currentFileID: file.fileID, currentDeclSymbol: nil, enclosingClassSymbol: nil,
            visibilityChecker: VisibilityChecker(symbols: driver.sema.symbols, sourceManager: driver.sourceManager),
            outerReceiverTypes: [], semaCacheContext: driver.semaCacheContext,
            useNewInference: driver.useNewInference,
            useUnrestrictedBuilderInference: driver.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: driver.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: driver.globalOptInMarkerNames
        )
        var results: [IndependentBodyResult] = []
        for (declaration, function, symbol, expressions) in declarations {
            let checkpoint = driver.diagnostics.checkpoint()
            driver.declChecker.typeCheckFunctionDecl(
                function, symbol: symbol, ctx: context.with(currentDeclSymbol: symbol),
                solver: driver.solver, diagnostics: driver.diagnostics
            )
            // New symbols, non-scalar bindings or diagnostics require the
            // authoritative module driver. Type allocations are canonicalized
            // in declaration order at join, including temporary lookup types.
            guard driver.sema.symbols.allSymbols().count == initialSymbolCount,
                  driver.sema.bindings.hasOnlyIndependentScalarBindings,
                  driver.diagnostics.diagnostics.isEmpty
            else { return [] }
            var expressionTypes: [ExprID: TypeID] = [:]
            var identifierSymbols: [ExprID: SymbolID] = [:]
            // Preparation already owns the body's expression IDs. Reuse them
            // instead of rescanning accumulated bindings through locked AST APIs.
            for expression in expressions {
                if let type = driver.sema.bindings.exprTypes[expression] {
                    expressionTypes[expression] = type
                }
                if let target = driver.sema.bindings.identifierSymbols[expression] {
                    identifierSymbols[expression] = target
                }
            }
            results.append(IndependentBodyResult(
                declaration: declaration, expressionTypes: expressionTypes,
                identifierSymbols: identifierSymbols,
                diagnostics: Array(driver.diagnostics.diagnostics.dropFirst(checkpoint)),
                newTypes: driver.sema.types.workerTypeKinds(since: initialTypeCount),
                initialTypeCount: initialTypeCount
            ))
        }
        return results
    }
}

extension TypeCheckDriver {
    func checkIndependentBodies(files: [ASTFile], fileScopes: [Int32: FileScope], frontendJobs: Int) throws -> [DeclID: IndependentBodyResult] {
        guard frontendJobs > 1, !sema.symbols.hasLazyImportedMetadataLoader else { return [:] }
        // The parent is the sole module writer until all workers have joined.
        // Inferred/deferred declaration ledgers stay on that parent; admissible
        // workers have no path to demand them.
        let work = files.compactMap { file -> IndependentFileWork? in
            guard let fileScope = fileScopes[file.fileID.rawValue] else { return nil }
            let declarations = file.topLevelDecls.compactMap { declaration -> (DeclID, FunDecl, SymbolID, [ExprID])? in
                guard case let .funDecl(function)? = ast.arena.decl(declaration),
                      let symbol = sema.bindings.declSymbols[declaration],
                      let expressions = independentScalarExpressions(function, symbol: symbol)
                else { return nil }
                return (declaration, function, symbol, expressions)
            }
            return declarations.isEmpty ? nil : IndependentFileWork(parent: self, file: file, fileScope: fileScope, declarations: declarations)
        }
        guard work.count > 1 else { return [:] }
        let results = try SemaPerFileExecutor.collect(count: work.count, jobs: frontendJobs) { index in
            work[index].run()
        }
        return Dictionary(uniqueKeysWithValues: results.flatMap { $0 }.map { ($0.declaration, $0) })
    }

    /// Explicit type alone is insufficient. Admit a closed expression grammar
    /// with scalar parameters only, no explicit call/contract/local declaration.
    /// Operator lookup uses frozen scopes; any resulting call forces a retry.
    func independentScalarExpressions(_ function: FunDecl, symbol: SymbolID) -> [ExprID]? {
        guard function.returnType != nil, function.receiverType == nil,
              function.contextReceivers.isEmpty, function.typeParams.isEmpty,
              !function.isInline, !function.isSuspend, function.annotations.isEmpty,
              case let .expr(root, _) = function.body,
              let signature = sema.symbols.functionSignature(for: symbol),
              signature.typeParameterSymbols.isEmpty, signature.contextReceiverTypes.isEmpty,
              signature.receiverType == nil, isScalar(signature.returnType),
              signature.parameterTypes.allSatisfy(isScalar),
              !signature.valueParameterIsVararg.contains(true),
              !signature.valueParameterHasDefaultValues.contains(true),
              signature.valueParameterSymbols.count == function.valueParams.count
        else { return nil }
        let parameters = Set(function.valueParams.map(\.name))
        var pending = [root]
        var visited: Set<ExprID> = []
        while let expr = pending.popLast() {
            guard visited.insert(expr).inserted else { continue }
            switch ast.arena.expr(expr) {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral,
                 .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral:
                break
            case let .nameRef(name, _) where parameters.contains(name):
                break
            case let .unaryExpr(_, operand, _):
                pending.append(operand)
            case let .binary(op, lhs, rhs, _):
                switch op {
                case .add, .subtract, .multiply, .divide, .modulo, .equal, .notEqual,
                     .identityEqual, .notIdentityEqual, .lessThan, .lessOrEqual,
                     .greaterThan, .greaterOrEqual, .logicalAnd, .logicalOr:
                    pending += [lhs, rhs]
                default: return nil
                }
            case let .ifExpr(condition, thenExpr, elseExpr, _):
                pending += [condition, thenExpr]
                if let elseExpr { pending.append(elseExpr) }
            default:
                return nil
            }
        }
        return Array(visited)
    }

    private func isScalar(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive(_, .nonNull), .stringStruct(.nonNull): true
        default: false
        }
    }
}
