@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InlineMemberGenericNonLocalReturnInferenceTests {
    /// KUU-4357: the caller's class type parameter must stay rigid while the
    /// generic inline member's result is inferred from the surrounding type.
    @Test func expressionBodyInfersGenericInlineMemberFromNonLocalReturn() throws {
        try withTemporaryFile(contents: """
        package probe

        class C<V> {
            private inline fun <T> withLock(proc: () -> T): T = proc()

            fun get(): V? = withLock {
                return null
            }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnostics.joined(separator: " | ")))

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let withLockCall = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      name == ctx.interner.intern("withLock")
                else {
                    return nil
                }
                return id
            }.first
            let call = try #require(withLockCall)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true)
        }
    }
}
