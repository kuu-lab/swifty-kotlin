@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite
struct CoroutineProduceVisibilityTests {
    @Test(arguments: [false, true])
    func produceRequiresAnImportOutsideItsPackage(fromArtifact: Bool) throws {
        if fromArtifact { TestStdlibCache.shared.prepare() }
        let library = fromArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let prefix = """
        import kotlinx.coroutines.CoroutineScope
        import kotlinx.coroutines.channels.ReceiveChannel
        """
        let body = """
        fun CoroutineScope.make(): ReceiveChannel<Int> = produce { send(1) }
        """
        let cases: [(name: String, source: String, error: Bool)] = [
            ("missing", "\(prefix)\n\(body)", true),
            ("explicit", "\(prefix)\nimport kotlinx.coroutines.channels.produce\n\(body)", false),
            ("wildcard", "\(prefix)\nimport kotlinx.coroutines.channels.*\n\(body)", false),
            ("package", "package kotlinx.coroutines.channels\nimport kotlinx.coroutines.CoroutineScope\n\(body)", false),
            ("user", """
            import kotlinx.coroutines.CoroutineScope
            fun CoroutineScope.produce(block: () -> Int): Int = block()
            fun CoroutineScope.make(): Int = produce { 1 }
            """, false),
        ]
        for testCase in cases {
            try withTemporaryFile(contents: testCase.source) { path in
                let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library,
                                                 allowDefaultStdlibLibrary: false)
                try runSema(ctx)
                #expect(ctx.diagnostics.hasError == testCase.error,
                        "\(testCase.name): \(ctx.diagnostics.diagnostics)")
            }
        }
    }
}
