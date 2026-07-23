#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibDiagnosticsTests {
    /// Bundled stdlib sources must not produce any diagnostics, including warnings.
    /// A minimal user file is required because LoadSourcesPhase rejects empty inputs.
    @Test
    func testBundledStdlibEmitsZeroDiagnostics() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let bundledDiagnostics = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            }

            let bundledErrors = bundledDiagnostics.filter { $0.severity == .error }
            let bundledWarnings = bundledDiagnostics.filter { $0.severity == .warning }
            let bundledNotes = bundledDiagnostics.filter { $0.severity == .note }
            let bundledInfo = bundledDiagnostics.filter { $0.severity == .info }

            #expect(
                bundledErrors.isEmpty,
                "Bundled stdlib produced errors: \(bundledErrors)"
            )
            #expect(
                bundledWarnings.isEmpty,
                "Bundled stdlib produced warnings: \(bundledWarnings)"
            )
            #expect(
                bundledNotes.isEmpty,
                "Bundled stdlib produced notes: \(bundledNotes)"
            )
            #expect(
                bundledInfo.isEmpty,
                "Bundled stdlib produced info diagnostics: \(bundledInfo)"
            )
        }
    }
}
#endif
