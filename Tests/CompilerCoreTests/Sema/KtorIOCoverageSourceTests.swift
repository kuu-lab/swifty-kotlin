@testable import CompilerCore
import Testing

@Suite
struct KtorIOCoverageSourceTests {
    @Test
    func ktorImportsResolveBundledAPIsAndOwnedDiscard() throws {
        let ctx = makeContextFromSources([
            """
            package io.ktor.utils.io.core
            import kotlinx.io.Source
            fun Source.discard(count: Long = Long.MAX_VALUE): Long {
                request(count)
                val countToDiscard = minOf(count, buffer.size)
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
