@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LambdaDestructuringParameterTests {
    @Test(arguments: ["(a)", "(a,)", "(a: Int)", "(a: () -> Int)", "(_)", "(`a b`)", "(a): List<Int>"])
    func preservesSingleComponent(parameters: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun demo() = { \(parameters) -> 0 }",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let lambdaIndex = try #require(ast.arena.exprs.indices.first {
            if case .lambdaLiteral = ast.arena.exprs[$0] { return true }
            return false
        })
        let lambdaID = ExprID(rawValue: Int32(lambdaIndex))
        guard case let .lambdaLiteral(params, body, _, _) = ast.arena.expr(lambdaID),
              case let .blockExpr(statements, _, _) = ast.arena.expr(body),
              let declaration = statements.first,
              case let .destructuringDecl(names, isMutable, initializer, _) = ast.arena.expr(declaration),
              case let .nameRef(parameter, _) = ast.arena.expr(initializer)
        else {
            Issue.record("Expected a single-component destructuring parameter")
            return
        }
        #expect(params == [parameter])
        #expect(statements.count == 1)
        #expect(!isMutable)
        let expected: [String?] = [parameters == "(_)" ? nil : (parameters.contains("`") ? "a b" : "a")]
        #expect(names.map { $0.map(ctx.interner.resolve) } == expected)
        let annotations = ast.arena.lambdaParamTypeRefs(for: lambdaID)
        if parameters.contains("):") {
            #expect(annotations?.count == 1)
            #expect(annotations?.first.flatMap { $0 } != nil)
        } else {
            #expect(annotations == nil)
        }
    }

    @Test(arguments: ["[a, b]", "[a, b]: Pair<Int, Int>"])
    func preservesSquareBracketDestructuringParameter(parameters: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun demo() = { \(parameters) -> a + b }",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let lambdaIndex = try #require(ast.arena.exprs.indices.first {
            if case .lambdaLiteral = ast.arena.exprs[$0] { return true }
            return false
        })
        let lambdaID = ExprID(rawValue: Int32(lambdaIndex))
        guard case let .lambdaLiteral(params, body, _, _) = ast.arena.expr(lambdaID),
              case let .blockExpr(statements, _, _) = ast.arena.expr(body),
              let declaration = statements.first,
              case let .destructuringDecl(names, isMutable, initializer, _) = ast.arena.expr(declaration),
              case let .nameRef(parameter, _) = ast.arena.expr(initializer)
        else {
            Issue.record("Expected a square-bracket destructuring parameter")
            return
        }
        #expect(params == [parameter])
        #expect(!isMutable)
        #expect(names.map { $0.map(ctx.interner.resolve) } == ["a", "b"])
        #expect(ast.arena.destructuringDeclLayout(for: declaration)?.syntax == .squareBrackets)
        if parameters.contains("]:") {
            let annotations = try #require(ast.arena.lambdaParamTypeRefs(for: lambdaID))
            #expect(annotations.count == 1)
            #expect(annotations.first.flatMap { $0 } != nil)
        } else {
            #expect(ast.arena.lambdaParamTypeRefs(for: lambdaID) == nil)
        }
    }

    @Test(arguments: ["()", "(,)", "(a,,)", "(a + b)", "(a b)", "(a:)", "(a) + b", "(a); b", "(a) as (Int) -> Int"])
    func malformedPrefixesDoNotBecomeDestructuringParameters(prefix: String) throws {
        let (ast, _) = try buildASTModule(
            from: "fun demo() = { \(prefix) -> 0 }",
            includeStdlib: false
        )
        let params = try #require(ast.arena.exprs.compactMap { expr -> [InternedString]? in
            guard case let .lambdaLiteral(params, _, _, _) = expr else { return nil }
            return params
        }.first)
        #expect(params.isEmpty)
        #expect(!ast.arena.exprs.contains {
            if case .destructuringDecl = $0 { return true }
            return false
        })
    }

    @Test(arguments: [
        "acc, (direction, distance)",
        "(direction, distance), acc",
        "acc, (_, distance)",
        "acc, (direction, _)",
        "acc, (direction, distance): Pair<Point, Int>",
        "acc: Point, (direction, distance): Pair<Point, Int>",
        "(direction, distance), (other, amount)",
        "acc, (direction)",
        "(direction), acc",
        "acc, (_)",
        "acc: Point, (direction): List<Point>",
        "acc, (direction, distance,)",
        "acc, (direction: Point, distance: Int)",
        "acc, (direction: () -> Point, distance: Int)",
    ])
    func preservesParameterPositionsAndComponents(parameters: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun demo() = { \(parameters) -> 0 }",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let (params, body) = try #require(ast.arena.exprs.compactMap { expr -> ([InternedString], ExprID)? in
            guard case let .lambdaLiteral(params, body, _, _) = expr else { return nil }
            return (params, body)
        }.first)
        #expect(params.count == 2)
        guard case let .blockExpr(statements, _, _)? = ast.arena.expr(body) else {
            Issue.record("Expected destructuring declarations in the lambda body")
            return
        }
        let firstIsDestructured = parameters.hasPrefix("(")
        let bothAreDestructured = parameters.contains("(other,")
        #expect(statements.count == (bothAreDestructured ? 2 : 1))
        let componentGroups: [[String?]] = bothAreDestructured
            ? [["direction", "distance"], ["other", "amount"]]
            : parameters.contains("distance") || parameters.contains(", _)")
                ? [[parameters.contains("(_, ") ? nil : "direction",
                    parameters.contains(", _)") ? nil : "distance"]]
                : [[parameters.contains("(_)") ? nil : "direction"]]
        for (index, statement) in statements.enumerated() {
            guard case let .destructuringDecl(names, isMutable, initializer, _)? = ast.arena.expr(statement),
                  case let .nameRef(parameter, _)? = ast.arena.expr(initializer)
            else {
                Issue.record("Expected a destructuring declaration referencing its lambda parameter")
                continue
            }
            #expect(!isMutable)
            #expect(names.map { $0.map(ctx.interner.resolve) } == componentGroups[index])
            let parameterIndex = bothAreDestructured ? index : (firstIsDestructured ? 0 : 1)
            #expect(parameter == params[parameterIndex])
        }
        if !bothAreDestructured {
            #expect(ctx.interner.resolve(params[firstIsDestructured ? 1 : 0]) == "acc")
        }
        let lambdaIndex = try #require(ast.arena.exprs.indices.first { index in
            if case .lambdaLiteral = ast.arena.exprs[index] { return true }
            return false
        })
        let lambdaID = ExprID(rawValue: Int32(lambdaIndex))
        if parameters.contains("):") {
            let annotations = try #require(ast.arena.lambdaParamTypeRefs(for: lambdaID))
            #expect(annotations.count == 2)
            #expect(annotations[1] != nil)
            #expect((annotations[0] != nil) == parameters.hasPrefix("acc:"))
        }
    }

    @Test(arguments: [
        "__destructured_1, (a, b) -> __destructured_1 + a + b",
        "(__destructured_1, a), (b, c) -> __destructured_1 + a + b + c",
        "acc, (a, b) -> acc + __destructured_1",
        "acc, (a, b) -> \"$__destructured_1\"",
        "acc, (a, b) -> ::__destructured_1",
    ])
    func generatedParametersDoNotShadowUserNames(lambda: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun demo() = { \(lambda) }",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let params = try #require(ast.arena.exprs.compactMap { expr -> [InternedString]? in
            guard case let .lambdaLiteral(params, _, _, _) = expr else { return nil }
            return params
        }.first)
        #expect(params.count == 2)
        #expect(Set(params).count == 2)
        #expect(ctx.interner.resolve(params[1]) != "__destructured_1")
        if lambda.hasPrefix("__destructured_1,") {
            #expect(ctx.interner.resolve(params[0]) == "__destructured_1")
        }
    }
}
