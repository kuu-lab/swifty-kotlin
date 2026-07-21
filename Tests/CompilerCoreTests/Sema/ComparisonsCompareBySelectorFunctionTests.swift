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

    // MARK: - Symbol registration

    @Test func testCompareBySelectorIsRegisteredInComparisonsPackage() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let fqName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("compareBy"),
            ]
            let candidates = sema.symbols.lookupAll(fqName: fqName)
            let sourceBackedSelectorOverloads = candidates.filter { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.count == 1
                    && sig.valueParameterIsVararg == [false]
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            }
            #expect(!(sourceBackedSelectorOverloads.isEmpty), "Expected kotlin.comparisons.compareBy selector overload to be registered from bundled stdlib source")
        }
    }

    @Test func testCompareBySelectorOverloadHasSingleSelectorParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
            #expect(!(selectorOverloads.isEmpty), "Expected at least one single-selector compareBy overload")
        }
    }

    // MARK: - Source resolution

    @Test func testCompareBySelectorFunctionResolvesInSource() throws {
        let source = """
        import kotlin.comparisons.compareBy

        data class Person(val name: String)

        fun makeComparator(): Comparator<Person> {
            return compareBy<Person> { it.name }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected compareBy<Person> selector form to resolve cleanly, got: \(diagnosticSummary)")
        }
    }

    @Test func testCompareBySelectorReturnsComparator() throws {
        let source = """
        import kotlin.comparisons.compareBy

        data class Item(val priority: Int)

        fun cmpItems(): Comparator<Item> = compareBy<Item> { it.priority }
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
                return ctx.interner.resolve(calleeName) == "compareBy"
            }, "Expected a call to compareBy")

            let exprType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                Issue.record("Expected compareBy result to be a class type (Comparator<T>)")
                return
            }
            let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"], "Expected compareBy(selector) to return kotlin.Comparator<T>")
        }
    }
}
#endif
