@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Executes bodies deserialized from a real Kotlin/Native `.klib`: source
/// code calls `demo.add` (primitive intrinsic inside a serialized body) and
/// `Greeter.greet()` (ctor field init + property getter + string concat).
@Suite
struct KlibBodyExecutionTests {
    private static var fixtureDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures")
            .path
    }

    @Test
    func executesImportedKlibBodies() throws {
        let fixtureKlib = Self.fixtureDirectory + "/demo.klib"
        guard FileManager.default.fileExists(atPath: fixtureKlib) else { return }

        let fm = FileManager.default
        let sourcePath = fm.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kt").path
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer {
            try? fm.removeItem(atPath: sourcePath)
            try? fm.removeItem(atPath: outputBase)
        }
        try """
        import demo.add
        import demo.Greeter

        fun main() {
            println(add(3, 4))
            val g = Greeter("Bob")
            println(g.greet())
        }
        """.write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KlibBodyExec",
            inputs: [sourcePath],
            outputPath: outputBase,
            emit: .executable,
            searchPaths: [Self.fixtureDirectory],
            target: defaultTargetTriple()
        )
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result, context: "klib body compilation")

        let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalized = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        #expect(normalized == "7\nHello, Bob\n")
    }
}
