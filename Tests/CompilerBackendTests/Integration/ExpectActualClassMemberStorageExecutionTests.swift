#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualClassMemberStorageExecutionTests {
    @Test
    func anonymousSubclassStoresActualClassProperties() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sources = [
            "package x\nexpect abstract class B",
            "package x\nactual abstract class B { internal val label: String = \"actual\"; internal var id: String = \"?\" }",
            """
            package x
            private val Impl: B = object : B() { init { id = "one" } }
            fun main() {
                Impl.id = Impl.id
                Impl.id = Impl.label
            }
            """,
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
                includeStdlib: false,
                stdlibLibraryPath: nil,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "anonymous subclass of paired expect/actual class"
            )
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
