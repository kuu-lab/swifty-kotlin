#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-010: Validates that the synthetic `kotlin.text.MatchResult`
/// sealed interface and its nested `MatchResult.Destructured` class are correctly
/// registered in the symbol table after sema, with all expected properties and
/// functions wired to their runtime ABI link names.
@Suite
struct MatchResultTypeTests {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - 1. MatchResult class symbol

    // MARK: - 2. MatchResult.value: String

    // MARK: - 3. MatchResult.range: IntRange

    // MARK: - 4. MatchResult.groupValues: List<String>

    // MARK: - 5. MatchResult.groups: MatchGroupCollection

    // MARK: - 6. MatchResult.next(): MatchResult?

    // MARK: - 7. MatchResult.destructured: MatchResult.Destructured

    // MARK: - 8. MatchResult.Destructured nested class

    // MARK: - 9. MatchResult.Destructured.match: MatchResult

    // MARK: - 10. MatchResult.Destructured.component1()..component9()

    // MARK: - 11. Source-level usage: basic MatchResult access type-checks

    // MARK: - 12. Source-level usage: MatchResult.destructured access type-checks

    // MARK: - 13. Source-level usage: MatchResult.next() chaining type-checks

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
            // testMatchResultClassSymbolIsRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testMatchResultValuePropertyIsRegistered
            """
            package sample1
            fun noop() {}
            """,
            // testMatchResultRangePropertyIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testMatchResultGroupValuesPropertyIsRegistered
            """
            package sample3
            fun noop() {}
            """,
            // testMatchResultGroupsPropertyIsRegistered
            """
            package sample4
            fun noop() {}
            """,
            // testMatchResultNextFunctionIsRegistered
            """
            package sample5
            fun noop() {}
            """,
            // testMatchResultDestructuredPropertyIsRegistered
            """
            package sample6
            fun noop() {}
            """,
            // testMatchResultDestructuredClassSymbolIsRegistered
            """
            package sample7
            fun noop() {}
            """,
            // testMatchResultDestructuredMatchPropertyIsRegistered
            """
            package sample8
            fun noop() {}
            """,
            // testMatchResultDestructuredComponentFunctionsAreRegistered
            """
            package sample9
            fun noop() {}
            """,
            // testBasicMatchResultAccessTypeChecks
            """
            package sample10

                    fun extractFirstNumber(input: String): String? {
                        val regex = Regex("(\\\\d+)")
                        val match = regex.find(input)
                        return match?.value
                    }

            """,
            // testDestructuredPropertyAccessTypeChecks
            """
            package sample11

                    fun extractGroups(input: String): String? {
                        val regex = Regex("(\\\\w+)\\\\s+(\\\\w+)")
                        val match = regex.find(input)
                        val d = match?.destructured
                        return d?.component1()
                    }

            """,
            // testMatchResultNextChainingTypeChecks
            """
            package sample12

                    fun allMatches(input: String): List<String> {
                        val regex = Regex("\\\\d+")
                        var match = regex.find(input)
                        val results = mutableListOf<String>()
                        while (match != null) {
                            results.add(match.value)
                            match = match.next()
                        }
                        return results
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testMatchResultClassSymbolIsRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "kotlin.text.MatchResult class symbol must be registered by sema"
                )
                let info = try #require(sema.symbols.symbol(sym))
                #expect(info.kind == .class,
                               "MatchResult should be registered with kind=class")

            }

            // === testMatchResultValuePropertyIsRegistered ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "value"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_result_value"),
                    "MatchResult.value must link to kk_match_result_value; found: \(links)"
                )

            }

            // === testMatchResultRangePropertyIsRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "range"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_result_range"),
                    "MatchResult.range must link to kk_match_result_range; found: \(links)"
                )

            }

            // === testMatchResultGroupValuesPropertyIsRegistered ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "groupValues"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "MatchResult.groupValues property must be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_match_result_groupValues",
                    "MatchResult.groupValues must link to kk_match_result_groupValues"
                )

            }

            // === testMatchResultGroupsPropertyIsRegistered ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "groups"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "MatchResult.groups property must be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_match_result_groups",
                    "MatchResult.groups must link to kk_match_result_groups"
                )

            }

            // === testMatchResultNextFunctionIsRegistered ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "next"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "MatchResult.next() function must be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_match_result_next",
                    "MatchResult.next() must link to kk_match_result_next"
                )

            }

            // === testMatchResultDestructuredPropertyIsRegistered ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "destructured"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "MatchResult.destructured property must be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_match_result_destructured",
                    "MatchResult.destructured must link to kk_match_result_destructured"
                )

            }

            // === testMatchResultDestructuredClassSymbolIsRegistered ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "Destructured"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "kotlin.text.MatchResult.Destructured nested class must be registered by sema"
                )
                let info = try #require(sema.symbols.symbol(sym))
                #expect(info.kind == .class,
                               "MatchResult.Destructured should be registered with kind=class")

            }

            // === testMatchResultDestructuredMatchPropertyIsRegistered ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "Destructured", "match"]
                    .map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookup(fqName: fq),
                    "MatchResult.Destructured.match property must be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_match_result_destructured_match",
                    "MatchResult.Destructured.match must link to kk_match_result_destructured_match"
                )

            }

            // === testMatchResultDestructuredComponentFunctionsAreRegistered ===

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                for index in 1...9 {
                    let fq = ["kotlin", "text", "MatchResult", "Destructured", "component\(index)"]
                        .map { interner.intern($0) }
                    let syms = sema.symbols.lookupAll(fqName: fq)
                    let expectedLink = "kk_match_result_destructured_component\(index)"
                    let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                    #expect(
                        links.contains(expectedLink),
                        "MatchResult.Destructured.component\(index)() must link to \(expectedLink); found: \(links)"
                    )
                }

            }

            // === testBasicMatchResultAccessTypeChecks ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let errors = sample10Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Basic MatchResult access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testDestructuredPropertyAccessTypeChecks ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let errors = sample11Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "MatchResult.destructured access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testMatchResultNextChainingTypeChecks ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let errors = sample12Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "MatchResult.next() chaining should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

        }
    }

}

#endif
