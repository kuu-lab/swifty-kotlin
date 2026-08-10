#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-001/039/040: Consolidated Sema coverage for String HOFs
/// (`all`, `onEach`, `onEachIndexed`). A single `runSema(ctx)` resolves all source
/// packages and each `do` block verifies the call count and return type.
@Suite
struct StringHofFunctionTests {
    private func memberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path,
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { return nil }
            return exprID
        }
    }

    @Test
    func testStringHofFunctionsResolveAndReturnCorrectType() throws {
        let sources: [String] = [
            """
            package sample0
            fun allDigits(value: String): Boolean {
                return value.all { c -> c.isDigit() }
            }

            fun allUppercase(): Boolean {
                return "HELLO".all { it.isUpperCase() }
            }
            """,
            """
            package sample1
            fun logChars(value: String): String {
                return value.onEach { c -> print(c) }
            }

            fun logLiteral(): String {
                return "hello".onEach { print(it) }
            }
            """,
            """
            package sample2
            fun logIndexedChars(value: String): String {
                return value.onEachIndexed { i, c -> print("$i:$c") }
            }

            fun logLiteralIndexed(): String {
                return "hello".onEachIndexed { index, ch -> print(index) }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let pathDiagnostics = diagnosticsForPath(paths[0], in: ctx)
            let errors = pathDiagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected String HOFs to resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            // === all ===
            do {
                let path = paths[0]
                let callIDs = memberCallExprIDs(named: "all", in: ast, path: path, ctx: ctx, interner: interner)
                #expect(callIDs.count == 2, "Expected two String.all call sites")
                for callID in callIDs {
                    let exprType = try #require(sema.bindings.exprType(for: callID))
                    #expect(
                        exprType == sema.types.booleanType,
                        "String.all should be typed as Boolean"
                    )
                }
            }

            // === onEach ===
            do {
                let path = paths[1]
                let callIDs = memberCallExprIDs(named: "onEach", in: ast, path: path, ctx: ctx, interner: interner)
                #expect(callIDs.count == 2, "Expected two String.onEach call sites")
                for callID in callIDs {
                    let exprType = try #require(sema.bindings.exprType(for: callID))
                    #expect(
                        exprType == sema.types.stringType,
                        "String.onEach should be typed as String"
                    )
                }
            }

            // === onEachIndexed ===
            do {
                let path = paths[2]
                let callIDs = memberCallExprIDs(named: "onEachIndexed", in: ast, path: path, ctx: ctx, interner: interner)
                #expect(callIDs.count == 2, "Expected two String.onEachIndexed call sites")
                for callID in callIDs {
                    let exprType = try #require(sema.bindings.exprType(for: callID))
                    #expect(
                        exprType == sema.types.stringType,
                        "String.onEachIndexed should be typed as String"
                    )
                }
            }
        }
    }
}
#endif
