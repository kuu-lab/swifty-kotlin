#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct UnsignedIndexedAssignmentTests {
    @Test(arguments: [("UByte", "ubyteArrayOf", "255u"), ("UShort", "ushortArrayOf", "65535u")])
    func arrayAssignmentContextualizesUnsignedLiteral(
        elementName: String, factory: String, literal: String
    ) throws {
        let ctx = makeContextFromSource("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val a = \(factory)(0u)
            a[0] = \(literal)
            println(a[0])
        }
        """)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(diagnostics.isEmpty, "\(diagnostics)")
        try expectAssignedType(elementName, ctx: ctx)
    }

    @Test(arguments: [("UByte", "255u"), ("UShort", "65535u")])
    func genericOperatorSetSubstitutesReceiverBeforeContextualizingLiteral(
        elementName: String, literal: String
    ) throws {
        let ctx = makeContextFromSource("""
        class Slot<T> {
            operator fun set(index: Int, value: T) {}
        }
        fun assign(slot: Slot<\(elementName)>) {
            slot[0] = \(literal)
        }
        """)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(diagnostics.isEmpty, "\(diagnostics)")
        let assignment = try expectAssignedType(elementName, ctx: ctx)
        let sema = try #require(ctx.sema)
        let callee = try #require(sema.bindings.callBinding(for: assignment)?.chosenCallee)
        let symbol = try #require(sema.symbols.symbol(callee))
        #expect(ctx.interner.resolve(symbol.name) == "set")
        #expect(!symbol.flags.contains(.synthetic))
    }

    @Test(arguments: [
        ("UByteArray", "256u"), ("UShortArray", "65536u"),
        ("UByteArray", "value"), ("UShortArray", "value"),
        ("UByteArray", "255"), ("UByteArray", "255uL"),
    ])
    func assignmentRejectsValuesThatCannotNarrow(arrayName: String, value: String) throws {
        let ctx = makeContextFromSource("""
        fun assign(a: \(arrayName), value: UInt) {
            a[0] = \(value)
        }
        """)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics
        #expect(diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001"
        }, "Expected a type error: \(diagnostics)")
    }

    @discardableResult
    private func expectAssignedType(_ name: String, ctx: CompilationContext) throws -> ExprID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAssign(_, _, _, range) = expr else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        })
        guard case let .indexedAssign(_, _, value, _) = ast.arena.expr(assignment) else {
            Issue.record("Expected indexed assignment")
            return assignment
        }
        let expectedType = name == "UByte" ? sema.types.ubyteType : sema.types.ushortType
        let assignedType = sema.bindings.exprType(for: value)
        #expect(assignedType == expectedType)
        return assignment
    }
}
#endif
