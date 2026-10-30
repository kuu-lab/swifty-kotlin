@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ChannelIteratorElementTypeTests {
    @Test(arguments: [false, true])
    func iterationPreservesElementTypes(useLibrary: Bool) throws {
        let library = try stdlibLibraryPath(useLibrary: useLibrary)
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.channels.*
        fun probe(ints: Channel<Int>, strings: ReceiveChannel<String>, nullable: Channel<String?>, stars: Channel<*>) {
            for (value in ints) { val result: Int = value }
            for (value in strings) { val result: String = value }
            for (value in nullable) { val result: String? = value }
            for (value in stars) { val result: Any? = value }
            val nextInt: Int = ints.iterator().next()
            val nextString: String = strings.iterator().next()
            val nextNullable: String? = nullable.iterator().next()
            val nextStar: Any? = stars.iterator().next()
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func iterationRejectsIncorrectElementType(useLibrary: Bool) throws {
        let library = try stdlibLibraryPath(useLibrary: useLibrary)
        try withTemporaryFile(contents: """
        package negative.loop
        import kotlinx.coroutines.channels.*
        fun probeLoop(ints: Channel<Int>) {
            for (value in ints) { val result: String = value }
        }
        """) { loopPath in
            try withTemporaryFile(contents: """
            package negative.direct
            import kotlinx.coroutines.channels.*
            fun probeNext(ints: Channel<Int>) {
                val result: String = ints.iterator().next()
            }
            """) { nextPath in
                let ctx = makeCompilationContext(inputs: [loopPath, nextPath], stdlibLibraryPath: library)
                try runSema(ctx)
                for path in [loopPath, nextPath] {
                    let file = try #require(ctx.sourceManager.fileID(forPath: path))
                    #expect(ctx.diagnostics.diagnostics.contains {
                        $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001" && $0.primaryRange?.start.file == file
                    }, "Expected a type mismatch in \(path): \(ctx.diagnostics.diagnostics)")
                }
            }
        }
    }

    private func stdlibLibraryPath(useLibrary: Bool) throws -> String? {
        guard useLibrary else { return nil }
        TestStdlibCache.shared.prepare()
        return try #require(CompilerOptions.defaultStdlibLibraryPath, "Expected a prepared stdlib artifact")
    }
}
