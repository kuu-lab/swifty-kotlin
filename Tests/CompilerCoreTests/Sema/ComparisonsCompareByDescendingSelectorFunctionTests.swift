#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-level coverage for the kotlin.comparisons.compareByDescending(selector) function
/// (STDLIB-COMP-FN-002).
///
/// Verifies that the synthetic top-level
/// `fun <T> compareByDescending(selector: (T) -> Comparable<*>?): Comparator<T>`
/// is registered in the `kotlin.comparisons` package and resolves from Kotlin
/// source code that explicitly imports the function.
@Suite
struct ComparisonsCompareByDescendingSelectorFunctionTests {

    // MARK: - Symbol registration

    @Test func testCompareByDescendingSelectorIsRegisteredInComparisonsPackage() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let fqName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("compareByDescending"),
            ]
            let candidates = sema.symbols.lookupAll(fqName: fqName)
            #expect(!(candidates.isEmpty), "Expected kotlin.comparisons.compareByDescending to be registered as a synthetic top-level function")

            let externalLinks = Set(
                candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(externalLinks.contains("kk_comparator_from_selector_descending"), "Expected at least one compareByDescending overload to link to kk_comparator_from_selector_descending, got: \(externalLinks)")
        }
    }

    @Test func testCompareByDescendingSelectorOverloadHasSingleSelectorParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let fqName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("compareByDescending"),
            ]
            let selectorOverloads = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.count == 1
                    && sig.typeParameterSymbols.count == 1
                    && sig.valueParameterIsVararg == [false]
            }
            #expect(!(selectorOverloads.isEmpty), "Expected at least one single-selector compareByDescending overload")
        }
    }

    // MARK: - Source resolution

    @Test func testCompareByDescendingSelectorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareByDescending

        data class Person(val age: Int)

        fun makeComparator(): Comparator<Person> {
            return compareByDescending<Person> { it.age }
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected compareByDescending(selector) to resolve, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testCompareByDescendingSelectorReturnsComparator() throws {
        let source = """
        import kotlin.comparisons.compareByDescending

        data class Item(val priority: Int)

        fun cmpItems(): Comparator<Item> = compareByDescending<Item> { it.priority }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareByDescending"
            }, "Expected a call to compareByDescending")

            let exprType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                Issue.record("Expected compareByDescending result to be a class type (Comparator<T>)")
                return
            }
            let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"], "Expected compareByDescending(selector) to return kotlin.Comparator<T>")
        }
    }
}
#endif
