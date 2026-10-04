@testable import CompilerCore
import Testing

@Suite
struct StdlibSpecialCallRegistryTests {
    /// KSP-604: `repeat` resolves to the bundled Kotlin declaration in
    /// `Stdlib/kotlin/Standard.kt`, so it must no longer carry a synthetic stub
    /// nor a `StdlibSpecialCallKind` marker.
    @Test
    func testRepeatResolvesToBundledKotlinDeclaration() throws {
        let ctx = makeContextFromSource("""
        fun sample() {
            repeat(2) { index ->
                println(index)
            }
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let repeatFQName = ["kotlin", "repeat"].map { ctx.interner.intern($0) }
        let repeatSymbol = try #require(sema.symbols.lookup(fqName: repeatFQName))
        let repeatFlags = try #require(sema.symbols.symbol(repeatSymbol)?.flags)
        #expect(!repeatFlags.contains(.synthetic))
        #expect(repeatFlags.contains(.inlineFunction))

        let repeatCall = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "repeat"
            },
            "Expected top-level repeat call"
        )
        #expect(sema.bindings.stdlibSpecialCallKind(for: repeatCall) == nil)
        #expect(sema.bindings.callBinding(for: repeatCall)?.chosenCallee == repeatSymbol)
    }
}
