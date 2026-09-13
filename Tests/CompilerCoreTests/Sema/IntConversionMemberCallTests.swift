#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntConversionMemberCallTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testIntConversionCallsInferRuntimeFriendlyTypes
            """
            package sample0

                    fun sample(x: Int) {
                        x.toFloat()
                        x.toByte()
                        x.toShort()
                    }

            """,
            // testLongAndDoubleToIntNarrowingConversionInfersIntType
            """
            package sample1

                    fun sample(l: Long, d: Double) {
                        l.toInt()
                        d.toInt()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testIntConversionCallsInferRuntimeFriendlyTypes ===

            do {

                let sample0Path = paths[0]



                let expectedTypes: [String: TypeID] = [
                    "toFloat": sema.types.floatType,
                    "toByte": sema.types.byteType,
                    "toShort": sema.types.shortType,
                ]

                for memberName in expectedTypes.keys {
                    let callExpr = try #require(
                        firstExprID(in: ast, path: sample0Path, ctx: ctx) { exprID, expr in
                            guard case let .memberCall(_, callee, _, _, _) = expr,
                                  interner.resolve(callee) == memberName,
                                  let range = ast.arena.exprRange(exprID)
                            else {
                                return false
                            }
                            return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                        },
                        "Expected a call expression for \(memberName)"
                    )
                    #expect(
                        sema.bindings.exprTypes[callExpr] == expectedTypes[memberName],
                        "\(memberName) should infer expected return type"
                    )
                }

            }

            // === testLongAndDoubleToIntNarrowingConversionInfersIntType ===

            do {




                // Collect the last 2 toInt() calls in the arena (user-file calls come after bundled stdlib).
                var toIntCallExprIDs: [ExprID] = []
                for index in ast.arena.exprs.indices.reversed() {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID) else { continue }
                    guard case let .memberCall(_, callee, _, _, _) = expr else { continue }
                    if interner.resolve(callee) == "toInt" {
                        toIntCallExprIDs.insert(exprID, at: 0)
                        if toIntCallExprIDs.count == 2 { break }
                    }
                }
                #expect(toIntCallExprIDs.count == 2, "Expected two toInt() calls")
                for exprID in toIntCallExprIDs {
                    #expect(
                        sema.bindings.exprTypes[exprID] == sema.types.intType,
                        "Long.toInt() and Double.toInt() should infer Int return type"
                    )
                }

            }

        }
    }

    @Test
    func testIntConversionsResolveThroughBundledKotlin() throws {
        let source = """
        fun main() {
            val value: Int = 16777217
            println(value.toChar().code)
            println(value.toDouble())
            val nullable: Int? = value
            println(nullable?.toChar()?.code)
            println(nullable?.toDouble())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Int conversions should type-check")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
            var resolvedNames: [String] = []

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      ast.arena.exprRange(exprID)?.start.file == fileID
                else {
                    continue
                }

                let calleeName: InternedString
                switch expr {
                case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                    calleeName = name
                default:
                    continue
                }

                let name = ctx.interner.resolve(calleeName)
                guard ["toChar", "toDouble"].contains(name),
                      let binding = sema.bindings.callBinding(for: exprID)
                else {
                    continue
                }

                resolvedNames.append(name)
                #expect(
                    sema.symbols.isSourceBackedSymbol(binding.chosenCallee),
                    "Int.\(name) must resolve to bundled Kotlin source"
                )
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == nil,
                    "The public Int.\(name) API must not carry a direct runtime link"
                )
            }

            #expect(resolvedNames.count == 4, "Expected regular and safe Int conversion calls")
            #expect(resolvedNames.contains("toChar"))
            #expect(resolvedNames.contains("toDouble"))
        }
    }

}

#endif
