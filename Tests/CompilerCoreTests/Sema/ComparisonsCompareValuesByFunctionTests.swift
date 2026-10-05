#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-COMP-FN-004: kotlin.comparisons.compareValuesBy (selector form).
///
/// Verifies that
/// `fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int`
/// KSP-461: it is provided by bundled Kotlin source (Stdlib/kotlin/comparisons/
/// Comparators.kt) and must resolve cleanly from user source code.
@Suite
struct ComparisonsCompareValuesByFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.comparisons.compareValuesBy

        fun cmp(): Int {
            val selector: (Int) -> Int = { x -> x }
            return compareValuesBy(13, 25, selector)
        }
        """,
        """
        package sample1
        fun cmp(): Int =
            compareValuesBy("ab", "cd", { s: String -> s.length }, { s: String -> s })
        """,
        """
        package sample2
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    /// Calling `compareValuesBy(a, b, selector)` from user source must resolve
    /// to the 1-selector overload without semantic errors.
    @Test func testCompareValuesByFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (1-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")

    }

    /// KSP-461: the 2-selector overload shares its arity with the
    /// `comparator + selector` one, so it must still resolve unambiguously.
    @Test func testCompareValuesByTwoSelectorsResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (2-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")

    }

    @Test func testImplicitSelectorsChooseCorrectOverloads() throws {
        let sources = [
            """
            package implicitTwo
            data class P(val n: String, val a: Int)
            fun cmp(): Int = compareValuesBy(P("a", 1), P("a", 2), { it.n }, { it.a })
            fun name(p: P): String = p.n
            fun mixed(): Int = compareValuesBy(P("a", 1), P("a", 2), ::name, { it.a })
            """,
            """
            package implicitThree
            data class P(val n: String, val a: Int, val c: Int)
            fun cmp(): Int = compareValuesBy(P("a", 1, 1), P("a", 1, 2), { it.n }, { it.a }, { it.c })
            """,
            """
            package implicitVararg
            data class P(val n: String, val a: Int, val c: Int, val d: Int)
            fun cmp(): Int = compareValuesBy(P("a", 1, 1, 1), P("a", 1, 1, 2), { it.n }, { it.a }, { it.c }, { it.d })
            """,
            """
            package explicitComparator
            data class P(val n: String, val a: Int)
            fun cmp(): Int = compareValuesBy(P("a", 1), P("a", 2), reverseOrder<Int>(), { it.a })
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Implicit selectors must resolve: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for (index, path) in paths.enumerated() {
                let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return ctx.interner.resolve(name) == "compareValuesBy"
                })
                let binding = try #require(sema.bindings.callBinding(for: call))
                let chosen = binding.chosenCallee
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "comparisons", "compareValuesBy"])
                #expect(signature.typeParameterSymbols.count == (index == 3 ? 2 : 1))
                #expect(signature.parameterTypes.count == [4, 5, 3, 4][index])
                #expect(signature.valueParameterIsVararg.contains(true) == (index == 2))
                if index == 2 {
                    #expect(binding.parameterMapping == [0: 0, 1: 1, 2: 2, 3: 2, 4: 2, 5: 2])
                }
            }
            let mixedCall = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                guard case let .call(_, _, args, _) = expr,
                      args.count == 4,
                      case .callableRef = ast.arena.expr(args[2].expr)
                else { return false }
                return true
            })
            let mixedBinding = try #require(sema.bindings.callBinding(for: mixedCall))
            let mixedSignature = try #require(sema.symbols.functionSignature(for: mixedBinding.chosenCallee))
            #expect(mixedSignature.parameterTypes.count == 4)
            #expect(mixedSignature.typeParameterSymbols.count == 1)
        }
    }

    /// KSP-461: the 1-selector overload is bundled Kotlin source, so it must be
    /// registered without any runtime external link.
    @Test func testCompareValuesByOneSelectorIsSourceBacked() throws {

        let ctx = try sharedCtx()
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "comparisons", "compareValuesBy"].map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fq)
            let isSourceBacked = symbols.contains { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == nil
                    && sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == 3
            }
            #expect(isSourceBacked, "compareValuesBy (1-selector) must be bundled Kotlin source")
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(links.isEmpty, "compareValuesBy must not keep runtime links; found: \(links)")

    }
}
#endif
