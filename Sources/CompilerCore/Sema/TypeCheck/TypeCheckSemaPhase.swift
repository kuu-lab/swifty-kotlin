
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
        let work = TypeCheckWork(driver: driver, fileScopes: fileScopes, files: ast.files, frontendJobs: ctx.options.semaParallelEnabled ? ctx.frontendJobs : 1)
        do {
            if let attribution = ctx.phaseTimer.map({ _ in TypeCheckAttribution() }) {
                sema.types.attribution = attribution
                sema.symbols.attribution = attribution
                ctx.typeCheckAttribution = attribution
            }
            defer {
                sema.types.attribution = nil
                sema.symbols.attribution = nil
            }
            try withSemaSubPhaseTiming("type-check", ctx: ctx) {
                try LargeStackExecutor.run {
                    try work.run()
                }
            }
        }

        withSemaSubPhaseTiming("post-validation", ctx: ctx) {
            if !ctx.deferredExpectActualTypePairs.isEmpty {
                DataFlowSemaPhase().verifyDeferredExpectActualTypes(
                    ctx.deferredExpectActualTypePairs,
                    symbols: sema.symbols,
                    types: sema.types,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
                ctx.deferredExpectActualTypePairs = []
            }
            let (inlineLambdaArguments, inlineAnonymousFunctionArguments, suspendLambdaArguments) =
                collectInlineLambdaArguments(ast: ast, sema: sema)
            validateTailrecFunctions(
                ast: ast,
                sema: sema,
                diagnostics: ctx.diagnostics,
                inlineLambdaArguments: inlineLambdaArguments
            )
            validateWorkerExecuteJobs(ast: ast, sema: sema, ctx: ctx)

            validateLoopJumpLambdaPaths(
                ast: ast,
                sema: sema,
                diagnostics: ctx.diagnostics,
                inlineControlFlowArguments: inlineLambdaArguments.union(inlineAnonymousFunctionArguments)
            )
            validateReturnLambdaPaths(ast: ast, sema: sema, diagnostics: ctx.diagnostics, inlineLambdaArguments: inlineLambdaArguments)
            validateInlineParameterUsages(
                ast: ast,
                sema: sema,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                sourceManager: ctx.sourceManager,
                inlineLambdaArguments: inlineLambdaArguments,
                inlineAnonymousFunctionArguments: inlineAnonymousFunctionArguments
            )
            driver.validateSuspensionContexts(
                inlineLambdaArguments: inlineLambdaArguments,
                suspendLambdaArguments: suspendLambdaArguments
            )
            driver.validateComposableContexts(
                inlineLambdaArguments: inlineLambdaArguments,
                inlineAnonymousFunctionArguments: inlineAnonymousFunctionArguments
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

    private func collectInlineLambdaArguments(
        ast: ASTModule,
        sema: SemaModule
    ) -> (
        inlineLambdaArguments: Set<ExprID>,
        inlineAnonymousFunctionArguments: Set<ExprID>,
        suspendLambdaArguments: Set<ExprID>
    ) {
        var inlineLambdaArguments: Set<ExprID> = []
        var inlineAnonymousFunctionArguments: Set<ExprID> = []
        var suspendLambdaArguments: Set<ExprID> = []
        let samHelpers = TypeCheckHelpers()
        func recordLambdaArguments(
            _ arguments: [ExprID], binding: CallBinding, intrinsicInline: Bool = false
        ) {
            guard let signature = sema.symbols.functionSignature(for: binding.chosenCallee) else { return }
            let calleeIsInline = intrinsicInline
                || sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true
            for (index, argument) in arguments.enumerated() {
                let parameterIndex = binding.parameterMapping[index] ?? index
                guard signature.parameterTypes.indices.contains(parameterIndex) else { continue }
                let isLambdaArgument: Bool
                if case .lambdaLiteral = ast.arena.expr(argument) {
                    isLambdaArgument = true
                } else {
                    isLambdaArgument = false
                }
                let anonymousFunctionDeclaration: ExprID? = {
                    guard ast.arena.isAnonymousFunction(argument),
                          case let .blockExpr(statements, _, _) = ast.arena.expr(argument)
                    else {
                        return nil
                    }
                    return statements.first(where: ast.arena.isAnonymousFunction)
                }()
                guard isLambdaArgument || anonymousFunctionDeclaration != nil else { continue }

                let parameterType = sema.types.makeNonNullable(signature.parameterTypes[parameterIndex])
                let parameterFunction: FunctionType?
                if case let .functionType(function) = sema.types.kind(of: parameterType) {
                    parameterFunction = function
                } else {
                    parameterFunction = samHelpers.samFunctionType(for: parameterType, sema: sema)
                }
                if isLambdaArgument, parameterFunction?.isSuspend == true {
                    suspendLambdaArguments.insert(argument)
                }
                let allowsNonLocalControlFlow =
                    !signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex)
                        || signature.valueParameterAllowsNonLocalReturn[parameterIndex]
                if calleeIsInline, allowsNonLocalControlFlow {
                    if isLambdaArgument {
                        inlineLambdaArguments.insert(argument)
                    }
                    if let anonymousFunctionDeclaration {
                        inlineAnonymousFunctionArguments.insert(anonymousFunctionDeclaration)
                    }
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
            let intrinsicInline = sema.bindings.scopeFunctionKind(for: callExprID) == .scopeUsePinned
            recordLambdaArguments(arguments, binding: binding, intrinsicInline: intrinsicInline)
        }
        for (exprID, binding) in sema.bindings.indexedCompoundAssignElementOperatorBindings {
            guard case let .indexedCompoundAssign(_, _, _, value, _) = ast.arena.expr(exprID) else { continue }
            recordLambdaArguments([value], binding: binding.call)
        }
        for (callExprID, kind) in sema.bindings.stdlibSpecialCallKinds where kind == .arrayConstructor {
            guard case let .call(_, _, args, _) = ast.arena.expr(callExprID),
                  args.count == 2,
                  case .lambdaLiteral = ast.arena.expr(args[1].expr)
            else {
                continue
            }
            inlineLambdaArguments.insert(args[1].expr)
        }
        return (inlineLambdaArguments, inlineAnonymousFunctionArguments, suspendLambdaArguments)
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

    private func validateLoopJumpLambdaPaths(
        ast: ASTModule,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        inlineControlFlowArguments: Set<ExprID>
    ) {
        for exprID in sema.bindings.loopJumpLambdaPaths.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let lambdaPath = sema.bindings.loopJumpLambdaPaths[exprID],
                  !lambdaPath.allSatisfy({ inlineControlFlowArguments.contains($0) })
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

    private func validateInlineParameterUsages(
        ast: ASTModule,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        sourceManager: SourceManager,
        inlineLambdaArguments: Set<ExprID>,
        inlineAnonymousFunctionArguments: Set<ExprID>
    ) {
        var functionDeclBySymbol: [SymbolID: FunDecl] = [:]
        var inlineFunctions: [(decl: FunDecl, signature: FunctionSignature)] = []
        for declID in ast.activeDeclarationIDs {
            guard case let .funDecl(funDecl) = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            functionDeclBySymbol[symbol] = funDecl
            guard sourceManager.origin(of: funDecl.range.start.file)?.isBundledStdlib != true,
                  funDecl.isInline || funDecl.modifiers.contains(.inline),
                  let signature = sema.symbols.functionSignature(for: symbol)
            else {
                continue
            }
            inlineFunctions.append((funDecl, signature))
        }
        guard !inlineFunctions.isEmpty else { return }

        let walker = InlineParameterUsageWalker(
            ast: ast,
            sema: sema,
            diagnostics: diagnostics,
            interner: interner,
            invokeName: interner.intern("invoke"),
            inlineLambdaArguments: inlineLambdaArguments,
            inlineAnonymousFunctionArguments: inlineAnonymousFunctionArguments,
            functionDeclBySymbol: functionDeclBySymbol
        )
        for (funDecl, signature) in inlineFunctions {
            walker.check(funDecl: funDecl, signature: signature)
        }
    }
}

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
            sourceManager: driver.sourceManager,
            jvmTarget: driver.compilationContext.flatMap { $0.options.emit.isJVM ? $0.options.jvmTarget : nil }
        )
        DataFlowSemaPhase().validateInferredMemberVariance(
            ast: driver.ast, symbols: driver.sema.symbols,
            bindings: driver.sema.bindings, types: driver.sema.types,
            diagnostics: driver.diagnostics, interner: driver.interner
        )
        DataFlowSemaPhase().validateInferredOverrideReturnTypes(
            ast: driver.ast, symbols: driver.sema.symbols,
            bindings: driver.sema.bindings, types: driver.sema.types,
            diagnostics: driver.diagnostics, interner: driver.interner,
            compilationModuleName: driver.compilationContext?.options.moduleName ?? "TestModule"
        )
        DataFlowSemaPhase().validateInferredPropertyTypeOverrides(
            ast: driver.ast, symbols: driver.sema.symbols,
            bindings: driver.sema.bindings, types: driver.sema.types,
            diagnostics: driver.diagnostics, interner: driver.interner,
            compilationModuleName: driver.compilationContext?.options.moduleName ?? "TestModule"
        )
        DataFlowSemaPhase().validateBodyNestedDeclOverrides(
            ast: driver.ast, symbols: driver.sema.symbols,
            bindings: driver.sema.bindings, types: driver.sema.types,
            diagnostics: driver.diagnostics, interner: driver.interner,
            compilationModuleName: driver.compilationContext?.options.moduleName ?? "TestModule"
        )
        DataFlowSemaPhase().validateDeferredDiamondOverrides(
            ast: driver.ast, symbols: driver.sema.symbols,
            bindings: driver.sema.bindings,
            diagnostics: driver.diagnostics, interner: driver.interner
        )
    }
}


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

private final class InlineParameterUsageWalker {
    private enum UsageRole {
        case invocationCallee
        case invokeReceiver
        case callArgument(call: ExprID, argumentIndex: Int)
        case other
    }

    private let ast: ASTModule
    private let sema: SemaModule
    private let diagnostics: DiagnosticEngine
    private let interner: StringInterner
    private let knownNames: KnownCompilerNames
    private let invokeName: InternedString
    private let inlineLambdaArguments: Set<ExprID>
    private let inlineAnonymousFunctionArguments: Set<ExprID>
    private let functionDeclBySymbol: [SymbolID: FunDecl]

    private var parameterIsCrossinline: [SymbolID: Bool] = [:]
    private var parameterDisplay: [SymbolID: String] = [:]

    init(
        ast: ASTModule,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        invokeName: InternedString,
        inlineLambdaArguments: Set<ExprID>,
        inlineAnonymousFunctionArguments: Set<ExprID>,
        functionDeclBySymbol: [SymbolID: FunDecl]
    ) {
        self.ast = ast
        self.sema = sema
        self.diagnostics = diagnostics
        self.interner = interner
        self.knownNames = KnownCompilerNames(interner: interner)
        self.invokeName = invokeName
        self.inlineLambdaArguments = inlineLambdaArguments
        self.inlineAnonymousFunctionArguments = inlineAnonymousFunctionArguments
        self.functionDeclBySymbol = functionDeclBySymbol
    }

    func check(funDecl: FunDecl, signature: FunctionSignature) {
        parameterIsCrossinline = [:]
        parameterDisplay = [:]
        for index in funDecl.valueParams.indices {
            guard signature.parameterTypes.indices.contains(index),
                  signature.valueParameterSymbols.indices.contains(index)
            else {
                continue
            }
            let valueParam = funDecl.valueParams[index]
            guard !valueParam.isNoinline,
                  case let .functionType(functionType) = sema.types.kind(of: signature.parameterTypes[index]),
                  functionType.nullability != .nullable
            else {
                continue
            }
            let paramSymbol = signature.valueParameterSymbols[index]
            parameterIsCrossinline[paramSymbol] = valueParam.isCrossinline
            let modifierPrefix = valueParam.isCrossinline ? "crossinline " : ""
            let typeName = sema.types.displayName(
                of: signature.parameterTypes[index], symbols: sema.symbols, interner: interner
            )
            parameterDisplay[paramSymbol] = "'\(modifierPrefix)\(interner.resolve(valueParam.name)): \(typeName)'"
        }
        guard !parameterIsCrossinline.isEmpty else { return }
        for valueParam in funDecl.valueParams {
            if let defaultValue = valueParam.defaultValue {
                visitExpr(defaultValue, role: .other, materialized: false)
            }
        }
        walkFunctionBody(funDecl.body, materialized: false)
    }

    private func visitExpr(_ exprID: ExprID, role: UsageRole, materialized: Bool) {
        if let parameterSymbol = inlineParameterReference(exprID) {
            classify(parameterSymbol: parameterSymbol, usage: exprID, role: role, materialized: materialized)
        }
        walkExpr(exprID, materialized: materialized)
    }

    private func inlineParameterReference(_ exprID: ExprID) -> SymbolID? {
        guard let symbol = sema.bindings.identifierSymbols[exprID],
              parameterIsCrossinline[symbol] != nil
        else {
            return nil
        }
        return symbol
    }

    private func classify(parameterSymbol: SymbolID, usage: ExprID, role: UsageRole, materialized: Bool) {
        if isCallableValueMemberInvocation(usage) {
            checkMaterializedContext(usage, parameterSymbol: parameterSymbol, materialized: materialized)
            return
        }
        switch role {
        case .other:
            reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
        case .invocationCallee, .invokeReceiver:
            checkMaterializedContext(usage, parameterSymbol: parameterSymbol, materialized: materialized)
        case let .callArgument(call, argumentIndex):
            classifyCallArgument(
                usage, parameterSymbol: parameterSymbol, call: call, argumentIndex: argumentIndex,
                materialized: materialized
            )
        }
    }

    private func checkMaterializedContext(_ usage: ExprID, parameterSymbol: SymbolID, materialized: Bool) {
        guard materialized, parameterIsCrossinline[parameterSymbol] == false else { return }
        reportNonLocalReturn(usage, parameterSymbol: parameterSymbol)
    }

    private func isCallableValueMemberInvocation(_ usage: ExprID) -> Bool {
        guard ast.arena.isExplicitCall(usage),
              let expr = ast.arena.expr(usage)
        else { return false }
        switch expr {
        case .memberCall, .safeMemberCall:
            return true
        default:
            return false
        }
    }

    private func classifyCallArgument(
        _ usage: ExprID,
        parameterSymbol: SymbolID,
        call: ExprID,
        argumentIndex: Int,
        materialized: Bool
    ) {
        // The compiler expands `Array(size, init)` and the primitive-array
        // `(size, init)` factories itself instead of inlining a callee body,
        // so the initializer position is a materialized function value, not
        // an inlinable parameter slot. kotlinc rejects forwarding a
        // restricted inline parameter there even though the resolved
        // declaration carries `inline`.
        if isCompilerExpandedArrayInitializerCall(call) {
            reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
            return
        }
        guard let binding = sema.bindings.callBindings[call],
              sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true,
              let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
        else {
            reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
            return
        }
        let parameterIndex = binding.parameterMapping[argumentIndex] ?? argumentIndex
        guard signature.parameterTypes.indices.contains(parameterIndex),
              signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex),
              case .functionType = sema.types.kind(of: sema.types.makeNonNullable(signature.parameterTypes[parameterIndex]))
        else {
            reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
            return
        }
        if signature.valueParameterAllowsNonLocalReturn[parameterIndex] {
            checkMaterializedContext(usage, parameterSymbol: parameterSymbol, materialized: materialized)
            return
        }
        if let targetDecl = functionDeclBySymbol[binding.chosenCallee],
           targetDecl.valueParams.indices.contains(parameterIndex) {
            let targetParam = targetDecl.valueParams[parameterIndex]
            if targetParam.isNoinline {
                reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
            } else if targetParam.isCrossinline {
                if parameterIsCrossinline[parameterSymbol] != true {
                    reportNonLocalReturn(usage, parameterSymbol: parameterSymbol)
                }
            } else {
                reportIllegalUsage(usage, parameterSymbol: parameterSymbol)
            }
        } else if parameterIsCrossinline[parameterSymbol] != true {
            reportNonLocalReturn(usage, parameterSymbol: parameterSymbol)
        }
    }

    private func isCompilerExpandedArrayInitializerCall(_ call: ExprID) -> Bool {
        if sema.bindings.stdlibSpecialCallKind(for: call) == .arrayConstructor {
            return true
        }
        guard let binding = sema.bindings.callBindings[call],
              let symbol = sema.symbols.symbol(binding.chosenCallee),
              symbol.kind == .function,
              sema.symbols.isSourceBackedSymbol(binding.chosenCallee),
              symbol.fqName.count == 2,
              symbol.fqName[0] == interner.intern("kotlin"),
              knownNames.isArrayLikeName(symbol.name),
              let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
              signature.receiverType == nil,
              signature.parameterTypes.count == 2,
              case .functionType = sema.types.kind(
                  of: sema.types.makeNonNullable(signature.parameterTypes[1])
              ),
              ReceiverClassifier(sema: sema, interner: interner).isArrayLikeType(signature.returnType)
        else {
            return false
        }
        return true
    }

    private func reportIllegalUsage(_ usage: ExprID, parameterSymbol: SymbolID) {
        let display = parameterDisplay[parameterSymbol] ?? "'parameter'"
        diagnostics.error(
            "KSWIFTK-SEMA-0449",
            "illegal usage of inline parameter \(display). Add 'noinline' modifier to the parameter declaration.",
            range: ast.arena.exprRange(usage)
        )
    }

    private func reportNonLocalReturn(_ usage: ExprID, parameterSymbol: SymbolID) {
        let display = parameterDisplay[parameterSymbol] ?? "'parameter'"
        diagnostics.error(
            "KSWIFTK-SEMA-0450",
            "cannot inline \(display) here: it might contain non-local returns. Add 'crossinline' modifier to parameter declaration \(display).",
            range: ast.arena.exprRange(usage)
        )
    }

    private func walkFunctionBody(_ body: FunctionBody, materialized: Bool) {
        switch body {
        case let .block(statements, _):
            for statement in statements {
                visitExpr(statement, role: .other, materialized: materialized)
            }
        case let .expr(exprID, _):
            visitExpr(exprID, role: .other, materialized: materialized)
        case .unit:
            break
        }
    }

    private func walkExpr(_ exprID: ExprID, materialized: Bool) {
        guard let expr = ast.arena.expr(exprID) else { return }
        switch expr {
        case let .call(callee, _, args, _):
            visitExpr(callee, role: .invocationCallee, materialized: materialized)
            if !isContractDescriptionCall(callee: callee, args: args) {
                for (index, argument) in args.enumerated() {
                    visitExpr(
                        argument.expr, role: .callArgument(call: exprID, argumentIndex: index),
                        materialized: materialized
                    )
                }
            }
        case let .memberCall(receiver, calleeName, _, args, _):
            visitMemberCall(receiver: receiver, calleeName: calleeName, args: args, call: exprID, materialized: materialized)
        case let .safeMemberCall(receiver, calleeName, _, args, _):
            visitMemberCall(receiver: receiver, calleeName: calleeName, args: args, call: exprID, materialized: materialized)
        case let .lambdaLiteral(_, body, _, _):
            visitExpr(
                body, role: .other,
                materialized: materialized || !inlineLambdaArguments.contains(exprID)
            )
        case let .blockExpr(statements, trailingExpr, _):
            var childMaterialized = materialized
            if ast.arena.isAnonymousFunction(exprID) {
                let anonymousFunction = statements.first(where: ast.arena.isAnonymousFunction)
                let isInlined = anonymousFunction.map { inlineAnonymousFunctionArguments.contains($0) } ?? false
                childMaterialized = materialized || !isInlined
            }
            for statement in statements {
                visitExpr(statement, role: .other, materialized: childMaterialized)
            }
            if let trailingExpr {
                visitExpr(trailingExpr, role: .other, materialized: childMaterialized)
            }
        case let .objectLiteral(_, declID, _):
            if let declID {
                walkDecl(declID, materialized: true)
            }
        case let .localFunDecl(_, _, valueParams, _, body, _, _, _, _):
            let childMaterialized = ast.arena.isAnonymousFunction(exprID) ? materialized : true
            for valueParam in valueParams {
                if let defaultValue = valueParam.defaultValue {
                    visitExpr(defaultValue, role: .other, materialized: childMaterialized)
                }
            }
            walkFunctionBody(body, materialized: childMaterialized)
        case let .localNominalDecl(declID, _):
            walkDecl(declID, materialized: true)
        case let .forExpr(_, iterable, body, _, _):
            visitExpr(iterable, role: .other, materialized: materialized)
            visitExpr(body, role: .other, materialized: materialized)
        case let .forDestructuringExpr(_, iterable, body, _, _):
            visitExpr(iterable, role: .other, materialized: materialized)
            visitExpr(body, role: .other, materialized: materialized)
        case let .whileExpr(condition, body, _, _):
            visitExpr(condition, role: .other, materialized: materialized)
            visitExpr(body, role: .other, materialized: materialized)
        case let .doWhileExpr(body, condition, _, _):
            visitExpr(body, role: .other, materialized: materialized)
            visitExpr(condition, role: .other, materialized: materialized)
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            visitExpr(condition, role: .other, materialized: materialized)
            visitExpr(thenExpr, role: .other, materialized: materialized)
            if let elseExpr {
                visitExpr(elseExpr, role: .other, materialized: materialized)
            }
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject {
                visitExpr(subject, role: .other, materialized: materialized)
            }
            for branch in branches {
                for condition in branch.conditions {
                    visitExpr(condition, role: .other, materialized: materialized)
                }
                if let guardExpr = branch.guard_ {
                    visitExpr(guardExpr, role: .other, materialized: materialized)
                }
                visitExpr(branch.body, role: .other, materialized: materialized)
            }
            if let elseExpr {
                visitExpr(elseExpr, role: .other, materialized: materialized)
            }
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            visitExpr(body, role: .other, materialized: materialized)
            for clause in catchClauses {
                visitExpr(clause.body, role: .other, materialized: materialized)
            }
            if let finallyExpr {
                visitExpr(finallyExpr, role: .other, materialized: materialized)
            }
        case let .unaryExpr(_, operand, _):
            visitExpr(operand, role: .other, materialized: materialized)
        case let .isCheck(operand, _, _, _):
            visitExpr(operand, role: .other, materialized: materialized)
        case let .asCast(operand, _, _, _):
            visitExpr(operand, role: .other, materialized: materialized)
        case let .nullAssert(operand, _):
            visitExpr(operand, role: .other, materialized: materialized)
        case let .returnExpr(value, _, _):
            if let value {
                visitExpr(value, role: .other, materialized: materialized)
            }
        case let .throwExpr(value, _):
            visitExpr(value, role: .other, materialized: materialized)
        case let .localDecl(_, _, _, initializer, _, _, _):
            if let initializer {
                visitExpr(initializer, role: .other, materialized: materialized)
            }
        case let .localAssign(_, value, _):
            visitExpr(value, role: .other, materialized: materialized)
        case let .memberAssign(receiver, _, value, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            visitExpr(value, role: .other, materialized: materialized)
        case let .safeMemberAssign(receiver, _, value, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            visitExpr(value, role: .other, materialized: materialized)
        case let .indexedAssign(receiver, indices, value, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            for index in indices {
                visitExpr(index, role: .other, materialized: materialized)
            }
            visitExpr(value, role: .other, materialized: materialized)
        case let .indexedAccess(receiver, indices, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            for index in indices {
                visitExpr(index, role: .other, materialized: materialized)
            }
        case let .compoundAssign(_, _, value, _):
            visitExpr(value, role: .other, materialized: materialized)
        case let .memberCompoundAssign(_, receiver, _, value, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            visitExpr(value, role: .other, materialized: materialized)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            visitExpr(receiver, role: .other, materialized: materialized)
            for index in indices {
                visitExpr(index, role: .other, materialized: materialized)
            }
            visitExpr(value, role: .other, materialized: materialized)
        case let .binary(_, lhs, rhs, _):
            visitExpr(lhs, role: .other, materialized: materialized)
            visitExpr(rhs, role: .other, materialized: materialized)
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            visitExpr(lhs, role: .other, materialized: materialized)
            visitExpr(rhs, role: .other, materialized: materialized)
        case let .destructuringDecl(_, _, initializer, _):
            visitExpr(initializer, role: .other, materialized: materialized)
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(partExpr) = part {
                    visitExpr(partExpr, role: .other, materialized: materialized)
                }
            }
        case let .callableRef(receiver, _, _):
            if let receiver {
                visitExpr(receiver, role: .other, materialized: materialized)
            }
        default:
            break
        }
    }

    private func visitMemberCall(
        receiver: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        call: ExprID,
        materialized: Bool
    ) {
        visitExpr(
            receiver, role: calleeName == invokeName ? .invokeReceiver : .other,
            materialized: materialized
        )
        for (index, argument) in args.enumerated() {
            visitExpr(
                argument.expr, role: .callArgument(call: call, argumentIndex: index),
                materialized: materialized
            )
        }
    }

    private func walkDecl(_ declID: DeclID, materialized: Bool) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case let .funDecl(funDecl):
            for valueParam in funDecl.valueParams {
                if let defaultValue = valueParam.defaultValue {
                    visitExpr(defaultValue, role: .other, materialized: materialized)
                }
            }
            walkFunctionBody(funDecl.body, materialized: materialized)
        case let .propertyDecl(property):
            if let initializer = property.initializer {
                visitExpr(initializer, role: .other, materialized: materialized)
            }
            if let delegateExpression = property.delegateExpression {
                visitExpr(delegateExpression, role: .other, materialized: materialized)
            }
            if let delegateBody = property.delegateBody {
                walkFunctionBody(delegateBody, materialized: materialized)
            }
            if let getter = property.getter {
                walkFunctionBody(getter.body, materialized: materialized)
            }
            if let setter = property.setter {
                walkFunctionBody(setter.body, materialized: materialized)
            }
            if let field = property.explicitBackingField, let initializer = field.initializer {
                visitExpr(initializer, role: .other, materialized: materialized)
            }
        case let .classDecl(classDecl):
            for superTypeEntry in classDecl.superTypeEntries {
                walkSuperTypeEntry(superTypeEntry, materialized: materialized)
            }
            for param in classDecl.primaryConstructorParams {
                if let defaultValue = param.defaultValue {
                    visitExpr(defaultValue, role: .other, materialized: materialized)
                }
            }
            for initBlock in classDecl.initBlocks {
                walkFunctionBody(initBlock, materialized: materialized)
            }
            for constructor in classDecl.secondaryConstructors {
                for valueParam in constructor.valueParams {
                    if let defaultValue = valueParam.defaultValue {
                        visitExpr(defaultValue, role: .other, materialized: materialized)
                    }
                }
                if let delegationCall = constructor.delegationCall {
                    for argument in delegationCall.args {
                        visitExpr(argument.expr, role: .other, materialized: materialized)
                    }
                }
                walkFunctionBody(constructor.body, materialized: materialized)
            }
            for memberDecl in classDecl.memberFunctions
                + classDecl.memberProperties
                + classDecl.nestedClasses
                + classDecl.nestedObjects {
                walkDecl(memberDecl, materialized: true)
            }
            for enumEntry in classDecl.enumEntries {
                walkEnumEntry(enumEntry, materialized: true)
            }
            if let companionObject = classDecl.companionObject {
                walkDecl(companionObject, materialized: true)
            }
            if let companionBlockObject = classDecl.companionBlockObject {
                walkDecl(companionBlockObject, materialized: true)
            }
        case let .interfaceDecl(interfaceDecl):
            for memberDecl in interfaceDecl.memberFunctions
                + interfaceDecl.memberProperties
                + interfaceDecl.nestedClasses
                + interfaceDecl.nestedObjects {
                walkDecl(memberDecl, materialized: true)
            }
            if let companionObject = interfaceDecl.companionObject {
                walkDecl(companionObject, materialized: true)
            }
            if let companionBlockObject = interfaceDecl.companionBlockObject {
                walkDecl(companionBlockObject, materialized: true)
            }
        case let .objectDecl(objectDecl):
            for superTypeEntry in objectDecl.superTypeEntries {
                walkSuperTypeEntry(superTypeEntry, materialized: materialized)
            }
            for argument in objectDecl.superTypeConstructorArgs {
                visitExpr(argument.expr, role: .other, materialized: materialized)
            }
            for initBlock in objectDecl.initBlocks {
                walkFunctionBody(initBlock, materialized: materialized)
            }
            for memberDecl in objectDecl.memberFunctions
                + objectDecl.memberProperties
                + objectDecl.nestedClasses
                + objectDecl.nestedObjects {
                walkDecl(memberDecl, materialized: true)
            }
        case let .enumEntryDecl(enumEntry):
            walkEnumEntry(enumEntry, materialized: materialized)
        case .typeAliasDecl:
            break
        }
    }

    private func walkEnumEntry(_ enumEntry: EnumEntryDecl, materialized: Bool) {
        for argument in enumEntry.constructorArgs {
            visitExpr(argument.expr, role: .other, materialized: materialized)
        }
        for initBlock in enumEntry.initBlocks {
            walkFunctionBody(initBlock, materialized: materialized)
        }
        for memberDecl in enumEntry.memberFunctions
            + enumEntry.memberProperties
            + enumEntry.nestedClasses {
            walkDecl(memberDecl, materialized: true)
        }
    }

    private func walkSuperTypeEntry(_ entry: SuperTypeEntry, materialized: Bool) {
        if let delegateExpression = entry.delegateExpression {
            visitExpr(delegateExpression, role: .other, materialized: materialized)
        }
        for argument in entry.constructorArgs {
            visitExpr(argument.expr, role: .other, materialized: materialized)
        }
    }

    private func isContractDescriptionCall(callee: ExprID, args: [CallArgument]) -> Bool {
        guard args.count == 1,
              case let .nameRef(calleeName, _) = ast.arena.expr(callee)
        else {
            return false
        }
        return calleeName == knownNames.contract
    }
}
