@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CompoundAssignContextualArgumentTests {
    private func userAssignments(in ctx: CompilationContext) throws -> [ExprID] {
        let ast = try #require(ctx.ast)
        return ast.arena.exprs.indices.compactMap { index in
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            switch ast.arena.exprs[index] {
            case .compoundAssign, .memberCompoundAssign: return id
            default: return nil
            }
        }
    }

    @Test
    func emptyMapUsesReceiverElementType() throws {
        let ctx = makeContextFromSource("""
        class Holder {
            val scopes = ArrayDeque<MutableMap<String, Boolean>>()
            fun addScope() { scopes += mutableMapOf() }
        }
        val scopes = ArrayDeque<MutableMap<String, Boolean>>()
        fun test(holder: Holder) {
            val localScopes = ArrayDeque<MutableMap<String, Boolean>>()
            localScopes += mutableMapOf()
            scopes += mutableMapOf()
            holder.scopes += mutableMapOf()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignments = try userAssignments(in: ctx)
        #expect(assignments.count == 4)
        for id in assignments {
            let binding = try #require(sema.bindings.callBinding(for: id))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.name == ctx.interner.intern("plusAssign"))
            #expect(sema.symbols.functionSignature(for: binding.chosenCallee)?.returnType == sema.types.unitType)
            let value: ExprID
            switch ast.arena.expr(id) {
            case let .compoundAssign(_, _, rhs, _), let .memberCompoundAssign(_, _, _, rhs, _):
                value = rhs
            default:
                Issue.record("Expected a user compound assignment")
                continue
            }
            let valueType = try #require(sema.bindings.exprType(for: value))
            guard case let .classType(map) = sema.types.kind(of: valueType) else {
                Issue.record("Expected an inferred MutableMap type")
                continue
            }
            #expect(map.args == [.invariant(sema.types.stringType), .invariant(sema.types.booleanType)])
        }
    }

    @Test
    func incompatibleMapIsRejected() throws {
        let arguments = [
            "mutableMapOf<Int, Boolean>()",
            "mutableMapOf<Nothing, Nothing>()",
            "mutableMapOf(1 to true)",
            "mutableMapOf(1 to null)",
            "wrong",
            "emptyMap<String, Boolean>()",
        ]
        let statements = arguments.flatMap { rhs in
            ["scopes", "holder.scopes"].map { "\($0) += \(rhs)" }
        }
        let functions = statements.enumerated().map { index, statement in
            """
            fun rejected\(index)() {
                val holder = Holder()
                val scopes = ArrayDeque<MutableMap<String, Boolean>>()
                val wrong = mutableMapOf<Int, Boolean>()
                \(statement)
            }
            """
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("""
        class Holder { val scopes = ArrayDeque<MutableMap<String, Boolean>>() }
        \(functions)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && ($0.code == "KSWIFTK-TYPE-0001" || $0.code == "KSWIFTK-SEMA-0002")
        }
        let ast = try #require(ctx.ast)
        let assignments = try userAssignments(in: ctx)
        #expect(assignments.count == statements.count)
        for id in assignments {
            let range = try #require(ast.arena.exprRange(id))
            #expect(errors.contains { diagnostic in
                diagnostic.primaryRange.map { range.contains($0) } == true
            }, "Missing rejection for assignment \(id)")
        }
    }

    @Test
    func concreteArgumentsRetainOverloadSelection() throws {
        let ctx = makeContextFromSource("""
        class Sink {
            operator fun plusAssign(value: MutableMap<String, Boolean>) {}
            operator fun plusAssign(value: Int) {}
        }
        fun test() {
            val sink = Sink()
            sink += mutableMapOf()
            sink += mutableMapOf("x" to true)
            sink += 1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func conflictingExpectedTypesAreNotChosenArbitrarily() throws {
        let ctx = makeContextFromSource("""
        class Sink {
            operator fun plusAssign(value: MutableMap<String, Boolean>) {}
            operator fun plusAssign(value: MutableMap<Int, Boolean>) {}
        }
        fun test() { val sink = Sink(); sink += mutableMapOf() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
