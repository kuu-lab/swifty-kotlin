@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ChannelSendElementTypeTests {
    @Test(arguments: [false, true])
    func validSendsUseElementAndProjectedTypes(useArtifact: Bool) throws {
        let artifact = try stdlibArtifact(useArtifact: useArtifact)
        let source = """
        import kotlinx.coroutines.channels.Channel
        suspend fun valid(
            ints: Channel<Int>, value: Int,
            nullable: Channel<String?>, maybeText: String?,
            projected: Channel<in String>, text: String
        ) {
            ints.send(value)
            nullable.send(maybeText)
            nullable.send(element = null)
            projected.send(text)
        }
        suspend fun safe(ch: Channel<Int>?, value: Int) { ch?.send(value) }
        suspend fun <T> generic(ch: Channel<T>, value: T) { ch.send(value) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func invalidElementAndProjectedSendsAreRejected(useArtifact: Bool) throws {
        let artifact = try stdlibArtifact(useArtifact: useArtifact)
        let source = """
        import kotlinx.coroutines.channels.Channel
        suspend fun invalidElement(ch: Channel<Int>) { ch.send("wrong") }
        suspend fun invalidNull(ch: Channel<Int>) { ch.send(null) }
        suspend fun invalidOut(ch: Channel<out String>) { ch.send("wrong") }
        suspend fun invalidStar(ch: Channel<*>) { ch.send("wrong") }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let errorLines = Set(errors.compactMap { diagnostic in
                diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
            })
            #expect(errorLines == [2, 3, 4, 5], "\(errors)")
        }
    }

    @Test(arguments: [false, true])
    func sendRetainsSuspendAndOrdinaryOverloadBehavior(useArtifact: Bool) throws {
        let artifact = try stdlibArtifact(useArtifact: useArtifact)
        try withTemporaryFile(contents: """
        package channel.send.visibility
        import kotlinx.coroutines.channels.Channel
        private fun Channel<Int>.send(value: String) {}
        suspend fun extensionOverload(ch: Channel<Int>) { ch.send("extension") }
        """) { extensionPath in
            try withTemporaryFile(contents: """
            package channel.send.visibility
            import kotlinx.coroutines.channels.Channel
            fun privateExtensionIsInvisible(ch: Channel<Int>) { ch.send("extension") }
            fun sendNeedsSuspendContext(ch: Channel<Int>) { ch.send(1) }
            """) { callPath in
                let ctx = makeCompilationContext(
                    inputs: [extensionPath, callPath],
                    stdlibLibraryPath: artifact,
                    allowDefaultStdlibLibrary: false
                )
                try runSema(ctx)
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                let errorLines = Set(errors.compactMap { diagnostic in
                    diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
                })
                let suspendErrors = errors.filter {
                    $0.code == "KSWIFTK-SEMA-0308"
                        && $0.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } == 4
                }
                #expect(errorLines == [3, 4], "\(errors)")
                #expect(suspendErrors.count == 1, "\(errors)")
            }
        }
    }

    private func stdlibArtifact(useArtifact: Bool) throws -> String? {
        guard useArtifact else { return nil }
        TestStdlibCache.shared.prepare()
        return try #require(CompilerOptions.defaultStdlibLibraryPath, "Expected a fresh stdlib artifact")
    }
}
