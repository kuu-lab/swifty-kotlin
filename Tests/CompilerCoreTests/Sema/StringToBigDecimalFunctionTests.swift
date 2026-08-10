#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Foundation
import Testing

/// STDLIB-TEXT-FN-083: `fun String.toBigDecimal(): BigDecimal` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the JVM-compatible `java.math.BigDecimal` return type.
@Suite
struct StringToBigDecimalFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let symbol = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: symbol)
    }

    private func bigDecimalType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fq = ["java", "math", "BigDecimal"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    @Test func testToBigDecimalResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.math.BigDecimal

        fun parse(raw: String): BigDecimal {
            return raw.toBigDecimal()
        }
        """)

        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected String.toBigDecimal() to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let directLink = externalLink(for: "toBigDecimal", sema: sema, interner: interner)
        #expect(
            directLink == nil || directLink?.isEmpty == true,
            "String.toBigDecimal should be source-backed and not have a direct external link"
        )
        #expect(
            RuntimeABISpec.allFunctions.first { $0.name == "__kk_string_toBigDecimal" } != nil,
            "__kk_string_toBigDecimal must be registered in RuntimeABISpec"
        )

        let fq = ["kotlin", "text", "toBigDecimal"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.stringType && signature.parameterTypes.isEmpty
            }
        )
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(returnType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("String.toBigDecimal() should return a class type")
            return
        }
        let returnSymbol = try #require(sema.symbols.symbol(returnType.classSymbol))
        let returnFQName = returnSymbol.fqName.map { interner.resolve($0) }

        #expect(returnFQName == ["java", "math", "BigDecimal"])
        #expect(returnType.nullability == .nonNull)

        let ast = try #require(ctx.ast)
        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return interner.resolve(callee) == "toBigDecimal" && args.isEmpty
            },
            "Expected member call to toBigDecimal() in AST"
        )
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for toBigDecimal"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil || sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty == true,
            "String.toBigDecimal() should resolve to standard library function (no direct external link)"
        )
    }
}
#endif
