@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testIdentityHashMapAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repoRoot.appendingPathComponent("Scripts/diff_cases/identity_hash_map")
        let expected = try String(contentsOf: fixture.appendingPathExtension("expected"), encoding: .utf8)
        let artifact = try Self.buildStdlibArtifact()
        for (surface, library) in [("source", nil), ("artifact", artifact)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: fixture.appendingPathExtension("kt").path,
                    moduleName: "KUU2060IdentityHashMap",
                    outputPath: output,
                    optLevel: optimization,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(surface), \(optimization): \(result.stderr)")
                #expect(result.stdout == expected, "\(surface), \(optimization)")
            }
        }
    }

    @Test
    func testIdentityHashMapTypeAndImportBoundaries() throws {
        let artifact = try Self.buildStdlibArtifact()
        let fixtures: [(String, Bool)] = [
            ("import java.util.IdentityHashMap\nfun identityMap(): MutableMap<String, Int> = IdentityHashMap<String, Int>()\nfun main() {}", true),
            ("fun valueMap(): MutableMap<String, Int> = HashMap<String, Int>()\nfun main() {}", true),
            ("import java.util.*\nfun probe(): MutableMap<String?, Int?> = IdentityHashMap<String?, Int?>()", true),
            ("fun probe(): MutableMap<String, Int> = java.util.IdentityHashMap<String, Int>()", true),
            ("import java.util.IdentityHashMap\nfun identityMap(): MutableMap<String, Int> = IdentityHashMap<Int, String>()\nfun main() {}", false),
            ("import java.util.IdentityHashMap\nfun probe(): MutableMap<String, Int> = IdentityHashMap<String?, Int?>()", false),
            ("import java.util.IdentityHashMap\nfun probe() { val map: MutableMap<String, Int> = IdentityHashMap<String, Int>(); map.put(null, 1) }", false),
            ("fun probe() = IdentityHashMap<String, Int>()", false),
        ]
        for library in [nil, artifact] {
            for (source, accepted) in fixtures {
                try withTemporaryFile(contents: source) { path in
                    let context = makeCompilationContext(
                        inputs: [path],
                        includeStdlib: library == nil,
                        stdlibLibraryPath: library,
                        allowDefaultStdlibLibrary: false
                    )
                    try runSema(context)
                    #expect(context.diagnostics.hasError == !accepted, "\(source): \(context.diagnostics.diagnostics)")
                    if accepted && source.contains("java.util") {
                        let sema = try #require(context.sema)
                        let symbol = try #require(sema.symbols.lookup(fqName: ["java", "util", "IdentityHashMap"].map(context.interner.intern)))
                        #expect(sema.symbols.isSourceBackedSymbol(symbol))
                    }
                }
            }
        }
    }
}
