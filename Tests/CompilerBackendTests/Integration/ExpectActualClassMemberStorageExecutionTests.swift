#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualClassMemberStorageExecutionTests {
    @Test
    func pairedActualClassInitializesFieldsForAnonymousSubclasses() throws {
        try assertPairedActualFieldProgram(
            mainBody: """
            private val Impl: B = object : B() {}

            fun main() {
                println(Impl.fixed)
                println(Impl.getPub())
            }
            """,
            expectedStdout: "fx\n?\n",
            context: "paired actual field initializers run for anonymous subclasses"
        )
    }

    @Test
    func externalWritesResolvePairedActualClassProperties() throws {
        try assertPairedActualFieldProgram(
            mainBody: """
            private val Impl: B = object : B() {}

            fun main() {
                Impl.pub = "external"
                println(Impl.getPub())
            }
            """,
            expectedStdout: "external\n",
            context: "external write to a paired actual class property"
        )
    }

    @Test
    func anonymousObjectInitializerCanWritePairedActualClassProperties() throws {
        try assertPairedActualFieldProgram(
            mainBody: """
            private val Impl: B = object : B() { init { pub = "init" } }

            fun main() {
                println(Impl.getPub())
            }
            """,
            expectedStdout: "init\n",
            context: "anonymous object init block writes a paired actual class property"
        )
    }
}

private func assertPairedActualFieldProgram(
    mainBody: String,
    expectedStdout: String,
    context: String
) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sources = [
        "package x\nexpect abstract class B",
        """
        package x
        actual abstract class B {
            var pub: String = "?"
            val fixed: String = "fx"
            fun setPub(v: String) { pub = v }
            fun getPub(): String = pub
        }
        """,
        "package x\n\(mainBody)",
    ]

    try withTemporaryFiles(contents: sources) { inputs in
        let output = directory.appendingPathComponent("expect-actual-member-storage").path
        let options = CompilerOptions(
            moduleName: "ExpectActualClassMemberStorage",
            inputs: inputs,
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: 0)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )
        try assertCompilationSucceeded(
            makeTestDriver().runForTesting(options: options),
            context: context
        )
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
        #expect(result.stdout == expectedStdout)
        #expect(result.stderr.isEmpty)
    }
}
#endif
