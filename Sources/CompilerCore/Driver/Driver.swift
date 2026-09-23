import Foundation

public final class CompilerDriver {
    private struct PreparedRunContext {
        let context: CompilationContext
        let timePhasesEnabled: Bool
        let incrementalEnabled: Bool
    }

    private let backendPhases: @Sendable () -> [CompilerPhase]

    public init(backendPhases: @escaping @Sendable () -> [CompilerPhase] = { [] }) {
        self.backendPhases = backendPhases
    }

    public func run(options: CompilerOptions) -> Int {
        let result = runInternal(options: options, printDiagnostics: true)
        return result.exitCode
    }

    func runForTesting(options: CompilerOptions) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        runInternal(options: options, printDiagnostics: false)
    }

    static func fallbackDiagnostic(for error: Error) -> (code: String, message: String)? {
        guard let pipelineError = error as? CompilerPipelineError else {
            return nil
        }
        switch pipelineError {
        case .loadError:
            return (
                code: "KSWIFTK-PIPELINE-0001",
                message: "Compiler pipeline failed while loading input sources."
            )
        case let .invalidInput(detail):
            return (
                code: "KSWIFTK-PIPELINE-0002",
                message: "Compiler pipeline received invalid intermediate state: \(detail)"
            )
        case .outputUnavailable:
            return (
                code: "KSWIFTK-PIPELINE-0003",
                message: "Compiler pipeline could not produce requested output."
            )
        }
    }

    private func runInternal(
        options: CompilerOptions,
        printDiagnostics: Bool
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        let prepared = prepareContext(options: options)
        let ctx = prepared.context

        let phases: [CompilerPhase] = [
            LoadSourcesPhase(),
            LexPhase(),
            ParsePhase(),
            BuildASTPhase(),
            SemaPhase(),
            BuildKIRPhase(),
            LoweringPhase(),
        ]

        executePhases(ctx: ctx, phases: phases, incrementalEnabled: prepared.incrementalEnabled)

        if !ctx.diagnostics.hasError, !ctx.incrementalOutputRestored {
            if ctx.options.emit == .kirDump {
                emitKIRDump(ctx: ctx)
            } else {
                let backend = backendPhases()
                executePhases(ctx: ctx, phases: backend, incrementalEnabled: false)
            }
        }

        return finalizeRun(ctx: ctx, printDiagnostics: printDiagnostics, timePhasesEnabled: prepared.timePhasesEnabled)
    }

    private func isIncrementalEnabled(options: CompilerOptions) -> Bool {
        if options.incrementalCachePath != nil {
            return true
        }
        return options.frontendFlags.contains("incremental")
    }

    private func resolveIncrementalCachePath(options: CompilerOptions) -> String {
        if let explicit = options.incrementalCachePath {
            return explicit
        }
        // Default: place cache next to the output.
        let outputURL = URL(fileURLWithPath: options.outputPath)
        let parentDir = outputURL.deletingLastPathComponent().path
        return parentDir + "/.kswiftk-cache"
    }

    /// Computes fingerprints for loaded sources, determines the incremental
    /// recompilation set, and restores the cached output for exact no-op builds.
    /// Returns `true` when the rest of the pipeline can be skipped.
    private func prepareIncrementalPipeline(ctx: CompilationContext) -> Bool {
        guard let cache = ctx.incrementalCache else { return false }

        let allPaths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
        cache.computeCurrentFingerprints(for: allPaths, sourceManager: ctx.sourceManager)

        if let recompileSet = cache.recompilationSet(allPaths: allPaths, options: ctx.options) {
            ctx.setIncrementalRecompileSet(recompileSet)
            if recompileSet.isEmpty {
                if cache.restoreCachedOutput(for: ctx.options) {
                    ctx.markIncrementalOutputRestored()
                    return true
                }
                // Old caches did not persist output artifacts. Fall back to a
                // full build so the requested output is always produced.
                ctx.setIncrementalRecompileSet(nil)
            } else if let frontendState = cache.loadFrontendState(for: ctx.options) {
                ctx.interner.preload(frontendState.internerValues)
                ctx.installIncrementalFrontendState(frontendState)
            } else {
                // Old caches can compute a recompilation set from deps.json, but
                // cannot safely skip unchanged files without reusable frontend
                // state. Fall back to a full build and refresh the cache.
                ctx.setIncrementalRecompileSet(nil)
            }
        } else {
            // No compatible previous cache — full build.
            ctx.setIncrementalRecompileSet(nil)
        }
        return false
    }

    private func prepareContext(options: CompilerOptions) -> PreparedRunContext {
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        let timePhasesEnabled = options.frontendFlags.contains("time-phases")
        if timePhasesEnabled {
            context.installPhaseTimer(PhaseTimer())
        }

        let incrementalEnabled = isIncrementalEnabled(options: options)
        if incrementalEnabled {
            let cachePath = resolveIncrementalCachePath(options: options)
            let cache = IncrementalCompilationCache(cachePath: cachePath)
            cache.loadPreviousState()
            context.installIncrementalCache(cache)
        }

        return PreparedRunContext(
            context: context,
            timePhasesEnabled: timePhasesEnabled,
            incrementalEnabled: incrementalEnabled
        )
    }

    private func executePhases(
        ctx: CompilationContext,
        phases: [CompilerPhase],
        incrementalEnabled: Bool
    ) {
        do {
            for phase in phases {
                let phaseName = type(of: phase).name
                ctx.phaseTimer?.beginPhase(phaseName)
                defer { ctx.phaseTimer?.endPhase() }

                if phase is LoadSourcesPhase {
                    try phase.run(ctx)
                    if ctx.diagnostics.hasError { break }
                    if incrementalEnabled {
                        if prepareIncrementalPipeline(ctx: ctx) {
                            return
                        }
                    }
                    continue
                }

                try phase.run(ctx)
                if ctx.diagnostics.hasError {
                    break
                }
            }
        } catch {
            if !ctx.diagnostics.hasError {
                if let fallback = Self.fallbackDiagnostic(for: error) {
                    ctx.diagnostics.error(fallback.code, fallback.message, range: nil)
                } else {
                    ctx.diagnostics.error("KSWIFTK-ICE-0001", "Compiler internal error: \(error)", range: nil)
                }
            }
        }
    }

    private func finalizeRun(
        ctx: CompilationContext,
        printDiagnostics: Bool,
        timePhasesEnabled: Bool
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        if !ctx.diagnostics.hasError, let cache = ctx.incrementalCache, !ctx.incrementalOutputRestored {
            let depGraph = buildDependencyGraph(ctx: ctx)
            let buildHash = cache.buildConfigurationHash(for: ctx.options)
            let frontendState = IncrementalFrontendState(context: ctx, buildConfigurationHash: buildHash)
            cache.saveState(dependencyGraph: depGraph, options: ctx.options, frontendState: frontendState)
        }

        if printDiagnostics {
            ctx.diagnostics.printDiagnostics(format: ctx.options.diagnosticsFormat, from: ctx.sourceManager)
        }

        if timePhasesEnabled, let timer = ctx.phaseTimer {
            timer.printSummary()
        }

        return (ctx.diagnostics.hasError ? 1 : 0, ctx.diagnostics.diagnostics)
    }

    private func emitKIRDump(ctx: CompilationContext) {
        guard let kir = ctx.kir else {
            ctx.diagnostics.error("KSWIFTK-PIPELINE-0003", "KIR not available for dump.", range: nil)
            return
        }
        let path = ctx.options.outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        do {
            try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        } catch {
            ctx.diagnostics.error("KSWIFTK-PIPELINE-0003", "Could not write KIR dump: \(error)", range: nil)
        }
    }

    /// Builds a dependency graph from the current compilation state.
    private func buildDependencyGraph(ctx: CompilationContext) -> DependencyGraph {
        let graph = DependencyGraph()
        guard let sema = ctx.sema, let ast = ctx.ast else {
            return graph
        }
        let interner = ctx.interner
        var symbolsByFile: [FileID: Set<String>] = [:]
        for sym in sema.symbols.allSymbols() {
            guard let symFileID = sema.symbols.sourceFileID(for: sym.id) else { continue }
            symbolsByFile[symFileID, default: []].insert(interner.resolve(sym.name))
        }

        var providedByFile: [FileID: Set<String>] = [:]
        for file in ast.files {
            providedByFile[file.fileID] = collectProvidedSymbols(
                file: file,
                ast: ast,
                symbolsByFile: symbolsByFile,
                interner: interner
            )
        }
        let allProvidedSymbols = providedByFile.values.reduce(into: Set<String>()) { result, symbols in
            result.formUnion(symbols)
        }

        for file in ast.files {
            let filePath = ctx.sourceManager.path(of: file.fileID)
            guard !filePath.isEmpty, let provided = providedByFile[file.fileID] else { continue }
            let package = file.packageFQName.map(interner.resolve).joined(separator: ".")
            let depended = collectDependedSymbols(
                file: file,
                ast: ast,
                interner: interner,
                availableSymbols: allProvidedSymbols
            )
            graph.recordProvided(filePath: filePath, symbols: provided, package: package)
            graph.recordDepended(filePath: filePath, symbols: depended)
            for imp in file.imports where imp.isWildcard {
                let importedPackage = imp.path.map(interner.resolve).joined(separator: ".")
                graph.recordWildcardImport(filePath: filePath, package: importedPackage)
            }
        }
        return graph
    }

    private func collectProvidedSymbols(
        file: ASTFile,
        ast: ASTModule,
        symbolsByFile: [FileID: Set<String>],
        interner: StringInterner
    ) -> Set<String> {
        var provided = Set<String>()
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID) else { continue }
            if let name = extractDeclName(decl, interner: interner) {
                provided.insert(name)
            }
        }
        if let fileSymbols = symbolsByFile[file.fileID] {
            provided.formUnion(fileSymbols)
        }
        return provided
    }

    private func collectDependedSymbols(
        file: ASTFile,
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>
    ) -> Set<String> {
        var depended = Set<String>()
        for imp in file.imports {
            if imp.isWildcard {
                continue
            }
            if let alias = imp.alias {
                depended.insert(interner.resolve(alias))
            } else if let last = imp.path.last {
                let name = interner.resolve(last)
                if name != "*" {
                    depended.insert(name)
                }
            }
        }
        for declID in file.topLevelDecls {
            collectDeclDependencies(
                declID: declID,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        }
        for exprID in file.scriptBody {
            collectExprDependencies(
                exprID: exprID,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        }
        return depended
    }

    /// Extracts the declaration name as a String, if available.
    private func extractDeclName(_ decl: Decl, interner: StringInterner) -> String? {
        switch decl {
        case let .classDecl(d):
            interner.resolve(d.name)
        case let .interfaceDecl(d):
            interner.resolve(d.name)
        case let .funDecl(d):
            interner.resolve(d.name)
        case let .propertyDecl(d):
            interner.resolve(d.name)
        case let .typeAliasDecl(d):
            interner.resolve(d.name)
        case let .objectDecl(d):
            interner.resolve(d.name)
        case let .enumEntryDecl(d):
            interner.resolve(d.name)
        }
    }

    /// Recursively collects symbol names referenced by a declaration.
    private func collectDeclDependencies(
        declID: DeclID,
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        guard let decl = ast.arena.decl(declID) else { return }

        switch decl {
        case let .classDecl(d):
            collectTypeParameterDependencies(
                d.typeParams,
                ast: ast,
                interner: interner,
                depended: &depended
            )
            collectValueParameterDependencies(
                d.primaryConstructorParams,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            collectNominalDeclDependencies(
                superTypes: d.superTypeEntries.map(\.typeRef),
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            for entry in d.superTypeEntries {
                if let delegateExpression = entry.delegateExpression {
                    collectExprDependencies(
                        exprID: delegateExpression,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
                collectCallArguments(
                    entry.constructorArgs,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            for initBlock in d.initBlocks {
                collectFunctionBodyDependencies(
                    initBlock,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            for constructor in d.secondaryConstructors {
                collectValueParameterDependencies(
                    constructor.valueParams,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
                if let delegationCall = constructor.delegationCall {
                    collectCallArguments(
                        delegationCall.args,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
                collectFunctionBodyDependencies(
                    constructor.body,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            for typeAlias in d.nestedTypeAliases {
                collectTypeAliasDependencies(
                    typeAlias,
                    ast: ast,
                    interner: interner,
                    depended: &depended
                )
            }
            for entry in d.enumEntries {
                collectCallArguments(
                    entry.constructorArgs,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
                for memberID in entry.memberFunctions {
                    collectDeclDependencies(
                        declID: memberID,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
            }
            if let companionObject = d.companionObject {
                collectDeclDependencies(
                    declID: companionObject,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        case let .interfaceDecl(d):
            collectTypeParameterDependencies(
                d.typeParams,
                ast: ast,
                interner: interner,
                depended: &depended
            )
            collectNominalDeclDependencies(
                superTypes: d.superTypes,
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            for typeAlias in d.nestedTypeAliases {
                collectTypeAliasDependencies(
                    typeAlias,
                    ast: ast,
                    interner: interner,
                    depended: &depended
                )
            }
            if let companionObject = d.companionObject {
                collectDeclDependencies(
                    declID: companionObject,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        case let .objectDecl(d):
            collectNominalDeclDependencies(
                superTypes: d.superTypes,
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            collectCallArguments(
                d.superTypeConstructorArgs,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            for initBlock in d.initBlocks {
                collectFunctionBodyDependencies(
                    initBlock,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            for typeAlias in d.nestedTypeAliases {
                collectTypeAliasDependencies(
                    typeAlias,
                    ast: ast,
                    interner: interner,
                    depended: &depended
                )
            }
        case let .funDecl(d):
            collectFunDeclDependencies(
                d,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        case let .propertyDecl(d):
            if let typeRef = d.type {
                collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
            }
            if let receiverType = d.receiverType {
                collectTypeRefDependencies(typeRefID: receiverType, ast: ast, interner: interner, depended: &depended)
            }
            if let initializer = d.initializer {
                collectExprDependencies(
                    exprID: initializer,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            if let delegateExpression = d.delegateExpression {
                collectExprDependencies(
                    exprID: delegateExpression,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            if let delegateBody = d.delegateBody {
                collectFunctionBodyDependencies(
                    delegateBody,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            if let getter = d.getter {
                collectFunctionBodyDependencies(
                    getter.body,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            if let setter = d.setter {
                collectFunctionBodyDependencies(
                    setter.body,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
            if let backingField = d.explicitBackingField {
                if let typeRef = backingField.type {
                    collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
                }
                collectExprDependencies(
                    exprID: backingField.initializer,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        case let .typeAliasDecl(d):
            collectTypeAliasDependencies(d, ast: ast, interner: interner, depended: &depended)
        case let .enumEntryDecl(d):
            collectCallArguments(
                d.constructorArgs,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
            for memberID in d.memberFunctions {
                collectDeclDependencies(
                    declID: memberID,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        }
    }

    private func collectNominalDeclDependencies(
        superTypes: [TypeRefID],
        memberIDs: [DeclID],
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        for superType in superTypes {
            collectTypeRefDependencies(typeRefID: superType, ast: ast, interner: interner, depended: &depended)
        }
        for memberID in memberIDs {
            collectDeclDependencies(
                declID: memberID,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        }
    }

    private func collectFunDeclDependencies(
        _ d: FunDecl,
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        collectTypeParameterDependencies(d.typeParams, ast: ast, interner: interner, depended: &depended)
        if let receiverType = d.receiverType {
            collectTypeRefDependencies(typeRefID: receiverType, ast: ast, interner: interner, depended: &depended)
        }
        collectValueParameterDependencies(
            d.valueParams,
            ast: ast,
            interner: interner,
            availableSymbols: availableSymbols,
            depended: &depended
        )
        if let retType = d.returnType {
            collectTypeRefDependencies(typeRefID: retType, ast: ast, interner: interner, depended: &depended)
        }
        collectFunctionBodyDependencies(
            d.body,
            ast: ast,
            interner: interner,
            availableSymbols: availableSymbols,
            depended: &depended
        )
    }

    private func collectTypeParameterDependencies(
        _ params: [TypeParamDecl],
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        for param in params {
            for upperBound in param.upperBounds {
                collectTypeRefDependencies(typeRefID: upperBound, ast: ast, interner: interner, depended: &depended)
            }
        }
    }

    private func collectValueParameterDependencies(
        _ params: [ValueParamDecl],
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        for param in params {
            if let typeRef = param.type {
                collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
            }
            if let defaultValue = param.defaultValue {
                collectExprDependencies(
                    exprID: defaultValue,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        }
    }

    private func collectTypeAliasDependencies(
        _ d: TypeAliasDecl,
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        collectTypeParameterDependencies(d.typeParams, ast: ast, interner: interner, depended: &depended)
        if let underlyingType = d.underlyingType {
            collectTypeRefDependencies(typeRefID: underlyingType, ast: ast, interner: interner, depended: &depended)
        }
    }

    private func collectFunctionBodyDependencies(
        _ body: FunctionBody,
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        switch body {
        case let .block(expressions, _):
            for expression in expressions {
                collectExprDependencies(
                    exprID: expression,
                    ast: ast,
                    interner: interner,
                    availableSymbols: availableSymbols,
                    depended: &depended
                )
            }
        case let .expr(expression, _):
            collectExprDependencies(
                exprID: expression,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        case .unit:
            break
        }
    }

    private func collectCallArguments(
        _ arguments: [CallArgument],
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        for argument in arguments {
            collectExprDependencies(
                exprID: argument.expr,
                ast: ast,
                interner: interner,
                availableSymbols: availableSymbols,
                depended: &depended
            )
        }
    }

    private func collectExprDependencies(
        exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner,
        availableSymbols: Set<String>,
        depended: inout Set<String>
    ) {
        guard let expr = ast.arena.expr(exprID) else { return }

        func collectName(_ name: InternedString) {
            let resolved = interner.resolve(name)
            if availableSymbols.contains(resolved) {
                depended.insert(resolved)
            }
        }

        func collectTypeArgs(_ typeArgs: [TypeRefID]) {
            for typeArg in typeArgs {
                collectTypeRefDependencies(typeRefID: typeArg, ast: ast, interner: interner, depended: &depended)
            }
        }

        switch expr {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral,
             .stringLiteral, .breakExpr, .continueExpr, .thisRef:
            break
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(expression) = part {
                    collectExprDependencies(
                        exprID: expression,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
            }
        case let .nameRef(name, _):
            collectName(name)
        case let .forExpr(_, iterable, body, _, _), let .forDestructuringExpr(_, iterable, body, _):
            collectExprDependencies(exprID: iterable, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .whileExpr(condition, body, _, _), let .doWhileExpr(body, condition, _, _):
            collectExprDependencies(exprID: condition, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .localDecl(_, _, typeAnnotation, initializer, _, _):
            if let typeAnnotation {
                collectTypeRefDependencies(typeRefID: typeAnnotation, ast: ast, interner: interner, depended: &depended)
            }
            if let initializer {
                collectExprDependencies(exprID: initializer, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .localAssign(_, value, _), let .throwExpr(value, _), let .returnExpr(value: value?, _, _):
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case .returnExpr(value: nil, _, _):
            break
        case let .memberAssign(receiver, callee, value, _):
            collectName(callee)
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .indexedAssign(receiver, indices, value, _):
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            for index in indices {
                collectExprDependencies(exprID: index, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .call(callee, typeArgs, args, _):
            collectTypeArgs(typeArgs)
            collectExprDependencies(exprID: callee, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectCallArguments(args, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .memberCall(receiver, callee, typeArgs, args, _), let .safeMemberCall(receiver, callee, typeArgs, args, _):
            collectName(callee)
            collectTypeArgs(typeArgs)
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectCallArguments(args, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .indexedAccess(receiver, indices, _):
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            for index in indices {
                collectExprDependencies(exprID: index, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .binary(_, lhs, rhs, _), let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            collectExprDependencies(exprID: lhs, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: rhs, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject {
                collectExprDependencies(exprID: subject, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            for branch in branches {
                for condition in branch.conditions {
                    collectExprDependencies(exprID: condition, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
                }
                if let guardExpr = branch.guard_ {
                    collectExprDependencies(exprID: guardExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
                }
                collectExprDependencies(exprID: branch.body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            if let elseExpr {
                collectExprDependencies(exprID: elseExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            collectExprDependencies(exprID: condition, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: thenExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            if let elseExpr {
                collectExprDependencies(exprID: elseExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            collectExprDependencies(exprID: body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            for clause in catchClauses {
                collectExprDependencies(exprID: clause.body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            if let finallyExpr {
                collectExprDependencies(exprID: finallyExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .unaryExpr(_, operand, _), let .nullAssert(operand, _):
            collectExprDependencies(exprID: operand, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .isCheck(expression, type, _, _), let .asCast(expression, type, _, _):
            collectExprDependencies(exprID: expression, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectTypeRefDependencies(typeRefID: type, ast: ast, interner: interner, depended: &depended)
        case let .compoundAssign(_, _, value, _):
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            for index in indices {
                collectExprDependencies(exprID: index, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .memberCompoundAssign(_, receiver, callee, value, _):
            collectName(callee)
            collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            collectExprDependencies(exprID: value, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .lambdaLiteral(_, body, _, _):
            collectExprDependencies(exprID: body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .objectLiteral(superTypes, decl, _):
            for superType in superTypes {
                collectTypeRefDependencies(typeRefID: superType, ast: ast, interner: interner, depended: &depended)
            }
            if let decl {
                collectDeclDependencies(declID: decl, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .callableRef(receiver, member, _):
            collectName(member)
            if let receiver {
                collectExprDependencies(exprID: receiver, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .localFunDecl(_, valueParams, returnType, body, _, _):
            collectValueParameterDependencies(valueParams, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            if let returnType {
                collectTypeRefDependencies(typeRefID: returnType, ast: ast, interner: interner, depended: &depended)
            }
            collectFunctionBodyDependencies(body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .localNominalDecl(declID, _):
            collectDeclDependencies(declID: declID, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                collectExprDependencies(exprID: statement, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
            if let trailingExpr {
                collectExprDependencies(exprID: trailingExpr, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
            }
        case let .superRef(interfaceQualifier, _):
            if let interfaceQualifier {
                collectName(interfaceQualifier)
            }
        case let .destructuringDecl(_, _, initializer, _):
            collectExprDependencies(exprID: initializer, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }
    }

    /// Collects type reference dependencies.
    private func collectTypeRefDependencies(
        typeRefID: TypeRefID,
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else { return }

        switch typeRef {
        case let .named(path, args, _):
            // Use only the last path component (the simple type name) to match
            // provided symbol granularity. Earlier components are package/module
            // qualifiers that don't correspond to per-file provided symbols.
            if let last = path.last {
                depended.insert(interner.resolve(last))
            }
            for arg in args {
                switch arg {
                case let .invariant(typeRef), let .out(typeRef), let .in(typeRef):
                    collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
                case .star:
                    break
                }
            }
        case let .functionType(contextReceiverTypes, receiverType, paramTypes, returnType, _, _):
            for contextReceiverType in contextReceiverTypes {
                collectTypeRefDependencies(typeRefID: contextReceiverType, ast: ast, interner: interner, depended: &depended)
            }
            if let receiverType {
                collectTypeRefDependencies(typeRefID: receiverType, ast: ast, interner: interner, depended: &depended)
            }
            for paramType in paramTypes {
                collectTypeRefDependencies(typeRefID: paramType, ast: ast, interner: interner, depended: &depended)
            }
            collectTypeRefDependencies(typeRefID: returnType, ast: ast, interner: interner, depended: &depended)
        case let .intersection(parts):
            for part in parts {
                collectTypeRefDependencies(typeRefID: part, ast: ast, interner: interner, depended: &depended)
            }
        case let .annotated(base, annotations):
            for annotation in annotations {
                depended.insert(annotation.name.split(separator: ".").last.map(String.init) ?? annotation.name)
            }
            collectTypeRefDependencies(typeRefID: base, ast: ast, interner: interner, depended: &depended)
        }
    }
}
