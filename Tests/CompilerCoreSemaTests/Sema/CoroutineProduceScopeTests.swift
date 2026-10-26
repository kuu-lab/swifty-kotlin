@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite
struct CoroutineProduceScopeTests {
    @Test func unimportedBuilderIsNotMadeVisibleFromArtifact() throws {
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let source = """
        import kotlinx.coroutines.CoroutineScope
        import kotlinx.coroutines.channels.ReceiveChannel
        fun CoroutineScope.produce(from: Int, to: Int): ReceiveChannel<Int> = produce {
            for (i in from..to) send(i)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library,
                                             allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "The unimported builder must remain unavailable")
        }
    }
}
