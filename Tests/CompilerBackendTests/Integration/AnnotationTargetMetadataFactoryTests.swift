import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct AnnotationTargetMetadataFactoryTests {
    @Test(arguments: [false, true], [0, 2])
    func factoriesResolveEnumDependencies(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let matrix = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/annotation_target_metadata_factory.kt"
        ), encoding: .utf8)
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        let cases = [
            ("minimal", """
            @Target(AnnotationTarget.EXPRESSION)
            @Retention(AnnotationRetention.SOURCE)
            annotation class Tag
            fun main() {}
            """, ""),
            ("matrix", matrix, "target:single:multiple:source:binary:runtime\nretention:vararg:source:binary:runtime\n"),
            ("control", "fun main() {}", ""),
        ]
        for (name, source, expected) in cases {
            let input = directory.appendingPathComponent(name + ".kt").path
            let output = directory.appendingPathComponent(name).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "AnnotationTargetMetadataFactory", inputs: [input], outputPath: output,
                emit: .executable, target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
            )))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(name): \(result.stderr)")
            #expect(result.stdout == expected, "\(name)")
        }
    }
}
