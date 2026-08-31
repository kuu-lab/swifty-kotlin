#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-981: the five generic `Iterable.last`-family overloads are bundled
/// Kotlin source and must not fall back to legacy runtime member bridges.
@Suite
struct IterableLastFamilySemaTests {
    @Test
    func testIterableLastFamilyResolvesToBundledSource() throws {
        let source = """
        fun probe(values: Iterable<Int>, element: Int) {
            values.last()
            values.last { it > 0 }
            values.lastIndexOf(element)
            values.lastOrNull()
            values.lastOrNull { it > 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Iterable.last-family calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for (name, expectedCount) in [("last", 2), ("lastIndexOf", 1), ("lastOrNull", 2)] {
                let calls = memberCallExprIDs(named: name, in: ast, interner: ctx.interner).filter { call in
                    guard let range = ast.arena.exprRange(call) else { return false }
                    return ctx.sourceManager.path(of: range.start.file) == path
                }
                #expect(calls.count == expectedCount, "Expected \(expectedCount) \(name) calls")
                for call in calls {
                    let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
                    #expect(sema.symbols.isSourceBackedSymbol(chosen))
                    #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                }
            }
        }
    }
}
#endif
