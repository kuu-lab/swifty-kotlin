#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testKUU2462UnsignedUpperBoundLiteralsRun(useStdlibLibrary: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let minimumPath = root.appendingPathComponent(
            "Scripts/diff_cases/kuu_2462_generic_unsigned_upper_bound.kt"
        )
        let publicPath = root.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/KUU2462/smartCastOnBothEndsGeneric.kt"
        )
        let minimum = try Data(contentsOf: minimumPath)
        let publicOriginal = try Data(contentsOf: publicPath)
        try #require(FileFingerprint.sha256Hex(minimum)
                     == "91bd8253f13b8b93a4d5381922365f54896a17571566318075bd9dc72db412d0")
        try #require(FileFingerprint.sha256Hex(publicOriginal)
                     == "3dcdc1d17365a50b3540337a7d273a2385ce87ecfc2f3c1ea997b8d469b37295")

        if useStdlibLibrary { TestStdlibCache.shared.prepare() }
        let library = useStdlibLibrary
            ? try #require(CompilerOptions.defaultStdlibLibraryPath,
                           "Library mode must use the published stdlib artifact") : nil
        // The original box test exercises generic range membership, which has
        // a separate source-stdlib runtime issue. Keep its executable check on
        // the artifact lane while covering the minimized inference case in both.
        var programs: [(name: String, sources: [Data])] = [("Minimum", [minimum])]
        if useStdlibLibrary {
            programs.append(
                ("PublicOriginal", [publicOriginal, Data("fun main() { println(box()) }\n".utf8)])
            )
        }

        for program in programs {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            var inputPaths: [String] = []
            for (index, source) in program.sources.enumerated() {
                let input = directory.appendingPathComponent("source-\(index).kt")
                try source.write(to: input)
                inputPaths.append(input.path)
            }
            let executable = directory.appendingPathComponent(program.name)
            let options = CompilerOptions(
                moduleName: "KUU2462\(program.name)",
                inputs: inputPaths,
                outputPath: executable.path,
                emit: .executable,
                target: TargetTriple.hostDefault(),
                optLevel: .O0,
                stdlibLibraryPath: library,
                allowDefaultStdlibLibrary: false
            )
            try #require(options.stdlibLibraryPath == library)
            #expect(options.includeStdlib == !useStdlibLibrary)
            let result = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(result)
            try #require(FileManager.default.isExecutableFile(atPath: executable.path))
            let execution = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
            #expect(execution.exitCode == 0)
            #expect(Data(execution.stdout.utf8) == Data("OK\n".utf8))
        }
    }
}
#endif
