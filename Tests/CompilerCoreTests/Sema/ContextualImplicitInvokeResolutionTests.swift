#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContextualImplicitInvokeResolutionTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            frontendFlags: ["opt-in=kotlin.ExperimentalContextParameters"],
            includeStdlib: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func selectedInvoke(
        _ ctx: CompilationContext
    ) throws -> (SemaModule, ExprID, SymbolID) {
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let invokeCall = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard sema.bindings.isInvokeOperatorCall(id) else {
                return nil
            }
            return id
        }.first)
        let binding = try #require(sema.bindings.callBinding(for: invokeCall))
        return (sema, invokeCall, binding.chosenCallee)
    }

    @Test func memberInvokeUsesAvailableContextParameter() throws {
        let ctx = context("""
        fun <T, R> with(receiver: T, block: T.() -> R): R = block(receiver)

        class Bar {
            context(a: Int)
            operator fun invoke() {}
        }

        context(a: String)
        operator fun Bar.invoke() {}

        val foo: Bar = Bar()
        fun use() { with(1) { foo() } }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let (sema, call, chosen) = try selectedInvoke(ctx)
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.bindings.isInvokeOperatorCall(call))
        #expect(signature.contextParameterTypes == [sema.types.intType])
        #expect(binding.contextParameterReceiverSymbols.count == 1)
        #expect(binding.contextParameterReceiverSymbols.first.flatMap { $0 } != nil)
        #expect(sema.symbols.parentSymbol(for: chosen).flatMap(sema.symbols.symbol)?.name == ctx.interner.intern("Bar"))
    }

    @Test func extensionInvokeUsesAvailableContextParameter() throws {
        let ctx = context("""
        fun <T, R> with(receiver: T, block: T.() -> R): R = block(receiver)

        class Bar

        context(a: Int)
        operator fun Bar.invoke() {}

        val foo: Bar = Bar()
        fun use() { with(1) { foo() } }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let (sema, call, chosen) = try selectedInvoke(ctx)
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.bindings.isInvokeOperatorCall(call))
        #expect(signature.contextParameterTypes == [sema.types.intType])
        #expect(binding.contextParameterReceiverSymbols.count == 1)
        #expect(binding.contextParameterReceiverSymbols.first.flatMap { $0 } != nil)
        #expect(signature.receiverType != nil)
    }
}
#endif
