#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-level coverage for the kotlin.comparisons.compareBy(selector) function
/// (STDLIB-COMP-FN-001).
///
/// Verifies that the bundled stdlib top-level
/// `fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T>`
/// is registered in the `kotlin.comparisons` package and resolves from Kotlin
/// source code that explicitly imports the function.
@Suite
struct ComparisonsCompareBySelectorFunctionTests {
    @Test func testCompareBySelectorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareBy

        data class Person(val name: String)

        data class Item(val priority: Int)

        fun makeComparator(): Comparator<Person> {
            return compareBy<Person> { it.name }
        }

        fun cmpItems(): Comparator<Item> = compareBy<Item> { it.priority }
        """)

        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected compareBy(selector) to resolve cleanly, got: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            },
            "Expected a call to compareBy"
        )

        let exprType = try #require(sema.bindings.exprTypes[callExpr])
        guard case let .classType(ct) = sema.types.kind(of: exprType) else {
            Issue.record("Expected compareBy result to be a class type (Comparator<T>)")
            return
        }
        let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"],
            "Expected compareBy(selector) to return kotlin.Comparator<T>"
        )

        let fqName: [InternedString] = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("comparisons"),
            ctx.interner.intern("compareBy"),
        ]
        let selectorOverloads = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 1
                && sig.typeParameterSymbols.count == 1
                && sig.valueParameterIsVararg == [false]
        }
        #expect(
            !selectorOverloads.isEmpty,
            "Expected at least one single-selector compareBy overload"
        )
        #expect(
            selectorOverloads.contains { sema.symbols.externalLinkName(for: $0) == nil },
            "Expected a source-backed compareBy(selector) overload"
        )
    }
}
#endif
