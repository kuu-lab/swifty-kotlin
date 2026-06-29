@testable import CompilerCore
import RuntimeABI
import XCTest

/// STDLIB-TEXT-FN-083: `fun String.toBigDecimal(): BigDecimal` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the JVM-compatible `java.math.BigDecimal` return type.
final class StringToBigDecimalFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let symbol = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: symbol)
    }

    func testToBigDecimalStubLinksToRuntimeSymbol() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "toBigDecimal", sema: sema, interner: interner),
            "kk_string_toBigDecimal",
            "String.toBigDecimal should link to kk_string_toBigDecimal"
        )
        XCTAssertNotNil(
            RuntimeABISpec.allFunctions.first { $0.name == "kk_string_toBigDecimal" },
            "kk_string_toBigDecimal must be registered in RuntimeABISpec"
        )
    }

    func testToBigDecimalReturnsJavaMathBigDecimal() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "toBigDecimal"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.stringType && signature.parameterTypes.isEmpty
            }
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(returnType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("String.toBigDecimal() should return a class type")
        }
        let returnSymbol = try XCTUnwrap(sema.symbols.symbol(returnType.classSymbol))
        let returnFQName = returnSymbol.fqName.map { interner.resolve($0) }

        XCTAssertEqual(returnFQName, ["java", "math", "BigDecimal"])
        XCTAssertEqual(returnType.nullability, .nonNull)
    }

    func testToBigDecimalCallResolvesToRuntimeBridge() throws {
        let source = """
        import java.math.BigDecimal

        fun parse(raw: String): BigDecimal {
            return raw.toBigDecimal()
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
                "Expected String.toBigDecimal() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toBigDecimal" && args.isEmpty
                },
                "Expected member call to toBigDecimal() in AST"
            )
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toBigDecimal"
            )

            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toBigDecimal",
                "String.toBigDecimal() should resolve to kk_string_toBigDecimal"
            )
        }
    }
}
