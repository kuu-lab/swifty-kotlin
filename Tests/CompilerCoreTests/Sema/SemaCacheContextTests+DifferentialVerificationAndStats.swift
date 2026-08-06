@testable import CompilerCore
import Testing

extension SemaCacheContextTests {

    // MARK: - Diagnostic Source-Range Correctness

    // MARK: - Inheritance / Super Call with Cache

    // MARK: - Callable Reference with Cache

    // MARK: - Scope Cache Statistics

    // MARK: - Lambda with Cache

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
    func testRunSemaCleanDifferentialVerificationAndStats() throws {


        let sources: [String] = [
            // testDifferentialVerificationUnresolvedFunction
            """
            package sample0

                    fun main() {
                        val x = unknown(42)
                    }

            """,
            // testDifferentialVerificationClassAndMemberCall
            """
            package sample1

                    class Foo {
                        fun bar(): Int = 42
                    }
                    fun main() {
                        val f = Foo()
                        val x = f.bar()
                    }

            """,
            // testDifferentialVerificationBinaryOperator
            """
            package sample2

                    fun main() {
                        val a = 1 + 2
                        val b = "hello" + " world"
                        val c = a > 0
                    }

            """,
            // testDifferentialVerificationMultipleOverloads
            """
            package sample3

                    fun greet(name: String): String = "Hello, " + name
                    fun greet(count: Int): String = "Hello #" + count.toString()
                    fun main() {
                        val a = greet("world")
                        val b = greet(42)
                    }

            """,
            // testDiagnosticSourceRangesCorrectWithCache
            """
            package sample4

                    fun main() {
                        val x = unknownFn(1)
                        val y = unknownFn(1)
                    }

            """,
            // testDifferentialVerificationInheritance
            """
            package sample5

                    open class Animal {
                        open fun speak(): String = "..."
                    }
                    class Dog : Animal() {
                        override fun speak(): String = "Woof"
                    }
                    fun main() {
                        val d: Animal = Dog()
                        val s = d.speak()
                    }

            """,
            // testDifferentialVerificationCallableReference
            """
            package sample6

                    fun double(x: Int): Int = x * 2
                    fun main() {
                        val fn = ::double
                    }

            """,
            // testScopeCacheStatisticsAreTracked
            """
            package sample7
            fun noop() {}
            """,
            // testDifferentialVerificationLambda
            """
            package sample8

                    fun apply(f: (Int) -> Int, x: Int): Int = f(x)
                    fun main() {
                        val result = apply({ it * 2 }, 5)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let cachedCtx = makeCompilationContext(inputs: paths, frontendFlags: ["sema-cache"])
            try runSema(cachedCtx)

            // === testDifferentialVerificationUnresolvedFunction ===

            do {
                let sample0Path = paths[0]
                let diagsNoCache = diagnosticsForPath(sample0Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample0Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for unresolved function with and without cache"
                )
            }

            // === testDifferentialVerificationClassAndMemberCall ===

            do {
                let sample1Path = paths[1]
                let diagsNoCache = diagnosticsForPath(sample1Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample1Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for class member calls with and without cache"
                )
            }

            // === testDifferentialVerificationBinaryOperator ===

            do {
                let sample2Path = paths[2]
                let diagsNoCache = diagnosticsForPath(sample2Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample2Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for binary operators with and without cache"
                )
            }

            // === testDifferentialVerificationMultipleOverloads ===

            do {
                let sample3Path = paths[3]
                let diagsNoCache = diagnosticsForPath(sample3Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample3Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for overloaded functions with and without cache"
                )
            }

            // === testDiagnosticSourceRangesCorrectWithCache ===

            do {
                let sample4Path = paths[4]

                // Two identical failing calls at different lines must produce diagnostics
                // that point to their respective (different) source locations.
                let diags = diagnosticsForPath(sample4Path, in: cachedCtx)

                // There should be at least two diagnostics for the two unresolved calls
                let unresolvedDiags = diags.filter { $0.code == "KSWIFTK-SEMA-0023" }
                #expect(
                    unresolvedDiags.count >= 2,
                    "Should have at least 2 unresolved function diagnostics"
                )
                if unresolvedDiags.count >= 2 {
                    // The two diagnostics must have different source ranges (different lines)
                    let ranges = unresolvedDiags.compactMap(\.primaryRange)
                    #expect(ranges.count == unresolvedDiags.count, "All diagnostics should have a primaryRange")
                    if ranges.count >= 2 {
                        #expect(
                            ranges[0] != ranges[1],
                            "Two identical failing calls at different locations must produce diagnostics with different source ranges"
                        )
                    }
                }
            }

            // === testDifferentialVerificationInheritance ===

            do {
                let sample5Path = paths[5]
                let diagsNoCache = diagnosticsForPath(sample5Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample5Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for inheritance with and without cache"
                )
            }

            // === testDifferentialVerificationCallableReference ===

            do {
                let sample6Path = paths[6]
                let diagsNoCache = diagnosticsForPath(sample6Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample6Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for callable references with and without cache"
                )
            }

            // === testScopeCacheStatisticsAreTracked ===

            do {
                let setup = makeSemaModule()
                let interner = setup.interner
                let symbols = setup.symbols

                let fooName = interner.intern("foo")
                let sym = symbols.define(
                    kind: .function, name: fooName,
                    fqName: [interner.intern("test"), interner.intern("foo")],
                    declSite: nil, visibility: .public, flags: []
                )

                let scope = BaseScope(parent: nil, symbols: symbols)
                scope.insert(sym)

                let cache = SemaCacheContext()

                #expect(cache.scopeHits == 0)
                #expect(cache.scopeMisses == 0)

                // First lookup: cache miss
                _ = cache.lookupInScope(fooName, scope: scope)
                #expect(cache.scopeHits == 0, "First lookup should be a miss")
                #expect(cache.scopeMisses == 1, "First lookup should be a miss")

                // Second lookup: cache hit
                _ = cache.lookupInScope(fooName, scope: scope)
                #expect(cache.scopeHits == 1, "Second lookup should be a hit")
                #expect(cache.scopeMisses == 1, "Miss count should not change")

                // Third lookup (different name): cache miss
                let barName = interner.intern("bar")
                _ = cache.lookupInScope(barName, scope: scope)
                #expect(cache.scopeHits == 1, "Unknown name should be a miss")
                #expect(cache.scopeMisses == 2, "Miss count should increment")
            }

            // === testDifferentialVerificationLambda ===

            do {
                let sample8Path = paths[8]
                let diagsNoCache = diagnosticsForPath(sample8Path, in: ctx)
                let diagsCached = diagnosticsForPath(sample8Path, in: cachedCtx)

                #expect(
                    diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
                    "Diagnostics must match for lambda expressions with and without cache"
                )
            }

        }
    }

}
