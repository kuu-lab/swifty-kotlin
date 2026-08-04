#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Foundation
import Testing

/// STDLIB-TEXT-FN-085: `fun String.toBigInteger(): BigInteger` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the JVM-compatible `java.math.BigInteger` return type.
@Suite
struct StringToBigIntegerFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let symbol = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: symbol)
    }

    private func bigIntegerType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fq = ["java", "math", "BigInteger"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    @Test func testToBigIntegerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.math.BigInteger

        fun parse(raw: String): BigInteger {
            return raw.toBigInteger()
        }
        """)

        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected String.toBigInteger() to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let directLink = externalLink(for: "toBigInteger", sema: sema, interner: interner)
        #expect(
            directLink == nil || directLink?.isEmpty == true,
            "String.toBigInteger should be source-backed and not have a direct external link"
        )
        #expect(
            RuntimeABISpec.allFunctions.contains { $0.name == "__kk_string_toBigInteger" },
            "__kk_string_toBigInteger must be registered in RuntimeABISpec"
        )

        let fq = ["kotlin", "text", "toBigInteger"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.stringType && signature.parameterTypes.isEmpty
            }
        )
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(returnType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("String.toBigInteger() should return a class type")
            return
        }
        let returnSymbol = try #require(sema.symbols.symbol(returnType.classSymbol))
        let returnFQName = returnSymbol.fqName.map { interner.resolve($0) }

        #expect(returnFQName == ["java", "math", "BigInteger"])
        #expect(returnType.nullability == .nonNull)

        let ast = try #require(ctx.ast)
        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return interner.resolve(callee) == "toBigInteger" && args.isEmpty
            },
            "Expected member call to toBigInteger() in AST"
        )
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for toBigInteger"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil || sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty == true,
            "String.toBigInteger() should resolve to standard library function (no direct external link)"
        )
    }
}
#endif
