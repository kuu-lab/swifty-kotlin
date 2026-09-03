#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IterableFirstFamilySemaTests {
    @Test
    func testIterableFirstFamilyUsesBundledSourceDeclarations() throws {
        let cases: [(name: String, source: String, expectedType: (CompilationContext) -> TypeID)] = [
            (
                "first",
                "fun probe(values: Iterable<Int>): Int = values.first()\n",
                { $0.sema!.types.intType }
            ),
            (
                "first",
                "fun probe(values: Iterable<Int>): Int = values.first { it > 1 }\n",
                { $0.sema!.types.intType }
            ),
            (
                "firstNotNullOf",
                "fun probe(values: Iterable<Int>): String = values.firstNotNullOf { if (it > 1) \"hit\" else null }\n",
                { $0.sema!.types.stringType }
            ),
            (
                "firstNotNullOfOrNull",
                "fun probe(values: Iterable<Int>): String? = values.firstNotNullOfOrNull { if (it > 1) \"hit\" else null }\n",
                { $0.sema!.types.makeNullable($0.sema!.types.stringType) }
            ),
            (
                "firstOrNull",
                "fun probe(values: Iterable<Int>): Int? = values.firstOrNull()\n",
                { $0.sema!.types.makeNullable($0.sema!.types.intType) }
            ),
            (
                "firstOrNull",
                "fun probe(values: Iterable<Int>): Int? = values.firstOrNull { it > 1 }\n",
                { $0.sema!.types.makeNullable($0.sema!.types.intType) }
            ),
        ]

        for testCase in cases {
            try withTemporaryFile(contents: testCase.source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                let errorDescriptions = errors.map { "\($0.code): \($0.message)" }
                #expect(
                    errors.isEmpty,
                    "Expected Iterable.\(testCase.name) to type-check, got: \(errorDescriptions)"
                )

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(memberCallExprID(
                    named: testCase.name,
                    in: ast,
                    path: path,
                    ctx: ctx
                ))
                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                let chosen = binding.chosenCallee

                #expect(sema.symbols.isSourceBackedSymbol(chosen))
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                #expect(sema.bindings.exprType(for: callExpr) == testCase.expectedType(ctx))

                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                let receiverType = try #require(signature.receiverType)
                guard case let .classType(receiver) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiver.classSymbol)
                else {
                    Issue.record("Expected Iterable.\(testCase.name) to have a class receiver")
                    return
                }
                #expect(
                    receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "Iterable"],
                    "Expected Iterable.\(testCase.name) receiver to be kotlin.collections.Iterable"
                )
            }
        }
    }

    private func memberCallExprID(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path,
                  case let .memberCall(_, callee, _, _, _) = expr,
                  ctx.interner.resolve(callee) == name
            else { continue }
            return exprID
        }
        return nil
    }
}
#endif
