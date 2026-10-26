#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

// KUU-3453: missing imported/platform supertypes must not make valid `is` checks impossible.
@Suite
struct ImpossibleIsCheckPlatformCompatibilityTests {
    @Test(arguments: [false, true])
    func platformTypeChecksAreAcceptedAndLocalImpossibleCheckRemainsDiagnosed(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
            interface Marker
            fun check() {
                val n: Number = 5
                n is Double
                "x" is java.io.Serializable
                StringBuilder() is java.lang.Appendable
                val x: Any = "a"
                x !is Int
            }
            fun unrelated(value: String) = value is Marker
            """

        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)

            let impossibleChecks = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0415" }
            let checkLines = impossibleChecks.compactMap { diagnostic in
                diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
            }
            let errorLines: [Int] = impossibleChecks.compactMap { diagnostic -> Int? in
                guard diagnostic.severity == .error, let range = diagnostic.primaryRange else { return nil }
                return ctx.sourceManager.lineColumn(of: range.start).line
            }

            #expect(!errorLines.contains(4), "A Number value must not be rejected as incompatible with Double: \(impossibleChecks)")
            #expect(!checkLines.contains(5), "String implements java.io.Serializable on the JVM: \(impossibleChecks)")
            #expect(!checkLines.contains(6), "StringBuilder implements java.lang.Appendable on the JVM: \(impossibleChecks)")
            #expect(!checkLines.contains(8), "A negated is check must not be reported as always false: \(impossibleChecks)")
            #expect(checkLines == [10], "Only the unrelated local-interface check should be diagnosed: \(impossibleChecks)")
            #expect(errorLines == [10], "Only the unrelated local-interface check should be diagnosed: \(impossibleChecks)")
        }
    }
}
#endif
