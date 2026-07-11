@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-084: `fun String.toBigDecimalOrNull(): BigDecimal?` in `kotlin.text`.
final class StringToBigDecimalOrNullFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func bigDecimalType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fq = ["java", "math", "BigDecimal"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func testToBigDecimalOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            let directLink = externalLink(for: "toBigDecimalOrNull", sema: sema, interner: ctx.interner)
            XCTAssert(
                directLink == nil || directLink?.isEmpty == true,
                "String.toBigDecimalOrNull should be source-backed and not have a direct external link"
            )
            XCTAssertEqual(
                externalLink(for: "__kk_string_toBigDecimalOrNull", sema: sema, interner: ctx.interner),
                "__kk_string_toBigDecimalOrNull",
                "__kk_string_toBigDecimalOrNull should link to __kk_string_toBigDecimalOrNull"
            )
        }
    }

    func testToBigDecimalOrNullInfersNullableBigDecimalType() throws {
        let source = """
        import java.math.BigDecimal

        fun probe(text: String) {
            val result: BigDecimal? = text.toBigDecimalOrNull()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toBigDecimalOrNull() to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toBigDecimalOrNull"
            })

            let expectedType = sema.types.makeNullable(
                try bigDecimalType(sema: sema, interner: ctx.interner)
            )
            XCTAssertEqual(sema.bindings.exprType(for: callExpr), expectedType)
        }
    }

    func testToBigDecimalOrNullWorksWithElvisFallback() throws {
        let source = """
        import java.math.BigDecimal

        fun parse(raw: String): BigDecimal {
            return raw.toBigDecimalOrNull() ?: "0".toBigDecimal()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Elvis fallback over toBigDecimalOrNull to type-check, got: \(diagnosticSummary)"
            )
        }
    }
}
