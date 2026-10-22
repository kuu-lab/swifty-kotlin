@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testGenericLazyDelegateUsesExplicitInitializerFunction() throws {
        let source = try diffCaseSource(
            "kuu_2466_generic_lazy_initializer.kt",
            file: #filePath
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = try Self.buildStdlibArtifact()
        let input = directory.appendingPathComponent("KUU2466.kt").path
        let output = directory.appendingPathComponent("KUU2466").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "KUU2466",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: 0)),
            includeStdlib: false,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(
            makeTestDriver().runForTesting(options: options),
            context: "KUU-2466, fresh .kklib, O0"
        )

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "KUU-2466: \(result.stderr)")
        #expect(result.stdout == "K")
    }

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

    /// KUU-2943: a delegated `var` declared with a visibility-only setter
    /// clause (`private set`/`protected set`) still routes writes through the
    /// synthesized setValue-forwarding accessor — previously the bare
    /// `setter.body == .unit` check downgraded them to direct field stores on
    /// a dead slot, silently losing the write (JetBrains kt9712 shape).
    @Test
    func testDelegatedVarWithRestrictedSetterVisibility() throws {
        // Source-mode O2 currently fails in unrelated bundled-stdlib codegen (KSWIFTK-BACKEND-1006).
        let configurations: [(useArtifact: Bool, optimization: Int)] = [
            (useArtifact: false, optimization: 0),
            (useArtifact: true, optimization: 0),
            (useArtifact: true, optimization: 2),
        ]
        let source = try diffCaseSource(
            "kuu_2943_delegated_var_restricted_set.kt",
            file: #filePath
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for configuration in configurations {
            let artifactPath = configuration.useArtifact ? try Self.buildStdlibArtifact() : nil
            let level = try #require(OptimizationLevel(rawValue: configuration.optimization))
            let name = "KUU2943"
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
            #expect(
                result.stdout == "K\nthisK\npv\npv!\ntv\n",
                "\(name), O\(configuration.optimization)"
            )
        }
    }
}
