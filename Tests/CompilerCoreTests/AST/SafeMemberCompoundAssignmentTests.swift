#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SafeMemberCompoundAssignmentTests {
    @Test
    func safeMemberCompoundAssignmentRunsInsideNonNullBranch() throws {
        let source = """
        class Box(var value: Int)
        fun probe(box: Box?) { box?.value += 5 }
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Diagnostics: \(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let file = try #require(ast.files.first { context.sourceManager.origin(of: $0.fileID) == .user })
        let declaration = try #require(file.topLevelDecls.first { declID in
            guard case let .funDecl(function) = ast.arena.decl(declID) else { return false }
            return function.name == context.interner.intern("probe")
        })
        guard case let .funDecl(function) = ast.arena.decl(declaration),
              case let .block(body, _) = function.body,
              let statement = body.first,
              case let .blockExpr(statements, nil, _) = ast.arena.expr(statement),
              statements.count == 2,
              case let .localDecl(receiverName, false, nil, receiverExpr?, false, false, _) = ast.arena.expr(statements[0]),
              case let .nameRef(sourceName, _) = ast.arena.expr(receiverExpr),
              case let .ifExpr(condition, thenExpr, nil, _) = ast.arena.expr(statements[1]),
              case let .binary(.notEqual, conditionReceiver, _, _) = ast.arena.expr(condition),
              case let .nameRef(conditionName, _) = ast.arena.expr(conditionReceiver),
              case let .memberCompoundAssign(.plusAssign, assignmentReceiver, callee, _, _) = ast.arena.expr(thenExpr),
              case let .nameRef(assignmentName, _) = ast.arena.expr(assignmentReceiver)
        else {
            Issue.record("Safe member compound assignment must be guarded by a non-null check")
            return
        }

        #expect(sourceName == context.interner.intern("box"))
        #expect(conditionName == receiverName)
        #expect(assignmentName == receiverName)
        #expect(callee == context.interner.intern("value"))
    }
}
#endif
