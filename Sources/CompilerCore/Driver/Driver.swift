import Foundation

public final class CompilerDriver {
    private struct PreparedRunContext {
        let context: CompilationContext
        let timePhasesEnabled: Bool
        let incrementalEnabled: Bool
    }

    private let backendPhases: @Sendable () -> [CompilerPhase]

    /// Starts program-independent backend work (e.g. resolving runtime link
    /// inputs) in the background while the frontend runs, so Link finds it
    /// ready instead of paying for it after Codegen. Must not block, throw, or
    /// trigger expensive builds; failures are left for the real phase to report.
    private let backendPrefetch: @Sendable (CompilerOptions) -> Void

    public init(
        backendPhases: @escaping @Sendable () -> [CompilerPhase] = { [] },
        backendPrefetch: @escaping @Sendable (CompilerOptions) -> Void = { _ in }
    ) {
        self.backendPhases = backendPhases
        self.backendPrefetch = backendPrefetch
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
        printDiagnostics: Bool,
        inMemorySources: [String: Data] = [:],
        generatedTestRun: Bool = false
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        if options.frontendFlags.contains("generate-test-runner"), !generatedTestRun {
            var preflightOptions = options
            preflightOptions.incrementalCachePath = nil
            preflightOptions.frontendFlags.removeAll { $0 == "incremental" }
            let preflight = runFrontend(options: preflightOptions).context
            if options.emit != .executable || options.stdlibOnly {
                preflight.diagnostics.error("KSWIFTK-TEST-0001", "Test runner generation requires executable emission.", range: nil)
            }
            if !preflight.diagnostics.hasError,
               let generated = TestRunnerGenerator(context: preflight).generate() {
                var generatedOptions = preflightOptions
                generatedOptions.inputs.append(generated.runnerPath)
                generatedOptions.entryPointFQName = TestRunnerGenerator.entryPoint
                return runInternal(options: generatedOptions, printDiagnostics: printDiagnostics,
                                   inMemorySources: generated.sources, generatedTestRun: true)
            }
            return finalizeRun(ctx: preflight, printDiagnostics: printDiagnostics, timePhasesEnabled: false)
        }
        let prepared = prepareContext(options: options, generatedTestRun: generatedTestRun)
        let ctx = prepared.context
        if options.emit == .executable {
            backendPrefetch(options)
        }
        // Preserve CLI input order; dictionary iteration must not assign file IDs.
        for path in options.inputs {
            if let data = inMemorySources[path] {
                _ = ctx.sourceManager.addFile(path: path, contents: data)
            }
        }

        let syntaxPhases: [CompilerPhase] = [LoadSourcesPhase()]
            + (options.emit.isJVM ? [JVMPreparationPhase()] : []) + [
            LexPhase(),
            ParsePhase(rejectsTopLevelStatementsOutsideScripts: true),
            BuildASTPhase(),
        ]
        // JVM shares semantic analysis, but has its own typed IR and lowering.
        let phases: [CompilerPhase] = syntaxPhases + (options.emit.isJVM ? [
            JVMSourceValidationPhase(),
            SemaPhase(),
            JVMFrontendPhase(),
        ] : [
            SemaPhase(),
            BuildKIRPhase(),
            LoweringPhase(),
        ])

        executePhases(ctx: ctx, phases: phases, incrementalEnabled: prepared.incrementalEnabled)

        var runExitCode: Int?
        if !ctx.diagnostics.hasError, !ctx.incrementalOutputRestored {
            if ctx.options.emit == .kirDump {
                emitKIRDump(ctx: ctx)
            } else if ctx.options.runsImmediately {
                runExitCode = runImmediately(ctx: ctx)
            } else {
                let backend = backendPhases()
                executePhases(ctx: ctx, phases: backend, incrementalEnabled: false)
            }
        }

        let result = finalizeRun(ctx: ctx, printDiagnostics: printDiagnostics, timePhasesEnabled: prepared.timePhasesEnabled)
        if let runExitCode, result.exitCode == 0 {
            return (runExitCode, result.diagnostics)
        }
        return result
    }

    private func isIncrementalEnabled(options: CompilerOptions, generatedTestRun: Bool = false) -> Bool {
        // Generated test-runner runs compile in-memory overlay sources that
        // were never written next to the inputs — keep them off the cache
        // even under the default-on scope.
        guard !generatedTestRun else { return false }
        guard !options.emit.isJVM else { return false }
        // `--run` must execute this compile's KIR, never restore a cached artifact.
        if options.runsImmediately { return false }
        if options.frontendFlags.contains("no-incremental") {
            return false
        }
        // Explicit opt-ins keep working everywhere.
        if options.incrementalCachePath != nil
            || options.frontendFlags.contains("incremental") {
            return true
        }
        // Default-on scope: configurations that compile the bundled stdlib
        // from source would snapshot its entire AST into frontend state —
        // hundreds of MB that make the cache a pure cost. Those stay opt-in;
        // artifact-based stdlib (kklib) and --no-stdlib builds are cached by
        // default.
        return !options.includeStdlib && !options.stdlibOnly
    }

    /// An explicitly configured path is used as-is (it is leaf-validated and
    /// integrity-authenticated at load); without one the cache lives in the
    /// compiler-managed per-user location outside the workspace, never next to
    /// the output where a repository could ship a poisoned `.kswiftk-cache`.
    private func resolveIncrementalCache(options: CompilerOptions) -> IncrementalCompilationCache? {
        if let explicit = options.incrementalCachePath {
            return IncrementalCompilationCache(cachePath: explicit)
        }
        return IncrementalCompilationCache.makeDefault(for: options)
    }

    /// Returns `true` when the rest of the pipeline can be skipped.
    private func prepareIncrementalPipeline(ctx: CompilationContext) -> Bool {
        guard let cache = ctx.incrementalCache else { return false }
        return PhaseTimer.measureSubPhase("incremental-prepare", timer: ctx.phaseTimer) {
            let allPaths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
            cache.computeCurrentFingerprints(for: allPaths, sourceManager: ctx.sourceManager)

            guard let recompileSet = cache.recompilationSet(allPaths: allPaths, options: ctx.options) else {
                // No compatible previous cache — full build.
                ctx.setIncrementalRecompileSet(nil)
                cache.recordOutcome(.full)
                return false
            }

            if recompileSet.isEmpty {
                if cache.restoreCachedOutput(for: ctx.options) {
                    // Replay the warnings the cached build emitted so a no-op
                    // run prints the same diagnostics a fresh build would.
                    for diagnostic in cache.loadPersistedDiagnostics() {
                        ctx.diagnostics.emit(diagnostic)
                    }
                    ctx.markIncrementalOutputRestored()
                    cache.recordOutcome(.restored)
                    return true
                }
                // Old caches did not persist output artifacts. Fall back to a
                // full build so the requested output is always produced.
                ctx.setIncrementalRecompileSet(nil)
                cache.recordOutcome(.full)
                return false
            }

            if recompileSet.count < allPaths.count,
               let frontendState = cache.loadFrontendState(for: ctx.options) {
                ctx.setIncrementalRecompileSet(recompileSet)
                ctx.interner.preload(frontendState.internerValues)
                ctx.installIncrementalFrontendState(frontendState)
                cache.recordOutcome(.partial)
            } else {
                // Old caches can compute a recompilation set from deps.json, but
                // cannot safely skip unchanged files without reusable frontend
                // state; a set covering every file has nothing to reuse either.
                // Fall back to a full build and refresh the cache.
                ctx.setIncrementalRecompileSet(nil)
                cache.recordOutcome(.full)
            }
            return false
        }
    }

    private func prepareContext(options: CompilerOptions, generatedTestRun: Bool = false) -> PreparedRunContext {
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: KklibSemaSession.makeInterner(options: options) ?? StringInterner()
        )

        let timePhasesEnabled = options.frontendFlags.contains("time-phases")
        if timePhasesEnabled {
            context.installPhaseTimer(PhaseTimer())
        }

        let incrementalEnabled = isIncrementalEnabled(
            options: options, generatedTestRun: generatedTestRun
        )
        if incrementalEnabled, let cache = resolveIncrementalCache(options: options) {
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
                    // BuildAST diagnostics are validation errors on an
                    // otherwise complete AST (e.g. a duplicate companion
                    // object). Keep going into Sema so semantic diagnostics
                    // are still reported alongside them, like kotlinc — the
                    // test pipeline already runs Sema unconditionally.
                    if phase is BuildASTPhase { continue }
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
            if let ast = ctx.ast {
                let declarations = DeclarationGraphBuilder.build(
                    ast: ast, sourceManager: ctx.sourceManager, interner: ctx.interner
                )
                depGraph.declarationGraph = declarations
                if ctx.options.frontendFlags.contains("incremental-stats") {
                    let line: String
                    if let previous = cache.dependencyGraph?.declarationGraph {
                        let invalidated = declarations.invalidated(since: previous).count
                        line = "declarations: total=\(declarations.units.count) invalidated=\(invalidated)\n"
                    } else {
                        line = "declarations: total=\(declarations.units.count) invalidated=all (no previous graph)\n"
                    }
                    FileHandle.standardError.write(Data(line.utf8))
                }
            }
            let buildHash = cache.buildConfigurationHash(for: ctx.options)
            let frontendState = IncrementalFrontendState(context: ctx, buildConfigurationHash: buildHash)
            cache.saveState(
                dependencyGraph: depGraph,
                options: ctx.options,
                frontendState: frontendState,
                diagnostics: ctx.diagnostics.diagnostics
            )
        }

        if printDiagnostics {
            ctx.diagnostics.printDiagnostics(format: ctx.options.diagnosticsFormat, from: ctx.sourceManager)
        }

        if ctx.options.frontendFlags.contains("incremental-stats"),
           let cache = ctx.incrementalCache {
            let line = cache.incrementalStatsSummary() + "\n"
            FileHandle.standardError.write(Data(line.utf8))
        }

        if timePhasesEnabled, let timer = ctx.phaseTimer {
            timer.printSummary()
            if let attribution = ctx.typeCheckAttribution {
                FileHandle.standardError.write(Data(attribution.summary().utf8))
            }
        }

        return (ctx.diagnostics.hasError ? 1 : 0, ctx.diagnostics.diagnostics)
    }

    /// `--run`: execute the lowered KIR in-process when the interpreter models
    /// the whole program, otherwise compile natively and run the executable.
    /// Returns the program's exit code, or nil when compilation failed (the
    /// diagnostics already carry the error).
    private func runImmediately(ctx: CompilationContext) -> Int? {
        switch KIRInterpreter.run(context: ctx) {
        case let .completed(stdout):
            FileHandle.standardOutput.write(Data(stdout.utf8))
            return 0
        case let .fallback(reason):
            FileHandle.standardError.write(Data("kswiftc: --run falling back to native execution (\(reason))\n".utf8))
        }
        executePhases(ctx: ctx, phases: backendPhases(), incrementalEnabled: false)
        let isTemporaryOutput = ctx.options.frontendFlags.contains("run-temp-output")
        defer {
            if isTemporaryOutput { try? FileManager.default.removeItem(atPath: ctx.options.outputPath) }
        }
        guard !ctx.diagnostics.hasError else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ctx.options.outputPath)
        do {
            try process.run()
        } catch {
            ctx.diagnostics.error("KSWIFTK-PIPELINE-0004", "Could not run '\(ctx.options.outputPath)': \(error)", range: nil)
            return nil
        }
        process.waitUntilExit()
        return Int(process.terminationStatus)
    }

    /// Runs outside `executePhases`, so it opens its own top-level phase to
    /// keep dump cost visible in `time-phases` next to the phases it follows.
    func emitKIRDump(ctx: CompilationContext) {
        ctx.phaseTimer?.beginPhase("KIRDump")
        defer { ctx.phaseTimer?.endPhase() }
        guard let kir = ctx.kir else {
            ctx.diagnostics.error("KSWIFTK-PIPELINE-0003", "KIR not available for dump.", range: nil)
            return
        }
        let path = IncrementalCompilationCache.outputArtifactPath(for: ctx.options)
        do {
            // Rendering and writing interleave, so "render" spans both and
            // "write" accumulates just the chunk writes inside it.
            try withSubPhaseTiming("render", timer: ctx.phaseTimer) {
                try Self.writeReplacingAtomically(path: path) { handle in
                    try kir.dump(
                        interner: ctx.interner,
                        symbols: ctx.sema?.symbols,
                        chunkBytes: Self.kirDumpChunkBytes
                    ) { chunk in
                        try withSubPhaseTiming("write", timer: ctx.phaseTimer, accumulating: true) {
                            try handle.write(contentsOf: Data(chunk.utf8))
                        }
                    }
                }
            }
        } catch {
            ctx.diagnostics.error("KSWIFTK-PIPELINE-0003", "Could not write KIR dump: \(error)", range: nil)
        }
    }

    /// Large enough that write syscalls stay rare, small enough that the dump
    /// never holds more than one chunk beyond what it is rendering.
    static let kirDumpChunkBytes = 1 << 20

    /// Same guarantee as `write(atomically: true)` without staging through
    /// the system replacement directory: write a sibling temp file, then
    /// rename it over the destination.
    static func writeReplacingAtomically(path: String, _ body: (FileHandle) throws -> Void) throws {
        let tempPath = path + ".tmp.\(UUID().uuidString)"
        guard FileManager.default.createFile(atPath: tempPath, contents: nil),
              let handle = FileHandle(forWritingAtPath: tempPath)
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tempPath])
        }
        do {
            try body(handle)
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(atPath: tempPath)
            throw error
        }
        guard rename(tempPath, path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(atPath: tempPath)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

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
                for initBlock in entry.initBlocks {
                    collectFunctionBodyDependencies(
                        initBlock,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
                for memberID in entry.memberFunctions + entry.memberProperties + entry.nestedClasses {
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
                if let initializer = backingField.initializer {
                    collectExprDependencies(
                        exprID: initializer,
                        ast: ast,
                        interner: interner,
                        availableSymbols: availableSymbols,
                        depended: &depended
                    )
                }
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

        func collectExpr(_ exprID: ExprID) {
            collectExprDependencies(exprID: exprID, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }

        func collectTypeRef(_ typeRefID: TypeRefID) {
            collectTypeRefDependencies(typeRefID: typeRefID, ast: ast, interner: interner, depended: &depended)
        }

        func collectTypeArgs(_ typeArgs: [TypeRefID]) {
            for typeArg in typeArgs {
                collectTypeRef(typeArg)
            }
        }

        func collectCallArgs(_ arguments: [CallArgument]) {
            collectCallArguments(arguments, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }

        func collectDecl(_ declID: DeclID) {
            collectDeclDependencies(declID: declID, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }

        func collectBody(_ body: FunctionBody) {
            collectFunctionBodyDependencies(body, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }

        func collectParams(_ params: [ValueParamDecl]) {
            collectValueParameterDependencies(params, ast: ast, interner: interner, availableSymbols: availableSymbols, depended: &depended)
        }

        func collectTypeParams(_ params: [TypeParamDecl]) {
            collectTypeParameterDependencies(params, ast: ast, interner: interner, depended: &depended)
        }

        switch expr {
        case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral,
             .stringLiteral, .breakExpr, .continueExpr, .thisRef:
            break
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(expression) = part {
                    collectExpr(expression)
                }
            }
        case let .nameRef(name, _):
            collectName(name)
        case let .forExpr(_, iterable, body, _, _), let .forDestructuringExpr(_, iterable, body, _, _):
            collectExpr(iterable)
            collectExpr(body)
        case let .whileExpr(condition, body, _, _), let .doWhileExpr(body, condition, _, _):
            collectExpr(condition)
            collectExpr(body)
        case let .localDecl(_, _, typeAnnotation, initializer, _, _, _):
            if let typeAnnotation {
                collectTypeRef(typeAnnotation)
            }
            if let initializer {
                collectExpr(initializer)
            }
        case let .localAssign(_, value, _), let .throwExpr(value, _), let .returnExpr(value: value?, _, _):
            collectExpr(value)
        case .returnExpr(value: nil, _, _):
            break
        case let .memberAssign(receiver, callee, value, _),
             let .safeMemberAssign(receiver, callee, value, _):
            collectName(callee)
            collectExpr(receiver)
            collectExpr(value)
        case let .indexedAssign(receiver, indices, value, _):
            collectExpr(receiver)
            for index in indices {
                collectExpr(index)
            }
            collectExpr(value)
        case let .call(callee, typeArgs, args, _):
            collectTypeArgs(typeArgs)
            collectExpr(callee)
            collectCallArgs(args)
        case let .memberCall(receiver, callee, typeArgs, args, _), let .safeMemberCall(receiver, callee, typeArgs, args, _):
            collectName(callee)
            collectTypeArgs(typeArgs)
            collectExpr(receiver)
            collectCallArgs(args)
        case let .indexedAccess(receiver, indices, _):
            collectExpr(receiver)
            for index in indices {
                collectExpr(index)
            }
        case let .binary(_, lhs, rhs, _), let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            collectExpr(lhs)
            collectExpr(rhs)
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject {
                collectExpr(subject)
            }
            for branch in branches {
                for condition in branch.conditions {
                    collectExpr(condition)
                }
                if let guardExpr = branch.guard_ {
                    collectExpr(guardExpr)
                }
                collectExpr(branch.body)
            }
            if let elseExpr {
                collectExpr(elseExpr)
            }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            collectExpr(condition)
            collectExpr(thenExpr)
            if let elseExpr {
                collectExpr(elseExpr)
            }
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            collectExpr(body)
            for clause in catchClauses {
                collectExpr(clause.body)
                if let paramType = clause.paramType {
                    collectTypeRef(paramType)
                }
            }
            if let finallyExpr {
                collectExpr(finallyExpr)
            }
        case let .unaryExpr(_, operand, _), let .nullAssert(operand, _):
            collectExpr(operand)
        case let .isCheck(expression, type, _, _), let .asCast(expression, type, _, _):
            collectExpr(expression)
            collectTypeRef(type)
        case let .compoundAssign(_, _, value, _):
            collectExpr(value)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            collectExpr(receiver)
            for index in indices {
                collectExpr(index)
            }
            collectExpr(value)
        case let .memberCompoundAssign(_, receiver, callee, value, _):
            collectName(callee)
            collectExpr(receiver)
            collectExpr(value)
        case let .lambdaLiteral(_, body, _, _):
            collectExpr(body)
        case let .objectLiteral(superTypes, decl, _):
            for superType in superTypes {
                collectTypeRef(superType)
            }
            if let decl {
                collectDecl(decl)
            }
        case let .callableRef(receiver, member, _):
            collectName(member)
            if let receiver {
                collectExpr(receiver)
            }
        case let .localFunDecl(_, receiverType, valueParams, returnType, body, _, _, typeParams, _):
            if let receiverType {
                collectTypeRef(receiverType)
            }
            collectTypeParams(typeParams)
            collectParams(valueParams)
            if let returnType {
                collectTypeRef(returnType)
            }
            collectBody(body)
        case let .localNominalDecl(declID, _):
            collectDecl(declID)
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                collectExpr(statement)
            }
            if let trailingExpr {
                collectExpr(trailingExpr)
            }
        case let .superRef(interfaceQualifier, label, _):
            if let interfaceQualifier {
                collectName(interfaceQualifier)
            }
            if let label {
                collectName(label)
            }
        case let .destructuringDecl(_, _, initializer, _):
            collectExpr(initializer)
        }
    }

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
