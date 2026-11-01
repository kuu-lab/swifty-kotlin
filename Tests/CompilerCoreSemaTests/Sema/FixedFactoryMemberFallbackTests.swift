@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct FixedFactoryMemberFallbackTests {
    @Test(arguments: ["Token", "makeToken"])
    func fixedFactoryArgumentFallsThroughInapplicableMember(factory: String) throws {
        let ctx = makeContext("""
        class Token(val value: Int)
        fun \(factory)(): Token = Token(1)
        class Receiver { fun pick(value: Int): Int = 0 }
        fun Receiver.pick(value: Token): Int = value.value
        fun use(receiver: Receiver): Int = receiver.pick(\(factory)())
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let calls = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("pick")
        }
        #expect(calls.count == 1)
        #expect(calls.allSatisfy {
            sema.symbols.symbol($0.chosenCallee)?.fqName == [ctx.interner.intern("pick")]
                && sema.symbols.functionSignature(for: $0.chosenCallee)?.receiverType != nil
        })
    }

    @Test
    func genericFactoryStillReceivesApplicableMemberContext() throws {
        let ctx = makeContext("""
        class Box<T>
        fun <T> makeBox(): Box<T> = Box<T>()
        class Receiver { fun pick(value: Box<String>): Int = 1 }
        fun Receiver.pick(value: Box<Int>): Int = 2
        fun use(receiver: Receiver): Int = receiver.pick(makeBox())
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let calls = sema.bindings.callBindings.values.filter {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("pick")
        }
        #expect(calls.count == 1)
        #expect(calls.allSatisfy {
            sema.symbols.symbol($0.chosenCallee)?.fqName == [
                ctx.interner.intern("Receiver"), ctx.interner.intern("pick"),
            ]
        })
    }

    @Test
    func fixedFactoryCannotSatisfyIncompatibleMemberWithoutExtension() throws {
        let ctx = makeContext("""
        class Token(val value: Int)
        fun makeToken(): Token = Token(1)
        class Receiver { fun pick(value: Int): Int = 0 }
        fun use(receiver: Receiver): Int = receiver.pick(makeToken())
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0473" })
    }

    private func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
