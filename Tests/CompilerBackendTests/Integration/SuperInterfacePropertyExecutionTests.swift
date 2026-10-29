import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct SuperInterfacePropertyExecutionTests {
    private func originalSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent(
                "Tests/CompilerBackendTests/Fixtures/KUU-2195/unqualifiedSuperWithDeeperHierarchies.kt"
            ),
            encoding: .utf8
        )
    }

    private func minimalSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent(
                "Tests/CompilerBackendTests/Fixtures/KUU-2195/super_interface_property_minimal.kt"
            ),
            encoding: .utf8
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func originalAndMinimalCasesRunWithSourceAndLibraryStdlib(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = library ? try testStdlibArtifactPath() : nil
        let source = try originalSource() + "\n" + minimalSource() + "\n" + """
        interface DeepFunction {
            fun label(): String = "FUNCTION"
        }
        class Controls : Deep, DeepFunction {
            fun readSuperProperty(): String = super.label
            fun callSuperFunction(): String = super.label()
            fun readThisProperty(): String = this.label
            fun callThisFunction(): String = this.label()
        }
        class Overrides : Deep, DeepFunction {
            override val label: String get() = "THIS"
            override fun label(): String = "THIS-FUNCTION"
            fun readSuperProperty(): String = super.label
            fun callSuperFunction(): String = super.label()
            fun readThisProperty(): String = this.label
            fun callThisFunction(): String = this.label()
        }
        fun main() {
            println(box())
            println(probe())
            println(Controls().readSuperProperty())
            println(Controls().callSuperFunction())
            println(Controls().readThisProperty())
            println(Controls().callThisFunction())
            println(Overrides().readSuperProperty())
            println(Overrides().callSuperFunction())
            println(Overrides().readThisProperty())
            println(Overrides().callThisFunction())
        }
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("KUU2195.kt")
        let executable = directory.appendingPathComponent("KUU2195")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "KUU2195SuperInterfaceProperty",
            inputs: [input.path],
            outputPath: executable.path,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: level,
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 30)
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(
            result.stdout == "OK\nOK\nOK\nFUNCTION\nOK\nFUNCTION\nOK\nFUNCTION\nTHIS\nTHIS-FUNCTION\n",
            "Unexpected output: \(result.stdout)"
        )
    }
}
