@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ChannelReceiveElementTypeTests {
    @Test(arguments: [false, true])
    func readsPreserveElementAndProjectionTypes(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        import kotlinx.coroutines.channels.Channel
        import kotlinx.coroutines.channels.ReceiveChannel
        class UserTypes {
            class Channel<T> { fun receive(): String = "custom" }
        }
        fun ordinary(ch: UserTypes.Channel<Int>): String = ch.receive()
        suspend fun number(ch: Channel<Int>): Int = ch.receive()
        suspend fun nullable(ch: Channel<String?>): String? = ch.receive()
        suspend fun projected(ch: Channel<out String>): String = ch.receive()
        suspend fun consumed(ch: Channel<in String>): Any? = ch.receive()
        suspend fun star(ch: Channel<*>): Any? = ch.receive()
        suspend fun safe(ch: Channel<Int>?): Int? = ch?.receive()
        suspend fun alias(ch: ReceiveChannel<String>): String = ch.receive()
        suspend fun <T> generic(ch: Channel<T>): T = ch.receive()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func nullableAndUnknownElementsCannotBeReadAsNonNull(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        suspend fun nullable(ch: kotlinx.coroutines.channels.Channel<String?>): String = ch.receive()
        suspend fun consumed(ch: kotlinx.coroutines.channels.Channel<in String>): String? = ch.receive()
        suspend fun star(ch: kotlinx.coroutines.channels.Channel<*>): String = ch.receive()
        suspend fun typeArgs(ch: kotlinx.coroutines.channels.Channel<Int>) = ch.receive<String>()
        suspend fun property(ch: kotlinx.coroutines.channels.Channel<Int>) = ch.receive
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let errorLines = Set(errors.compactMap { diagnostic in
                diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
            })
            #expect(errorLines == [1, 2, 3, 4, 5], "\(errors)")
        }
    }
}
