#if canImport(Testing)
@testable import CompilerCore
import Testing

// STDLIB-COMP-FN-030: minOf(a: T, b: T, c: T): T where T : Comparable<T>
@Suite
struct ComparisonsMinOfComparable3FunctionTests {
    @Test func testMinOfComparable3ArgFunctionResolvesInSource() throws {
        // Use String (a Kotlin built-in Comparable) so that the subtype
        // check primitive <: Comparable<primitive> is satisfied without
        // relying on user-defined generic supertype resolution.
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.minOf

        fun pickEarliest(a: String, b: String, c: String): String {
            return minOf(a, b, c)
        }
        """)
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected minOf(a, b, c) Comparable 3-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testMinOfComparable3ArgResolvesToGenericOverloadNotPrimitiveSpecialCall() throws {
        let ctx = makeContextFromSource("""
        fun pickEarliest(a: String, b: String, c: String): String {
            return minOf(a, b, c)
        }
        """)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, args, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return interner.resolve(calleeName) == "minOf" && args.count == 3
            },
            "Expected 3-arg minOf call with String arguments"
        )

        // Comparable overload is not a primitive fast-path; no special-call kind.
        #expect(
            sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil,
            "Comparable minOf(a, b, c) must not be assigned a primitive special-call kind"
        )

        let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        let symbol = try #require(sema.symbols.symbol(chosen))
        #expect(symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("comparisons"),
            interner.intern("minOf"),
        ])

        // Signature must have a single type parameter bounded by Comparable<T>
        let sig = try #require(sema.symbols.functionSignature(for: chosen))
        #expect(sig.parameterTypes.count == 3)
        #expect(
            !(sig.typeParameterSymbols.isEmpty),
            "Comparable minOf(a, b, c) must have a generic type parameter T : Comparable<T>"
        )
    }
}
#endif
