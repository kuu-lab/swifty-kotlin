@testable import CompilerCore
import RuntimeABI
import XCTest

/// STDLIB-TEXT-FN-085: `fun String.toBigInteger(): BigInteger` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the JVM-compatible `java.math.BigInteger` return type.
final class StringToBigIntegerFunctionTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let symbol = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: symbol)
    }

    func testToBigIntegerStubLinksToRuntimeSymbol() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "toBigInteger", sema: sema, interner: interner),
            "kk_string_toBigInteger",
            "String.toBigInteger should link to kk_string_toBigInteger"
        )
        XCTAssertNotNil(
            RuntimeABISpec.allFunctions.first { $0.name == "kk_string_toBigInteger" },
            "kk_string_toBigInteger must be registered in RuntimeABISpec"
        )
    }

    func testToBigIntegerReturnsJavaMathBigInteger() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "toBigInteger"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.stringType && signature.parameterTypes.isEmpty
            }
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(returnType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("String.toBigInteger() should return a class type")
        }
        let returnSymbol = try XCTUnwrap(sema.symbols.symbol(returnType.classSymbol))
        let returnFQName = returnSymbol.fqName.map { interner.resolve($0) }

        XCTAssertEqual(returnFQName, ["java", "math", "BigInteger"])
        XCTAssertEqual(returnType.nullability, .nonNull)
    }

    func testToBigIntegerCallResolvesToRuntimeBridge() throws {
        let source = """
        import java.math.BigInteger

        fun parse(raw: String): BigInteger {
            return raw.toBigInteger()
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
                "Expected String.toBigInteger() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toBigInteger" && args.isEmpty
                },
                "Expected member call to toBigInteger() in AST"
            )
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toBigInteger"
            )

            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toBigInteger",
                "String.toBigInteger() should resolve to kk_string_toBigInteger"
            )
        }
    }
}
