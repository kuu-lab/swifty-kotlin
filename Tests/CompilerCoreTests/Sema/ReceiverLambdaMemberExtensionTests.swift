@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ReceiverLambdaMemberExtensionTests {
    @Test
    func inapplicableSAMMemberFallsBackToGenericMemberExtension() throws {
        let ctx = makeContext("""
        fun interface Parser<out T> { fun parse(source: String): T }
        class State {
            fun <T> Parser<T>.parse(): T = parse("")
        }
        fun <T> parser(block: State.() -> T): Parser<T> = Parser { block(State()) }
        fun <T> combine(element: Parser<T>, separator: Parser<Unit>): Parser<T> {
            val wrapped = parser {
                separator.parse()
                element.parse()
            }
            return wrapped
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let extensions = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("parse")
                && sema.symbols.memberExtensionOwnerSymbol(for: $0.chosenCallee) != nil
        }
        #expect(extensions.count == 2)
        #expect(extensions.contains { $0.substitutedTypeArguments.contains(sema.types.unitType) })
    }

    @Test
    func applicableMemberKeepsPrecedenceInsideReceiverLambda() throws {
        let ctx = makeContext("""
        class Parser { fun parse(source: String): Int = 1 }
        class State { fun Parser.parse(source: String): Int = 2 }
        fun parser(block: State.() -> Int): Int = block(State())
        fun use(p: Parser): Int = parser { p.parse("source") }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let parseCalls = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("parse")
        }
        #expect(parseCalls.count == 1)
        #expect(parseCalls.allSatisfy { sema.symbols.memberExtensionOwnerSymbol(for: $0.chosenCallee) == nil })
    }

    @Test
    func memberExtensionNotOperatorResolvesInsideSuspendReceiverLambda() throws {
        let ctx = makeContext("""
        class Context {
            var res: String = ""
            operator fun Any.not() { res = "OK" }
        }
        fun coVerify(verifyBlock: suspend Context.() -> Unit) {}
        fun use(c: Any) { coVerify { !c } }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let notCalls = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("not")
        }
        #expect(notCalls.count == 1)
        let callee = try #require(notCalls.first?.chosenCallee)
        let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Context"))
    }

    @Test
    func memberExtensionNotOperatorResolvesInsideReceiverLambda() throws {
        let ctx = makeContext("""
        var res = "FAIL"
        class Context {
            operator fun Any.not() { res = "OK" }
        }
        fun coVerify(block: Context.() -> Unit) { Context().block() }
        fun main() { val c = Any(); coVerify { !c } }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let notCalls = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("not")
        }
        #expect(notCalls.count == 1)
        let callee = try #require(notCalls.first?.chosenCallee)
        let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Context"))
    }

    @Test
    func memberExtensionStillRequiresDispatchReceiver() throws {
        let ctx = makeContext("""
        fun interface Parser<out T> { fun parse(source: String): T }
        class State { fun <T> Parser<T>.parse(): T = parse("") }
        fun outside(p: Parser<Int>): Int = p.parse()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func contextualMemberExtensionResolvesAcrossNestedReceiverLambdas() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.ExperimentalContextParameters::class)

        class Context
        class Extended
        class Containing {
            context(_: Context) fun Extended.foo(obj: Any? = null) {}
        }
        fun caller() = with(Containing()) { with(Context()) { Extended().foo() } }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let fooCall = try #require(sema.bindings.callBindings.values.first {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("foo")
        })
        let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: fooCall.chosenCallee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Containing"))
        #expect(fooCall.contextParameterReceiverSymbols.count == 1)
        #expect(fooCall.contextParameterReceiverSymbols.allSatisfy { $0 != nil })
    }

    private func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
