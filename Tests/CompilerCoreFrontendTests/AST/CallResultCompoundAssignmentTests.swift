@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CallResultCompoundAssignmentTests {
    private func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return context
    }

    @Test(arguments: ["factory.get()", "factory.get(1)", "create()"])
    func callResultIsEvaluatedThroughAnImmutableTemporary(lhs: String) throws {
        let context = makeContext("fun probe() { \(lhs) += 1 }")
        try runFrontend(context)
        let ast = try #require(context.ast)
        let file = try #require(ast.files.first { context.sourceManager.origin(of: $0.fileID) == .user })
        let declaration = try #require(file.topLevelDecls.first)
        guard case let .funDecl(function) = ast.arena.decl(declaration),
              case let .block(body, _) = function.body,
              let statement = body.first,
              case let .blockExpr(statements, nil, _) = ast.arena.expr(statement),
              statements.count == 2,
              case let .localDecl(name, false, _, initializer?, false, false, _) = ast.arena.expr(statements[0]),
              case let .compoundAssign(.plusAssign, target, _, _) = ast.arena.expr(statements[1])
        else {
            Issue.record("Call-result assignment must retain the call in an immutable temporary")
            return
        }
        #expect(ast.arena.isCallResultCompoundAssignmentBlock(statement))
        #expect(name == target)
        switch ast.arena.expr(initializer) {
        case .memberCall:
            #expect(ast.arena.isExplicitCall(initializer))
        case .call:
            break
        default:
            Issue.record("The temporary must preserve the original call")
        }
    }

    @Test
    func propertyAssignmentRetainsItsWritebackRepresentation() throws {
        let context = makeContext("fun probe() { factory.value += 1 }")
        try runFrontend(context)
        let ast = try #require(context.ast)
        let assignments = ast.arena.snapshot().expressions.filter {
            if case let .memberCompoundAssign(_, _, _, _, range) = $0 {
                return context.sourceManager.origin(of: range.start.file) == .user
            }
            return false
        }
        #expect(assignments.count == 1)
    }

    @Test(arguments: [
        "class Box { operator fun plus(value: Int): Box = this }",
        "class Box { fun plusAssign(value: Int) {} }",
        "class Box { operator fun plusAssign(value: Int): Int = value }",
    ], ["create()", "factory.get()"])
    func invalidCallResultAssignmentIsRejected(declaration: String, lhs: String) throws {
        let context = makeContext("""
        \(declaration)
        fun create(): Box = Box()
        class Factory { fun get(): Box = Box() }
        fun probe(factory: Factory) { \(lhs) += 1 }
        """)
        try runSema(context)
        let expectedCode = declaration.contains("operator fun plusAssign")
            ? "KSWIFTK-SEMA-0300" : "KSWIFTK-SEMA-0014"
        assertHasDiagnostic(expectedCode, in: context)
    }

    @Test
    func immutableCallResultSelectsInPlaceOperatorEvenWhenBinaryOperatorExists() throws {
        let context = makeContext("""
        class Box {
            operator fun plusAssign(value: Int) {}
            operator fun plus(value: Int): Box = this
        }
        fun create(): Box = Box()
        fun probe() { create() += 1 }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "Diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let calls = sema.bindings.callBindings.filter { id, _ in
            if case .compoundAssign = ast.arena.expr(id) { return true }
            return false
        }
        #expect(calls.count == 1)
        let call = try #require(calls.first?.value)
        #expect(sema.symbols.symbol(call.chosenCallee)?.name == context.interner.intern("plusAssign"))
    }

    @Test
    func mutablePropertyRetainsAssignmentOperatorAmbiguity() throws {
        let context = makeContext("""
        class Box {
            operator fun plusAssign(value: Int) {}
            operator fun plus(value: Int): Box = this
        }
        class Factory { var value = Box() }
        fun probe(factory: Factory) { factory.value += 1 }
        """)
        try runSema(context)
        assertHasDiagnostic("KSWIFTK-SEMA-0302", in: context)
    }

    @Test(arguments: ["create() += x!!", "create(x!!) += 1"], [false, true])
    func outerImmutableSmartCastSurvivesCallResultAssignment(statement: String, local: Bool) throws {
        let parameter = local ? "input" : "x"
        let context = makeContext("""
        class Box { operator fun plusAssign(value: Int) {} }
        fun create(value: Int = 0): Box = Box()
        fun probe(\(parameter): Int?): Int {
            \(local ? "val x = input" : "")
            \(statement)
            return x
        }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "Diagnostics: \(context.diagnostics.diagnostics)")
    }

    @Test
    func assignmentBlockMarkerSurvivesSnapshotAndDefaultsForOlderSnapshots() throws {
        let context = makeContext("fun probe() { create() += 1 }")
        try runFrontend(context)
        let arena = try #require(context.ast?.arena)
        let snapshot = arena.snapshot()
        let block = try #require(snapshot.callResultCompoundAssignmentBlocks.first)
        let data = try JSONEncoder().encode(snapshot)
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: data))
        #expect(restored.isCallResultCompoundAssignmentBlock(block))
        var older = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        older.removeValue(forKey: "callResultCompoundAssignmentBlocks")
        let legacy = try JSONDecoder().decode(ASTArenaSnapshot.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(legacy.callResultCompoundAssignmentBlocks.isEmpty)
    }
}
