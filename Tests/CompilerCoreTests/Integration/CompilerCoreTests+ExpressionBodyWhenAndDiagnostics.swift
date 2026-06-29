#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {
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

    @Test func testFunctionExpressionBodyWhenRemainsExpressionBody() throws {
        let source = """
        fun classify(v: Int) = when (v) {
            0 -> 10
            else -> 20
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let file = try #require(ast.files.first)
        let declID = try #require(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            Issue.record("Expected top-level function declaration.")
            return
        }

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

    @Test func testBlockBodySplitsStatementsOnNewline() throws {
        let source = """
        fun main() {
            println(1)
            println(2)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let file = try #require(ast.files.first)
        let declID = try #require(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            Issue.record("Expected top-level function declaration.")
            return
        }

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

    @Test func testDoWhileInlineBodyParsesConditionOutsideBody() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do x = x + 1 while (x < 3)
            return x
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
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
        #expect(ctx.interner.resolve(name) == "x")

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

    @Test func testLambdaLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun build() = { x: Int -> x + 1 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .lambdaLiteral(params, bodyExprID, _, _) = expr
        else {
            Issue.record("Expected lambda literal expression body.")
            return
        }

        #expect(params.map { ctx.interner.resolve($0) } == ["x"])
        // Lambda body may be wrapped in blockExpr(statements: [], trailingExpr: expr)
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

    @Test func testObjectLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        interface I
        fun build() = object : I {}
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
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
        #expect(ctx.interner.resolve(first) == "I")
    }

    @Test func testCallableReferenceExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun target(x: Int) = x
        fun unbound() = ::target
        fun bound(x: Int) = x::toString
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let unbound = try #require(topLevelFunction(named: "unbound", in: ast, interner: ctx.interner))
        guard case let .expr(unboundExprID, _) = unbound.body,
              let unboundExpr = ast.arena.expr(unboundExprID),
              case let .callableRef(unboundReceiver, unboundMember, _) = unboundExpr
        else {
            Issue.record("Expected unbound callable reference.")
            return
        }
        #expect(unboundReceiver == nil)
        #expect(ctx.interner.resolve(unboundMember) == "target")

        let bound = try #require(topLevelFunction(named: "bound", in: ast, interner: ctx.interner))
        guard case let .expr(boundExprID, _) = bound.body,
              let boundExpr = ast.arena.expr(boundExprID),
              case let .callableRef(boundReceiver, boundMember, _) = boundExpr
        else {
            Issue.record("Expected bound callable reference.")
            return
        }
        #expect(ctx.interner.resolve(boundMember) == "toString")
        let receiverExprID = try #require(boundReceiver)
        guard let receiverExpr = ast.arena.expr(receiverExprID),
              case let .nameRef(receiverName, _) = receiverExpr
        else {
            Issue.record("Expected callable reference receiver expression.")
            return
        }
        #expect(ctx.interner.resolve(receiverName) == "x")
    }

    @Test func testSubjectLessWhenParsesCorrectly() throws {
        let source = """
        fun classify(x: Int, y: Int): Int {
            return when {
                x > 0 -> 1
                y > 0 -> 2
                else -> 0
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let file = try #require(ast.files.first)
        let declID = try #require(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            Issue.record("Expected top-level function declaration.")
            return
        }

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

    @Test func testSubjectLessWhenGuardChainSemaPassesWithElse() throws {
        let source = """
        fun classify(x: Int, y: Int): Int = when {
            x > 0 -> 1
            y > 0 -> 2
            else -> 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testSubjectLessWhenWithoutElseIsNonExhaustive() throws {
        let source = """
        fun classify(x: Int): Int {
            when {
                x > 0 -> 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testSubjectLessWhenWithNonBooleanConditionEmitsDiagnostic() throws {
        let source = """
        fun test() = when {
            42 -> "invalid"
            else -> "ok"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    @Test func testUnresolvedIdentifierEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownVariable
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    @Test func testUnresolvedFunctionCallEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownFunction(1)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    @Test func testUnresolvedTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(x: UnknownType) = x
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

}
#endif
