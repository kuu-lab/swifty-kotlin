#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-PATH-FN-039: kotlin.io.path.PathWalkOption enum
//
// Focused coverage for the synthetic `kotlin.io.path.PathWalkOption` enum class.
// The enum is registered by `HeaderHelpers+SyntheticPathStubs+TypeCreation.swift`
// via `ensurePathWalkOptionEnum`, and its two entries (BREADTH_FIRST, FOLLOW_LINKS)
// are exposed as fields whose `propertyType` is the enum class type itself so that
// `PathWalkOption.BREADTH_FIRST`-style member references resolve through
// `resolveClassNameMemberValue`.

@Suite
struct PathWalkOptionEnumTests {

    // MARK: Helpers
    private static let allEntries = ["BREADTH_FIRST", "FOLLOW_LINKS"]

    // MARK: - Enum class declaration shape

    // MARK: - Enum entries

    // MARK: - Member resolution in source

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
            // testPathWalkOptionIsRegisteredAsEnumClass
            """
            package sample0
            fun noop() {}
            """,
            // testPathWalkOptionIsParentedToKotlinIOPathPackage
            """
            package sample1
            fun noop() {}
            """,
            // testPathWalkOptionHasCorrectPropertyType
            """
            package sample2
            fun noop() {}
            """,
            // testBothPathWalkOptionEntriesAreRegisteredAsFields
            """
            package sample3
            fun noop() {}
            """,
            // testPathWalkOptionEntryPropertyTypesAreEnumType
            """
            package sample4
            fun noop() {}
            """,
            // testPathWalkOptionEntriesAreParentedToEnumClass
            """
            package sample5
            fun noop() {}
            """,
            // testPathWalkOptionHasExactlyTwoEntries
            """
            package sample6
            fun noop() {}
            """,
            // testPathWalkOptionMemberAccessResolves
            """
            package sample7

                    import kotlin.io.path.PathWalkOption

                    fun pickBreadthFirst(): PathWalkOption = PathWalkOption.BREADTH_FIRST
                    fun pickFollowLinks(): PathWalkOption = PathWalkOption.FOLLOW_LINKS

            """,
            // testPathWalkOptionUsedInWhenExpressionResolves
            """
            package sample8

                    import kotlin.io.path.PathWalkOption

                    fun describe(option: PathWalkOption): String {
                        return when (option) {
                            PathWalkOption.BREADTH_FIRST -> "breadth-first"
                            PathWalkOption.FOLLOW_LINKS -> "follow-links"
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPathWalkOptionIsRegisteredAsEnumClass ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "kotlin.io.path.PathWalkOption must be registered as a synthetic symbol"
                )
                #expect(
                    sema.symbols.symbol(symbol)?.kind == .enumClass,
                    "PathWalkOption must be registered as enumClass (not regular class)"
                )

            }

            // === testPathWalkOptionIsParentedToKotlinIOPathPackage ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))

                let parent = try #require(
                    sema.symbols.parentSymbol(for: symbol),
                    "PathWalkOption must be parented to the kotlin.io.path package symbol"
                )
                let parentInfo = try #require(sema.symbols.symbol(parent))
                #expect(parentInfo.kind == .package)
                #expect(
                    parentInfo.fqName.map { interner.resolve($0) } == ["kotlin", "io", "path"],
                    "PathWalkOption's parent must be the kotlin.io.path package"
                )

            }

            // === testPathWalkOptionHasCorrectPropertyType ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(
                    sema.symbols.propertyType(for: symbol) == expectedType,
                    "PathWalkOption's propertyType must be the enum class type itself"
                )

            }

            // === testBothPathWalkOptionEntriesAreRegisteredAsFields ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                for entry in Self.allEntries {
                    let fqName = ["kotlin", "io", "path", "PathWalkOption", entry].map { interner.intern($0) }
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: fqName),
                        "PathWalkOption.\(entry) must be present in the symbol table"
                    )
                    #expect(
                        sema.symbols.symbol(symbol)?.kind == .field,
                        "PathWalkOption.\(entry) must be registered as field (enum entry)"
                    )
                }

            }

            // === testPathWalkOptionEntryPropertyTypesAreEnumType ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: enumSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                for entry in Self.allEntries {
                    let fqName = enumFQName + [interner.intern(entry)]
                    let entrySymbol = try #require(
                        sema.symbols.lookup(fqName: fqName),
                        "PathWalkOption.\(entry) must exist"
                    )
                    #expect(
                        sema.symbols.propertyType(for: entrySymbol) == expectedType,
                        "PathWalkOption.\(entry) propertyType must equal PathWalkOption (so member resolution works)"
                    )
                }

            }

            // === testPathWalkOptionEntriesAreParentedToEnumClass ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

                for entry in Self.allEntries {
                    let fqName = enumFQName + [interner.intern(entry)]
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: fqName))
                    #expect(
                        sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol,
                        "PathWalkOption.\(entry) must be parented to the PathWalkOption enum class"
                    )
                }

            }

            // === testPathWalkOptionHasExactlyTwoEntries ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
                let children = sema.symbols.children(ofFQName: enumFQName)
                let fieldNames: Set<String> = Set(
                    children.compactMap { child -> String? in
                        guard let info = sema.symbols.symbol(child), info.kind == .field else {
                            return nil
                        }
                        return info.fqName.last.map { interner.resolve($0) }
                    }
                )
                #expect(
                    fieldNames == Set(Self.allEntries),
                    "PathWalkOption enum entries must exactly match the Kotlin stdlib spec (BREADTH_FIRST, FOLLOW_LINKS)"
                )

            }

            // === testPathWalkOptionMemberAccessResolves ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let errors = sample7Diagnostics.filter { $0.severity == .error }
                let messages = errors.map { "\($0.code): \($0.message)" }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected every PathWalkOption entry to resolve cleanly, got: \(messages)")
                )

            }

            // === testPathWalkOptionUsedInWhenExpressionResolves ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let errors = sample8Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "PathWalkOption in when expression should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

        }
    }

}

#endif
