@testable import CompilerCore
import XCTest

// STDLIB-COMP-FN-030: minOf(a: T, b: T, c: T): T where T : Comparable<T>
final class ComparisonsMinOfComparable3FunctionTests: XCTestCase {
    func testMinOfComparable3ArgFunctionResolvesInSource() throws {
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
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected minOf(a, b, c) Comparable 3-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testMinOfComparable3ArgResolvesToGenericOverloadNotPrimitiveSpecialCall() throws {
        let ctx = makeContextFromSource("""
        fun pickEarliest(a: String, b: String, c: String): String {
            return minOf(a, b, c)
        }
        """)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let callExpr = try XCTUnwrap(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, args, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return interner.resolve(calleeName) == "minOf" && args.count == 3
            },
            "Expected 3-arg minOf call with String arguments"
        )

        // Comparable overload is not a primitive fast-path; no special-call kind.
        XCTAssertNil(
            sema.bindings.stdlibSpecialCallKind(for: callExpr),
            "Comparable minOf(a, b, c) must not be assigned a primitive special-call kind"
        )

        let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
        XCTAssertEqual(symbol.fqName, [
            interner.intern("kotlin"),
            interner.intern("comparisons"),
            interner.intern("minOf"),
        ])

        // Signature must have a single type parameter bounded by Comparable<T>
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
        XCTAssertEqual(sig.parameterTypes.count, 3)
        XCTAssertFalse(
            sig.typeParameterSymbols.isEmpty,
            "Comparable minOf(a, b, c) must have a generic type parameter T : Comparable<T>"
        )
    }
}
