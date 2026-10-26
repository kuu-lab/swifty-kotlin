@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct UncheckedCastDiagnosticTests {
    @Test
    func bundledSuppressionDoesNotHideUserUncheckedCastWarnings() throws {
        let context = makeContextFromSource("""
        fun cast(value: Any): List<String> = value as List<String>
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

        let warnings = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-UNCHECKED-CAST"
        }
        let bundledWarnings = warnings.filter {
            $0.primaryRange.map { context.sourceManager.origin(of: $0.start.file)?.isBundledStdlib == true } == true
        }
        let userWarnings = warnings.filter {
            $0.primaryRange.map { context.sourceManager.origin(of: $0.start.file) == .user } == true
        }
        #expect(bundledWarnings.isEmpty, "\(bundledWarnings)")
        #expect(userWarnings.count == 1, "\(userWarnings)")
        #expect(userWarnings.allSatisfy { $0.severity == .warning })
    }

    @Test
    func nullableNothingCastsDoNotWarnWhileErasedValueCastsStillWarn() throws {
        let sources = [
            "fun cast(): List<Int>? = null as List<Int>?",
            "fun cast(): List<Int>? = null as? List<Int>?",
            "fun cast(value: Nothing?): List<Int>? = value as List<Int>?",
            "fun cast(): Map<String, Int>? = null as Map<String, Int>?",
            "fun cast(): List<Int> = null as List<Int>",
            "fun cast(value: Any): List<Int> = value as List<Int>",
            "fun cast(value: Any?): List<Int>? = value as List<Int>?",
            "fun cast(value: Any?): List<Int>? = value as? List<Int>?",
            "fun cast(value: Any?): List<*>? = value as List<*>?",
            "fun main() { println((null as List<Int>?).orEmpty()) }",
        ]
        let expectedWarningCounts = [0, 0, 0, 0, 1, 1, 1, 1, 0, 0]
        let packagedSources = sources.enumerated().map { "package sample\($0.offset)\n\($0.element)" }
        try withTemporaryFiles(contents: packagedSources) { paths in
            let context = makeCompilationContext(inputs: paths)
            try runSema(context)
            for (index, path) in paths.enumerated() {
                _ = try #require(context.sourceManager.fileID(forPath: path))
                let diagnostics = diagnosticsForPath(path, in: context)
                #expect(diagnostics.filter { $0.severity == .error }.isEmpty,
                        "Unexpected errors for \(sources[index]): \(diagnostics)")
                let warnings = diagnostics.filter { $0.code == "KSWIFTK-SEMA-UNCHECKED-CAST" }
                #expect(warnings.count == expectedWarningCounts[index],
                        "Unexpected unchecked casts for \(sources[index]): \(warnings)")
                #expect(warnings.allSatisfy { $0.severity == .warning })
            }
        }
    }
}
