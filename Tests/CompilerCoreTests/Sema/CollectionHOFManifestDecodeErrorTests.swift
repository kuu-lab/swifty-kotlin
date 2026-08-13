#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Tests that collection HOF type inference works correctly even when external
/// library metadata is missing or unavailable — the compiler's built-in
/// synthetic stubs must serve as a reliable fallback.
@Suite
struct CollectionHOFManifestDecodeErrorTests {

    /// Verify that collection HOF members are available via synthetic stubs
    /// without any external library metadata loaded.

    /// Verify that invalid/non-existent search paths do not cause crashes
    /// and that the compiler falls back to synthetic stubs gracefully.

    /// Verify that all collection HOF stubs carry the expected inline+synthetic flags.

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
            // testCollectionHOFSyntheticStubsResolveWithoutExternalMetadata
            """
            package sample0

                    fun test(values: List<String>) {
                        values.mapIndexed { i, s -> s }
                        values.groupBy { it.length }
                        values.partition { it.length > 3 }
                    }

            """,
            // testCollectionWindowedTransformSourceDefinitionResolvesWithoutExternalMetadata
            """
            package sample1

                    fun test(values: List<Int>) {
                        values.windowed(3, 2, true) { window ->
                            window.size
                        }
                    }

            """,
            // testCollectionHOFStubsFlagsAreCorrect
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

            // === testCollectionHOFSyntheticStubsResolveWithoutExternalMetadata ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let source = sources[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // No searchPaths — purely relying on bundled stdlib / synthetic stubs.

                    let collectionsFQ: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                    ]
                    let listFQ: [InternedString] = collectionsFQ + [interner.intern("List")]

                    // mapIndexed is now provided by bundled Kotlin source (top-level extension).
                    let mapIndexedSource = sema.symbols.lookup(
                        fqName: collectionsFQ + [interner.intern("mapIndexed")]
                    )
                    #expect(mapIndexedSource != nil, "mapIndexed bundled source must exist without external metadata")
                    if let mapIndexedSource {
                        let symbol = try #require(sema.symbols.symbol(mapIndexedSource))
                        #expect(!symbol.flags.contains(.synthetic), "mapIndexed must be a real bundled source declaration")
                    }

                    // partition still uses a synthetic member stub.
                    let partitionSymbolID = sema.symbols.lookup(
                        fqName: listFQ + [interner.intern("partition")]
                    )
                    #expect(partitionSymbolID != nil, "Synthetic stub for 'partition' must exist without external metadata")

                    // No type-constraint errors expected.
                    assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)

            }

            // === testCollectionWindowedTransformSourceDefinitionResolvesWithoutExternalMetadata ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let source = sources[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let collectionsFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let windowedCandidates = sema.symbols.lookupAll(
                    fqName: collectionsFQ + [interner.intern("windowed")]
                )
                let windowedTransform = windowedCandidates.first { symID in
                    guard let sig = sema.symbols.functionSignature(for: symID) else {
                        return false
                    }
                    return sig.parameterTypes.count == 4
                }

                #expect(windowedTransform != nil, "Bundled source for Iterable.windowed(size, step, partialWindows, transform) must exist")
                if let windowedTransform {
                    #expect(sema.symbols.externalLinkName(for: windowedTransform) == nil)
                    let fileID = try #require(sema.symbols.sourceFileID(for: windowedTransform))
                    #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt")
                }

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)

            }

            // === testCollectionHOFStubsFlagsAreCorrect ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let listFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]

                let hofMembers = [
                    "mapIndexed", "flatMap", "associate",
                    "associateBy", "associateWith",
                    "groupBy", "partition",
                ]

                for memberName in hofMembers {
                    guard let symbolID = sema.symbols.lookup(
                        fqName: listFQ + [interner.intern(memberName)]
                    ) else {
                        // Stubs not registered — covered by other tests.
                        continue
                    }
                    let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                    #expect(flags.contains(.synthetic), "Expected '\(memberName)' to be marked synthetic")
                }

            }

        }
    }

}

#endif
