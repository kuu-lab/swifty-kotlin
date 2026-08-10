@testable import CompilerCore
import Foundation
import Testing

/// Verifies CharSequence?.isNullOrBlank() (STDLIB-TEXT-FN-032) resolves cleanly
/// in Sema through bundled Kotlin source.
@Suite
struct StringIsNullOrBlankFunctionTests {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        fileID: FileID,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  range.start.file == fileID,
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    @Test func testIsNullOrBlankResolvesInSource() throws {
        let sources: [String] = [
            """
            package sample0

            fun classifyNullable(value: String?): Boolean {
                return value.isNullOrBlank()
            }

            fun classifyNonNull(value: String): Boolean {
                return value.isNullOrBlank()
            }
            """,
            """
            fun main() {
                val maybe: String? = null
                maybe.isNullOrBlank()
                val present: String? = "  "
                present.isNullOrBlank()
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToLowering(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for (index, _) in sources.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains(where: { $0.severity == .error }),
                    "Expected isNullOrBlank to resolve cleanly, got: \(pathDiagnostics)"
                )
            }

            let path0 = paths[0]
            guard let fileID = ctx.sourceManager.fileID(forPath: path0) else {
                Issue.record("Missing file ID for sample0"); return
            }
            let callIDs = allMemberCallExprIDs(
                named: "isNullOrBlank",
                in: ast,
                fileID: fileID,
                interner: interner
            )
            #expect(callIDs.count == 2, "Expected calls for nullable and non-null receivers")
            for callID in callIDs {
                let exprType = try #require(sema.bindings.exprTypes[callID])
                #expect(
                    exprType == sema.types.booleanType,
                    "isNullOrBlank should be typed as Boolean"
                )
            }

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: interner)
            let throwFlags = extractThrowFlags(from: body, interner: interner)
            #expect(throwFlags["kk_string_isNullOrBlank"] == nil)
            #expect(throwFlags["kk_string_isNullOrBlank_flat"] == nil)
            #expect(throwFlags["__string_isNullOrBlank_flat"] == nil)
        }
    }
}
