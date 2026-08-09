@testable import CompilerCore
import Foundation
import Testing

@Suite
struct TestFrameworkSyntheticStubTests {

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "test", member].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)
        return symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    private func lookupTestSymbols(
        sema: SemaModule,
        interner: StringInterner,
        name: String
    ) -> [SymbolID] {
        let fq = ["kotlin", "test", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq)
    }

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
            // testTestAnnotationsAreRegisteredAsAnnotationClasses
            """
            package sample0
            fun noop() {}
            """,
            // testAssertionStubsExposeAllExpectedExternalLinks
            """
            package sample1
            fun noop() {}
            """,
            // testAssertionsAndAnnotationsResolveInSource
            """
            package sample2

                    import kotlin.test.After
                    import kotlin.test.Before
                    import kotlin.test.Test
                    import kotlin.test.assertEquals
                    import kotlin.test.assertNull
                    import kotlin.test.assertTrue

                    class TestFrameworkBasicSuite {
                        @Before
                        fun setUp() {}

                        @After
                        fun tearDown() {}

                        @Test
                        fun testAssertions() {
                            assertEquals(1, 1)
                            assertEquals("hello", "he" + "llo")
                            assertTrue(true)
                            assertNull(null)
                        }
                    }

            """,
            // testSyntheticAnnotationsAreRegistered
            """
            package sample3
            fun noop() {}
            """,
            // testSyntheticAssertionStubsHaveExpectedLinks
            """
            package sample4
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testTestAnnotationsAreRegisteredAsAnnotationClasses ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                for name in ["Test", "Before", "After"] {
                    let fq = ["kotlin", "test", name].map { interner.intern($0) }
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: fq),
                        "Expected kotlin.test.\(name) to be registered"
                    )
                    let resolved = try #require(sema.symbols.symbol(symbol))
                    #expect(resolved.kind == .annotationClass)
                }

            }

            // === testAssertionStubsExposeAllExpectedExternalLinks ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let expected: [String: [String]] = [
                    "assertEquals": ["kk_test_assertEquals", "kk_test_assertEquals_message"],
                    "assertTrue": ["kk_test_assertTrue", "kk_test_assertTrue_message"],
                    "assertNull": ["kk_test_assertNull", "kk_test_assertNull_message"],
                ]

                for (member, links) in expected {
                    let actualLinks = Set(externalLinks(for: member, sema: sema, interner: interner))
                    for link in links {
                        #expect(
                            actualLinks.contains(link),
                            "kotlin.test.\(member) should expose \(link)"
                        )
                    }
                }

            }

            // === testAssertionsAndAnnotationsResolveInSource ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let expectedLinks: [String: String] = [
                    "assertEquals": "kk_test_assertEquals",
                    "assertTrue": "kk_test_assertTrue",
                    "assertNull": "kk_test_assertNull",
                ]

                for (memberName, expectedLinkName) in expectedLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample2Path, ctx: ctx) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == memberName
                    }, "Expected call to \(memberName) in AST")

                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected \(memberName) to resolve"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == expectedLinkName
                    )
                }

            }

            // === testSyntheticAnnotationsAreRegistered ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                for annotationName in ["Test", "Before", "After"] {
                    let symbols = lookupTestSymbols(sema: sema, interner: interner, name: annotationName)
                    let symbol = try #require(symbols.first, "Expected kotlin.test.\(annotationName)")
                    #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
                }

            }

            // === testSyntheticAssertionStubsHaveExpectedLinks ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let expectedLinks: [(name: String, arity: Int, link: String)] = [
                    ("assertEquals", 2, "kk_test_assertEquals"),
                    ("assertEquals", 3, "kk_test_assertEquals_message"),
                    ("assertTrue", 1, "kk_test_assertTrue"),
                    ("assertTrue", 2, "kk_test_assertTrue_message"),
                    ("assertNull", 1, "kk_test_assertNull"),
                    ("assertNull", 2, "kk_test_assertNull_message"),
                ]

                for entry in expectedLinks {
                    let symbols = lookupTestSymbols(sema: sema, interner: interner, name: entry.name)
                    let matching = symbols.first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.parameterTypes.count == entry.arity
                            && sig.returnType == sema.types.unitType
                    }
                    let symbol = try #require(matching, "Expected kotlin.test.\(entry.name) with arity \(entry.arity)")
                    #expect(sema.symbols.externalLinkName(for: symbol) == entry.link)
                }

            }

        }
    }

}
