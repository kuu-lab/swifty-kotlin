
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

        if ctx.options.frontendFlags.contains("reachability-sema"), ctx.options.emit == .executable {
            sema.unreachableTopLevelFunctionDecls = withSemaSubPhaseTiming("reachability", ctx: ctx) {
                TopLevelFunctionReachability.unreachableFunctionDecls(
                    ast: ast, sourceManager: ctx.sourceManager, interner: ctx.interner
                )
            }
        }

        let solver = ConstraintSolver()
        let resolver = OverloadResolver()
        if let semaCacheContext {
            resolver.cacheContext = semaCacheContext
        }
        let dataFlow = DataFlowAnalyzer()
        let lazyBoundDecls = withSemaSubPhaseTiming("lazy-bound-decls", ctx: ctx) {
            collectLazyBoundObjectLiteralDecls(ast: ast)
        }

        // Run consistency checks for active declarations only, so incremental
        // frontends can drop stale declarations from the previous compile.
        let activeDeclIDs = ast.activeDeclarationIDs
        withSemaSubPhaseTiming("unbound-decl-check", ctx: ctx) {
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
        }

        let driver = withSemaSubPhaseTiming("driver-init", ctx: ctx) {
            TypeCheckDriver(
            ast: ast,
            sema: sema,
            compilationContext: ctx,
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
        }

        let fileScopes = withSemaSubPhaseTiming("build-file-scopes", ctx: ctx) {
            driver.scopeBuilder.buildFileScopes(
                ast: ast,
                sema: sema,
                interner: ctx.interner,
                sourceManager: ctx.sourceManager
            )
        }

        // Expression type inference recurses with large per-frame contexts
        // (`TypeInferenceContext` is threaded by value through every call).
        // Swift Testing executes tests as tasks on the Swift Concurrency
        // cooperative pool, whose threads have 512 KiB stacks, so type-checking
        // even moderately nested call/lambda chains there can overflow and
        // crash with SIGBUS (signal 10). Run it on a big-stack thread so
        // recursion headroom is independent of the calling thread, matching
        // `BuildKIRPhase`'s handling of the same class of issue in lowering.
        let work = TypeCheckWork(driver: driver, fileScopes: fileScopes, files: ast.files, frontendJobs: ctx.options.frontendFlags.contains("sema-parallel") ? ctx.frontendJobs : 1)
        try withSemaSubPhaseTiming("type-check", ctx: ctx) {
            try LargeStackExecutor.run {
                try work.run()
            }
        }

        try withSemaSubPhaseTiming("post-validation", ctx: ctx) {
            let (inlineLambdaArguments, suspendLambdaArguments) = collectInlineLambdaArguments(ast: ast, sema: sema)
            validateTailrecFunctions(
                ast: ast,
                sema: sema,
                diagnostics: ctx.diagnostics,
                inlineLambdaArguments: inlineLambdaArguments
            )
            validateWorkerExecuteJobs(ast: ast, sema: sema, ctx: ctx)

            validateLoopJumpLambdaPaths(ast: ast, sema: sema, diagnostics: ctx.diagnostics, inlineLambdaArguments: inlineLambdaArguments)
            validateReturnLambdaPaths(ast: ast, sema: sema, diagnostics: ctx.diagnostics, inlineLambdaArguments: inlineLambdaArguments)
            validateOperatorConventions(ast: ast, interner: ctx.interner, diagnostics: ctx.diagnostics)
            driver.validateSuspensionContexts(
                inlineLambdaArguments: inlineLambdaArguments,
                suspendLambdaArguments: suspendLambdaArguments
            )
        }

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
        // This post-pass recursively walks the same deep expressions as the
        // body checker; it must not return to a thin cooperative-pool stack.
        let escapeWork = ComparableCharEscapeWork(ast: ast, sema: sema, interner: ctx.interner)
        let nonEscapingLocals = try withSemaSubPhaseTiming("comparable-char-escape", ctx: ctx) {
            try LargeStackExecutor.run { escapeWork.run() }
        }
        sema.bindings.setNonEscapingComparableCharLocals(nonEscapingLocals)
    }

    /// Collects the lambda arguments whose bodies execute in the caller's own
    /// control-flow and suspension context:
    ///
    /// - `inlineLambdaArguments`: lambdas passed to `inline` callees on
    ///   parameters that are neither `noinline` nor `crossinline`. These keep
    ///   the caller's non-local-return and suspension contexts.
    /// - `suspendLambdaArguments`: lambdas bound to a parameter whose declared
    ///   type is a `suspend` function type or a SAM type with a suspend method.
    ///   Such lambdas supply their own suspension context regardless of whether
    ///   the callee is `inline`, which is required because the lambda's recorded
    ///   `exprTypes` entry is not always rewritten to the suspend variant after
    ///   overload resolution picks the bound signature (e.g. `Flow.filter`'s
    ///   `predicate: suspend (T) -> Boolean`).
    private func collectInlineLambdaArguments(
        ast: ASTModule,
        sema: SemaModule
    ) -> (inlineLambdaArguments: Set<ExprID>, suspendLambdaArguments: Set<ExprID>) {
        var inlineLambdaArguments: Set<ExprID> = []
        var suspendLambdaArguments: Set<ExprID> = []
        let samHelpers = TypeCheckHelpers()
        func recordLambdaArguments(_ arguments: [ExprID], binding: CallBinding) {
            guard let signature = sema.symbols.functionSignature(for: binding.chosenCallee) else { return }
            let calleeIsInline = sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true
            for (index, argument) in arguments.enumerated() {
                let parameterIndex = binding.parameterMapping[index] ?? index
                guard case .lambdaLiteral = ast.arena.expr(argument),
                      signature.parameterTypes.indices.contains(parameterIndex)
                else { continue }

                let parameterType = sema.types.makeNonNullable(signature.parameterTypes[parameterIndex])
                let parameterFunction: FunctionType?
                if case let .functionType(function) = sema.types.kind(of: parameterType) {
                    parameterFunction = function
                } else {
                    parameterFunction = samHelpers.samFunctionType(for: parameterType, sema: sema)
                }
                if parameterFunction?.isSuspend == true {
                    suspendLambdaArguments.insert(argument)
                }
                if calleeIsInline,
                   !signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex)
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
            recordLambdaArguments(arguments, binding: binding)
        }
        // Indexed compound assignments bind get() on the expression itself
        // and keep the element's plusAssign()/plus() call separately.
        for (exprID, binding) in sema.bindings.indexedCompoundAssignElementOperatorBindings {
            guard case let .indexedCompoundAssign(_, _, _, value, _) = ast.arena.expr(exprID) else { continue }
            recordLambdaArguments([value], binding: binding.call)
        }
        // Intrinsic Array(size, init) calls have no selected function binding,
        // but their initializer is inlined just like the bundled factory body.
        for (callExprID, kind) in sema.bindings.stdlibSpecialCallKinds where kind == .arrayConstructor {
            guard case let .call(_, _, args, _) = ast.arena.expr(callExprID),
                  args.count == 2,
                  case .lambdaLiteral = ast.arena.expr(args[1].expr)
            else {
                continue
            }
            inlineLambdaArguments.insert(args[1].expr)
        }
        return (inlineLambdaArguments, suspendLambdaArguments)
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

    /// Non-local loop jumps are legal only when every lambda boundary between
    /// the jump and its loop target belongs to an inline parameter that allows
    /// non-local control flow. The selected call binding is available only
    /// after body inference, so the initial checker records these candidate
    /// paths and this pass reports rejected ones here.
    private func validateLoopJumpLambdaPaths(
        ast: ASTModule, sema: SemaModule, diagnostics: DiagnosticEngine, inlineLambdaArguments: Set<ExprID>
    ) {
        for exprID in sema.bindings.loopJumpLambdaPaths.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let lambdaPath = sema.bindings.loopJumpLambdaPaths[exprID],
                  !lambdaPath.allSatisfy({ inlineLambdaArguments.contains($0) })
            else { continue }
            let code: String
            let message: String
            switch ast.arena.expr(exprID) {
            case .breakExpr:
                code = "KSWIFTK-SEMA-0018"
                message = "'break' is only allowed inside loop bodies."
            case .continueExpr:
                code = "KSWIFTK-SEMA-0019"
                message = "'continue' is only allowed inside loop bodies."
            default:
                continue
            }
            diagnostics.error(code, message, range: ast.arena.exprRange(exprID))
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
    let frontendJobs: Int

    init(driver: TypeCheckDriver, fileScopes: [Int32: FileScope], files: [ASTFile], frontendJobs: Int) {
        self.driver = driver
        self.fileScopes = fileScopes
        self.files = files
        self.frontendJobs = frontendJobs
    }

    func run() throws {
        try driver.typeCheckModule(fileScopes: fileScopes, files: files, frontendJobs: frontendJobs)
        ValPropertyInitializationChecker(
            ast: driver.ast, sema: driver.sema, interner: driver.interner,
            sourceManager: driver.sourceManager
        ).check()
        ConstPropertyEvaluator(ast: driver.ast, sema: driver.sema, interner: driver.interner)
            .evaluate(diagnostics: driver.diagnostics)
        driver.declChecker.validatePendingAnnotationConstants()
        driver.validateJsFileNameAnnotationArguments(in: files)
        DataFlowSemaPhase().validateDeferredAnnotationTargets(
            ast: driver.ast, symbols: driver.sema.symbols, types: driver.sema.types,
            bindings: driver.sema.bindings, diagnostics: driver.diagnostics, interner: driver.interner,
            sourceManager: driver.sourceManager
        )
    }
}


// Inputs are handed to one joined large-stack thread after all body workers
// finish. The caller owns the resulting binding-table update.
private final class ComparableCharEscapeWork: @unchecked Sendable {
    let ast: ASTModule
    let sema: SemaModule
    let interner: StringInterner

    init(ast: ASTModule, sema: SemaModule, interner: StringInterner) {
        self.ast = ast
        self.sema = sema
        self.interner = interner
    }

    func run() -> Set<SymbolID> {
        ComparableCharEscapeAnalyzer(
            ast: ast, symbols: sema.symbols, types: sema.types,
            bindings: sema.bindings, interner: interner
        ).analyze()
    }
}
