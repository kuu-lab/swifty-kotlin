#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {
    @Test func testTrailingLambdaParsing() throws {
        let sources: [String] = [
            // 0: without parens parses as call expression
            """
            package sample0
            fun apply(block: () -> Int): Int = block()
            fun main0(): Int = apply { 42 }
            """,

            // 1: with explicit type arguments parses as call expression
            """
            package sample1
            fun <T> build(block: () -> T): T = block()
            fun main1(): Int = build<Int> { 1 }
            """,

            // 2: with multiple statements parses as lambda block body
            """
            package sample2
            fun main2() {
                val s = buildString {
                    append("hello ")
                    append("world")
                }
                println(s)
            }
            """,

            // 3: member trailing lambda with two parameters
            """
            package sample3
            fun main3() {
                val values = listOf(1, 2, 3)
                val total = values.fold(0) { acc, value -> acc + value }
                println(total)
            }
            """,

            // 4: parenthesized call with two lambda arguments
            """
            package sample4
            fun foo(a: () -> Int, b: () -> String): Int = 0
            fun main4(): Int = foo({ 42 }, { "x" })
            """,

            // 5: top-level property with generic trailing lambda initializer
            """
            package sample5
            fun <T> build(block: () -> T): T = block()
            val topLevelValue5 = build<Int> { 1 }
            """,

            // 6: top-level property with non-generic trailing lambda initializer
            """
            package sample6
            fun apply(block: () -> Int): Int = block()
            val topLevelValue6 = apply { 42 }
            """,

            // 7: class member property with generic trailing lambda initializer
            """
            package sample7
            fun <T> build(block: () -> T): T = block()
            class Holder {
                val member = build<Int> { 7 }
            }
            """,

            // 8: top-level property trailing lambda preserves inner semicolons
            """
            package sample8
            fun apply(block: () -> Int): Int = block()
            val topLevelValue8 = apply { val x = 42; x }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            // 0
            do {
                let function = try #require(topLevelFunction(named: "main0", in: ast, interner: interner))
                guard case let .expr(exprID, _) = function.body,
                      let expr = ast.arena.expr(exprID),
                      case let .call(calleeID, _, args, _) = expr
                else {
                    Issue.record("Expected trailing lambda call to parse as call expression.")
                    return
                }

                #expect(args.count == 1)
                guard let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    Issue.record("Expected call callee to be a name reference.")
                    return
                }
                #expect(interner.resolve(calleeName) == "apply")

                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected trailing lambda argument.")
                    return
                }
            }

            // 1
            do {
                let function = try #require(topLevelFunction(named: "main1", in: ast, interner: interner))
                guard case let .expr(exprID, _) = function.body,
                      let expr = ast.arena.expr(exprID),
                      case let .call(_, typeArgs, args, _) = expr
                else {
                    Issue.record("Expected generic trailing lambda call to parse as call expression.")
                    return
                }

                #expect(typeArgs.count == 1)
                #expect(args.count == 1)
            }

            // 2
            do {
                let function = try #require(topLevelFunction(named: "main2", in: ast, interner: interner))
                guard case let .block(statements, _) = function.body,
                      let localDeclID = statements.first,
                      let localDeclExpr = ast.arena.expr(localDeclID),
                      case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
                      let callExprID = initializer,
                      let callExpr = ast.arena.expr(callExprID),
                      case let .call(_, _, args, _) = callExpr,
                      let lambdaArg = args.first,
                      let lambdaExpr = ast.arena.expr(lambdaArg.expr),
                      case let .lambdaLiteral(_, lambdaBodyID, _, _) = lambdaExpr,
                      let lambdaBody = ast.arena.expr(lambdaBodyID),
                      case let .blockExpr(bodyStatements, trailingExpr, _) = lambdaBody
                else {
                    Issue.record("Expected builder trailing lambda body to be parsed as block expression.")
                    return
                }

                #expect(bodyStatements.count == 1)
                let firstStmtID = try #require(bodyStatements.first)
                let trailingID = try #require(trailingExpr)
                guard let firstStmt = ast.arena.expr(firstStmtID), case .call = firstStmt else {
                    Issue.record("Expected first lambda statement to be a call expression.")
                    return
                }
                guard let trailing = ast.arena.expr(trailingID), case .call = trailing else {
                    Issue.record("Expected trailing lambda expression to be a call expression.")
                    return
                }
            }

            // 3
            do {
                let function = try #require(topLevelFunction(named: "main3", in: ast, interner: interner))
                guard case let .block(statements, _) = function.body,
                      statements.count >= 2,
                      let localDeclExpr = ast.arena.expr(statements[1]),
                      case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
                      let callExprID = initializer,
                      let callExpr = ast.arena.expr(callExprID),
                      case let .memberCall(_, calleeName, _, args, _) = callExpr,
                      interner.resolve(calleeName) == "fold",
                      args.count == 2,
                      let lambdaExpr = ast.arena.expr(args[1].expr),
                      case let .lambdaLiteral(params, bodyExprID, _, _) = lambdaExpr,
                      let bodyExpr = ast.arena.expr(bodyExprID)
                else {
                    Issue.record("Expected fold call with trailing lambda argument.")
                    return
                }

                #expect(params.map(interner.resolve) == ["acc", "value"])
                guard case .binary = bodyExpr else {
                    Issue.record("Expected lambda body to parse as a binary expression.")
                    return
                }
            }

            // 4
            do {
                let function = try #require(topLevelFunction(named: "main4", in: ast, interner: interner))
                guard case let .expr(exprID, _) = function.body,
                      let expr = ast.arena.expr(exprID),
                      case let .call(calleeID, _, args, _) = expr
                else {
                    Issue.record("Expected parenthesized lambda call to parse as a call expression.")
                    return
                }

                guard args.count == 2 else {
                    Issue.record("Expected two lambda arguments, got \(args.count).")
                    return
                }
                guard let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    Issue.record("Expected call callee to be a name reference.")
                    return
                }
                #expect(interner.resolve(calleeName) == "foo")

                guard let firstArgExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = firstArgExpr
                else {
                    Issue.record("Expected first argument to be a lambda literal.")
                    return
                }

                guard let secondArgExpr = ast.arena.expr(args[1].expr),
                      case .lambdaLiteral = secondArgExpr
                else {
                    Issue.record("Expected second argument to be a lambda literal.")
                    return
                }
            }

            // 5
            do {
                let property = try #require(topLevelProperty(named: "topLevelValue5", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .call(calleeID, typeArgs, args, _) = initializerExpr
                else {
                    Issue.record("Expected property initializer to parse as a call expression.")
                    return
                }

                #expect(typeArgs.count == 1)
                #expect(args.count == 1)
                guard let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    Issue.record("Expected call callee to be a name reference.")
                    return
                }
                #expect(interner.resolve(calleeName) == "build")
                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected trailing lambda argument.")
                    return
                }
            }

            // 6
            do {
                let property = try #require(topLevelProperty(named: "topLevelValue6", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .call(_, _, args, _) = initializerExpr
                else {
                    Issue.record("Expected property initializer to parse as a call expression.")
                    return
                }
                #expect(args.count == 1)
                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected trailing lambda argument.")
                    return
                }
            }

            // 7
            do {
                var memberProperty: PropertyDecl?
                outer: for file in ast.files {
                    for declID in file.topLevelDecls {
                        guard let decl = ast.arena.decl(declID),
                              case let .classDecl(classDecl) = decl
                        else { continue }
                        for propertyDeclID in classDecl.memberProperties {
                            guard let propertyDecl = ast.arena.decl(propertyDeclID),
                                  case let .propertyDecl(property) = propertyDecl,
                                  interner.resolve(property.name) == "member"
                            else { continue }
                            memberProperty = property
                            break outer
                        }
                    }
                }
                let property = try #require(memberProperty)
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .call(_, typeArgs, args, _) = initializerExpr
                else {
                    Issue.record("Expected member property initializer to parse as a call expression.")
                    return
                }
                #expect(typeArgs.count == 1)
                #expect(args.count == 1)
                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected trailing lambda argument.")
                    return
                }
            }

            // 8
            do {
                let property = try #require(topLevelProperty(named: "topLevelValue8", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .call(_, _, args, _) = initializerExpr
                else {
                    Issue.record("Expected property initializer to parse as a call expression.")
                    return
                }
                #expect(args.count == 1)
                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected trailing lambda argument.")
                    return
                }
            }
        }
    }
}
#endif
