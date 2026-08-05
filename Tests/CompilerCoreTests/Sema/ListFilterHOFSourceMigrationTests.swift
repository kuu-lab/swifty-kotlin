@testable import CompilerCore
import Testing

@Suite
struct ListFilterHOFSourceMigrationTests {

    private let sourcePath = "__bundled_kotlin/collections/ListFilterHOF.kt"

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
            // migratedListFilterFunctionsAreBundledSourceDefinitions
            """
            package sample0
            fun noop() {}
            """,
            // migratedListFilterFunctionsDoNotKeepPublicRuntimeLinkedMembers
            """
            package sample1
            fun noop() {}
            """,
            // listFilterCallsBindBundledSourceDefinitions
            """
            package sample2

                    fun sampleInts(values: List<Int>, destination: MutableList<Int>) {
                        values.filter { value -> value > 0 }
                        values.filterNot { value -> value > 0 }
                        values.filterIndexed { index, value -> index < value }
                        values.filterTo(destination) { value -> value > 0 }
                        values.filterNotTo(destination) { value -> value > 0 }
                        values.filterIndexedTo(destination) { index, value -> index < value }
                    }

                    fun sampleNullable(values: List<Int?>, destination: MutableList<Int>) {
                        values.filterNotNull()
                        values.filterNotNullTo(destination)
                    }

                    fun sampleAny(values: List<Any>, destination: MutableList<String>) {
                        values.filterIsInstance<String>()
                        values.filterIsInstanceTo(destination)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === migratedListFilterFunctionsAreBundledSourceDefinitions ===

            do {

                let sample0Path = paths[0]

                let source = sources[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let packageFQName = ["kotlin", "collections"].map(interner.intern)
                let expectedArities: [String: Set<Int>] = [
                    "filter": [1],
                    "filterNot": [1],
                    "filterNotNull": [0],
                    "filterIndexed": [1],
                    "filterIsInstance": [0],
                    "filterTo": [2],
                    "filterNotTo": [2],
                    "filterNotNullTo": [1],
                    "filterIndexedTo": [2],
                    "filterIsInstanceTo": [1],
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
                        return ctx.sourceManager.path(of: fileID) == sourcePath
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
                        "Expected \(name) bundled source definitions to be List extension functions"
                    )
                    #expect(
                        sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                        "Expected \(name) bundled source definitions to avoid direct C external links"
                    )
                }

            }

            // === migratedListFilterFunctionsDoNotKeepPublicRuntimeLinkedMembers ===

            do {

                let sample1Path = paths[1]

                let source = sources[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let listFQName = ["kotlin", "collections", "List"].map(interner.intern)
                let oldLink: (String) -> String = { "kk_list_" + $0 }
                let disallowedMemberLinks: [String: Set<String>] = [
                    "filter": [oldLink("filter")],
                    "filterNot": [oldLink("filterNot")],
                    "filterNotNull": [oldLink("filterNotNull")],
                    "filterIndexed": [oldLink("filterIndexed")],
                    "filterIsInstance": [oldLink("filterIsInstance")],
                    "filterTo": [oldLink("filterTo")],
                    "filterNotTo": [oldLink("filterNotTo")],
                    "filterNotNullTo": [oldLink("filterNotNullTo")],
                    "filterIndexedTo": [oldLink("filterIndexedTo")],
                    "filterIsInstanceTo": [oldLink("filterIsInstanceTo")],
                ]

                for (name, disallowedLinks) in disallowedMemberLinks {
                    let fqName = listFQName + [interner.intern(name)]
                    let memberLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                        sema.symbols.externalLinkName(for: $0)
                    })
                    let leakedLinks = memberLinks.intersection(disallowedLinks)
                    #expect(
                        leakedLinks.isEmpty,
                        "Expected \(name) to be served by bundled source, but found public member links \(leakedLinks)"
                    )
                }

            }

            // === listFilterCallsBindBundledSourceDefinitions ===

            do {

                let sample2Path = paths[2]

                let source = sources[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "Expected List filter source calls to type-check cleanly, got: \(diagnosticSummary(in: ctx))"
                )

                let expectedNames: Set<String> = [
                    "filter",
                    "filterNot",
                    "filterNotNull",
                    "filterIndexed",
                    "filterIsInstance",
                    "filterTo",
                    "filterNotTo",
                    "filterNotNullTo",
                    "filterIndexedTo",
                    "filterIsInstanceTo",
                ]
                for name in expectedNames {
                    let callExpr = try #require(userMemberCallID(named: name, in: ast, ctx: ctx, excludedPath: sourcePath))
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosenCallee))
                    let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                    #expect(symbol.declSite != nil)
                    #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
                }

            }

        }
    }

}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics
        .map { diagnostic in
            guard let range = diagnostic.primaryRange else {
                return "\(diagnostic.code): \(diagnostic.message)"
            }
            let position = ctx.sourceManager.lineColumn(of: range.start)
            return "\(ctx.sourceManager.path(of: range.start.file)):\(position.line):\(position.column): \(diagnostic.code): \(diagnostic.message)"
        }
        .joined(separator: "\n")
}

private func userMemberCallID(
    named name: String,
    in ast: ASTModule,
    ctx: CompilationContext,
    excludedPath: String
) -> ExprID? {
    firstExprID(in: ast) { exprID, expr in
        guard case let .memberCall(_, callee, _, _, _) = expr,
              ctx.interner.resolve(callee) == name
        else {
            return false
        }
        guard let range = ast.arena.exprRange(exprID) else {
            return true
        }
        return ctx.sourceManager.path(of: range.start.file) != excludedPath
    }
}
