@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testDelegatedPropertyInitializersInCompanionAndNamedObject() throws {
        // Source-mode O2 currently fails in unrelated bundled-stdlib codegen (KSWIFTK-BACKEND-1006).
        let configurations: [(useArtifact: Bool, optimization: Int)] = [
            (useArtifact: false, optimization: 0),
            (useArtifact: true, optimization: 0),
            (useArtifact: true, optimization: 2),
        ]
        let upstream = try diffCaseSource(
            "kuu_2276_delegated_property_on_companion.kt",
            file: #filePath
        )
        let initializationOrder = try diffCaseSource(
            "kuu_2276_delegated_property_initialization_order.kt",
            file: #filePath
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for configuration in configurations {
            let artifactPath = configuration.useArtifact ? try Self.buildStdlibArtifact() : nil
            let level = try #require(OptimizationLevel(rawValue: configuration.optimization))
            for (name, source) in [
                ("KUU2276Upstream", upstream),
                ("KUU2276InitializationOrder", initializationOrder),
            ] {
                let input = directory.appendingPathComponent(name + ".kt").path
                let output = directory.appendingPathComponent(name).path
                try source.write(toFile: input, atomically: true, encoding: .utf8)
                let options = CompilerOptions(
                    moduleName: name,
                    inputs: [input],
                    outputPath: output,
                    emit: .executable,
                    target: defaultTargetTriple(),
                    optLevel: level,
                    includeStdlib: !configuration.useArtifact,
                    stdlibLibraryPath: artifactPath,
                    allowDefaultStdlibLibrary: false
                )
                try assertCompilationSucceeded(
                    makeTestDriver().runForTesting(options: options),
                    context: "\(name), \(configuration.useArtifact ? "fresh .kklib" : "source"), O\(configuration.optimization)"
                )

                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(name), O\(configuration.optimization): \(result.stderr)")
                #expect(result.stdout == "OK", "\(name), O\(configuration.optimization)")
            }
        }
    }
}
