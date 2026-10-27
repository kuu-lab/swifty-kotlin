@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ChannelReceiveSuspensionContextTests {
    @Test(arguments: [false, true])
    func receiveRequiresSuspensionAndPreservesOtherCalls(artifact: Bool) throws {
        if artifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.channels.Channel as KChannel
        fun consume(block: () -> Unit) { block() }
        fun ordinary(ch: KChannel<Int>) { ch.receive() }
        fun safe(ch: KChannel<Int>?) { ch?.receive() }
        suspend fun nested(ch: KChannel<Int>) { consume { ch.receive() } }
        suspend fun permitted(ch: KChannel<Int>) { ch.receive() }
        fun coroutine(ch: KChannel<Int>) { runBlocking { ch.receive() } }
        fun suspendLambda(ch: KChannel<Int>) { val action: suspend () -> Unit = { ch.receive() } }
        fun KChannel<Int>.receive(tag: Int): Int = tag
        fun extension(ch: KChannel<Int>): Int = ch.receive(1)
        class Channel { fun receive(): Int = 1 }
        fun user(ch: Channel): Int = ch.receive()
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: artifact
            )
            if artifact { #expect(ctx.options.stdlibLibraryPath != nil) }
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let lines = Set(errors.compactMap { $0.primaryRange?.start }.map {
                ctx.sourceManager.lineColumn(of: $0).line
            })
            #expect(lines == [4, 5, 6], "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0308" }, "\(errors)")
        }
    }
}
