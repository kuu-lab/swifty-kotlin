#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

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

        fun use(foo: Bar) { with(1) { foo() } }
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

    @Test func invokeWithoutRequiredContextKeepsContextDiagnostic() throws {
        let ctx = context("""
        class Bar {
            context(a: Int)
            operator fun invoke() {}
        }

        fun use(bar: Bar) { bar() }
        """)

        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-CTX-002"
                && $0.message.contains("Int")
        }, "Expected a missing Int context diagnostic: \(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0002"
        }, "Context failure should not degrade to overload failure: \(ctx.diagnostics.diagnostics)")
    }

    @Test func localFunctionScopesAndContextualInvokeResolveIndependently() throws {
        let ctx = context("""
        fun <T, R> with(receiver: T, block: T.() -> R): R = block(receiver)

        class Bar {
            context(a: Int)
            operator fun invoke(): String = "context(Int) Bar.invoke "
        }

        context(a: String)
        operator fun Bar.invoke(): String = "context(String) Bar.invoke "

        class Foo {
            val foo = Bar()

            fun test(): String {
                fun foo(): String = "local foo "
                return with("") { foo() } + with(1) { foo() }
            }

            fun test2(): String {
                fun String.foo(): String = "local foo "
                return with("") { foo() } + with(1) { foo() }
            }

            fun test3(): String {
                context(a: String) fun foo(): String = "local foo "
                return with("") { foo() } + with(1) { foo() }
            }

            fun test4(): String = with("") { foo() }
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let invokeCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            return sema.bindings.isInvokeOperatorCall(id) ? id : nil
        }
        #expect(invokeCalls.count == 3)
        let invokeContextTypes = invokeCalls.compactMap { call in
            sema.bindings.callBinding(for: call)
                .flatMap { sema.symbols.functionSignature(for: $0.chosenCallee) }
        }.flatMap(\.contextParameterTypes)
        #expect(invokeContextTypes.filter { $0 == sema.types.intType }.count == 2)
        #expect(invokeContextTypes.filter { $0 == sema.types.stringType }.count == 1)
        let invokeBindings = invokeCalls.compactMap { sema.bindings.callBinding(for: $0) }
        #expect(invokeBindings.count == 3)
        #expect(invokeBindings.allSatisfy {
            $0.contextParameterReceiverSymbols.count == 1
                && $0.contextParameterReceiverSymbols.first.flatMap { $0 } != nil
        })
    }
}
#endif
