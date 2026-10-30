@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KtorIOCoverageSourceTests {
    @Test
    func ktorPosixDispatcherImportsNativeIO() throws {
        let ctx = makeContextFromSources([
            """
            package io.ktor.utils.io
            import kotlinx.coroutines.CoroutineDispatcher
            expect fun ioDispatcher(): CoroutineDispatcher
            """,
            """
            package io.ktor.utils.io
            import kotlinx.coroutines.CoroutineDispatcher
            import kotlinx.coroutines.Dispatchers
            import kotlinx.coroutines.IO

            public actual fun ioDispatcher(): CoroutineDispatcher = Dispatchers.IO
            """,
            """
            package io.ktor.utils.io
            import kotlinx.coroutines.CoroutineDispatcher
            import kotlinx.coroutines.IO

            fun importedIODispatcher(): CoroutineDispatcher = IO
            """,
        ])
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let symbols = try #require(ctx.sema?.symbols)
        let io = try #require(symbols.lookupAll(fqName: ["kotlinx", "coroutines", "IO"].map(ctx.interner.intern)).first)
        let info = try #require(symbols.symbol(io))
        #expect(info.visibility == .public)
        #expect(symbols.isSourceBackedSymbol(io))
        let file = try #require(symbols.sourceFileID(for: io))
        #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlinx/coroutines/Dispatchers.kt")
    }

    @Test
    func ktorImportsResolveBundledAPIsAndOwnedDiscard() throws {
        let ctx = makeContextFromSources([
            """
            package io.ktor.utils.io.core
            import kotlinx.io.Source
            import kotlinx.io.InternalIoApi

            @OptIn(InternalIoApi::class)
            val Source.remaining: Long
                get() = buffer.size

            @OptIn(InternalIoApi::class)
            fun Source.discard(count: Long = Long.MAX_VALUE): Long {
                request(count)
                val countToDiscard = minOf(count, remaining)
                buffer.skip(countToDiscard)
                return countToDiscard
            }
            """,
            """
            package io.ktor.utils.io
            import io.ktor.utils.io.core.*
            import kotlinx.io.*
            import kotlinx.coroutines.*
            import kotlin.text.Charsets

            @OptIn(ExperimentalCoroutinesApi::class)
            fun copy(error: Throwable): Throwable? =
                if (error is CopyableThrowable<*>) error.createCopy() else error

            fun read(buffer: Buffer, source: Source): String {
                source.discard(2)
                source.discard(1)
                buffer.readString(0L, Charsets.UTF_8)
                buffer.readString(Charsets.UTF_8)
                return buffer.readString()
            }
            """,
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let symbols = try #require(ctx.sema?.symbols)
        for fqName in [
            "kotlinx.coroutines.CopyableThrowable",
            "kotlinx.io.readString",
        ] {
            let found = symbols.lookupAll(fqName: fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
            #expect(!found.isEmpty)
            #expect(found.allSatisfy(symbols.isSourceBackedSymbol))
            #expect(found.allSatisfy { symbols.externalLinkName(for: $0) == nil })
        }
        #expect(symbols.lookupAll(fqName: ["kotlinx", "io", "discard"].map(ctx.interner.intern)).isEmpty)
    }
}
