@testable import CompilerCore
import Foundation
import Testing

/// Verifies `String?.toBoolean()` (STDLIB-TEXT-FN-087) resolves cleanly in Sema
/// for both nullable and non-null receivers and lowers through to the runtime
/// helper `kk_string_toBoolean_flat`, which is classified as non-throwing per
/// Kotlin's specification (`null.toBoolean()` returns `false`, never throws).
@Suite
struct StringToBooleanFunctionTests {
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

    @Test func testToBooleanResolvesInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun parseNullable(value: String?): Boolean {
                return value.toBoolean()
            }

            fun parseNonNull(value: String): Boolean {
                return value.toBoolean()
            }

            fun parseStrictOrNull(value: String): Boolean? {
                return value.toBooleanStrictOrNull()
            }
            """,
            """
            package sample1
            fun mainFlat() {
                val missing: String? = null
                missing.toBoolean()
                val present: String? = "TRUE"
                present.toBoolean()
                val concrete: String = "false"
                concrete.toBoolean()
            }
            """,
            """
            package sample2
            fun mainOrNull() {
                val yes: String = "true"
                yes.toBooleanStrictOrNull()
                val no: String = "false"
                no.toBooleanStrictOrNull()
                val other: String = "yes"
                other.toBooleanStrictOrNull()
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
                    "Expected toBoolean/toBooleanStrictOrNull to resolve cleanly, got: \(pathDiagnostics)"
                )
            }

            let path0 = paths[0]
            guard let fileID = ctx.sourceManager.fileID(forPath: path0) else {
                Issue.record("Missing file ID for sample0"); return
            }

            let toBooleanCalls = allMemberCallExprIDs(named: "toBoolean", in: ast, fileID: fileID, interner: interner)
            #expect(toBooleanCalls.count == 2)
            for callID in toBooleanCalls {
                let exprType = try #require(sema.bindings.exprTypes[callID])
                #expect(
                    exprType == sema.types.booleanType,
                    "toBoolean should be typed as Boolean"
                )
            }

            let orNullCalls = allMemberCallExprIDs(named: "toBooleanStrictOrNull", in: ast, fileID: fileID, interner: interner)
            #expect(orNullCalls.count == 1)
            let orNullType = try #require(sema.bindings.exprTypes[orNullCalls[0]])
            #expect(
                orNullType == sema.types.make(.primitive(.boolean, .nullable)),
                "toBooleanStrictOrNull should be typed as nullable Boolean (Boolean?)"
            )

            let module = try #require(ctx.kir)

            // === testToBooleanLowersToRuntimeHelperNonThrowing ===
            do {

                let body = try findKIRFunctionBody(named: "mainFlat", in: module, interner: interner)
                let throwFlags = extractThrowFlags(from: body, interner: interner)
                let toBooleanFlags = try #require(
                    throwFlags["kk_string_toBoolean"],
                    "Expected kk_string_toBoolean calls to appear in mainFlat()"
                )
                #expect(toBooleanFlags.count == 3)
                #expect(
                    toBooleanFlags.allSatisfy { $0 == false },
                    "kk_string_toBoolean must be lowered as non-throwing"
                )
            }

            // === testToBooleanStrictOrNullLowersToRuntimeHelperNonThrowing ===
            do {

                let body = try findKIRFunctionBody(named: "mainOrNull", in: module, interner: interner)
                let throwFlags = extractThrowFlags(from: body, interner: interner)
                let orNullFlags = try #require(
                    throwFlags["kk_string_toBooleanStrictOrNull_flat"],
                    "Expected kk_string_toBooleanStrictOrNull_flat calls to appear in mainOrNull()"
                )
                #expect(orNullFlags.count == 3)
                #expect(
                    orNullFlags.allSatisfy { $0 == false },
                    "kk_string_toBooleanStrictOrNull_flat must be lowered as non-throwing"
                )
            }
        }
    }
}
