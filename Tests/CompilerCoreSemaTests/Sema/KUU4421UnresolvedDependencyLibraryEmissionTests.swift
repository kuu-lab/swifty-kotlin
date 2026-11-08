#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// A single source file with unresolved kmath dependencies must report Sema
/// diagnostics instead of trapping while compiling a library.
@Suite
struct KUU4421UnresolvedDependencyLibraryEmissionTests {
    @Test
    func reportsUnresolvedDependenciesWithoutTrappingDuringLibraryEmit() throws {
        TestStdlibCache.shared.prepare()
        let stdlibPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/KUU-4421/XYColumnarData.kt")
        let source = try String(contentsOf: fixture, encoding: .utf8)

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "XYColumnarData",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .library,
                target: defaultTargetTriple(),
                includeStdlib: false,
                stdlibLibraryPath: stdlibPath,
                allowDefaultStdlibLibrary: false
            )
            let result = CompilerDriver().runForTesting(options: options)

            #expect(result.exitCode == 1)
            #expect(result.diagnostics.contains { $0.severity == .error })
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" })
        }
    }
}
#endif
