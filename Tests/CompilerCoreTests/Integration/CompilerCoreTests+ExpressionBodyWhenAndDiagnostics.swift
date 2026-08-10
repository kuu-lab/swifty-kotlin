#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {

    @Test func testExpressionBodyWhenAndDiagnostics() throws {
        let sources: [String] = [
            // 0: subject-less when guard chain with else
            """
            package sample0
            fun classify(x: Int, y: Int): Int = when {
                x > 0 -> 1
                y > 0 -> 2
                else -> 0
            }
            """,

            // 1: subject-less when without else is non-exhaustive
            """
            package sample1
            fun classify(x: Int): Int {
                when {
                    x > 0 -> 1
                }
            }
            """,

            // 2: subject-less when with non-boolean condition
            """
            package sample2
            fun test() = when {
                42 -> "invalid"
                else -> "ok"
            }
            """,

            // 3: unresolved identifier
            """
            package sample3
            fun test() = unknownVariable
            """,

            // 4: unresolved function call
            """
            package sample4
            fun test() = unknownFunction(1)
            """,

            // 5: unresolved type annotation
            """
            package sample5
            fun test(x: UnknownType) = x
            """,

            // 6: function expression-body when remains expression body
            """
            package sample6
            fun classifyExpr(v: Int) = when (v) {
                0 -> 10
                else -> 20
            }
            """,

            // 7: block body splits statements on newline
            """
            package sample7
            fun main7() {
                println(1)
                println(2)
            }
            """,

            // 8: do-while inline body parses condition outside body
            """
            package sample8
            fun main8(): Int {
                var x = 0
                do x = x + 1 while (x < 3)
                return x
            }
            """,

            // 9: lambda literal expression body parses as dedicated expr node
            """
            package sample9
            fun build9() = { x: Int -> x + 1 }
            """,

            // 10: object literal expression body parses as dedicated expr node
            """
            package sample10
            interface I
            fun build10() = object : I {}
            """,

            // 11: callable reference expression body parses as dedicated expr node
            """
            package sample11
            fun target11(x: Int) = x
            fun unbound11() = ::target11
            fun bound11(x: Int) = x::toString
            """,

            // 12: subject-less when parses correctly
            """
            package sample12
            fun classifySubjectless(x: Int, y: Int): Int {
                return when {
                    x > 0 -> 1
                    y > 0 -> 2
                    else -> 0
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // 0
            do {
                let sampleDiags = diagnosticsForPath(paths[0], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
            }

            // 1
            do {
                let sampleDiags = diagnosticsForPath(paths[1], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
            }

            // 2
            do {
                let sampleDiags = diagnosticsForPath(paths[2], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0032", in: sampleDiags)
            }

            // 3
            do {
                let sampleDiags = diagnosticsForPath(paths[3], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)
            }

            // 4
            do {
                let sampleDiags = diagnosticsForPath(paths[4], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)
            }

            // 5
            do {
                let sampleDiags = diagnosticsForPath(paths[5], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)
            }

            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            // 6
            do {
                let function = try #require(topLevelFunction(named: "classifyExpr", in: ast, interner: interner))
                switch function.body {
                case let .expr(exprID, _):
                    guard let expr = ast.arena.expr(exprID),
                          case let .whenExpr(_, branches, elseExpr, _) = expr
                    else {
                        Issue.record("Expected expression body to be parsed as when expression.")
                        return
                    }
                    #expect(branches.count == 1)
                    #expect(elseExpr != nil)
                case .block, .unit:
                    Issue.record("Expression-body function must not be parsed as block body.")
                }
            }

            // 7
            do {
                let function = try #require(topLevelFunction(named: "main7", in: ast, interner: interner))
                switch function.body {
                case let .block(exprIDs, _):
                    #expect(exprIDs.count == 2)
                    for exprID in exprIDs {
                        guard let expr = ast.arena.expr(exprID), case .call = expr else {
                            Issue.record("Expected block statement to parse as call expression.")
                            return
                        }
                    }
                case .expr, .unit:
                    Issue.record("Block-body function should produce block expressions.")
                }
            }

            // 8
            do {
                let function = try #require(topLevelFunction(named: "main8", in: ast, interner: interner))
                guard case let .block(stmts, _) = function.body else {
                    Issue.record("Expected block-body function.")
                    return
                }
                let doWhileExprID = try #require(stmts.first(where: { exprID in
                    guard let expr = ast.arena.expr(exprID) else { return false }
                    if case .doWhileExpr = expr { return true }
                    return false
                }))

                guard let doWhileExpr = ast.arena.expr(doWhileExprID),
                      case let .doWhileExpr(bodyExprID, conditionExprID, _, _) = doWhileExpr
                else {
                    Issue.record("Expected do-while expression.")
                    return
                }

                guard let bodyExpr = ast.arena.expr(bodyExprID),
                      case let .localAssign(name, _, _) = bodyExpr
                else {
                    Issue.record("Expected inline do-while body to parse as local assignment.")
                    return
                }
                #expect(interner.resolve(name) == "x")

                guard let conditionExpr = ast.arena.expr(conditionExprID),
                      case let .binary(op, _, _, _) = conditionExpr
                else {
                    Issue.record("Expected do-while condition to parse as binary expression.")
                    return
                }
                #expect(op == .lessThan)

                if let bodyRange = ast.arena.exprRange(bodyExprID),
                   let conditionRange = ast.arena.exprRange(conditionExprID)
                {
                    #expect(bodyRange.end.offset <= conditionRange.start.offset)
                }
            }

            // 9
            do {
                let function = try #require(topLevelFunction(named: "build9", in: ast, interner: interner))
                guard case let .expr(exprID, _) = function.body,
                      let expr = ast.arena.expr(exprID),
                      case let .lambdaLiteral(params, bodyExprID, _, _) = expr
                else {
                    Issue.record("Expected lambda literal expression body.")
                    return
                }

                #expect(params.map { interner.resolve($0) } == ["x"])
                let effectiveBodyID: ExprID = if let bodyExpr = ast.arena.expr(bodyExprID),
                                                 case let .blockExpr(_, trailing, _) = bodyExpr,
                                                 let trailingID = trailing
                {
                    trailingID
                } else {
                    bodyExprID
                }
                guard let bodyExpr = ast.arena.expr(effectiveBodyID),
                      case .binary = bodyExpr
                else {
                    Issue.record("Expected parsed lambda body expression.")
                    return
                }
            }

            // 10
            do {
                let function = try #require(topLevelFunction(named: "build10", in: ast, interner: interner))
                guard case let .expr(exprID, _) = function.body,
                      let expr = ast.arena.expr(exprID),
                      case let .objectLiteral(superTypes, _, _) = expr
                else {
                    Issue.record("Expected object literal expression body.")
                    return
                }

                #expect(superTypes.count == 1)
                let superType = try #require(ast.arena.typeRef(superTypes[0]))
                guard case let .named(path, _, _) = superType,
                      let first = path.first
                else {
                    Issue.record("Expected named super type in object literal.")
                    return
                }
                #expect(interner.resolve(first) == "I")
            }

            // 11
            do {
                let unbound = try #require(topLevelFunction(named: "unbound11", in: ast, interner: interner))
                guard case let .expr(unboundExprID, _) = unbound.body,
                      let unboundExpr = ast.arena.expr(unboundExprID),
                      case let .callableRef(unboundReceiver, unboundMember, _) = unboundExpr
                else {
                    Issue.record("Expected unbound callable reference.")
                    return
                }
                #expect(unboundReceiver == nil)
                #expect(interner.resolve(unboundMember) == "target11")

                let bound = try #require(topLevelFunction(named: "bound11", in: ast, interner: interner))
                guard case let .expr(boundExprID, _) = bound.body,
                      let boundExpr = ast.arena.expr(boundExprID),
                      case let .callableRef(boundReceiver, boundMember, _) = boundExpr
                else {
                    Issue.record("Expected bound callable reference.")
                    return
                }
                #expect(interner.resolve(boundMember) == "toString")
                let receiverExprID = try #require(boundReceiver)
                guard let receiverExpr = ast.arena.expr(receiverExprID),
                      case let .nameRef(receiverName, _) = receiverExpr
                else {
                    Issue.record("Expected callable reference receiver expression.")
                    return
                }
                #expect(interner.resolve(receiverName) == "x")
            }

            // 12
            do {
                let function = try #require(topLevelFunction(named: "classifySubjectless", in: ast, interner: interner))
                switch function.body {
                case let .block(stmts, _):
                    guard let returnExprID = stmts.first,
                          let returnExpr = ast.arena.expr(returnExprID),
                          case let .returnExpr(whenID, _, _) = returnExpr,
                          let whenID,
                          let whenExpr = ast.arena.expr(whenID),
                          case let .whenExpr(subject, branches, elseExpr, _) = whenExpr
                    else {
                        Issue.record("Expected return of when expression.")
                        return
                    }
                    #expect(subject == nil, "Subject-less when must have nil subject.")
                    #expect(branches.count == 2)
                    #expect(elseExpr != nil)
                case .expr, .unit:
                    Issue.record("Block-body function should produce block expressions.")
                }
            }
        }
    }

    @Test func testDriverReportsPipelineOutputUnavailableWithoutICE() throws {
        let source = "fun main() = 0"
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
        let outputBase = missingDir.appendingPathComponent("result").path

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = makeTestOptions(
                moduleName: "PipelineFailure",
                inputs: [tempSourcePath],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(result.exitCode == 1)
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-PIPELINE-0003" })
            #expect(!(result.diagnostics.contains { $0.code == "KSWIFTK-ICE-0001" }))
        }
    }
}
#endif
