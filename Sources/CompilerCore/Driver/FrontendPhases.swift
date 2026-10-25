import Foundation

final class LockedIndexedResults<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element?]

    init(count: Int) {
        values = Array(repeating: nil, count: count)
    }

    func store(_ value: Element, at index: Int) {
        lock.lock()
        values[index] = value
        lock.unlock()
    }

    func orderedResults() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return values.enumerated().map { index, value in
            guard let value else {
                preconditionFailure("Missing parallel result at index \(index).")
            }
            return value
        }
    }
}

private func collectPerFileResultsInParallel<Result: Sendable>(
    fileIDs: [FileID],
    task: @escaping @Sendable (FileID) -> Result
) -> [(FileID, Result)] {
    let count = fileIDs.count
    guard count > 0 else { return [] }
    let results = LockedIndexedResults<Result>(count: count)
    DispatchQueue.concurrentPerform(iterations: count) { index in
        results.store(task(fileIDs[index]), at: index)
    }
    let orderedResults = results.orderedResults()
    return zip(fileIDs, orderedResults).sorted(by: { $0.0.rawValue < $1.0.rawValue })
}

private func isBundledStdlibFile(_ fileID: FileID, sourceManager: SourceManager) -> Bool {
    sourceManager.origin(of: fileID)?.isBundledStdlib == true
}

private func remapTokenKind(
    _ kind: TokenKind,
    localToShared: [InternedString]
) -> TokenKind {
    func remap(_ value: InternedString) -> InternedString {
        let index = Int(value.rawValue)
        precondition(index >= 0 && index < localToShared.count, "Invalid lexer-local interned string ID.")
        return localToShared[index]
    }

    switch kind {
    case let .identifier(value):
        return .identifier(remap(value))
    case let .backtickedIdentifier(value):
        return .backtickedIdentifier(remap(value))
    case let .stringSegment(value):
        return .stringSegment(remap(value))
    case let .missing(expected):
        return .missing(expected: remapTokenKind(expected, localToShared: localToShared))
    default:
        return kind
    }
}

private func remapTokens(
    _ tokens: [Token],
    localStrings: [String],
    into sharedInterner: StringInterner
) -> [Token] {
    let localToShared = localStrings.map(sharedInterner.intern)
    return tokens.map { token in
        Token(
            kind: remapTokenKind(token.kind, localToShared: localToShared),
            range: token.range,
            leadingTrivia: token.leadingTrivia,
            trailingTrivia: token.trailingTrivia
        )
    }
}

private func collectPerFileResultsWithBundledStdlibTiming<Result: Sendable>(
    fileIDs: [FileID],
    sourceManager: SourceManager,
    phaseTimer: PhaseTimer?,
    task: @escaping @Sendable (FileID) -> Result
) -> [(FileID, Result)] {
    guard let phaseTimer else {
        return collectPerFileResultsInParallel(fileIDs: fileIDs, task: task)
    }

    var bundledFileIDs: [FileID] = []
    var otherFileIDs: [FileID] = []
    for fileID in fileIDs {
        if isBundledStdlibFile(fileID, sourceManager: sourceManager) {
            bundledFileIDs.append(fileID)
        } else {
            otherFileIDs.append(fileID)
        }
    }
    guard !bundledFileIDs.isEmpty else {
        return collectPerFileResultsInParallel(fileIDs: fileIDs, task: task)
    }

    let startTime = DispatchTime.now().uptimeNanoseconds
    let bundledResults = collectPerFileResultsInParallel(fileIDs: bundledFileIDs, task: task)
    let endTime = DispatchTime.now().uptimeNanoseconds
    phaseTimer.recordSubPhase("bundled-stdlib", startTime: startTime, endTime: endTime)

    let otherResults = collectPerFileResultsInParallel(fileIDs: otherFileIDs, task: task)
    return (bundledResults + otherResults).sorted(by: { $0.0.rawValue < $1.0.rawValue })
}

public final class LoadSourcesPhase: CompilerPhase {
    public static let name = "LoadSources"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.inputs.isEmpty && !ctx.options.stdlibOnly {
            ctx.diagnostics.error(
                "KSWIFTK-SOURCE-0001",
                "No input files were specified.",
                range: nil
            )
            throw CompilerPipelineError.loadError
        }

        if let stdlibLibraryPath = ctx.options.stdlibLibraryPath {
            try validateStdlibLibraryPath(stdlibLibraryPath, ctx: ctx)
        }

        if ctx.options.includeStdlib {
            try injectBundledStdlib(into: ctx)
        }

        for path in ctx.options.inputs {
            if ctx.sourceManager.containsFile(path: path) { continue }
            do {
                _ = try ctx.sourceManager.addFile(path: path)
            } catch {
                ctx.diagnostics.error(
                    "KSWIFTK-SOURCE-0002",
                    "Cannot read input file: \(path)",
                    range: nil
                )
                throw CompilerPipelineError.loadError
            }
        }
    }

    internal func injectBundledStdlib(
        into ctx: CompilationContext,
        resourcePath: String? = Bundle.module.resourcePath
    ) throws {
        do {
            let sources = try BundledStdlib.collectBundledStdlibSources(
                resourcePath: resourcePath,
                profile: ctx.options.stdlibProfile,
                forWasmTarget: ctx.options.target.isWasm
            )
            for source in sources {
                guard !ctx.sourceManager.containsFile(path: source.path) else { continue }
                _ = ctx.sourceManager.addFile(path: source.path, contents: source.contents, origin: .bundledStdlib)
            }
        } catch let error as BundledStdlib.LoadError {
            switch error {
            case .resourcePathMissing, .resourceDirectoryMissing:
                ctx.diagnostics.error(
                    "KSWIFTK-SOURCE-0101",
                    error.description,
                    range: nil
                )
            case .enumerationFailed, .readFailed, .templateExpansionFailed:
                ctx.diagnostics.error(
                    "KSWIFTK-SOURCE-0102",
                    error.description,
                    range: nil
                )
            }
            throw CompilerPipelineError.loadError
        }
    }

    private func validateStdlibLibraryPath(_ path: String, ctx: CompilationContext) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            ctx.diagnostics.error(
                "KSWIFTK-SOURCE-0103",
                "Stdlib library path does not exist or is not a directory: \(path)",
                range: nil
            )
            throw CompilerPipelineError.loadError
        }
        let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestPath) else {
            ctx.diagnostics.error(
                "KSWIFTK-SOURCE-0103",
                "Stdlib library is missing manifest.json: \(path)",
                range: nil
            )
            throw CompilerPipelineError.loadError
        }
    }

}

public final class LexPhase: CompilerPhase {
    public static let name = "Lex"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let fileIDs = ctx.sourceManager.fileIDs()
            .filter { ctx.needsRecompilation(fileID: $0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
        let interner = ctx.interner
        let diagnostics = ctx.diagnostics
        let sourceManager = ctx.sourceManager

        // Each lexer uses a private interner so worker scheduling cannot assign
        // process-visible IDs. Merge into the shared interner below in file order.
        let lexedByFile = collectPerFileResultsWithBundledStdlibTiming(
            fileIDs: fileIDs,
            sourceManager: sourceManager,
            phaseTimer: ctx.phaseTimer
        ) { fileID in
            let localInterner = StringInterner()
            let contents = sourceManager.contents(of: fileID)
            let lexer = KotlinLexer(
                file: fileID,
                source: contents,
                interner: localInterner,
                diagnostics: diagnostics
            )
            return (tokens: lexer.lexAll(), localStrings: localInterner.snapshotValues())
        }
        let tokensByFile = lexedByFile.map { fileID, lexed in
            (
                fileID,
                remapTokens(
                    lexed.tokens,
                    localStrings: lexed.localStrings,
                    into: interner
                )
            )
        }

        var allTokens: [Token] = []
        for (_, fileTokens) in tokensByFile {
            if let last = fileTokens.last, case .eof = last.kind {
                allTokens.append(contentsOf: fileTokens.dropLast())
            } else {
                allTokens.append(contentsOf: fileTokens)
            }
        }
        ctx.storeLexResults(allTokens: allTokens, tokensByFile: tokensByFile)

        ctx.diagnostics.sortBySourceLocation()
    }
}

public final class ParsePhase: CompilerPhase {
    public static let name = "Parse"

    /// Reject top-level statements in non-`.kts` user sources. Enabled by the
    /// compile pipelines; phase-level harnesses (golden dumps, parser tests)
    /// keep parsing script-shaped `.kt` fixtures without the diagnostic.
    private let rejectsTopLevelStatementsOutsideScripts: Bool

    public init(rejectsTopLevelStatementsOutsideScripts: Bool = false) {
        self.rejectsTopLevelStatementsOutsideScripts = rejectsTopLevelStatementsOutsideScripts
    }

    public func run(_ ctx: CompilationContext) throws {
        let interner = ctx.interner
        let diagnostics = ctx.diagnostics
        let tokensByFile = Dictionary(uniqueKeysWithValues: ctx.tokensByFile.map { ($0.0, $0.1) })
        let fileIDs = tokensByFile.keys.sorted(by: { $0.rawValue < $1.rawValue })
        let parsedByFile = collectPerFileResultsWithBundledStdlibTiming(
            fileIDs: fileIDs,
            sourceManager: ctx.sourceManager,
            phaseTimer: ctx.phaseTimer
        ) { fileID in
            let parser = KotlinParser(
                tokens: tokensByFile[fileID] ?? [],
                interner: interner,
                diagnostics: diagnostics
            )
            let parsed = parser.parseFile()
            return (parsed.arena, parsed.root)
        }
        let syntaxTrees = parsedByFile.map { fileID, parsed in
            (fileID, parsed.0, parsed.1)
        }

        if rejectsTopLevelStatementsOutsideScripts {
            reportTopLevelStatementsOutsideScripts(syntaxTrees, ctx: ctx)
        }

        ctx.storeSyntaxTrees(syntaxTrees)

        ctx.diagnostics.sortBySourceLocation()
    }
}

extension ParsePhase {
    /// Top-level statements make the parser pick script mode, which is only a
    /// valid compilation unit for `.kts` sources. In a regular `.kt` file
    /// kotlinc rejects every statement with "expecting a top level declaration",
    /// so a forgotten `fun main` can no longer become an executable by accident.
    private func reportTopLevelStatementsOutsideScripts(
        _ syntaxTrees: [(FileID, SyntaxArena, NodeID)],
        ctx: CompilationContext
    ) {
        for (fileID, arena, root) in syntaxTrees {
            guard arena.node(root).kind == .script,
                  ctx.sourceManager.origin(of: fileID) == .user,
                  !ctx.sourceManager.path(of: fileID).lowercased().hasSuffix(".kts") else { continue }
            for child in arena.children(of: root) {
                guard case let .node(nodeID) = child else { continue }
                switch arena.node(nodeID).kind {
                case .packageHeader, .importHeader, .importList, .classDecl, .interfaceDecl, .objectDecl,
                     .funDecl, .propertyDecl, .typeAliasDecl, .enumEntry:
                    continue
                default:
                    break
                }
                ctx.diagnostics.error(
                    "KSWIFTK-PARSE-0025",
                    "Expecting a top level declaration; top-level statements are only allowed in '.kts' script files.",
                    range: arena.node(nodeID).range
                )
            }
        }
    }
}

public final class BuildASTPhase: CompilerPhase {
    public static let name = "BuildAST"

    struct PerFileASTResult {
        let fileRawID: Int32
        let packageFQName: [InternedString]
        let imports: [ImportDecl]
        let topLevelDecls: [DeclID]
        let scriptBody: [ExprID]
        let annotations: [AnnotationNode]
        let range: SourceRange?
        let allDecls: [DeclID]
    }

    /// Cleared between files because different `SyntaxArena`s reuse the same
    /// `NodeID` space.
    var tokenCache: [NodeID: [Token]] = [:]

    let diagnostics: DiagnosticEngine?

    public init(diagnostics: DiagnosticEngine? = nil) {
        self.diagnostics = diagnostics
    }

    public func run(_ ctx: CompilationContext) throws {
        if ctx.syntaxTrees.isEmpty {
            if let cst = ctx.syntaxTree {
                let fileID: FileID = if let firstToken = ctx.tokens.first, firstToken.range.start.file != FileID.invalid {
                    firstToken.range.start.file
                } else {
                    FileID(rawValue: 0)
                }
                ctx.storeFallbackSyntaxTree(fileID: fileID, arena: cst, root: ctx.syntaxTreeRoot)
            } else {
                throw CompilerPipelineError.invalidInput("Parse phase did not run.")
            }
        }

        buildAndMergeFiles(ctx, jobs: ctx.frontendJobs)
        ctx.diagnostics.sortBySourceLocation()
    }

    private struct WorkerASTResult {
        let file: PerFileASTResult
        let arena: ASTArenaSnapshot
        let addedStrings: [String]
    }

    /// Every worker allocates in a private namespace. Publish only after all
    /// workers finish, in syntax-tree order, for the same IDs at every jobs count.
    private func buildAndMergeFiles(_ ctx: CompilationContext, jobs: Int) {
        let arena = makeArena(ctx)
        let baselineInterner = ctx.interner.makeWorkerInterner()
        let sharedStringCount = baselineInterner.snapshotValues().count
        let syntaxTrees = ctx.syntaxTrees
        let results = LockedIndexedResults<WorkerASTResult>(count: syntaxTrees.count)
        let buildFile: @Sendable (Int) -> Void = { index in
            let (fileID, cst, root) = syntaxTrees[index]
            let localArena = ASTArena()
            let localInterner = baselineInterner.makeWorkerInterner()
            let phase = BuildASTPhase(diagnostics: ctx.diagnostics)
            let file = phase.buildFileAST(
                fileID: fileID, cst: cst, root: root,
                interner: localInterner, arena: localArena
            )
            results.store(WorkerASTResult(
                file: file,
                arena: localArena.snapshot(),
                addedStrings: Array(localInterner.snapshotValues().dropFirst(sharedStringCount))
            ), at: index)
        }

        if jobs <= 1 {
            for index in syntaxTrees.indices {
                buildFile(index)
            }
        } else {
            let jobSemaphore = DispatchSemaphore(value: jobs)
            let completionGroup = DispatchGroup()
            for index in syntaxTrees.indices {
                jobSemaphore.wait()
                completionGroup.enter()
                DispatchQueue.global().async {
                    defer {
                        completionGroup.leave()
                        jobSemaphore.signal()
                    }
                    buildFile(index)
                }
            }
            completionGroup.wait()
        }

        let orderedResults = results.orderedResults().map { worker in
            let strings = worker.addedStrings.map(ctx.interner.intern)
            let remapper = arena.appendFileSnapshot(
                worker.arena, sharedStringCount: sharedStringCount, addedStrings: strings
            )
            let file = worker.file
            return PerFileASTResult(
                fileRawID: file.fileRawID,
                packageFQName: file.packageFQName.map { remapper.remap($0) },
                imports: file.imports.map { remapper.remap($0) },
                topLevelDecls: file.topLevelDecls.map { remapper.remap($0) },
                scriptBody: file.scriptBody.map { remapper.remap($0) },
                annotations: file.annotations.map { remapper.remap($0) },
                range: file.range,
                allDecls: file.allDecls.map { remapper.remap($0) }
            )
        }
        let merged = mergePerFileASTResults(orderedResults)
        finalizeAST(
            ctx: ctx,
            arena: arena,
            declarations: merged.declarations,
            packageByFile: merged.packageByFile,
            importsByFile: merged.importsByFile,
            declarationsByFile: merged.declarationsByFile,
            scriptExprsByFile: merged.scriptExprsByFile,
            annotationsByFile: merged.annotationsByFile,
            fileRangesByFile: merged.fileRangesByFile,
            allDeclsByFile: merged.allDeclsByFile
        )
    }

    private func makeArena(_ ctx: CompilationContext) -> ASTArena {
        if let state = ctx.incrementalFrontendState {
            return ASTArena(snapshot: state.arenaSnapshot)
        }
        return ASTArena()
    }


    func buildFileAST(
        fileID: FileID,
        cst: SyntaxArena,
        root: NodeID,
        interner: StringInterner,
        arena: ASTArena
    ) -> PerFileASTResult {
        let isScript = cst.node(root).kind == .script
        let fileRawID = fileID.rawValue
        var declarations: [DeclID] = []
        var packageFQName: [InternedString] = []
        var imports: [ImportDecl] = []
        var topLevelDecls: [DeclID] = []
        var scriptBody: [ExprID] = []
        // Top-level declarations materialized as real file-scope decls below;
        // passed to `blockExpressions` so script mode doesn't also nest them
        // as shadowing local decls inside the synthesized `main()` body.
        var materializedDeclNodeIDs: Set<NodeID> = []
        var pendingContextReceivers: [ContextReceiverDecl] = []
        let rootNode = cst.node(root)
        let fileAnnotations = declarationAnnotations(from: root, in: cst, interner: interner)
            .filter { $0.useSiteTarget == "file" }

        for child in cst.children(of: root) {
            guard case let .node(nodeID) = child else {
                continue
            }
            let node = cst.node(nodeID)
            let prefixedContextReceivers = node.kind == .statement ? [] : pendingContextReceivers
            if node.kind != .statement {
                pendingContextReceivers = []
            }

            switch node.kind {
            case .packageHeader:
                packageFQName = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: true)

            case .importHeader:
                imports.append(makeImportDecl(from: nodeID, in: cst, interner: interner))

            case .importList:
                for importChild in cst.children(of: nodeID) {
                    guard case let .node(importNodeID) = importChild else { continue }
                    guard cst.node(importNodeID).kind == .importHeader else { continue }
                    imports.append(makeImportDecl(from: importNodeID, in: cst, interner: interner))
                }

            case .classDecl:
                let decl = Decl.classDecl(makeClassDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)
                materializedDeclNodeIDs.insert(nodeID)

            case .interfaceDecl:
                let decl = Decl.interfaceDecl(makeInterfaceDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .objectDecl:
                let decl = Decl.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)
                materializedDeclNodeIDs.insert(nodeID)

            case .funDecl:
                let decl = Decl.funDecl(makeFunDecl(
                    from: nodeID, in: cst, interner: interner, astArena: arena,
                    prefixedContextReceivers: prefixedContextReceivers
                ))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)
                materializedDeclNodeIDs.insert(nodeID)

            case .propertyDecl where !isScript:
                let decl = Decl.propertyDecl(makePropertyDecl(
                    from: nodeID, in: cst, interner: interner, astArena: arena,
                    prefixedContextReceivers: prefixedContextReceivers
                ))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .typeAliasDecl:
                let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .enumEntry:
                let decl = Decl.enumEntryDecl(EnumEntryDecl(
                    range: node.range,
                    name: declarationName(from: nodeID, in: cst, interner: interner),
                    annotations: declarationAnnotations(from: nodeID, in: cst, interner: interner),
                    constructorArgs: []
                ))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            default:
                if node.kind == .statement {
                    let tokens = collectTokens(from: nodeID, in: cst)
                    let parsedContextReceivers = parseContextReceivers(
                        from: tokens, interner: interner, astArena: arena
                    )
                    if !parsedContextReceivers.isEmpty {
                        pendingContextReceivers = parsedContextReceivers
                    } else if tokens.first?.kind != .symbol(.at) {
                        pendingContextReceivers = []
                    }
                }
                continue
            }
        }

        if isScript {
            let scriptExprs = blockExpressions(
                from: root,
                in: cst,
                interner: interner,
                astArena: arena,
                excludingNodeIDs: materializedDeclNodeIDs
            )
            scriptBody = scriptExprs

            let mainName = interner.intern("main")
            let mainDecl = FunDecl(
                range: rootNode.range,
                name: mainName,
                modifiers: [],
                body: .block(scriptExprs, rootNode.range),
                isScriptEntryPoint: true
            )
            let declID = arena.appendDecl(.funDecl(mainDecl))
            declarations.append(declID)
            topLevelDecls.append(declID)
        }

        return PerFileASTResult(
            fileRawID: fileRawID,
            packageFQName: packageFQName,
            imports: imports,
            topLevelDecls: topLevelDecls,
            scriptBody: scriptBody,
            annotations: fileAnnotations,
            range: rootNode.range,
            allDecls: declarations
        )
    }

    private func appendDecl(
        _ decl: Decl,
        to arena: ASTArena,
        declarations: inout [DeclID],
        fileDecls: inout [DeclID]
    ) {
        let declID = arena.appendDecl(decl)
        declarations.append(declID)
        fileDecls.append(declID)
    }

    private func makeImportDecl(from nodeID: NodeID, in cst: SyntaxArena, interner: StringInterner) -> ImportDecl {
        let path = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: false)
        let alias = extractImportAlias(from: nodeID, in: cst, interner: interner)
        let isWildcard = collectTokens(from: nodeID, in: cst).contains { $0.kind == .symbol(.star) }
        return ImportDecl(range: cst.node(nodeID).range, path: path, alias: alias, isWildcard: isWildcard)
    }

    private func mergePerFileASTResults(_ results: [PerFileASTResult]) -> (
        declarations: [DeclID],
        packageByFile: [Int32: [InternedString]],
        importsByFile: [Int32: [ImportDecl]],
        declarationsByFile: [Int32: [DeclID]],
        scriptExprsByFile: [Int32: [ExprID]],
        annotationsByFile: [Int32: [AnnotationNode]],
        fileRangesByFile: [Int32: SourceRange?],
        allDeclsByFile: [Int32: [DeclID]]
    ) {
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]
        var scriptExprsByFile: [Int32: [ExprID]] = [:]
        var annotationsByFile: [Int32: [AnnotationNode]] = [:]
        var fileRangesByFile: [Int32: SourceRange?] = [:]
        var allDeclsByFile: [Int32: [DeclID]] = [:]

        for result in results.sorted(by: { $0.fileRawID < $1.fileRawID }) {
            declarations.append(contentsOf: result.allDecls)
            packageByFile[result.fileRawID] = result.packageFQName
            importsByFile[result.fileRawID] = result.imports
            declarationsByFile[result.fileRawID] = result.topLevelDecls
            annotationsByFile[result.fileRawID] = result.annotations
            fileRangesByFile[result.fileRawID] = result.range
            allDeclsByFile[result.fileRawID] = result.allDecls
            if !result.scriptBody.isEmpty {
                scriptExprsByFile[result.fileRawID] = result.scriptBody
            }
        }

        return (
            declarations: declarations,
            packageByFile: packageByFile,
            importsByFile: importsByFile,
            declarationsByFile: declarationsByFile,
            scriptExprsByFile: scriptExprsByFile,
            annotationsByFile: annotationsByFile,
            fileRangesByFile: fileRangesByFile,
            allDeclsByFile: allDeclsByFile
        )
    }


    private func finalizeAST(
        ctx: CompilationContext,
        arena: ASTArena,
        declarations: [DeclID],
        packageByFile: [Int32: [InternedString]],
        importsByFile: [Int32: [ImportDecl]],
        declarationsByFile: [Int32: [DeclID]],
        scriptExprsByFile: [Int32: [ExprID]],
        annotationsByFile: [Int32: [AnnotationNode]],
        fileRangesByFile: [Int32: SourceRange?],
        allDeclsByFile: [Int32: [DeclID]]
    ) {
        if let state = ctx.incrementalFrontendState {
            finalizeIncrementalAST(
                ctx: ctx,
                state: state,
                arena: arena,
                packageByFile: packageByFile,
                importsByFile: importsByFile,
                declarationsByFile: declarationsByFile,
                scriptExprsByFile: scriptExprsByFile,
                annotationsByFile: annotationsByFile,
                fileRangesByFile: fileRangesByFile,
                allDeclsByFile: allDeclsByFile
            )
            return
        }

        let fileIDs = ctx.syntaxTrees.map(\.0.rawValue).filter { $0 != FileID.invalid.rawValue }
        let uniqueFileIDs = Array(Set(fileIDs)).sorted()
        let files: [ASTFile] = uniqueFileIDs.map { rawID in
            ASTFile(
                fileID: FileID(rawValue: rawID),
                packageFQName: packageByFile[rawID] ?? [],
                imports: importsByFile[rawID] ?? [],
                topLevelDecls: declarationsByFile[rawID] ?? [],
                scriptBody: scriptExprsByFile[rawID] ?? [],
                annotations: annotationsByFile[rawID] ?? [],
                range: fileRangesByFile[rawID] ?? nil
            )
        }

        let totalTokenCount: Int = if !ctx.tokensByFile.isEmpty {
            ctx.tokensByFile.reduce(0) { $0 + $1.1.count }
        } else {
            ctx.tokens.count
        }

        ctx.storeAST(ASTModule(
            files: files,
            arena: arena,
            declarationCount: declarations.count,
            tokenCount: totalTokenCount,
            activeDeclsByFileRawID: allDeclsByFile
        ))
    }

    private func finalizeIncrementalAST(
        ctx: CompilationContext,
        state: IncrementalFrontendState,
        arena: ASTArena,
        packageByFile: [Int32: [InternedString]],
        importsByFile: [Int32: [ImportDecl]],
        declarationsByFile: [Int32: [DeclID]],
        scriptExprsByFile: [Int32: [ExprID]],
        annotationsByFile: [Int32: [AnnotationNode]],
        fileRangesByFile: [Int32: SourceRange?],
        allDeclsByFile: [Int32: [DeclID]]
    ) {
        let changedRawIDs = Set(ctx.syntaxTrees.map(\.0.rawValue))
        var activeDeclsByFile = state.activeDeclsByFileRawID
        var tokenCountsByFile = state.tokenCountsByFileRawID

        let tokenCountByFileID = Dictionary(uniqueKeysWithValues: ctx.tokensByFile.map { ($0.0, $0.1.count) })
        let changedFiles: [ASTFile] = changedRawIDs.sorted().map { rawID in
            activeDeclsByFile[rawID] = allDeclsByFile[rawID] ?? []
            let fileID = FileID(rawValue: rawID)
            if let tokenCount = tokenCountByFileID[fileID] {
                tokenCountsByFile[rawID] = tokenCount
            }
            return ASTFile(
                fileID: fileID,
                packageFQName: packageByFile[rawID] ?? [],
                imports: importsByFile[rawID] ?? [],
                topLevelDecls: declarationsByFile[rawID] ?? [],
                scriptBody: scriptExprsByFile[rawID] ?? [],
                annotations: annotationsByFile[rawID] ?? [],
                range: fileRangesByFile[rawID] ?? nil
            )
        }

        let reusedFiles = state.files.filter { !changedRawIDs.contains($0.fileID.rawValue) }
        let files = (reusedFiles + changedFiles).sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })
        let currentRawIDs = Set(ctx.sourceManager.fileIDs().map(\.rawValue))
        activeDeclsByFile = activeDeclsByFile.filter { currentRawIDs.contains($0.key) }
        tokenCountsByFile = tokenCountsByFile.filter { currentRawIDs.contains($0.key) }
        let declarationCount = activeDeclsByFile.values.reduce(0) { $0 + $1.count }
        let totalTokenCount = tokenCountsByFile.values.reduce(0, +)

        ctx.storeAST(ASTModule(
            files: files,
            arena: arena,
            declarationCount: declarationCount,
            tokenCount: totalTokenCount,
            activeDeclsByFileRawID: activeDeclsByFile
        ))
    }
}
