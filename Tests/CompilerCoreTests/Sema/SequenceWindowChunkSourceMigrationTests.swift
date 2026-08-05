@testable import CompilerCore
import Testing

@Suite
struct SequenceWindowChunkSourceMigrationTests {

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // migratedSequenceWindowChunkFunctionsAreBundledSourceDefinitions
            """
            package sample0
            fun noop() {}
            """,
            // sequenceWindowChunkSyntheticBridgesRetainRuntimeLinks
            """
            package sample1
            fun noop() {}
            """,
            // migratedSequenceWindowChunkFunctionsDoNotKeepPublicRuntimeLinkedMembers
            """
            package sample2
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === migratedSequenceWindowChunkFunctionsAreBundledSourceDefinitions ===

            do {

                let sample0Path = paths[0]

                let source = sources[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let packageFQName = ["kotlin", "sequences"].map(interner.intern)
                let expectedArities: [String: Set<Int>] = [
                    "take": [1],
                    "takeWhile": [1],
                    "drop": [1],
                    "dropWhile": [1],
                    "chunked": [1, 2],
                    "windowed": [3, 4],
                    "zip": [1, 2],
                    "zipWithNext": [0, 1],
                    "distinct": [0],
                    "distinctBy": [1],
                ]

                for (name, arities) in expectedArities {
                    let fqName = packageFQName + [interner.intern(name)]
                    let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              !symbol.flags.contains(.synthetic),
                              let fileID = sema.symbols.sourceFileID(for: symbolID)
                        else {
                            return false
                        }
                        return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/sequences/SequenceWindowChunk.kt"
                    }
                    let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                        sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
                    })

                    #expect(
                        arities.isSubset(of: registeredArities),
                        "Expected \(name) bundled source overloads \(arities), got \(registeredArities)"
                    )
                    #expect(
                        sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil },
                        "Expected \(name) bundled source definitions to be Sequence extension functions"
                    )
                    #expect(
                        sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                        "Expected \(name) bundled source definitions to avoid direct C external links"
                    )
                }

            }

            // === sequenceWindowChunkSyntheticBridgesRetainRuntimeLinks ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let sequenceFQName = ["kotlin", "sequences", "Sequence"].map(interner.intern)
                let expectedLinks: [String: String] = [
                    "__kk_sequence_take": "kk_sequence_take",
                    "__kk_sequence_takeWhile": "kk_sequence_takeWhile",
                    "__kk_sequence_drop": "kk_sequence_drop",
                    "__kk_sequence_dropWhile": "kk_sequence_dropWhile",
                    "__kk_sequence_chunked": "kk_sequence_chunked",
                    "__kk_sequence_chunked_transform": "kk_sequence_chunked_transform",
                    "__kk_sequence_windowed": "kk_sequence_windowed",
                    "__kk_sequence_windowed_transform": "kk_sequence_windowed_transform",
                    "__kk_sequence_zip": "kk_sequence_zip",
                    "__kk_sequence_zip_transform": "kk_sequence_zip_transform",
                    "__kk_sequence_zipWithNext": "kk_sequence_zipWithNext",
                    "__kk_sequence_zipWithNextTransform": "kk_sequence_zipWithNextTransform",
                    "__kk_sequence_distinct": "kk_sequence_distinct",
                    "__kk_sequence_distinctBy": "kk_sequence_distinctBy",
                ]

                for (name, expectedLink) in expectedLinks {
                    let fqName = sequenceFQName + [interner.intern(name)]
                    let links = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                        sema.symbols.externalLinkName(for: $0)
                    })
                    #expect(links.contains(expectedLink), "Expected \(name) bridge to link to \(expectedLink)")
                }

            }

            // === migratedSequenceWindowChunkFunctionsDoNotKeepPublicRuntimeLinkedMembers ===

            do {

                let sample2Path = paths[2]

                let source = sources[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let sequenceFQName = ["kotlin", "sequences", "Sequence"].map(interner.intern)
                let disallowedMemberLinks: [String: Set<String>] = [
                    "take": ["kk_sequence_take"],
                    "takeWhile": ["kk_sequence_takeWhile"],
                    "drop": ["kk_sequence_drop"],
                    "dropWhile": ["kk_sequence_dropWhile"],
                    "chunked": ["kk_sequence_chunked", "kk_sequence_chunked_transform"],
                    "windowed": ["kk_sequence_windowed", "kk_sequence_windowed_transform"],
                    "zip": ["kk_sequence_zip", "kk_sequence_zip_transform"],
                    "zipWithNext": ["kk_sequence_zipWithNext", "kk_sequence_zipWithNextTransform"],
                    "distinct": ["kk_sequence_distinct"],
                    "distinctBy": ["kk_sequence_distinctBy"],
                ]

                for (name, disallowedLinks) in disallowedMemberLinks {
                    let fqName = sequenceFQName + [interner.intern(name)]
                    let memberLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                        sema.symbols.externalLinkName(for: $0)
                    })
                    let leakedLinks = memberLinks.intersection(disallowedLinks)
                    #expect(
                        leakedLinks.isEmpty,
                        "Expected \(name) to be served by bundled source, but found public member links \(leakedLinks)"
                    )
                }

                let oldZipWithNextTransformFQName = sequenceFQName
                    + [interner.intern("zipWithNext"), interner.intern("transform")]
                let oldZipWithNextTransformLinks = Set(
                    sema.symbols.lookupAll(fqName: oldZipWithNextTransformFQName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    !oldZipWithNextTransformLinks.contains("kk_sequence_zipWithNextTransform"),
                    "Expected zipWithNext(transform) to be served by bundled source"
                )

            }

        }
    }

}
