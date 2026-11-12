@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-4542: source-defined `Throwable` subclasses must stringify through
    /// the same `ClassName: message` path as kotlinc for direct, `Any`-erased,
    /// and `Throwable`-static receivers, while preserving overrides and cause
    /// identity.
    @Test
    func testThrowableSubclassToStringDispatch() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        private class NamedThrowable(message: String?) : Throwable(message)
        private class NoArgThrowable : Throwable()
        private class MessageCauseThrowable(message: String?, cause: Throwable?) : Throwable(message, cause)
        private class OverridingThrowable : Throwable("base") {
            override fun toString(): String = "override"
        }

        fun main() {
            val cause = Throwable("cause")
            val messageCause = MessageCauseThrowable("message", cause)
            val noArgAny: Any = NoArgThrowable()
            val messageCauseAny: Any = messageCause
            val overridden: Throwable = OverridingThrowable()
            val overriddenAny: Any = OverridingThrowable()

            println(NamedThrowable("subclass").toString())
            println(noArgAny.toString())
            println(noArgAny is Throwable)
            println(messageCause.toString())
            println(messageCauseAny.toString())
            println(messageCauseAny is Throwable)
            println(messageCause.cause === cause)
            println(overridden.toString())
            println(overriddenAny.toString())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU4542ThrowableSubclassToStringArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "NamedThrowable: subclass\nNoArgThrowable\ntrue\nMessageCauseThrowable: message\nMessageCauseThrowable: message\ntrue\ntrue\noverride\noverride\n"
            )
        }
    }
}
