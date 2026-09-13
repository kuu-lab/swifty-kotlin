#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-CAP-013: `resolveTypeRef` used to resolve an unqualified type name
/// (e.g. `Lazy` in `val x: Lazy<Int> = ...`) via a global short-name scan
/// across *all* packages, sorted by internal symbol ID, completely ignoring
/// lexical scope / import priority. Since `kotlin.properties.Lazy` (an
/// unrelated, zero-arity marker interface, not a default import) happens to
/// be registered before `kotlin.Lazy` (the real, one-arity `out T` interface
/// returned by `lazy`/`lazyOf`), the annotation resolved to the wrong symbol
/// and the return-type constraint against the correctly-typed `lazyOf`/`lazy`
/// call always failed with KSWIFTK-TYPE-0001.
@Suite
struct GenericFunctionExpectedTypeConstraintTests {

    /// Unqualified `Lazy` must never resolve to the unrelated
    /// `kotlin.properties.Lazy` marker interface, which is not a default
    /// import and declares no type parameters or `value` member.
    private func assertLocalIsRootKotlinLazy(
        named targetName: String,
        ctx: CompilationContext
    ) throws {
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let interner = ctx.interner

        let rootLazyFQName = ["kotlin", "Lazy"].map { interner.intern($0) }
        let legacyLazyFQName = ["kotlin", "properties", "Lazy"].map { interner.intern($0) }
        let rootLazySymbol = try #require(sema.symbols.lookup(fqName: rootLazyFQName))

        let mainBody = try #require(findMainBodyStatements(in: ast, interner: interner))
        var checked = false
        for exprID in mainBody {
            guard let expr = ast.arena.expr(exprID),
                  case let .localDecl(name, _, _, initializer, _, _) = expr,
                  interner.resolve(name) == targetName,
                  let initializer,
                  let boundType = sema.bindings.exprType(for: initializer)
            else { continue }

            guard case let .classType(classType) = sema.types.kind(of: boundType) else {
                Issue.record("Expected \(targetName) to bind to a class type, got \(sema.types.renderType(boundType))")
                continue
            }
            #expect(classType.classSymbol == rootLazySymbol)
            if let legacyLazySymbol = sema.symbols.lookup(fqName: legacyLazyFQName) {
                #expect(classType.classSymbol != legacyLazySymbol)
            }
            checked = true
        }
        #expect(checked, "Expected to find local declaration named \(targetName)")
    }

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
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
            // testLazyOfMatchesExplicitLazyExpectedType
            """
            package sample0

                    fun main() {
                        val x: Lazy<Int> = lazyOf(1)
                        println(x.value)
                    }

            """,
            // testLazyBlockMatchesExplicitLazyExpectedType
            """
            package sample1

                    fun main() {
                        val x: Lazy<Int> = lazy { 1 }
                        println(x.value)
                    }

            """,
            // testLazyModeMatchesExplicitLazyExpectedType
            """
            package sample2

                    fun main() {
                        val x: Lazy<Int> = lazy(LazyThreadSafetyMode.NONE) { 1 }
                        println(x.value)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testLazyOfMatchesExplicitLazyExpectedType ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample0Diagnostics)
                #expect(sample0Diagnostics.isEmpty, "Got: \(sample0Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

            // === testLazyBlockMatchesExplicitLazyExpectedType ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample1Diagnostics)
                #expect(sample1Diagnostics.isEmpty, "Got: \(sample1Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

            // === testLazyModeMatchesExplicitLazyExpectedType ===

            do {

                let sample2Path = paths[2]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample2Diagnostics)
                #expect(sample2Diagnostics.isEmpty, "Got: \(sample2Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

        }
    }

}

#endif
