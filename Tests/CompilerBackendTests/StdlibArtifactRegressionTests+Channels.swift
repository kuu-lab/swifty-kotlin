@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    @Test(arguments: [false, true])
    func testChannelSendChannelSubtype(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/channel_send_channel_subtype.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ChannelSendChannelSubtype", emit: .executable, outputPath: outputBase,
                stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") ==
                "false\ntrue\ntrue\n7\n9\ntrue\ntrue\ntrue\nvalue\ntrue\n")
        }
    }

    @Test(arguments: [true, false], [0, 2])
    func testChannelReceivePreservesElementType(fromSource: Bool, optimization: Int) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu3641_channel_receive_element_type.kt"
        ), encoding: .utf8)
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))

        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU3641ChannelReceive_\(fromSource)_O\(optimization)",
                outputPath: output,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath,
                includeStdlib: fromSource,
                prepareTestStdlibCache: false
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "42\ntrue\nout\n9\n11\nnull\nnull\n13\nclosed\n")
        }
    }

    @Test(arguments: [true, false], [0, 2])
    func testChannelReceiveRejectsInvalidResultAndBareSyntax(fromSource: Bool, optimization: Int) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.channels.Channel

        suspend fun invalidResult(channel: Channel<Int>): String = channel.receive()

        suspend fun missingCall(channel: Channel<Int>) {
            val value = channel.receive
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "KUU3641InvalidChannelReceive",
                inputs: [inputPath],
                outputPath: output,
                emit: .kirDump,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            let result = makeTestDriver().runForTesting(options: options)

            #expect(result.exitCode != 0, "Expected invalid receive uses to fail compilation")
            #expect(result.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001" },
                "Expected a receive result type mismatch: \(result.diagnostics)")
            #expect(result.diagnostics.filter { $0.severity == .error }.count >= 2,
                "Expected the bare receive reference to remain invalid: \(result.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func testChannelExceptionsNullableMessage(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_channel_ex_nullable_message.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ChannelExceptionsNullableMessage",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") ==
                "send closed\nreceive closed\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n")
        }
    }

    @Test(arguments: [false, true])
    func testProducerScopeClosedForSend(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu1133_producer_scope_closed_for_send.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ProducerScopeClosedForSend",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            channel open: false
            channel closed: true
            callbackFlow open: false,false,false
            callbackFlow closed: true,true,true
            channelFlow open: false,false,false
            channelFlow closed: true,true,true
            produce open: false,false,false
            produce closed: true,true,true

            """)
        }
    }

    @Test
    func testChannelSendApisThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            val ch = Channel<Int>(2)
            println("trySend ok: ${ch.trySend(7).isSuccess}")
            println("close(cause): ${ch.close(IllegalStateException("boom"))}")
            val closed = ch.trySend(9)
            println("closed: ${closed.isClosed}")
            println("cause: ${closed.exceptionOrNull()?.message}")

            val ch2 = Channel<Int>(3)
            ch2.send(1)
            ch2.send(2)
            ch2.close()
            var sum = 0
            ch2.consumeEach { sum += it }
            println("sum: $sum")
            println("empty: ${ch2.isEmpty}")

            callbackFlow<Int> {
                this.trySend(11).onSuccess { println("ps: ok") }
                println("ps closed: ${this.isClosedForSend}")
                this.close()
            }.collect { println("got: $it") }

            println("done")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ChannelSendApis",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "trySend ok: true\nclose(cause): true\nclosed: true\ncause: boom\nsum: 3\nempty: false\nps: ok\nps closed: false\ngot: 11\ndone\n")
        }
    }
}
