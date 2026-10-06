
/// Semantic analysis pass that performs type checking and type inference.
///
/// This phase is a thin wrapper around ``TypeCheckDriver``, which dispatches
/// type-checking work to independent delegate classes (`ExprTypeChecker`,
/// `CallTypeChecker`, `ControlFlowTypeChecker`, etc.). Each delegate holds only
/// the context it needs, replacing the previous extension-based splitting
/// where a single monolithic class shared all state across multiple files.
final class TypeCheckSemaPhase: CompilerPhase {
    static let name = "TypeCheckSema"

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Semantic model is unavailable.")
        }

        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("AST is unavailable during type check.")
        }

        let semaCacheEnabled = ctx.options.frontendFlags.contains("sema-cache")
        let semaCacheContext: SemaCacheContext? = semaCacheEnabled ? SemaCacheContext() : nil

        let solver = ConstraintSolver()
        let resolver = OverloadResolver()
        if let semaCacheContext {
            resolver.cacheContext = semaCacheContext
        }
        let dataFlow = DataFlowAnalyzer()
        let semaCtx = SemaModule(
            symbols: sema.symbols,
            types: sema.types,
            bindings: sema.bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )

        let lazyBoundDecls = collectLazyBoundObjectLiteralDecls(ast: ast)

        // Run consistency checks for active declarations only, so incremental
        // frontends can drop stale declarations from the previous compile.
        let activeDeclIDs = ast.activeDeclarationIDs
        for declID in activeDeclIDs {
            if lazyBoundDecls.contains(declID) {
                continue
            }
            if sema.bindings.declSymbols[declID] == nil {
                ctx.diagnostics.error(
                    "KSWIFTK-TYPE-0003",
                    "Unbound declaration found during type checking.",
                    range: nil
                )
            }
        }

        let driver = TypeCheckDriver(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            sourceManager: ctx.sourceManager,
            solver: solver,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: ctx.interner,
            diagnostics: ctx.diagnostics,
            semaCacheContext: semaCacheContext,
            useNewInference: ctx.options.useNewInference,
            useUnrestrictedBuilderInference: ctx.options.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: ctx.options.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: ctx.options.optInMarkerNames
        )

        let fileScopes = driver.scopeBuilder.buildFileScopes(
            ast: ast,
            sema: sema,
            interner: ctx.interner,
            sourceManager: ctx.sourceManager
        )

        // Expression type inference recurses with large per-frame contexts
        // (`TypeInferenceContext` is threaded by value through every call).
        // Swift Testing executes tests as tasks on the Swift Concurrency
        // cooperative pool, whose threads have 512 KiB stacks, so type-checking
        // even moderately nested call/lambda chains there can overflow and
        // crash with SIGBUS (signal 10). Run it on a big-stack thread so
        // recursion headroom is independent of the calling thread, matching
        // `BuildKIRPhase`'s handling of the same class of issue in lowering.
        let work = TypeCheckWork(driver: driver, fileScopes: fileScopes, files: ast.files)
        try LargeStackExecutor.run {
            work.run()
        }

        let inlineLambdaArguments = collectInlineLambdaArguments(ast: ast, sema: sema)
        validateReturnLambdaPaths(ast: ast, sema: sema, diagnostics: ctx.diagnostics, inlineLambdaArguments: inlineLambdaArguments)
        driver.validateSuspensionContexts(inlineLambdaArguments: inlineLambdaArguments)

        for declID in lazyBoundDecls where activeDeclIDs.contains(declID) && sema.bindings.declSymbols[declID] == nil {
            let declRange: SourceRange? = if let decl = ast.arena.decl(declID) {
                switch decl {
                case let .classDecl(classDecl):
                    classDecl.range
                case let .interfaceDecl(interfaceDecl):
                    interfaceDecl.range
                case let .funDecl(funDecl):
                    funDecl.range
                case let .propertyDecl(propertyDecl):
                    propertyDecl.range
                case let .typeAliasDecl(typeAliasDecl):
                    typeAliasDecl.range
                case let .objectDecl(objectDecl):
                    objectDecl.range
                case let .enumEntryDecl(enumEntryDecl):
                    enumEntryDecl.range
                }
            } else {
                nil
            }
            ctx.diagnostics.error(
                "KSWIFTK-TYPE-0003",
                "Unbound declaration found during type checking.",
                range: declRange
            )
        }

        // KUU-1211: escape-analyze `Comparable<Char>` locals now that body
        // type checking has populated bindings; KIR lowering reads the result
        // to dispatch their `compareTo` receivers through `kk_char_compareTo`
        // like kotlinc's unboxed `Intrinsics.compare` on a primitive `char`.
        sema.bindings.setNonEscapingComparableCharLocals(
            ComparableCharEscapeAnalyzer(
                ast: ast,
                symbols: sema.symbols,
                types: sema.types,
                bindings: sema.bindings,
                interner: ctx.interner
            ).analyze()
        )
    }

    private func collectInlineLambdaArguments(ast: ASTModule, sema: SemaModule) -> Set<ExprID> {
        var inlineLambdaArguments: Set<ExprID> = []
        func recordInlineLambdaArguments(_ arguments: [ExprID], binding: CallBinding) {
            guard sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true,
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
            else { return }
            for (index, argument) in arguments.enumerated() {
                let parameterIndex = binding.parameterMapping[index] ?? index
                guard case .lambdaLiteral = ast.arena.expr(argument),
                      signature.parameterTypes.indices.contains(parameterIndex),
                      case .functionType = sema.types.kind(of: sema.types.makeNonNullable(signature.parameterTypes[parameterIndex]))
                else { continue }
                if !signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex)
                    || signature.valueParameterAllowsNonLocalReturn[parameterIndex]
                {
                    inlineLambdaArguments.insert(argument)
                }
            }
        }
        for (callExprID, binding) in sema.bindings.callBindings {
            let arguments: [ExprID]
            switch ast.arena.expr(callExprID) {
            case let .call(_, _, args, _), let .memberCall(_, _, _, args, _),
                 let .safeMemberCall(_, _, _, args, _):
                arguments = args.map(\.expr)
            case let .binary(_, _, rhs, _), let .compoundAssign(_, _, rhs, _),
                 let .memberCompoundAssign(_, _, _, rhs, _):
                arguments = [rhs]
            case let .inExpr(lhs, _, _), let .notInExpr(lhs, _, _):
                arguments = [lhs]
            case let .indexedAccess(_, indices, _), let .indexedCompoundAssign(_, _, indices, _, _):
                arguments = indices
            case let .indexedAssign(_, indices, value, _):
                arguments = indices + [value]
            default:
                continue
            }
            recordInlineLambdaArguments(arguments, binding: binding)
        }
        // Indexed compound assignments bind get() on the expression itself
        // and keep the element's plusAssign()/plus() call separately.
        for (exprID, binding) in sema.bindings.indexedCompoundAssignElementOperatorBindings {
            guard case let .indexedCompoundAssign(_, _, _, value, _) = ast.arena.expr(exprID) else { continue }
            recordInlineLambdaArguments([value], binding: binding.call)
        }
        return inlineLambdaArguments
    }

    private func validateReturnLambdaPaths(
        ast: ASTModule, sema: SemaModule, diagnostics: DiagnosticEngine, inlineLambdaArguments: Set<ExprID>
    ) {
        let returnPaths = sema.bindings.functionReturnLambdaPaths.merging(
            sema.bindings.lambdaReturnLambdaPaths, uniquingKeysWith: { _, lambdaPath in lambdaPath }
        )
        for returnExprID in returnPaths.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let lambdaPath = returnPaths[returnExprID],
                  !lambdaPath.allSatisfy({ inlineLambdaArguments.contains($0) })
            else { continue }
            let destination = sema.bindings.lambdaReturnTargets[returnExprID] == nil ? "function" : "lambda"
            diagnostics.error(
                "KSWIFTK-SEMA-0042",
                "A return to an enclosing \(destination) cannot cross a non-inline, crossinline, or noinline lambda boundary.",
                range: ast.arena.exprRange(returnExprID)
            )
        }
    }

    private func collectLazyBoundObjectLiteralDecls(ast: ASTModule) -> Set<DeclID> {
        var declsToSkip: Set<DeclID> = []
        for expr in ast.arena.exprs {
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID
            else {
                continue
            }
            collectObjectLiteralDeclTree(declID, ast: ast, into: &declsToSkip)
        }
        return declsToSkip
    }

    private func collectObjectLiteralDeclTree(
        _ declID: DeclID,
        ast: ASTModule,
        into declsToSkip: inout Set<DeclID>
    ) {
        guard declsToSkip.insert(declID).inserted,
              let decl = ast.arena.decl(declID)
        else {
            return
        }
        guard case let .objectDecl(objectDecl) = decl else {
            return
        }
        for childDeclID in objectDecl.memberFunctions
            + objectDecl.memberProperties
            + objectDecl.nestedClasses
            + objectDecl.nestedObjects
        {
            collectObjectLiteralDeclTree(childDeclID, ast: ast, into: &declsToSkip)
        }
    }
}

/// Holds the non-`Sendable` type-checking inputs and exposes a `@Sendable`
/// callable surface so the large-stack thread can run `typeCheckModule`
/// without capturing non-`Sendable` values through `withoutActuallyEscaping`
/// closures.
private final class TypeCheckWork: @unchecked Sendable {
    let driver: TypeCheckDriver
    let fileScopes: [Int32: FileScope]
    let files: [ASTFile]

    init(driver: TypeCheckDriver, fileScopes: [Int32: FileScope], files: [ASTFile]) {
        self.driver = driver
        self.fileScopes = fileScopes
        self.files = files
    }

    func run() {
        driver.typeCheckModule(fileScopes: fileScopes, files: files)
        ConstPropertyEvaluator(ast: driver.ast, sema: driver.sema, interner: driver.interner)
            .evaluate(diagnostics: driver.diagnostics)
    }
}
