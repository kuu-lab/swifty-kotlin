#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct UncheckedArrayViewIntegerLiteralAssignmentTests {
    @Test
    func directUncheckedArrayViewPreservesJvmIntegerLiteralAdaptation() throws {
        let ctx = makeContextFromSource("""
        fun widen(values: Array<Long>): Array<Any?> = values as Array<Any?>
        fun assign(
            bytes: Array<Byte>, shorts: Array<Short>, ints: Array<Int>, longs: Array<Long>,
            floats: Array<Float>, doubles: Array<Double>
        ) {
            (bytes as Array<Any?>)[0] = 7
            (shorts as Array<Any?>)[0] = 7
            (ints as Array<Any?>)[0] = 7
            (longs as Array<Any?>)[0] = 7
            (floats as Array<Any?>)[0] = 7
            (doubles as Array<Any?>)[0] = 7
            (bytes as Array<Any?>)[0] = 7L
            widen(longs)[0] = 7
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let contextualAssignments: [(String, TypeID)] = [
            ("bytes", sema.types.byteType),
            ("shorts", sema.types.shortType),
            ("ints", sema.types.intType),
            ("longs", sema.types.longType),
        ]
        for (name, expectedType) in contextualAssignments {
            let value = try assignedValue(
                throughCastOf: name,
                whereValueIsLongLiteral: false,
                ast: ast,
                ctx: ctx
            )
            #expect(sema.bindings.exprType(for: value) == expectedType)
        }

        for name in ["floats", "doubles"] {
            let value = try assignedValue(
                throughCastOf: name,
                whereValueIsLongLiteral: false,
                ast: ast,
                ctx: ctx
            )
            #expect(sema.bindings.exprType(for: value) == sema.types.intType)
        }

        let suffixedValue = try assignedValue(
            throughCastOf: "bytes",
            whereValueIsLongLiteral: true,
            ast: ast,
            ctx: ctx
        )
        #expect(sema.bindings.exprType(for: suffixedValue) == sema.types.longType)

        // The direct casts above match first; the function-boundary case is
        // identified by its call receiver after excluding explicit casts.
        let nonCastAssignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAssign(receiver, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return false }
            if case .asCast = ast.arena.expr(receiver) { return false }
            return true
        })
        guard case let .indexedAssign(_, _, boundaryValue, _) = ast.arena.expr(nonCastAssignment) else {
            Issue.record("Expected the function-boundary indexed assignment")
            return
        }
        #expect(sema.bindings.exprType(for: boundaryValue) == sema.types.intType)
    }

    private func assignedValue(
        throughCastOf variableName: String,
        whereValueIsLongLiteral expectedLongLiteral: Bool,
        ast: ASTModule,
        ctx: CompilationContext
    ) throws -> ExprID {
        let variable = ctx.interner.intern(variableName)
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAssign(receiver, _, value, range) = expr,
                  case let .asCast(operand, _, _, _) = ast.arena.expr(receiver),
                  case let .nameRef(name, _) = ast.arena.expr(operand),
                  name == variable,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return false
            }
            if expectedLongLiteral {
                if case .longLiteral = ast.arena.expr(value) { return true }
                return false
            }
            if case .intLiteral = ast.arena.expr(value) { return true }
            return false
        })
        guard case let .indexedAssign(_, _, value, _) = ast.arena.expr(assignment) else {
            Issue.record("Expected indexed assignment")
            return assignment
        }
        return value
    }
}
#endif
