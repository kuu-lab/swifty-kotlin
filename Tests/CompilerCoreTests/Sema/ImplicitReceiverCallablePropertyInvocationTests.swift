#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImplicitReceiverCallablePropertyInvocationTests {
    private func makeIsolatedContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func memberFunctionPropertyCallsThroughImplicitReceiver() throws {
        let ctx = makeIsolatedContext("""
        class Holder(val f: (Int) -> String) {
            fun method(value: Int): String = "member:$value"
        }
        fun Holder.read(): String {
            val local = f
            return f(3) + local(3) + method(3)
        }
        fun explicit(holder: Holder): String = holder.f(3)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "f", in: ast, interner: ctx.interner))
        guard case let .call(callee, _, _, _) = ast.arena.expr(call) else {
            Issue.record("Expected an unqualified property call")
            return
        }
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Holder"), ctx.interner.intern("f"),
        ]))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.target == .localValue(property))
        #expect(binding.receiverArgumentOffset == 0)
        #expect(sema.bindings.identifierSymbol(for: callee) == property)
        #expect(sema.bindings.implicitReceiverMemberNames[callee] == ctx.interner.intern("f"))
    }

    @Test func receiverFunctionPropertyAcceptsItsReceiverArgument() throws {
        let ctx = makeIsolatedContext("""
        class Holder(val f: Int.() -> Int)
        fun Holder.read(): Int = f(4)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "f", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.receiverArgumentOffset == 1)
        #expect(binding.parameterMapping == [:])
    }
}
#endif
