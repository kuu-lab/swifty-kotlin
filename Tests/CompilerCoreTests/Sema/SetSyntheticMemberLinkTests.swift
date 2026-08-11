@testable import CompilerCore
import Foundation
import Testing

/// Verifies that `Set` binary collection members resolve to the bundled Kotlin
/// stdlib declarations (KSP-432) instead of `kk_set_*` runtime bridges.
@Suite
struct SetSyntheticMemberLinkTests {
    private static let binaryMembers = ["intersect", "union", "subtract"]

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func setReceiverFunctions(
        named member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let packageFQName = ["kotlin", "collections"].map { interner.intern($0) }
        let setFQName = packageFQName + [interner.intern("Set")]
        return sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(member)]).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiverType = signature.receiverType,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
            else {
                return false
            }
            return sema.symbols.symbol(classType.classSymbol)?.fqName == setFQName
        }
    }

    @Test func testSetBinaryMembersAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()

        for member in Self.binaryMembers {
            let candidates = setReceiverFunctions(named: member, sema: sema, interner: interner)
            let symbolID = try #require(candidates.first, "Expected bundled source for Set.\(member)")
            #expect(
                sema.symbols.externalLinkName(for: symbolID) == nil,
                "Set.\(member) should not carry a kk_set_* runtime link"
            )
        }
    }

    @Test func testSetBinaryMembersResolveInCallExpressions() throws {
        let source = """
        fun probe(values: Set<Int>, other: List<Int>) {
            val left = values.intersect(other)
            val middle = values.union(other)
            val right = values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in Self.binaryMembers {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "Expected \(memberName) to bind to the bundled source declaration"
                )
                #expect(sema.symbols.symbol(chosenCallee)?.flags.contains(.synthetic) == false)
            }
        }
    }
}
