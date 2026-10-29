@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: ["source", "artifact", "producer"], [0, 2])
    func testSingletonBoundClassLiteralThroughAny(mode: String, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = mode == "source" ? nil : try Self.buildStdlibArtifact()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let expectedIdentity = """
        Token
        reflectionsingleton.Token
        true
        true
        true
        Token
        reflectionsingleton.Token
        true
        DirectFirst
        reflectionsingleton.DirectFirst
        Hidden
        reflectionsingleton.Hidden
        true
        Nested
        reflectionsingleton.Holder.Nested
        true
        Named
        reflectionsingleton.Holder.Named
        true
        Ordinary
        reflectionsingleton.Ordinary
        true
        true
        true
        false
        """ + "\n"

        func compile(_ source: String, name: String, emit: EmitMode, imports: [String] = []) throws -> String {
            let input = directory.appendingPathComponent(name + ".kt").path
            let output = directory.appendingPathComponent(name).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: name, inputs: [input], outputPath: output,
                emit: emit, searchPaths: imports, target: defaultTargetTriple(), optLevel: level,
                includeStdlib: mode == "source", stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: name)
            if emit == .library {
                // The consumer must work after the producer source has been retired.
                try FileManager.default.removeItem(atPath: input)
                return output + ".kklib"
            }
            return output
        }

        for (index, fixture) in [
            ("object_bound_class_literal_any.kt", "Token\n"),
            ("object_bound_class_literal_identity.kt", expectedIdentity),
        ].enumerated() {
            // Collection must preserve the singleton and the first dynamic classifier.
            var fixtureSource = try diffCaseSource(fixture.0, file: #filePath)
            var expected = fixture.1
            if mode == "producer", index == 1 {
                // Private singleton library startup is tracked separately in KUU-2163.
                // Keep its strict checks in both monolithic compilation modes.
                let start = try #require(fixtureSource.range(of: "    val hidden = hiddenClassifier()"))
                let end = try #require(fixtureSource.range(of: "    val nested = classifier"))
                fixtureSource.removeSubrange(start.lowerBound..<end.lowerBound)
                expected = expected.replacingOccurrences(of: "Hidden\nreflectionsingleton.Hidden\ntrue\n", with: "")
            }
            let source = index == 1 ? fixtureSource.replacingOccurrences(
                of: "val dynamic = classifier(Token)",
                with: "val dynamic = classifier(Token)\nkotlin.native.runtime.GC.collect()"
            ) : fixtureSource
            let optIn = index == 1 ? "@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)\n" : ""
            let mainRange = try #require(source.range(of: "fun main()"))
            let executable: String
            if mode == "producer" {
                let library = try compile(String(source[..<mainRange.lowerBound]), name: "SingletonProducer\(index)", emit: .library)
                let imports = index == 1 ? "import reflectionsingleton.*\n" : ""
                executable = try compile(optIn + imports + String(source[mainRange.lowerBound...]), name: "SingletonConsumer\(index)", emit: .executable, imports: [library])
            } else {
                executable = try compile(optIn + source, name: "SingletonMonolithic\(index)", emit: .executable)
            }
            // Each run starts without any KClass cache or prior literal evaluation.
            for _ in 0..<2 {
                let result = try CommandRunner.run(executable: executable, arguments: [])
                #expect(result.exitCode == 0, "\(mode) O\(optimization): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(fixture.0), \(mode) O\(optimization)")
            }
        }
    }
}
