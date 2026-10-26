#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenInfixExpressionBodyTests {
    @Test
    func day18ShapedExpressionRetainsChainedInfixArgument() throws {
        let source = """
        class Day18 {
            private fun parseRowPart1(input: String): Pair<Point2D, Int> =
                when (input[0]) {
                    'U' -> NORTH
                    'D' -> SOUTH
                    'L' -> WEST
                    'R' -> EAST
                    else -> throw IllegalStateException("Bad direction $input")
                } to input.substringAfter(" ").substringBefore(" ").toInt()
            private fun parseRowPart2(input: String) = input
        }
        """
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let function = try #require(firstFunDecl(named: "parseRowPart1", in: ast, interner: ctx.interner))
        guard case let .expr(pair, _) = function.body,
              case let .memberCall(receiver, callee, _, arguments, _) = ast.arena.expr(pair),
              case let .whenExpr(_, branches, elseExpr, _) = ast.arena.expr(receiver)
        else {
            Issue.record("Expected parseRowPart1 to retain the when receiver and infix call")
            return
        }
        #expect(ctx.interner.resolve(callee) == "to")
        #expect(branches.count == 4)
        #expect(elseExpr != nil)
        #expect(arguments.count == 1)
        guard case let .memberCall(_, argumentCallee, _, _, _) = ast.arena.expr(try #require(arguments.first).expr) else {
            Issue.record("Expected the chained infix argument to remain in parseRowPart1")
            return
        }
        #expect(ctx.interner.resolve(argumentCallee) == "toInt")
        #expect(firstFunDecl(named: "parseRowPart2", in: ast, interner: ctx.interner) != nil)
    }

    @Test(arguments: [false, true], [false, true])
    func whenToPairPreservesFunctionBody(member: Bool, blockBody: Bool) throws {
        let expression = """
        when (flag) {
            true -> 1
            false -> 2
        } to 3
        """
        let body = blockBody ? "{ return \(expression) }" : "= \(expression)"
        let declarations = """
        \(member ? "private " : "")fun choose(flag: Boolean): Pair<Int, Int> \(body)
        fun after() = 4
        class After
        val marker = 5
        """
        let source = (member ? "class Demo {\n\(declarations)\n}" : declarations)
            + "\nfun main() {}"
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let choose = try #require(firstFunDecl(named: "choose", in: ast, interner: ctx.interner))
        let pair: ExprID
        if blockBody {
            guard case let .block(statements, _) = choose.body,
                  statements.count == 1,
                  case let .returnExpr(value, _, _) = ast.arena.expr(statements[0])
            else {
                Issue.record("Expected a block body returning the complete infix expression")
                return
            }
            pair = try #require(value)
        } else {
            guard case let .expr(value, _) = choose.body else {
                Issue.record("Expected the infix expression to remain an expression body")
                return
            }
            pair = value
        }
        guard case let .memberCall(receiver, callee, _, arguments, _) = ast.arena.expr(pair),
              case let .whenExpr(_, branches, _, _) = ast.arena.expr(receiver)
        else {
            Issue.record("Expected an infix call with the when expression as receiver")
            return
        }
        #expect(ctx.interner.resolve(callee) == "to")
        #expect(branches.count == 2)
        #expect(arguments.count == 1)
        guard case let .intLiteral(value, _) = ast.arena.expr(try #require(arguments.first).expr) else {
            Issue.record("Expected the infix argument to be retained")
            return
        }
        #expect(value == 3)
        #expect(firstFunDecl(named: "after", in: ast, interner: ctx.interner) != nil)
        let file = try #require(ast.files.first)
        #expect(file.topLevelDecls.count == (member ? 2 : 5))
        #expect(file.topLevelDecls.filter {
            guard case let .funDecl(function) = ast.arena.decl($0) else { return false }
            return ctx.interner.resolve(function.name) == "main"
        }.count == 1)
        if member {
            guard case let .classDecl(demo) = ast.arena.decl(try #require(file.topLevelDecls.first)) else {
                Issue.record("Expected the member declarations to remain in Demo")
                return
            }
            #expect(demo.memberFunctions.count == 2)
            #expect(demo.nestedClasses.count == 1)
            #expect(demo.memberProperties.count == 1)
        }
    }
}
#endif
