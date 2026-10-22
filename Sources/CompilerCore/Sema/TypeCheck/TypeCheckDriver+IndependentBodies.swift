/// A closed worker result. Worker TypeIDs are remapped at join; no new symbol
/// or synthetic name may escape without an explicit canonical mapping.
struct IndependentBodyResult: @unchecked Sendable {
    let declaration: DeclID
    let expressionTypes: [ExprID: TypeID]
    let identifierSymbols: [ExprID: SymbolID]
    let sourceDeclaredExpectedTypeExpressions: Set<ExprID>
    let diagnostics: [Diagnostic]
    let newTypes: [TypeKind]
    let initialTypeCount: Int
    let localSymbols: [SemaWorkerLocalSymbol]
    let newStrings: [String]
    let initialStringCount: Int
}

private struct IndependentFileInput {
    let file: ASTFile
    let scope: FileScope
    let declarations: [(DeclID, FunDecl, SymbolID, [ExprID])]
}

/// The parent and file/import scopes are frozen throughout the executor's
/// dispatch/join barrier. Create a mutable snapshot inside each task, so only
/// jobs snapshots can be alive, rather than retaining one for every file.
private final class IndependentBodyInputs: @unchecked Sendable {
    let parent: TypeCheckDriver
    let files: [IndependentFileInput]

    init(parent: TypeCheckDriver, files: [IndependentFileInput]) {
        self.parent = parent
        self.files = files
    }

    func run(_ index: Int) -> [IndependentBodyResult] {
        let input = files[index]
        return IndependentFileWork(
            parent: parent, file: input.file, fileScope: input.scope, declarations: input.declarations
        ).run()
    }
}

/// Each work item is owned by one worker until the indexed join. AST and source
/// data are frozen, and SymbolTable has no lazy loader or concurrent writer.
private final class IndependentFileWork: @unchecked Sendable {
    let worker: SemaBodyWorker
    var driver: TypeCheckDriver { worker.driver }
    let file: ASTFile
    let declarations: [(DeclID, FunDecl, SymbolID, [ExprID])]
    let initialTypeCount: Int
    let fileScope: FileScope

    init(parent: TypeCheckDriver, file: ASTFile, fileScope: FileScope, declarations: [(DeclID, FunDecl, SymbolID, [ExprID])]) {
        self.file = file
        self.fileScope = fileScope
        self.declarations = declarations
        let worker = SemaBodyWorker(parent: parent)
        self.worker = worker
        let driver = worker.driver
        initialTypeCount = driver.sema.types.internedTypeCount
    }

    func run() -> [IndependentBodyResult] {
        // Parent scopes and symbols are frozen until the join. Keep the real
        // import chain: even scalar operators can resolve source extensions.
        // Only newly created function scopes are mutable and worker-owned.
        let context = worker.inferenceContext(file: file, scope: fileScope)
        var results: [IndependentBodyResult] = []
        for (declaration, function, symbol, expressions) in declarations {
            let initialSymbolCount = driver.sema.symbols.symbolCount
            let initialStringCount = driver.interner.internedStringCount
            let parameterSymbols = Set(driver.sema.symbols.functionSignature(for: symbol)?.valueParameterSymbols ?? [])
            let expectedLocals = expressions.filter {
                if case .localDecl = driver.ast.arena.expr($0) { return true }
                return false
            }.count
            let checkpoint = driver.diagnostics.checkpoint()
            driver.declChecker.typeCheckFunctionDecl(
                function, symbol: symbol, ctx: context.with(currentDeclSymbol: symbol),
                solver: driver.solver, diagnostics: driver.diagnostics
            )
            let localSymbols = driver.sema.symbols.workerLocalSymbols(since: initialSymbolCount)
            let ownedSymbols = parameterSymbols.union(localSymbols?.map { $0.symbol.id } ?? [])
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
            let sourceDeclaredExpectedTypeExpressions =
                driver.sema.bindings.sourceDeclaredExpectedTypeExprIDs.intersection(Set(expressions))
            // Only ordinary scalar local allocations are admitted. Lambda
            // synthetic parameters, objects, captures and pending metadata need
            // their own delta contracts; they remain on the module driver.
            guard let localSymbols,
                  localSymbols.count == expectedLocals,
                  localSymbols.allSatisfy({ driver.isIndependentScalarType($0.type) }),
                  identifierSymbols.values.allSatisfy(ownedSymbols.contains),
                  driver.sema.bindings.hasOnlyIndependentScalarBindings(
                    allowingSourceDeclaredExpectedTypeExprIDs: Set(expressions)
                  ),
                  driver.diagnostics.diagnostics.isEmpty
            else { return [] }
            results.append(IndependentBodyResult(
                declaration: declaration, expressionTypes: expressionTypes,
                identifierSymbols: identifierSymbols,
                sourceDeclaredExpectedTypeExpressions: sourceDeclaredExpectedTypeExpressions,
                diagnostics: Array(driver.diagnostics.diagnostics.dropFirst(checkpoint)),
                newTypes: driver.sema.types.workerTypeKinds(since: initialTypeCount),
                initialTypeCount: initialTypeCount,
                localSymbols: localSymbols,
                newStrings: driver.interner.workerStrings(since: initialStringCount),
                initialStringCount: initialStringCount
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
        let work = files.compactMap { file -> IndependentFileInput? in
            guard let fileScope = fileScopes[file.fileID.rawValue] else { return nil }
            let declarations = file.topLevelDecls.compactMap { declaration -> (DeclID, FunDecl, SymbolID, [ExprID])? in
                guard !sema.unreachableTopLevelFunctionDecls.contains(declaration),
                      case let .funDecl(function)? = ast.arena.decl(declaration),
                      let symbol = sema.bindings.declSymbols[declaration],
                      let expressions = independentScalarExpressions(function, symbol: symbol)
                else { return nil }
                return (declaration, function, symbol, expressions)
            }
            return declarations.isEmpty ? nil : IndependentFileInput(file: file, scope: fileScope, declarations: declarations)
        }
        guard work.count > 1 else { return [:] }
        let inputs = IndependentBodyInputs(parent: self, files: work)
        let results = try SemaPerFileExecutor.collect(count: work.count, jobs: frontendJobs) { index in
            inputs.run(index)
        }
        return Dictionary(uniqueKeysWithValues: results.flatMap { $0 }.map { ($0.declaration, $0) })
    }

    /// Explicit type alone is insufficient. Admit a closed expression grammar
    /// with scalar parameters and ordinary locals, no call/contract/closure.
    /// The checker remains authoritative for lexical visibility and flow.
    /// Operator lookup uses frozen scopes; any resulting call forces a retry.
    func independentScalarExpressions(_ function: FunDecl, symbol: SymbolID) -> [ExprID]? {
        guard function.returnType != nil, function.receiverType == nil,
              function.contextReceivers.isEmpty, function.typeParams.isEmpty,
              !function.isInline, !function.isSuspend, function.annotations.isEmpty,
              let signature = sema.symbols.functionSignature(for: symbol),
              signature.typeParameterSymbols.isEmpty, signature.contextReceiverTypes.isEmpty,
              signature.receiverType == nil, isIndependentScalarType(signature.returnType),
              signature.parameterTypes.allSatisfy(isIndependentScalarType),
              !signature.valueParameterIsVararg.contains(true),
              !signature.valueParameterHasDefaultValues.contains(true),
              signature.valueParameterSymbols.count == function.valueParams.count
        else { return nil }
        var names = Set(function.valueParams.map(\.name))
        var referencedNames: Set<InternedString> = []
        var pending: [ExprID]
        switch function.body {
        case let .expr(root, _): pending = [root]
        case let .block(statements, _): pending = statements
        case .unit: return nil
        }
        var visited: Set<ExprID> = []
        while let expr = pending.popLast() {
            guard visited.insert(expr).inserted else { continue }
            switch ast.arena.expr(expr) {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral,
                 .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral:
                break
            case let .nameRef(name, _):
                referencedNames.insert(name)
            case let .localDecl(name, _, _, initializer, delegated, lateinit, _):
                // The worker result is admitted only after resolved local
                // symbols and every binding side table pass the scalar-delta
                // checks below. That lets explicit annotations participate
                // without trusting an unresolved TypeRef here.
                guard !delegated, !lateinit, let initializer else { return nil }
                names.insert(name)
                pending.append(initializer)
            case let .localAssign(name, value, _):
                referencedNames.insert(name)
                pending.append(value)
            case let .returnExpr(value, label, _):
                guard label == nil, let value else { return nil }
                pending.append(value)
            case let .blockExpr(statements, trailing, _):
                pending += statements
                if let trailing { pending.append(trailing) }
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
        guard referencedNames.isSubset(of: names) else { return nil }
        return Array(visited)
    }

    func isIndependentScalarType(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive(_, .nonNull), .stringStruct(.nonNull): true
        default: false
        }
    }
}
