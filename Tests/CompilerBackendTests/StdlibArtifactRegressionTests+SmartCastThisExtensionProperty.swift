@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2451: a smart-cast dispatch `this` can provide the receiver for a
    /// top-level extension property, both in source and fresh-artifact builds.
    @Test(arguments: [true, false], [0, 2])
    func testSmartCastThisResolvesTopLevelExtensionProperty(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = """
        open class KFoo {
            fun foo(): String {
                if (this is KFooQux) return qux
                return "FAIL"
            }
        }
        class KFooQux : KFoo()
        val KFooQux.qux: String get() = "OK"
        fun box(): String = KFooQux().foo()

        open class Base {
            fun read(): String {
                if (this is Child) return marker
                return "FAIL"
            }
        }
        class Child : Base()
        val Child.marker: String get() = "OK"

        fun Base.explicitRead(): String {
            if (this is Child) return this.marker
            return "FAIL"
        }
        fun concreteRead(value: Child): String = value.marker

        fun main() {
            println(box())
            println(Child().read())
            println(Child().explicitRead())
            println(concreteRead(Child()))
        }
        """
        let input = directory.appendingPathComponent("kuu2451.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("kuu2451").path
        let options = CompilerOptions(
            moduleName: "KUU2451SmartCastThisExtensionProperty",
            inputs: [input.path],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "OK\nOK\nOK\nOK\n")
    }
}
