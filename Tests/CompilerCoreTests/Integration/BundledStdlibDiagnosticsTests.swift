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
                return !isUserSourceRange(range, in: ctx)
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

    @Test
    func testStdlibSuppressionsDoNotHideUserWarnings() throws {
        let source = """
        import kotlinx.coroutines.test.StandardTestDispatcher

        fun unchecked(value: Any): List<String> = value as List<String>
        fun experimental() { StandardTestDispatcher() }
        fun unreachable(): Int {
            return 1
            return 2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics)")
            let userWarnings = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return diagnostic.severity == .warning && isUserSourceRange(range, in: ctx)
            }
            #expect(userWarnings.map(\.code).sorted() == [
                "KSWIFTK-SEMA-0096",
                "KSWIFTK-SEMA-OPT-IN",
                "KSWIFTK-SEMA-UNCHECKED-CAST"
            ])
            let bundledDiagnostics = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return !isUserSourceRange(range, in: ctx)
            }
            #expect(bundledDiagnostics.isEmpty, "Unexpected stdlib diagnostics: \(bundledDiagnostics)")
        }
    }
}
#endif
