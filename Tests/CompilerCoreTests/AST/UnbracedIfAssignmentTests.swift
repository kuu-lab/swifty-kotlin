@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct UnbracedIfAssignmentTests {
    private func parsedIf(in context: CompilationContext) throws -> (ASTModule, Expr) {
        let ast = try #require(context.ast)
        let file = try #require(ast.files.first {
            context.sourceManager.origin(of: $0.fileID) == .user
        })
        let function = try #require(file.topLevelDecls.compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = ast.arena.decl(declaration),
                  function.name == context.interner.intern("choose")
            else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body else {
            throw TestFailure("Expected a function block")
        }
        let statement = try #require(statements.first { expression in
            if case .ifExpr = ast.arena.expr(expression) { return true }
            return false
        })
        return (ast, try #require(ast.arena.expr(statement)))
    }

    @Test
    func assignmentThenBodyDoesNotConsumeElse() throws {
        let context = makeContextFromSource("""
        fun choose(flag: Boolean) {
            var value = 0
            if (flag) value = 1 else value = 2
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(_, thenValue, _) = ast.arena.expr(thenID),
              let elseID,
              case let .localAssign(_, elseValue, _) = ast.arena.expr(elseID)
        else {
            Issue.record("Both unbraced branches must preserve their assignments")
            return
        }
        guard case .intLiteral(1, _) = ast.arena.expr(thenValue),
              case .intLiteral(2, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("Assignments must retain the value from their own branch")
            return
        }
    }

    @Test
    func comparisonInAssignmentDoesNotHideElse() throws {
        let context = makeContextFromSource("""
        fun choose(flag: Boolean, input: Int) {
            var value = false
            if (flag) value = input < 0 else value = true
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, _, elseID, _) = branch,
              let elseID,
              case let .localAssign(_, elseValue, _) = ast.arena.expr(elseID),
              case .boolLiteral(true, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("A comparison must preserve the enclosing else assignment")
            return
        }
    }

    @Test
    func nestedIfValueKeepsItsElseAndTheEnclosingElse() throws {
        let context = makeContextFromSource("""
        fun choose(outer: Boolean, inner: Boolean) {
            var value = 0
            if (outer) value = if (inner) 1 else 2 else value = 3
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(_, value, _) = ast.arena.expr(thenID),
              case let .ifExpr(_, _, innerElseID, _) = ast.arena.expr(value)
        else {
            Issue.record("Expected an assignment of an if expression")
            return
        }
        #expect(elseID != nil)
        #expect(innerElseID != nil)
    }

    @Test
    func newlineElseAfterSemicolonStaysAttachedToUnbracedIf() throws {
        let context = makeContextFromSource("""
        fun choose() {
            var x = 1.0
            var n = 5.0
            if (3.14 < n) {
                if (0.0 < x)
                    x -= 1.0;
                else
                    x += 1.0;
                n += 1.0;
            }
        }
        """)
        try runFrontend(context)
        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let (ast, outerBranch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, _, _) = outerBranch,
              case let .blockExpr(statements, _, _) = ast.arena.expr(thenID),
              let nestedID = statements.first(where: { expression in
                  if case .ifExpr = ast.arena.expr(expression) { return true }
                  return false
              }),
              case let .ifExpr(_, _, elseID, _) = ast.arena.expr(nestedID)
        else {
            Issue.record("Expected the inner if to remain a statement in the outer block")
            return
        }
        #expect(elseID != nil)
        #expect(statements.count == 2)
    }

    @Test
    func annotatedElseBranchAssignmentPreservesIfStructure() throws {
        let context = makeContextFromSource("""
        fun choose() {
            var n = 0
            if (1 < 0) n = 5 else @Suppress("X") n = 7
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(thenName, thenValue, _) = ast.arena.expr(thenID),
              let elseID,
              case let .localAssign(elseName, elseValue, _) = ast.arena.expr(elseID)
        else {
            Issue.record("Both branches must be parsed as assignments")
            return
        }
        #expect(context.interner.resolve(thenName) == "n")
        #expect(context.interner.resolve(elseName) == "n")
        guard case .intLiteral(5, _) = ast.arena.expr(thenValue),
              case .intLiteral(7, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("Assignments must retain correct branch values")
            return
        }
        #expect(!ast.arena.expressionAnnotations(for: elseID).isEmpty)
    }

    @Test
    func annotatedThenBranchAssignmentPreservesIfStructure() throws {
        let context = makeContextFromSource("""
        fun choose() {
            var n = 0
            if (1 > 0) @Suppress("X") n = 9 else n = 2
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(thenName, thenValue, _) = ast.arena.expr(thenID),
              let elseID,
              case let .localAssign(elseName, elseValue, _) = ast.arena.expr(elseID)
        else {
            Issue.record("Both branches must be parsed as assignments")
            return
        }
        #expect(context.interner.resolve(thenName) == "n")
        #expect(context.interner.resolve(elseName) == "n")
        guard case .intLiteral(9, _) = ast.arena.expr(thenValue),
              case .intLiteral(2, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("Assignments must retain correct branch values")
            return
        }
        #expect(!ast.arena.expressionAnnotations(for: thenID).isEmpty)
    }

    @Test
    func annotatedCompoundAssignmentBranchPreservesIfStructure() throws {
        let context = makeContextFromSource("""
        fun choose() {
            var n = 0
            if (1 > 0) @Suppress("X") n += 9 else n -= 2
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .compoundAssign(thenOp, thenName, thenValue, _) = ast.arena.expr(thenID),
              let elseID,
              case let .compoundAssign(elseOp, elseName, elseValue, _) = ast.arena.expr(elseID)
        else {
            Issue.record("Both branches must be parsed as compound assignments")
            return
        }
        #expect(thenOp == .plusAssign)
        #expect(elseOp == .minusAssign)
        #expect(context.interner.resolve(thenName) == "n")
        #expect(context.interner.resolve(elseName) == "n")
        guard case .intLiteral(9, _) = ast.arena.expr(thenValue),
              case .intLiteral(2, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("Compound assignments must retain correct branch values")
            return
        }
        #expect(!ast.arena.expressionAnnotations(for: thenID).isEmpty)
    }

    @Test
    func newlineAnnotatedElseBranchStaysAttachedInsideNestedBlock() throws {
        let context = makeContextFromSource("""
        fun choose(l: List<Any>) {
            val out = mutableListOf<Any>()
            fun walk(x: List<Any>) { out.add(x.size) }
            for (e in l) {
                if (e !is List<*>)
                    out.add(e)
                else
                    @Suppress("UNCHECKED_CAST")
                    walk(e as List<Any>)
            }
        }
        """)
        try runFrontend(context)
        let ast = try #require(context.ast)
        let file = try #require(ast.files.first {
            context.sourceManager.origin(of: $0.fileID) == .user
        })
        let function = try #require(file.topLevelDecls.compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = ast.arena.decl(declaration),
                  function.name == context.interner.intern("choose")
            else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body,
              let forID = statements.first(where: { expression in
                  if case .forExpr = ast.arena.expr(expression) { return true }
                  return false
              }),
              case let .forExpr(_, _, bodyID, _, _) = ast.arena.expr(forID),
              case let .blockExpr(bodyStatements, bodyTrailing, _) = ast.arena.expr(bodyID)
        else {
            Issue.record("Expected a for loop with a block body")
            return
        }
        // The annotated else-branch statement must not detach into a second
        // statement that runs unconditionally after the if.
        #expect(bodyStatements.isEmpty)
        guard let ifID = bodyTrailing,
              case let .ifExpr(_, _, elseID, _) = ast.arena.expr(ifID),
              let elseID
        else {
            Issue.record("The if must keep its annotated else branch")
            return
        }
        #expect(!ast.arena.expressionAnnotations(for: elseID).isEmpty)
    }

    private struct TestFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
