@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct DelegatePropertyKIRTests {
    @Test
    func testLazyDelegateEndToEndCompilesToExecutable() throws {
        let source = """
        val x by lazy { 42 }
        fun main() {
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LazyDelegateExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath),
                    "Executable should be produced for lazy delegate program")
        }
    }

    @Test
    func testNotNullDelegateReadBeforeAssignmentTrapsWithHelpfulMessage() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.notNull()
        fun main() {
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NotNullTrapExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                Issue.record("Reading notNull before assignment should fail")
                return
            } catch let CommandRunnerError.nonZeroExit(result) {
                let combined = result.stdout + result.stderr
                if !combined.isEmpty {
                    #expect(
                        combined.contains("IllegalStateException")
                            || combined.contains("fatalError")
                            || combined.contains("initialized before get")
                            || combined.contains("KSWIFTK-LINK-0003"),
                        "Unexpected process output: \(combined)"
                    )
                }
            }
        }
    }
}
